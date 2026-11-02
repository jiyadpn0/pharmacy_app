import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';
import '../providers/pharmacy_provider.dart';
import '../services/server_config_service.dart';
import '../services/supabase_sync_service.dart';
import '../services/lan_sync_service.dart';
import '../services/app_notification_service.dart';
import '../services/invoice_recovery_service.dart';
import '../widgets/server_discrepancy_dialog.dart';
import '../utils/app_dialogs.dart';
import '../utils/theme_constants.dart';

class ServerSettingsScreen extends StatefulWidget {
  final bool embedInTab;
  const ServerSettingsScreen({super.key, this.embedInTab = false});

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();

  static Widget buildLiveTransferMonitorCardStatic(SupabaseSyncService syncService, AppThemeColors c) {
    final bool isExport = syncService.isExportMode;
    final double overallPctDouble = syncService.syncProgress.clamp(0.0, 1.0);
    final int overallPct = (overallPctDouble * 100).toInt();
    final int overallRemainingPct = (100 - overallPct).clamp(0, 100);

    final categories = syncService.categorySyncStatuses.isNotEmpty
        ? syncService.categorySyncStatuses
        : [
            CategorySyncStatus(id: 'products', name: 'Registered Products', icon: Icons.inventory_2_rounded),
            CategorySyncStatus(id: 'batches', name: 'Active Stock Batches', icon: Icons.layers_rounded),
            CategorySyncStatus(id: 'sales', name: 'Sales Invoices & Items', icon: Icons.point_of_sale_rounded),
            CategorySyncStatus(id: 'purchases', name: 'Purchase Inward Entries', icon: Icons.shopping_bag_rounded),
            CategorySyncStatus(id: 'sales_returns', name: 'Sales Return Receipts', icon: Icons.assignment_return_rounded),
            CategorySyncStatus(id: 'purchase_returns', name: 'Purchase Return Entries', icon: Icons.unarchive_rounded),
            CategorySyncStatus(id: 'patients', name: 'Customers & Patients', icon: Icons.people_alt_rounded),
            CategorySyncStatus(id: 'suppliers_doctors', name: 'Suppliers & Doctors', icon: Icons.medical_services_rounded),
          ];

    final leftItems = categories.take(4).toList();
    final rightItems = categories.skip(4).take(4).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isExport
            ? (c.isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF))
            : (c.isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isExport ? Colors.indigo.shade400 : Colors.teal.shade400,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isExport ? Icons.upload_rounded : Icons.download_rounded,
                color: isExport ? Colors.indigo.shade700 : Colors.teal.shade700,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isExport
                      ? '📤 EXPORT IN PROGRESS: Local Database ──► Cloud'
                      : '📥 IMPORT IN PROGRESS: Local Database ◄── Cloud',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: isExport ? Colors.indigo.shade900 : Colors.teal.shade900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: syncService.isCancelRequested ? null : () => syncService.cancelSync(),
                icon: const Icon(Icons.cancel_rounded, size: 16, color: Colors.white),
                label: Text(
                  syncService.isCancelRequested ? 'CANCELLING...' : 'CANCEL',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<double>(
            valueListenable: syncService.syncProgressNotifier,
            builder: (context, rawProgress, _) {
              final double pctDouble = rawProgress.clamp(0.0, 1.0);
              final int livePct = (pctDouble * 100).toInt();
              final int liveRemainingPct = (100 - livePct).clamp(0, 100);
              return Column(
                children: [
                  DataStreamAnimationWidget(isExport: isExport, isCompleted: livePct >= 100),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: isExport
                            ? _buildSourceBox(isExport, liveRemainingPct)
                            : _buildTargetBox(isExport, livePct),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: isExport
                            ? _buildTargetBox(isExport, livePct)
                            : _buildSourceBox(isExport, liveRemainingPct),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '⚡ Velocity: ${syncService.currentRecordsPerSec.toInt()} rec/sec',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.isDark ? Colors.grey.shade300 : Colors.grey.shade800),
              ),
              Text(
                '⏱️ ETA: ${syncService.formattedEta}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.isDark ? Colors.grey.shade300 : Colors.grey.shade800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: leftItems.map((cat) => _buildCategoryCardStatic(cat, c, isExport)).toList(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  children: rightItems.map((cat) => _buildCategoryCardStatic(cat, c, isExport)).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _buildCategoryCardStatic(CategorySyncStatus cat, AppThemeColors c, bool isExport) {
    Color badgeColor;
    String badgeText;
    IconData badgeIcon;

    switch (cat.state) {
      case CategorySyncState.completed:
        badgeColor = Colors.green.shade700;
        badgeText = '100%';
        badgeIcon = Icons.check_circle_rounded;
        break;
      case CategorySyncState.transferring:
        badgeColor = isExport ? Colors.indigo.shade700 : Colors.teal.shade700;
        badgeText = '${cat.percentage}%';
        badgeIcon = Icons.sync_rounded;
        break;
      case CategorySyncState.error:
        badgeColor = Colors.red.shade700;
        badgeText = 'ERROR';
        badgeIcon = Icons.error_rounded;
        break;
      case CategorySyncState.queued:
        badgeColor = Colors.grey.shade600;
        badgeText = 'QUEUED';
        badgeIcon = Icons.hourglass_empty_rounded;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cat.state == CategorySyncState.transferring
              ? (isExport ? Colors.indigo.shade400 : Colors.teal.shade400)
              : (cat.state == CategorySyncState.completed ? Colors.green.shade300 : Colors.grey.shade300),
          width: cat.state == CategorySyncState.transferring ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(cat.icon, size: 16, color: badgeColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  cat.name,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: c.primaryText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(6)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 10, color: Colors.white),
                    const SizedBox(width: 3),
                    Text(
                      badgeText,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 9, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Left: ${cat.inversePercentage}% Remaining',
                style: TextStyle(fontSize: 10, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
              ),
              Text(
                'Right: ${cat.processedCount}/${cat.totalCount > 0 ? cat.totalCount : cat.beforeCount}',
                style: TextStyle(fontSize: 10, color: Colors.green.shade800, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: cat.progress,
              minHeight: 5,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(badgeColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _keyCtrl = TextEditingController();
  final TextEditingController _branchCtrl = TextEditingController();
  final TextEditingController _terminalCtrl = TextEditingController();

  bool _isServerModeEnabled = false;
  bool _isLanSyncEnabled = true;
  AppSyncMode _syncMode = AppSyncMode.hybridCloud;
  bool _obscureKey = true;
  bool _isTestingConnection = false;
  String _pingResultMessage = '';
  bool _pingSuccess = false;
  bool _invoice5Recovered = false;
  bool _isRecoveringInvoice5 = false;

  @override
  void initState() {
    super.initState();
    _initStoredConfig();
    _checkInvoice5RecoveryStatus();
    ServerConfigService.instance.addListener(_loadStoredConfig);
  }

  void _checkInvoice5RecoveryStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool done = prefs.getBool('invoice_5_recovery_completed') ?? false;
      if (mounted) {
        setState(() {
          _invoice5Recovered = done;
        });
      }
    } catch (_) {}
  }

  void _initStoredConfig() {
    final config = ServerConfigService.instance;
    _isServerModeEnabled = config.isServerModeEnabled;
    _isLanSyncEnabled = config.isLanSyncEnabled;
    _syncMode = config.syncMode;
    _urlCtrl.text = config.supabaseUrl;
    _keyCtrl.text = config.supabaseAnonKey;
    _branchCtrl.text = config.storeBranchId;
    _terminalCtrl.text = config.terminalId;
  }

  void _loadStoredConfig() {
    final config = ServerConfigService.instance;
    if (mounted) {
      setState(() {
        if (_urlCtrl.text.isEmpty) {
          _urlCtrl.text = config.supabaseUrl;
        }
        if (_keyCtrl.text.isEmpty) {
          _keyCtrl.text = config.supabaseAnonKey;
        }
        if (_branchCtrl.text.isEmpty) {
          _branchCtrl.text = config.storeBranchId;
        }
        if (_terminalCtrl.text.isEmpty) {
          _terminalCtrl.text = config.terminalId;
        }
      });
    }
  }

  @override
  void dispose() {
    ServerConfigService.instance.removeListener(_loadStoredConfig);
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _branchCtrl.dispose();
    _terminalCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final url = _urlCtrl.text.trim();
    final key = _keyCtrl.text.trim();

    if (url.isEmpty || key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both Supabase URL and API Key first.')),
      );
      return;
    }

    setState(() {
      _isTestingConnection = true;
      _pingResultMessage = 'Pinging server...';
      _pingSuccess = false;
    });

    final stopwatch = Stopwatch()..start();
    final bool success = await ServerConfigService.instance.testConnection(url, key);
    stopwatch.stop();

    if (mounted) {
      final errMsg = ServerConfigService.instance.lastErrorMessage;
      setState(() {
        _isTestingConnection = false;
        _pingSuccess = success;
        if (success) {
          _pingResultMessage = 'Connection Successful! Realtime Listener Active (Latency: ${stopwatch.elapsedMilliseconds} ms)';
          SupabaseSyncService.instance.initRealtimeListeners();
          SupabaseSyncService.instance.triggerInstantSync();
          SupabaseSyncService.instance.reportServerTelemetryHealth(pingLatencyMs: stopwatch.elapsedMilliseconds).ignore();
        } else {
          _pingResultMessage = errMsg.isNotEmpty ? errMsg : 'Connection Failed. Please check URL and API Key.';
        }
      });
    }
  }

  Future<void> _saveAndConnect() async {
    final url = _urlCtrl.text.trim();
    final key = _keyCtrl.text.trim();
    final branch = _branchCtrl.text.trim();
    final terminal = _terminalCtrl.text.trim();

    await ServerConfigService.instance.setTerminalId(terminal);
    if (!mounted) return;

    if (_isServerModeEnabled && (url.isEmpty || key.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supabase URL and API Key are required when Server Mode is enabled.')),
      );
      return;
    }

    final bool connected = await ServerConfigService.instance.connectServer(
      url: url,
      anonKey: key,
      branchId: branch,
      enableMode: _isServerModeEnabled,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isServerModeEnabled
              ? (connected ? 'Connected to Cloud Server successfully!' : 'Saved settings, but server connection failed.')
              : 'Switched to Local Standalone Mode.'),
          backgroundColor: connected || !_isServerModeEnabled ? Colors.green.shade800 : Colors.orange.shade800,
        ),
      );
    }
  }

  void _copySqlSchemaToClipboard() {
    final sql = SupabaseSyncService.generatePostgresSqlSchema();
    Clipboard.setData(ClipboardData(text: sql));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Supabase SQL Setup Schema copied to clipboard! Paste it into Supabase SQL Editor.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<Set<String>?> _showCategorySelectionDialog({required bool isExport}) async {
    final c = AppColors.of(context);
    return await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => CategorySelectionDialog(
        isExport: isExport,
        c: c,
      ),
    );
  }

  Future<void> _exportBackupFile() async {
    try {
      final path = await DbHelper.instance.createLocalBackup();
      if (!mounted) return;
      AppDialogs.showPathDialog(
        context: context,
        title: "Backup Complete",
        message: "Timestamped database backup file created successfully:",
        path: path,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export Backup Error: $e'), backgroundColor: Colors.red.shade800),
      );
    }
  }

  Future<void> _importBackupFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db'],
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final file = File(filePath);

        if (!mounted) return;
        final confirm = await AppDialogs.showConfirmDialog(
          context: context,
          title: "Confirm Database Restore?",
          content: "Restoring from '${file.path}' will replace your active database with the imported data. The app will reload instantly.",
        );

        if (confirm == true) {
          if (!mounted) return;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const Center(child: CircularProgressIndicator()),
          );

          final provider = Provider.of<PharmacyProvider>(context, listen: false);
          final success = await DbHelper.instance.restoreBackupFile(file);
          if (success) {
            await provider.loadFromDatabase();
          }
          if (mounted && Navigator.canPop(context)) Navigator.pop(context);

          if (success && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("⚡ Database Restored Successfully! All data matches imported file."),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import Restore Error: $e'), backgroundColor: Colors.red.shade800),
      );
    }
  }

  Future<int> _fetchServerCount(String endpoint, {String? queryFilter}) async {
    try {
      final config = ServerConfigService.instance;
      if (!config.isConnected || config.supabaseUrl.isEmpty || config.supabaseAnonKey.isEmpty) return -1;

      String filterParam = queryFilter ?? '';
      if (filterParam.isEmpty) {
        if (['purchase_entries', 'sales_return_invoices', 'purchase_return_entries', 'patient_payments', 'supplier_payments', 'supplier_credit_notes'].contains(endpoint)) {
          filterParam = 'is_deleted=eq.0';
        }
      }

      final extraStr = filterParam.isNotEmpty ? '?select=count&$filterParam' : '?select=count';
      final uri = Uri.parse('${config.supabaseUrl}/rest/v1/$endpoint$extraStr');
      final headers = {
        'apikey': config.supabaseAnonKey.trim(),
        'Authorization': 'Bearer ${config.supabaseAnonKey.trim()}',
        'Prefer': 'count=exact',
        'Range': '0-0',
      };
      var res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200 || res.statusCode == 206) {
        final contentRange = res.headers['content-range'] ?? '';
        if (contentRange.contains('/')) {
          final totalStr = contentRange.split('/').last.trim();
          return int.tryParse(totalStr) ?? -1;
        }
      } else if (filterParam.isNotEmpty) {
        // Fallback to simple count query if custom filter returns HTTP status error
        final fallbackUri = Uri.parse('${config.supabaseUrl}/rest/v1/$endpoint?select=count&entry_no=not.is.null');
        res = await http.get(fallbackUri, headers: headers).timeout(const Duration(seconds: 2));
        if (res.statusCode == 200 || res.statusCode == 206) {
          final contentRange = res.headers['content-range'] ?? '';
          if (contentRange.contains('/')) {
            final totalStr = contentRange.split('/').last.trim();
            return int.tryParse(totalStr) ?? -1;
          }
        }
      }
    } catch (_) {}
    return -1;
  }

  Future<int> _fetchLocalCount(Database db, String query) async {
    try {
      final res = await db.rawQuery(query).timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () => [],
      );
      if (res.isNotEmpty) {
        return res.first['cnt'] as int? ?? 0;
      }
    } catch (e) {
      debugPrint('Error fetching local count ($query): $e');
    }
    return 0;
  }

