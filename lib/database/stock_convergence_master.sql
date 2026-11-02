-- =========================================================================
-- PHARMA PRO ERP - MULTI-TERMINAL STOCK CONVERGENCE & AUTHORITATIVE SERVER ENGINE
-- Migration Version: 2026_11_STOCK_CONVERGENCE_01
-- Safe & Non-Destructive: Preserves all existing pharmacy records, tables, and views.
-- Execute in Supabase Dashboard -> SQL Editor
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1. EXTEND CORE TABLES WITH ENTERPRISE CONVERGENCE COLUMNS & INDEXES
-- -------------------------------------------------------------------------

-- stock_batches
ALTER TABLE public.stock_batches ADD COLUMN IF NOT EXISTS branch_id TEXT DEFAULT 'MAIN_STORE';
ALTER TABLE public.stock_batches ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();
ALTER TABLE public.stock_batches ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'chk_stock_non_negative' AND table_name = 'stock_batches'
    ) THEN
        ALTER TABLE public.stock_batches ADD CONSTRAINT chk_stock_non_negative CHECK (current_quantity >= 0);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_stock_batches_branch_prod_batch
ON public.stock_batches(branch_id, product_id, batch_number);

CREATE INDEX IF NOT EXISTS idx_stock_batches_branch_updated
ON public.stock_batches(branch_id, updated_at DESC);

-- Ensure transaction tables have branch_id & terminal_id
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS branch_id TEXT DEFAULT 'MAIN_STORE';
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

ALTER TABLE public.sales_items ADD COLUMN IF NOT EXISTS branch_id TEXT DEFAULT 'MAIN_STORE';
ALTER TABLE public.sales_items ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';

ALTER TABLE public.purchase_entries ADD COLUMN IF NOT EXISTS branch_id TEXT DEFAULT 'MAIN_STORE';
ALTER TABLE public.purchase_entries ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';
ALTER TABLE public.purchase_entries ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

ALTER TABLE public.purchase_items ADD COLUMN IF NOT EXISTS branch_id TEXT DEFAULT 'MAIN_STORE';
ALTER TABLE public.purchase_items ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';

ALTER TABLE public.sales_return_invoices ADD COLUMN IF NOT EXISTS branch_id TEXT DEFAULT 'MAIN_STORE';
ALTER TABLE public.sales_return_invoices ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';
ALTER TABLE public.sales_return_invoices ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

ALTER TABLE public.sales_return_items ADD COLUMN IF NOT EXISTS branch_id TEXT DEFAULT 'MAIN_STORE';
ALTER TABLE public.sales_return_items ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';

ALTER TABLE public.purchase_return_entries ADD COLUMN IF NOT EXISTS branch_id TEXT DEFAULT 'MAIN_STORE';
ALTER TABLE public.purchase_return_entries ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';
ALTER TABLE public.purchase_return_entries ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

ALTER TABLE public.purchase_return_items ADD COLUMN IF NOT EXISTS branch_id TEXT DEFAULT 'MAIN_STORE';
ALTER TABLE public.purchase_return_items ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';

ALTER TABLE public.stock_adjustments ADD COLUMN IF NOT EXISTS branch_id TEXT DEFAULT 'MAIN_STORE';
ALTER TABLE public.stock_adjustments ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';
ALTER TABLE public.stock_adjustments ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

ALTER TABLE public.stock_adjustment_items ADD COLUMN IF NOT EXISTS branch_id TEXT DEFAULT 'MAIN_STORE';
ALTER TABLE public.stock_adjustment_items ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';

