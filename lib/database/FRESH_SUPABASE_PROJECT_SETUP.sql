-- =========================================================================
-- PHARMAPRO ERP - COMPLETE PRODUCTION SUPABASE DATABASE SETUP (v3.5.1)
-- 100% Non-Destructive, Multi-Terminal Safe & Schema Backward Compatible
-- Preserves all existing records, tables, and product catalogs.
-- Paste and Run in Supabase Dashboard -> SQL Editor
-- =========================================================================

-- -------------------------------------------------------------------------
-- STEP 1: FIX SECURITY DEFINER VIEWS & CLEAN UP LEGACY ARTIFACTS
-- -------------------------------------------------------------------------
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

-- -------------------------------------------------------------------------
-- STEP 2: AUTOMATED TIMESTAMP TRIGGER FUNCTION
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- -------------------------------------------------------------------------
-- STEP 3: ENSURE ALL CORE MASTER & TRANSACTION TABLES EXIST
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.categories (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  is_active INTEGER DEFAULT 1,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.manufacturers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  is_active INTEGER DEFAULT 1,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.racks (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  is_active INTEGER DEFAULT 1,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.generics (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  use TEXT,
  side_effects TEXT,
  is_active INTEGER DEFAULT 1,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.sub_categories (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  category_id TEXT REFERENCES public.categories(id) ON DELETE SET NULL,
  is_active INTEGER DEFAULT 1,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.suppliers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  dl_no TEXT,
  gst_no TEXT,
  address TEXT,
  state TEXT,
  phone TEXT,
  email TEXT,
  account_no TEXT,
  ifsc TEXT,
  bank_name TEXT,
  payment_terms TEXT,
  rating REAL DEFAULT 5.0,
  is_active INTEGER DEFAULT 1,
  color TEXT,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.customers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  mobile TEXT,
  phone TEXT,
  address TEXT,
  email TEXT,
  gstin TEXT,
  current_balance REAL DEFAULT 0.0,
  is_active INT DEFAULT 1,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  terminal_id TEXT DEFAULT 'POS-01',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.patients (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  mobile TEXT,
  address TEXT,
  current_balance REAL DEFAULT 0.0,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  terminal_id TEXT DEFAULT 'POS-01',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.staff (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT,
  role TEXT,
  code TEXT,
  is_active INTEGER DEFAULT 1,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.product_master (
  id TEXT PRIMARY KEY,
  product_name TEXT NOT NULL,
  name TEXT,
  generic_name TEXT,
  category_id TEXT,
  sub_category_id TEXT,
  manufacturer_id TEXT,
  rack_id TEXT,
  hsn_code TEXT,
  gst_rate REAL DEFAULT 12.0,
  gst_percent REAL DEFAULT 12.0,
  s_disc_percent REAL DEFAULT 0.0,
  schedule TEXT DEFAULT 'H',
  mrp REAL DEFAULT 0.0,
  purchase_rate REAL DEFAULT 0.0,
  selling_price REAL DEFAULT 0.0,
  sale_price REAL DEFAULT 0.0,
  reorder_level INTEGER DEFAULT 10,
  max_level INTEGER DEFAULT 100,
  unit TEXT DEFAULT 'Strip',
  packing INTEGER DEFAULT 10,
  patent TEXT,
  barcode TEXT,
  is_controlled INTEGER DEFAULT 0,
  is_banned INTEGER DEFAULT 0,
  is_nrx INTEGER DEFAULT 0,
  is_active INTEGER DEFAULT 1,
  is_disc_locked INTEGER DEFAULT 0,
  preferred_wholesale TEXT,
  lead_time INTEGER DEFAULT 2,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  terminal_id TEXT DEFAULT 'POS-01',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.stock_batches (
  id TEXT PRIMARY KEY,
  product_id TEXT,
  batch_number TEXT NOT NULL,
  expiry_date TEXT NOT NULL,
  mfg_date TEXT,
  purchase_rate REAL DEFAULT 0.0,
  landing_cost REAL DEFAULT 0.0,
  mrp REAL DEFAULT 0.0,
  selling_rate REAL DEFAULT 0.0,
  current_quantity INTEGER DEFAULT 0,
  current_stock INTEGER DEFAULT 0,
  s_disc_percent REAL DEFAULT 0.0,
  gst_percent REAL DEFAULT 12.0,
  rack TEXT,
  supplier_name TEXT,
  packing INTEGER DEFAULT 1,
  is_active INTEGER DEFAULT 1,
  financial_year TEXT,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  terminal_id TEXT DEFAULT 'POS-01',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.sales_invoices (
  entry_no TEXT PRIMARY KEY,
  invoice_no TEXT,
  financial_year TEXT,
  date TEXT NOT NULL,
  customer_acc TEXT,
  customer_name TEXT,
  patient TEXT,
  customer_phone TEXT,
  mobile TEXT,
  doctor TEXT,
  doctor_reg_no TEXT,
  done_by TEXT,
  terminal_id TEXT DEFAULT 'POS-01',
  shift_id TEXT,
  patient_age INT DEFAULT 0,
  patient_gender TEXT,
  patient_address TEXT,
  gstin_number TEXT,
  place_of_supply TEXT,
  subtotal REAL DEFAULT 0.0,
  sub_total REAL DEFAULT 0.0,
  discount_amount REAL DEFAULT 0.0,
  discount REAL DEFAULT 0.0,
  discount_percent REAL DEFAULT 0.0,
  additional_discount REAL DEFAULT 0.0,
  other_charge REAL DEFAULT 0.0,
  tax_amount REAL DEFAULT 0.0,
  tax REAL DEFAULT 0.0,
  round_off REAL DEFAULT 0.0,
  net_amount REAL DEFAULT 0.0,
  grand_total REAL DEFAULT 0.0,
  total_amount REAL DEFAULT 0.0,
  rcvd_amt REAL DEFAULT 0.0,
  payment_mode TEXT DEFAULT 'CASH',
  payment_remarks TEXT,
  secondary_acc TEXT,
  secondary_amt REAL DEFAULT 0.0,
  is_deleted INTEGER DEFAULT 0,
  is_paid INTEGER DEFAULT 1,
  tax_type TEXT DEFAULT 'Non Gst',
  agent TEXT DEFAULT 'Admin',
  sales_return_amt REAL DEFAULT 0.0,
  order_type INTEGER DEFAULT 0,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.sales_items (
  id BIGSERIAL PRIMARY KEY,
  invoice_no TEXT,
  product_id TEXT,
  product_name TEXT,
  extra TEXT,
  batch_number TEXT,
  expiry_date TEXT,
  quantity INTEGER DEFAULT 1,
  f_qty INTEGER DEFAULT 0,
  hsn_code TEXT,
  schedule TEXT DEFAULT 'H',
  packing INTEGER DEFAULT 1,
  mrp REAL DEFAULT 0.0,
  purchase_rate REAL DEFAULT 0.0,
  landing_cost REAL DEFAULT 0.0,
  taxable_sp REAL DEFAULT 0.0,
  unit_price REAL DEFAULT 0.0,
  disc_percent REAL DEFAULT 0.0,
  disc_amt REAL DEFAULT 0.0,
  gst_percent REAL DEFAULT 12.0,
  gst_amt REAL DEFAULT 0.0,
  cgst_amt REAL DEFAULT 0.0,
  sgst_amt REAL DEFAULT 0.0,
  igst_amt REAL DEFAULT 0.0,
  total_amount REAL DEFAULT 0.0,
  profit REAL DEFAULT 0.0,
  supplier_name TEXT,
  rack TEXT,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  terminal_id TEXT DEFAULT 'POS-01',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.purchase_entries (
  entry_no TEXT PRIMARY KEY,
  sup_inv_no TEXT,
  sup_inv_date TEXT,
  financial_year TEXT,
  date TEXT NOT NULL,
  supplier_name TEXT,
  done_by TEXT,
  subtotal REAL DEFAULT 0.0,
  sub_total REAL DEFAULT 0.0,
  discount_amount REAL DEFAULT 0.0,
  discount REAL DEFAULT 0.0,
  other_charge REAL DEFAULT 0.0,
  other_charges REAL DEFAULT 0.0,
  tax_amount REAL DEFAULT 0.0,
  round_off REAL DEFAULT 0.0,
  net_amount REAL DEFAULT 0.0,
  grand_total REAL DEFAULT 0.0,
  inv_total REAL DEFAULT 0.0,
  total_amount REAL DEFAULT 0.0,
  remarks TEXT,
  payment_status INTEGER DEFAULT 0,
  payment_mode TEXT DEFAULT 'CREDIT',
  payment_remarks TEXT,
  payment_date TEXT,
  paid_amount REAL DEFAULT 0.0,
  days INTEGER DEFAULT 0,
  is_deleted INTEGER DEFAULT 0,
  tax_type TEXT DEFAULT 'Gst',
  branch_id TEXT DEFAULT 'MAIN_STORE',
  terminal_id TEXT DEFAULT 'POS-01',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.purchase_items (
  id BIGSERIAL PRIMARY KEY,
  entry_no TEXT,
  product_id TEXT,
  product_name TEXT,
  extra TEXT,
  batch_number TEXT,
  batch TEXT,
  expiry_date TEXT,
  expiry TEXT,
  quantity INTEGER DEFAULT 1,
  qty INTEGER DEFAULT 1,
  loose_qty INTEGER DEFAULT 0,
  f_qty INTEGER DEFAULT 0,
  packing INTEGER DEFAULT 1,
  packin INTEGER DEFAULT 1,
  mrp REAL DEFAULT 0.0,
  unit_price REAL DEFAULT 0.0,
  p_rate REAL DEFAULT 0.0,
  gross REAL DEFAULT 0.0,
  disc_percent REAL DEFAULT 0.0,
  disc_amt REAL DEFAULT 0.0,
  gst_percent REAL DEFAULT 12.0,
  gst_amt REAL DEFAULT 0.0,
  total_amount REAL DEFAULT 0.0,
  total REAL DEFAULT 0.0,
  rack TEXT,
  hsn_code TEXT,
  s_disc_percent REAL DEFAULT 0.0,
  selling_rate REAL DEFAULT 0.0,
  s_rate REAL DEFAULT 0.0,
  landing_cost REAL DEFAULT 0.0,
  l_cost REAL DEFAULT 0.0,
  supplier TEXT,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  terminal_id TEXT DEFAULT 'POS-01',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.sales_return_invoices (
  entry_no TEXT PRIMARY KEY,
  date TEXT NOT NULL,
  customer_acc TEXT,
  patient TEXT,
  doctor TEXT,
  sub_total REAL DEFAULT 0.0,
  discount REAL DEFAULT 0.0,
  tax REAL DEFAULT 0.0,
  round_off REAL DEFAULT 0.0,
  grand_total REAL DEFAULT 0.0,
  narration TEXT,
  gst_mode INTEGER DEFAULT 1,
  original_invoice_no TEXT,
  is_deleted INTEGER DEFAULT 0,
  financial_year TEXT,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  terminal_id TEXT DEFAULT 'POS-01',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.sales_return_items (
  id BIGSERIAL PRIMARY KEY,
  return_no TEXT,
  product_id TEXT,
  product_name TEXT,
  batch_number TEXT,
  expiry_date TEXT,
  quantity INTEGER DEFAULT 1,
  mrp REAL DEFAULT 0.0,
  sale_rate REAL DEFAULT 0.0,
  disc_percent REAL DEFAULT 0.0,
  disc_amt REAL DEFAULT 0.0,
  hsn_code TEXT,
  total REAL DEFAULT 0.0,
  purchase_rate REAL DEFAULT 0.0,
  landing_cost REAL DEFAULT 0.0,
  supplier_name TEXT,
  packing INTEGER DEFAULT 1,
  gst_percent REAL DEFAULT 12.0,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  terminal_id TEXT DEFAULT 'POS-01',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.purchase_return_entries (
  entry_no TEXT PRIMARY KEY,
  date TEXT NOT NULL,
  supplier_name TEXT,
  original_purchase_no TEXT,
  done_by TEXT,
  grand_total REAL DEFAULT 0.0,
  gst_mode INTEGER DEFAULT 1,
  is_deleted INTEGER DEFAULT 0,
  financial_year TEXT,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  terminal_id TEXT DEFAULT 'POS-01',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.purchase_return_items (
  id BIGSERIAL PRIMARY KEY,
  entry_no TEXT,
  product_name TEXT,
  batch_number TEXT,
  batch TEXT,
  expiry_date TEXT,
  expiry TEXT,
  quantity INTEGER DEFAULT 1,
  qty INTEGER DEFAULT 1,
  loose_qty INTEGER DEFAULT 0,
  f_qty INTEGER DEFAULT 0,
  unit TEXT,
  packing INTEGER DEFAULT 1,
  packin INTEGER DEFAULT 1,
  mrp REAL DEFAULT 0.0,
  unit_price REAL DEFAULT 0.0,
  selling_rate REAL DEFAULT 0.0,
  disc_percent REAL DEFAULT 0.0,
  gst_percent REAL DEFAULT 12.0,
  total REAL DEFAULT 0.0,
  reason TEXT,
  supplier TEXT,
  hsn_code TEXT,
  sup_inv_no TEXT,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  terminal_id TEXT DEFAULT 'POS-01',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.stock_adjustments (
  entry_no TEXT PRIMARY KEY,
  date TEXT NOT NULL,
  done_by TEXT,
  reason TEXT,
  grand_total REAL DEFAULT 0.0,
  is_deleted INTEGER DEFAULT 0,
  financial_year TEXT,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  terminal_id TEXT DEFAULT 'POS-01',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.stock_adjustment_items (
  id BIGSERIAL PRIMARY KEY,
  adjustment_no TEXT,
  product_id TEXT,
  batch_number TEXT,
  qty INTEGER DEFAULT 0,
  purchase_rate REAL DEFAULT 0.0,
  total REAL DEFAULT 0.0,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  terminal_id TEXT DEFAULT 'POS-01',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.stock_write_offs (
  id TEXT PRIMARY KEY,
  date TEXT NOT NULL,
  product_id TEXT,
  batch_number TEXT,
  quantity INTEGER DEFAULT 0,
  reason TEXT,
  loss_value REAL DEFAULT 0.0,
  financial_year TEXT,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  terminal_id TEXT DEFAULT 'POS-01',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.registered_terminals (
  machine_id TEXT PRIMARY KEY,
  branch_id TEXT NOT NULL DEFAULT 'MAIN_STORE',
  terminal_id TEXT NOT NULL,
  computer_name TEXT,
  notes TEXT,
  is_active INT DEFAULT 1,
  registered_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.active_computers (
  machine_id TEXT PRIMARY KEY,
  branch_id TEXT NOT NULL DEFAULT 'MAIN_STORE',
  terminal_id TEXT NOT NULL DEFAULT 'POS-01',
  app_version TEXT,
  last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.idempotency_keys (
  idempotency_key TEXT PRIMARY KEY,
  branch_id TEXT NOT NULL DEFAULT 'MAIN_STORE',
  terminal_id TEXT NOT NULL DEFAULT 'POS-01',
  operation_type TEXT NOT NULL,
  reference_no TEXT NOT NULL,
  response_payload JSONB NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.idempotency_log (
  idempotency_key TEXT PRIMARY KEY,
  branch_id TEXT NOT NULL DEFAULT 'MAIN_STORE',
  terminal_id TEXT NOT NULL DEFAULT 'POS-01',
  operation_type TEXT NOT NULL DEFAULT 'SALE',
  reference_no TEXT NOT NULL,
  response_payload JSONB NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.stock_ledger (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  idempotency_key TEXT,
  operation_type TEXT NOT NULL,
  reference_no TEXT NOT NULL,
  product_id TEXT NOT NULL,
  batch_number TEXT NOT NULL,
  quantity_delta INT NOT NULL DEFAULT 0,
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

CREATE TABLE IF NOT EXISTS public.server_metadata (
  key TEXT PRIMARY KEY,
  value TEXT,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.voucher_sequences (
  voucher_type TEXT NOT NULL,
  financial_year TEXT NOT NULL,
  last_sequence INT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (voucher_type, financial_year)
);
CREATE INDEX IF NOT EXISTS idx_voucher_sequences_lookup ON public.voucher_sequences(voucher_type, financial_year);
GRANT ALL ON TABLE public.voucher_sequences TO anon, authenticated, service_role;

-- Ensure composite unique constraints for terminal upserts
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_sales_invoices_entry_term') THEN
    ALTER TABLE public.sales_invoices ADD CONSTRAINT uq_sales_invoices_entry_term UNIQUE (entry_no, terminal_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_purchase_entries_entry_term') THEN
    ALTER TABLE public.purchase_entries ADD CONSTRAINT uq_purchase_entries_entry_term UNIQUE (entry_no, terminal_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_sales_ret_entry_term') THEN
    ALTER TABLE public.sales_return_invoices ADD CONSTRAINT uq_sales_ret_entry_term UNIQUE (entry_no, terminal_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_pur_ret_entry_term') THEN
    ALTER TABLE public.purchase_return_entries ADD CONSTRAINT uq_pur_ret_entry_term UNIQUE (entry_no, terminal_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_stock_adj_entry_term') THEN
    ALTER TABLE public.stock_adjustments ADD CONSTRAINT uq_stock_adj_entry_term UNIQUE (entry_no, terminal_id);
  END IF;
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

-- -------------------------------------------------------------------------
-- STEP 4: IMMEDIATE SCHEMA COMPATIBILITY MIGRATION LAYER
-- Runs BEFORE any indexes or functions compile, guaranteeing missing columns
-- can NEVER cause compile-time errors (such as 42703 column does not exist).
-- -------------------------------------------------------------------------
DO $$
DECLARE
  t TEXT;
  tbls TEXT[] := ARRAY[
    'product_master', 'stock_batches', 'sales_invoices', 'sales_items',
    'purchase_entries', 'purchase_items', 'sales_return_invoices', 'sales_return_items',
    'purchase_return_entries', 'purchase_return_items', 'stock_adjustments',
    'stock_adjustment_items', 'stock_write_offs', 'patients', 'customers',
    'categories', 'manufacturers', 'racks', 'generics', 'sub_categories', 'suppliers', 'staff'
  ];
BEGIN
  FOREACH t IN ARRAY tbls LOOP
    IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = t) THEN
      EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS branch_id TEXT DEFAULT ''MAIN_STORE''', t);
      EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT ''POS-01''', t);
      EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()', t);
    END IF;
  END LOOP;
END $$;

-- product_master backward & forward compatibility
ALTER TABLE IF EXISTS public.product_master ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE IF EXISTS public.product_master ADD COLUMN IF NOT EXISTS product_name TEXT;
ALTER TABLE IF EXISTS public.product_master ADD COLUMN IF NOT EXISTS barcode TEXT;
ALTER TABLE IF EXISTS public.product_master ADD COLUMN IF NOT EXISTS sale_rate NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.product_master ADD COLUMN IF NOT EXISTS selling_price NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.product_master ADD COLUMN IF NOT EXISTS purchase_rate NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.product_master ADD COLUMN IF NOT EXISTS gst_percent NUMERIC DEFAULT 12.0;
ALTER TABLE IF EXISTS public.product_master ADD COLUMN IF NOT EXISTS gst_rate NUMERIC DEFAULT 12.0;
ALTER TABLE IF EXISTS public.product_master ADD COLUMN IF NOT EXISTS packing INT DEFAULT 1;
ALTER TABLE IF EXISTS public.product_master ADD COLUMN IF NOT EXISTS rack TEXT;
ALTER TABLE IF EXISTS public.product_master ADD COLUMN IF NOT EXISTS generic_name TEXT;
ALTER TABLE IF EXISTS public.product_master ADD COLUMN IF NOT EXISTS is_active INT DEFAULT 1;

UPDATE public.product_master SET name = product_name WHERE (name IS NULL OR name = '') AND product_name IS NOT NULL;
UPDATE public.product_master SET product_name = name WHERE (product_name IS NULL OR product_name = '') AND name IS NOT NULL;
UPDATE public.product_master SET sale_rate = selling_price WHERE sale_rate = 0.0 AND selling_price > 0.0;
UPDATE public.product_master SET selling_price = sale_rate WHERE selling_price = 0.0 AND sale_rate > 0.0;
UPDATE public.product_master SET gst_percent = gst_rate WHERE gst_percent = 0.0 AND gst_rate > 0.0;
UPDATE public.product_master SET gst_rate = gst_percent WHERE gst_rate = 0.0 AND gst_percent > 0.0;

-- stock_batches compatibility
ALTER TABLE IF EXISTS public.stock_batches ADD COLUMN IF NOT EXISTS current_stock INT DEFAULT 0;
ALTER TABLE IF EXISTS public.stock_batches ADD COLUMN IF NOT EXISTS current_quantity INT DEFAULT 0;
ALTER TABLE IF EXISTS public.stock_batches ADD COLUMN IF NOT EXISTS mrp NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.stock_batches ADD COLUMN IF NOT EXISTS sale_rate NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.stock_batches ADD COLUMN IF NOT EXISTS selling_rate NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.stock_batches ADD COLUMN IF NOT EXISTS purchase_rate NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.stock_batches ADD COLUMN IF NOT EXISTS landing_cost NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.stock_batches ADD COLUMN IF NOT EXISTS gst_percent NUMERIC DEFAULT 12.0;
ALTER TABLE IF EXISTS public.stock_batches ADD COLUMN IF NOT EXISTS rack TEXT;
ALTER TABLE IF EXISTS public.stock_batches ADD COLUMN IF NOT EXISTS supplier_name TEXT;
ALTER TABLE IF EXISTS public.stock_batches ADD COLUMN IF NOT EXISTS packing INT DEFAULT 1;
ALTER TABLE IF EXISTS public.stock_batches ADD COLUMN IF NOT EXISTS is_active INT DEFAULT 1;
ALTER TABLE IF EXISTS public.stock_batches ADD COLUMN IF NOT EXISTS financial_year TEXT;

UPDATE public.stock_batches SET current_stock = current_quantity WHERE current_stock = 0 AND current_quantity != 0;
UPDATE public.stock_batches SET current_quantity = current_stock WHERE current_quantity = 0 AND current_stock != 0;
UPDATE public.stock_batches SET sale_rate = selling_rate WHERE sale_rate = 0.0 AND selling_rate > 0.0;
UPDATE public.stock_batches SET selling_rate = sale_rate WHERE selling_rate = 0.0 AND sale_rate > 0.0;

-- sales_invoices compatibility
ALTER TABLE IF EXISTS public.sales_invoices ADD COLUMN IF NOT EXISTS grand_total NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.sales_invoices ADD COLUMN IF NOT EXISTS net_amount NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.sales_invoices ADD COLUMN IF NOT EXISTS total_amount NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.sales_invoices ADD COLUMN IF NOT EXISTS sub_total NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.sales_invoices ADD COLUMN IF NOT EXISTS subtotal NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.sales_invoices ADD COLUMN IF NOT EXISTS discount NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.sales_invoices ADD COLUMN IF NOT EXISTS discount_amount NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.sales_invoices ADD COLUMN IF NOT EXISTS patient TEXT;
ALTER TABLE IF EXISTS public.sales_invoices ADD COLUMN IF NOT EXISTS customer_name TEXT;
ALTER TABLE IF EXISTS public.sales_invoices ADD COLUMN IF NOT EXISTS mobile TEXT;
ALTER TABLE IF EXISTS public.sales_invoices ADD COLUMN IF NOT EXISTS customer_phone TEXT;
ALTER TABLE IF EXISTS public.sales_invoices ADD COLUMN IF NOT EXISTS is_deleted INT DEFAULT 0;
ALTER TABLE IF EXISTS public.sales_invoices ADD COLUMN IF NOT EXISTS is_paid INT DEFAULT 1;
ALTER TABLE IF EXISTS public.sales_invoices ADD COLUMN IF NOT EXISTS financial_year TEXT;

UPDATE public.sales_invoices SET grand_total = net_amount WHERE grand_total = 0.0 AND net_amount > 0.0;
UPDATE public.sales_invoices SET net_amount = grand_total WHERE net_amount = 0.0 AND grand_total > 0.0;
UPDATE public.sales_invoices SET sub_total = subtotal WHERE sub_total = 0.0 AND subtotal > 0.0;
UPDATE public.sales_invoices SET subtotal = sub_total WHERE subtotal = 0.0 AND sub_total > 0.0;
UPDATE public.sales_invoices SET patient = customer_name WHERE (patient IS NULL OR patient = '') AND customer_name IS NOT NULL;
UPDATE public.sales_invoices SET customer_name = patient WHERE (customer_name IS NULL OR customer_name = '') AND patient IS NOT NULL;
UPDATE public.sales_invoices SET mobile = customer_phone WHERE (mobile IS NULL OR mobile = '') AND customer_phone IS NOT NULL;
UPDATE public.sales_invoices SET customer_phone = mobile WHERE (customer_phone IS NULL OR customer_phone = '') AND mobile IS NOT NULL;

-- purchase_entries compatibility
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS grand_total NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS net_amount NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS total_amount NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS sub_total NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS subtotal NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS discount NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS discount_amount NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS is_deleted INT DEFAULT 0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS payment_status INT DEFAULT 0;
ALTER TABLE IF EXISTS public.purchase_entries ADD COLUMN IF NOT EXISTS financial_year TEXT;

UPDATE public.purchase_entries SET grand_total = net_amount WHERE grand_total = 0.0 AND net_amount > 0.0;
UPDATE public.purchase_entries SET net_amount = grand_total WHERE net_amount = 0.0 AND grand_total > 0.0;
UPDATE public.purchase_entries SET sub_total = subtotal WHERE sub_total = 0.0 AND subtotal > 0.0;
UPDATE public.purchase_entries SET subtotal = sub_total WHERE subtotal = 0.0 AND sub_total > 0.0;

-- sales_items compatibility
ALTER TABLE IF EXISTS public.sales_items ADD COLUMN IF NOT EXISTS total NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.sales_items ADD COLUMN IF NOT EXISTS total_amount NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.sales_items ADD COLUMN IF NOT EXISTS quantity INT DEFAULT 0;
ALTER TABLE IF EXISTS public.sales_items ADD COLUMN IF NOT EXISTS qty INT DEFAULT 0;
ALTER TABLE IF EXISTS public.sales_items ADD COLUMN IF NOT EXISTS taxable_sp NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.sales_items ADD COLUMN IF NOT EXISTS unit_price NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.sales_items ADD COLUMN IF NOT EXISTS landing_cost NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.sales_items ADD COLUMN IF NOT EXISTS purchase_rate NUMERIC DEFAULT 0.0;

UPDATE public.sales_items SET total = total_amount WHERE total = 0.0 AND total_amount > 0.0;
UPDATE public.sales_items SET total_amount = total WHERE total_amount = 0.0 AND total > 0.0;
UPDATE public.sales_items SET qty = quantity WHERE qty = 0 AND quantity > 0;
UPDATE public.sales_items SET quantity = qty WHERE quantity = 0 AND qty > 0;

-- purchase_items compatibility
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS total NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS total_amount NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS quantity INT DEFAULT 0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS qty INT DEFAULT 0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS unit_price NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS selling_rate NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS p_rate NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS s_rate NUMERIC DEFAULT 0.0;
ALTER TABLE IF EXISTS public.purchase_items ADD COLUMN IF NOT EXISTS l_cost NUMERIC DEFAULT 0.0;

UPDATE public.purchase_items SET total = total_amount WHERE total = 0.0 AND total_amount > 0.0;
UPDATE public.purchase_items SET total_amount = total WHERE total_amount = 0.0 AND total > 0.0;
UPDATE public.purchase_items SET qty = quantity WHERE qty = 0 AND quantity > 0;
UPDATE public.purchase_items SET quantity = qty WHERE quantity = 0 AND qty > 0;
UPDATE public.purchase_items SET p_rate = unit_price WHERE p_rate = 0.0 AND unit_price > 0.0;
UPDATE public.purchase_items SET unit_price = p_rate WHERE unit_price = 0.0 AND p_rate > 0.0;

-- -------------------------------------------------------------------------
-- STEP 5: CLEANLY DROP EXISTING FUNCTION OVERLOADS (PREVENTS 42P13 CONFLICTS)
-- -------------------------------------------------------------------------
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT p.proname, pg_get_function_identity_arguments(p.oid) as argtypes
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
          AND p.proname IN (
              'get_max_entry_sequence',
              'fn_auto_lease_terminal',
              'fn_heartbeat_and_check_terminal',
              'fn_cleanup_expired_idempotency_logs',
              'fn_save_sale_invoice_atomic',
              'fn_process_sale_atomic',
              'fn_save_purchase_entry_atomic',
              'fn_process_purchase_atomic',
              'fn_process_sales_return_atomic',
              'fn_process_purchase_return_atomic',
              'fn_process_stock_adjustment_atomic',
              'fn_process_stock_write_off_atomic',
              'fn_void_sale_atomic',
              'fn_void_purchase_atomic',
              'fn_reconcile_branch_stock_from_ledger'
          )
    ) LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS public.' || quote_ident(r.proname) || '(' || r.argtypes || ') CASCADE';
    END LOOP;
END $$;

-- -------------------------------------------------------------------------
-- STEP 6: ATOMIC RPC FUNCTIONS (CONCURRENCY, ROW LOCKS & LEDGER TRACKING)
-- -------------------------------------------------------------------------

-- 1. Numeric Maximum Sequence Calculator
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

-- 1B. Pre-Save Cloud Atomic Sequence Allocator (Lock & Claim)
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

END;
$$;

-- 2. Auto Terminal Lease
CREATE OR REPLACE FUNCTION public.fn_auto_lease_terminal(
    p_machine_id TEXT,
    p_computer_name TEXT DEFAULT '',
    p_branch_id TEXT DEFAULT 'MAIN_STORE'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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

    SELECT terminal_id, computer_name
    INTO v_existing_terminal, v_existing_name
    FROM public.registered_terminals
    WHERE machine_id = v_clean_machine AND branch_id = v_clean_branch;

    IF FOUND THEN
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
$$;

-- 3. Terminal Heartbeat & Anti-Collision Check
CREATE OR REPLACE FUNCTION public.fn_heartbeat_and_check_terminal(
    p_branch_id TEXT,
    p_terminal_id TEXT,
    p_machine_id TEXT,
    p_app_version TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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
            'message', 'Duplicate Terminal ID detected: Machine ' || v_conflict_machine || ' is active as ' || v_clean_term
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

-- 4. Idempotency Log Cleanup
CREATE OR REPLACE FUNCTION public.fn_cleanup_expired_idempotency_logs()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    deleted_count INT := 0;
BEGIN
    DELETE FROM public.idempotency_log
    WHERE created_at < NOW() - INTERVAL '24 hours';
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

-- 5. Atomic Sale Invoice Save with Deadlock Prevention, Canonical Row Locks & Stock Ledger
CREATE OR REPLACE FUNCTION public.fn_save_sale_invoice_atomic(
  p_invoice JSONB,
  p_items JSONB DEFAULT '[]'::JSONB,
  p_idempotency_key TEXT DEFAULT ''
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
  v_user_id TEXT;
  v_existing_terminal TEXT;
  v_existing_branch TEXT;
  v_cached_response JSONB;
  v_item JSONB;
  v_prod_id TEXT;
  v_batch_no TEXT;
  v_qty INT;
  v_f_qty INT;
  v_total_deduct INT;
  v_units_remaining INT;
  v_deduct_this_batch INT;
  v_avail_qty INT;
  v_closing_stock INT;
  v_batch_rec RECORD;
  v_res JSONB;
  v_is_edit BOOLEAN;
  v_max_seq INT;
BEGIN
  SET LOCAL lock_timeout = '5s';

  -- Step 1: Idempotency Check
  IF p_idempotency_key IS NOT NULL AND TRIM(p_idempotency_key) <> '' THEN
    SELECT response_payload INTO v_cached_response
    FROM public.idempotency_log
    WHERE idempotency_key = TRIM(p_idempotency_key);

    IF FOUND THEN
      RETURN v_cached_response;
    END IF;
  END IF;

  v_entry_no := TRIM(COALESCE(p_invoice->>'entry_no', p_invoice->>'invoice_no', ''));
  v_terminal_id := TRIM(COALESCE(p_invoice->>'terminal_id', 'POS-01'));
  v_branch_id := TRIM(COALESCE(p_invoice->>'branch_id', 'MAIN_STORE'));
  v_user_id := TRIM(COALESCE(p_invoice->>'done_by', p_invoice->>'agent', 'Cashier'));
  v_is_edit := COALESCE((p_invoice->>'is_edit')::BOOLEAN, false);

  IF v_entry_no IS NULL OR v_entry_no = '' OR v_terminal_id = '' OR v_branch_id = '' THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'INVALID_INPUT',
      'message', 'Missing required entry_no, terminal_id, or branch_id'
    );
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'EMPTY_ITEMS',
      'message', 'Rejected: p_items array cannot be empty or null'
    );
  END IF;

  -- Strict Anti-Collision Safety: If this is a NEW entry (Save button) and entry_no is already taken,
  -- auto-allocate the next sequence number so existing records can NEVER be overwritten.
  IF NOT v_is_edit AND EXISTS (SELECT 1 FROM public.sales_invoices WHERE entry_no = v_entry_no) THEN
    SELECT COALESCE(MAX(NULLIF(regexp_replace(entry_no, '\D', '', 'g'), '')::INT), 0) + 1
    INTO v_max_seq
    FROM public.sales_invoices;
    v_entry_no := v_max_seq::TEXT;
  END IF;

  SELECT terminal_id, branch_id
  INTO v_existing_terminal, v_existing_branch
  FROM public.sales_invoices
  WHERE entry_no = v_entry_no
  FOR UPDATE;

  IF FOUND THEN
    v_existing_terminal := TRIM(COALESCE(v_existing_terminal, ''));
    v_existing_branch := TRIM(COALESCE(v_existing_branch, ''));

    IF v_existing_terminal <> '' AND v_existing_branch <> '' AND (v_existing_terminal <> v_terminal_id OR v_existing_branch <> v_branch_id) THEN
      RETURN jsonb_build_object(
        'success', false,
        'reason', 'COLLISION',
        'message', 'Invoice entry_no already exists under a different terminal/branch'
      );
    END IF;

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
      done_by = v_user_id,
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
      agent = v_user_id,
      sales_return_amt = COALESCE(NULLIF(p_invoice->>'sales_return_amt', '')::NUMERIC, 0.0),
      order_type = COALESCE(NULLIF(p_invoice->>'order_type', '')::INT, 0),
      branch_id = v_branch_id,
      updated_at = NOW()
    WHERE entry_no = v_entry_no;
  ELSE
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
      v_user_id,
      COALESCE(NULLIF(p_invoice->>'sales_return_amt', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(p_invoice->>'order_type', '')::INT, 0),
      v_branch_id,
      NOW()
    );
  END IF;

  DELETE FROM public.sales_items WHERE invoice_no = v_entry_no;

  -- Step 2: Canonical Ordering, Batch Deductions & Auditable Stock Ledger Entry
  IF p_items IS NOT NULL AND jsonb_array_length(p_items) > 0 THEN
    FOR v_item IN
      SELECT item
      FROM jsonb_array_elements(p_items) AS item
      ORDER BY (item->>'product_id') ASC, (COALESCE(item->>'batch_number', item->>'batch', '')) ASC
    LOOP
      v_prod_id := TRIM(COALESCE(v_item->>'product_id', ''));
      v_batch_no := TRIM(COALESCE(v_item->>'batch_number', v_item->>'batch', ''));
      v_qty := COALESCE(NULLIF(v_item->>'quantity', '')::INT, NULLIF(v_item->>'qty', '')::INT, 1);
      v_f_qty := COALESCE(NULLIF(v_item->>'f_qty', '')::INT, 0);
      v_total_deduct := v_qty + v_f_qty;

      IF v_prod_id <> '' AND v_batch_no <> '' AND v_total_deduct > 0 THEN
        -- Check total available quantity across matching batches in this branch
        SELECT COALESCE(SUM(current_quantity), 0) INTO v_avail_qty
        FROM public.stock_batches
        WHERE branch_id = v_branch_id
          AND product_id = v_prod_id
          AND LOWER(TRIM(batch_number)) = LOWER(v_batch_no);

        IF v_avail_qty < v_total_deduct THEN
          RETURN jsonb_build_object(
            'success', false,
            'reason', 'INSUFFICIENT_STOCK',
            'message', 'Insufficient stock for product ' || v_prod_id || ' batch ' || v_batch_no || ' (Available: ' || v_avail_qty || ', Required: ' || v_total_deduct || ')'
          );
        END IF;

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
              current_stock = current_quantity - v_deduct_this_batch,
              updated_at = NOW()
          WHERE id = v_batch_rec.id
          RETURNING current_quantity INTO v_closing_stock;

          -- Append entry to immutable stock ledger
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
      END IF;
    END LOOP;

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
      v_terminal_id,
      NOW()
    FROM jsonb_array_elements(p_items) AS item;
  END IF;

  v_res := jsonb_build_object(
    'success', true,
    'entry_no', v_entry_no,
    'branch_id', v_branch_id,
    'terminal_id', v_terminal_id
  );

  -- Step 3: Record in Idempotency Registries
  IF p_idempotency_key IS NOT NULL AND TRIM(p_idempotency_key) <> '' THEN
    INSERT INTO public.idempotency_log (
      idempotency_key, branch_id, terminal_id, operation_type, reference_no, response_payload, created_at
    ) VALUES (
      TRIM(p_idempotency_key), v_branch_id, v_terminal_id, 'SALE', v_entry_no, v_res, NOW()
    )
    ON CONFLICT (idempotency_key) DO UPDATE
    SET response_payload = EXCLUDED.response_payload,
        created_at = NOW();

    INSERT INTO public.idempotency_keys (
      idempotency_key, branch_id, terminal_id, operation_type, reference_no, response_payload, created_at
    ) VALUES (
      TRIM(p_idempotency_key), v_branch_id, v_terminal_id, 'SALE', v_entry_no, v_res, NOW()
    )
    ON CONFLICT (idempotency_key) DO NOTHING;
  END IF;

  RETURN v_res;
END;
$$;

-- Alias for fn_process_sale_atomic (100% parameter signature compatibility)
CREATE OR REPLACE FUNCTION public.fn_process_sale_atomic(
  p_invoice JSONB,
  p_items JSONB DEFAULT '[]'::JSONB,
  p_idempotency_key TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN public.fn_save_sale_invoice_atomic(p_invoice, p_items, p_idempotency_key);
END;
$$;

-- 6. Atomic Purchase Entry Save with Idempotency, Sequence Anti-Collision & Ledger Tracking
CREATE OR REPLACE FUNCTION public.fn_save_purchase_entry_atomic(
  p_purchase JSONB,
  p_items JSONB DEFAULT '[]'::JSONB,
  p_idempotency_key TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_entry_no TEXT;
    v_branch_id TEXT;
    v_terminal_id TEXT;
    v_user_id TEXT;
    v_item JSONB;
    v_cached_response JSONB;
    v_res JSONB;
    v_is_edit BOOLEAN;
    v_max_seq INT;
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
BEGIN
    SET LOCAL lock_timeout = '5s';

    IF p_idempotency_key IS NOT NULL AND TRIM(p_idempotency_key) <> '' THEN
        SELECT response_payload INTO v_cached_response
        FROM public.idempotency_log
        WHERE idempotency_key = TRIM(p_idempotency_key);

        IF FOUND THEN
            RETURN v_cached_response;
        END IF;
    END IF;

    v_entry_no := TRIM(COALESCE(p_purchase->>'entry_no', ''));
    v_branch_id := TRIM(COALESCE(p_purchase->>'branch_id', 'MAIN_STORE'));
    v_terminal_id := TRIM(COALESCE(p_purchase->>'terminal_id', 'POS-01'));
    v_user_id := TRIM(COALESCE(p_purchase->>'done_by', 'Admin'));
    v_is_edit := COALESCE((p_purchase->>'is_edit')::BOOLEAN, false);

    IF NOT v_is_edit AND EXISTS (SELECT 1 FROM public.purchase_entries WHERE entry_no = v_entry_no) THEN
        SELECT COALESCE(MAX(NULLIF(regexp_replace(entry_no, '\D', '', 'g'), '')::INT), 0) + 1
        INTO v_max_seq
        FROM public.purchase_entries;
        v_entry_no := v_max_seq::TEXT;
    END IF;

    INSERT INTO public.purchase_entries (
        entry_no, sup_inv_no, sup_inv_date, financial_year, date, supplier_name,
        done_by, subtotal, sub_total, discount_amount, discount, other_charge, other_charges,
        round_off, net_amount, grand_total, inv_total, total_amount, remarks,
        payment_status, payment_mode, branch_id, terminal_id, updated_at
    ) VALUES (
        v_entry_no,
        p_purchase->>'sup_inv_no',
        p_purchase->>'sup_inv_date',
        p_purchase->>'financial_year',
        COALESCE(p_purchase->>'date', NOW()::TEXT),
        p_purchase->>'supplier_name',
        v_user_id,
        COALESCE((p_purchase->>'subtotal')::NUMERIC, (p_purchase->>'sub_total')::NUMERIC, 0.0),
        COALESCE((p_purchase->>'sub_total')::NUMERIC, (p_purchase->>'subtotal')::NUMERIC, 0.0),
        COALESCE((p_purchase->>'discount_amount')::NUMERIC, (p_purchase->>'discount')::NUMERIC, 0.0),
        COALESCE((p_purchase->>'discount')::NUMERIC, (p_purchase->>'discount_amount')::NUMERIC, 0.0),
        COALESCE((p_purchase->>'other_charge')::NUMERIC, 0.0),
        COALESCE((p_purchase->>'other_charges')::NUMERIC, 0.0),
        COALESCE((p_purchase->>'round_off')::NUMERIC, 0.0),
        COALESCE((p_purchase->>'net_amount')::NUMERIC, (p_purchase->>'grand_total')::NUMERIC, 0.0),
        COALESCE((p_purchase->>'grand_total')::NUMERIC, (p_purchase->>'net_amount')::NUMERIC, 0.0),
        COALESCE((p_purchase->>'inv_total')::NUMERIC, 0.0),
        COALESCE((p_purchase->>'total_amount')::NUMERIC, (p_purchase->>'grand_total')::NUMERIC, 0.0),
        p_purchase->>'remarks',
        COALESCE((p_purchase->>'payment_status')::INT, 0),
        COALESCE(p_purchase->>'payment_mode', 'CREDIT'),
        v_branch_id,
        v_terminal_id,
        NOW()
    )
    ON CONFLICT (entry_no) DO UPDATE SET
        supplier_name = EXCLUDED.supplier_name,
        sup_inv_no = EXCLUDED.sup_inv_no,
        net_amount = EXCLUDED.net_amount,
        grand_total = EXCLUDED.grand_total,
        inv_total = EXCLUDED.inv_total,
        branch_id = EXCLUDED.branch_id,
        updated_at = NOW();

    DELETE FROM public.purchase_items WHERE entry_no = v_entry_no;

    IF p_items IS NOT NULL AND jsonb_array_length(p_items) > 0 THEN
        FOR v_item IN
            SELECT item
            FROM jsonb_array_elements(p_items) AS item
            ORDER BY (item->>'product_id') ASC, (COALESCE(item->>'batch_number', item->>'batch', '')) ASC
        LOOP
            v_prod_id := TRIM(COALESCE(v_item->>'product_id', v_item->>'id', ''));
            v_batch_no := TRIM(COALESCE(v_item->>'batch_number', v_item->>'batch', ''));
            v_exp_date := TRIM(COALESCE(v_item->>'expiry_date', v_item->>'expiry', ''));
            v_qty := COALESCE(NULLIF(v_item->>'quantity', '')::INT, NULLIF(v_item->>'qty', '')::INT, 1);
            v_f_qty := COALESCE(NULLIF(v_item->>'f_qty', '')::INT, 0);
            v_packing := COALESCE(NULLIF(v_item->>'packing', '')::INT, NULLIF(v_item->>'packin', '')::INT, 1);
            v_loose_qty := COALESCE(NULLIF(v_item->>'loose_qty', '')::INT, 0);
            v_p_rate := COALESCE(NULLIF(v_item->>'unit_price', '')::NUMERIC, NULLIF(v_item->>'p_rate', '')::NUMERIC, 0.0);
            v_l_cost := COALESCE(NULLIF(v_item->>'landing_cost', '')::NUMERIC, NULLIF(v_item->>'l_cost', '')::NUMERIC, v_p_rate);
            v_mrp := COALESCE(NULLIF(v_item->>'mrp', '')::NUMERIC, 0.0);
            v_s_rate := COALESCE(NULLIF(v_item->>'selling_rate', '')::NUMERIC, NULLIF(v_item->>'s_rate', '')::NUMERIC, v_mrp);
            v_gst_pct := COALESCE(NULLIF(v_item->>'gst_percent', '')::NUMERIC, 12.0);
            v_supplier := TRIM(COALESCE(v_item->>'supplier', p_purchase->>'supplier_name', ''));

            v_total_units := (v_qty * v_packing) + v_loose_qty + (v_f_qty * v_packing);

            INSERT INTO public.purchase_items (
                entry_no, product_id, product_name, batch_number, batch, expiry_date, expiry,
                quantity, qty, f_qty, loose_qty, packing, packin, mrp, unit_price, p_rate,
                gross, disc_percent, disc_amt, gst_percent, gst_amt, total_amount, total,
                selling_rate, s_rate, landing_cost, l_cost, supplier, hsn_code, rack, branch_id, terminal_id, created_at
            ) VALUES (
                v_entry_no, v_prod_id, COALESCE(v_item->>'product_name', ''), v_batch_no, v_batch_no, v_exp_date, v_exp_date,
                v_qty, v_qty, v_f_qty, v_loose_qty, v_packing, v_packing, v_mrp, v_p_rate, v_p_rate,
                COALESCE((v_item->>'gross')::NUMERIC, 0.0),
                COALESCE((v_item->>'disc_percent')::NUMERIC, 0.0),
                COALESCE((v_item->>'disc_amt')::NUMERIC, 0.0),
                v_gst_pct,
                COALESCE((v_item->>'gst_amt')::NUMERIC, 0.0),
                COALESCE((v_item->>'total_amount')::NUMERIC, (v_item->>'total')::NUMERIC, 0.0),
                COALESCE((v_item->>'total')::NUMERIC, (v_item->>'total_amount')::NUMERIC, 0.0),
                v_s_rate, v_s_rate, v_l_cost, v_l_cost, v_supplier,
                COALESCE(v_item->>'hsn_code', v_item->>'hsn', ''),
                COALESCE(v_item->>'rack', ''),
                v_branch_id, v_terminal_id, NOW()
            );

            v_batch_key := v_branch_id || '_' || v_prod_id || '_' || v_batch_no || '_' || v_exp_date;
            v_batch_key := regexp_replace(v_batch_key, '[^a-zA-Z0-9_-]', '_', 'g');

            INSERT INTO public.stock_batches (
                id, product_id, batch_number, expiry_date,
                purchase_rate, landing_cost, mrp, selling_rate,
                current_quantity, current_stock, gst_percent, supplier_name, packing, is_active,
                branch_id, updated_at
            ) VALUES (
                v_batch_key, v_prod_id, v_batch_no, v_exp_date,
                v_p_rate, v_l_cost, v_mrp, v_s_rate,
                v_total_units, v_total_units, v_gst_pct, v_supplier, v_packing, 1,
                v_branch_id, NOW()
            )
            ON CONFLICT (id) DO UPDATE SET
                current_quantity = stock_batches.current_quantity + EXCLUDED.current_quantity,
                current_stock = stock_batches.current_stock + EXCLUDED.current_stock,
                purchase_rate = EXCLUDED.purchase_rate,
                landing_cost = EXCLUDED.landing_cost,
                mrp = EXCLUDED.mrp,
                selling_rate = EXCLUDED.selling_rate,
                updated_at = NOW()
            RETURNING current_quantity INTO v_closing_stock;

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

    v_res := jsonb_build_object(
        'success', true,
        'entry_no', v_entry_no,
        'branch_id', v_branch_id,
        'terminal_id', v_terminal_id
    );

    IF p_idempotency_key IS NOT NULL AND TRIM(p_idempotency_key) <> '' THEN
        INSERT INTO public.idempotency_log (
            idempotency_key, branch_id, terminal_id, operation_type, reference_no, response_payload, created_at
        ) VALUES (
            TRIM(p_idempotency_key), v_branch_id, v_terminal_id, 'PURCHASE', v_entry_no, v_res, NOW()
        )
        ON CONFLICT (idempotency_key) DO UPDATE
        SET response_payload = EXCLUDED.response_payload,
            created_at = NOW();

        INSERT INTO public.idempotency_keys (
            idempotency_key, branch_id, terminal_id, operation_type, reference_no, response_payload, created_at
        ) VALUES (
            TRIM(p_idempotency_key), v_branch_id, v_terminal_id, 'PURCHASE', v_entry_no, v_res, NOW()
        )
        ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;

    RETURN v_res;
END;
$$;

-- Alias for fn_process_purchase_atomic
CREATE OR REPLACE FUNCTION public.fn_process_purchase_atomic(
  p_purchase JSONB,
  p_items JSONB DEFAULT '[]'::JSONB,
  p_idempotency_key TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN public.fn_save_purchase_entry_atomic(p_purchase, p_items, p_idempotency_key);
END;
$$;

-- 7. Atomic Sales Return Save
CREATE OR REPLACE FUNCTION public.fn_process_sales_return_atomic(
    p_return JSONB,
    p_items JSONB DEFAULT '[]'::JSONB,
    p_idempotency_key TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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
    IF p_idempotency_key IS NOT NULL AND TRIM(p_idempotency_key) <> '' THEN
        SELECT response_payload INTO v_cached_response
        FROM public.idempotency_keys
        WHERE idempotency_key = TRIM(p_idempotency_key);

        IF FOUND THEN
            RETURN v_cached_response;
        END IF;
    END IF;

    v_entry_no := TRIM(COALESCE(p_return->>'entry_no', ''));
    v_branch_id := TRIM(COALESCE(p_return->>'branch_id', 'MAIN_STORE'));
    v_terminal_id := TRIM(COALESCE(p_return->>'terminal_id', 'POS-01'));
    v_user_id := TRIM(COALESCE(p_return->>'done_by', 'Cashier'));

    IF v_entry_no = '' OR v_branch_id = '' THEN
        RETURN jsonb_build_object('success', false, 'reason', 'INVALID_INPUT', 'message', 'Missing entry_no or branch_id');
    END IF;

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

            v_batch_key := v_branch_id || '_' || v_prod_id || '_' || v_batch_no || '_' || v_exp_date;
            v_batch_key := regexp_replace(v_batch_key, '[^a-zA-Z0-9_-]', '_', 'g');

            INSERT INTO public.stock_batches (
                id, product_id, batch_number, expiry_date, current_quantity, current_stock, branch_id, updated_at
            ) VALUES (
                v_batch_key, v_prod_id, v_batch_no, v_exp_date, v_qty, v_qty, v_branch_id, NOW()
            )
            ON CONFLICT (id) DO UPDATE SET
                current_quantity = stock_batches.current_quantity + EXCLUDED.current_quantity,
                current_stock = stock_batches.current_stock + EXCLUDED.current_stock,
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
        'terminal_id', v_terminal_id
    );

    IF p_idempotency_key IS NOT NULL AND TRIM(p_idempotency_key) <> '' THEN
        INSERT INTO public.idempotency_keys (
            idempotency_key, branch_id, terminal_id, operation_type, reference_no, response_payload, created_at
        ) VALUES (
            TRIM(p_idempotency_key), v_branch_id, v_terminal_id, 'SALES_RETURN', v_entry_no, v_response, NOW()
        )
        ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;

    RETURN v_response;
END;
$$;

-- 8. Atomic Purchase Return Save
CREATE OR REPLACE FUNCTION public.fn_process_purchase_return_atomic(
    p_return JSONB,
    p_items JSONB DEFAULT '[]'::JSONB,
    p_idempotency_key TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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
    IF p_idempotency_key IS NOT NULL AND TRIM(p_idempotency_key) <> '' THEN
        SELECT response_payload INTO v_cached_response
        FROM public.idempotency_keys
        WHERE idempotency_key = TRIM(p_idempotency_key);

        IF FOUND THEN
            RETURN v_cached_response;
        END IF;
    END IF;

    v_entry_no := TRIM(COALESCE(p_return->>'entry_no', ''));
    v_branch_id := TRIM(COALESCE(p_return->>'branch_id', 'MAIN_STORE'));
    v_terminal_id := TRIM(COALESCE(p_return->>'terminal_id', 'POS-01'));
    v_user_id := TRIM(COALESCE(p_return->>'done_by', 'Admin'));

    IF v_entry_no = '' OR v_branch_id = '' THEN
        RETURN jsonb_build_object('success', false, 'reason', 'INVALID_INPUT', 'message', 'Missing entry_no or branch_id');
    END IF;

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
              AND LOWER(TRIM(batch_number)) = LOWER(v_batch_no);

            IF v_avail_qty < v_qty THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'reason', 'INSUFFICIENT_STOCK',
                    'message', 'Cannot return to supplier: Insufficient shelf stock for product ' || v_prod_id || ' batch ' || v_batch_no || ' (Available: ' || v_avail_qty || ', Required: ' || v_qty || ')'
                );
            END IF;
        END LOOP;
    END IF;

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
                    current_stock = current_stock - v_deduct,
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
        'terminal_id', v_terminal_id
    );

    IF p_idempotency_key IS NOT NULL AND TRIM(p_idempotency_key) <> '' THEN
        INSERT INTO public.idempotency_keys (
            idempotency_key, branch_id, terminal_id, operation_type, reference_no, response_payload, created_at
        ) VALUES (
            TRIM(p_idempotency_key), v_branch_id, v_terminal_id, 'PURCHASE_RETURN', v_entry_no, v_response, NOW()
        )
        ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;

    RETURN v_response;
END;
$$;

-- 9. Atomic Stock Adjustment Save
CREATE OR REPLACE FUNCTION public.fn_process_stock_adjustment_atomic(
    p_adjustment JSONB,
    p_items JSONB DEFAULT '[]'::JSONB,
    p_idempotency_key TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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
    IF p_idempotency_key IS NOT NULL AND TRIM(p_idempotency_key) <> '' THEN
        SELECT response_payload INTO v_cached_response
        FROM public.idempotency_keys
        WHERE idempotency_key = TRIM(p_idempotency_key);

        IF FOUND THEN
            RETURN v_cached_response;
        END IF;
    END IF;

    v_entry_no := TRIM(COALESCE(p_adjustment->>'entry_no', ''));
    v_branch_id := TRIM(COALESCE(p_adjustment->>'branch_id', 'MAIN_STORE'));
    v_terminal_id := TRIM(COALESCE(p_adjustment->>'terminal_id', 'POS-01'));
    v_user_id := TRIM(COALESCE(p_adjustment->>'done_by', 'Admin'));

    IF v_entry_no = '' OR v_branch_id = '' THEN
        RETURN jsonb_build_object('success', false, 'reason', 'INVALID_INPUT', 'message', 'Missing entry_no or branch_id');
    END IF;

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
                  AND LOWER(TRIM(batch_number)) = LOWER(v_batch_no);

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
                    id, product_id, batch_number, expiry_date, current_quantity, current_stock, branch_id, updated_at
                ) VALUES (
                    v_batch_key, v_prod_id, v_batch_no, COALESCE(v_item->>'expiry_date', '--/--'), v_qty, v_qty, v_branch_id, NOW()
                )
                ON CONFLICT (id) DO UPDATE SET
                    current_quantity = stock_batches.current_quantity + EXCLUDED.current_quantity,
                    current_stock = stock_batches.current_stock + EXCLUDED.current_stock,
                    updated_at = NOW()
                RETURNING current_quantity INTO v_closing_stock;
            ELSE
                UPDATE public.stock_batches
                SET current_quantity = current_quantity + v_qty,
                    current_stock = current_stock + v_qty,
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
        'terminal_id', v_terminal_id
    );

    IF p_idempotency_key IS NOT NULL AND TRIM(p_idempotency_key) <> '' THEN
        INSERT INTO public.idempotency_keys (
            idempotency_key, branch_id, terminal_id, operation_type, reference_no, response_payload, created_at
        ) VALUES (
            TRIM(p_idempotency_key), v_branch_id, v_terminal_id, 'ADJUSTMENT', v_entry_no, v_response, NOW()
        )
        ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;

    RETURN v_response;
END;
$$;

-- 10. Atomic Stock Write Off Save
CREATE OR REPLACE FUNCTION public.fn_process_stock_write_off_atomic(
    p_write_off JSONB,
    p_idempotency_key TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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
    IF p_idempotency_key IS NOT NULL AND TRIM(p_idempotency_key) <> '' THEN
        SELECT response_payload INTO v_cached_response
        FROM public.idempotency_keys
        WHERE idempotency_key = TRIM(p_idempotency_key);

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
        RETURN jsonb_build_object('success', false, 'reason', 'INVALID_INPUT', 'message', 'Missing write off id, product_id, or batch_number');
    END IF;

    SELECT COALESCE(SUM(current_quantity), 0) INTO v_avail_qty
    FROM public.stock_batches
    WHERE branch_id = v_branch_id
      AND product_id = v_prod_id
      AND LOWER(TRIM(batch_number)) = LOWER(v_batch_no);

    IF v_avail_qty < v_qty THEN
        RETURN jsonb_build_object('success', false, 'reason', 'INSUFFICIENT_STOCK', 'message', 'Cannot write-off: Only ' || v_avail_qty || ' available.');
    END IF;

    UPDATE public.stock_batches
    SET current_quantity = current_quantity - v_qty,
        current_stock = current_stock - v_qty,
        updated_at = NOW()
    WHERE branch_id = v_branch_id
      AND product_id = v_prod_id
      AND LOWER(TRIM(batch_number)) = LOWER(v_batch_no)
    RETURNING current_quantity INTO v_closing_stock;

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

    INSERT INTO public.stock_ledger (
        idempotency_key, operation_type, reference_no, product_id, batch_number,
        quantity_delta, qty_in, qty_out, closing_balance,
        branch_id, terminal_id, user_id, created_at
    ) VALUES (
        p_idempotency_key, 'WRITE_OFF', v_id, v_prod_id, v_batch_no,
        -v_qty, 0, v_qty, v_closing_stock,
        v_branch_id, v_terminal_id, v_user_id, NOW()
    );

    v_response := jsonb_build_object('success', true, 'id', v_id, 'branch_id', v_branch_id);

    IF p_idempotency_key IS NOT NULL AND TRIM(p_idempotency_key) <> '' THEN
        INSERT INTO public.idempotency_keys (
            idempotency_key, branch_id, terminal_id, operation_type, reference_no, response_payload, created_at
        ) VALUES (
            TRIM(p_idempotency_key), v_branch_id, v_terminal_id, 'WRITE_OFF', v_id, v_response, NOW()
        )
        ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;

    RETURN v_response;
END;
$$;

-- 11. Atomic Sale Void with Stock Restoration
CREATE OR REPLACE FUNCTION public.fn_void_sale_atomic(
    p_entry_no TEXT,
    p_branch_id TEXT DEFAULT 'MAIN_STORE',
    p_terminal_id TEXT DEFAULT 'POS-01',
    p_idempotency_key TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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
    IF p_idempotency_key IS NOT NULL AND TRIM(p_idempotency_key) <> '' THEN
        SELECT response_payload INTO v_cached_response
        FROM public.idempotency_keys
        WHERE idempotency_key = TRIM(p_idempotency_key);

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
        RETURN jsonb_build_object('success', false, 'reason', 'NOT_FOUND', 'message', 'Invoice not found');
    END IF;

    IF v_inv_rec.is_deleted = 1 THEN
        RETURN jsonb_build_object('success', true, 'entry_no', v_clean_entry, 'message', 'Already voided');
    END IF;

    UPDATE public.sales_invoices
    SET is_deleted = 1, updated_at = NOW()
    WHERE entry_no = v_clean_entry;

    FOR v_item IN
        SELECT product_id, batch_number, quantity, f_qty, purchase_rate, mrp, unit_price
        FROM public.sales_items
        WHERE invoice_no = v_clean_entry
    LOOP
        UPDATE public.stock_batches
        SET current_quantity = current_quantity + (v_item.quantity + v_item.f_qty),
            current_stock = current_stock + (v_item.quantity + v_item.f_qty),
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

    v_response := jsonb_build_object('success', true, 'entry_no', v_clean_entry, 'message', 'Voided successfully');

    IF p_idempotency_key IS NOT NULL AND TRIM(p_idempotency_key) <> '' THEN
        INSERT INTO public.idempotency_keys (
            idempotency_key, branch_id, terminal_id, operation_type, reference_no, response_payload, created_at
        ) VALUES (
            TRIM(p_idempotency_key), v_clean_branch, v_clean_term, 'SALE_VOID', v_clean_entry, v_response, NOW()
        )
        ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;

    RETURN v_response;
END;
$$;

-- 12. Atomic Purchase Void with Consumption Verification
CREATE OR REPLACE FUNCTION public.fn_void_purchase_atomic(
    p_entry_no TEXT,
    p_branch_id TEXT DEFAULT 'MAIN_STORE',
    p_terminal_id TEXT DEFAULT 'POS-01',
    p_idempotency_key TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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
    IF p_idempotency_key IS NOT NULL AND TRIM(p_idempotency_key) <> '' THEN
        SELECT response_payload INTO v_cached_response
        FROM public.idempotency_keys
        WHERE idempotency_key = TRIM(p_idempotency_key);

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
        RETURN jsonb_build_object('success', false, 'reason', 'NOT_FOUND', 'message', 'Purchase not found');
    END IF;

    IF v_pur_rec.is_deleted = 1 THEN
        RETURN jsonb_build_object('success', true, 'entry_no', v_clean_entry, 'message', 'Already voided');
    END IF;

    FOR v_item IN
        SELECT product_id, COALESCE(batch_number, batch) as batch, COALESCE(quantity, qty) as qty, loose_qty, f_qty, COALESCE(packing, packin, 1) as packin
        FROM public.purchase_items
        WHERE entry_no = v_clean_entry
    LOOP
        v_req_deduct := (v_item.qty * COALESCE(v_item.packin, 1)) + COALESCE(v_item.loose_qty, 0) + (v_item.f_qty * COALESCE(v_item.packin, 1));

        SELECT COALESCE(SUM(current_quantity), 0) INTO v_avail_qty
        FROM public.stock_batches
        WHERE branch_id = v_clean_branch
          AND product_id = v_item.product_id
          AND LOWER(TRIM(batch_number)) = LOWER(TRIM(v_item.batch));

        IF v_avail_qty < v_req_deduct THEN
            RETURN jsonb_build_object(
                'success', false,
                'reason', 'STOCK_ALREADY_CONSUMED',
                'message', 'Cannot void purchase: units were already sold'
            );
        END IF;
    END LOOP;

    UPDATE public.purchase_entries
    SET is_deleted = 1, updated_at = NOW()
    WHERE entry_no = v_clean_entry;

    FOR v_item IN
        SELECT product_id, COALESCE(batch_number, batch) as batch, COALESCE(quantity, qty) as qty, loose_qty, f_qty, COALESCE(packing, packin, 1) as packin, COALESCE(unit_price, p_rate, 0.0) as p_rate, mrp, COALESCE(selling_rate, s_rate, 0.0) as s_rate
        FROM public.purchase_items
        WHERE entry_no = v_clean_entry
    LOOP
        v_req_deduct := (v_item.qty * COALESCE(v_item.packin, 1)) + COALESCE(v_item.loose_qty, 0) + (v_item.f_qty * COALESCE(v_item.packin, 1));

        UPDATE public.stock_batches
        SET current_quantity = current_quantity - v_req_deduct,
            current_stock = current_stock - v_req_deduct,
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

    v_response := jsonb_build_object('success', true, 'entry_no', v_clean_entry, 'message', 'Voided successfully');

    IF p_idempotency_key IS NOT NULL AND TRIM(p_idempotency_key) <> '' THEN
        INSERT INTO public.idempotency_keys (
            idempotency_key, branch_id, terminal_id, operation_type, reference_no, response_payload, created_at
        ) VALUES (
            TRIM(p_idempotency_key), v_clean_branch, v_clean_term, 'PURCHASE_VOID', v_clean_entry, v_response, NOW()
        )
        ON CONFLICT (idempotency_key) DO NOTHING;
    END IF;

    RETURN v_response;
END;
$$;

-- 13. Auditable Stock Reconciliation from Immutable Ledger
CREATE OR REPLACE FUNCTION public.fn_reconcile_branch_stock_from_ledger(
    p_branch_id TEXT DEFAULT 'MAIN_STORE'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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
            current_stock = GREATEST(0, v_rec.calculated_stock),
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
-- STEP 7: SAFE HIGH-SPEED PERFORMANCE INDEXES (DYNAMIC SQL)
-- -------------------------------------------------------------------------
DO $$
BEGIN
  EXECUTE 'CREATE INDEX IF NOT EXISTS idx_prod_master_branch ON public.product_master(branch_id)';
  EXECUTE 'CREATE INDEX IF NOT EXISTS idx_prod_master_updated ON public.product_master(updated_at DESC)';
  EXECUTE 'CREATE INDEX IF NOT EXISTS idx_prod_master_name ON public.product_master(name)';
  EXECUTE 'CREATE INDEX IF NOT EXISTS idx_prod_master_prod_name ON public.product_master(product_name)';
  EXECUTE 'CREATE INDEX IF NOT EXISTS idx_stock_batches_branch_prod ON public.stock_batches(branch_id, product_id)';
  EXECUTE 'CREATE INDEX IF NOT EXISTS idx_stock_batches_search ON public.stock_batches(product_id, batch_number)';
  EXECUTE 'CREATE INDEX IF NOT EXISTS idx_stock_batches_updated ON public.stock_batches(updated_at DESC)';
  EXECUTE 'CREATE INDEX IF NOT EXISTS idx_sales_inv_branch_fy ON public.sales_invoices(branch_id, financial_year, entry_no)';
  EXECUTE 'CREATE INDEX IF NOT EXISTS idx_sales_items_inv ON public.sales_items(invoice_no)';
  EXECUTE 'CREATE INDEX IF NOT EXISTS idx_pur_entries_branch_fy ON public.purchase_entries(branch_id, financial_year, entry_no)';
  EXECUTE 'CREATE INDEX IF NOT EXISTS idx_pur_items_entry ON public.purchase_items(entry_no)';
  EXECUTE 'CREATE INDEX IF NOT EXISTS idx_sales_ret_inv_branch ON public.sales_return_invoices(branch_id, financial_year)';
  EXECUTE 'CREATE INDEX IF NOT EXISTS idx_pur_ret_entries_branch ON public.purchase_return_entries(branch_id, financial_year)';
  EXECUTE 'CREATE INDEX IF NOT EXISTS idx_stock_adj_branch ON public.stock_adjustments(branch_id, financial_year)';
  EXECUTE 'CREATE INDEX IF NOT EXISTS idx_idemp_keys_lookup ON public.idempotency_keys(branch_id, operation_type, reference_no)';
  EXECUTE 'CREATE INDEX IF NOT EXISTS idx_idemp_log_lookup ON public.idempotency_log(branch_id, operation_type, reference_no)';
  EXECUTE 'CREATE INDEX IF NOT EXISTS idx_stock_ledger_batch_hist ON public.stock_ledger(branch_id, product_id, batch_number, created_at DESC)';
  EXECUTE 'CREATE INDEX IF NOT EXISTS idx_active_computers_term ON public.active_computers(branch_id, terminal_id, last_seen_at DESC)';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Index execution notice: %', SQLERRM;
END $$;

-- -------------------------------------------------------------------------
-- STEP 8: SAFE STOCK CONSTRAINT
-- -------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'chk_stock_non_negative' AND table_name = 'stock_batches'
    ) THEN
        BEGIN
            ALTER TABLE public.stock_batches ADD CONSTRAINT chk_stock_non_negative CHECK (current_quantity >= 0);
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
    END IF;
END $$;

-- -------------------------------------------------------------------------
-- STEP 9: ACTIVATE REALTIME REPLICATION FOR ALL TABLES
-- Configures Full Replica Identity and Adds Tables to supabase_realtime
-- -------------------------------------------------------------------------
DO $$
DECLARE
  tbl_name text;
  realtime_tables text[] := ARRAY[
    'product_master',
    'stock_batches',
    'sales_invoices',
    'sales_items',
    'purchase_entries',
    'purchase_items',
    'sales_return_invoices',
    'sales_return_items',
    'purchase_return_entries',
    'purchase_return_items',
    'stock_adjustments',
    'stock_adjustment_items',
    'stock_write_offs',
    'stock_ledger',
    'patients',
    'customers',
    'suppliers'
  ];
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    FOREACH tbl_name IN ARRAY realtime_tables LOOP
      IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = tbl_name) THEN
        BEGIN
          EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL', tbl_name);
          IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = tbl_name) THEN
            EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', tbl_name);
          END IF;
        EXCEPTION WHEN OTHERS THEN
          RAISE NOTICE 'Skipping publication for %: %', tbl_name, SQLERRM;
        END;
      END IF;
    END LOOP;
  END IF;
END $$;

-- -------------------------------------------------------------------------
-- STEP 10: ROW LEVEL SECURITY & PERMISSIONS
-- -------------------------------------------------------------------------
DO $$
DECLARE
  t text;
BEGIN
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
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;

-- Notify PostgREST to immediately refresh its schema cache
NOTIFY pgrst, 'reload schema';
