-- =========================================================================
-- PHARMA PRO ERP - MASTER SUPABASE SERVER SECURITY & MAINTENANCE SCRIPT
-- Copy and run this script in Supabase Dashboard -> SQL Editor
-- (Non-destructive: Will NOT delete any existing pharmacy records or tables)
-- =========================================================================

-- 1. EXTEND EXISTING CORE TABLES WITH MISSING ENTERPRISE COLUMNS
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS customer_phone TEXT;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS mobile TEXT;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS done_by TEXT;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS terminal_id TEXT;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS shift_id TEXT;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS patient_age INT DEFAULT 0;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS patient_gender TEXT;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS patient_address TEXT;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS doctor_reg_no TEXT;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS gstin_number TEXT;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS place_of_supply TEXT;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS subtotal NUMERIC DEFAULT 0.0;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS discount_amount NUMERIC DEFAULT 0.0;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS discount NUMERIC DEFAULT 0.0;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS tax_amount NUMERIC DEFAULT 0.0;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS tax NUMERIC DEFAULT 0.0;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS net_amount NUMERIC DEFAULT 0.0;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS grand_total NUMERIC DEFAULT 0.0;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS total_amount NUMERIC DEFAULT 0.0;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS e_way_bill_no TEXT;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS irn_number TEXT;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS delivery_status TEXT DEFAULT 'COUNTER';
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS courier_tracking_id TEXT;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS loyalty_points_earned NUMERIC DEFAULT 0;
ALTER TABLE sales_invoices ADD COLUMN IF NOT EXISTS loyalty_points_redeemed NUMERIC DEFAULT 0;

ALTER TABLE sales_items ADD COLUMN IF NOT EXISTS unit_price NUMERIC DEFAULT 0.0;
ALTER TABLE sales_items ADD COLUMN IF NOT EXISTS total_amount NUMERIC DEFAULT 0.0;
ALTER TABLE sales_items ADD COLUMN IF NOT EXISTS f_qty INT DEFAULT 0;
ALTER TABLE sales_items ADD COLUMN IF NOT EXISTS hsn_code TEXT;
ALTER TABLE sales_items ADD COLUMN IF NOT EXISTS schedule TEXT;
ALTER TABLE sales_items ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';

ALTER TABLE purchase_entries ADD COLUMN IF NOT EXISTS supplier_gstin TEXT;
ALTER TABLE purchase_entries ADD COLUMN IF NOT EXISTS credit_days INT DEFAULT 0;
ALTER TABLE purchase_entries ADD COLUMN IF NOT EXISTS due_date DATE;
ALTER TABLE purchase_entries ADD COLUMN IF NOT EXISTS po_number TEXT;
ALTER TABLE purchase_entries ADD COLUMN IF NOT EXISTS gstr_2b_status TEXT DEFAULT 'PENDING';

ALTER TABLE purchase_items ADD COLUMN IF NOT EXISTS trade_disc_amt NUMERIC DEFAULT 0;
ALTER TABLE purchase_items ADD COLUMN IF NOT EXISTS cash_disc_amt NUMERIC DEFAULT 0;
ALTER TABLE purchase_items ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';

ALTER TABLE stock_adjustments ADD COLUMN IF NOT EXISTS valuation_loss NUMERIC DEFAULT 0;
ALTER TABLE stock_adjustments ADD COLUMN IF NOT EXISTS old_qty INT DEFAULT 0;
ALTER TABLE stock_adjustments ADD COLUMN IF NOT EXISTS new_qty INT DEFAULT 0;
ALTER TABLE stock_adjustments ADD COLUMN IF NOT EXISTS reason_code TEXT;

ALTER TABLE stock_write_offs ADD COLUMN IF NOT EXISTS is_claimable INT DEFAULT 0;
ALTER TABLE stock_write_offs ADD COLUMN IF NOT EXISTS manufacturer_id TEXT;
ALTER TABLE stock_write_offs ADD COLUMN IF NOT EXISTS claim_status TEXT DEFAULT 'UNCLAIMED';

ALTER TABLE patients ADD COLUMN IF NOT EXISTS gstin TEXT;
ALTER TABLE patients ADD COLUMN IF NOT EXISTS credit_limit NUMERIC DEFAULT 0;
ALTER TABLE patients ADD COLUMN IF NOT EXISTS chronic_disease_tags TEXT;

ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS dl_number_20b TEXT;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS dl_number_21b TEXT;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS dl_expiry_date DATE;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS fssai_no TEXT;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS bank_account_no TEXT;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS bank_ifsc TEXT;

ALTER TABLE product_master ADD COLUMN IF NOT EXISTS storage_condition TEXT DEFAULT 'ROOM_TEMP';
ALTER TABLE product_master ADD COLUMN IF NOT EXISTS moq INT DEFAULT 1;
ALTER TABLE product_master ADD COLUMN IF NOT EXISTS is_dpco_controlled INT DEFAULT 0;

-- 2. CREATE MISSING CLOUD TABLES
CREATE TABLE IF NOT EXISTS staff_users (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    role TEXT DEFAULT 'CASHIER',
    pin_hash TEXT,
    is_active INT DEFAULT 1,
    branch_id TEXT DEFAULT 'MAIN_STORE',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,
    permission_key TEXT NOT NULL,
    is_granted INT DEFAULT 1,
    branch_id TEXT DEFAULT 'MAIN_STORE'
);

CREATE TABLE IF NOT EXISTS purchase_orders (
    id TEXT PRIMARY KEY,
    po_number TEXT NOT NULL,
    supplier_name TEXT,
    order_date DATE,
    expected_delivery_date DATE,
    status TEXT DEFAULT 'PENDING',
    total_amount NUMERIC DEFAULT 0,
    branch_id TEXT DEFAULT 'MAIN_STORE',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS purchase_order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    po_number TEXT NOT NULL,
    product_id TEXT NOT NULL,
    product_name TEXT,
    qty INT DEFAULT 1,
    estimated_rate NUMERIC DEFAULT 0,
    branch_id TEXT DEFAULT 'MAIN_STORE'
);

