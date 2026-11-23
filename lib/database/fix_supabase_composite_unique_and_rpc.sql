-- ============================================================================
-- FIX: SALES INVOICE ATOMIC RPC CONSTRAINT RESOLUTION
-- Run this in Supabase Dashboard -> SQL Editor
-- Resolves PostgreSQL Error 42P10 by matching composite unique constraint
-- ============================================================================

-- Step 1: Ensure composite unique constraints exist on transaction tables
CREATE UNIQUE INDEX IF NOT EXISTS uq_sales_invoices_entry_terminal
ON public.sales_invoices (entry_no, terminal_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_purchase_entries_entry_terminal
ON public.purchase_entries (entry_no, terminal_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_sales_return_entry_terminal
ON public.sales_return_invoices (entry_no, terminal_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_purchase_return_entry_terminal
ON public.purchase_return_entries (entry_no, terminal_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_stock_adj_entry_terminal
ON public.stock_adjustments (entry_no, terminal_id);

-- Step 2: Update fn_process_sale_atomic to use (entry_no, terminal_id) for ON CONFLICT
CREATE OR REPLACE FUNCTION public.fn_process_sale_atomic(
    p_invoice JSONB,
    p_items JSONB,
    p_idempotency_key TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_entry_no TEXT;
    v_branch_id TEXT;
    v_terminal_id TEXT;
    v_user_id TEXT;
    v_cached_response JSONB;
    v_item JSONB;
    v_prod_id TEXT;
    v_batch_no TEXT;
    v_req_qty INT;
    v_f_qty INT;
    v_total_deduct INT;
    v_avail_qty INT;
    v_batch_rec RECORD;
    v_units_remaining INT;
    v_deduct_this_batch INT;
    v_closing_stock INT;
    v_response JSONB;
    v_old_item RECORD;
    v_reversal_qty INT;
    v_is_deleted INT;
BEGIN
    -- 1. Idempotency Check
    IF p_idempotency_key IS NOT NULL AND p_idempotency_key <> '' THEN
        SELECT response_payload INTO v_cached_response
        FROM public.idempotency_keys
        WHERE idempotency_key = p_idempotency_key;

        IF FOUND THEN
            RETURN v_cached_response;
        END IF;
    END IF;

    -- 2. Input Validation
    v_entry_no := TRIM(COALESCE(p_invoice->>'entry_no', p_invoice->>'invoice_no', ''));
    v_branch_id := TRIM(COALESCE(p_invoice->>'branch_id', 'MAIN_STORE'));
    v_terminal_id := TRIM(COALESCE(p_invoice->>'terminal_id', 'POS-01'));
    v_user_id := TRIM(COALESCE(p_invoice->>'done_by', p_invoice->>'agent', 'Cashier'));
    v_is_deleted := COALESCE(NULLIF(p_invoice->>'is_deleted', '')::INT, 0);

    IF v_entry_no = '' OR v_branch_id = '' OR v_terminal_id = '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'reason', 'INVALID_INPUT',
            'message', 'Missing required entry_no, branch_id, or terminal_id'
        );
    END IF;

    -- 2b. Invoice Edit / Void Restoral: If invoice already exists, reverse prior stock deductions
    IF EXISTS (SELECT 1 FROM public.sales_invoices WHERE entry_no = v_entry_no AND terminal_id = v_terminal_id AND COALESCE(is_deleted, 0) = 0) THEN
        FOR v_old_item IN
            SELECT product_id, batch_number, quantity, f_qty
            FROM public.sales_items
            WHERE invoice_no = v_entry_no AND terminal_id = v_terminal_id
        LOOP
            v_reversal_qty := COALESCE(v_old_item.quantity, 0) + COALESCE(v_old_item.f_qty, 0);
            IF v_reversal_qty > 0 THEN
                UPDATE public.stock_batches
                SET current_quantity = current_quantity + v_reversal_qty,
                    updated_at = NOW()
                WHERE branch_id = v_branch_id
                  AND product_id = v_old_item.product_id
                  AND LOWER(TRIM(batch_number)) = LOWER(TRIM(v_old_item.batch_number));

                INSERT INTO public.stock_ledger (
                    idempotency_key, operation_type, reference_no, product_id, batch_number,
                    quantity_delta, qty_in, qty_out, closing_balance,
                    branch_id, terminal_id, user_id, created_at
                ) VALUES (
                    COALESCE(p_idempotency_key, '') || '_REV',
                    CASE WHEN v_is_deleted = 1 THEN 'SALE_VOID_REVERSAL' ELSE 'SALE_EDIT_REVERSAL' END,
                    v_entry_no, v_old_item.product_id, v_old_item.batch_number,
                    v_reversal_qty, v_reversal_qty, 0,
                    COALESCE((SELECT current_quantity FROM public.stock_batches WHERE branch_id = v_branch_id AND product_id = v_old_item.product_id AND LOWER(TRIM(batch_number)) = LOWER(TRIM(v_old_item.batch_number)) LIMIT 1), 0),
                    v_branch_id, v_terminal_id, v_user_id, NOW()
                );
            END IF;
        END LOOP;
    END IF;

    -- If this is a void/cancellation operation, update status and return immediately
    IF v_is_deleted = 1 THEN
        UPDATE public.sales_invoices
        SET is_deleted = 1, updated_at = NOW()
        WHERE entry_no = v_entry_no AND terminal_id = v_terminal_id;

        DELETE FROM public.sales_items WHERE invoice_no = v_entry_no AND terminal_id = v_terminal_id;

        v_response := jsonb_build_object(
            'success', true,
            'entry_no', v_entry_no,
            'is_deleted', 1,
            'message', 'Invoice successfully voided and stock restored.'
        );

        IF p_idempotency_key IS NOT NULL AND p_idempotency_key <> '' THEN
            INSERT INTO public.idempotency_keys (
                idempotency_key, branch_id, terminal_id, operation_type, reference_no, response_payload, created_at
            ) VALUES (
                p_idempotency_key, v_branch_id, v_terminal_id, 'SALE_VOID', v_entry_no, v_response, NOW()
            )
            ON CONFLICT (idempotency_key) DO NOTHING;
        END IF;

        RETURN v_response;
    END IF;

    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'reason', 'EMPTY_ITEMS',
            'message', 'Rejected: p_items array cannot be empty or null'
        );
    END IF;

    -- 3. Pre-flight Validation with FOR UPDATE Row Locks to Prevent Overselling
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_prod_id := TRIM(COALESCE(v_item->>'product_id', ''));
        v_batch_no := TRIM(COALESCE(v_item->>'batch_number', v_item->>'batch', ''));
        v_req_qty := COALESCE(NULLIF(v_item->>'quantity', '')::INT, NULLIF(v_item->>'qty', '')::INT, 1);
        v_f_qty := COALESCE(NULLIF(v_item->>'f_qty', '')::INT, 0);
        v_total_deduct := v_req_qty + v_f_qty;

        IF v_total_deduct > 0 THEN
            WITH locked_batches AS (
                SELECT current_quantity
                FROM public.stock_batches
                WHERE branch_id = v_branch_id
                  AND product_id = v_prod_id
                  AND LOWER(TRIM(batch_number)) = LOWER(v_batch_no)
                FOR UPDATE
            )
            SELECT COALESCE(SUM(current_quantity), 0) INTO v_avail_qty
            FROM locked_batches;

            IF v_avail_qty < v_total_deduct THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'reason', 'INSUFFICIENT_STOCK',
                    'message', 'Insufficient stock for product ' || v_prod_id || ' batch ' || v_batch_no || ' (Available: ' || v_avail_qty || ', Required: ' || v_total_deduct || ')',
                    'product_id', v_prod_id,
                    'batch_number', v_batch_no,
                    'available_stock', v_avail_qty,
                    'requested_qty', v_total_deduct
                );
            END IF;
        END IF;
    END LOOP;

    -- 4. Apply Deductions & Record Auditable Stock Ledger Movements
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_prod_id := TRIM(COALESCE(v_item->>'product_id', ''));
        v_batch_no := TRIM(COALESCE(v_item->>'batch_number', v_item->>'batch', ''));
        v_req_qty := COALESCE(NULLIF(v_item->>'quantity', '')::INT, NULLIF(v_item->>'qty', '')::INT, 1);
        v_f_qty := COALESCE(NULLIF(v_item->>'f_qty', '')::INT, 0);
        v_total_deduct := v_req_qty + v_f_qty;

        v_units_remaining := v_total_deduct;

        FOR v_batch_rec IN
            SELECT id, current_quantity, purchase_rate, mrp, selling_rate
            FROM public.stock_batches
            WHERE branch_id = v_branch_id
              AND product_id = v_prod_id
              AND LOWER(TRIM(batch_number)) = LOWER(v_batch_no)
              AND current_quantity > 0
            ORDER BY expiry_date ASC, id ASC
            FOR UPDATE
        LOOP
            IF v_units_remaining <= 0 THEN
                EXIT;
            END IF;

            v_deduct_this_batch := LEAST(v_units_remaining, v_batch_rec.current_quantity);

            UPDATE public.stock_batches
            SET current_quantity = current_quantity - v_deduct_this_batch,
                updated_at = NOW()
            WHERE id = v_batch_rec.id
            RETURNING current_quantity INTO v_closing_stock;

            -- Record immutable ledger entry
            INSERT INTO public.stock_ledger (
                idempotency_key, operation_type, reference_no, product_id, batch_number,
                quantity_delta, qty_in, qty_out, closing_balance,
                purchase_rate, mrp, selling_rate,
                branch_id, terminal_id, user_id, created_at
            ) VALUES (
                p_idempotency_key, 'SALE', v_entry_no, v_prod_id, v_batch_no,
                -v_deduct_this_batch, 0, v_deduct_this_batch, v_closing_stock,
                COALESCE(v_batch_rec.purchase_rate, 0.0), COALESCE(v_batch_rec.mrp, 0.0), COALESCE(v_batch_rec.selling_rate, 0.0),
                v_branch_id, v_terminal_id, v_user_id, NOW()
            );

            v_units_remaining := v_units_remaining - v_deduct_this_batch;
        END LOOP;
    END LOOP;

    -- 5. Upsert Sales Invoice Header (ON CONFLICT matches composite constraint uq_sales_invoices_entry_terminal)
    INSERT INTO public.sales_invoices (
        entry_no, invoice_no, financial_year, date, customer_name, patient,
        customer_phone, mobile, done_by, terminal_id,
        subtotal, sub_total, discount_amount, discount,
        tax_amount, net_amount, grand_total, total_amount,
        payment_mode, is_deleted, is_paid, agent,
        branch_id, updated_at
    ) VALUES (
        v_entry_no,
        COALESCE(p_invoice->>'invoice_no', v_entry_no),
        COALESCE(p_invoice->>'financial_year', ''),
        COALESCE(p_invoice->>'date', NOW()::TEXT),
        COALESCE(p_invoice->>'customer_name', p_invoice->>'patient', ''),
        COALESCE(p_invoice->>'patient', p_invoice->>'customer_name', ''),
        COALESCE(p_invoice->>'customer_phone', p_invoice->>'mobile', ''),
        COALESCE(p_invoice->>'mobile', p_invoice->>'customer_phone', ''),
        v_user_id,
        v_terminal_id,
        COALESCE(NULLIF(p_invoice->>'subtotal', '')::NUMERIC, NULLIF(p_invoice->>'sub_total', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'sub_total', '')::NUMERIC, NULLIF(p_invoice->>'subtotal', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'discount_amount', '')::NUMERIC, NULLIF(p_invoice->>'discount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'discount', '')::NUMERIC, NULLIF(p_invoice->>'discount_amount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'tax_amount', '')::NUMERIC, NULLIF(p_invoice->>'tax', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'net_amount', '')::NUMERIC, NULLIF(p_invoice->>'grand_total', '')::NUMERIC, NULLIF(p_invoice->>'total_amount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'grand_total', '')::NUMERIC, NULLIF(p_invoice->>'net_amount', '')::NUMERIC, NULLIF(p_invoice->>'total_amount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'total_amount', '')::NUMERIC, NULLIF(p_invoice->>'grand_total', '')::NUMERIC, NULLIF(p_invoice->>'net_amount', '')::NUMERIC, 0.0),
        COALESCE(p_invoice->>'payment_mode', p_invoice->>'customer_acc', 'CASH'),
        COALESCE(NULLIF(p_invoice->>'is_deleted', '')::INT, 0),
        COALESCE(NULLIF(p_invoice->>'is_paid', '')::INT, 1),
        COALESCE(p_invoice->>'agent', 'Admin'),
        v_branch_id,
        NOW()
    )
    ON CONFLICT (entry_no, terminal_id) DO UPDATE SET
        invoice_no = EXCLUDED.invoice_no,
        date = EXCLUDED.date,
        customer_name = EXCLUDED.customer_name,
        patient = EXCLUDED.patient,
        subtotal = EXCLUDED.subtotal,
        discount_amount = EXCLUDED.discount_amount,
        tax_amount = EXCLUDED.tax_amount,
        net_amount = EXCLUDED.net_amount,
        grand_total = EXCLUDED.grand_total,
        is_deleted = EXCLUDED.is_deleted,
        branch_id = EXCLUDED.branch_id,
        updated_at = NOW();

    DELETE FROM public.sales_items WHERE invoice_no = v_entry_no AND terminal_id = v_terminal_id;

    INSERT INTO public.sales_items (
        invoice_no, product_id, product_name, batch_number,
        quantity, qty, mrp, purchase_rate, landing_cost,
        taxable_sp, unit_price, total, total_amount, branch_id,
        terminal_id, updated_at
    )
    SELECT
        v_entry_no,
        COALESCE(item->>'product_id', ''),
        COALESCE(item->>'product_name', ''),
        COALESCE(item->>'batch_number', item->>'batch', ''),
        COALESCE(NULLIF(item->>'quantity', '')::INT, NULLIF(item->>'qty', '')::INT, 1),
        COALESCE(NULLIF(item->>'qty', '')::INT, NULLIF(item->>'quantity', '')::INT, 1),
        COALESCE(NULLIF(item->>'mrp', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(item->>'purchase_rate', '')::NUMERIC, NULLIF(item->>'p_rate', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(item->>'landing_cost', '')::NUMERIC, NULLIF(item->>'l_cost', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(item->>'taxable_sp', '')::NUMERIC, NULLIF(item->>'unit_price', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(item->>'unit_price', '')::NUMERIC, NULLIF(item->>'s_rate', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(item->>'total', '')::NUMERIC, NULLIF(item->>'total_amount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(item->>'total_amount', '')::NUMERIC, NULLIF(item->>'total', '')::NUMERIC, 0.0),
        v_branch_id,
        v_terminal_id,
        NOW()
    FROM jsonb_array_elements(p_items) AS item;

    v_response := jsonb_build_object(
        'success', true,
        'entry_no', v_entry_no,
        'branch_id', v_branch_id,
        'terminal_id', v_terminal_id,
        'idempotency_key', p_idempotency_key
    );

    IF p_idempotency_key IS NOT NULL AND p_idempotency_key <> '' THEN
        INSERT INTO public.idempotency_keys (
            idempotency_key, branch_id, terminal_id, operation_type, reference_no, response_payload, created_at
        ) VALUES (
            p_idempotency_key, v_branch_id, v_terminal_id, 'SALE', v_entry_no, v_response, NOW()
        )
        ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;

    RETURN v_response;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_process_sale_atomic(JSONB, JSONB, TEXT) TO anon, authenticated, service_role;