  Future<void> _showLiveSystemCountsDialog() async {
    try {
      await SupabaseSyncService.instance.reconcileCloudSyncedEntries().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
      final db = await DbHelper.instance.database;

      final localCounts = await Future.wait([
        _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM product_master'),
        _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM stock_batches'),
        _fetchLocalCount(db, "SELECT COUNT(DISTINCT CASE WHEN instr(entry_no, '_') > 0 THEN substr(entry_no, instr(entry_no, '_') + 1) ELSE entry_no END) as cnt FROM sales_invoices WHERE (customer_acc IS NULL OR customer_acc != 'Special Order') AND (entry_no IS NOT NULL AND entry_no != '') AND (is_deleted = 1 OR grand_total > 0 OR sub_total > 0 OR total_amount > 0)"),
        _fetchLocalCount(db, "SELECT COUNT(DISTINCT CASE WHEN instr(entry_no, '_') > 0 THEN substr(entry_no, instr(entry_no, '_') + 1) ELSE entry_no END) as cnt FROM purchase_entries WHERE (entry_no IS NOT NULL AND entry_no != '') AND (is_deleted = 1 OR grand_total > 0 OR inv_total > 0 OR sub_total > 0)"),
        _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM sales_return_invoices WHERE (is_deleted = 0 OR is_deleted IS NULL)'),
        _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM purchase_return_entries WHERE (is_deleted = 0 OR is_deleted IS NULL)'),
        _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM stock_adjustments'),
        _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM stock_write_offs'),
        _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM patients'),
        _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM suppliers'),
        _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM doctors'),
        _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM patient_payments WHERE (is_deleted = 0 OR is_deleted IS NULL)'),
        _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM supplier_payments WHERE (is_deleted = 0 OR is_deleted IS NULL)'),
        _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM supplier_credit_notes WHERE (is_deleted = 0 OR is_deleted IS NULL)'),
      ]).timeout(
        const Duration(seconds: 3),
        onTimeout: () => List.filled(14, 0),
      );

      final pCnt = localCounts[0];
      final bCnt = localCounts[1];
      final salCnt = localCounts[2];
      final purCnt = localCounts[3];
      final srCnt = localCounts[4];
      final prCnt = localCounts[5];
      final adjCnt = localCounts[6];
      final dmgCnt = localCounts[7];
      final patCnt = localCounts[8];
      final supCnt = localCounts[9];
      final docCnt = localCounts[10];
      final custAccCnt = localCounts[11];
      final wholesAccCnt = localCounts[12];
      final vouchersCnt = localCounts[13];

      final serverCounts = await Future.wait([
        _fetchServerCount('product_master'),
        _fetchServerCount('stock_batches'),
        _fetchServerCount('sales_invoices', queryFilter: 'entry_no=not.is.null&customer_acc=not.eq.Special%20Order'),
        _fetchServerCount('purchase_entries', queryFilter: 'entry_no=not.is.null'),
        _fetchServerCount('sales_return_invoices'),
        _fetchServerCount('purchase_return_entries'),
        _fetchServerCount('stock_adjustments'),
        _fetchServerCount('stock_write_offs'),
        _fetchServerCount('patients'),
        _fetchServerCount('suppliers'),
        _fetchServerCount('doctors'),
        _fetchServerCount('patient_payments'),
        _fetchServerCount('supplier_payments'),
        _fetchServerCount('supplier_credit_notes'),
      ]).timeout(
        const Duration(seconds: 8),
        onTimeout: () => List.filled(14, -1),
      );

      final pServer = serverCounts[0];
      final bServer = serverCounts[1];
      final salServer = serverCounts[2];
      final purServer = serverCounts[3];
      final srServer = serverCounts[4];
      final prServer = serverCounts[5];
      final adjServer = serverCounts[6];
      final dmgServer = serverCounts[7];
      final patServer = serverCounts[8];
      final supServer = serverCounts[9];
      final docServer = serverCounts[10];
      final custAccServer = serverCounts[11];
      final wholesAccServer = serverCounts[12];
      final vouchersServer = serverCounts[13];

      final fmt = NumberFormat('#,##,###');

      final items = [
        {'catKey': 'product_master', 'title': 'Registered Products (Product Master)', 'icon': Icons.inventory_2_rounded, 'local': pCnt, 'server': pServer, 'color': Colors.blue},
        {'catKey': 'stock_batches', 'title': 'Active Stock Batches (Inventory)', 'icon': Icons.layers_rounded, 'local': bCnt, 'server': bServer, 'color': Colors.indigo},
        {'catKey': 'sales_invoices', 'title': 'Sales Invoices & Counter Bills', 'icon': Icons.point_of_sale_rounded, 'local': salCnt, 'server': salServer, 'color': Colors.green},
        {'catKey': 'purchase_entries', 'title': 'Purchase Inward Entries', 'icon': Icons.shopping_bag_rounded, 'local': purCnt, 'server': purServer, 'color': Colors.teal},
        {'catKey': 'sales_return_invoices', 'title': 'Sales Return Receipts', 'icon': Icons.assignment_return_rounded, 'local': srCnt, 'server': srServer, 'color': Colors.amber},
        {'catKey': 'purchase_return_entries', 'title': 'Purchase Return Entries', 'icon': Icons.unarchive_rounded, 'local': prCnt, 'server': prServer, 'color': Colors.orange},
        {'catKey': 'stock_adjustments', 'title': 'Stock Adjustments', 'icon': Icons.tune_rounded, 'local': adjCnt, 'server': adjServer, 'color': Colors.cyan},
        {'catKey': 'stock_write_offs', 'title': 'Damage & Write-off Entries', 'icon': Icons.remove_shopping_cart_rounded, 'local': dmgCnt, 'server': dmgServer, 'color': Colors.red},
        {'catKey': 'patients', 'title': 'Customers & Patients Registry', 'icon': Icons.people_alt_rounded, 'local': patCnt, 'server': patServer, 'color': Colors.purple},
        {'catKey': 'suppliers', 'title': 'Wholesalers & Suppliers', 'icon': Icons.local_shipping_rounded, 'local': supCnt, 'server': supServer, 'color': Colors.deepOrange},
        {'catKey': 'doctors', 'title': 'Doctors Profiles', 'icon': Icons.medical_services_rounded, 'local': docCnt, 'server': docServer, 'color': Colors.pink},
        {'catKey': 'patient_payments', 'title': 'Customer Account Ledger / Receipts', 'icon': Icons.person_search_rounded, 'local': custAccCnt, 'server': custAccServer, 'color': Colors.lightGreen},
        {'catKey': 'supplier_payments', 'title': 'Wholesale Account Ledger / Payments', 'icon': Icons.store_rounded, 'local': wholesAccCnt, 'server': wholesAccServer, 'color': Colors.blueGrey},
        {'catKey': 'supplier_credit_notes', 'title': 'Payment & Receipt Cash Vouchers', 'icon': Icons.receipt_rounded, 'local': vouchersCnt, 'server': vouchersServer, 'color': Colors.brown},
      ];

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.analytics_rounded, color: Colors.blue),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Live PC vs. Cloud Server Record Counts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          ),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: items.map((it) {
                  final catKey = it['catKey'] as String;
                  final title = it['title'] as String;
                  final icon = it['icon'] as IconData;
                  final local = it['local'] as int;
                  final server = it['server'] as int;
                  final color = it['color'] as Color;

                  final diff = server >= 0 ? (local - server) : 0;
                  final bool isMatched = (server >= 0 && diff == 0);
                  final Color numberColor = isMatched ? Colors.black87 : Colors.red.shade700;
                  final Color badgeBorderColor = isMatched ? Colors.grey.shade300 : Colors.red.shade400;

                  String statusText;
                  Color statusColor;

                  if (server < 0) {
                    statusText = 'Server Unreachable / Offline';
                    statusColor = Colors.grey.shade700;
                  } else if (diff == 0) {
                    statusText = 'In Sync ✅ (Local PC & Cloud Server Match Exactly)';
                    statusColor = Colors.green.shade800;
                  } else if (diff > 0) {
                    statusText = '+$diff Local Records Pending Cloud Push';
                    statusColor = Colors.orange.shade800;
                  } else {
                    statusText = '+${diff.abs()} Cloud Records Pending Pull';
                    statusColor = Colors.blue.shade800;
                  }

                  return InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      ServerDiscrepancyDialog.show(context, initialCategoryKey: catKey);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: color.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(icon, color: color, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                              Icon(Icons.youtube_searched_for_rounded, size: 18, color: Colors.red.shade700),
                              const SizedBox(width: 4),
                              Text(
                                'Inspect Discrepancies',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade700),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  statusText,
                                  style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: badgeBorderColor)),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        const Text('LOCAL PC', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                        Text(fmt.format(local), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: numberColor)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: badgeBorderColor)),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        const Text('CLOUD SERVER', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                        Text(server >= 0 ? fmt.format(server) : 'N/A', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: server >= 0 ? numberColor : Colors.grey)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.cleaning_services_rounded, size: 16),
              label: const Text('RESET CLOUD & RE-SYNC FROM THIS PC', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    title: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                        SizedBox(width: 10),
                        Text('Reset Cloud Catalog & Re-Export?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    content: const Text(
                      'This will purge duplicate/stale records in Supabase Cloud (`product_master`) and re-export your local PC catalog to Supabase Cloud Server.\n\nYour local database will NOT be deleted.',
                      style: TextStyle(fontSize: 13),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, false),
                        child: const Text('CANCEL'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
                        onPressed: () => Navigator.pop(dialogCtx, true),
                        child: const Text('YES, RESET & RE-SYNC', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
                if (!context.mounted) return;

                if (confirm == true) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('⚡ Purging remote cloud duplicate products and re-uploading clean catalog...'), duration: Duration(seconds: 3)),
                  );
                  final success = await SupabaseSyncService.instance.purgeAndReSyncCategory('products');
                  if (!context.mounted) return;
                  if (success) {
                    messenger.showSnackBar(
                      SnackBar(content: const Text('🎉 Cloud Catalog reset and synced successfully!'), backgroundColor: Colors.green.shade800),
                    );
                  } else {
                    messenger.showSnackBar(
                      SnackBar(content: Text('⚠️ Re-sync completed with notes: ${SupabaseSyncService.instance.lastSyncError}'), backgroundColor: Colors.orange.shade800),
                    );
                  }
                }
              },
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CLOSE', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Error fetching live system & server counts: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final syncService = SupabaseSyncService.instance;

    final bodyWidget = Container(
      alignment: Alignment.topCenter,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 780),
        margin: EdgeInsets.all(widget.embedInTab ? 0 : 24),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            // Free Cloud Sync Feature Banner
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: c.isDark
                      ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                      : [const Color(0xFFEFF6FF), const Color(0xFFDBEAFE)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade300, width: 1.2),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade700,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.cloud_done_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              "100% FREE & UNLIMITED CLOUD SYNC",
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                letterSpacing: 0.8,
                                color: c.isDark ? Colors.blue.shade200 : const Color(0xFF1E40AF),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade700,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                "FREE FOREVER",
                                style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Connect your free Supabase server or PostgreSQL database for real-time multi-device database synchronization, live stock updates, and automatic cloud backups with zero subscription fees.",
                          style: TextStyle(fontSize: 11.5, height: 1.3, color: c.isDark ? Colors.grey.shade300 : Colors.grey.shade800),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Last Successful Sync Status Banner
            ListenableBuilder(
              listenable: syncService,
              builder: (context, _) {
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: syncService.isSyncing
                        ? Colors.blue.shade50
                        : (syncService.lastSyncTime != null
                            ? Colors.green.shade50
                            : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: syncService.isSyncing
                          ? Colors.blue.shade300
                          : (syncService.lastSyncTime != null
                              ? Colors.green.shade300
                              : Colors.grey.shade300),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        syncService.isSyncing
                            ? Icons.sync_rounded
                            : (syncService.lastSyncTime != null
                                ? Icons.check_circle_rounded
                                : Icons.cloud_off_rounded),
                        color: syncService.isSyncing
                            ? Colors.blue.shade800
                            : (syncService.lastSyncTime != null
                                ? Colors.green.shade800
                                : Colors.grey.shade700),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              syncService.isSyncing
                                  ? 'Cloud Syncing in Progress...'
                                  : (syncService.lastSyncTime != null
                                      ? 'Cloud Status: Connected & Up-to-Date'
                                      : 'Cloud Status: Disconnected / Local Mode'),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: syncService.isSyncing
                                    ? Colors.blue.shade900
                                    : (syncService.lastSyncTime != null
                                        ? Colors.green.shade900
                                        : Colors.grey.shade800),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Last Successful Sync: ${syncService.lastSyncFormatted}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: syncService.lastSyncTime != null
                                    ? Colors.green.shade900
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // NETWORK & SYNC ARCHITECTURE MODE SELECTOR
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: c.isDark ? Colors.grey.shade800 : Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SYNC ARCHITECTURE & NETWORK MODE',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 12),

                    // Segmented Button Choice for AppSyncMode
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<AppSyncMode>(
                        segments: const [
                          ButtonSegment<AppSyncMode>(
                            value: AppSyncMode.offline,
                            label: Text('Offline'),
                            icon: Icon(Icons.signal_wifi_off_rounded, size: 16),
                          ),
                          ButtonSegment<AppSyncMode>(
                            value: AppSyncMode.lanOnly,
                            label: Text('LAN Shop'),
                            icon: Icon(Icons.lan_rounded, size: 16),
                          ),
                          ButtonSegment<AppSyncMode>(
                            value: AppSyncMode.hybridCloud,
                            label: Text('Hybrid Cloud'),
                            icon: Icon(Icons.cloud_sync_rounded, size: 16),
                          ),
                          ButtonSegment<AppSyncMode>(
                            value: AppSyncMode.pureCloud,
                            label: Text('Pure Cloud Live'),
                            icon: Icon(Icons.cloud_done_rounded, size: 16),
                          ),
                        ],
                        selected: {_syncMode},
                        onSelectionChanged: (Set<AppSyncMode> selection) {
                          if (selection.isNotEmpty) {
                            final mode = selection.first;
                            setState(() {
                              _syncMode = mode;
                              if (mode == AppSyncMode.offline) {
                                _isLanSyncEnabled = false;
                                _isServerModeEnabled = false;
                              } else if (mode == AppSyncMode.lanOnly) {
                                _isLanSyncEnabled = true;
                                _isServerModeEnabled = false;
                              } else if (mode == AppSyncMode.hybridCloud || mode == AppSyncMode.pureCloud) {
                                _isLanSyncEnabled = true;
                                _isServerModeEnabled = true;
                              }
                            });
                            ServerConfigService.instance.setSyncMode(mode);
                            if (mode == AppSyncMode.offline) {
                              LanSyncService.instance.stopLanListener();
                            }
                          }
                        },
                      ),
                    ),
                    if (_syncMode == AppSyncMode.pureCloud) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade300),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.bolt, color: Colors.blue, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Pure Cloud Live Mode active: Real-time direct cloud operation. Database export & full sync runs manually on demand only.",
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Individual Switches for fine-grained control
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable LAN Local UDP Sync (Port 9999)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text('Ultra-fast 10ms Wi-Fi/router UDP broadcast between shop counters.'),
                      value: _isLanSyncEnabled,
                      activeThumbColor: AppColors.success,
                      onChanged: (val) {
                        setState(() {
                          _isLanSyncEnabled = val;
                          if (val && _isServerModeEnabled) {
                            _syncMode = AppSyncMode.hybridCloud;
                          } else if (val) {
                            _syncMode = AppSyncMode.lanOnly;
                          } else if (!_isServerModeEnabled) {
                            _syncMode = AppSyncMode.offline;
                          }
                        });
                        ServerConfigService.instance.setLanSyncEnabled(val);
                        if (!val) {
                          LanSyncService.instance.stopLanListener();
                        }
                      },
                    ),
                    const Divider(),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable Supabase Cloud Sync', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text('Backup and sync billing invoices with Supabase Cloud.'),
                      value: _isServerModeEnabled,
                      activeThumbColor: AppColors.success,
                      onChanged: (val) {
                        setState(() {
                          _isServerModeEnabled = val;
                          if (val && _isLanSyncEnabled) {
                            _syncMode = AppSyncMode.hybridCloud;
                          } else if (!val && _isLanSyncEnabled) {
                            _syncMode = AppSyncMode.lanOnly;
                          } else if (!val) {
                            _syncMode = AppSyncMode.offline;
                          }
                        });
                        ServerConfigService.instance.setSyncMode(_syncMode);
                      },
                    ),
                    const Divider(),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Automatic Cloud Sync / Auto Exporting', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text('When DISABLED (default), automatic database exports are stopped. Database transfers run ONLY when manually triggered.'),
                      value: ServerConfigService.instance.autoSyncEnabled,
                      activeThumbColor: AppColors.success,
                      onChanged: (val) {
                        setState(() {});
                        ServerConfigService.instance.setAutoSyncEnabled(val);
                      },
                    ),
                    const Divider(),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Instant Storage + Background Cloud Sync on Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text('Saves entries to local storage immediately and syncs to cloud in background without showing loading screen on entry pages.'),
                      value: ServerConfigService.instance.bgSyncOnSave,
                      activeThumbColor: AppColors.success,
                      onChanged: (val) {
                        setState(() {});
                        ServerConfigService.instance.setBgSyncOnSave(val);
                      },
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 24),

            // Server Details Form
            AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: _isServerModeEnabled ? 1.0 : 0.5,
              child: IgnorePointer(
                ignoring: !_isServerModeEnabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SUPABASE SERVER DETAILS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                    const SizedBox(height: 12),

                    // Server URL Field
                    TextField(
                      controller: _urlCtrl,
                      decoration: InputDecoration(
                        labelText: 'Supabase Project URL',
                        hintText: 'https://your-project.supabase.co',
                        prefixIcon: const Icon(Icons.dns_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: c.isDark ? Colors.grey.shade900 : Colors.grey.shade50,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // API Key Field with Show/Hide eye icon
                    TextField(
                      controller: _keyCtrl,
                      obscureText: _obscureKey,
                      decoration: InputDecoration(
                        labelText: 'Supabase Anon / API Key',
                        hintText: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
                        prefixIcon: const Icon(Icons.key_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureKey ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                          onPressed: () => setState(() => _obscureKey = !_obscureKey),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: c.isDark ? Colors.grey.shade900 : Colors.grey.shade50,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Store Branch ID Field
                    TextField(
                      controller: _branchCtrl,
                      decoration: InputDecoration(
                        labelText: 'Store / Branch Identifier',
                        hintText: 'MAIN_STORE or COUNTER_1',
                        prefixIcon: const Icon(Icons.store_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: c.isDark ? Colors.grey.shade900 : Colors.grey.shade50,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Terminal / Counter Identifier Field
                    TextField(
                      controller: _terminalCtrl,
                      onChanged: (val) {
                        ServerConfigService.instance.setTerminalId(val);
                        setState(() {});
                      },
                      decoration: InputDecoration(
                        labelText: 'Terminal / Counter Identifier',
                        hintText: 'POS-01 (or POS-02 for Counter 2)',
                        helperText: 'Multi-PC Entry Prefix: ${ServerConfigService.instance.terminalPrefix.isNotEmpty ? ServerConfigService.instance.terminalPrefix : 'None'} (Sample entry: ${ServerConfigService.instance.terminalPrefix}1001)',
                        helperStyle: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                        prefixIcon: const Icon(Icons.computer_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: c.isDark ? Colors.grey.shade900 : Colors.grey.shade50,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Test Connection Ping Row
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _isTestingConnection ? null : _testConnection,
                          icon: _isTestingConnection
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.sensors_rounded, size: 18),
                          label: const Text('Test Connection Ping'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (_pingResultMessage.isNotEmpty)
                          Expanded(
                            child: Chip(
                              avatar: Icon(
                                _pingSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
                                color: _pingSuccess ? Colors.green : Colors.red,
                                size: 18,
                              ),
                              label: Text(_pingResultMessage, style: const TextStyle(fontSize: 11)),
                              backgroundColor: _pingSuccess ? Colors.green.shade50 : Colors.red.shade50,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // SAVE & CONNECT TO SERVER BUTTON
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saveAndConnect,
                icon: const Icon(Icons.save_rounded, size: 20),
                label: Text(_isServerModeEnabled ? 'SAVE & CONNECT TO SERVER' : 'SAVE LOCAL MODE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isServerModeEnabled ? AppColors.primary : Colors.grey.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 2,
                ),
              ),
            ),

            const SizedBox(height: 20),

            ListenableBuilder(
              listenable: syncService,
              builder: (context, _) {
                if (syncService.isSyncing && syncService.isManualTransfer && !syncService.isSilentBackgroundSync) {
                  return _buildLiveTransferMonitorCard(syncService, c);
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: c.isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.isDark ? Colors.blue.shade900 : Colors.blue.shade200, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.swap_horizontal_circle_rounded, color: Colors.blue.shade700, size: 24),
                          const SizedBox(width: 10),
                          Text(
                            'UNIFIED MULTI-PC DATA TRANSFER HUB',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: c.isDark ? Colors.blue.shade200 : Colors.blue.shade900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Send or receive 100% database records between PC 1 and PC 2 via Cloud or USB.',
                        style: TextStyle(fontSize: 12, color: c.isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                      ),
                      const SizedBox(height: 16),

                      // Section 1: EXPORT DATA (Send from PC 1)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.isDark ? Colors.indigo.shade900.withValues(alpha: 0.3) : Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.indigo.shade300, width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.upload_rounded, color: Colors.indigo, size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  '📤 EXPORT DATA (Send Data from PC 1)',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: c.isDark ? Colors.indigo.shade200 : Colors.indigo.shade900),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      ScaffoldMessenger.of(context).clearSnackBars();
                                      final url = _urlCtrl.text.trim();
                                      final key = _keyCtrl.text.trim();
                                      final branch = _branchCtrl.text.trim();

                                      if (url.isEmpty || key.isEmpty) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Please enter Supabase URL and API Key first.')),
                                        );
                                        return;
                                      }

                                      if (!ServerConfigService.instance.isConnected) {
                                        await ServerConfigService.instance.connectServer(
                                          url: url,
                                          anonKey: key,
                                          branchId: branch,
                                          enableMode: _isServerModeEnabled,
                                        );
                                      }

                                      final selected = await _showCategorySelectionDialog(isExport: true);
                                      if (selected == null || selected.isEmpty) return;

                                      await syncService.forcePushAllData(selectedCategories: selected);
                                      if (!context.mounted) return;
                                      _showSyncCompletionNotification(context, syncService, isExport: true);
                                    },
                                    icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                                    label: const Text('EXPORT TO CLOUD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.indigo.shade700,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final selected = await _showCategorySelectionDialog(isExport: true);
                                      if (selected == null || selected.isEmpty) return;
                                      _exportBackupFile();
                                    },
                                    icon: const Icon(Icons.save_alt_rounded, size: 18, color: Colors.indigo),
                                    label: const Text('OFFLINE USB EXPORT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.indigo)),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      side: const BorderSide(color: Colors.indigo, width: 1.5),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Section 2: IMPORT DATA (Receive on PC 2)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.isDark ? Colors.teal.shade900.withValues(alpha: 0.3) : Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.teal.shade300, width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.download_rounded, color: Colors.teal, size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  '📥 IMPORT DATA (Receive Data on PC 2)',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: c.isDark ? Colors.teal.shade200 : Colors.teal.shade900),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      ScaffoldMessenger.of(context).clearSnackBars();
                                      final url = _urlCtrl.text.trim();
                                      final key = _keyCtrl.text.trim();
                                      final branch = _branchCtrl.text.trim();

                                      if (url.isEmpty || key.isEmpty) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Please enter Supabase URL and API Key first.')),
                                        );
                                        return;
                                      }

                                      if (!ServerConfigService.instance.isConnected) {
                                        await ServerConfigService.instance.connectServer(
                                          url: url,
                                          anonKey: key,
                                          branchId: branch,
                                          enableMode: _isServerModeEnabled,
                                        );
                                      }

                                      final selected = await _showCategorySelectionDialog(isExport: false);
                                      if (selected == null || selected.isEmpty) return;

                                      final success = await syncService.syncAllPendingData(
                                        forceFull: true,
                                        isExportMode: false,
                                        isManualTransfer: true,
                                        selectedCategories: selected,
                                      );
                                      if (!context.mounted) return;
                                      if (success) {
                                        await Provider.of<PharmacyProvider>(context, listen: false).loadFromDatabase();
                                      }
                                      if (!context.mounted) return;
                                      _showSyncCompletionNotification(context, syncService, isExport: false);
                                    },
                                    icon: const Icon(Icons.cloud_download_rounded, size: 18),
                                    label: const Text('IMPORT FROM CLOUD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.teal.shade700,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      final selected = await _showCategorySelectionDialog(isExport: false);
                                      if (selected == null || selected.isEmpty) return;
                                      _importBackupFile();
                                    },
                                    icon: const Icon(Icons.folder_open_rounded, size: 18, color: Colors.teal),
                                    label: const Text('OFFLINE USB IMPORT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.teal)),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      side: const BorderSide(color: Colors.teal, width: 1.5),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Live System Record Statistics Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showLiveSystemCountsDialog,
                icon: const Icon(Icons.analytics_rounded, size: 20, color: Colors.blue),
                label: const Text('📊 VIEW LIVE LOCAL vs CLOUD SERVER COUNTS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Colors.blue, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),

            const SizedBox(height: 16),

            _buildInvoiceRecoveryCard(c),

            const SizedBox(height: 16),

            _buildCloudPruningTimerCard(),

            const SizedBox(height: 20),
            const Divider(),

            // PostgreSQL Schema Setup Helper
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('PostgreSQL Schema Setup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: const Text('Copy SQL schema to paste into Supabase SQL Editor.'),
              trailing: OutlinedButton.icon(
                onPressed: _copySqlSchemaToClipboard,
                icon: const Icon(Icons.code_rounded, size: 16),
                label: const Text('Copy SQL Schema'),
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.embedInTab) {
      return bodyWidget;
    }

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text('Server & Cloud Sync Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: bodyWidget,
    );
  }

  Widget _buildLiveTransferMonitorCard(SupabaseSyncService syncService, AppThemeColors c) {
    final bool isExport = syncService.isExportMode;
    final double overallPctDouble = syncService.syncProgress.clamp(0.0, 1.0);
    final int overallPct = (overallPctDouble * 100).toInt();
    final int overallRemainingPct = (100 - overallPct).clamp(0, 100);

    final categories = syncService.categorySyncStatuses.isNotEmpty
        ? syncService.categorySyncStatuses
        : _getDefaultCategories();

    final half = (categories.length / 2).ceil();
    final leftItems = categories.take(half).toList();
    final rightItems = categories.skip(half).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isExport
            ? (c.isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF))
            : (c.isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isExport ? Colors.indigo.shade400 : Colors.teal.shade400,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isExport ? Colors.indigo : Colors.teal).withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Mode & Animation Stream
          Row(
            children: [
              Icon(
                isExport ? Icons.upload_rounded : Icons.download_rounded,
                color: isExport ? Colors.indigo.shade700 : Colors.teal.shade700,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isExport
                      ? '📤 EXPORT IN PROGRESS: Local Database ──► Cloud'
                      : '📥 IMPORT IN PROGRESS: Local Database ◄── Cloud',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: isExport ? Colors.indigo.shade900 : Colors.teal.shade900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: syncService.isCancelRequested ? null : () => syncService.cancelSync(),
                icon: const Icon(Icons.cancel_rounded, size: 16, color: Colors.white),
                label: Text(
                  syncService.isCancelRequested ? 'CANCELLING...' : 'CANCEL',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          ValueListenableBuilder<double>(
            valueListenable: syncService.syncProgressNotifier,
            builder: (context, rawProgress, _) {
              final double pctDouble = rawProgress.clamp(0.0, 1.0);
              final int livePct = (pctDouble * 100).toInt();
              final int liveRemainingPct = (100 - livePct).clamp(0, 100);
              return Column(
                children: [
                  DataStreamAnimationWidget(isExport: isExport, isCompleted: livePct >= 100),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: isExport
                            ? _buildSourceBox(isExport, liveRemainingPct)
                            : _buildTargetBox(isExport, livePct),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: isExport
                            ? _buildTargetBox(isExport, livePct)
                            : _buildSourceBox(isExport, liveRemainingPct),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 8),

          // Realtime Throughput Velocity
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '⚡ Velocity: ${syncService.currentRecordsPerSec.toInt()} rec/sec',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.isDark ? Colors.grey.shade300 : Colors.grey.shade800),
              ),
              Text(
                '⏱️ ETA: ${syncService.formattedEta}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.isDark ? Colors.grey.shade300 : Colors.grey.shade800),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 2-Column Non-Scrollable Grid Layout (4 items Left, 4 items Right)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: leftItems.map((cat) => _buildCategoryCard(cat, c, isExport)).toList(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  children: rightItems.map((cat) => _buildCategoryCard(cat, c, isExport)).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(CategorySyncStatus cat, AppThemeColors c, bool isExport) {
    Color badgeColor;
    String badgeText;
    IconData badgeIcon;

    switch (cat.state) {
      case CategorySyncState.completed:
        badgeColor = Colors.green.shade700;
        badgeText = '100%';
        badgeIcon = Icons.check_circle_rounded;
        break;
      case CategorySyncState.transferring:
        badgeColor = isExport ? Colors.indigo.shade700 : Colors.teal.shade700;
        badgeText = '${cat.percentage}%';
        badgeIcon = Icons.sync_rounded;
        break;
      case CategorySyncState.error:
        badgeColor = Colors.red.shade700;
        badgeText = 'ERROR';
        badgeIcon = Icons.error_rounded;
        break;
      case CategorySyncState.queued:
        badgeColor = Colors.grey.shade600;
        badgeText = 'QUEUED';
        badgeIcon = Icons.hourglass_empty_rounded;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cat.state == CategorySyncState.transferring
              ? (isExport ? Colors.indigo.shade400 : Colors.teal.shade400)
              : (cat.state == CategorySyncState.completed ? Colors.green.shade300 : Colors.grey.shade300),
          width: cat.state == CategorySyncState.transferring ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(cat.icon, size: 16, color: badgeColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  cat.name,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: c.primaryText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(6)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 10, color: Colors.white),
                    const SizedBox(width: 3),
                    Text(
                      badgeText,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 9, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Left: ${cat.inversePercentage}% Remaining',
                style: TextStyle(fontSize: 10, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
              ),
              Text(
                'Right: ${cat.processedCount}/${cat.totalCount > 0 ? cat.totalCount : cat.beforeCount}',
                style: TextStyle(fontSize: 10, color: Colors.green.shade800, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: cat.progress,
              minHeight: 5,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(badgeColor),
            ),
          ),
        ],
      ),
    );
  }

  List<CategorySyncStatus> _getDefaultCategories() {
    return [
      CategorySyncStatus(id: 'products', name: 'Registered Stocks', icon: Icons.medication_rounded),
      CategorySyncStatus(id: 'batches', name: 'Inventory', icon: Icons.layers_rounded),
      CategorySyncStatus(id: 'sales', name: 'Sales', icon: Icons.point_of_sale_rounded),
      CategorySyncStatus(id: 'purchases', name: 'Purchase', icon: Icons.shopping_bag_rounded),
      CategorySyncStatus(id: 'sales_returns', name: 'Sales Return', icon: Icons.assignment_return_rounded),
      CategorySyncStatus(id: 'purchase_returns', name: 'Purchase Return', icon: Icons.unarchive_rounded),
      CategorySyncStatus(id: 'prescriptions_adjustments', name: 'Adjustment', icon: Icons.tune_rounded),
      CategorySyncStatus(id: 'damages', name: 'Damage', icon: Icons.remove_shopping_cart_rounded),
      CategorySyncStatus(id: 'patients', name: 'Patients, Doctors & Phone Numbers', icon: Icons.people_alt_rounded),
      CategorySyncStatus(id: 'suppliers_doctors', name: 'Suppliers & Wholesalers', icon: Icons.medical_services_rounded),
      CategorySyncStatus(id: 'customer_account', name: 'Customer Account', icon: Icons.person_search_rounded),
      CategorySyncStatus(id: 'wholesale_account', name: 'Wholesale Account', icon: Icons.store_rounded),
      CategorySyncStatus(id: 'accounts_daybook', name: 'Daybook, Expenses & Petty Cash', icon: Icons.today_rounded),
      CategorySyncStatus(id: 'month_book', name: 'Month Book', icon: Icons.calendar_month_rounded),
      CategorySyncStatus(id: 'vouchers', name: 'Vouchers', icon: Icons.receipt_rounded),
    ];
  }

  void _showSyncCompletionNotification(BuildContext context, SupabaseSyncService syncService, {required bool isExport}) {
    final categories = syncService.categorySyncStatuses;
    final int totalAttempted = categories.fold(0, (sum, c) => sum + c.totalCount);
    final int totalProcessed = categories.fold(0, (sum, c) => sum + c.processedCount);
    final bool isFullSuccess = syncService.lastSyncError.isEmpty && (totalAttempted == 0 || totalProcessed >= totalAttempted);

    // 1. Log notification to header bell notification menu (Silent background notification)
    try {
      AppNotificationService.instance.addNotification(
        title: isFullSuccess
            ? (isExport ? '🎉 Cloud Export Completed (100%)' : '🎉 Cloud Import Completed (100%)')
            : (isExport ? '⚠️ Cloud Export Completed with Warnings' : '⚠️ Cloud Import Completed with Warnings'),
        message: '$totalProcessed / ${totalAttempted > 0 ? totalAttempted : totalProcessed} records synced.',
        type: NotificationType.backup,
      );
    } catch (_) {}
  }

  void _showSyncCompletionDialog(BuildContext context, SupabaseSyncService syncService, {required bool isExport}) {
    final categories = syncService.categorySyncStatuses;
    final int totalAttempted = categories.fold(0, (sum, c) => sum + c.totalCount);
    final int totalProcessed = categories.fold(0, (sum, c) => sum + c.processedCount);
    final bool isFullSuccess = syncService.lastSyncError.isEmpty && (totalAttempted == 0 || totalProcessed >= totalAttempted);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isFullSuccess ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
              color: isFullSuccess ? Colors.green.shade700 : Colors.orange.shade800,
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isFullSuccess
                    ? (isExport ? '🎉 Cloud Export Completed Successfully!' : '🎉 Cloud Import Completed Successfully!')
                    : (isExport ? '⚠️ Cloud Export Completed with Warnings' : '⚠️ Cloud Import Completed with Warnings'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Container(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isFullSuccess ? Colors.green.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isFullSuccess ? Colors.green.shade200 : Colors.orange.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Records Processed:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isFullSuccess ? Colors.green.shade900 : Colors.orange.shade900)),
                    Text(
                      '$totalProcessed / ${totalAttempted > 0 ? totalAttempted : totalProcessed}',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: isFullSuccess ? Colors.green.shade900 : Colors.orange.shade900),
                    ),
                  ],
                ),
              ),
              if (syncService.lastSyncError.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('Last Sync Status / Notice:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.red.shade200)),
                  child: Text(syncService.lastSyncError, style: TextStyle(fontSize: 11, color: Colors.red.shade900)),
                ),
              ],
              if (syncService.skippedItemLogs.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Skipped / Isolated Items (${syncService.skippedItemLogs.length}):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.orange.shade900)),
                const SizedBox(height: 4),
                Container(
                  constraints: const BoxConstraints(maxHeight: 100),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.orange.shade200)),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: syncService.skippedItemLogs.map((log) => Text('• $log', style: TextStyle(fontSize: 10, color: Colors.orange.shade900))).toList(),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text('Category Summary:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Column(
                    children: categories.map((cat) {
                      final bool isDone = cat.processedCount >= cat.totalCount && cat.totalCount > 0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Icon(cat.icon, size: 16, color: isDone ? Colors.green : Colors.blueGrey),
                            const SizedBox(width: 8),
                            Expanded(child: Text(cat.name, style: const TextStyle(fontSize: 12))),
                            Text(
                              '${cat.processedCount} / ${cat.totalCount}',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: isDone ? Colors.green.shade800 : Colors.orange.shade800),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: isFullSuccess ? Colors.green.shade700 : Colors.indigo.shade700, foregroundColor: Colors.white),
            child: const Text('OK / CLOSE', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildCloudPruningTimerCard() {
    final c = AppColors.of(context);
    final config = ServerConfigService.instance;
    final int currentTimer = config.cloudDataPruningTimerYears;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.isDark ? Colors.grey.shade900 : Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_toggle_off_rounded, color: Colors.indigo.shade700, size: 24),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'CLOUD DATA PRUNING & RETENTION TIMER',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Keep cloud storage fast and lightweight by defining how long transaction history remains in the cloud. Data older than this timer is verified at MAIN_STORE local database before cloud pruning.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Cloud Retention Period', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(
                      currentTimer > 0
                          ? 'Prune cloud rows older than $currentTimer ${currentTimer == 1 ? "Year" : "Years"}'
                          : 'Disabled — Keep all historical rows in the cloud indefinitely',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: c.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: currentTimer,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: c.primaryText),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 Year')),
                      DropdownMenuItem(value: 2, child: Text('2 Years')),
                      DropdownMenuItem(value: 3, child: Text('3 Years (Recommended)')),
                      DropdownMenuItem(value: 4, child: Text('4 Years')),
                      DropdownMenuItem(value: 0, child: Text('Disabled (Keep All Data)')),
                    ],
                    onChanged: (val) async {
                      if (val == null) return;
                      await ServerConfigService.instance.setCloudDataPruningTimerYears(val);
                      setState(() {});
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(val > 0
                                ? 'Cloud Pruning Timer set to $val ${val == 1 ? "Year" : "Years"}.'
                                : 'Cloud Pruning Timer disabled. All cloud data will be kept.'),
                            backgroundColor: Colors.teal.shade800,
                          ),
                        );
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceRecoveryCard(AppThemeColors c) {
    return Card(
      color: c.cardBg,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _invoice5Recovered ? Colors.green.shade300 : Colors.deepOrange.shade300, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _invoice5Recovered ? Icons.check_circle_rounded : Icons.restore_page_rounded,
                  color: _invoice5Recovered ? Colors.green : Colors.deepOrange,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'One-Time Invoice #5 Recovery (PC2)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: c.primaryText),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Purges local unsynced draft #5, restores draft stock, and imports PC1\'s real sale invoice #5 from Supabase Cloud. Supabase server data is NOT modified.',
              style: TextStyle(fontSize: 12, color: c.secondaryText),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _invoice5Recovered
                  ? OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                      label: const Text('Invoice #5 Recovery Completed', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Colors.green, width: 1.5),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: _isRecoveringInvoice5 ? null : () => _triggerInvoice5Recovery(),
                      icon: _isRecoveringInvoice5
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.restore_page_rounded, size: 18, color: Colors.white),
                      label: Text(
                        _isRecoveringInvoice5 ? 'Recovering Invoice #5...' : 'RECOVER INVOICE #5 FROM CLOUD',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _triggerInvoice5Recovery() async {
    final messenger = ScaffoldMessenger.of(context);
    final pharmacyProvider = Provider.of<PharmacyProvider>(context, listen: false);
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    if (prefs.getBool('invoice_5_recovery_completed') == true) {
      setState(() {
        _invoice5Recovered = true;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Invoice #5 recovery has already been completed on PC2.')),
      );
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Invoice #5 Recovery'),
        content: const Text(
          'This action will safely remove PC2\'s local unsynced draft #5, restore its draft stock, and import PC1\'s real sale invoice #5 from Supabase Cloud.\n\n'
          '• Local database backup will be created and verified first.\n'
          '• Supabase Cloud server data will NOT be modified or deleted.\n\n'
          'Proceed with recovery?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('PROCEED WITH RECOVERY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _isRecoveringInvoice5 = true;
    });

    try {
      final result = await InvoiceRecoveryService.instance.recoverUnsyncedInvoice(
        entryNo: "5",
        pharmacy: pharmacyProvider,
      );

      if (!context.mounted) return;

      setState(() {
        _isRecoveringInvoice5 = false;
      });

      if (result.success) {
        await prefs.setBool('invoice_5_recovery_completed', true);
        if (!context.mounted) return;
        setState(() {
          _invoice5Recovered = true;
        });
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
                SizedBox(width: 10),
                Text('Recovery Succeeded'),
              ],
            ),
            content: Text(
              '${result.message}\n\n'
              'Verified Backup Location:\n${result.backupPath ?? 'Created in backups folder.'}',
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        if (!context.mounted) return;
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error_outline_rounded, color: Colors.red, size: 28),
                SizedBox(width: 10),
                Text('Recovery Aborted / Failed'),
              ],
            ),
            content: Text(result.message),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRecoveringInvoice5 = false;
      });
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Error During Recovery'),
          content: Text('An unexpected error occurred: $e'),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }



  Widget buildLiveTransferMonitorCardStatic(SupabaseSyncService syncService, AppThemeColors c) {
    final bool isExport = syncService.isExportMode;
    final double overallPctDouble = syncService.syncProgress.clamp(0.0, 1.0);
    final int overallPct = (overallPctDouble * 100).toInt();
    final int overallRemainingPct = (100 - overallPct).clamp(0, 100);

    final categories = syncService.categorySyncStatuses.isNotEmpty
        ? syncService.categorySyncStatuses
        : [
            CategorySyncStatus(id: 'products', name: 'Registered Products', icon: Icons.inventory_2_rounded),
            CategorySyncStatus(id: 'batches', name: 'Active Stock Batches', icon: Icons.layers_rounded),
            CategorySyncStatus(id: 'sales', name: 'Sales Invoices & Items', icon: Icons.point_of_sale_rounded),
            CategorySyncStatus(id: 'purchases', name: 'Purchase Inward Entries', icon: Icons.shopping_bag_rounded),
            CategorySyncStatus(id: 'accounts_daybook', name: 'Accounts, Vouchers & Day Book', icon: Icons.account_balance_wallet_rounded),
            CategorySyncStatus(id: 'sales_returns', name: 'Sales Return Receipts', icon: Icons.assignment_return_rounded),
            CategorySyncStatus(id: 'purchase_returns', name: 'Purchase Return Entries', icon: Icons.unarchive_rounded),
            CategorySyncStatus(id: 'patients', name: 'Customers & Patients', icon: Icons.people_alt_rounded),
            CategorySyncStatus(id: 'suppliers_doctors', name: 'Suppliers & Doctors', icon: Icons.medical_services_rounded),
            CategorySyncStatus(id: 'prescriptions_adjustments', name: 'Prescriptions & Adjustments', icon: Icons.description_rounded),
          ];

    final half = (categories.length / 2).ceil();
    final leftItems = categories.take(half).toList();
    final rightItems = categories.skip(half).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isExport
            ? (c.isDark ? const Color(0xFF1E1B4B) : const Color(0xFFEEF2FF))
            : (c.isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isExport ? Colors.indigo.shade400 : Colors.teal.shade400,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isExport ? Icons.upload_rounded : Icons.download_rounded,
                color: isExport ? Colors.indigo.shade700 : Colors.teal.shade700,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isExport
                      ? '📤 EXPORT IN PROGRESS: Local Database ──► Cloud'
                      : '📥 IMPORT IN PROGRESS: Cloud ──► Local Database',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: isExport ? Colors.indigo.shade900 : Colors.teal.shade900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: syncService.isCancelRequested ? null : () => syncService.cancelSync(),
                icon: const Icon(Icons.cancel_rounded, size: 14, color: Colors.white),
                label: Text(
                  syncService.isCancelRequested ? 'CANCELLING...' : 'CANCEL',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DataStreamAnimationWidget(isExport: isExport, isCompleted: overallPct >= 100),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: isExport
                    ? _buildSourceBox(isExport, overallRemainingPct)
                    : _buildTargetBox(isExport, overallPct),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: isExport
                    ? _buildTargetBox(isExport, overallPct)
                    : _buildSourceBox(isExport, overallRemainingPct),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '⚡ Velocity: ${syncService.currentRecordsPerSec.toInt()} rec/sec',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.isDark ? Colors.grey.shade300 : Colors.grey.shade800),
              ),
              Text(
                '⏱️ ETA: ${syncService.formattedEta}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.isDark ? Colors.grey.shade300 : Colors.grey.shade800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: leftItems.map((cat) => _buildCategoryCardStatic(cat, c, isExport)).toList(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  children: rightItems.map((cat) => _buildCategoryCardStatic(cat, c, isExport)).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCardStatic(CategorySyncStatus cat, AppThemeColors c, bool isExport) {
    Color badgeColor;
    String badgeText;
    IconData badgeIcon;

    switch (cat.state) {
      case CategorySyncState.completed:
        badgeColor = Colors.green.shade700;
        badgeText = '100%';
        badgeIcon = Icons.check_circle_rounded;
        break;
      case CategorySyncState.transferring:
        badgeColor = isExport ? Colors.indigo.shade700 : Colors.teal.shade700;
        badgeText = '${cat.percentage}%';
        badgeIcon = Icons.sync_rounded;
        break;
      case CategorySyncState.error:
        badgeColor = Colors.red.shade700;
        badgeText = 'ERROR';
        badgeIcon = Icons.error_rounded;
        break;
      case CategorySyncState.queued:
        badgeColor = Colors.grey.shade600;
        badgeText = 'QUEUED';
        badgeIcon = Icons.hourglass_empty_rounded;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cat.state == CategorySyncState.transferring
              ? (isExport ? Colors.indigo.shade400 : Colors.teal.shade400)
              : (cat.state == CategorySyncState.completed ? Colors.green.shade300 : Colors.grey.shade300),
          width: cat.state == CategorySyncState.transferring ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(cat.icon, size: 16, color: badgeColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  cat.name,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: c.primaryText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(6)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 10, color: Colors.white),
                    const SizedBox(width: 3),
                    Text(
                      badgeText,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 9, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Left: ${cat.inversePercentage}% Remaining',
                style: TextStyle(fontSize: 10, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
              ),
              Text(
                'Right: ${cat.processedCount}/${cat.totalCount > 0 ? cat.totalCount : cat.beforeCount}',
                style: TextStyle(fontSize: 10, color: Colors.green.shade800, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: cat.progress,
              minHeight: 5,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(badgeColor),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildSourceBox(bool isExport, int overallRemainingPct) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.orange.shade300),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          isExport ? '🔵 SOURCE (PC 1)' : '🔵 SOURCE (CLOUD)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.orange.shade900),
        ),
        Text(
          '$overallRemainingPct% REMAINING',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.orange.shade800),
        ),
      ],
    ),
  );
}

Widget _buildTargetBox(bool isExport, int overallPct) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.green.shade400),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          isExport ? '🟢 TARGET (CLOUD)' : '🟢 TARGET (PC 2)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.green.shade900),
        ),
        Text(
          '$overallPct% COMPLETED',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.green.shade800),
        ),
      ],
    ),
  );
}

class DataStreamAnimationWidget extends StatefulWidget {
  final bool isExport;
  final bool isCompleted;
  const DataStreamAnimationWidget({super.key, required this.isExport, this.isCompleted = false});

  @override
  State<DataStreamAnimationWidget> createState() => _DataStreamAnimationWidgetState();
}

class _DataStreamAnimationWidgetState extends State<DataStreamAnimationWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (!widget.isCompleted) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(DataStreamAnimationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCompleted) {
      if (_controller.isAnimating) {
        _controller.stop();
      }
    } else {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isCompleted
        ? Colors.green.shade600
        : (widget.isExport ? Colors.indigo.shade600 : Colors.teal.shade600);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(double.infinity, 16),
          painter: _DataStreamPainter(
            progress: widget.isCompleted ? 1.0 : _controller.value,
            isExport: widget.isExport,
            color: color,
          ),
        );
      },
    );
  }
}

