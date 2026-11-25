===================================================================
 Sahakar Pharmacy ERP v3.6.2 - Windows Deployment & User Guide
===================================================================

REQUIREMENTS:
- Windows 10 (64-bit) or Windows 11
- Microsoft Visual C++ 2015-2022 Redistributable (x64)
- 4 GB RAM minimum (8 GB recommended for high-volume retail billing)
- Thermal Receipt Printer (80mm/58mm ESC/POS supported)
- USB Barcode Scanner (Plug & Play HID keyboard mode supported)

INSTALLATION OPTIONS:
Option A (Installer Setup):
  Run 'PharmacyERP_v3.6.2_Setup.exe' and follow the setup wizard.
  This installs desktop shortcuts and program menu entries.

Option B (Portable / USB Counter Mode):
  Extract 'PharmacyERP_v3.6.2_Portable.zip' to your desired drive (e.g., 'C:\SahakarERP\').
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
