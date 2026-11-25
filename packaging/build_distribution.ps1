# =====================================================================
# Sahakar Pharmacy ERP - Production Distribution & Packaging Script
# =====================================================================

$ErrorActionPreference = "Stop"

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ReleaseDir = Join-Path $ProjectRoot "build\windows\x64\runner\Release"
$DistDir = Join-Path $ProjectRoot "dist"
$Version = "3.6.2"
$ZipName = "PharmacyERP_v${Version}_Portable.zip"
$ZipPath = Join-Path $DistDir $ZipName

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Sahakar Pharmacy ERP - Windows Distribution Packager" -ForegroundColor Cyan
Write-Host " Version: $Version" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Verify Release Build Output
$ExePath = Join-Path $ReleaseDir "pharmacy_app.exe"
if (-not (Test-Path $ExePath)) {
    Write-Error "Release build not found at: $ExePath. Please run 'flutter build windows --release' first."
    exit 1
}

Write-Host "[1/5] Release binary verified: $ExePath" -ForegroundColor Green

# 2. Ensure dist directory exists and is clean
if (-not (Test-Path $DistDir)) {
    New-Item -ItemType Directory -Path $DistDir | Out-Null
}

# 3. Create Deployment Readme in Release and Dist
$ReadmeContent = @"
===================================================================
 Sahakar Pharmacy ERP v${Version} - Windows Deployment & User Guide
===================================================================

REQUIREMENTS:
- Windows 10 (64-bit) or Windows 11
- Microsoft Visual C++ 2015-2022 Redistributable (x64)
- 4 GB RAM minimum (8 GB recommended for high-volume retail billing)
- Thermal Receipt Printer (80mm/58mm ESC/POS supported)
- USB Barcode Scanner (Plug & Play HID keyboard mode supported)

INSTALLATION OPTIONS:
Option A (Installer Setup):
  Run 'PharmacyERP_v${Version}_Setup.exe' and follow the setup wizard.
  This installs desktop shortcuts and program menu entries.

Option B (Portable / USB Counter Mode):
  Extract '$ZipName' to your desired drive (e.g., 'C:\SahakarERP\').
  Run 'pharmacy_app.exe' directly.

DATA INTEGRITY & SAFETY:
- The ERP stores local transactional data and offline stock queues
  using SQLite FFI with WAL (Write-Ahead Logging).
- Local databases and automated backups are preserved across updates.
- Automatic day-end closings generate mirrored backups in the 'Backups'
  directory with atomic SQLite VACUUM INTO snapshots.

SUPPORT & UPDATES:
- Repository: https://github.com/jiyadpn0/pharmacy_app
===================================================================
"@

$ReadmePath = Join-Path $DistDir "README_INSTALLATION.txt"
Set-Content -Path $ReadmePath -Value $ReadmeContent -Encoding UTF8
Write-Host "[2/5] Created distribution readme: $ReadmePath" -ForegroundColor Green

# 4. Create Standalone Portable ZIP
Write-Host "[3/5] Creating Portable Distribution Archive ($ZipName)..." -ForegroundColor Yellow
if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}

Compress-Archive -Path "$ReleaseDir\*" -DestinationPath $ZipPath -CompressionLevel Optimal
$ZipSizeMB = [math]::Round((Get-Item $ZipPath).Length / 1MB, 2)
Write-Host "[3/5] Portable ZIP created successfully: $ZipPath ($ZipSizeMB MB)" -ForegroundColor Green

# 5. Compute SHA-256 Checksums for Release Artifacts
Write-Host "[4/5] Computing SHA-256 cryptographic checksums..." -ForegroundColor Yellow
$Checksums = @()
$Checksums += "SHA-256 Checksums for Sahakar Pharmacy ERP v${Version} Release Artifacts"
$Checksums += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$Checksums += "--------------------------------------------------------------------------------"

$ZipHash = (Get-FileHash -Path $ZipPath -Algorithm SHA256).Hash
$Checksums += "$ZipHash  $ZipName"

$ExeHash = (Get-FileHash -Path $ExePath -Algorithm SHA256).Hash
$Checksums += "$ExeHash  pharmacy_app.exe (Release Binary)"

$ChecksumsPath = Join-Path $DistDir "CHECKSUMS.sha256"
Set-Content -Path $ChecksumsPath -Value $Checksums -Encoding UTF8
Write-Host "[4/5] Checksums saved to: $ChecksumsPath" -ForegroundColor Green

# 6. Check for Inno Setup Compiler (ISCC.exe)
Write-Host "[5/5] Scanning for Inno Setup Compiler (ISCC.exe)..." -ForegroundColor Yellow
$IsccCandidates = @(
    "iscc.exe",
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
)

$IsccFound = $null
foreach ($c in $IsccCandidates) {
    if (Get-Command $c -ErrorAction SilentlyContinue) {
        $IsccFound = $c
        break
    }
    if (Test-Path $c) {
        $IsccFound = $c
        break
    }
}

if ($IsccFound) {
    Write-Host "Found Inno Setup Compiler at: $IsccFound" -ForegroundColor Cyan
    $IssPath = Join-Path $PSScriptRoot "installer.iss"
    Write-Host "Compiling Windows Installer ($IssPath)..." -ForegroundColor Yellow
    & $IsccFound $IssPath
    $InstallerPath = Join-Path $DistDir "PharmacyERP_v${Version}_Setup.exe"
    if (Test-Path $InstallerPath) {
        $InstallerSizeMB = [math]::Round((Get-Item $InstallerPath).Length / 1MB, 2)
        Write-Host "Windows Installer generated successfully: $InstallerPath ($InstallerSizeMB MB)" -ForegroundColor Green
    }
} else {
    Write-Host "Note: Inno Setup (ISCC.exe) was not detected on this machine." -ForegroundColor DarkYellow
    Write-Host "The Inno Setup script has been prepared at: 'packaging\installer.iss'." -ForegroundColor DarkYellow
    Write-Host "You can compile it anytime by installing Inno Setup 6 (https://jrsoftware.org/isdl.php) and running: ISCC packaging\installer.iss" -ForegroundColor DarkYellow
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Packaging Completed Successfully!" -ForegroundColor Green
Write-Host " Output Directory: $DistDir" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