class _DataStreamPainter extends CustomPainter {
  final double progress;
  final bool isExport;
  final Color color;

  _DataStreamPainter({
    required this.progress,
    required this.isExport,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final particlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);

    final y = size.height / 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);

    const int particleCount = 6;
    for (int i = 0; i < particleCount; i++) {
      double p = (progress + (i / particleCount)) % 1.0;
      if (!isExport) {
        p = 1.0 - p;
      }
      final x = p * size.width;
      canvas.drawCircle(Offset(x, y), 4.0, glowPaint);
      canvas.drawCircle(Offset(x, y), 2.5, particlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DataStreamPainter oldDelegate) => true;
}

class CategorySelectionDialog extends StatefulWidget {
  final bool isExport;
  final AppThemeColors c;
  final Map<String, int>? initialItemCounts;

  const CategorySelectionDialog({
    super.key,
    required this.isExport,
    required this.c,
    this.initialItemCounts,
  });

  @override
  State<CategorySelectionDialog> createState() => _CategorySelectionDialogState();
}

class _CategorySelectionDialogState extends State<CategorySelectionDialog> {
  late final List<Map<String, dynamic>> sections;
  late final Set<String> allCategoryIds;
  late Set<String> localSelected;
  Map<String, int> itemCounts = {};
  bool isLoadingCounts = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialItemCounts != null && widget.initialItemCounts!.isNotEmpty) {
      itemCounts = Map.from(widget.initialItemCounts!);
      isLoadingCounts = false;
    }

