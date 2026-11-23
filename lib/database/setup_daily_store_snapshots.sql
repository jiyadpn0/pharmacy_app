-- ==============================================================================
-- TIER-1 ENTERPRISE AUTOMATED DAILY STORE SNAPSHOTS & OWNER MOBILE PULSE SCHEMA
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.daily_store_snapshots (
    id TEXT PRIMARY KEY,
    snapshot_date DATE NOT NULL,
    branch_id TEXT NOT NULL DEFAULT 'MAIN_STORE',
    terminal_id TEXT NOT NULL DEFAULT 'POS-01',
    total_invoices INTEGER NOT NULL DEFAULT 0,
    total_sales NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    cash_sales NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    upi_sales NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    card_sales NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    credit_sales NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    total_cgst NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    total_sgst NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    total_gst NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    total_net_sales NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    total_purchase_cost NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    gross_margin_est NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    total_inventory_valuation_cost NUMERIC(14,2) NOT NULL DEFAULT 0.00,
    total_inventory_valuation_mrp NUMERIC(14,2) NOT NULL DEFAULT 0.00,
    total_active_batches INTEGER NOT NULL DEFAULT 0,
    total_products_count INTEGER NOT NULL DEFAULT 0,
    low_stock_items_count INTEGER NOT NULL DEFAULT 0,
    expiring_soon_count INTEGER NOT NULL DEFAULT 0,
    terminal_breakdown JSONB NOT NULL DEFAULT '[]'::jsonb,
    raw_payload JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for instant date-range queries & multi-branch reporting
CREATE INDEX IF NOT EXISTS idx_snapshots_date ON public.daily_store_snapshots(snapshot_date DESC);
CREATE INDEX IF NOT EXISTS idx_snapshots_branch ON public.daily_store_snapshots(branch_id);

-- Enable Row Level Security (RLS)
ALTER TABLE public.daily_store_snapshots ENABLE ROW LEVEL SECURITY;

-- Allow authenticated and anon access with merge-duplicates policy
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'daily_store_snapshots' AND policyname = 'Allow all access to daily_store_snapshots'
    ) THEN
        CREATE POLICY "Allow all access to daily_store_snapshots"
        ON public.daily_store_snapshots
        FOR ALL
        USING (true)
        WITH CHECK (true);
    END IF;
END $$;
