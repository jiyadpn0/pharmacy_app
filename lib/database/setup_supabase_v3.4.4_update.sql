-- =========================================================================
-- PHARMA PRO ERP - SUPABASE SERVER v3.4.4 UPDATE & REGISTRATION SCRIPT
-- Execute in Supabase Dashboard -> SQL Editor
-- (Non-destructive: Updates version metadata, adds app_versions table, and
--  synchronizes active computer / terminal version telemetry)
-- =========================================================================

-- 1. Create or extend application version registry table
CREATE TABLE IF NOT EXISTS public.app_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    version TEXT NOT NULL UNIQUE,
    release_name TEXT DEFAULT 'PharmaPro ERP v3.4.4',
    release_notes TEXT,
    download_url TEXT,
    is_mandatory BOOLEAN DEFAULT FALSE,
    min_supported_version TEXT DEFAULT '3.4.0',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable Row Level Security and configure open read access
ALTER TABLE public.app_versions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow Read app_versions" ON public.app_versions;
CREATE POLICY "Allow Read app_versions"
ON public.app_versions FOR SELECT
USING (true);

DROP POLICY IF EXISTS "Allow All app_versions" ON public.app_versions;
CREATE POLICY "Allow All app_versions"
ON public.app_versions FOR ALL
USING (true)
WITH CHECK (true);

GRANT ALL ON public.app_versions TO anon, authenticated, service_role;

-- 2. Register / Upsert version 3.4.4
INSERT INTO public.app_versions (
    version,
    release_name,
    release_notes,
    is_mandatory,
    min_supported_version,
    updated_at
) VALUES (
    '3.4.4',
    'PharmaPro ERP v3.4.4 Release',
    'v3.4.4 Update: Multi-PC Supabase terminal tracking, inventory convergence synchronization, and security optimizations.',
    FALSE,
    '3.4.0',
    NOW()
)
ON CONFLICT (version) DO UPDATE SET
    release_name = EXCLUDED.release_name,
    release_notes = EXCLUDED.release_notes,
    is_mandatory = EXCLUDED.is_mandatory,
    min_supported_version = EXCLUDED.min_supported_version,
    updated_at = NOW();

-- 3. Register version into system_security configuration
INSERT INTO public.system_security (setting_key, setting_value, is_enabled, updated_at)
VALUES
    ('APP_VERSION', '3.4.4', 1, NOW()),
    ('LATEST_VERSION', '3.4.4', 1, NOW()),
    ('MIN_REQUIRED_VERSION', '3.4.0', 1, NOW())
ON CONFLICT (setting_key) DO UPDATE SET
    setting_value = EXCLUDED.setting_value,
    is_enabled = EXCLUDED.is_enabled,
    updated_at = NOW();

-- 4. Ensure active_computers telemetry table has app_version column and defaults to 3.4.4
CREATE TABLE IF NOT EXISTS public.active_computers (
    machine_id TEXT PRIMARY KEY,
    branch_id TEXT NOT NULL DEFAULT 'MAIN_STORE',
    terminal_id TEXT NOT NULL DEFAULT 'POS-01',
    app_version TEXT DEFAULT '3.4.4',
    last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.active_computers ADD COLUMN IF NOT EXISTS app_version TEXT DEFAULT '3.4.4';

UPDATE public.active_computers
SET app_version = '3.4.4'
WHERE app_version IS NULL OR app_version = '' OR app_version = '3.3.7';

-- 5. RPC function to query active server app version
CREATE OR REPLACE FUNCTION public.fn_get_server_app_version()
RETURNS JSONB AS $$
BEGIN
    RETURN jsonb_build_object(
        'current_version', '3.4.4',
        'min_supported_version', '3.4.0',
        'updated_at', NOW()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.fn_get_server_app_version() TO anon, authenticated, service_role;