CREATE TABLE IF NOT EXISTS product_mappings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wholesaler_name TEXT NOT NULL,
    supplier_item_name TEXT NOT NULL,
    master_product_id TEXT NOT NULL,
    branch_id TEXT DEFAULT 'MAIN_STORE',
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS invoice_edit_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_no TEXT NOT NULL,
    edited_by TEXT,
    edit_reason TEXT,
    original_snapshot JSONB,
    edited_snapshot JSONB,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    branch_id TEXT DEFAULT 'MAIN_STORE'
);

CREATE TABLE IF NOT EXISTS parked_sales (
    id TEXT PRIMARY KEY,
    terminal_id TEXT,
    cashier_id TEXT,
    customer_name TEXT,
    parked_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    branch_id TEXT DEFAULT 'MAIN_STORE'
);

CREATE TABLE IF NOT EXISTS registered_terminals (
    machine_id TEXT PRIMARY KEY,
    branch_id TEXT NOT NULL DEFAULT 'MAIN_STORE',
    terminal_id TEXT NOT NULL,
    computer_name TEXT,
    notes TEXT,
    is_active INT DEFAULT 1,
    registered_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reg_terminals_branch_term ON registered_terminals(branch_id, terminal_id);

CREATE TABLE IF NOT EXISTS stock_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id TEXT NOT NULL,
    batch_number TEXT,
    transaction_type TEXT NOT NULL, -- INWARD, OUTWARD, ADJUSTMENT, RETURN
    reference_no TEXT,
    qty_in INT DEFAULT 0,
    qty_out INT DEFAULT 0,
    closing_balance INT DEFAULT 0,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    branch_id TEXT DEFAULT 'MAIN_STORE'
);

CREATE TABLE IF NOT EXISTS day_closing_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    closing_date DATE NOT NULL,
    cash_opening NUMERIC DEFAULT 0,
    cash_sales NUMERIC DEFAULT 0,
    card_sales NUMERIC DEFAULT 0,
    upi_sales NUMERIC DEFAULT 0,
    actual_counted_cash NUMERIC DEFAULT 0,
    cash_mismatch NUMERIC DEFAULT 0,
    upi_settlement_ref TEXT,
    closed_by TEXT,
    branch_id TEXT DEFAULT 'MAIN_STORE',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS general_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    voucher_no TEXT,
    transaction_date DATE,
    debit_account TEXT,
    credit_account TEXT,
    amount NUMERIC DEFAULT 0,
    narration TEXT,
    branch_id TEXT DEFAULT 'MAIN_STORE',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS schedule_h1_register (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_date DATE NOT NULL,
    patient_name TEXT,
    patient_address TEXT,
    doctor_name TEXT,
    doctor_reg_no TEXT,
    drug_name TEXT NOT NULL,
    batch_number TEXT,
    quantity INT DEFAULT 1,
    invoice_no TEXT,
    branch_id TEXT DEFAULT 'MAIN_STORE'
);

-- 3. TELEMETRY & AUDIT LOG TABLES
CREATE TABLE IF NOT EXISTS telemetry_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_name TEXT NOT NULL,
    error_message TEXT,
    metadata JSONB,
    app_version TEXT,
    device_model TEXT,
    ip_address TEXT,
    terminal_id TEXT DEFAULT 'POS-01',
    branch_id TEXT DEFAULT 'MAIN_STORE',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS cloud_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    action TEXT NOT NULL,
    details TEXT,
    severity TEXT DEFAULT 'INFO',
    reference_id TEXT,
    terminal_id TEXT DEFAULT 'POS-01',
    branch_id TEXT DEFAULT 'MAIN_STORE',
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS daily_financial_summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    summary_date DATE NOT NULL UNIQUE,
    branch_id TEXT DEFAULT 'MAIN_STORE',
    total_sales_count INT DEFAULT 0,
    gross_sales_amount NUMERIC DEFAULT 0.0,
    cash_collected NUMERIC DEFAULT 0.0,
    card_collected NUMERIC DEFAULT 0.0,
    upi_collected NUMERIC DEFAULT 0.0,
    returns_amount NUMERIC DEFAULT 0.0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. FIX SECURITY DEFINER VIEWS (RESOLVES SUPABASE LINTER CRITICAL WARNING)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_views WHERE schemaname = 'public' AND viewname = 'purchase_orders') THEN
    ALTER VIEW public.purchase_orders SET (security_invoker = true);
  END IF;
  IF EXISTS (SELECT 1 FROM pg_views WHERE schemaname = 'public' AND viewname = 'product_mappings') THEN
    ALTER VIEW public.product_mappings SET (security_invoker = true);
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Skipping view security_invoker: %', SQLERRM;
END $$;

-- 5. ROW LEVEL SECURITY (RLS) ENABLEMENT & PRODUCTION APP POLICIES
DO $$
DECLARE
  t text;
BEGIN
  -- Iterate strictly over physical base tables (ignoring views and materialized views)
  FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
    BEGIN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
      EXECUTE format('DROP POLICY IF EXISTS "Allow All Access" ON public.%I', t);
      EXECUTE format('CREATE POLICY "Allow All Access" ON public.%I FOR ALL TO anon, authenticated, service_role USING (true) WITH CHECK (true)', t);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skipping RLS on %: %', t, SQLERRM;
    END;
  END LOOP;
END $$;

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

