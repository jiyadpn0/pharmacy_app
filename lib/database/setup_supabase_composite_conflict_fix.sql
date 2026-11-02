-- ============================================================================
-- SUPABASE COMPOSITE UNIQUE CONSTRAINTS FOR MULTI-TERMINAL PARALLEL ENTRIES
-- Applies to Sales, Purchases, Returns, Stock Adjustments, and Write-Offs
-- ============================================================================

-- Step 1: Ensure terminal_id column exists on all transaction tables
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';
ALTER TABLE public.purchase_entries ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';
ALTER TABLE public.sales_return_invoices ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';
ALTER TABLE public.purchase_return_entries ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';
ALTER TABLE public.stock_adjustments ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';

-- Step 2: Remove legacy single-column unique constraints on entry_no if present
ALTER TABLE public.sales_invoices DROP CONSTRAINT IF EXISTS sales_invoices_entry_no_key;
ALTER TABLE public.purchase_entries DROP CONSTRAINT IF EXISTS purchase_entries_entry_no_key;
ALTER TABLE public.sales_return_invoices DROP CONSTRAINT IF EXISTS sales_return_invoices_entry_no_key;
ALTER TABLE public.purchase_return_entries DROP CONSTRAINT IF EXISTS purchase_return_entries_entry_no_key;
ALTER TABLE public.stock_adjustments DROP CONSTRAINT IF EXISTS stock_adjustments_entry_no_key;

-- Step 3: Create composite unique indexes (Entry No + Terminal ID)
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
