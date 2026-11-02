import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/db_helper.dart';
import '../../providers/pharmacy_provider.dart';
import '../../services/update_checker_service.dart';
import '../../utils/app_dialogs.dart';
import '../../utils/theme_constants.dart';

class DatabaseBackupTab extends StatefulWidget {
  final Function(String, {bool isError}) showSnackBar;
  final Function(String, String) showErrorDialog;
  final VoidCallback checkGitHubUpdates;

  const DatabaseBackupTab({
    super.key,
    required this.showSnackBar,
    required this.showErrorDialog,
    required this.checkGitHubUpdates,
  });

  @override
  State<DatabaseBackupTab> createState() => _DatabaseBackupTabState();
}

class _DatabaseBackupTabState extends State<DatabaseBackupTab> {
  int _backupRetentionDays = 30;
  bool _autoUpdateEnabled = true;
  String _secondaryBackupPath = '';

  @override
  void initState() {
    super.initState();
    _loadBackupSettings();
  }

  Future<void> _loadBackupSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _backupRetentionDays = prefs.getInt('backup_retention_days') ?? 30;
        _autoUpdateEnabled = prefs.getBool('auto_update_check_enabled') ?? true;
        _secondaryBackupPath = prefs.getString('secondary_backup_path') ?? '';
      });
    }
  }

  Future<void> _pickSecondaryBackupDirectory() async {
    try {
      final selectedDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: 'Select Secondary USB / External Backup Folder',
      );
      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('secondary_backup_path', selectedDirectory);
        setState(() {
          _secondaryBackupPath = selectedDirectory;
        });
        widget.showSnackBar("Secondary USB backup destination set: $selectedDirectory");
      }
    } catch (e) {
      widget.showErrorDialog("Folder Selection Error", "Could not select directory: $e");
    }
  }

  Future<void> _clearSecondaryBackupDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('secondary_backup_path');
    setState(() {
      _secondaryBackupPath = '';
    });
    widget.showSnackBar("Secondary USB backup destination cleared.");
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppStyles.h2Of(context)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: c.secondaryText, fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PharmacyProvider>(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Database Management", "Ensure your data is safe and synchronized."),
        const SizedBox(height: 24),
        _buildUnifiedDatabaseBackupCard(provider),
        const SizedBox(height: 24),
        _buildBatchConsolidationCard(provider),
        const SizedBox(height: 32),
        _buildBackupAndUpdatePreferences(),
        const SizedBox(height: 48),
        _buildDbStats(provider),
      ],
    );
  }

  Widget _buildUnifiedDatabaseBackupCard(PharmacyProvider provider) {
    return Container(
      width: 624,
      padding: const EdgeInsets.all(24),
      decoration: AppStyles.cardDecorationOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.shield_outlined, color: Colors.teal, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Unified Database Backup & Recovery",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _backupRetentionDays > 0
                          ? "Automatic snapshots kept for $_backupRetentionDays days. Cloud and USB recovery supported."
                          : "Automatic snapshots kept indefinitely. Cloud and USB recovery supported.",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _performBackup(provider),
                  icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                  label: const Text("CREATE BACKUP NOW", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showRestoreHubDialog(provider),
                  icon: const Icon(Icons.history_rounded, size: 18),
                  label: const Text("RESTORE HUB", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade800,
                    side: BorderSide(color: Colors.orange.shade800, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              IconButton(
                tooltip: "Import External .db File (USB / Pendrive)",
                onPressed: () => _importExternalDbBackup(provider),
                icon: const Icon(Icons.file_open_rounded),
                color: Colors.indigo,
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.indigo.shade200, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBackupAndUpdatePreferences() {
    final c = AppColors.of(context);
    return Container(
      width: 624,
      padding: const EdgeInsets.all(28),
      decoration: AppStyles.cardDecorationOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("BACKUP & UPDATE PREFERENCES",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.5)),
          const SizedBox(height: 20),

          // 1. Backup Retention Period
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.timer_rounded, color: Colors.teal, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Automatic Backup Retention Period", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      _backupRetentionDays > 0
                          ? "Automatically purge backup files older than $_backupRetentionDays days."
                          : "Keep all backups indefinitely (never delete automatically).",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: c.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _backupRetentionDays,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: c.primaryText),
                    items: const [
                      DropdownMenuItem(value: 7, child: Text("7 Days")),
                      DropdownMenuItem(value: 15, child: Text("15 Days")),
                      DropdownMenuItem(value: 30, child: Text("30 Days (Default)")),
                      DropdownMenuItem(value: 60, child: Text("60 Days")),
                      DropdownMenuItem(value: 90, child: Text("90 Days")),
                      DropdownMenuItem(value: 180, child: Text("180 Days")),
                      DropdownMenuItem(value: 365, child: Text("1 Year (365 Days)")),
                      DropdownMenuItem(value: 0, child: Text("Keep All (Unlimited)")),
                    ],
                    onChanged: (val) async {
                      if (val == null) return;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt('backup_retention_days', val);
                      setState(() {
                        _backupRetentionDays = val;
                      });
                      await DbHelper.instance.cleanupOldBackups(keepDays: val);
                      widget.showSnackBar(val > 0 ? "Backup retention period updated to $val days." : "Backup retention set to Keep All.");
                    },
                  ),
                ),
              ),
            ],
          ),

          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider()),

          // 2. Secondary USB / External Drive Auto-Backup Mirroring
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.usb_rounded, color: Colors.amber, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Secondary USB / External Drive Auto-Backup", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      _secondaryBackupPath.isNotEmpty
                          ? "Auto-mirror verified snapshots to: $_secondaryBackupPath"
                          : "Configure a USB drive or NAS folder to automatically receive backup copies.",
                      style: TextStyle(
                        fontSize: 12,
                        color: _secondaryBackupPath.isNotEmpty ? Colors.amber.shade400 : Colors.grey,
                        fontWeight: _secondaryBackupPath.isNotEmpty ? FontWeight.w600 : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _pickSecondaryBackupDirectory,
                icon: const Icon(Icons.folder_open_rounded, size: 15),
                label: Text(_secondaryBackupPath.isNotEmpty ? "CHANGE" : "SELECT FOLDER", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade900,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              if (_secondaryBackupPath.isNotEmpty) ...[
                const SizedBox(width: 6),
                IconButton(
                  tooltip: "Clear USB Backup Path",
                  onPressed: _clearSecondaryBackupDirectory,
                  icon: const Icon(Icons.close_rounded, size: 18, color: Colors.redAccent),
                ),
              ],
            ],
          ),

          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider()),

          // 3. Auto Update Switch
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.sync_rounded, color: Colors.blue, size: 22),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Automatic Update Check on Startup", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    SizedBox(height: 2),
                    Text("Silently check for software updates when the application starts.", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              Switch(
                value: _autoUpdateEnabled,
                activeThumbColor: Colors.blue,
                onChanged: (val) async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('auto_update_check_enabled', val);
                  setState(() {
                    _autoUpdateEnabled = val;
                  });
                  widget.showSnackBar(val ? "Automatic update check enabled." : "Automatic update check disabled.");
                },
              ),
            ],
          ),

          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider()),

          // 3. Manual Check for Updates
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.indigo.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.system_update_rounded, color: Colors.indigo, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Manual Check for Updates", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text("Installed Version: v${UpdateCheckerService.currentVersion} (Commercial Build)", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => widget.checkGitHubUpdates(),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text("CHECK NOW", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDbStats(PharmacyProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Database Diagnostics", "Real-time summary of records currently stored in your software."),
        const SizedBox(height: 24),
        Container(
          width: 624,
          padding: const EdgeInsets.all(24),
          decoration: AppStyles.cardDecorationOf(context),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem("Total Sales", provider.sales.length.toString(), Colors.blue),
              _statItem("Purchases", provider.purchases.length.toString(), Colors.indigo),
              _statItem("Products", provider.productMaster.length.toString(), Colors.teal),
              _statItem("Patients", provider.patients.length.toString(), Colors.orange),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          "Tip: If records aren't showing in History screens, check your Date Filters. Imported records will appear under their original dates.",
          style: TextStyle(fontSize: 12, color: Colors.blueGrey, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
      ],
    );
  }

  void _performBackup(PharmacyProvider provider) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final path = await provider.performManualBackup();

      if (!mounted) return;
      Navigator.pop(context); // Close loader

      AppDialogs.showPathDialog(
        context: context,
        title: "Backup Complete",
        message: "A timestamped database backup was created successfully:",
        path: path,
        icon: Icons.check_circle,
        iconColor: Colors.teal,
      );
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      widget.showErrorDialog("Backup Error", e.toString());
    }
  }

  void _showRestoreHubDialog(PharmacyProvider provider) async {
    try {
      final backups = await provider.getAvailableBackups();

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.history_rounded, color: Colors.deepOrange),
              SizedBox(width: 8),
              Text("Database Restore Hub"),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 350,
            child: backups.isEmpty
                ? const Center(child: Text("No backup files found. Click 'Local Backup' to create one."))
                : ListView.builder(
                    itemCount: backups.length,
                    itemBuilder: (context, idx) {
                      final b = backups[idx];
                      final File file = b['file'] as File;
                      final DateTime dt = b['date'] as DateTime;
                      final int sizeBytes = b['size'] as int;
                      final double sizeMb = sizeBytes / (1024 * 1024);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.storage_rounded, color: Colors.blue),
                          title: Text(b['name'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Text(
                            "${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')} • ${sizeMb.toStringAsFixed(2)} MB",
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
                            icon: const Icon(Icons.restore_rounded, size: 16),
                            label: const Text("RESTORE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              _confirmAndRestore(provider, file);
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("CLOSE"),
            )
          ],
        ),
      );
    } catch (e) {
      widget.showErrorDialog("Error", "Failed to load backups: $e");
    }
  }

  void _confirmAndRestore(PharmacyProvider provider, File file) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Database Restore"),
        content: const Text(
          "WARNING: Restoring a backup will OVERWRITE all current database records! "
          "The app will restart after restore completes.\n\nAre you sure you want to proceed?",
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const Center(child: CircularProgressIndicator()),
              );

              final success = await provider.restoreFromBackup(file);

              if (!mounted) return;
              Navigator.pop(context);

              if (success) {
                widget.showSnackBar("Database restored successfully! Restarting data layers...");
                await provider.loadFromDatabase();
              } else {
                widget.showErrorDialog("Restore Failed", "Failed to restore database from backup file.");
              }
            },
            child: const Text("OVERWRITE & RESTORE"),
          ),
        ],
      ),
    );
  }

  void _importExternalDbBackup(PharmacyProvider provider) async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db', 'sqlite', 'bak'],
      );

      if (result != null && result.files.single.path != null) {
        final File selectedFile = File(result.files.single.path!);
        if (!mounted) return;
        _confirmAndRestore(provider, selectedFile);
      }
    } catch (e) {
      widget.showErrorDialog("Import Error", "Failed to pick file: $e");
    }
  }

  Widget _buildBatchConsolidationCard(PharmacyProvider provider) {
    return Container(
      width: 624,
      padding: const EdgeInsets.all(24),
      decoration: AppStyles.cardDecorationOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.cleaning_services_rounded, color: Colors.indigo, size: 28),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Batch Audit & Consolidation Tool",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "Merges duplicate batch entries and cleans up zero-stock records for faster database queries.",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _runBatchConsolidation(provider),
              icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
              label: const Text("CONSOLIDATE & CLEAN BATCHES NOW", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _runBatchConsolidation(PharmacyProvider provider) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final resultMsg = await provider.auditAndConsolidateStockBatches();
      if (!mounted) return;
      Navigator.pop(context);

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.green),
              SizedBox(width: 8),
              Text("Batch Consolidation Result"),
            ],
          ),
          content: Text(resultMsg.isEmpty ? "All stock batches are clean and consolidated." : resultMsg),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      widget.showErrorDialog("Consolidation Failed", e.toString());
    }
  }
}