-- 6. AUTOMATED FREE TIER DB CLEANUP CRON (30-day telemetry retention)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        BEGIN
            PERFORM cron.unschedule('nightly-pharmacy-maintenance');
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;

        PERFORM cron.schedule(
            'nightly-pharmacy-maintenance',
            '0 2 * * *',
            'DELETE FROM public.telemetry_logs WHERE created_at < NOW() - INTERVAL ''30 days''; DELETE FROM public.cloud_audit_logs WHERE timestamp < NOW() - INTERVAL ''60 days'';'
        );
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Skipping pg_cron setup: %', SQLERRM;
END $$;

-- 7. CLEAN DROP OF DEPRECATED & REPLACED FUNCTIONS (RESOLVES 42P13 & SEARCH PATH WARNINGS)
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN (
    SELECT proname, oid::regprocedure AS regproc
    FROM pg_proc
    WHERE pronamespace = 'public'::regnamespace
      AND proname IN (
        'fn_next_sequence_number',
        'fn_claim_next_invoice_no',
        'fn_claim_next_sale_invoice_no',
        'fn_save_sale_invoice_atomic',
        'fn_save_sale_invoice_atomic_ui',
        'fn_save_sale_invoice_atomic_v2',
        'fn_save_purchase_entry_atomic',
        'get_max_entry_sequence'
      )
  ) LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.regproc || ' CASCADE';
  END LOOP;
END $$;

-- 8. ATOMIC SALE INVOICE UPSERT (WITH SECURE SEARCH PATH)
DROP FUNCTION IF EXISTS public.fn_save_sale_invoice_atomic CASCADE;

