-- ==============================================================================
-- PHARMACY APP: COMPLETE FIX FOR PURCHASE_ENTRIES & PURCHASE_ITEMS SCHEMA
-- Run this in Supabase SQL Editor:
-- https://supabase.com/dashboard/project/awnfbjvvvtdzcluekwjl/sql
-- ==============================================================================

-- 1. FIX PURCHASE_ENTRIES TABLE COLUMNS (Missing columns caused PGRST204)
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS sup_inv_no TEXT;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS sup_inv_date TEXT;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS done_by TEXT;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS subtotal NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS sub_total NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS discount_amount NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS discount NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS other_charge NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS other_charges NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS round_off NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS net_amount NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS grand_total NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS inv_total NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS total_amount NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS remarks TEXT;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS days INTEGER DEFAULT 0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS tax_type TEXT DEFAULT 'Gst';
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS payment_status INTEGER DEFAULT 0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS payment_mode TEXT DEFAULT 'CREDIT';
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS payment_remarks TEXT;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS payment_date TEXT;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS paid_amount NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS branch_id TEXT DEFAULT 'MAIN_STORE';
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS is_deleted INTEGER DEFAULT 0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS financial_year TEXT;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- 2. FIX PURCHASE_ITEMS TABLE COLUMNS (Missing columns caused missing prices, qty & batches)
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS product_id TEXT;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS product_name TEXT;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS extra TEXT;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS batch_number TEXT;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS batch TEXT;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS expiry_date TEXT;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS expiry TEXT;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS quantity INTEGER DEFAULT 1;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS qty INTEGER DEFAULT 1;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS loose_qty INTEGER DEFAULT 0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS f_qty INTEGER DEFAULT 0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS packing INTEGER DEFAULT 1;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS packin INTEGER DEFAULT 1;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS mrp NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS unit_price NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS p_rate NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS gross NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS disc_percent NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS disc_amt NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS net NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS gst_percent NUMERIC DEFAULT 12.0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS gst_amt NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS total_amount NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS total NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS rack TEXT;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS hsn_code TEXT;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS s_disc_percent NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS selling_rate NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS s_rate NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS landing_cost NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS l_cost NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS supplier TEXT;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS branch_id TEXT DEFAULT 'MAIN_STORE';
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- 3. ENSURE VOUCHER_SEQUENCES TABLE EXISTS
CREATE TABLE IF NOT EXISTS public.voucher_sequences (
    voucher_type TEXT NOT NULL,
    financial_year TEXT NOT NULL,
    last_sequence INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (voucher_type, financial_year)
);

