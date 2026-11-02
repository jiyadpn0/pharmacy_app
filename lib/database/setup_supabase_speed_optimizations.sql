-- =========================================================================
-- PHARMA PRO ERP - SUPABASE MULTI-TERMINAL ENTERPRISE OPTIMIZATION SCRIPT
-- Copy and run this entire script in Supabase Dashboard -> SQL Editor
-- =========================================================================

-- =========================================================================
-- STEP 1: DROP OVERLOADED FUNCTIONS (FIXES PGRST203 AMBIGUITY ERRORS)
-- =========================================================================
DROP FUNCTION IF EXISTS public.fn_next_sequence_number(text, text);
DROP FUNCTION IF EXISTS public.fn_next_sequence_number(text);
DROP FUNCTION IF EXISTS public.fn_save_sale_invoice_atomic(jsonb, jsonb);

-- =========================================================================
-- STEP 2: TIMESTAMP TRIGGER FOR DELTA CATCH-UP SYNC
-- =========================================================================
CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add updated_at & terminal_id columns if missing
ALTER TABLE stock_batches ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();
ALTER TABLE product_master ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();
ALTER TABLE purchase_entries ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

ALTER TABLE stock_batches ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'PC_1';
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'PC_1';
ALTER TABLE product_master ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'PC_1';
ALTER TABLE purchase_entries ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'PC_1';

-- Attach updated_at triggers
DROP TRIGGER IF EXISTS set_updated_at_stock_batches ON stock_batches;
CREATE TRIGGER set_updated_at_stock_batches
BEFORE UPDATE ON stock_batches
FOR EACH ROW EXECUTE PROCEDURE update_modified_column();

DROP TRIGGER IF EXISTS set_updated_at_sales_invoices ON sales_invoices;
CREATE TRIGGER set_updated_at_sales_invoices
BEFORE UPDATE ON sales_invoices
FOR EACH ROW EXECUTE PROCEDURE update_modified_column();

DROP TRIGGER IF EXISTS set_updated_at_product_master ON product_master;
CREATE TRIGGER set_updated_at_product_master
BEFORE UPDATE ON product_master
FOR EACH ROW EXECUTE PROCEDURE update_modified_column();

-- =========================================================================
-- 2. ATOMIC VOUCHER SEQUENCE RESERVATION RPC (Sub-millisecond Sequence Safety for 3-4 PCs)
-- =========================================================================
CREATE OR REPLACE FUNCTION fn_next_sequence_number(
    p_table TEXT,
    p_fy TEXT
) RETURNS TEXT AS $$
DECLARE
    v_max INT := 0;
BEGIN
    -- Transaction advisory lock to guarantee sequence isolation without FOR UPDATE aggregate syntax errors
    PERFORM pg_advisory_xact_lock(hashtext(p_table || '_' || p_fy));

    IF p_table = 'sales_invoices' THEN
        SELECT COALESCE(MAX(
            CASE
                WHEN POSITION('-' IN entry_no) > 0 THEN
                    REGEXP_REPLACE(reverse(split_part(reverse(entry_no), '-', 1)), '[^0-9]', '', 'g')::INT
                WHEN POSITION('_' IN entry_no) > 0 THEN
                    REGEXP_REPLACE(split_part(entry_no, '_', 2), '[^0-9]', '', 'g')::INT
                ELSE
                    REGEXP_REPLACE(entry_no, '[^0-9]', '', 'g')::INT
            END
        ), 0) INTO v_max FROM sales_invoices WHERE financial_year = p_fy;
    ELSIF p_table = 'purchase_entries' THEN
        SELECT COALESCE(MAX(
            CASE
                WHEN POSITION('-' IN entry_no) > 0 THEN
                    REGEXP_REPLACE(reverse(split_part(reverse(entry_no), '-', 1)), '[^0-9]', '', 'g')::INT
                WHEN POSITION('_' IN entry_no) > 0 THEN
                    REGEXP_REPLACE(split_part(entry_no, '_', 2), '[^0-9]', '', 'g')::INT
                ELSE
                    REGEXP_REPLACE(entry_no, '[^0-9]', '', 'g')::INT
            END
        ), 0) INTO v_max FROM purchase_entries WHERE financial_year = p_fy;
    ELSIF p_table = 'sales_return_invoices' THEN
        SELECT COALESCE(MAX(
            CASE
                WHEN POSITION('-' IN entry_no) > 0 THEN
                    REGEXP_REPLACE(reverse(split_part(reverse(entry_no), '-', 1)), '[^0-9]', '', 'g')::INT
                WHEN POSITION('_' IN entry_no) > 0 THEN
                    REGEXP_REPLACE(split_part(entry_no, '_', 2), '[^0-9]', '', 'g')::INT
                ELSE
                    REGEXP_REPLACE(entry_no, '[^0-9]', '', 'g')::INT
            END
        ), 0) INTO v_max FROM sales_return_invoices WHERE financial_year = p_fy;
    ELSIF p_table = 'purchase_return_entries' THEN
        SELECT COALESCE(MAX(
            CASE
                WHEN POSITION('-' IN entry_no) > 0 THEN
                    REGEXP_REPLACE(reverse(split_part(reverse(entry_no), '-', 1)), '[^0-9]', '', 'g')::INT
                WHEN POSITION('_' IN entry_no) > 0 THEN
                    REGEXP_REPLACE(split_part(entry_no, '_', 2), '[^0-9]', '', 'g')::INT
                ELSE
                    REGEXP_REPLACE(entry_no, '[^0-9]', '', 'g')::INT
            END
        ), 0) INTO v_max FROM purchase_return_entries WHERE financial_year = p_fy;
    ELSE
        RETURN NULL;
    END IF;

    RETURN (v_max + 1)::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =========================================================================