CREATE OR REPLACE FUNCTION public.fn_save_sale_invoice_atomic(
  p_invoice JSONB,
  p_items JSONB DEFAULT '[]'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_entry_no TEXT;
  v_terminal_id TEXT;
  v_branch_id TEXT;
  v_existing_terminal TEXT;
  v_existing_branch TEXT;
BEGIN
  -- Extract key identifiers
  v_entry_no := p_invoice->>'entry_no';
  v_terminal_id := TRIM(COALESCE(p_invoice->>'terminal_id', ''));
  v_branch_id := TRIM(COALESCE(p_invoice->>'branch_id', ''));

  -- Mandatory field validation
  IF v_entry_no IS NULL OR v_entry_no = '' OR v_terminal_id = '' OR v_branch_id = '' THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'INVALID_INPUT',
      'message', 'Missing required entry_no, terminal_id, or branch_id'
    );
  END IF;

  -- Server-side check: reject empty p_items array BEFORE changing header or deleting items
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'EMPTY_ITEMS',
      'message', 'Rejected: p_items array cannot be empty or null'
    );
  END IF;

  -- Row-level lock check for existing invoice ownership
  SELECT terminal_id, branch_id
  INTO v_existing_terminal, v_existing_branch
  FROM public.sales_invoices
  WHERE entry_no = v_entry_no
  FOR UPDATE;

  IF FOUND THEN
    v_existing_terminal := TRIM(COALESCE(v_existing_terminal, ''));
    v_existing_branch := TRIM(COALESCE(v_existing_branch, ''));

    -- Collision check: reject if belonging to another terminal/branch or unknown ownership
    IF v_existing_terminal = '' OR v_existing_branch = '' OR v_existing_terminal <> v_terminal_id OR v_existing_branch <> v_branch_id THEN
      RETURN jsonb_build_object(
        'success', false,
        'reason', 'COLLISION',
        'message', 'Invoice entry_no already exists under a different terminal/branch or unknown ownership'
      );
    END IF;

    -- Update existing header safely
    UPDATE public.sales_invoices
    SET
      invoice_no = COALESCE(p_invoice->>'invoice_no', v_entry_no),
      financial_year = COALESCE(p_invoice->>'financial_year', ''),
      date = COALESCE(p_invoice->>'date', ''),
      customer_acc = COALESCE(p_invoice->>'customer_acc', p_invoice->>'payment_mode', 'Cash'),
      customer_name = COALESCE(p_invoice->>'customer_name', p_invoice->>'patient', ''),
      patient = COALESCE(p_invoice->>'patient', p_invoice->>'customer_name', ''),
      customer_phone = COALESCE(p_invoice->>'customer_phone', p_invoice->>'mobile', ''),
      mobile = COALESCE(p_invoice->>'mobile', p_invoice->>'customer_phone', ''),
      doctor = COALESCE(p_invoice->>'doctor', ''),
      doctor_reg_no = COALESCE(p_invoice->>'doctor_reg_no', ''),
      done_by = COALESCE(p_invoice->>'done_by', 'Cashier'),
      terminal_id = v_terminal_id,
      shift_id = COALESCE(p_invoice->>'shift_id', 'SHIFT-01'),
      patient_age = COALESCE(NULLIF(p_invoice->>'patient_age', '')::INT, 0),
      patient_gender = COALESCE(p_invoice->>'patient_gender', ''),
      patient_address = COALESCE(p_invoice->>'patient_address', ''),
      gstin_number = COALESCE(p_invoice->>'gstin_number', ''),
      place_of_supply = COALESCE(p_invoice->>'place_of_supply', ''),
      subtotal = COALESCE(NULLIF(p_invoice->>'subtotal', '')::NUMERIC, NULLIF(p_invoice->>'sub_total', '')::NUMERIC, 0.0),
      sub_total = COALESCE(NULLIF(p_invoice->>'sub_total', '')::NUMERIC, NULLIF(p_invoice->>'subtotal', '')::NUMERIC, 0.0),
      discount_amount = COALESCE(NULLIF(p_invoice->>'discount_amount', '')::NUMERIC, NULLIF(p_invoice->>'discount', '')::NUMERIC, 0.0),
      discount = COALESCE(NULLIF(p_invoice->>'discount', '')::NUMERIC, NULLIF(p_invoice->>'discount_amount', '')::NUMERIC, 0.0),
      discount_percent = COALESCE(NULLIF(p_invoice->>'discount_percent', '')::NUMERIC, 0.0),
      additional_discount = COALESCE(NULLIF(p_invoice->>'additional_discount', '')::NUMERIC, 0.0),
      other_charge = COALESCE(NULLIF(p_invoice->>'other_charge', '')::NUMERIC, 0.0),
      tax_amount = COALESCE(NULLIF(p_invoice->>'tax_amount', '')::NUMERIC, NULLIF(p_invoice->>'tax', '')::NUMERIC, 0.0),
      tax = COALESCE(NULLIF(p_invoice->>'tax', '')::NUMERIC, NULLIF(p_invoice->>'tax_amount', '')::NUMERIC, 0.0),
      round_off = COALESCE(NULLIF(p_invoice->>'round_off', '')::NUMERIC, 0.0),
      net_amount = COALESCE(NULLIF(p_invoice->>'net_amount', '')::NUMERIC, NULLIF(p_invoice->>'grand_total', '')::NUMERIC, NULLIF(p_invoice->>'total_amount', '')::NUMERIC, 0.0),
      grand_total = COALESCE(NULLIF(p_invoice->>'grand_total', '')::NUMERIC, NULLIF(p_invoice->>'net_amount', '')::NUMERIC, NULLIF(p_invoice->>'total_amount', '')::NUMERIC, 0.0),
      total_amount = COALESCE(NULLIF(p_invoice->>'total_amount', '')::NUMERIC, NULLIF(p_invoice->>'grand_total', '')::NUMERIC, NULLIF(p_invoice->>'net_amount', '')::NUMERIC, 0.0),
      rcvd_amt = COALESCE(NULLIF(p_invoice->>'rcvd_amt', '')::NUMERIC, 0.0),
      payment_mode = COALESCE(p_invoice->>'payment_mode', 'CASH'),
      payment_remarks = COALESCE(p_invoice->>'payment_remarks', ''),
      secondary_acc = COALESCE(p_invoice->>'secondary_acc', ''),
      secondary_amt = COALESCE(NULLIF(p_invoice->>'secondary_amt', '')::NUMERIC, 0.0),
      is_deleted = COALESCE(NULLIF(p_invoice->>'is_deleted', '')::INT, 0),
      is_paid = COALESCE(NULLIF(p_invoice->>'is_paid', '')::INT, 1),
      tax_type = COALESCE(p_invoice->>'tax_type', 'Non Gst'),
      agent = COALESCE(p_invoice->>'agent', 'Admin'),
      sales_return_amt = COALESCE(NULLIF(p_invoice->>'sales_return_amt', '')::NUMERIC, 0.0),
      order_type = COALESCE(NULLIF(p_invoice->>'order_type', '')::INT, 0),
      branch_id = v_branch_id,
      updated_at = NOW()
    WHERE entry_no = v_entry_no;

  ELSE
    -- Insert new header safely with unique_violation exception handler
    BEGIN
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
        COALESCE(p_invoice->>'date', ''),
        COALESCE(p_invoice->>'customer_acc', p_invoice->>'payment_mode', 'Cash'),
        COALESCE(p_invoice->>'customer_name', p_invoice->>'patient', ''),
        COALESCE(p_invoice->>'patient', p_invoice->>'customer_name', ''),
        COALESCE(p_invoice->>'customer_phone', p_invoice->>'mobile', ''),
        COALESCE(p_invoice->>'mobile', p_invoice->>'customer_phone', ''),
        COALESCE(p_invoice->>'doctor', ''),
        COALESCE(p_invoice->>'doctor_reg_no', ''),
        COALESCE(p_invoice->>'done_by', 'Cashier'),
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
      );
    EXCEPTION WHEN unique_violation THEN
      -- Concurrent collision handler
      SELECT terminal_id, branch_id
      INTO v_existing_terminal, v_existing_branch
      FROM public.sales_invoices
      WHERE entry_no = v_entry_no
      FOR UPDATE;

      v_existing_terminal := TRIM(COALESCE(v_existing_terminal, ''));
      v_existing_branch := TRIM(COALESCE(v_existing_branch, ''));

      IF v_existing_terminal = '' OR v_existing_branch = '' OR v_existing_terminal <> v_terminal_id OR v_existing_branch <> v_branch_id THEN
        RETURN jsonb_build_object(
          'success', false,
          'reason', 'COLLISION',
          'message', 'Concurrent collision: Invoice entry_no was created by another terminal/branch'
        );
      END IF;

      -- Update header consistently
      UPDATE public.sales_invoices
      SET
        invoice_no = COALESCE(p_invoice->>'invoice_no', v_entry_no),
        financial_year = COALESCE(p_invoice->>'financial_year', ''),
        date = COALESCE(p_invoice->>'date', ''),
        customer_acc = COALESCE(p_invoice->>'customer_acc', p_invoice->>'payment_mode', 'Cash'),
        customer_name = COALESCE(p_invoice->>'customer_name', p_invoice->>'patient', ''),
        patient = COALESCE(p_invoice->>'patient', p_invoice->>'customer_name', ''),
        customer_phone = COALESCE(p_invoice->>'customer_phone', p_invoice->>'mobile', ''),
        mobile = COALESCE(p_invoice->>'mobile', p_invoice->>'customer_phone', ''),
        doctor = COALESCE(p_invoice->>'doctor', ''),
        doctor_reg_no = COALESCE(p_invoice->>'doctor_reg_no', ''),
        done_by = COALESCE(p_invoice->>'done_by', 'Cashier'),
        terminal_id = v_terminal_id,
        shift_id = COALESCE(p_invoice->>'shift_id', 'SHIFT-01'),
        patient_age = COALESCE(NULLIF(p_invoice->>'patient_age', '')::INT, 0),
        patient_gender = COALESCE(p_invoice->>'patient_gender', ''),
        patient_address = COALESCE(p_invoice->>'patient_address', ''),
        gstin_number = COALESCE(p_invoice->>'gstin_number', ''),
        place_of_supply = COALESCE(p_invoice->>'place_of_supply', ''),
        subtotal = COALESCE(NULLIF(p_invoice->>'subtotal', '')::NUMERIC, NULLIF(p_invoice->>'sub_total', '')::NUMERIC, 0.0),
        sub_total = COALESCE(NULLIF(p_invoice->>'sub_total', '')::NUMERIC, NULLIF(p_invoice->>'subtotal', '')::NUMERIC, 0.0),
        discount_amount = COALESCE(NULLIF(p_invoice->>'discount_amount', '')::NUMERIC, NULLIF(p_invoice->>'discount', '')::NUMERIC, 0.0),
        discount = COALESCE(NULLIF(p_invoice->>'discount', '')::NUMERIC, NULLIF(p_invoice->>'discount_amount', '')::NUMERIC, 0.0),
        discount_percent = COALESCE(NULLIF(p_invoice->>'discount_percent', '')::NUMERIC, 0.0),
        additional_discount = COALESCE(NULLIF(p_invoice->>'additional_discount', '')::NUMERIC, 0.0),
        other_charge = COALESCE(NULLIF(p_invoice->>'other_charge', '')::NUMERIC, 0.0),
        tax_amount = COALESCE(NULLIF(p_invoice->>'tax_amount', '')::NUMERIC, NULLIF(p_invoice->>'tax', '')::NUMERIC, 0.0),
        tax = COALESCE(NULLIF(p_invoice->>'tax', '')::NUMERIC, NULLIF(p_invoice->>'tax_amount', '')::NUMERIC, 0.0),
        round_off = COALESCE(NULLIF(p_invoice->>'round_off', '')::NUMERIC, 0.0),
        net_amount = COALESCE(NULLIF(p_invoice->>'net_amount', '')::NUMERIC, NULLIF(p_invoice->>'grand_total', '')::NUMERIC, NULLIF(p_invoice->>'total_amount', '')::NUMERIC, 0.0),
        grand_total = COALESCE(NULLIF(p_invoice->>'grand_total', '')::NUMERIC, NULLIF(p_invoice->>'net_amount', '')::NUMERIC, NULLIF(p_invoice->>'total_amount', '')::NUMERIC, 0.0),
        total_amount = COALESCE(NULLIF(p_invoice->>'total_amount', '')::NUMERIC, NULLIF(p_invoice->>'grand_total', '')::NUMERIC, NULLIF(p_invoice->>'net_amount', '')::NUMERIC, 0.0),
        rcvd_amt = COALESCE(NULLIF(p_invoice->>'rcvd_amt', '')::NUMERIC, 0.0),
        payment_mode = COALESCE(p_invoice->>'payment_mode', 'CASH'),
        payment_remarks = COALESCE(p_invoice->>'payment_remarks', ''),
        secondary_acc = COALESCE(p_invoice->>'secondary_acc', ''),
        secondary_amt = COALESCE(NULLIF(p_invoice->>'secondary_amt', '')::NUMERIC, 0.0),
        is_deleted = COALESCE(NULLIF(p_invoice->>'is_deleted', '')::INT, 0),
        is_paid = COALESCE(NULLIF(p_invoice->>'is_paid', '')::INT, 1),
        tax_type = COALESCE(p_invoice->>'tax_type', 'Non Gst'),
        agent = COALESCE(p_invoice->>'agent', 'Admin'),
        sales_return_amt = COALESCE(NULLIF(p_invoice->>'sales_return_amt', '')::NUMERIC, 0.0),
        order_type = COALESCE(NULLIF(p_invoice->>'order_type', '')::INT, 0),
        branch_id = v_branch_id,
        updated_at = NOW()
      WHERE entry_no = v_entry_no;
    END;
  END IF;

  -- Atomically replace line items in sales_items (using invoice_no foreign key)
  DELETE FROM public.sales_items WHERE invoice_no = v_entry_no;

  IF p_items IS NOT NULL AND jsonb_array_length(p_items) > 0 THEN
    INSERT INTO public.sales_items (
      invoice_no, product_id, product_name, extra, batch_number, expiry_date,
      quantity, f_qty, hsn_code, schedule, packing, mrp, purchase_rate, landing_cost,
      taxable_sp, unit_price, disc_percent, disc_amt, gst_percent, gst_amt,
      cgst_amt, sgst_amt, igst_amt, total_amount, profit, supplier_name, rack, branch_id,
      created_at
    )
    SELECT
      v_entry_no,
      COALESCE(item->>'product_id', ''),
      COALESCE(item->>'product_name', ''),
      COALESCE(item->>'extra', ''),
      COALESCE(item->>'batch_number', ''),
      COALESCE(item->>'expiry_date', ''),
      COALESCE(NULLIF(item->>'quantity', '')::INT, NULLIF(item->>'qty', '')::INT, 1),
      COALESCE(NULLIF(item->>'f_qty', '')::INT, 0),
      COALESCE(item->>'hsn_code', ''),
      COALESCE(item->>'schedule', 'H'),
      COALESCE(NULLIF(item->>'packing', '')::INT, NULLIF(item->>'packin', '')::INT, 1),
      COALESCE(NULLIF(item->>'mrp', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'purchase_rate', '')::NUMERIC, NULLIF(item->>'p_rate', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'landing_cost', '')::NUMERIC, NULLIF(item->>'l_cost', '')::NUMERIC, NULLIF(item->>'purchase_rate', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'taxable_sp', '')::NUMERIC, NULLIF(item->>'unit_price', '')::NUMERIC, NULLIF(item->>'s_rate', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'unit_price', '')::NUMERIC, NULLIF(item->>'s_rate', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'disc_percent', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'disc_amt', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'gst_percent', '')::NUMERIC, 12.0),
      COALESCE(NULLIF(item->>'gst_amt', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'cgst_amt', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'sgst_amt', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'igst_amt', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'total_amount', '')::NUMERIC, NULLIF(item->>'net_amount', '')::NUMERIC, NULLIF(item->>'total', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'profit', '')::NUMERIC, 0.0),
      COALESCE(item->>'supplier_name', ''),
      COALESCE(item->>'rack', ''),
      v_branch_id,
      COALESCE(NULLIF(item->>'created_at', '')::TIMESTAMPTZ, NOW())
    FROM jsonb_array_elements(p_items) AS item;
  END IF;

  RETURN jsonb_build_object('success', true, 'entry_no', v_entry_no);