-- 4. FUNCTION: GET MAX ENTRY SEQUENCE
CREATE OR REPLACE FUNCTION public.get_max_entry_sequence(
    p_table TEXT,
    p_fy TEXT DEFAULT '',
    p_prefix TEXT DEFAULT ''
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    max_seq INT := 0;
BEGIN
    IF p_table = 'sales_invoices' THEN
        IF p_prefix IS NOT NULL AND p_prefix <> '' THEN
            SELECT COALESCE(MAX(CAST(NULLIF(SUBSTRING(REPLACE(entry_no, p_prefix, '') FROM '[0-9]+$'), '') AS INT)), 0)
            INTO max_seq
            FROM public.sales_invoices
            WHERE (p_fy IS NULL OR p_fy = '' OR financial_year = p_fy)
              AND entry_no LIKE p_prefix || '%'
              AND (COALESCE(is_deleted::text, '0') NOT IN ('1', 'true'));
        ELSE
            SELECT COALESCE(MAX(CAST(NULLIF(SUBSTRING(entry_no FROM '[0-9]+$'), '') AS INT)), 0)
            INTO max_seq
            FROM public.sales_invoices
            WHERE (p_fy IS NULL OR p_fy = '' OR financial_year = p_fy)
              AND (COALESCE(is_deleted::text, '0') NOT IN ('1', 'true'));
        END IF;
    ELSIF p_table = 'purchase_entries' THEN
        IF p_prefix IS NOT NULL AND p_prefix <> '' THEN
            SELECT COALESCE(MAX(CAST(NULLIF(SUBSTRING(REPLACE(entry_no, p_prefix, '') FROM '[0-9]+$'), '') AS INT)), 0)
            INTO max_seq
            FROM public.purchase_entries
            WHERE (p_fy IS NULL OR p_fy = '' OR financial_year = p_fy)
              AND entry_no LIKE p_prefix || '%'
              AND (COALESCE(is_deleted::text, '0') NOT IN ('1', 'true'));
        ELSE
            SELECT COALESCE(MAX(CAST(NULLIF(SUBSTRING(entry_no FROM '[0-9]+$'), '') AS INT)), 0)
            INTO max_seq
            FROM public.purchase_entries
            WHERE (p_fy IS NULL OR p_fy = '' OR financial_year = p_fy)
              AND (COALESCE(is_deleted::text, '0') NOT IN ('1', 'true'));
        END IF;
    ELSIF p_table = 'sales_return_invoices' THEN
        SELECT COALESCE(MAX(CAST(NULLIF(SUBSTRING(entry_no FROM '[0-9]+$'), '') AS INT)), 0)
        INTO max_seq
        FROM public.sales_return_invoices
        WHERE (p_fy IS NULL OR p_fy = '' OR financial_year = p_fy)
          AND (COALESCE(is_deleted::text, '0') NOT IN ('1', 'true'));
    ELSIF p_table = 'purchase_return_entries' THEN
        SELECT COALESCE(MAX(CAST(NULLIF(SUBSTRING(entry_no FROM '[0-9]+$'), '') AS INT)), 0)
        INTO max_seq
        FROM public.purchase_return_entries
        WHERE (p_fy IS NULL OR p_fy = '' OR financial_year = p_fy)
          AND (COALESCE(is_deleted::text, '0') NOT IN ('1', 'true'));
    ELSIF p_table = 'stock_adjustments' THEN
        SELECT COALESCE(MAX(CAST(NULLIF(SUBSTRING(entry_no FROM '[0-9]+$'), '') AS INT)), 0)
        INTO max_seq
        FROM public.stock_adjustments
        WHERE (p_fy IS NULL OR p_fy = '' OR financial_year = p_fy)
          AND (COALESCE(is_deleted::text, '0') NOT IN ('1', 'true'));
    END IF;

    RETURN max_seq;
END;
$$;

REVOKE ALL ON FUNCTION public.get_max_entry_sequence(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_max_entry_sequence(TEXT, TEXT, TEXT) TO anon, authenticated, service_role;

-- 5. FUNCTION: ALLOCATE ENTRY SEQUENCE (ATOMIC LOCKING ACROSS PCS)
CREATE OR REPLACE FUNCTION public.allocate_entry_sequence(
    p_table TEXT,
    p_fy TEXT,
    p_prefix TEXT DEFAULT ''
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_voucher_key TEXT;
    v_last_seq INT := 0;
    v_max_existing INT := 0;
    v_allocated INT := 0;
    v_clean_fy TEXT := COALESCE(p_fy, '');
    v_clean_prefix TEXT := COALESCE(p_prefix, '');
BEGIN
    SET LOCAL lock_timeout = '3s';
    v_voucher_key := p_table || CASE WHEN v_clean_prefix <> '' THEN '_' || v_clean_prefix ELSE '' END;

    INSERT INTO public.voucher_sequences (voucher_type, financial_year, last_sequence, updated_at)
    VALUES (v_voucher_key, v_clean_fy, 0, NOW())
    ON CONFLICT (voucher_type, financial_year) DO NOTHING;

    SELECT last_sequence INTO v_last_seq
    FROM public.voucher_sequences
    WHERE voucher_type = v_voucher_key AND financial_year = v_clean_fy
    FOR UPDATE;

    v_max_existing := public.get_max_entry_sequence(p_table, v_clean_fy, v_clean_prefix);

    -- Sequence alignment: Never allow voucher_sequences to create artificial sequence gaps
    IF v_max_existing = 0 THEN
        v_last_seq := 0;
    ELSIF v_last_seq < v_max_existing OR v_last_seq > v_max_existing THEN
        v_last_seq := v_max_existing;
    END IF;

    v_allocated := v_last_seq + 1;

    UPDATE public.voucher_sequences
    SET last_sequence = v_allocated, updated_at = NOW()
    WHERE voucher_type = v_voucher_key AND financial_year = v_clean_fy;

    RETURN v_allocated;
END;
$$;

REVOKE ALL ON FUNCTION public.allocate_entry_sequence(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.allocate_entry_sequence(TEXT, TEXT, TEXT) TO anon, authenticated, service_role;

-- 6. CLEAN UP TEST ENTRIES (Delete corrupt test entries 10 & 11)
DELETE FROM public.purchase_items WHERE entry_no IN ('10', '11');
DELETE FROM public.purchase_entries WHERE entry_no IN ('10', '11');

-- 7. RESET PURCHASE SEQUENCE COUNTER TO 0 (So next entries start at 1, 2, ...)
INSERT INTO public.voucher_sequences (voucher_type, financial_year, last_sequence, updated_at)
VALUES ('purchase_entries', '2026-27', 0, NOW())
ON CONFLICT (voucher_type, financial_year)
DO UPDATE SET last_sequence = 0, updated_at = NOW();

-- 8. REFRESH SUPABASE POSTGREST SCHEMA CACHE (Fixes PGRST204 immediately)
NOTIFY pgrst, 'reload schema';
