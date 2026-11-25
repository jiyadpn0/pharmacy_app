-- =========================================================================
-- PHARMA PRO ERP - SUPABASE SERVER v4.2.3 UPDATE & REGISTRATION SCRIPT
-- Execute in Supabase Dashboard -> SQL Editor
-- (Registers v4.2.3 as the minimum required version, enforcing auto-update)
-- =========================================================================

-- 1. Create or extend application version registry table
CREATE TABLE IF NOT EXISTS public.app_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    version TEXT NOT NULL UNIQUE,
    release_name TEXT DEFAULT 'PharmaPro ERP v4.2.3',
    release_notes TEXT,
    download_url TEXT,
    is_mandatory BOOLEAN DEFAULT FALSE,
    min_supported_version TEXT DEFAULT '4.2.2',
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

-- 2. Register / Upsert version 4.2.3 with min_supported_version = 4.2.2
INSERT INTO public.app_versions (
    version,
    release_name,
    release_notes,
    download_url,
    is_mandatory,
    min_supported_version,
    updated_at
) VALUES (
    '4.2.3',
    'PharmaPro ERP v4.2.3 (Native Standalone Updater & Remote Policy)',
    'v4.2.3 Update: Dedicated native updater.exe utility, Supabase app_versions policy auto-fetch, mandatory update enforcement dialogs, and robust LAN wipe lock isolation.',
    'https://github.com/jiyadpn0/pharmacy_app/releases/download/v4.2.3/PharmacyERP_v4.2.3_Portable.zip',
    TRUE,
    '4.2.2',
    NOW()
)
ON CONFLICT (version) DO UPDATE SET
    release_name = EXCLUDED.release_name,
    release_notes = EXCLUDED.release_notes,
    download_url = EXCLUDED.download_url,
    is_mandatory = EXCLUDED.is_mandatory,
    min_supported_version = EXCLUDED.min_supported_version,
    updated_at = NOW();

-- 3. Register version into system_security configuration
INSERT INTO public.system_security (setting_key, setting_value, is_enabled, updated_at)
VALUES
    ('APP_VERSION', '4.2.3', 1, NOW()),
    ('LATEST_VERSION', '4.2.3', 1, NOW()),
    ('MIN_REQUIRED_VERSION', '4.2.2', 1, NOW())
ON CONFLICT (setting_key) DO UPDATE SET
    setting_value = EXCLUDED.setting_value,
    is_enabled = EXCLUDED.is_enabled,
    updated_at = NOW();

-- 4. RPC function to query active server app version
CREATE OR REPLACE FUNCTION public.fn_get_server_app_version()
RETURNS JSONB AS $$
BEGIN
    RETURN jsonb_build_object(
        'current_version', '4.2.3',
        'min_supported_version', '4.2.2',
        'is_mandatory', true,
        'download_url', 'https://github.com/jiyadpn0/pharmacy_app/releases/download/v4.2.3/PharmacyERP_v4.2.3_Portable.zip',
        'updated_at', NOW()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.fn_get_server_app_version() TO anon, authenticated, service_role;