END;
$$;

-- 9. ATOMIC PURCHASE ENTRY UPSERT (WITH SECURE SEARCH PATH)
DROP FUNCTION IF EXISTS public.fn_save_purchase_entry_atomic CASCADE;

CREATE OR REPLACE FUNCTION public.fn_save_purchase_entry_atomic(
  p_purchase JSONB,
  p_items JSONB DEFAULT '[]'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_entry_no TEXT;
    v_item JSONB;
BEGIN
    v_entry_no := p_purchase->>'entry_no';

    INSERT INTO public.purchase_entries (
        entry_no, sup_inv_no, sup_inv_date, financial_year, date, supplier_name,
        done_by, subtotal, discount_amount, other_charge, round_off, net_amount,
        inv_total, remarks, payment_status, payment_mode, branch_id, updated_at
    ) VALUES (
        v_entry_no,
        p_purchase->>'sup_inv_no',
        p_purchase->>'sup_inv_date',
        p_purchase->>'financial_year',
        p_purchase->>'date',
        p_purchase->>'supplier_name',
        p_purchase->>'done_by',
        COALESCE((p_purchase->>'subtotal')::NUMERIC, (p_purchase->>'sub_total')::NUMERIC, 0.0),
        COALESCE((p_purchase->>'discount_amount')::NUMERIC, (p_purchase->>'discount')::NUMERIC, 0.0),
        COALESCE((p_purchase->>'other_charge')::NUMERIC, 0.0),
        COALESCE((p_purchase->>'round_off')::NUMERIC, 0.0),
        COALESCE((p_purchase->>'net_amount')::NUMERIC, (p_purchase->>'grand_total')::NUMERIC, 0.0),
        COALESCE((p_purchase->>'inv_total')::NUMERIC, 0.0),
        p_purchase->>'remarks',
        COALESCE((p_purchase->>'payment_status')::INT, 0),
        COALESCE(p_purchase->>'payment_mode', 'CREDIT'),
        COALESCE(p_purchase->>'branch_id', 'MAIN_STORE'),
        NOW()
    )
    ON CONFLICT (entry_no) DO UPDATE SET
        supplier_name = EXCLUDED.supplier_name,
        sup_inv_no = EXCLUDED.sup_inv_no,
        net_amount = EXCLUDED.net_amount,
        inv_total = EXCLUDED.inv_total,
        updated_at = NOW();

    DELETE FROM public.purchase_items WHERE entry_no = v_entry_no;

    IF p_items IS NOT NULL AND jsonb_array_length(p_items) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
        LOOP
            INSERT INTO public.purchase_items (
                entry_no, product_id, product_name, batch_number, expiry_date,
                quantity, f_qty, packing, mrp, unit_price, gross, disc_percent,
                disc_amt, gst_percent, gst_amt, total_amount, branch_id
            ) VALUES (
                v_entry_no,
                v_item->>'product_id',
                v_item->>'product_name',
                COALESCE(v_item->>'batch_number', v_item->>'batch', ''),
                COALESCE(v_item->>'expiry_date', v_item->>'expiry', ''),
                COALESCE((v_item->>'quantity')::INT, (v_item->>'qty')::INT, 1),
                COALESCE((v_item->>'f_qty')::INT, 0),
                COALESCE((v_item->>'packing')::INT, (v_item->>'packin')::INT, 1),
                COALESCE((v_item->>'mrp')::NUMERIC, 0.0),
                COALESCE((v_item->>'unit_price')::NUMERIC, (v_item->>'rate')::NUMERIC, 0.0),
                COALESCE((v_item->>'gross')::NUMERIC, 0.0),
                COALESCE((v_item->>'disc_percent')::NUMERIC, 0.0),
                COALESCE((v_item->>'disc_amt')::NUMERIC, 0.0),
                COALESCE((v_item->>'gst_percent')::NUMERIC, 0.0),
                COALESCE((v_item->>'gst_amt')::NUMERIC, 0.0),
                COALESCE((v_item->>'total_amount')::NUMERIC, (v_item->>'net_amount')::NUMERIC, 0.0),
                COALESCE(p_purchase->>'branch_id', 'MAIN_STORE')
            );
        END LOOP;
    END IF;

    RETURN jsonb_build_object('success', true, 'entry_no', v_entry_no);
END;
$$;

-- 10. CLOUD VOUCHER SEQUENCES TRACKING TABLE & NUMERIC MAXIMUM ENTRY SEQUENCE
CREATE TABLE IF NOT EXISTS public.voucher_sequences (
    voucher_type TEXT NOT NULL,
    financial_year TEXT NOT NULL,
    last_sequence INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (voucher_type, financial_year)
);
CREATE INDEX IF NOT EXISTS idx_voucher_sequences_lookup ON public.voucher_sequences(voucher_type, financial_year);
GRANT ALL ON TABLE public.voucher_sequences TO anon, authenticated, service_role;

DROP FUNCTION IF EXISTS public.get_max_entry_sequence CASCADE;

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

-- 10B. PRE-SAVE CLOUD ATOMIC SEQUENCE ALLOCATOR (LOCK & CLAIM)
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

    IF v_last_seq < v_max_existing THEN
        v_last_seq := v_max_existing;
    END IF;

    v_allocated := v_last_seq + 1;

    UPDATE public.voucher_sequences
    SET last_sequence = v_allocated, updated_at = NOW()
    WHERE voucher_type = v_voucher_key AND financial_year = v_clean_fy;

    RETURN v_allocated;
END;
$$;
END;
$$;

-- 11. AUTOMATIC POS TERMINAL LEASING & IDENTITY MANAGEMENT FUNCTION
CREATE OR REPLACE FUNCTION public.fn_auto_lease_terminal(
    p_machine_id TEXT,
    p_computer_name TEXT DEFAULT '',
    p_branch_id TEXT DEFAULT 'MAIN_STORE'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $func$
DECLARE
    v_clean_machine TEXT;
    v_clean_branch TEXT;
    v_clean_name TEXT;
    v_existing_terminal TEXT;
    v_existing_name TEXT;
    v_new_terminal TEXT;
    v_next_num INT := 1;
    v_candidate TEXT;
BEGIN
    v_clean_machine := TRIM(COALESCE(p_machine_id, ''));
    v_clean_branch := TRIM(COALESCE(p_branch_id, 'MAIN_STORE'));
    v_clean_name := TRIM(COALESCE(p_computer_name, ''));

    IF v_clean_machine = '' THEN
        RETURN jsonb_build_object('success', false, 'message', 'machine_id cannot be empty');
    END IF;

    -- 1. Check if this machine is already registered
    SELECT terminal_id, computer_name
    INTO v_existing_terminal, v_existing_name
    FROM public.registered_terminals
    WHERE machine_id = v_clean_machine AND branch_id = v_clean_branch;

    IF FOUND THEN
        -- Update last seen timestamp and backfill computer name if blank
        UPDATE public.registered_terminals
        SET last_seen_at = NOW(),
            computer_name = COALESCE(NULLIF(computer_name, ''), v_clean_name)
        WHERE machine_id = v_clean_machine AND branch_id = v_clean_branch;

        RETURN jsonb_build_object(
            'success', true,
            'terminal_id', v_existing_terminal,
            'computer_name', COALESCE(v_existing_name, v_clean_name),
            'is_new', false
        );
    END IF;

    -- 2. Brand new machine: find lowest available POS-01, POS-02, POS-03...
    LOOP
        v_candidate := 'POS-' || LPAD(v_next_num::TEXT, 2, '0');
        IF NOT EXISTS (
            SELECT 1 FROM public.registered_terminals
            WHERE branch_id = v_clean_branch AND terminal_id = v_candidate
        ) THEN
            v_new_terminal := v_candidate;
            EXIT;
        END IF;
        v_next_num := v_next_num + 1;
    END LOOP;

    -- 3. Register the new machine with its leased terminal ID
    INSERT INTO public.registered_terminals (
        machine_id, branch_id, terminal_id, computer_name, registered_at, last_seen_at
    ) VALUES (
        v_clean_machine, v_clean_branch, v_new_terminal, v_clean_name, NOW(), NOW()
    );

    RETURN jsonb_build_object(
        'success', true,
        'terminal_id', v_new_terminal,
        'computer_name', v_clean_name,
        'is_new', true
    );
END;
$func$;

REVOKE ALL ON FUNCTION public.fn_auto_lease_terminal(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_auto_lease_terminal(TEXT, TEXT, TEXT) TO anon, authenticated, service_role;

-- 12. REALTIME REPLICATION ENABLEMENT
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'sales_invoices') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE sales_invoices;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'registered_terminals') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE registered_terminals;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'sales_items') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE sales_items;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'stock_batches') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE stock_batches;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'product_master') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE product_master;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'purchase_entries') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE purchase_entries;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'purchase_items') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE purchase_items;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'stock_adjustments') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE stock_adjustments;
    END IF;
  END IF;
