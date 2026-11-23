-- ============================================================================
-- SUPABASE POSTGRESQL NUMERIC MAXIMUM SEQUENCE & ATOMIC ALLOCATION FIX
-- 1. Eliminates Text-Sorting Order Bugs (e.g., "9" > "10" or "99" > "100")
-- 2. Supports both BOOLEAN and INTEGER is_deleted columns across all tables
-- 3. Provides Pre-Save Cloud Atomic Sequence Lock via allocate_entry_sequence()
-- ============================================================================

-- 1. CLOUD VOUCHER SEQUENCES TRACKING TABLE
CREATE TABLE IF NOT EXISTS public.voucher_sequences (
    voucher_type TEXT NOT NULL,
    financial_year TEXT NOT NULL,
    last_sequence INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (voucher_type, financial_year)
);

CREATE INDEX IF NOT EXISTS idx_voucher_sequences_lookup
ON public.voucher_sequences(voucher_type, financial_year);

GRANT ALL ON TABLE public.voucher_sequences TO anon, authenticated, service_role;

-- 2. NUMERIC MAXIMUM ENTRY SEQUENCE CALCULATOR
CREATE OR REPLACE FUNCTION public.get_max_entry_sequence(
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
    ELSIF p_table = 'stock_write_offs' THEN
        SELECT COALESCE(MAX(CAST(NULLIF(SUBSTRING(entry_no FROM '[0-9]+$'), '') AS INT)), 0)
        INTO max_seq
        FROM public.stock_write_offs
        WHERE (p_fy IS NULL OR p_fy = '' OR financial_year = p_fy)
          AND (COALESCE(is_deleted::text, '0') NOT IN ('1', 'true'));
    END IF;

    RETURN max_seq;
END;
$$;

REVOKE ALL ON FUNCTION public.get_max_entry_sequence(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_max_entry_sequence(TEXT, TEXT, TEXT) TO anon, authenticated, service_role;

-- 3. PRE-SAVE CLOUD ATOMIC SEQUENCE ALLOCATOR (LOCK & CLAIM)
-- Guarantees two machines can never claim the same entry number simultaneously
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

    -- Ensure row exists for this voucher type and FY
    INSERT INTO public.voucher_sequences (voucher_type, financial_year, last_sequence, updated_at)
    VALUES (v_voucher_key, v_clean_fy, 0, NOW())
    ON CONFLICT (voucher_type, financial_year) DO NOTHING;

    -- Acquire exclusive row lock to serialize concurrent requests
    SELECT last_sequence INTO v_last_seq
    FROM public.voucher_sequences
    WHERE voucher_type = v_voucher_key AND financial_year = v_clean_fy
    FOR UPDATE;

    -- Safeguard: check the true maximum number currently committed in the target table
    v_max_existing := public.get_max_entry_sequence(p_table, v_clean_fy, v_clean_prefix);

    -- Sequence alignment: Never allow voucher_sequences to create artificial sequence gaps
    IF v_max_existing = 0 THEN
        v_last_seq := 0;
    ELSIF v_last_seq < v_max_existing OR v_last_seq > v_max_existing THEN
        v_last_seq := v_max_existing;
    END IF;

    v_allocated := v_last_seq + 1;

    -- Update sequence table atomically
    UPDATE public.voucher_sequences
    SET last_sequence = v_allocated, updated_at = NOW()
    WHERE voucher_type = v_voucher_key AND financial_year = v_clean_fy;

    RETURN v_allocated;
END;
$$;

REVOKE ALL ON FUNCTION public.allocate_entry_sequence(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.allocate_entry_sequence(TEXT, TEXT, TEXT) TO anon, authenticated, service_role;
