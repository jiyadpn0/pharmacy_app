-- =========================================================================
-- PHARMA PRO ERP - WIPE ALL TRANSACTIONS (SALES, PURCHASES, RETURNS, BATCHES)
-- KEEP PRODUCT MASTER LIST INTACT ON SUPABASE SERVER & LOCAL DATABASE
-- =========================================================================
-- Run this script in Supabase Dashboard -> SQL Editor to clear all transaction
-- records from the Cloud Server while preserving product catalog & master data.

-- 1. Sales & Counter Billing
TRUNCATE TABLE sales_items CASCADE;
TRUNCATE TABLE sales_invoices CASCADE;

-- 2. Purchase Entries & Inward Invoices
TRUNCATE TABLE purchase_items CASCADE;
TRUNCATE TABLE purchase_entries CASCADE;

-- 3. Sales Returns & Credit Notes
TRUNCATE TABLE sales_return_items CASCADE;
TRUNCATE TABLE sales_return_invoices CASCADE;

-- 4. Purchase Returns & Debit Notes
TRUNCATE TABLE purchase_return_items CASCADE;
TRUNCATE TABLE purchase_return_entries CASCADE;

-- 5. Prescriptions & Stock Adjustments
TRUNCATE TABLE prescription_items CASCADE;
TRUNCATE TABLE prescriptions CASCADE;
TRUNCATE TABLE stock_adjustment_items CASCADE;
TRUNCATE TABLE stock_adjustments CASCADE;

-- 6. Stock Write-offs & Damages
TRUNCATE TABLE stock_write_offs CASCADE;

-- 7. Inventory Batches
TRUNCATE TABLE stock_batches CASCADE;

-- 8. Payments, Ledgers & Summaries
TRUNCATE TABLE patient_payments CASCADE;
TRUNCATE TABLE supplier_payments CASCADE;
TRUNCATE TABLE supplier_credit_notes CASCADE;
TRUNCATE TABLE daily_financial_summaries CASCADE;

-- 9. Logs & Telemetry
TRUNCATE TABLE cloud_audit_logs CASCADE;
TRUNCATE TABLE telemetry_logs CASCADE;

-- =========================================================================
-- NOTE: The following Master Data tables remain COMPLETELY INTACT:
--   - product_master (Registered Stocks & Catalog)
--   - categories
--   - manufacturers
--   - racks
--   - generics
--   - suppliers
--   - patients
--   - doctors
--   - accounts
--   - staff
-- =========================================================================