-- 3. BULK JSON PRODUCT IMPORT RPC (Sub-second catalog & price list imports)
-- =========================================================================
CREATE OR REPLACE FUNCTION fn_bulk_import_products(p_data JSONB)
RETURNS VOID AS $$
BEGIN
    INSERT INTO product_master (id, name, packing, mrp, sale_price, purchase_rate, category_id, rack_id, hsn_code, gst_percent)
    SELECT
        (x->>'id'),
        (x->>'name'),
        COALESCE((x->>'pack_size')::INT, (x->>'packing')::INT, 1),
        COALESCE((x->>'mrp')::NUMERIC, 0.0),
        COALESCE((x->>'sale_price')::NUMERIC, 0.0),
        COALESCE((x->>'purchase_rate')::NUMERIC, 0.0),
        COALESCE(x->>'category_id', 'General'),
        COALESCE(x->>'rack_id', ''),
        COALESCE(x->>'hsn_code', ''),
        COALESCE((x->>'gst_percent')::NUMERIC, 12.0)
    FROM jsonb_array_elements(p_data) AS x
    ON CONFLICT (id) DO UPDATE
    SET
        mrp = EXCLUDED.mrp,
        sale_price = EXCLUDED.sale_price,
        purchase_rate = EXCLUDED.purchase_rate,
        updated_at = NOW()
    WHERE EXCLUDED.updated_at >= product_master.updated_at;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =========================================================================