    sections = [
      {
        'title': 'STOCK',
        'icon': Icons.inventory_2_rounded,
        'color': Colors.blue,
        'side': 'left',
        'items': [
          {
            'id': 'products',
            'name': 'Registered Stocks',
            'subtitle': 'Product ID, Name, Packing, Rack, HSN, MRP, P.Rate, Brand, Generic, GST%, Category, Schedule, Reorder Level, Max Level',
            'icon': Icons.medication_rounded,
            'isFuture': false,
          },
          {
            'id': 'batches',
            'name': 'Inventory',
            'subtitle': 'Batch stock, Expiry dates, Quantities & Purchase Rate',
            'icon': Icons.layers_rounded,
            'isFuture': false,
          },
        ],
      },
      {
        'title': 'TRANSACTION',
        'icon': Icons.receipt_long_rounded,
        'color': Colors.orange,
        'side': 'left',
        'items': [
          {
            'id': 'sales',
            'name': 'Sales',
            'subtitle': 'Sales Invoices & Counter Bills',
            'icon': Icons.point_of_sale_rounded,
            'isFuture': false,
          },
          {
            'id': 'purchases',
            'name': 'Purchase',
            'subtitle': 'Purchase Inward Entries & Supplier Bills',
            'icon': Icons.shopping_bag_rounded,
            'isFuture': false,
          },
          {
            'id': 'sales_returns',
            'name': 'Sales Return',
            'subtitle': 'Customer Credit Notes & Return Receipts',
            'icon': Icons.assignment_return_rounded,
            'isFuture': false,
          },
          {
            'id': 'purchase_returns',
            'name': 'Purchase Return',
            'subtitle': 'Supplier Debit Notes & Outward Returns',
            'icon': Icons.unarchive_rounded,
            'isFuture': false,
          },
          {
            'id': 'prescriptions_adjustments',
            'name': 'Adjustment',
            'subtitle': 'Stock Adjustments & Opening Adjustments',
            'icon': Icons.tune_rounded,
            'isFuture': false,
          },
          {
            'id': 'damages',
            'name': 'Damage',
            'subtitle': 'Damaged & Expired Stock Write-offs',
            'icon': Icons.remove_shopping_cart_rounded,
            'isFuture': false,
          },
        ],
      },
      {
        'title': 'ACCOUNTS',
        'icon': Icons.groups_rounded,
        'color': Colors.green,
        'side': 'right',
        'items': [
          {
            'id': 'patients',
            'name': 'Patients, Doctors & Phone Numbers',
            'subtitle': 'Patient Contacts, Prescribing Doctors & Phone Registry',
            'icon': Icons.people_alt_rounded,
            'isFuture': false,
          },
          {
            'id': 'suppliers_doctors',
            'name': 'Suppliers & Wholesalers',
            'subtitle': 'Distributor Masters, GSTIN & Drug License Numbers',
            'icon': Icons.medical_services_rounded,
            'isFuture': false,
          },
        ],
      },
      {
        'title': 'LEDGER',
        'icon': Icons.account_balance_wallet_rounded,
        'color': Colors.purple,
        'side': 'right',
        'items': [
          {
            'id': 'customer_account',
            'name': 'Customer Account',
            'subtitle': 'Customer Credit Ledger & Receivables',
            'icon': Icons.person_search_rounded,
            'isFuture': true,
          },
          {
            'id': 'wholesale_account',
            'name': 'Wholesale Account',
            'subtitle': 'Wholesaler Payable Ledger',
            'icon': Icons.store_rounded,
            'isFuture': true,
          },
          {
            'id': 'accounts_daybook',
            'name': 'Daybook, Shop Expenses & Petty Cash',
            'subtitle': 'Daily Cash, Expenses & Petty Cash Register',
            'icon': Icons.today_rounded,
            'isFuture': true,
          },
          {
            'id': 'month_book',
            'name': 'Month Book',
            'subtitle': 'Monthly Financial Summaries & Statement',
            'icon': Icons.calendar_month_rounded,
            'isFuture': true,
          },
          {
            'id': 'vouchers',
            'name': 'Vouchers',
            'subtitle': 'Payment & Receipt Cash Vouchers',
            'icon': Icons.receipt_rounded,
            'isFuture': true,
          },
        ],
      },
    ];