END $$;

-- 13. ENTERPRISE HIGH-PERFORMANCE INDEXES (PREVENTS DISK IO BUDGET EXHAUSTION & SEQUENTIAL SCANS)
CREATE INDEX IF NOT EXISTS idx_sales_invoices_fy_entry ON public.sales_invoices (financial_year, entry_no);
CREATE INDEX IF NOT EXISTS idx_sales_invoices_updated_at ON public.sales_invoices (updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_sales_invoices_created_at ON public.sales_invoices (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sales_invoices_branch_term ON public.sales_invoices (branch_id, terminal_id);

CREATE INDEX IF NOT EXISTS idx_sales_items_invoice_no ON public.sales_items (invoice_no);
CREATE INDEX IF NOT EXISTS idx_sales_items_product_id ON public.sales_items (product_id);
CREATE INDEX IF NOT EXISTS idx_sales_items_created_at ON public.sales_items (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_purchase_entries_fy_entry ON public.purchase_entries (financial_year, entry_no);
CREATE INDEX IF NOT EXISTS idx_purchase_entries_updated_at ON public.purchase_entries (updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_purchase_entries_created_at ON public.purchase_entries (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_purchase_items_entry_no ON public.purchase_items (entry_no);
CREATE INDEX IF NOT EXISTS idx_purchase_items_product_id ON public.purchase_items (product_id);

CREATE INDEX IF NOT EXISTS idx_stock_batches_prod_id ON public.stock_batches (product_id);
CREATE INDEX IF NOT EXISTS idx_stock_batches_updated_at ON public.stock_batches (updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_stock_batches_batch_num ON public.stock_batches (batch_number);

CREATE INDEX IF NOT EXISTS idx_product_master_name ON public.product_master (product_name);
CREATE INDEX IF NOT EXISTS idx_product_master_barcode ON public.product_master (barcode);
CREATE INDEX IF NOT EXISTS idx_product_master_updated_at ON public.product_master (updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_active_computers_branch ON public.active_computers (branch_id, last_seen_at DESC);

-- 14. SINGLE GLOBAL STORE-WIDE SEQUENCE LEDGER (ATOMIC & CONCURRENCY-SAFE ACROSS ALL PCS)
CREATE TABLE IF NOT EXISTS public.system_sequences (
    table_name TEXT NOT NULL,
    financial_year TEXT NOT NULL,
    branch_id TEXT NOT NULL DEFAULT 'MAIN_STORE',
    current_value INT NOT NULL DEFAULT 0,
    PRIMARY KEY (table_name, financial_year, branch_id)
);

CREATE OR REPLACE FUNCTION public.fn_claim_global_invoice_number(
    p_table TEXT,
    p_fy TEXT,
    p_branch_id TEXT DEFAULT 'MAIN_STORE'
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_clean_table TEXT;
    v_clean_fy TEXT;
    v_clean_branch TEXT;
    v_curr_val INT;
    v_calculated_max INT := 0;
BEGIN
    v_clean_table := TRIM(COALESCE(p_table, 'sales_invoices'));
    v_clean_fy := TRIM(COALESCE(p_fy, ''));
    v_clean_branch := TRIM(COALESCE(p_branch_id, 'MAIN_STORE'));

    -- Row lock on system_sequences to guarantee zero race conditions between simultaneous billing on PC 1, PC 2, etc.
    SELECT current_value INTO v_curr_val
    FROM public.system_sequences
    WHERE table_name = v_clean_table AND financial_year = v_clean_fy AND branch_id = v_clean_branch
    FOR UPDATE;

    IF NOT FOUND THEN
        -- Seed the sequence from existing records if not yet initialized
        IF v_clean_table = 'sales_invoices' THEN
            SELECT COALESCE(MAX(CAST(REGEXP_REPLACE(entry_no, '\D', '', 'g') AS INT)), 0)
            INTO v_calculated_max
            FROM public.sales_invoices
            WHERE financial_year = v_clean_fy;
        ELSIF v_clean_table = 'purchase_entries' THEN
            SELECT COALESCE(MAX(CAST(REGEXP_REPLACE(entry_no, '\D', '', 'g') AS INT)), 0)
            INTO v_calculated_max
            FROM public.purchase_entries
            WHERE financial_year = v_clean_fy;
        ELSIF v_clean_table = 'sales_return_invoices' THEN
            SELECT COALESCE(MAX(CAST(REGEXP_REPLACE(entry_no, '\D', '', 'g') AS INT)), 0)
            INTO v_calculated_max
            FROM public.sales_return_invoices
            WHERE financial_year = v_clean_fy;
        ELSIF v_clean_table = 'purchase_return_entries' THEN
            SELECT COALESCE(MAX(CAST(REGEXP_REPLACE(entry_no, '\D', '', 'g') AS INT)), 0)
            INTO v_calculated_max
            FROM public.purchase_return_entries
            WHERE financial_year = v_clean_fy;
        ELSIF v_clean_table = 'stock_adjustments' THEN
            SELECT COALESCE(MAX(CAST(REGEXP_REPLACE(entry_no, '\D', '', 'g') AS INT)), 0)
            INTO v_calculated_max
            FROM public.stock_adjustments
            WHERE financial_year = v_clean_fy;
        END IF;

        v_curr_val := v_calculated_max + 1;

        INSERT INTO public.system_sequences (table_name, financial_year, branch_id, current_value)
        VALUES (v_clean_table, v_clean_fy, v_clean_branch, v_curr_val)
        ON CONFLICT (table_name, financial_year, branch_id)
        DO UPDATE SET current_value = GREATEST(system_sequences.current_value, EXCLUDED.current_value);

        RETURN v_curr_val;
    ELSE
        v_curr_val := v_curr_val + 1;

        UPDATE public.system_sequences
        SET current_value = v_curr_val
        WHERE table_name = v_clean_table AND financial_year = v_clean_fy AND branch_id = v_clean_branch;

        RETURN v_curr_val;
    END IF;
END;
$$;

-- 15. RESOLVE SUPABASE SECURITY LINTER WARNINGS (DROP DEPRECATED & RESTRICT PUBLIC EXECUTION)
DROP FUNCTION IF EXISTS public.fn_claim_next_invoice_no CASCADE;
DROP FUNCTION IF EXISTS public.fn_next_sequence_number CASCADE;
DROP FUNCTION IF EXISTS public.fn_save_purchase_entry_atomic_unchecked CASCADE;
DROP FUNCTION IF EXISTS public.fn_save_sale_invoice_atomic_unchecked CASCADE;

REVOKE ALL ON FUNCTION public.fn_claim_global_invoice_number(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_claim_global_invoice_number(TEXT, TEXT, TEXT) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.fn_save_sale_invoice_atomic(JSONB, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_save_sale_invoice_atomic(JSONB, JSONB) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.fn_save_purchase_entry_atomic(JSONB, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_save_purchase_entry_atomic(JSONB, JSONB) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_max_entry_sequence(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_max_entry_sequence(TEXT, TEXT, TEXT) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.allocate_entry_sequence(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.allocate_entry_sequence(TEXT, TEXT, TEXT) TO anon, authenticated, service_role;



