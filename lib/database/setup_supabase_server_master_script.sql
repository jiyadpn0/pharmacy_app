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

-- 4. ROW LEVEL SECURITY (RLS) ENABLEMENT & POLICIES
ALTER TABLE sales_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_master ENABLE ROW LEVEL SECURITY;
ALTER TABLE cloud_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE telemetry_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoice_edit_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE parked_sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE day_closing_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE general_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedule_h1_register ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS open_authenticated_sales ON sales_invoices;
-- Fail closed until tenant/user ownership columns and policies are configured.
CREATE POLICY open_authenticated_sales ON sales_invoices FOR ALL TO authenticated USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS open_authenticated_purchases ON purchase_entries;
CREATE POLICY open_authenticated_purchases ON purchase_entries FOR ALL TO authenticated USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS open_authenticated_batches ON stock_batches;
CREATE POLICY open_authenticated_batches ON stock_batches FOR ALL TO authenticated USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS open_authenticated_products ON product_master;
CREATE POLICY open_authenticated_products ON product_master FOR ALL TO authenticated USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS open_authenticated_audit ON cloud_audit_logs;
CREATE POLICY open_authenticated_audit ON cloud_audit_logs FOR ALL TO authenticated USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS open_authenticated_telemetry ON telemetry_logs;
CREATE POLICY open_authenticated_telemetry ON telemetry_logs FOR ALL TO authenticated USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS open_authenticated_staff ON staff_users;
CREATE POLICY open_authenticated_staff ON staff_users FOR ALL TO authenticated USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS open_authenticated_po ON purchase_orders;
CREATE POLICY open_authenticated_po ON purchase_orders FOR ALL TO authenticated USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS open_authenticated_mappings ON product_mappings;
CREATE POLICY open_authenticated_mappings ON product_mappings FOR ALL TO authenticated USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS open_authenticated_edit_history ON invoice_edit_history;
CREATE POLICY open_authenticated_edit_history ON invoice_edit_history FOR ALL TO authenticated USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS open_authenticated_parked ON parked_sales;
CREATE POLICY open_authenticated_parked ON parked_sales FOR ALL TO authenticated USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS open_authenticated_ledger ON stock_ledger;
CREATE POLICY open_authenticated_ledger ON stock_ledger FOR ALL TO authenticated USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS open_authenticated_closing ON day_closing_records;
CREATE POLICY open_authenticated_closing ON day_closing_records FOR ALL TO authenticated USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS open_authenticated_gl ON general_ledger;
CREATE POLICY open_authenticated_gl ON general_ledger FOR ALL TO authenticated USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS open_authenticated_h1 ON schedule_h1_register;
CREATE POLICY open_authenticated_h1 ON schedule_h1_register FOR ALL TO authenticated USING (false) WITH CHECK (false);

-- 5. AUTOMATED FREE TIER DB CLEANUP CRON (30-day telemetry retention)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.schedule(
            'nightly-pharmacy-maintenance',
            '0 2 * * *',
            $$
            VACUUM ANALYZE;
            DELETE FROM telemetry_logs WHERE created_at < NOW() - INTERVAL '30 days';
            DELETE FROM cloud_audit_logs WHERE timestamp < NOW() - INTERVAL '60 days';
            $$
        );
    END IF;
END $$;

-- 6. ATOMIC SALE INVOICE UPSERT & RPC FUNCTIONS
DROP FUNCTION IF EXISTS public.fn_next_sequence_number(text, text);
DROP FUNCTION IF EXISTS public.fn_next_sequence_number(text, text, text);
DROP FUNCTION IF EXISTS public.fn_next_sequence_number(text);
DROP FUNCTION IF EXISTS public.fn_claim_next_invoice_no(text, text);
DROP FUNCTION IF EXISTS public.fn_claim_next_sale_invoice_no(text, text, text);

DROP FUNCTION IF EXISTS public.fn_save_purchase_entry_atomic(jsonb, jsonb);
DROP FUNCTION IF EXISTS public.fn_save_purchase_entry_atomic(jsonb);

DROP FUNCTION IF EXISTS public.fn_save_sale_invoice_atomic(jsonb, jsonb);
DROP FUNCTION IF EXISTS public.fn_save_sale_invoice_atomic_ui(jsonb, jsonb);
DROP FUNCTION IF EXISTS public.fn_save_sale_invoice_atomic_v2(jsonb, jsonb);

CREATE OR REPLACE FUNCTION public.fn_save_sale_invoice_atomic(
  p_invoice JSONB,
  p_items JSONB DEFAULT '[]'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
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