    allCategoryIds = {};
    for (var sec in sections) {
      for (var item in (sec['items'] as List<Map<String, dynamic>>)) {
        allCategoryIds.add(item['id'] as String);
      }
    }
    localSelected = Set.from(allCategoryIds);

    if (isLoadingCounts) {
      _loadItemCounts();
    }
  }

  Future<int> _fetchLocalCount(Database db, String query) async {
    try {
      final res = await db.rawQuery(query).timeout(
        const Duration(milliseconds: 1200),
        onTimeout: () => [],
      );
      if (res.isNotEmpty) {
        return res.first['cnt'] as int? ?? 0;
      }
    } catch (e) {
      debugPrint('Error fetching local count ($query): $e');
    }
    return 0;
  }

  Future<void> _loadItemCounts() async {
    final Map<String, int> counts = {
      'products': 0,
      'batches': 0,
      'sales': 0,
      'purchases': 0,
      'sales_returns': 0,
      'purchase_returns': 0,
      'prescriptions_adjustments': 0,
      'damages': 0,
      'patients': 0,
      'suppliers_doctors': 0,
      'customer_account': 0,
      'wholesale_account': 0,
      'accounts_daybook': 0,
      'month_book': 0,
      'vouchers': 0,
    };

    try {
      if (widget.isExport) {
        final db = await DbHelper.instance.database;
        final results = await Future.wait([
          _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM product_master'),
          _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM stock_batches'),
          _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM sales_invoices WHERE is_deleted = 0'),
          _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM purchase_entries WHERE is_deleted = 0'),
          _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM sales_return_invoices'),
          _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM purchase_return_entries'),
          _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM stock_adjustments'),
          _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM stock_write_offs'),
          _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM patients'),
          _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM suppliers'),
          _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM doctors'),
          _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM patient_payments'),
          _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM supplier_payments'),
          _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM supplier_credit_notes'),
          _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM accounts'),
        ]).timeout(
          const Duration(seconds: 2),
          onTimeout: () => List.filled(15, 0),
        );

        counts['products'] = results[0];
        counts['batches'] = results[1];
        counts['sales'] = results[2];
        counts['purchases'] = results[3];
        counts['sales_returns'] = results[4];
        counts['purchase_returns'] = results[5];
        counts['prescriptions_adjustments'] = results[6];
        counts['damages'] = results[7];
        counts['patients'] = results[8];
        counts['suppliers_doctors'] = results[9] + results[10];
        counts['customer_account'] = results[11];
        counts['wholesale_account'] = results[12];
        counts['accounts_daybook'] = results[11] + results[12] + results[13] + results[14];
        counts['month_book'] = 0;
        counts['vouchers'] = results[13];
      } else {
        final syncService = SupabaseSyncService.instance;
        final results = await Future.wait([
          syncService.fetchRemoteCount('product_master'),
          syncService.fetchRemoteCount('stock_batches'),
          syncService.fetchRemoteCount('sales_invoices'),
          syncService.fetchRemoteCount('purchase_entries'),
          syncService.fetchRemoteCount('sales_return_invoices'),
          syncService.fetchRemoteCount('purchase_return_entries'),
          syncService.fetchRemoteCount('stock_adjustments'),
          syncService.fetchRemoteCount('stock_write_offs'),
          syncService.fetchRemoteCount('patients'),
          syncService.fetchRemoteCount('suppliers'),
          syncService.fetchRemoteCount('doctors'),
          syncService.fetchRemoteCount('patient_payments'),
          syncService.fetchRemoteCount('supplier_payments'),
        ]).timeout(
          const Duration(seconds: 8),
          onTimeout: () => List.filled(13, 0),
        );

        counts['products'] = results[0];
        counts['batches'] = results[1];
        counts['sales'] = results[2];
        counts['purchases'] = results[3];
        counts['sales_returns'] = results[4];
        counts['purchase_returns'] = results[5];
        counts['prescriptions_adjustments'] = results[6];
        counts['damages'] = results[7];
        counts['patients'] = results[8];
        counts['suppliers_doctors'] = results[9] + results[10];
        counts['customer_account'] = results[11];
        counts['wholesale_account'] = results[12];
        counts['accounts_daybook'] = results[11] + results[12];
        counts['vouchers'] = results[11] + results[12];
      }
    } catch (e) {
      debugPrint('Error loading category counts: $e');
    } finally {
      if (mounted) {
        setState(() {
          itemCounts = counts;
          isLoadingCounts = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final isExport = widget.isExport;
    final isAllSelected = localSelected.length == allCategoryIds.length;
    final leftSections = sections.where((s) => s['side'] == 'left').toList();
    final rightSections = sections.where((s) => s['side'] == 'right').toList();

    int totalQtySelected = 0;
    if (!isLoadingCounts) {
      for (var selId in localSelected) {
        totalQtySelected += itemCounts[selId] ?? 0;
      }
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: c.isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Container(
        width: 840,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title Bar
            Row(
              children: [
                Icon(
                  isExport ? Icons.upload_rounded : Icons.download_rounded,
                  color: isExport ? Colors.indigo : Colors.teal,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isExport ? 'Select Data Items to Export (Push)' : 'Select Data Items to Import (Pull)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: c.isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context, null),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Tick the items you want to ${isExport ? "upload" : "download"}. Unchecked items will be skipped.',
              style: TextStyle(fontSize: 12, color: c.isDark ? Colors.grey.shade400 : Colors.grey.shade600),
            ),
            const SizedBox(height: 12),

            // Top Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isLoadingCounts
                      ? '${localSelected.length} of ${allCategoryIds.length} Items Selected'
                      : '${localSelected.length} of ${allCategoryIds.length} Items Selected ($totalQtySelected Total Qty)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isExport ? Colors.indigo.shade400 : Colors.teal.shade400,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      if (isAllSelected) {
                        localSelected.clear();
                      } else {
                        localSelected = Set.from(allCategoryIds);
                      }
                    });
                  },
                  icon: Icon(
                    isAllSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
                    size: 16,
                    color: isExport ? Colors.indigo : Colors.teal,
                  ),
                  label: Text(
                    isAllSelected ? 'Deselect All' : 'Select All',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isExport ? Colors.indigo : Colors.teal,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 2-SIDE AREA
            Expanded(
              child: SingleChildScrollView(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // LEFT SIDE AREA
                    Expanded(
                      child: Column(
                        children: leftSections.map((sec) => _buildSectionCard(sec, c, isExport)).toList(),
                      ),
                    ),
                    const SizedBox(width: 14),
                    // RIGHT SIDE AREA
                    Expanded(
                      child: Column(
                        children: rightSections.map((sec) => _buildSectionCard(sec, c, isExport)).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, null),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    if (localSelected.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please tick at least one item to transfer.')),
                      );
                      return;
                    }
                    Navigator.pop(context, localSelected);
                  },
                  icon: Icon(isExport ? Icons.cloud_upload_rounded : Icons.cloud_download_rounded, size: 18),
                  label: Text(
                    isLoadingCounts
                        ? (isExport ? 'START PUSH (${localSelected.length} ITEMS)' : 'START PULL (${localSelected.length} ITEMS)')
                        : (isExport
                            ? 'START PUSH (${localSelected.length} ITEMS - $totalQtySelected QTY)'
                            : 'START PULL (${localSelected.length} ITEMS - $totalQtySelected QTY)'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isExport ? Colors.indigo.shade700 : Colors.teal.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(Map<String, dynamic> sec, AppThemeColors c, bool isExport) {
    final String sectionTitle = sec['title'] as String;
    final IconData sectionIcon = sec['icon'] as IconData;
    final MaterialColor sectionColor = sec['color'] as MaterialColor;
    final List<Map<String, dynamic>> items = sec['items'] as List<Map<String, dynamic>>;

    final secItemIds = items.map((i) => i['id'] as String).toSet();
    final secSelectedCount = items.where((i) => localSelected.contains(i['id'])).length;
    final isSecAllSelected = secSelectedCount == items.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: c.isDark ? const Color(0xFF334155) : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: sectionColor.withValues(alpha: c.isDark ? 0.2 : 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(
                bottom: BorderSide(
                  color: c.isDark ? const Color(0xFF334155) : Colors.grey.shade200,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(sectionIcon, size: 18, color: sectionColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sectionTitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: c.isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: sectionColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$secSelectedCount/${items.length}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: sectionColor,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () {
                    setState(() {
                      if (isSecAllSelected) {
                        localSelected.removeAll(secItemIds);
                      } else {
                        localSelected.addAll(secItemIds);
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSecAllSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                          size: 16,
                          color: sectionColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Select All',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: sectionColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Section Items List
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              children: items.map((item) {
                final String id = item['id'] as String;
                final String name = item['name'] as String;
                final String subtitle = item['subtitle'] as String;
                final IconData icon = item['icon'] as IconData;
                final bool isFuture = item['isFuture'] == true;
                final bool isChecked = localSelected.contains(id);
                final int qty = itemCounts[id] ?? 0;

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: isChecked
                        ? (isExport
                            ? (c.isDark ? Colors.indigo.shade900.withValues(alpha: 0.3) : Colors.indigo.shade50)
                            : (c.isDark ? Colors.teal.shade900.withValues(alpha: 0.3) : Colors.teal.shade50))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isChecked
                          ? (isExport ? Colors.indigo.shade300 : Colors.teal.shade300)
                          : Colors.transparent,
                    ),
                  ),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        if (isChecked) {
                          localSelected.remove(id);
                        } else {
                          localSelected.add(id);
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: Checkbox(
                              value: isChecked,
                              activeColor: isExport ? Colors.indigo.shade700 : Colors.teal.shade700,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    localSelected.add(id);
                                  } else {
                                    localSelected.remove(id);
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            icon,
                            size: 18,
                            color: isChecked
                                ? (isExport ? Colors.indigo : Colors.teal)
                                : (c.isDark ? Colors.grey.shade500 : Colors.grey.shade600),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isChecked ? FontWeight.bold : FontWeight.w500,
                                          color: c.isDark ? Colors.white : const Color(0xFF1E293B),
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: (!isLoadingCounts && qty > 0)
                                            ? (isExport
                                                ? (c.isDark ? Colors.indigo.shade900.withValues(alpha: 0.5) : Colors.indigo.shade50)
                                                : (c.isDark ? Colors.teal.shade900.withValues(alpha: 0.5) : Colors.teal.shade50))
                                            : (c.isDark ? const Color(0xFF334155) : Colors.grey.shade200),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: (!isLoadingCounts && qty > 0)
                                              ? (isExport ? Colors.indigo.shade300 : Colors.teal.shade300)
                                              : (c.isDark ? Colors.grey.shade700 : Colors.grey.shade400),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: isLoadingCounts
                                          ? SizedBox(
                                              width: 10,
                                              height: 10,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 1.5,
                                                color: isExport ? Colors.indigo.shade700 : Colors.teal.shade700,
                                              ),
                                            )
                                          : Text(
                                              isExport ? '$qty Qty' : '$qty Cloud Qty',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: qty > 0
                                                    ? (isExport ? Colors.indigo.shade800 : Colors.teal.shade800)
                                                    : (c.isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                                              ),
                                            ),
                                    ),
                                    if (isFuture) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.purple.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'Future Link',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.purple,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: c.isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}