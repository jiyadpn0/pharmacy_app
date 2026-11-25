import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/db_helper.dart';
import '../../providers/pharmacy_provider.dart';
import '../../services/backup_service.dart';
import '../../services/database_maintenance_service.dart';
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
  DatabaseHealthReport? _healthReport;
  bool _isLoadingHealth = false;
  PreFlightAuditReport? _auditReport;
  bool _isAuditing = false;
  bool _isHealing = false;
  PhysicalBackupStatus? _physicalStatus;
  bool _isLoadingPhysicalStatus = false;
  bool _isMirroringUsb = false;

  @override
  void initState() {
    super.initState();
    _loadBackupSettings();
    _fetchHealthReport();
    _runPreFlightAudit(silent: true);
    _fetchPhysicalBackupStatus();
  }

  Future<void> _fetchHealthReport() async {
    if (!mounted) return;
    setState(() => _isLoadingHealth = true);
    try {
      final rep = await DatabaseMaintenanceService.instance.getHealthReport();
      if (mounted) {
        setState(() {
          _healthReport = rep;
          _isLoadingHealth = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingHealth = false);
    }
  }

  Future<void> _runPreFlightAudit({bool silent = false}) async {
    if (!mounted) return;
    setState(() => _isAuditing = true);
    try {
      final audit = await DatabaseMaintenanceService.instance.runPreFlightAudit();
      if (mounted) {
        setState(() {
          _auditReport = audit;
          _isAuditing = false;
        });
        if (!silent) {
          widget.showSnackBar(
            "Pre-Flight DB Audit: ${audit.healthGrade} (${audit.isProductionReady ? 'Production Ready' : 'Optimization Recommended'})",
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAuditing = false);
        if (!silent) widget.showErrorDialog("Audit Failed", e.toString());
      }
    }
  }

  Future<void> _runAutoHealing(PharmacyProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_fix_high_rounded, color: Colors.teal),
            SizedBox(width: 8),
            Text("Run Database Auto-Healing?"),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "This routine will automatically:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text("1. Capture an immutable pre-repair backup snapshot."),
            Text("2. Reconcile current batch stock against immutable ledger history."),
            Text("3. Reset stuck poison-pill sync outbox queues."),
            Text("4. Rebuild all B-Tree indexes (REINDEX) and optimize query planner."),
            SizedBox(height: 12),
            Text(
              "All existing valid transactions and data will be safely preserved.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("START AUTO-HEAL"),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isHealing = true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.teal),
            SizedBox(height: 16),
            Text("Auto-healing database & reconciling ledger...", style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );

    try {
      final healResult = await DatabaseMaintenanceService.instance.performAutoHealing(
        backupCallback: () => provider.performManualBackup(),
        reconcileStock: true,
        unclogOutbox: true,
        vacuumAndReindex: true,
      );

      await provider.loadFromDatabase();
      await _fetchHealthReport();
      final freshAudit = await DatabaseMaintenanceService.instance.runPreFlightAudit();

      if (!mounted) return;
      Navigator.pop(context); // close loader
      setState(() {
        _isHealing = false;
        _auditReport = freshAudit;
      });

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.green),
              SizedBox(width: 8),
              Text("Database Auto-Healing Complete"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(healResult.message, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Text("• Batches Reconciled: ${healResult.batchesReconciled}", style: const TextStyle(fontSize: 12)),
              Text("• Outbox Events Unclogged: ${healResult.uncloggedOutboxEvents}", style: const TextStyle(fontSize: 12)),
              Text("• B-Tree Reindexing: ${healResult.reindexCompleted ? 'Success' : 'Skipped'}", style: const TextStyle(fontSize: 12)),
              Text("• Storage Vacuum: ${healResult.vacuumCompleted ? 'Success' : 'Skipped'}", style: const TextStyle(fontSize: 12)),
              if (healResult.backupCreatedPath != null) ...[
                const SizedBox(height: 8),
                Text("• Safety Backup: ${healResult.backupCreatedPath}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
              child: const Text("DONE"),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        setState(() => _isHealing = false);
        widget.showErrorDialog("Healing Failed", e.toString());
      }
    }
  }

  Future<void> _loadBackupSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _backupRetentionDays = prefs.getInt('backup_retention_days') ?? 30;
        _autoUpdateEnabled = prefs.getBool('auto_update_check_enabled') ?? true;
        _secondaryBackupPath = prefs.getString('secondary_backup_path') ?? '';
      });
      _fetchPhysicalBackupStatus();
    }
  }

  Future<void> _fetchPhysicalBackupStatus() async {
    if (!mounted) return;
    setState(() => _isLoadingPhysicalStatus = true);
    try {
      final status = await BackupService.getPhysicalBackupStatus();
      if (mounted) {
        setState(() {
          _physicalStatus = status;
          _isLoadingPhysicalStatus = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingPhysicalStatus = false);
    }
  }

  Future<void> _mirrorToUsbNow() async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    setState(() => _isMirroringUsb = true);
    try {
      final primaryFiles = await BackupService.getBackupList();
      File targetLocalFile;
      if (primaryFiles.isEmpty) {
        final createdPath = await provider.performManualBackup();
        targetLocalFile = File(createdPath);
      } else {
        targetLocalFile = primaryFiles.first;
      }

      final result = await BackupService.mirrorBackupToSecondaryDrive(targetLocalFile);
      await _fetchPhysicalBackupStatus();
      if (result.success) {
        widget.showSnackBar("Physical USB Backup: ${result.message}");
      } else {
        widget.showErrorDialog("USB Mirror Notice", result.message);
      }
    } catch (e) {
      widget.showErrorDialog("USB Mirror Error", e.toString());
    } finally {
      if (mounted) setState(() => _isMirroringUsb = false);
    }
  }

  Future<void> _autoDetectUsbDrives() async {
    final drives = await BackupService.detectRemovableDrives();
    if (drives.isEmpty) {
      widget.showSnackBar("No removable USB drives detected. Connect a USB drive and try again.", isError: true);
      return;
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.usb_rounded, color: Colors.amber),
            SizedBox(width: 8),
            Text("Detected Removable Drives"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Select a detected volume to configure automatic physical mirroring:"),
            const SizedBox(height: 12),
            ...drives.map((d) {
              final targetFolder = p.join(d, 'Pharmacy_Backups');
              return ListTile(
                leading: const Icon(Icons.usb_rounded, color: Colors.blueGrey),
                title: Text(d, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("Target: $targetFolder", style: const TextStyle(fontSize: 11)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('secondary_backup_path', targetFolder);
                  setState(() => _secondaryBackupPath = targetFolder);
                  await _fetchPhysicalBackupStatus();
                  widget.showSnackBar("Secondary USB backup destination set: $targetFolder");
                },
              );
            }),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
        ],
      ),
    );
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
        await _fetchPhysicalBackupStatus();
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
    await _fetchPhysicalBackupStatus();
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
        _buildPreFlightAuditCard(provider),
        const SizedBox(height: 24),
        _buildPhysicalUsbSentinelCard(provider),
        const SizedBox(height: 24),
        _buildUnifiedDatabaseBackupCard(provider),
        const SizedBox(height: 24),
        _buildDatabaseMaintenanceCard(),
        const SizedBox(height: 24),
        _buildBatchConsolidationCard(provider),
        const SizedBox(height: 32),
        _buildBackupAndUpdatePreferences(),
        const SizedBox(height: 48),
        _buildDbStats(provider),
      ],
    );
  }

  Widget _buildPreFlightAuditCard(PharmacyProvider provider) {
    final audit = _auditReport;
    final isReady = audit?.isProductionReady ?? true;
    final grade = audit?.healthGrade ?? "EXCELLENT";

    Color gradeColor;
    IconData gradeIcon;
    switch (grade) {
      case "CRITICAL":
        gradeColor = Colors.redAccent;
        gradeIcon = Icons.cancel_rounded;
        break;
      case "ATTENTION":
        gradeColor = Colors.amber;
        gradeIcon = Icons.warning_rounded;
        break;
      case "GOOD":
        gradeColor = Colors.lightGreen;
        gradeIcon = Icons.check_circle_outline_rounded;
        break;
      default:
        gradeColor = const Color(0xFF10B981);
        gradeIcon = Icons.verified_rounded;
    }

    return Container(
      width: 624,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isReady ? const Color(0xFF10B981).withValues(alpha: 0.4) : Colors.amber.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: gradeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(gradeIcon, color: gradeColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          "Pre-Flight DB Health & Auto-Healing Hub",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: gradeColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: gradeColor, width: 1),
                          ),
                          child: Text(
                            grade,
                            style: TextStyle(color: gradeColor, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isReady
                          ? "Physical SQLite B-Trees, relational integrity, and stock ledger are synchronized and counter-ready."
                          : "Audit identified items that can be automatically resolved via the Auto-Healing routine.",
                      style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Diagnostic Metrics Grid
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildDiagnosticStat(
                  "B-Tree Integrity",
                  audit != null ? (audit.sqliteIntegrityOk ? "Verified (OK)" : "Corrupted") : "Checking...",
                  Icons.shield_rounded,
                  audit?.sqliteIntegrityOk == false ? Colors.redAccent : Colors.teal,
                ),
                _buildDiagnosticStat(
                  "Foreign Keys",
                  audit != null ? "${audit.foreignKeyViolationsCount} Violations" : "Checking...",
                  Icons.link_rounded,
                  audit != null && audit.foreignKeyViolationsCount > 0 ? Colors.orange : Colors.blue,
                ),
                _buildDiagnosticStat(
                  "Ledger Alignment",
                  audit != null
                      ? (audit.discrepantBatchesCount == 0 ? "100% In Sync" : "${audit.discrepantBatchesCount} Discrepant")
                      : "Checking...",
                  Icons.account_balance_rounded,
                  audit != null && audit.discrepantBatchesCount > 0 ? Colors.amber : const Color(0xFF10B981),
                ),
                _buildDiagnosticStat(
                  "Sync Outbox",
                  audit != null ? "${audit.failedOutboxCount} Blocked" : "0 Blocked",
                  Icons.cloud_sync_rounded,
                  audit != null && audit.failedOutboxCount > 0 ? Colors.redAccent : Colors.lightBlue,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isAuditing ? null : () => _runPreFlightAudit(),
                  icon: _isAuditing
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.analytics_rounded, size: 18),
                  label: Text(
                    _isAuditing ? "AUDITING..." : "RUN DEEP HEALTH AUDIT",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isHealing ? null : () => _runAutoHealing(provider),
                  icon: _isHealing
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_fix_high_rounded, size: 18),
                  label: Text(
                    _isHealing ? "HEALING..." : "AUTO-HEAL & RECONCILE",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhysicalUsbSentinelCard(PharmacyProvider provider) {
    final status = _physicalStatus;
    final isConfigured = status?.isConfigured ?? false;
    final isAccessible = status?.isDriveAccessible ?? false;
    final isSynced = status?.isSyncedWithPrimary ?? false;

    Color badgeColor;
    IconData badgeIcon;
    String badgeText;

    if (!isConfigured) {
      badgeColor = Colors.blueGrey;
      badgeIcon = Icons.usb_off_rounded;
      badgeText = "NOT CONFIGURED";
    } else if (!isAccessible) {
      badgeColor = Colors.redAccent;
      badgeIcon = Icons.disc_full_rounded;
      badgeText = "DRIVE OFFLINE";
    } else if (!isSynced) {
      badgeColor = Colors.amber;
      badgeIcon = Icons.sync_problem_rounded;
      badgeText = "SYNC PENDING";
    } else {
      badgeColor = const Color(0xFF10B981);
      badgeIcon = Icons.verified_user_rounded;
      badgeText = "PLUGGED IN & SYNCED";
    }

    return Container(
      width: 624,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSynced && isAccessible
              ? const Color(0xFF10B981).withValues(alpha: 0.4)
              : (isAccessible ? Colors.amber.withValues(alpha: 0.5) : Colors.blueGrey.withValues(alpha: 0.4)),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(badgeIcon, color: badgeColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          "Physical USB Mirroring Sentinel",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: badgeColor, width: 1),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      status?.statusMessage ?? "Automated real-time mirroring to external USB flash drive or secondary volume.",
                      style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
              if (_isLoadingPhysicalStatus)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Diagnostic Metrics Grid
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildPhysicalMetric(
                      "Target Destination",
                      _secondaryBackupPath.isNotEmpty ? _secondaryBackupPath : "None Configured",
                      Icons.folder_shared_rounded,
                      _secondaryBackupPath.isNotEmpty ? Colors.white : Colors.grey,
                      maxWidth: 250,
                    ),
                    _buildPhysicalMetric(
                      "Drive Status",
                      isAccessible ? "Connected & Writable" : (isConfigured ? "Disconnected / Offline" : "No Drive Set"),
                      isAccessible ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      isAccessible ? Colors.greenAccent : (isConfigured ? Colors.redAccent : Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildPhysicalMetric(
                      "Last Physical Mirror",
                      status?.lastMirroredAt != null ? DateFormat('dd/MM/yyyy HH:mm:ss').format(status!.lastMirroredAt!) : "No Backups Yet",
                      Icons.history_rounded,
                      status?.lastMirroredAt != null ? Colors.white : Colors.grey,
                    ),
                    _buildPhysicalMetric(
                      "Mirrored Storage",
                      status != null ? "${status.totalMirroredFiles} files (${status.totalSizeMb.toStringAsFixed(1)} MB)" : "0 files (0 MB)",
                      Icons.storage_rounded,
                      Colors.cyanAccent,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Action Buttons Bar
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isMirroringUsb ? null : _mirrorToUsbNow,
                  icon: _isMirroringUsb
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync_rounded, size: 16),
                  label: const Text(
                    "MIRROR TO USB NOW",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _pickSecondaryBackupDirectory,
                icon: const Icon(Icons.folder_open_rounded, size: 16),
                label: Text(
                  _secondaryBackupPath.isNotEmpty ? "CHANGE FOLDER" : "SELECT FOLDER",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.tealAccent,
                  side: const BorderSide(color: Colors.teal, width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _autoDetectUsbDrives,
                icon: const Icon(Icons.usb_rounded, size: 16),
                label: const Text("AUTO-DETECT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.amberAccent,
                  side: const BorderSide(color: Colors.amber, width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              if (_secondaryBackupPath.isNotEmpty) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: "Clear USB Backup Path",
                  onPressed: _clearSecondaryBackupDirectory,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhysicalMetric(String label, String value, IconData icon, Color color, {double? maxWidth}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
            const SizedBox(height: 2),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth ?? 180),
              child: Text(
                value,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: color),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
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

              final bool isSuccess = await provider.restoreFromBackup(file);
              const String errMsg = "Failed to restore database.";

              if (!mounted) return;
              Navigator.pop(context);

              if (isSuccess) {
                widget.showSnackBar("Database restored successfully! Restarting data layers...");
                await provider.loadFromDatabase();
              } else {
                widget.showErrorDialog("Restore Failed", errMsg);
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

  Widget _buildDatabaseMaintenanceCard() {
    final rep = _healthReport;
    final isHealthy = rep?.isHealthy ?? true;

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
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.tune_rounded, color: Colors.blue, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          "SQLite Storage Engine & WAL Compaction",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(width: 8),
                        if (_isLoadingHealth)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Flushes uncommitted write logs (WAL), compacts database files, trains query planner index statistics, and audits B-Tree integrity.",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Diagnostic Metrics Grid
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildDiagnosticStat(
                  "Main DB",
                  rep != null ? "${rep.dbSizeMb.toStringAsFixed(2)} MB" : "...",
                  Icons.storage_rounded,
                  Colors.teal,
                ),
                _buildDiagnosticStat(
                  "Write Log (WAL)",
                  rep != null ? "${rep.walSizeMb.toStringAsFixed(2)} MB" : "...",
                  Icons.article_rounded,
                  rep != null && rep.walSizeMb > 10 ? Colors.orange : Colors.blue,
                ),
                _buildDiagnosticStat(
                  "Integrity Check",
                  isHealthy ? "Verified (OK)" : "Warning",
                  isHealthy ? Icons.check_circle_rounded : Icons.warning_rounded,
                  isHealthy ? Colors.green : Colors.redAccent,
                ),
                _buildDiagnosticStat(
                  "Uncompacted",
                  rep != null ? "${rep.walLogFrames - rep.walCheckpointedFrames} frames" : "0 frames",
                  Icons.sync_rounded,
                  Colors.blueGrey,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _runDatabaseMaintenance,
                  icon: const Icon(Icons.speed_rounded, size: 18),
                  label: const Text(
                    "OPTIMIZE & TRUNCATE WAL NOW",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _runIntegrityAuditOnly,
                icon: const Icon(Icons.verified_user_outlined, size: 18),
                label: const Text(
                  "AUDIT INTEGRITY",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue.shade700,
                  side: BorderSide(color: Colors.blue.shade400, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticStat(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color)),
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ],
    );
  }

  Future<void> _runDatabaseMaintenance() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await DatabaseMaintenanceService.instance.performMaintenance(truncateWal: true, runOptimize: true);
      if (!mounted) return;
      Navigator.pop(context); // close loader
      await _fetchHealthReport();
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(
                result.success ? Icons.check_circle_rounded : Icons.warning_rounded,
                color: result.success ? Colors.green : Colors.amber,
              ),
              const SizedBox(width: 8),
              const Text("Database Maintenance Completed"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result.message, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 8),
              Text("• WAL Space Reclaimed: ${result.walFreedMb.toStringAsFixed(2)} MB", style: const TextStyle(fontSize: 12)),
              Text("• Final WAL Size: ${(result.finalWalSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB", style: const TextStyle(fontSize: 12)),
              Text("• Frames Checkpointed: ${result.checkpointedFrames}", style: const TextStyle(fontSize: 12)),
              Text("• SQLite Integrity Status: ${result.quickCheckResult}", style: const TextStyle(fontSize: 12)),
              Text("• Elapsed Time: ${result.duration.inMilliseconds} ms", style: const TextStyle(fontSize: 12)),
            ],
          ),
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
      widget.showErrorDialog("Maintenance Failed", e.toString());
    }
  }

  Future<void> _runIntegrityAuditOnly() async {
    await _fetchHealthReport();
    if (!mounted) return;
    final rep = _healthReport;
    final isOk = rep?.isHealthy ?? false;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(isOk ? Icons.verified_rounded : Icons.error_rounded, color: isOk ? Colors.green : Colors.red),
            const SizedBox(width: 8),
            const Text("B-Tree Integrity Audit"),
          ],
        ),
        content: Text(
          isOk
              ? "SQLite PRAGMA quick_check returned OK.\nDatabase indices and pages are structurally sound and uncorrupted."
              : "Integrity Warning: ${rep?.integrityMessage ?? 'Unknown error'}",
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }
}