-- 4. HIGH-SPEED COMPOUND QUERY INDEXES & NON-NEGATIVE STOCK CONSTRAINT
-- =========================================================================
CREATE INDEX IF NOT EXISTS idx_sales_invoices_fast ON sales_invoices(financial_year, terminal_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_stock_batches_fast ON stock_batches(financial_year, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_product_master_fast ON product_master(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_sales_invoices_lookup ON sales_invoices(store_branch_id, financial_year, entry_no);
CREATE INDEX IF NOT EXISTS idx_stock_batches_search ON stock_batches(product_id, expiry_date, current_quantity);
CREATE INDEX IF NOT EXISTS idx_product_master_name ON product_master(name);
CREATE INDEX IF NOT EXISTS idx_product_master_updated ON product_master(updated_at DESC);

-- Enforce database-level non-negative stock constraint to prevent overselling race conditions across terminals
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'chk_stock_non_negative' AND table_name = 'stock_batches'
    ) THEN
        ALTER TABLE stock_batches ADD CONSTRAINT chk_stock_non_negative CHECK (current_quantity >= 0);
    END IF;
END $$;

-- =========================================================================
-- 5. REALTIME WEBSOCKET BROADCAST PUBLICATION & SPEED OPTIMIZATIONS
-- =========================================================================

-- Enable RLS and consolidate all policies into a single clean policy per table
DO $$
DECLARE
    pol RECORD;
    tbl text;
BEGIN
    FOR pol IN
        SELECT policyname, tablename
        FROM pg_policies
        WHERE schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I;', pol.policyname, pol.tablename);
    END LOOP;

    FOR tbl IN
        SELECT tablename FROM pg_tables WHERE schemaname = 'public'
    LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', tbl);
        -- Fail closed until a reviewed per-table tenant/user policy is added.
        EXECUTE format('CREATE POLICY open_access_policy ON public.%I FOR ALL TO authenticated USING (false) WITH CHECK (false);', tbl);
    END LOOP;
END $$;

-- Drop duplicate indexes on product_master to accelerate writes
DROP INDEX IF EXISTS public.idx_product_master_name_dup;
DROP INDEX IF EXISTS public.idx_product_master_barcode_dup;
DROP INDEX IF EXISTS public.idx_pm_name;
DROP INDEX IF EXISTS public.idx_product_name;
DROP INDEX IF EXISTS public.idx_prod_master_name;
DROP INDEX IF EXISTS public.idx_pm_barcode;
DROP INDEX IF EXISTS public.idx_product_barcode;
DROP INDEX IF EXISTS public.idx_product_master_name;
DROP INDEX IF EXISTS public.idx_product_master_barcode;

-- Create clean single indexes on foreign keys to accelerate joins & WAL streaming
CREATE INDEX IF NOT EXISTS idx_sales_items_fk_inv ON public.sales_items(invoice_no);
CREATE INDEX IF NOT EXISTS idx_purchase_items_fk_entry ON public.purchase_items(entry_no);
CREATE INDEX IF NOT EXISTS idx_sales_ret_items_fk ON public.sales_return_items(return_no);
CREATE INDEX IF NOT EXISTS idx_purchase_ret_items_fk ON public.purchase_return_items(entry_no);
CREATE INDEX IF NOT EXISTS idx_stock_adj_items_fk ON public.stock_adjustment_items(adjustment_no);
CREATE INDEX IF NOT EXISTS idx_prescription_items_fk ON public.prescription_items(prescription_id);
CREATE INDEX IF NOT EXISTS idx_stock_batches_fk_prod ON public.stock_batches(product_id);

-- Set REPLICA IDENTITY FULL for all Realtime tables
ALTER TABLE public.sales_invoices REPLICA IDENTITY FULL;
ALTER TABLE public.sales_items REPLICA IDENTITY FULL;
ALTER TABLE public.purchase_entries REPLICA IDENTITY FULL;
ALTER TABLE public.purchase_items REPLICA IDENTITY FULL;
ALTER TABLE public.product_master REPLICA IDENTITY FULL;
ALTER TABLE public.stock_batches REPLICA IDENTITY FULL;
ALTER TABLE public.stock_adjustments REPLICA IDENTITY FULL;
ALTER TABLE public.sales_return_invoices REPLICA IDENTITY FULL;
ALTER TABLE public.sales_return_items REPLICA IDENTITY FULL;
ALTER TABLE public.purchase_return_entries REPLICA IDENTITY FULL;
ALTER TABLE public.purchase_return_items REPLICA IDENTITY FULL;

-- Fix Function Search Path Mutable warning and secure execution
ALTER FUNCTION public.update_modified_column SET search_path = public;
ALTER FUNCTION public.fn_next_sequence_number SET search_path = public;
ALTER FUNCTION public.fn_bulk_import_products SET search_path = public;

-- Publish all 11 core ERP tables to Supabase Realtime publication
DO $$
DECLARE
    t text;
    realtime_tables text[] := ARRAY[
        'sales_invoices', 'sales_items',
        'purchase_entries', 'purchase_items',
        'product_master', 'stock_batches', 'stock_adjustments',
        'sales_return_invoices', 'sales_return_items',
        'purchase_return_entries', 'purchase_return_items'
    ];
BEGIN
    FOR i IN 1..array_length(realtime_tables, 1) LOOP
        t := realtime_tables[i];
        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_tables
            WHERE pubname = 'supabase_realtime' AND tablename = t
        ) THEN
            EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I;', t);
        END IF;
    END LOOP;
END $$;