ALTER TABLE public.stock_write_offs ADD COLUMN IF NOT EXISTS branch_id TEXT DEFAULT 'MAIN_STORE';
ALTER TABLE public.stock_write_offs ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';
ALTER TABLE public.stock_write_offs ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- -------------------------------------------------------------------------
-- 2. CREATE IDEMPOTENCY KEYS TABLE
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.idempotency_keys (
    idempotency_key TEXT PRIMARY KEY,
    branch_id TEXT NOT NULL,
    terminal_id TEXT NOT NULL,
    operation_type TEXT NOT NULL,
    reference_no TEXT NOT NULL,
    response_payload JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_idemp_keys_lookup
ON public.idempotency_keys(branch_id, operation_type, reference_no);

CREATE INDEX IF NOT EXISTS idx_idemp_keys_created
ON public.idempotency_keys(created_at);

-- -------------------------------------------------------------------------
-- 3. AUDITABLE STOCK LEDGER TABLE
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.stock_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    idempotency_key TEXT,
    operation_type TEXT NOT NULL, -- SALE, PURCHASE, SALES_RETURN, PURCHASE_RETURN, ADJUSTMENT, WRITE_OFF, SALE_VOID, PURCHASE_VOID
    reference_no TEXT NOT NULL,
    product_id TEXT NOT NULL,
    batch_number TEXT NOT NULL,
    quantity_delta INT NOT NULL, -- Negative for deductions, positive for additions
    qty_in INT DEFAULT 0,
    qty_out INT DEFAULT 0,
    closing_balance INT DEFAULT 0,
    purchase_rate NUMERIC DEFAULT 0.0,
    mrp NUMERIC DEFAULT 0.0,
    selling_rate NUMERIC DEFAULT 0.0,
    branch_id TEXT NOT NULL DEFAULT 'MAIN_STORE',
    terminal_id TEXT NOT NULL DEFAULT 'POS-01',
    user_id TEXT DEFAULT 'Admin',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stock_ledger_batch_hist
ON public.stock_ledger(branch_id, product_id, batch_number, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_stock_ledger_ref
ON public.stock_ledger(branch_id, operation_type, reference_no);

CREATE INDEX IF NOT EXISTS idx_stock_ledger_idemp
ON public.stock_ledger(branch_id, idempotency_key);

-- -------------------------------------------------------------------------
-- 4. ACTIVE COMPUTERS / TERMINAL IDENTITY VERIFICATION TABLE
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.active_computers (
    machine_id TEXT PRIMARY KEY,
    branch_id TEXT NOT NULL DEFAULT 'MAIN_STORE',
    terminal_id TEXT NOT NULL DEFAULT 'POS-01',
    app_version TEXT,
    last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_active_computers_term
ON public.active_computers(branch_id, terminal_id, last_seen_at DESC);

-- -------------------------------------------------------------------------
-- 5. ATOMIC RPC FUNCTION: fn_heartbeat_and_check_terminal
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_heartbeat_and_check_terminal(
    p_branch_id TEXT,
    p_terminal_id TEXT,
    p_machine_id TEXT,
    p_app_version TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_clean_branch TEXT;
    v_clean_term TEXT;
    v_clean_machine TEXT;
    v_conflict_machine TEXT;
    v_conflict_seen TIMESTAMPTZ;
BEGIN
    v_clean_branch := TRIM(COALESCE(p_branch_id, 'MAIN_STORE'));
    v_clean_term := UPPER(TRIM(COALESCE(p_terminal_id, '')));
    v_clean_machine := TRIM(COALESCE(p_machine_id, ''));

    IF v_clean_branch = '' OR v_clean_term = '' OR v_clean_machine = '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Missing branch_id, terminal_id, or machine_id'
        );
    END IF;

    -- Upsert current PC heartbeat
    INSERT INTO public.active_computers (
        machine_id, branch_id, terminal_id, app_version, last_seen_at
    ) VALUES (
        v_clean_machine, v_clean_branch, v_clean_term, p_app_version, NOW()
    )
    ON CONFLICT (machine_id) DO UPDATE SET
        branch_id = EXCLUDED.branch_id,
        terminal_id = EXCLUDED.terminal_id,
        app_version = EXCLUDED.app_version,
        last_seen_at = NOW();

    -- Check for another machine reporting the same terminal_id in this branch within past 5 minutes
    SELECT machine_id, last_seen_at
    INTO v_conflict_machine, v_conflict_seen
    FROM public.active_computers
    WHERE branch_id = v_clean_branch
      AND UPPER(TRIM(terminal_id)) = v_clean_term
      AND machine_id <> v_clean_machine
      AND last_seen_at >= (NOW() - INTERVAL '5 minutes')
    ORDER BY last_seen_at DESC
    LIMIT 1;

    IF FOUND THEN
        RETURN jsonb_build_object(
            'success', true,
            'is_duplicate_terminal', true,
            'conflicting_machine_id', v_conflict_machine,
            'conflicting_last_seen', v_conflict_seen,
            'terminal_id', v_clean_term,
            'branch_id', v_clean_branch,
            'message', 'Duplicate Terminal ID detected: Machine ' || v_conflict_machine || ' is also active as terminal ' || v_clean_term
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'is_duplicate_terminal', false,
        'terminal_id', v_clean_term,
        'branch_id', v_clean_branch
    );
END;
$$;

-- -------------------------------------------------------------------------
-- 6. ATOMIC RPC FUNCTION: fn_process_sale_atomic
-- -------------------------------------------------------------------------
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

    IF v_entry_no = '' OR v_branch_id = '' OR v_terminal_id = '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'reason', 'INVALID_INPUT',
            'message', 'Missing required entry_no, branch_id, or terminal_id'
        );
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
            -- Check total available stock across locked matching batch rows in this branch
            SELECT COALESCE(SUM(current_quantity), 0) INTO v_avail_qty
            FROM public.stock_batches
            WHERE branch_id = v_branch_id
              AND product_id = v_prod_id
              AND LOWER(TRIM(batch_number)) = LOWER(v_batch_no)
            FOR UPDATE;

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

    -- 5. Upsert Sales Invoice Header & Replace Line Items
    INSERT INTO public.sales_invoices (
        entry_no, invoice_no, financial_year, date, customer_acc, customer_name, patient,
        customer_phone, mobile, doctor, doctor_reg_no, done_by, terminal_id, shift_id,
        patient_age, patient_gender, patient_address, gstin_number, place_of_supply,
        subtotal, sub_total, discount_amount, discount, discount_percent, additional_discount,
        other_charge, tax_amount, tax, round_off, net_amount, grand_total, total_amount,
        rcvd_amt, payment_mode, payment_remarks, secondary_acc, secondary_amt,
        is_deleted, is_paid, tax_type, agent, sales_return_amt, order_type,
        branch_id, updated_at
    ) VALUES (
        v_entry_no,
        COALESCE(p_invoice->>'invoice_no', v_entry_no),
        COALESCE(p_invoice->>'financial_year', ''),
        COALESCE(p_invoice->>'date', NOW()::TEXT),
        COALESCE(p_invoice->>'customer_acc', p_invoice->>'payment_mode', 'Cash'),
        COALESCE(p_invoice->>'customer_name', p_invoice->>'patient', ''),
        COALESCE(p_invoice->>'patient', p_invoice->>'customer_name', ''),
        COALESCE(p_invoice->>'customer_phone', p_invoice->>'mobile', ''),
        COALESCE(p_invoice->>'mobile', p_invoice->>'customer_phone', ''),
        COALESCE(p_invoice->>'doctor', ''),
        COALESCE(p_invoice->>'doctor_reg_no', ''),
        v_user_id,
        v_terminal_id,
        COALESCE(p_invoice->>'shift_id', 'SHIFT-01'),
        COALESCE(NULLIF(p_invoice->>'patient_age', '')::INT, 0),
        COALESCE(p_invoice->>'patient_gender', ''),
        COALESCE(p_invoice->>'patient_address', ''),
        COALESCE(p_invoice->>'gstin_number', ''),
        COALESCE(p_invoice->>'place_of_supply', ''),
        COALESCE(NULLIF(p_invoice->>'subtotal', '')::NUMERIC, NULLIF(p_invoice->>'sub_total', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'sub_total', '')::NUMERIC, NULLIF(p_invoice->>'subtotal', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'discount_amount', '')::NUMERIC, NULLIF(p_invoice->>'discount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'discount', '')::NUMERIC, NULLIF(p_invoice->>'discount_amount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'discount_percent', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'additional_discount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'other_charge', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'tax_amount', '')::NUMERIC, NULLIF(p_invoice->>'tax', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'tax', '')::NUMERIC, NULLIF(p_invoice->>'tax_amount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'round_off', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'net_amount', '')::NUMERIC, NULLIF(p_invoice->>'grand_total', '')::NUMERIC, NULLIF(p_invoice->>'total_amount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'grand_total', '')::NUMERIC, NULLIF(p_invoice->>'net_amount', '')::NUMERIC, NULLIF(p_invoice->>'total_amount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'total_amount', '')::NUMERIC, NULLIF(p_invoice->>'grand_total', '')::NUMERIC, NULLIF(p_invoice->>'net_amount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'rcvd_amt', '')::NUMERIC, 0.0),
        COALESCE(p_invoice->>'payment_mode', 'CASH'),
        COALESCE(p_invoice->>'payment_remarks', ''),
        COALESCE(p_invoice->>'secondary_acc', ''),
        COALESCE(NULLIF(p_invoice->>'secondary_amt', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'is_deleted', '')::INT, 0),
        COALESCE(NULLIF(p_invoice->>'is_paid', '')::INT, 1),
        COALESCE(p_invoice->>'tax_type', 'Non Gst'),
        COALESCE(p_invoice->>'agent', 'Admin'),
        COALESCE(NULLIF(p_invoice->>'sales_return_amt', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'order_type', '')::INT, 0),
        v_branch_id,
        NOW()
    )
    ON CONFLICT (entry_no) DO UPDATE SET
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

    DELETE FROM public.sales_items WHERE invoice_no = v_entry_no;

    INSERT INTO public.sales_items (
        invoice_no, product_id, product_name, extra, batch_number, expiry_date,
        quantity, f_qty, hsn_code, schedule, packing, mrp, purchase_rate, landing_cost,
        taxable_sp, unit_price, disc_percent, disc_amt, gst_percent, gst_amt,
        cgst_amt, sgst_amt, igst_amt, total_amount, profit, supplier_name, rack, branch_id,
        terminal_id, created_at
    )
    SELECT
        v_entry_no,
        COALESCE(item->>'product_id', ''),
        COALESCE(item->>'product_name', ''),
        COALESCE(item->>'extra', ''),
        COALESCE(item->>'batch_number', item->>'batch', ''),
        COALESCE(item->>'expiry_date', item->>'expiry', ''),
        COALESCE(NULLIF(item->>'quantity', '')::INT, NULLIF(item->>'qty', '')::INT, 1),
        COALESCE(NULLIF(item->>'f_qty', '')::INT, 0),
        COALESCE(item->>'hsn_code', ''),
        COALESCE(item->>'schedule', 'H'),
        COALESCE(NULLIF(item->>'packing', '')::INT, 1),
        COALESCE(NULLIF(item->>'mrp', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(item->>'purchase_rate', '')::NUMERIC, NULLIF(item->>'p_rate', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(item->>'landing_cost', '')::NUMERIC, NULLIF(item->>'l_cost', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(item->>'taxable_sp', '')::NUMERIC, NULLIF(item->>'unit_price', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(item->>'unit_price', '')::NUMERIC, NULLIF(item->>'s_rate', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(item->>'disc_percent', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(item->>'disc_amt', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(item->>'gst_percent', '')::NUMERIC, 12.0),
        COALESCE(NULLIF(item->>'gst_amt', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(item->>'cgst_amt', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(item->>'sgst_amt', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(item->>'igst_amt', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(item->>'total_amount', '')::NUMERIC, NULLIF(item->>'total', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(item->>'profit', '')::NUMERIC, 0.0),
        COALESCE(item->>'supplier_name', ''),
        COALESCE(item->>'rack', ''),
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

-- -------------------------------------------------------------------------
-- 7. ATOMIC RPC FUNCTION: fn_process_purchase_atomic
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_process_purchase_atomic(
    p_purchase JSONB,
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
    v_exp_date TEXT;
    v_qty INT;
    v_f_qty INT;
    v_packing INT;
    v_loose_qty INT;
    v_total_units INT;
    v_batch_key TEXT;
    v_p_rate NUMERIC;
    v_l_cost NUMERIC;
    v_mrp NUMERIC;
    v_s_rate NUMERIC;
    v_gst_pct NUMERIC;
    v_supplier TEXT;
    v_closing_stock INT;
    v_response JSONB;
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
    v_entry_no := TRIM(COALESCE(p_purchase->>'entry_no', ''));
    v_branch_id := TRIM(COALESCE(p_purchase->>'branch_id', 'MAIN_STORE'));
    v_terminal_id := TRIM(COALESCE(p_purchase->>'terminal_id', 'POS-01'));
    v_user_id := TRIM(COALESCE(p_purchase->>'done_by', 'Admin'));

    IF v_entry_no = '' OR v_branch_id = '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'reason', 'INVALID_INPUT',
            'message', 'Missing required entry_no or branch_id'
        );
    END IF;

    -- 3. Upsert Purchase Entry Header
    INSERT INTO public.purchase_entries (
        entry_no, date, supplier_name, sup_inv_no, sup_inv_date, done_by,
        sub_total, trade_discount, discount, other_charges, round_off,
        grand_total, total_amount, paid_amount, payment_status, days,
        remarks, financial_year, is_deleted, branch_id, terminal_id, updated_at
    ) VALUES (
        v_entry_no,
        COALESCE(p_purchase->>'date', NOW()::TEXT),
        COALESCE(p_purchase->>'supplier_name', ''),
        COALESCE(p_purchase->>'sup_inv_no', ''),
        COALESCE(p_purchase->>'sup_inv_date', NOW()::TEXT),
        v_user_id,
        COALESCE(NULLIF(p_purchase->>'sub_total', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_purchase->>'trade_discount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_purchase->>'discount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_purchase->>'other_charges', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_purchase->>'round_off', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_purchase->>'grand_total', '')::NUMERIC, NULLIF(p_purchase->>'total_amount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_purchase->>'total_amount', '')::NUMERIC, NULLIF(p_purchase->>'grand_total', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_purchase->>'paid_amount', '')::NUMERIC, 0.0),
        COALESCE(p_purchase->>'payment_status', 'UNPAID'),
        COALESCE(NULLIF(p_purchase->>'days', '')::INT, 0),
        COALESCE(p_purchase->>'remarks', ''),
        COALESCE(p_purchase->>'financial_year', ''),
        COALESCE(NULLIF(p_purchase->>'is_deleted', '')::INT, 0),
        v_branch_id,
        v_terminal_id,
        NOW()
    )
    ON CONFLICT (entry_no) DO UPDATE SET
        supplier_name = EXCLUDED.supplier_name,
        sup_inv_no = EXCLUDED.sup_inv_no,
        grand_total = EXCLUDED.grand_total,
        is_deleted = EXCLUDED.is_deleted,
        branch_id = EXCLUDED.branch_id,
        updated_at = NOW();

    DELETE FROM public.purchase_items WHERE entry_no = v_entry_no;

    -- 4. Process Items & Inward Stock Delta
    IF p_items IS NOT NULL AND jsonb_array_length(p_items) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
        LOOP
            v_prod_id := TRIM(COALESCE(v_item->>'product_id', v_item->>'id', ''));
            v_batch_no := TRIM(COALESCE(v_item->>'batch', v_item->>'batch_number', ''));
            v_exp_date := TRIM(COALESCE(v_item->>'expiry', v_item->>'expiry_date', ''));
            v_qty := COALESCE(NULLIF(v_item->>'qty', '')::INT, NULLIF(v_item->>'quantity', '')::INT, 1);
            v_f_qty := COALESCE(NULLIF(v_item->>'f_qty', '')::INT, 0);
            v_packing := COALESCE(NULLIF(v_item->>'packin', '')::INT, NULLIF(v_item->>'packing', '')::INT, 1);
            v_loose_qty := COALESCE(NULLIF(v_item->>'loose_qty', '')::INT, 0);
            v_p_rate := COALESCE(NULLIF(v_item->>'p_rate', '')::NUMERIC, NULLIF(v_item->>'purchase_rate', '')::NUMERIC, 0.0);
            v_l_cost := COALESCE(NULLIF(v_item->>'l_cost', '')::NUMERIC, NULLIF(v_item->>'landing_cost', '')::NUMERIC, v_p_rate);
            v_mrp := COALESCE(NULLIF(v_item->>'mrp', '')::NUMERIC, 0.0);
            v_s_rate := COALESCE(NULLIF(v_item->>'s_rate', '')::NUMERIC, NULLIF(v_item->>'selling_rate', '')::NUMERIC, v_mrp);
            v_gst_pct := COALESCE(NULLIF(v_item->>'gst_percent', '')::NUMERIC, 12.0);
            v_supplier := TRIM(COALESCE(v_item->>'supplier', p_purchase->>'supplier_name', ''));

            v_total_units := (v_qty * v_packing) + v_loose_qty + (v_f_qty * v_packing);

            -- Save purchase line item
            INSERT INTO public.purchase_items (
                entry_no, product_id, product_name, batch, expiry,
                qty, loose_qty, f_qty, packin, mrp, p_rate, l_cost, s_rate,
                gst_percent, total, supplier, branch_id, terminal_id, created_at
            ) VALUES (
                v_entry_no, v_prod_id, COALESCE(v_item->>'product_name', ''), v_batch_no, v_exp_date,
                v_qty, v_loose_qty, v_f_qty, v_packing, v_mrp, v_p_rate, v_l_cost, v_s_rate,
                v_gst_pct, COALESCE(NULLIF(v_item->>'total', '')::NUMERIC, 0.0), v_supplier, v_branch_id, v_terminal_id, NOW()
            );

            -- Inward delta to stock_batches
            v_batch_key := v_branch_id || '_' || v_prod_id || '_' || v_batch_no || '_' || v_exp_date;
            v_batch_key := regexp_replace(v_batch_key, '[^a-zA-Z0-9_-]', '_', 'g');

            INSERT INTO public.stock_batches (
                id, product_id, batch_number, expiry_date,
                purchase_rate, landing_cost, mrp, selling_rate,
                current_quantity, gst_percent, supplier_name, packing, is_active,
                branch_id, updated_at
            ) VALUES (
                v_batch_key, v_prod_id, v_batch_no, v_exp_date,
                v_p_rate, v_l_cost, v_mrp, v_s_rate,
                v_total_units, v_gst_pct, v_supplier, v_packing, 1,
                v_branch_id, NOW()
            )
            ON CONFLICT (id) DO UPDATE SET
                current_quantity = stock_batches.current_quantity + EXCLUDED.current_quantity,
                purchase_rate = EXCLUDED.purchase_rate,
                landing_cost = EXCLUDED.landing_cost,
                mrp = EXCLUDED.mrp,
                selling_rate = EXCLUDED.selling_rate,
                updated_at = NOW()
            RETURNING current_quantity INTO v_closing_stock;

            -- Record inward stock movement in ledger
            INSERT INTO public.stock_ledger (
                idempotency_key, operation_type, reference_no, product_id, batch_number,
                quantity_delta, qty_in, qty_out, closing_balance,
                purchase_rate, mrp, selling_rate,
                branch_id, terminal_id, user_id, created_at
            ) VALUES (
                p_idempotency_key, 'PURCHASE', v_entry_no, v_prod_id, v_batch_no,
                v_total_units, v_total_units, 0, v_closing_stock,
                v_p_rate, v_mrp, v_s_rate,
                v_branch_id, v_terminal_id, v_user_id, NOW()
            );
        END LOOP;
    END IF;

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
            p_idempotency_key, v_branch_id, v_terminal_id, 'PURCHASE', v_entry_no, v_response, NOW()
        )
        ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;

    RETURN v_response;
END;
$$;

-- -------------------------------------------------------------------------
-- 8. ATOMIC RPC FUNCTION: fn_process_sales_return_atomic
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_process_sales_return_atomic(
    p_return JSONB,
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
    v_exp_date TEXT;
    v_qty INT;
    v_batch_key TEXT;
    v_closing_stock INT;
    v_response JSONB;
BEGIN
    IF p_idempotency_key IS NOT NULL AND p_idempotency_key <> '' THEN
        SELECT response_payload INTO v_cached_response
        FROM public.idempotency_keys
        WHERE idempotency_key = p_idempotency_key;

        IF FOUND THEN
            RETURN v_cached_response;
        END IF;
    END IF;

    v_entry_no := TRIM(COALESCE(p_return->>'entry_no', ''));
    v_branch_id := TRIM(COALESCE(p_return->>'branch_id', 'MAIN_STORE'));
    v_terminal_id := TRIM(COALESCE(p_return->>'terminal_id', 'POS-01'));
    v_user_id := TRIM(COALESCE(p_return->>'done_by', 'Cashier'));

    IF v_entry_no = '' OR v_branch_id = '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'reason', 'INVALID_INPUT',
            'message', 'Missing entry_no or branch_id'
        );
    END IF;

    -- Upsert header
    INSERT INTO public.sales_return_invoices (
        entry_no, date, customer_acc, patient, original_invoice_no,
        sub_total, discount, round_off, grand_total, narration,
        financial_year, branch_id, terminal_id, updated_at
    ) VALUES (
        v_entry_no,
        COALESCE(p_return->>'date', NOW()::TEXT),
        COALESCE(p_return->>'customer_acc', 'Cash'),
        COALESCE(p_return->>'patient', ''),
        COALESCE(p_return->>'original_invoice_no', ''),
        COALESCE(NULLIF(p_return->>'sub_total', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_return->>'discount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_return->>'round_off', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_return->>'grand_total', '')::NUMERIC, 0.0),
        COALESCE(p_return->>'narration', ''),
        COALESCE(p_return->>'financial_year', ''),
        v_branch_id,
        v_terminal_id,
        NOW()
    )
    ON CONFLICT (entry_no) DO UPDATE SET
        grand_total = EXCLUDED.grand_total,
        branch_id = EXCLUDED.branch_id,
        updated_at = NOW();

    DELETE FROM public.sales_return_items WHERE return_no = v_entry_no;

    IF p_items IS NOT NULL AND jsonb_array_length(p_items) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
        LOOP
            v_prod_id := TRIM(COALESCE(v_item->>'product_id', ''));
            v_batch_no := TRIM(COALESCE(v_item->>'batch_number', v_item->>'batch', ''));
            v_exp_date := TRIM(COALESCE(v_item->>'expiry_date', v_item->>'expiry', ''));
            v_qty := COALESCE(NULLIF(v_item->>'quantity', '')::INT, NULLIF(v_item->>'qty', '')::INT, 1);

            INSERT INTO public.sales_return_items (
                return_no, product_id, product_name, batch_number, expiry_date,
                quantity, mrp, sale_rate, total, branch_id, terminal_id, created_at
            ) VALUES (
                v_entry_no, v_prod_id, COALESCE(v_item->>'product_name', ''), v_batch_no, v_exp_date,
                v_qty, COALESCE(NULLIF(v_item->>'mrp', '')::NUMERIC, 0.0),
                COALESCE(NULLIF(v_item->>'sale_rate', '')::NUMERIC, 0.0),
                COALESCE(NULLIF(v_item->>'total', '')::NUMERIC, 0.0),
                v_branch_id, v_terminal_id, NOW()
            );

            -- Restore shelf stock delta
            v_batch_key := v_branch_id || '_' || v_prod_id || '_' || v_batch_no || '_' || v_exp_date;
            v_batch_key := regexp_replace(v_batch_key, '[^a-zA-Z0-9_-]', '_', 'g');

            INSERT INTO public.stock_batches (
                id, product_id, batch_number, expiry_date, current_quantity, branch_id, updated_at
            ) VALUES (
                v_batch_key, v_prod_id, v_batch_no, v_exp_date, v_qty, v_branch_id, NOW()
            )
            ON CONFLICT (id) DO UPDATE SET
                current_quantity = stock_batches.current_quantity + EXCLUDED.current_quantity,
                updated_at = NOW()
            RETURNING current_quantity INTO v_closing_stock;

            INSERT INTO public.stock_ledger (
                idempotency_key, operation_type, reference_no, product_id, batch_number,
                quantity_delta, qty_in, qty_out, closing_balance,
                branch_id, terminal_id, user_id, created_at
            ) VALUES (
                p_idempotency_key, 'SALES_RETURN', v_entry_no, v_prod_id, v_batch_no,
                v_qty, v_qty, 0, v_closing_stock,
                v_branch_id, v_terminal_id, v_user_id, NOW()
            );
        END LOOP;
    END IF;

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
            p_idempotency_key, v_branch_id, v_terminal_id, 'SALES_RETURN', v_entry_no, v_response, NOW()
        )
        ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;

    RETURN v_response;
END;
$$;

-- -------------------------------------------------------------------------
-- 9. ATOMIC RPC FUNCTION: fn_process_purchase_return_atomic
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_process_purchase_return_atomic(
    p_return JSONB,
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
    v_qty INT;
    v_avail_qty INT;
    v_units_remaining INT;
    v_batch_rec RECORD;
    v_deduct INT;
    v_closing_stock INT;
    v_response JSONB;
BEGIN
    IF p_idempotency_key IS NOT NULL AND p_idempotency_key <> '' THEN
        SELECT response_payload INTO v_cached_response
        FROM public.idempotency_keys
        WHERE idempotency_key = p_idempotency_key;

        IF FOUND THEN
            RETURN v_cached_response;
        END IF;
    END IF;

    v_entry_no := TRIM(COALESCE(p_return->>'entry_no', ''));
    v_branch_id := TRIM(COALESCE(p_return->>'branch_id', 'MAIN_STORE'));
    v_terminal_id := TRIM(COALESCE(p_return->>'terminal_id', 'POS-01'));
    v_user_id := TRIM(COALESCE(p_return->>'done_by', 'Admin'));

    IF v_entry_no = '' OR v_branch_id = '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'reason', 'INVALID_INPUT',
            'message', 'Missing entry_no or branch_id'
        );
    END IF;

    -- Pre-flight verification with FOR UPDATE lock
    IF p_items IS NOT NULL AND jsonb_array_length(p_items) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
        LOOP
            v_prod_id := TRIM(COALESCE(v_item->>'product_id', v_item->>'id', ''));
            v_batch_no := TRIM(COALESCE(v_item->>'batch', v_item->>'batch_number', ''));
            v_qty := COALESCE(NULLIF(v_item->>'qty', '')::INT, NULLIF(v_item->>'quantity', '')::INT, 1);

            SELECT COALESCE(SUM(current_quantity), 0) INTO v_avail_qty
            FROM public.stock_batches
            WHERE branch_id = v_branch_id
              AND product_id = v_prod_id
              AND LOWER(TRIM(batch_number)) = LOWER(v_batch_no)
            FOR UPDATE;

            IF v_avail_qty < v_qty THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'reason', 'INSUFFICIENT_STOCK',
                    'message', 'Cannot return to supplier: Insufficient shelf stock for product ' || v_prod_id || ' batch ' || v_batch_no || ' (Available: ' || v_avail_qty || ', Required: ' || v_qty || ')'
                );
            END IF;
        END LOOP;
    END IF;

    -- Upsert header
    INSERT INTO public.purchase_return_entries (
        entry_no, date, supplier_name, original_purchase_no, done_by,
        grand_total, financial_year, branch_id, terminal_id, updated_at
    ) VALUES (
        v_entry_no,
        COALESCE(p_return->>'date', NOW()::TEXT),
        COALESCE(p_return->>'supplier_name', ''),
        COALESCE(p_return->>'original_purchase_no', ''),
        v_user_id,
        COALESCE(NULLIF(p_return->>'grand_total', '')::NUMERIC, 0.0),
        COALESCE(p_return->>'financial_year', ''),
        v_branch_id,
        v_terminal_id,
        NOW()
    )
    ON CONFLICT (entry_no) DO UPDATE SET
        grand_total = EXCLUDED.grand_total,
        branch_id = EXCLUDED.branch_id,
        updated_at = NOW();

    DELETE FROM public.purchase_return_items WHERE entry_no = v_entry_no;

    -- Deduct shelf stock & record movements
    IF p_items IS NOT NULL AND jsonb_array_length(p_items) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
        LOOP
            v_prod_id := TRIM(COALESCE(v_item->>'product_id', v_item->>'id', ''));
            v_batch_no := TRIM(COALESCE(v_item->>'batch', v_item->>'batch_number', ''));
            v_qty := COALESCE(NULLIF(v_item->>'qty', '')::INT, NULLIF(v_item->>'quantity', '')::INT, 1);

            INSERT INTO public.purchase_return_items (
                entry_no, product_name, batch, expiry, qty, total, branch_id, terminal_id, created_at
            ) VALUES (
                v_entry_no, COALESCE(v_item->>'product_name', ''), v_batch_no,
                COALESCE(v_item->>'expiry', ''), v_qty,
                COALESCE(NULLIF(v_item->>'total', '')::NUMERIC, 0.0),
                v_branch_id, v_terminal_id, NOW()
            );

            v_units_remaining := v_qty;

            FOR v_batch_rec IN
                SELECT id, current_quantity
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

                v_deduct := LEAST(v_units_remaining, v_batch_rec.current_quantity);

                UPDATE public.stock_batches
                SET current_quantity = current_quantity - v_deduct,
                    updated_at = NOW()
                WHERE id = v_batch_rec.id
                RETURNING current_quantity INTO v_closing_stock;

                INSERT INTO public.stock_ledger (
                    idempotency_key, operation_type, reference_no, product_id, batch_number,
                    quantity_delta, qty_in, qty_out, closing_balance,
                    branch_id, terminal_id, user_id, created_at
                ) VALUES (
                    p_idempotency_key, 'PURCHASE_RETURN', v_entry_no, v_prod_id, v_batch_no,
                    -v_deduct, 0, v_deduct, v_closing_stock,
                    v_branch_id, v_terminal_id, v_user_id, NOW()
                );

                v_units_remaining := v_units_remaining - v_deduct;
            END LOOP;
        END LOOP;
    END IF;

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
            p_idempotency_key, v_branch_id, v_terminal_id, 'PURCHASE_RETURN', v_entry_no, v_response, NOW()
        )
        ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;

    RETURN v_response;
END;
$$;

-- -------------------------------------------------------------------------
-- 10. ATOMIC RPC FUNCTION: fn_process_stock_adjustment_atomic
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_process_stock_adjustment_atomic(
    p_adjustment JSONB,
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
    v_qty INT;
    v_avail_qty INT;
    v_batch_key TEXT;
    v_closing_stock INT;
    v_response JSONB;
BEGIN
    IF p_idempotency_key IS NOT NULL AND p_idempotency_key <> '' THEN
        SELECT response_payload INTO v_cached_response
        FROM public.idempotency_keys
        WHERE idempotency_key = p_idempotency_key;

        IF FOUND THEN
            RETURN v_cached_response;
        END IF;
    END IF;

    v_entry_no := TRIM(COALESCE(p_adjustment->>'entry_no', ''));
    v_branch_id := TRIM(COALESCE(p_adjustment->>'branch_id', 'MAIN_STORE'));
    v_terminal_id := TRIM(COALESCE(p_adjustment->>'terminal_id', 'POS-01'));
    v_user_id := TRIM(COALESCE(p_adjustment->>'done_by', 'Admin'));

    IF v_entry_no = '' OR v_branch_id = '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'reason', 'INVALID_INPUT',
            'message', 'Missing entry_no or branch_id'
        );
    END IF;

    -- Pre-flight checks for negative adjustments
    IF p_items IS NOT NULL AND jsonb_array_length(p_items) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
        LOOP
            v_prod_id := TRIM(COALESCE(v_item->>'product_id', ''));
            v_batch_no := TRIM(COALESCE(v_item->>'batch_number', v_item->>'batch', ''));
            v_qty := COALESCE(NULLIF(v_item->>'qty', '')::INT, 0);

            IF v_qty < 0 THEN
                SELECT COALESCE(SUM(current_quantity), 0) INTO v_avail_qty
                FROM public.stock_batches
                WHERE branch_id = v_branch_id
                  AND product_id = v_prod_id
                  AND LOWER(TRIM(batch_number)) = LOWER(v_batch_no)
                FOR UPDATE;

                IF v_avail_qty + v_qty < 0 THEN
                    RETURN jsonb_build_object(
                        'success', false,
                        'reason', 'INSUFFICIENT_STOCK',
                        'message', 'Cannot reduce stock: only ' || v_avail_qty || ' units available for product ' || v_prod_id || ' batch ' || v_batch_no
                    );
                END IF;
            END IF;
        END LOOP;
    END IF;

    -- Upsert header
    INSERT INTO public.stock_adjustments (
        entry_no, date, done_by, reason, grand_total, financial_year, branch_id, terminal_id, updated_at
    ) VALUES (
        v_entry_no,
        COALESCE(p_adjustment->>'date', NOW()::TEXT),
        v_user_id,
        COALESCE(p_adjustment->>'reason', ''),
        COALESCE(NULLIF(p_adjustment->>'grand_total', '')::NUMERIC, 0.0),
        COALESCE(p_adjustment->>'financial_year', ''),
        v_branch_id,
        v_terminal_id,
        NOW()
    )
    ON CONFLICT (entry_no) DO UPDATE SET
        reason = EXCLUDED.reason,
        grand_total = EXCLUDED.grand_total,
        branch_id = EXCLUDED.branch_id,
        updated_at = NOW();

    DELETE FROM public.stock_adjustment_items WHERE adjustment_no = v_entry_no;

    -- Process items & apply delta
    IF p_items IS NOT NULL AND jsonb_array_length(p_items) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
        LOOP
            v_prod_id := TRIM(COALESCE(v_item->>'product_id', ''));
            v_batch_no := TRIM(COALESCE(v_item->>'batch_number', v_item->>'batch', ''));
            v_qty := COALESCE(NULLIF(v_item->>'qty', '')::INT, 0);

            INSERT INTO public.stock_adjustment_items (
                adjustment_no, product_id, batch_number, qty, purchase_rate, total, branch_id, terminal_id, created_at
            ) VALUES (
                v_entry_no, v_prod_id, v_batch_no, v_qty,
                COALESCE(NULLIF(v_item->>'purchase_rate', '')::NUMERIC, 0.0),
                COALESCE(NULLIF(v_item->>'total', '')::NUMERIC, 0.0),
                v_branch_id, v_terminal_id, NOW()
            );

            v_batch_key := v_branch_id || '_' || v_prod_id || '_' || v_batch_no;
            v_batch_key := regexp_replace(v_batch_key, '[^a-zA-Z0-9_-]', '_', 'g');

            IF v_qty >= 0 THEN
                INSERT INTO public.stock_batches (
                    id, product_id, batch_number, expiry_date, current_quantity, branch_id, updated_at
                ) VALUES (
                    v_batch_key, v_prod_id, v_batch_no, COALESCE(v_item->>'expiry_date', '--/--'), v_qty, v_branch_id, NOW()
                )
                ON CONFLICT (id) DO UPDATE SET
                    current_quantity = stock_batches.current_quantity + EXCLUDED.current_quantity,
                    updated_at = NOW()
                RETURNING current_quantity INTO v_closing_stock;
            ELSE
                UPDATE public.stock_batches
                SET current_quantity = current_quantity + v_qty,
                    updated_at = NOW()
                WHERE branch_id = v_branch_id
                  AND product_id = v_prod_id
                  AND LOWER(TRIM(batch_number)) = LOWER(v_batch_no)
                RETURNING current_quantity INTO v_closing_stock;
            END IF;

            INSERT INTO public.stock_ledger (
                idempotency_key, operation_type, reference_no, product_id, batch_number,
                quantity_delta, qty_in, qty_out, closing_balance,
                branch_id, terminal_id, user_id, created_at
            ) VALUES (
                p_idempotency_key, 'ADJUSTMENT', v_entry_no, v_prod_id, v_batch_no,
                v_qty, (CASE WHEN v_qty > 0 THEN v_qty ELSE 0 END), (CASE WHEN v_qty < 0 THEN ABS(v_qty) ELSE 0 END), v_closing_stock,
                v_branch_id, v_terminal_id, v_user_id, NOW()
            );
        END LOOP;
    END IF;

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
            p_idempotency_key, v_branch_id, v_terminal_id, 'ADJUSTMENT', v_entry_no, v_response, NOW()
        )
        ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;

    RETURN v_response;
END;
$$;

-- -------------------------------------------------------------------------
-- 11. ATOMIC RPC FUNCTION: fn_process_stock_write_off_atomic
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_process_stock_write_off_atomic(
    p_write_off JSONB,
    p_idempotency_key TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id TEXT;
    v_branch_id TEXT;
    v_terminal_id TEXT;
    v_user_id TEXT;
    v_cached_response JSONB;
    v_prod_id TEXT;
    v_batch_no TEXT;
    v_qty INT;
    v_avail_qty INT;
    v_closing_stock INT;
    v_response JSONB;
BEGIN
    IF p_idempotency_key IS NOT NULL AND p_idempotency_key <> '' THEN
        SELECT response_payload INTO v_cached_response
        FROM public.idempotency_keys
        WHERE idempotency_key = p_idempotency_key;

        IF FOUND THEN
            RETURN v_cached_response;
        END IF;
    END IF;

    v_id := TRIM(COALESCE(p_write_off->>'id', ''));
    v_branch_id := TRIM(COALESCE(p_write_off->>'branch_id', 'MAIN_STORE'));
    v_terminal_id := TRIM(COALESCE(p_write_off->>'terminal_id', 'POS-01'));
    v_user_id := TRIM(COALESCE(p_write_off->>'user_id', 'Admin'));
    v_prod_id := TRIM(COALESCE(p_write_off->>'product_id', ''));
    v_batch_no := TRIM(COALESCE(p_write_off->>'batch_number', ''));
    v_qty := COALESCE(NULLIF(p_write_off->>'quantity', '')::INT, 1);

    IF v_id = '' OR v_prod_id = '' OR v_batch_no = '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'reason', 'INVALID_INPUT',
            'message', 'Missing required write off id, product_id, or batch_number'
        );
    END IF;

    -- Pre-flight lock & check
    SELECT COALESCE(SUM(current_quantity), 0) INTO v_avail_qty
    FROM public.stock_batches
    WHERE branch_id = v_branch_id
      AND product_id = v_prod_id
      AND LOWER(TRIM(batch_number)) = LOWER(v_batch_no)
    FOR UPDATE;

    IF v_avail_qty < v_qty THEN
        RETURN jsonb_build_object(
            'success', false,
            'reason', 'INSUFFICIENT_STOCK',
            'message', 'Cannot write-off ' || v_qty || ' units of product ' || v_prod_id || '. Only ' || v_avail_qty || ' available.'
        );
    END IF;

    -- Deduct stock
    UPDATE public.stock_batches
    SET current_quantity = current_quantity - v_qty,
        updated_at = NOW()
    WHERE branch_id = v_branch_id
      AND product_id = v_prod_id
      AND LOWER(TRIM(batch_number)) = LOWER(v_batch_no)
    RETURNING current_quantity INTO v_closing_stock;

    -- Insert write off record
    INSERT INTO public.stock_write_offs (
        id, date, product_id, batch_number, quantity, reason,
        loss_value, financial_year, branch_id, terminal_id, updated_at
    ) VALUES (
        v_id,
        COALESCE(p_write_off->>'date', NOW()::TEXT),
        v_prod_id,
        v_batch_no,
        v_qty,
        COALESCE(p_write_off->>'reason', ''),
        COALESCE(NULLIF(p_write_off->>'loss_value', '')::NUMERIC, 0.0),
        COALESCE(p_write_off->>'financial_year', ''),
        v_branch_id,
        v_terminal_id,
        NOW()
    )
    ON CONFLICT (id) DO UPDATE SET
        quantity = EXCLUDED.quantity,
        loss_value = EXCLUDED.loss_value,
        branch_id = EXCLUDED.branch_id,
        updated_at = NOW();

    -- Record ledger
    INSERT INTO public.stock_ledger (
        idempotency_key, operation_type, reference_no, product_id, batch_number,
        quantity_delta, qty_in, qty_out, closing_balance,
        branch_id, terminal_id, user_id, created_at
    ) VALUES (
        p_idempotency_key, 'WRITE_OFF', v_id, v_prod_id, v_batch_no,
        -v_qty, 0, v_qty, v_closing_stock,
        v_branch_id, v_terminal_id, v_user_id, NOW()
    );

    v_response := jsonb_build_object(
        'success', true,
        'id', v_id,
        'branch_id', v_branch_id,
        'terminal_id', v_terminal_id,
        'idempotency_key', p_idempotency_key
    );

    IF p_idempotency_key IS NOT NULL AND p_idempotency_key <> '' THEN
        INSERT INTO public.idempotency_keys (
            idempotency_key, branch_id, terminal_id, operation_type, reference_no, response_payload, created_at
        ) VALUES (
            p_idempotency_key, v_branch_id, v_terminal_id, 'WRITE_OFF', v_id, v_response, NOW()
        )
        ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;

    RETURN v_response;
END;
$$;

-- -------------------------------------------------------------------------
-- 12. ATOMIC RPC FUNCTION: fn_void_sale_atomic
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_void_sale_atomic(
    p_entry_no TEXT,
    p_branch_id TEXT,
    p_terminal_id TEXT,
    p_idempotency_key TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_clean_entry TEXT;
    v_clean_branch TEXT;
    v_clean_term TEXT;
    v_cached_response JSONB;
    v_inv_rec RECORD;
    v_item RECORD;
    v_closing_stock INT;
    v_response JSONB;
BEGIN
    IF p_idempotency_key IS NOT NULL AND p_idempotency_key <> '' THEN
        SELECT response_payload INTO v_cached_response
        FROM public.idempotency_keys
        WHERE idempotency_key = p_idempotency_key;

        IF FOUND THEN
            RETURN v_cached_response;
        END IF;
    END IF;

    v_clean_entry := TRIM(COALESCE(p_entry_no, ''));
    v_clean_branch := TRIM(COALESCE(p_branch_id, 'MAIN_STORE'));
    v_clean_term := TRIM(COALESCE(p_terminal_id, 'POS-01'));

    SELECT * INTO v_inv_rec
    FROM public.sales_invoices
    WHERE entry_no = v_clean_entry AND branch_id = v_clean_branch
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'reason', 'NOT_FOUND',
            'message', 'Invoice not found: ' || v_clean_entry
        );
    END IF;

    IF v_inv_rec.is_deleted = 1 THEN
        -- Already deleted
        RETURN jsonb_build_object(
            'success', true,
            'entry_no', v_clean_entry,
            'message', 'Invoice was already voided'
        );
    END IF;

    -- Mark deleted
    UPDATE public.sales_invoices
    SET is_deleted = 1, updated_at = NOW()
    WHERE entry_no = v_clean_entry;

    -- Restore quantities to shelf stock
    FOR v_item IN
        SELECT product_id, batch_number, quantity, f_qty, purchase_rate, mrp, unit_price
        FROM public.sales_items
        WHERE invoice_no = v_clean_entry
    LOOP
        UPDATE public.stock_batches
        SET current_quantity = current_quantity + (v_item.quantity + v_item.f_qty),
            updated_at = NOW()
        WHERE branch_id = v_clean_branch
          AND product_id = v_item.product_id
          AND LOWER(TRIM(batch_number)) = LOWER(TRIM(v_item.batch_number))
        RETURNING current_quantity INTO v_closing_stock;

        INSERT INTO public.stock_ledger (
            idempotency_key, operation_type, reference_no, product_id, batch_number,
            quantity_delta, qty_in, qty_out, closing_balance,
            purchase_rate, mrp, selling_rate,
            branch_id, terminal_id, user_id, created_at
        ) VALUES (
            p_idempotency_key, 'SALE_VOID', v_clean_entry, v_item.product_id, v_item.batch_number,
            (v_item.quantity + v_item.f_qty), (v_item.quantity + v_item.f_qty), 0, v_closing_stock,
            COALESCE(v_item.purchase_rate, 0.0), COALESCE(v_item.mrp, 0.0), COALESCE(v_item.unit_price, 0.0),
            v_clean_branch, v_clean_term, 'Admin', NOW()
        );
    END LOOP;

    v_response := jsonb_build_object(
        'success', true,
        'entry_no', v_clean_entry,
        'branch_id', v_clean_branch,
        'message', 'Invoice voided and stock restored successfully'
    );

    IF p_idempotency_key IS NOT NULL AND p_idempotency_key <> '' THEN
        INSERT INTO public.idempotency_keys (
            idempotency_key, branch_id, terminal_id, operation_type, reference_no, response_payload, created_at
        ) VALUES (
            p_idempotency_key, v_clean_branch, v_clean_term, 'SALE_VOID', v_clean_entry, v_response, NOW()
        )
        ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;

    RETURN v_response;
END;
$$;

-- -------------------------------------------------------------------------
-- 13. ATOMIC RPC FUNCTION: fn_void_purchase_atomic
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_void_purchase_atomic(
    p_entry_no TEXT,
    p_branch_id TEXT,
    p_terminal_id TEXT,
    p_idempotency_key TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_clean_entry TEXT;
    v_clean_branch TEXT;
    v_clean_term TEXT;
    v_cached_response JSONB;
    v_pur_rec RECORD;
    v_item RECORD;
    v_avail_qty INT;
    v_req_deduct INT;
    v_closing_stock INT;
    v_response JSONB;
BEGIN
    IF p_idempotency_key IS NOT NULL AND p_idempotency_key <> '' THEN
        SELECT response_payload INTO v_cached_response
        FROM public.idempotency_keys
        WHERE idempotency_key = p_idempotency_key;

        IF FOUND THEN
            RETURN v_cached_response;
        END IF;
    END IF;

    v_clean_entry := TRIM(COALESCE(p_entry_no, ''));
    v_clean_branch := TRIM(COALESCE(p_branch_id, 'MAIN_STORE'));
    v_clean_term := TRIM(COALESCE(p_terminal_id, 'POS-01'));

    SELECT * INTO v_pur_rec
    FROM public.purchase_entries
    WHERE entry_no = v_clean_entry AND branch_id = v_clean_branch
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'reason', 'NOT_FOUND',
            'message', 'Purchase entry not found: ' || v_clean_entry
        );
    END IF;

    IF v_pur_rec.is_deleted = 1 THEN
        RETURN jsonb_build_object(
            'success', true,
            'entry_no', v_clean_entry,
            'message', 'Purchase entry was already voided'
        );
    END IF;

    -- Verify shelf stock availability before voiding (ensure units were not already sold)
    FOR v_item IN
        SELECT product_id, batch, qty, loose_qty, f_qty, packin
        FROM public.purchase_items
        WHERE entry_no = v_clean_entry
    LOOP
        v_req_deduct := (v_item.qty * COALESCE(v_item.packin, 1)) + COALESCE(v_item.loose_qty, 0) + (v_item.f_qty * COALESCE(v_item.packin, 1));

        SELECT COALESCE(SUM(current_quantity), 0) INTO v_avail_qty
        FROM public.stock_batches
        WHERE branch_id = v_clean_branch
          AND product_id = v_item.product_id
          AND LOWER(TRIM(batch_number)) = LOWER(TRIM(v_item.batch))
        FOR UPDATE;

        IF v_avail_qty < v_req_deduct THEN
            RETURN jsonb_build_object(
                'success', false,
                'reason', 'STOCK_ALREADY_CONSUMED',
                'message', 'Cannot void purchase #' || v_clean_entry || ': Units of product ' || v_item.product_id || ' batch ' || v_item.batch || ' were already sold. (Available: ' || v_avail_qty || ', Needed: ' || v_req_deduct || ')'
            );
        END IF;
    END LOOP;

    -- Mark deleted
    UPDATE public.purchase_entries
    SET is_deleted = 1, updated_at = NOW()
    WHERE entry_no = v_clean_entry;

    -- Deduct purchase units
    FOR v_item IN
        SELECT product_id, batch, qty, loose_qty, f_qty, packin, p_rate, mrp, s_rate
        FROM public.purchase_items
        WHERE entry_no = v_clean_entry
    LOOP
        v_req_deduct := (v_item.qty * COALESCE(v_item.packin, 1)) + COALESCE(v_item.loose_qty, 0) + (v_item.f_qty * COALESCE(v_item.packin, 1));

        UPDATE public.stock_batches
        SET current_quantity = current_quantity - v_req_deduct,
            updated_at = NOW()
        WHERE branch_id = v_clean_branch
          AND product_id = v_item.product_id
          AND LOWER(TRIM(batch_number)) = LOWER(TRIM(v_item.batch))
        RETURNING current_quantity INTO v_closing_stock;

        INSERT INTO public.stock_ledger (
            idempotency_key, operation_type, reference_no, product_id, batch_number,
            quantity_delta, qty_in, qty_out, closing_balance,
            purchase_rate, mrp, selling_rate,
            branch_id, terminal_id, user_id, created_at
        ) VALUES (
            p_idempotency_key, 'PURCHASE_VOID', v_clean_entry, v_item.product_id, v_item.batch,
            -v_req_deduct, 0, v_req_deduct, v_closing_stock,
            COALESCE(v_item.p_rate, 0.0), COALESCE(v_item.mrp, 0.0), COALESCE(v_item.s_rate, 0.0),
            v_clean_branch, v_clean_term, 'Admin', NOW()
        );
    END LOOP;

    v_response := jsonb_build_object(
        'success', true,
        'entry_no', v_clean_entry,
        'branch_id', v_clean_branch,
        'message', 'Purchase voided and stock deducted successfully'
    );

    IF p_idempotency_key IS NOT NULL AND p_idempotency_key <> '' THEN
        INSERT INTO public.idempotency_keys (
            idempotency_key, branch_id, terminal_id, operation_type, reference_no, response_payload, created_at
        ) VALUES (
            p_idempotency_key, v_clean_branch, v_clean_term, 'PURCHASE_VOID', v_clean_entry, v_response, NOW()
        )
        ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;

    RETURN v_response;
END;
$$;

-- -------------------------------------------------------------------------
-- 14. STOCK RECONCILIATION RPC: fn_reconcile_branch_stock_from_ledger
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_reconcile_branch_stock_from_ledger(
    p_branch_id TEXT DEFAULT 'MAIN_STORE'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_reconciled_count INT := 0;
    v_rec RECORD;
BEGIN
    FOR v_rec IN
        SELECT product_id, batch_number, SUM(quantity_delta) as calculated_stock
        FROM public.stock_ledger
        WHERE branch_id = p_branch_id
        GROUP BY product_id, batch_number
    LOOP
        UPDATE public.stock_batches
        SET current_quantity = GREATEST(0, v_rec.calculated_stock),
            updated_at = NOW()
        WHERE branch_id = p_branch_id
          AND product_id = v_rec.product_id
          AND LOWER(TRIM(batch_number)) = LOWER(TRIM(v_rec.batch_number));

        v_reconciled_count := v_reconciled_count + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'branch_id', p_branch_id,
        'batches_reconciled', v_reconciled_count
    );
END;
$$;

-- -------------------------------------------------------------------------
-- 15. SECURE REALTIME PUBLICATION & PERMISSIONS
-- -------------------------------------------------------------------------
DO $$
DECLARE
    tbl text;
    realtime_tables text[] := ARRAY[
        'stock_batches', 'stock_ledger', 'sales_invoices', 'sales_items',
        'purchase_entries', 'purchase_items', 'sales_return_invoices',
        'sales_return_items', 'stock_adjustments', 'stock_write_offs'
    ];
BEGIN
    FOR i IN 1..array_length(realtime_tables, 1) LOOP
        tbl := realtime_tables[i];
        EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL;', tbl);
        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_tables
            WHERE pubname = 'supabase_realtime' AND tablename = tbl
        ) THEN
            EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I;', tbl);
        END IF;
    END LOOP;
END $$;
