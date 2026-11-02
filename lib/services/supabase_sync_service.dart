import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sql;
import '../database/db_helper.dart';
import '../providers/pharmacy_provider.dart';
import '../utils/app_formatters.dart';
import '../utils/app_logger.dart';
import 'app_notification_service.dart';
import 'delta_sync_service.dart';
import 'remote_logger_service.dart';
import 'server_config_service.dart';
import 'supabase_realtime_service.dart';

enum CategorySyncState { queued, transferring, completed, error }

class CategorySyncStatus {
  final String id;
  final String name;
  final IconData icon;
  int beforeCount;
  int totalCount;
  int processedCount;
  CategorySyncState state;

  CategorySyncStatus({
    required this.id,
    required this.name,
    required this.icon,
    this.beforeCount = 0,
    this.totalCount = 0,
    this.processedCount = 0,
    this.state = CategorySyncState.queued,
  });

  double get progress {
    if (state == CategorySyncState.completed) return 1.0;
    if (totalCount <= 0) return 0.0;
    return (processedCount / totalCount).clamp(0.0, 1.0);
  }

  int get percentage {
    if (state == CategorySyncState.completed) return 100;
    return (progress * 100).toInt();
  }

  int get inversePercentage => (100 - percentage).clamp(0, 100);
}

class SupabaseSyncService extends ChangeNotifier {
  SupabaseSyncService._internal();
  static final SupabaseSyncService instance = SupabaseSyncService._internal();

  static const String _keyLastSyncTimestamp = 'supabase_last_sync_timestamp';
  static const String _keyInitialSyncCompleted = 'supabase_initial_sync_completed';

  bool _isSyncing = false;
  bool _isWiping = false;
  bool _isManualTransfer = false;
  bool _cancelRequested = false;
  bool _isInitialSyncCompleted = false;
  bool _syncPaused = false;
  bool _isRecoveryLocked = false;
  bool _isBulkImportActive = false;
  int _activePushSalesInvoiceCount = 0;
  DateTime? _recoveryLockAcquiredAt;

  bool get isWiping => _isWiping;
  bool get isBulkImportActive => _isBulkImportActive;
  bool get isSyncPaused {
    checkAndHealStuckRecoveryLock();
    return _syncPaused || _isBulkImportActive;
  }
  bool get isRecoveryLocked {
    checkAndHealStuckRecoveryLock();
    return _isRecoveryLocked || _isBulkImportActive;
  }
  int get activePushSalesInvoiceCount => _activePushSalesInvoiceCount;

  /// Explicitly pause background sync for heavy bulk import operations without auto-healing timeout
  void setBulkImportActive(bool active) {
    _isBulkImportActive = active;
    if (active) {
      _isRecoveryLocked = true;
      _syncPaused = true;
      _cancelRequested = true;
      _recoveryLockAcquiredAt = null; // Prevent checkAndHealStuckRecoveryLock from auto-healing
      _realtimeStreamTimer?.cancel();
      _realtimeStreamTimer = null;
      try {
        DeltaSyncService.instance.stopPeriodicSync();
      } catch (_) {}
    } else {
      resumeSync();
    }
  }

  /// Pauses background sync tasks and waits for all active sync execution and in-flight pushSalesInvoice calls to finish.
  /// Returns true if all pushes and syncs became idle within [timeout], false if still busy.
  Future<bool> pauseSyncAndAwaitIdle({
    Duration timeout = const Duration(seconds: 15),
    bool keepPausedOnTimeout = false,
  }) async {
    _isRecoveryLocked = true;
    _syncPaused = true;
    _cancelRequested = true;
    _recoveryLockAcquiredAt = DateTime.now();
    _realtimeStreamTimer?.cancel();
    _realtimeStreamTimer = null;

    final stopwatch = Stopwatch()..start();
    while ((_isSyncing || DeltaSyncService.instance.isSyncing || _activePushSalesInvoiceCount > 0) && stopwatch.elapsed < timeout) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    final bool isIdle = !(_isSyncing || DeltaSyncService.instance.isSyncing || _activePushSalesInvoiceCount > 0);
    if (!isIdle) {
      debugPrint('pauseSyncAndAwaitIdle TIMED OUT: _isSyncing=$_isSyncing, deltaSyncing=${DeltaSyncService.instance.isSyncing}, activePushes=$_activePushSalesInvoiceCount');
      if (!keepPausedOnTimeout && !_isBulkImportActive) {
        _isRecoveryLocked = false;
        _syncPaused = false;
        _cancelRequested = false;
        _recoveryLockAcquiredAt = null;
      }
    }
    return isIdle;
  }

  /// Auto-releases recovery lock if it was accidentally left locked for more than 90 seconds
  void checkAndHealStuckRecoveryLock() {
    if (_isBulkImportActive) return; // Do NOT auto-heal recovery lock during active bulk import
    if ((_isRecoveryLocked || _syncPaused) && _recoveryLockAcquiredAt != null) {
      if (DateTime.now().difference(_recoveryLockAcquiredAt!).inSeconds > 90) {
        debugPrint('⚠️ Auto-healing stuck Invoice Recovery Lock (held > 90s). Resuming sync...');
        resumeSync();
      }
    }
  }

  /// Resumes normal background sync execution
  void resumeSync() {
    _isBulkImportActive = false;
    _isRecoveryLocked = false;
    _syncPaused = false;
    _cancelRequested = false;
    _recoveryLockAcquiredAt = null;
    initRealtimeListeners();
    try {
      SupabaseRealtimeService.instance.resumeSubscriptions();
    } catch (_) {}
    try {
      DeltaSyncService.instance.startPeriodicSync();
    } catch (_) {}
    if (ServerConfigService.instance.isServerModeEnabled) {
      triggerInstantSync(isManualTransfer: true);
    }
  }
  bool _isSilentBackgroundSync = false;
  bool get isSilentBackgroundSync => _isSilentBackgroundSync;
  bool _isExportMode = true;
  double _syncProgress = 0.0;
  final ValueNotifier<double> syncProgressNotifier = ValueNotifier<double>(0.0);
  DateTime? _lastProgressNotifyTime;
  double _currentRecordsPerSec = 0.0;
  int _currentEtaSeconds = 0;
  String _syncStatusMessage = 'Idle';
  String _lastSyncError = '';
  DateTime? _lastSyncTime;
  VoidCallback? onDataPulled;
  List<CategorySyncStatus> _categorySyncStatuses = [];
  Set<String>? _activeSelectedCategoryIds;

  bool _isCategorySelected(String id) {
    if (_activeSelectedCategoryIds == null || _activeSelectedCategoryIds!.isEmpty) return true;
    if (_activeSelectedCategoryIds!.contains(id)) return true;
    // Map new category IDs to sync handlers
    if (id == 'prescriptions_adjustments' &&
        (_activeSelectedCategoryIds!.contains('adjustments') || _activeSelectedCategoryIds!.contains('damages'))) {
      return true;
    }
    if (id == 'accounts_daybook' &&
        (_activeSelectedCategoryIds!.contains('customer_account') ||
            _activeSelectedCategoryIds!.contains('wholesale_account') ||
            _activeSelectedCategoryIds!.contains('daybook_expenses') ||
            _activeSelectedCategoryIds!.contains('month_book') ||
            _activeSelectedCategoryIds!.contains('vouchers'))) {
      return true;
    }
    return false;
  }

  bool get isSyncing => _isSyncing;
  bool get isManualTransfer => _isManualTransfer;
  bool get isCancelRequested => _cancelRequested;
  bool get isInitialSyncCompleted => _isInitialSyncCompleted;
  bool get isExportMode => _isExportMode;
  double get syncProgress {
    if (_categorySyncStatuses.isNotEmpty) {
      final double totalCatProgress = _categorySyncStatuses.fold(0.0, (sum, cat) => sum + cat.progress);
      final double avgCatProgress = totalCatProgress / _categorySyncStatuses.length;
      return avgCatProgress.clamp(_syncProgress, 1.0);
    }
    if (_totalRowsToSync > 0) {
      return (_processedRowsCount / _totalRowsToSync).clamp(0.0, 1.0);
    }
    return _syncProgress.clamp(0.0, 1.0);
  }
  double get currentRecordsPerSec => _currentRecordsPerSec;
  int get currentEtaSeconds => _currentEtaSeconds;
  String get syncStatusMessage => _syncStatusMessage;
  String get lastSyncError => _lastSyncError;
  DateTime? get lastSyncTime => _lastSyncTime;
  List<CategorySyncStatus> get categorySyncStatuses => List.unmodifiable(_categorySyncStatuses);

  http.Client? _syncClient;

  /// Closes active TCP connection streams and resets client instance.
  void _closeClient() {
    try {
      _syncClient?.close();
    } catch (_) {}
    _syncClient = null;
  }

  @override
  void dispose() {
    _realtimeStreamTimer?.cancel();
    _realtimeStreamTimer = null;
    _closeClient();
    super.dispose();
  }

  /// Cancels an in-progress synchronization instantly.
  void cancelSync() {
    if (_isSyncing) {
      _cancelRequested = true;
      _isSyncing = false;
      _closeClient();
      _syncProgress = 0.0;
      _syncStatusMessage = 'Sync Cancelled by User.';
      notifyListeners();
    }
  }

  final List<String> _skippedItemLogs = [];
  List<String> get skippedItemLogs => List.unmodifiable(_skippedItemLogs);
  void clearSkippedItemLogs() => _skippedItemLogs.clear();

  String get lastSyncFormatted {
    if (_lastSyncTime == null) return 'Never Synced';
    return DateFormat('dd/MM/yyyy, hh:mm:ss a').format(_lastSyncTime!);
  }

  /// Reconciliation pass: Checks local entries flagged as unsynced (is_synced = 0)
  /// against the Cloud Server REST API. If they already exist on the server, local
  /// Checks cloud database_epoch in server_metadata to detect remote server wipes/resets.
  /// If the cloud epoch is new/different, purges local SQLite records marked is_synced = 1
  /// while preserving fresh unsynced offline drafts (is_synced = 0).
  Future<void> checkDatabaseEpoch() async {
    final config = ServerConfigService.instance;
    if (!config.isServerModeEnabled || !config.isConnected || config.isWiping) return;

    try {
      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
      final uri = Uri.parse('$cleanUrl/rest/v1/server_metadata?key=eq.database_epoch&select=value');
      final res = await http.get(uri, headers: config.restHeaders).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final List<dynamic> rows = jsonDecode(res.body);
        if (rows.isNotEmpty) {
          final cloudEpoch = rows.first['value']?.toString().trim() ?? '';
          if (cloudEpoch.isNotEmpty) {
            final lastEpoch = config.lastKnownEpoch;
            if (lastEpoch.isNotEmpty && lastEpoch != cloudEpoch) {
              AppLogger.instance.info(
                "SUPABASE",
                "⚡ Remote Cloud Reset Detected! Cloud epoch ($cloudEpoch) != Local ($lastEpoch). Purging old synced local records...",
              );

              final db = await DbHelper.instance.database;
              await db.transaction((txn) async {
                await txn.delete('sales_items', where: 'invoice_no IN (SELECT entry_no FROM sales_invoices WHERE is_synced = 1)');
                await txn.delete('sales_invoices', where: 'is_synced = 1');
                await txn.delete('purchase_items', where: 'entry_no IN (SELECT entry_no FROM purchase_entries WHERE is_synced = 1)');
                await txn.delete('purchase_entries', where: 'is_synced = 1');
                await txn.delete('sales_return_items', where: 'return_no IN (SELECT entry_no FROM sales_return_invoices WHERE is_synced = 1)');
                await txn.delete('sales_return_invoices', where: 'is_synced = 1');
                await txn.delete('purchase_return_items', where: 'entry_no IN (SELECT entry_no FROM purchase_return_entries WHERE is_synced = 1)');
                await txn.delete('purchase_return_entries', where: 'is_synced = 1');
              });
            }
            await config.setLastKnownEpoch(cloudEpoch);
          }
        }
      }
    } catch (e) {
      debugPrint('checkDatabaseEpoch exception: $e');
    }
  }

  /// SQLite is updated to is_synced = 1 so they do not falsely show as unsynced.
  Future<void> reconcileCloudSyncedEntries() async {
    try {
      await checkDatabaseEpoch();
      final db = await DbHelper.instance.database;

      // Mark zero-total blank draft entries (with NO line items) as synced so they don't count as pending
      await db.rawUpdate("UPDATE sales_invoices SET is_synced = 1 WHERE (is_deleted = 0 OR is_deleted IS NULL) AND (grand_total IS NULL OR grand_total = 0) AND (sub_total IS NULL OR sub_total = 0) AND entry_no NOT IN (SELECT DISTINCT invoice_no FROM sales_items WHERE invoice_no IS NOT NULL)");
      await db.rawUpdate("UPDATE purchase_entries SET is_synced = 1 WHERE (is_deleted = 0 OR is_deleted IS NULL) AND (grand_total IS NULL OR grand_total = 0) AND (inv_total IS NULL OR inv_total = 0) AND (sub_total IS NULL OR sub_total = 0) AND entry_no NOT IN (SELECT DISTINCT entry_no FROM purchase_items WHERE entry_no IS NOT NULL)");

      // Also mark locally soft-deleted records as synced so they do not falsely report as pending push
      await db.rawUpdate('UPDATE sales_invoices SET is_synced = 1 WHERE is_deleted = 1 AND (is_synced = 0 OR is_synced IS NULL)');
      await db.rawUpdate('UPDATE purchase_entries SET is_synced = 1 WHERE is_deleted = 1 AND (is_synced = 0 OR is_synced IS NULL)');

      if (!ServerConfigService.instance.isServerModeEnabled || !ServerConfigService.instance.isConnected) {
        return;
      }
      final config = ServerConfigService.instance;
      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);

      Future<void> reconcileTable(String tableName, String keyColumn) async {
        try {
          final pending = await db.query(
            tableName,
            columns: [keyColumn],
            where: 'is_synced = 0 OR is_synced IS NULL',
            limit: 50,
          );
          if (pending.isNotEmpty) {
            final keys = pending.map((row) => row[keyColumn]?.toString().trim() ?? '').where((k) => k.isNotEmpty).toList();
            if (keys.isNotEmpty) {
              final filterStr = keys.map((k) => '"$k"').join(',');
              final uri = Uri.parse('$cleanUrl/rest/v1/$tableName?$keyColumn=in.($filterStr)&select=$keyColumn');
              final res = await http.get(uri, headers: config.restHeaders).timeout(const Duration(seconds: 4));
              if (res.statusCode == 200) {
                final List<dynamic> cloudRows = jsonDecode(res.body);
                final foundKeys = cloudRows.map((r) => r[keyColumn]?.toString().trim() ?? '').where((k) => k.isNotEmpty).toList();
                if (foundKeys.isNotEmpty) {
                  final placeholders = List.filled(foundKeys.length, '?').join(',');
                  await db.rawUpdate(
                    'UPDATE $tableName SET is_synced = 1, is_cloud_synced = 1 WHERE $keyColumn IN ($placeholders)',
                    foundKeys,
                  );
                }
              }
            }
          }
        } catch (e) {
          debugPrint('reconcileTable $tableName exception: $e');
        }
      }

      await reconcileTable('sales_invoices', 'entry_no');
      await reconcileTable('purchase_entries', 'entry_no');
      await reconcileTable('sales_return_invoices', 'entry_no');
      await reconcileTable('purchase_return_entries', 'entry_no');
      await reconcileTable('patient_payments', 'id');
      await reconcileTable('supplier_payments', 'id');
      await reconcileTable('stock_adjustments', 'entry_no');
    } catch (e) {
      debugPrint('reconcileCloudSyncedEntries exception: $e');
    }
  }

  /// Returns total count of unsynced transaction records across key local tables (matching Unsynced Data Monitor).
  Future<int> getUnsyncedTotalCount() async {
    try {
      await reconcileCloudSyncedEntries();
      final db = await DbHelper.instance.database;
      final salCnt = (await db.rawQuery('SELECT COUNT(*) as cnt FROM sales_invoices WHERE (is_synced = 0 OR is_synced IS NULL) AND (is_deleted = 0 OR is_deleted IS NULL)')).first['cnt'] as int? ?? 0;
      final purCnt = (await db.rawQuery('SELECT COUNT(*) as cnt FROM purchase_entries WHERE (is_synced = 0 OR is_synced IS NULL) AND (is_deleted = 0 OR is_deleted IS NULL)')).first['cnt'] as int? ?? 0;
      final srCnt = (await db.rawQuery('SELECT COUNT(*) as cnt FROM sales_return_invoices WHERE (is_synced = 0 OR is_synced IS NULL)')).first['cnt'] as int? ?? 0;
      final prCnt = (await db.rawQuery('SELECT COUNT(*) as cnt FROM purchase_return_entries WHERE (is_synced = 0 OR is_synced IS NULL)')).first['cnt'] as int? ?? 0;
      final adjCnt = (await db.rawQuery('SELECT COUNT(*) as cnt FROM stock_adjustments WHERE (is_synced = 0 OR is_synced IS NULL)')).first['cnt'] as int? ?? 0;
      final patPayCnt = (await db.rawQuery('SELECT COUNT(*) as cnt FROM patient_payments WHERE (is_synced = 0 OR is_synced IS NULL)')).first['cnt'] as int? ?? 0;
      final supPayCnt = (await db.rawQuery('SELECT COUNT(*) as cnt FROM supplier_payments WHERE (is_synced = 0 OR is_synced IS NULL)')).first['cnt'] as int? ?? 0;

      // Include pending deletions and unsynced master data records for complete queue accuracy
      int delCnt = 0;
      try {
        final delTableCheck = await db.rawQuery("SELECT COUNT(*) as cnt FROM sqlite_master WHERE type='table' AND name='pending_deletions'");
        if ((delTableCheck.first['cnt'] as int? ?? 0) > 0) {
          delCnt = (await db.rawQuery('SELECT COUNT(*) as cnt FROM pending_deletions')).first['cnt'] as int? ?? 0;
        }
      } catch (_) {}

      int prodCnt = 0;
      try {
        prodCnt = (await db.rawQuery('SELECT COUNT(*) as cnt FROM product_master WHERE is_synced = 0 OR is_synced IS NULL')).first['cnt'] as int? ?? 0;
      } catch (_) {}

      int batchCnt = 0;
      try {
        batchCnt = (await db.rawQuery('SELECT COUNT(*) as cnt FROM stock_batches WHERE is_synced = 0 OR is_synced IS NULL')).first['cnt'] as int? ?? 0;
      } catch (_) {}

      int patCnt = 0;
      try {
        patCnt = (await db.rawQuery('SELECT COUNT(*) as cnt FROM patients WHERE is_synced = 0 OR is_synced IS NULL')).first['cnt'] as int? ?? 0;
      } catch (_) {}

      int supCnt = 0;
      try {
        supCnt = (await db.rawQuery('SELECT COUNT(*) as cnt FROM suppliers WHERE is_synced = 0 OR is_synced IS NULL')).first['cnt'] as int? ?? 0;
      } catch (_) {}

      return salCnt + purCnt + srCnt + prCnt + adjCnt + patPayCnt + supPayCnt + delCnt + prodCnt + batchCnt + patCnt + supCnt;
    } catch (e) {
      debugPrint('Error getting unsynced total count: $e');
      return -1; // Return -1 to signal unknown/error status to caller instead of false 0
    }
  }

  /// Returns list of unsynced local entries for review in the panel.
  Future<List<Map<String, dynamic>>> getUnsyncedEntriesList() async {
    try {
      await reconcileCloudSyncedEntries();
      final db = await DbHelper.instance.database;
      final sales = await db.query('sales_invoices', where: '(is_synced = 0 OR is_synced IS NULL) AND (is_deleted = 0 OR is_deleted IS NULL)', limit: 30);
      final purchases = await db.query('purchase_entries', where: '(is_synced = 0 OR is_synced IS NULL) AND (is_deleted = 0 OR is_deleted IS NULL)', limit: 30);
      final salesReturns = await db.query('sales_return_invoices', where: 'is_synced = 0 OR is_synced IS NULL', limit: 20);
      final purchaseReturns = await db.query('purchase_return_entries', where: 'is_synced = 0 OR is_synced IS NULL', limit: 20);
      final patientPayments = await db.query('patient_payments', where: 'is_synced = 0 OR is_synced IS NULL', limit: 20);
      final supplierPayments = await db.query('supplier_payments', where: 'is_synced = 0 OR is_synced IS NULL', limit: 20);
      
      final currentTerminal = ServerConfigService.instance.terminalId;
      List<Map<String, dynamic>> combined = [];
      for (var s in sales) {
        final tId = s['terminal_id']?.toString().trim();
        combined.add({
          'type': 'Sales Invoice',
          'entry_no': s['entry_no'] ?? '',
          'date': s['date'] ?? '',
          'amount': s['grand_total'] ?? 0.0,
          'account': s['customer_acc'] ?? s['patient'] ?? 'Customer',
          'terminal_id': (tId != null && tId.isNotEmpty) ? tId : currentTerminal,
        });
      }
      for (var p in purchases) {
        final tId = p['terminal_id']?.toString().trim();
        combined.add({
          'type': 'Purchase Inward',
          'entry_no': p['entry_no'] ?? p['sup_inv_no'] ?? '',
          'date': p['date'] ?? '',
          'amount': p['grand_total'] ?? 0.0,
          'account': p['supplier_name'] ?? '',
          'terminal_id': (tId != null && tId.isNotEmpty) ? tId : currentTerminal,
        });
      }
      for (var sr in salesReturns) {
        final tId = sr['terminal_id']?.toString().trim();
        combined.add({
          'type': 'Sales Return',
          'entry_no': sr['entry_no'] ?? '',
          'date': sr['date'] ?? '',
          'amount': sr['grand_total'] ?? 0.0,
          'account': sr['patient'] ?? 'Customer',
          'terminal_id': (tId != null && tId.isNotEmpty) ? tId : currentTerminal,
        });
      }
      for (var pr in purchaseReturns) {
        final tId = pr['terminal_id']?.toString().trim();
        combined.add({
          'type': 'Purchase Return',
          'entry_no': pr['entry_no'] ?? '',
          'date': pr['date'] ?? '',
          'amount': pr['grand_total'] ?? 0.0,
          'account': pr['supplier_name'] ?? '',
          'terminal_id': (tId != null && tId.isNotEmpty) ? tId : currentTerminal,
        });
      }
      for (var pp in patientPayments) {
        final tId = pp['terminal_id']?.toString().trim();
        combined.add({
          'type': 'Customer Receipt',
          'entry_no': pp['id'] ?? '',
          'date': pp['date'] ?? '',
          'amount': pp['amount'] ?? 0.0,
          'account': pp['patient_name'] ?? 'Patient/Customer',
          'terminal_id': (tId != null && tId.isNotEmpty) ? tId : currentTerminal,
        });
      }
      for (var sp in supplierPayments) {
        final tId = sp['terminal_id']?.toString().trim();
        combined.add({
          'type': 'Supplier Payment',
          'entry_no': sp['id'] ?? '',
          'date': sp['date'] ?? '',
          'amount': sp['amount'] ?? 0.0,
          'account': sp['supplier_name'] ?? 'Supplier',
          'terminal_id': (tId != null && tId.isNotEmpty) ? tId : currentTerminal,
        });
      }
      return combined;
    } catch (e) {
      debugPrint('Error getting unsynced entries list: $e');
      return [];
    }
  }

  /// Returns list of stock batches with negative stock (< 0) resulting from offline multi-PC sales.
  Future<List<Map<String, dynamic>>> getNegativeStockDiscrepancies() async {
    try {
      final db = await DbHelper.instance.database;
      final rows = await db.rawQuery('''
        SELECT sb.product_id, sb.batch_number, sb.current_stock, pm.name as product_name
        FROM stock_batches sb
        LEFT JOIN product_master pm ON sb.product_id = pm.id
        WHERE sb.current_stock < 0
        LIMIT 100
      ''');
      return rows;
    } catch (e) {
      debugPrint('Error getting negative stock discrepancies: $e');
      return [];
    }
  }

  bool get _isReady =>
      ServerConfigService.instance.isServerModeEnabled &&
      ServerConfigService.instance.supabaseUrl.isNotEmpty &&
      ServerConfigService.instance.supabaseAnonKey.isNotEmpty;

  /// Returns standardized Indian Standard Time (IST / Kerala Time UTC+5:30)
  static DateTime get currentIstTime {
    final utcNow = DateTime.now().toUtc();
    return utcNow.add(const Duration(hours: 5, minutes: 30));
  }

  /// Direct cloud fetch for a sale invoice by entryNo (Online-First)
  Future<Map<String, dynamic>?> fetchSaleInvoiceFromCloud(String entryNo) async {
    if (!_isReady) return null;
    try {
      final config = ServerConfigService.instance;
      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
      final uri = Uri.parse('$cleanUrl/rest/v1/sales_invoices?entry_no=eq.${Uri.encodeComponent(entryNo)}&select=*');
      final res = await http.get(uri, headers: config.restHeaders).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        if (data.isNotEmpty) {
          return Map<String, dynamic>.from(data.first);
        }
      }
    } catch (e) {
      debugPrint('fetchSaleInvoiceFromCloud error: $e');
    }
    return null;
  }

  /// Direct cloud fetch for a purchase entry by entryNo (Online-First)
  Future<Map<String, dynamic>?> fetchPurchaseEntryFromCloud(String entryNo) async {
    if (!_isReady) return null;
    try {
      final config = ServerConfigService.instance;
      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
      final uri = Uri.parse('$cleanUrl/rest/v1/purchase_entries?entry_no=eq.${Uri.encodeComponent(entryNo)}&select=*');
      final res = await http.get(uri, headers: config.restHeaders).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        if (data.isNotEmpty) {
          return Map<String, dynamic>.from(data.first);
        }
      }
    } catch (e) {
      debugPrint('fetchPurchaseEntryFromCloud error: $e');
    }
    return null;
  }

  /// Direct fast cloud refresh for a patient's ledger records (Online-First with 2.5s Timeout)
  Future<bool> refreshPatientLedgerCloudDirect(String patientName) async {
    if (!_isReady || patientName.trim().isEmpty) return false;
    try {
      final config = ServerConfigService.instance;
      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
      final encodedName = Uri.encodeComponent(patientName.trim());
      final headers = config.restHeaders;
      final db = await DbHelper.instance.database;

      // 1. Fetch sales_invoices for patient
      final salesUri = Uri.parse('$cleanUrl/rest/v1/sales_invoices?patient=eq.$encodedName&is_deleted=eq.0&select=*');
      final salesRes = await http.get(salesUri, headers: headers).timeout(const Duration(milliseconds: 2500));
      if (salesRes.statusCode == 200) {
        final List<dynamic> salesData = jsonDecode(salesRes.body);
        for (var row in salesData) {
          if (row is Map<String, dynamic>) {
            await db.insert('sales_invoices', Map<String, dynamic>.from(row), conflictAlgorithm: sql.ConflictAlgorithm.replace);
          }
        }
      }

      // 2. Fetch sales_return_invoices for patient
      final returnsUri = Uri.parse('$cleanUrl/rest/v1/sales_return_invoices?patient=eq.$encodedName&is_deleted=eq.0&select=*');
      final returnsRes = await http.get(returnsUri, headers: headers).timeout(const Duration(milliseconds: 2500));
      if (returnsRes.statusCode == 200) {
        final List<dynamic> returnsData = jsonDecode(returnsRes.body);
        for (var row in returnsData) {
          if (row is Map<String, dynamic>) {
            await db.insert('sales_return_invoices', Map<String, dynamic>.from(row), conflictAlgorithm: sql.ConflictAlgorithm.replace);
          }
        }
      }

      // 3. Fetch patient_payments for patient
      final payUri = Uri.parse('$cleanUrl/rest/v1/patient_payments?patient_name=eq.$encodedName&select=*');
      final payRes = await http.get(payUri, headers: headers).timeout(const Duration(milliseconds: 2500));
      if (payRes.statusCode == 200) {
        final List<dynamic> payData = jsonDecode(payRes.body);
        for (var row in payData) {
          if (row is Map<String, dynamic>) {
            await db.insert('patient_payments', Map<String, dynamic>.from(row), conflictAlgorithm: sql.ConflictAlgorithm.replace);
          }
        }
      }
      return true;
    } catch (e) {
      debugPrint('refreshPatientLedgerCloudDirect offline/timeout note: $e');
      return false;
    }
  }

  /// Direct fast cloud refresh for date-range transactions (Online-First with 3.5s Timeout)
  Future<bool> refreshDateRangeTransactionsCloudDirect(DateTime from, DateTime to, {PharmacyProvider? pharmacy}) async {
    if (!_isReady) return false;
    try {
      await syncAllPendingCloudRecords(pharmacy: pharmacy);
      return true;
    } catch (e) {
      debugPrint('refreshDateRangeTransactionsCloudDirect offline/timeout note: $e');
      return false;
    }
  }

  /// Helper function to sanitize sales invoices independently:
  Map<String, dynamic> sanitizeSalesInvoiceRow(Map<String, dynamic> raw) {
    final map = Map<String, dynamic>.from(raw);
    map.remove('customer_phone');
    map.remove('subtotal');
    map.remove('net_amount');
    map.remove('tax_amount');
    map.remove('discount');
    map.remove('tax');
    map.remove('special_order_json');
    map.remove('expecting_date');
    map.remove('special_customer_name');
    map.remove('special_customer_phone');
    return map;
  }

  /// Helper function to sanitize purchase entries independently:
  Map<String, dynamic> sanitizePurchaseEntry(Map<String, dynamic> raw) {
    final map = Map<String, dynamic>.from(raw);
    map.remove('invoice_no');
    map.remove('customer_phone');
    map.remove('patient');
    map.remove('doctor');
    map.remove('subtotal');
    map.remove('discount_amount');
    map.remove('tax_amount');
    map.remove('net_amount');
    map.remove('branch_id');
    map.remove('created_at');
    map.remove('updated_at');
    map.remove('terminal_id');
    
    if (raw.containsKey('subtotal') && !map.containsKey('sub_total')) {
      map['sub_total'] = raw['subtotal'];
    }
    if (raw.containsKey('discount_amount') && !map.containsKey('discount')) {
      map['discount'] = raw['discount_amount'];
    }
    if (raw.containsKey('net_amount') && !map.containsKey('inv_total')) {
      map['inv_total'] = raw['net_amount'];
    }
    if (raw.containsKey('paid_amt') && !map.containsKey('paid_amount')) {
      map['paid_amount'] = raw['paid_amt'];
    }
    return map;
  }

  /// Alias for backward compatibility
  Future<int> syncPendingCloudSalesAndPurchases({PharmacyProvider? pharmacy}) async {
    return syncAllPendingCloudRecords(pharmacy: pharmacy);
  }

  /// Pulls all missing cloud records across ALL transaction endpoints (sales, purchases, sales returns, purchase returns, adjustments)
  /// directly into local SQLite database on PC 2, resolving any local vs cloud count discrepancies automatically.
  Future<int> syncAllPendingCloudRecords({PharmacyProvider? pharmacy}) async {
    if (!_isReady || _isWiping || _isSyncing || _isManualTransfer || _syncPaused || _isRecoveryLocked) return 0;
    int syncedCount = 0;
    try {
      final config = ServerConfigService.instance;
      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
      final headers = config.restHeaders;
      final db = await DbHelper.instance.database;

      final endpoints = [
        {'table': 'sales_invoices', 'pk': 'entry_no', 'items': 'sales_items', 'fk': 'invoice_no'},
        {'table': 'purchase_entries', 'pk': 'entry_no', 'items': 'purchase_items', 'fk': 'entry_no'},
        {'table': 'sales_return_invoices', 'pk': 'entry_no', 'items': 'sales_return_items', 'fk': 'invoice_no'},
        {'table': 'purchase_return_entries', 'pk': 'entry_no', 'items': 'purchase_return_items', 'fk': 'entry_no'},
        {'table': 'stock_adjustments', 'pk': 'entry_no', 'items': 'stock_adjustment_items', 'fk': 'entry_no'},
      ];

      for (var ep in endpoints) {
        if (_syncPaused || _isRecoveryLocked) break;
        final table = ep['table']!;
        final pk = ep['pk']!;
        final itemsTable = ep['items']!;
        final fkCol = ep['fk']!;

        final remoteUri = Uri.parse('$cleanUrl/rest/v1/$table?select=*&order=created_at.desc&limit=500');
        final res = await http.get(remoteUri, headers: headers).timeout(const Duration(seconds: 20));

        if (res.statusCode == 200) {
          final List<dynamic> remoteData = jsonDecode(res.body);
          final List<Map<String, dynamic>> missingRows = [];

          if (remoteData.isNotEmpty) {
            final localRows = await db.query(table, columns: [pk]);
            final Set<String> localKeys = localRows.map((e) => e[pk]?.toString() ?? '').where((k) => k.isNotEmpty).toSet();
            for (var row in remoteData) {
              if (row is Map<String, dynamic>) {
                final rawEntryNo = row[pk]?.toString() ?? row['invoice_no']?.toString() ?? '';
                if (rawEntryNo.isEmpty) continue;
                if (!localKeys.contains(rawEntryNo)) {
                  missingRows.add(row);
                }
              }
            }
          }

          if (missingRows.isNotEmpty) {
            syncedCount += missingRows.length;
            for (var row in missingRows) {
              try {
                final rawEntryNo = row[pk]?.toString() ?? row['invoice_no']?.toString() ?? '';
                final cleanNo = rawEntryNo.contains('_') ? rawEntryNo.substring(rawEntryNo.indexOf('_') + 1) : rawEntryNo;

                Map<String, dynamic> insertRow = Map<String, dynamic>.from(row);

                if (table == 'sales_invoices') {
                  insertRow = sanitizeSalesInvoiceRow(insertRow);
                } else if (table == 'purchase_entries') {
                  insertRow = sanitizePurchaseEntry(insertRow);
                } else if (table == 'purchase_return_entries' || table == 'stock_adjustments') {
                  insertRow.remove('invoice_no');
                }

                // Dynamically filter insertRow against local SQLite table columns
                final tableInfo = await db.rawQuery('PRAGMA table_info($table)');
                final tableCols = tableInfo.map((c) => c['name']?.toString()).whereType<String>().toSet();
                if (tableCols.isNotEmpty) {
                  insertRow.removeWhere((k, _) => !tableCols.contains(k));
                }

                // Insert header into local SQLite safely
                await db.insert(
                  table,
                  insertRow..['is_synced'] = 1,
                  conflictAlgorithm: sql.ConflictAlgorithm.replace,
                );

                // Fetch line items for this header if available
                try {
                  final encodedEntry = Uri.encodeComponent(rawEntryNo);
                  final encodedClean = Uri.encodeComponent(cleanNo);
                  final itemsUri = Uri.parse('$cleanUrl/rest/v1/$itemsTable?$fkCol=in.($encodedEntry,$encodedClean)&select=*');
                  final itemsRes = await http.get(itemsUri, headers: headers).timeout(const Duration(seconds: 4));
                  if (itemsRes.statusCode == 200) {
                    final List<dynamic> itemsData = jsonDecode(itemsRes.body);
                    if (itemsData.isNotEmpty) {
                      await db.delete(itemsTable, where: '$fkCol = ? OR $fkCol = ?', whereArgs: [rawEntryNo, cleanNo]);
                      final Set<String> seenSigs = {};
                      for (var itm in itemsData) {
                        if (itm is Map<String, dynamic>) {
                          final pId = (itm['product_id'] ?? itm['product_name'] ?? '').toString();
                          final batchNo = (itm['batch_number'] ?? itm['batch'] ?? '').toString().trim().toLowerCase();
                          final qVal = (itm['quantity'] ?? itm['qty'] ?? 1).toString();
                          final sig = "$pId|$batchNo|$qVal";
                          
                          if (!seenSigs.contains(sig)) {
                            seenSigs.add(sig);
                            
                            // Strip cloud-only / conflict keys before local SQLite insertion
                            final localRow = Map<String, dynamic>.from(itm);
                            localRow.remove('id'); // Let local SQLite autoincrement manage ID
                            localRow.remove('created_at');

                            // Ensure column names match local schema
                            if (table == 'sales_invoices') {
                              localRow['qty'] = _toInt(localRow['quantity'] ?? localRow['qty'], 1);
                              localRow['s_rate'] = _toDouble(localRow['unit_price'] ?? localRow['s_rate']);
                              localRow['total'] = _toDouble(localRow['total_amount'] ?? localRow['total']);
                            } else if (table == 'purchase_entries') {
                              localRow['qty'] = _toInt(localRow['quantity'] ?? localRow['qty'], 1);
                              localRow['batch'] = localRow['batch_number'] ?? localRow['batch'] ?? '';
                              localRow['expiry'] = localRow['expiry_date'] ?? localRow['expiry'] ?? '';
                              localRow['p_rate'] = _toDouble(localRow['unit_price'] ?? localRow['p_rate']);
                              localRow['total'] = _toDouble(localRow['total_amount'] ?? localRow['total']);
                            }

                            // Dynamically filter localRow against local SQLite item table columns
                            final itemTableInfo = await db.rawQuery('PRAGMA table_info($itemsTable)');
                            final itemTableCols = itemTableInfo.map((c) => c['name']?.toString()).whereType<String>().toSet();
                            if (itemTableCols.isNotEmpty) {
                              localRow.removeWhere((k, _) => !itemTableCols.contains(k));
                            }

                            await db.insert(itemsTable, localRow, conflictAlgorithm: sql.ConflictAlgorithm.replace);
                          }
                        }
                      }
                    }
                  }
                } catch (_) {}
              } catch (e) {
                debugPrint('Error syncing single cloud record ($table): $e');
                AppLogger.instance.error('SUPABASE_SYNC', 'Error syncing single cloud record ($table)', error: e);
              }
            }

            if (pharmacy != null) {
              await pharmacy.recalculateTodayStatsFromDb();
              pharmacy.notifyListeners();
            }
          }
        }
      }

      if (syncedCount > 0) {
        onDataPulled?.call();
        if (pharmacy != null) {
          pharmacy.invalidateSearchProductsCache();
          await pharmacy.recalculateAllStockFromLedgerInternal(db);
          await pharmacy.loadFromDatabase();
          await pharmacy.recalculateTodayStatsFromDb();
          pharmacy.notifyListeners();
        } else {
          try {
            await recalculateStockFromLedgerDirect(db);
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('syncAllPendingCloudRecords note: $e');
    }
    return syncedCount;
  }

  /// Direct SQL stock recalculation from purchase and sales ledgers when PharmacyProvider reference is omitted
  static Future<void> recalculateStockFromLedgerDirect(sql.Database db) async {
    try {
      final List<Map<String, dynamic>> purRows = await db.rawQuery('''
        SELECT 
          pi.product_id,
          pi.product_name,
          LOWER(TRIM(pi.batch)) as clean_batch,
          SUM((IFNULL(pi.qty, 0) + IFNULL(pi.f_qty, 0)) * CASE WHEN IFNULL(pi.packin, 1) > 0 THEN IFNULL(pi.packin, 1) ELSE 1 END) as pur_qty
        FROM purchase_items pi
        JOIN purchase_entries pe ON pi.entry_no = pe.entry_no
        WHERE IFNULL(pe.is_deleted, 0) = 0
        GROUP BY pi.product_id, pi.product_name, LOWER(TRIM(pi.batch))
      ''');

      final List<Map<String, dynamic>> purRetRows = await db.rawQuery('''
        SELECT 
          pri.product_name,
          LOWER(TRIM(pri.batch)) as clean_batch,
          SUM((IFNULL(pri.qty, 0) * CASE WHEN IFNULL(pri.packin, 1) > 0 THEN IFNULL(pri.packin, 1) ELSE 1 END)
              + IFNULL(pri.loose_qty, 0)
              + (IFNULL(pri.f_qty, 0) * CASE WHEN IFNULL(pri.packin, 1) > 0 THEN IFNULL(pri.packin, 1) ELSE 1 END)) as ret_qty
        FROM purchase_return_items pri
        JOIN purchase_return_entries pre ON pri.entry_no = pre.entry_no
        WHERE IFNULL(pre.is_deleted, 0) = 0
        GROUP BY pri.product_name, LOWER(TRIM(pri.batch))
      ''');

      final List<Map<String, dynamic>> saleRows = await db.rawQuery('''
        SELECT 
          si.product_id,
          si.product_name,
          LOWER(TRIM(si.batch_number)) as clean_batch,
          SUM(IFNULL(si.qty, 0)) as sale_qty
        FROM sales_items si
        JOIN sales_invoices s ON (si.invoice_no = s.entry_no OR CAST(si.invoice_no AS TEXT) = CAST(s.entry_no AS TEXT) OR LOWER(TRIM(si.invoice_no)) = LOWER(TRIM(s.entry_no)))
        WHERE IFNULL(s.is_deleted, 0) = 0 AND IFNULL(si.is_deleted, 0) = 0
        GROUP BY si.product_id, si.product_name, LOWER(TRIM(si.batch_number))
      ''');

      final List<Map<String, dynamic>> saleRetRows = await db.rawQuery('''
        SELECT 
          sri.product_id,
          sri.product_name,
          LOWER(TRIM(sri.batch_number)) as clean_batch,
          SUM(IFNULL(sri.quantity, 0)) as sale_ret_qty
        FROM sales_return_items sri
        JOIN sales_return_invoices sr ON sri.return_no = sr.entry_no
        WHERE IFNULL(sr.is_deleted, 0) = 0
        GROUP BY sri.product_id, sri.product_name, LOWER(TRIM(sri.batch_number))
      ''');

      final List<Map<String, dynamic>> adjRows = await db.rawQuery('''
        SELECT 
          sai.product_id,
          LOWER(TRIM(sai.batch_number)) as clean_batch,
          SUM(IFNULL(sai.qty, 0)) as adj_qty
        FROM stock_adjustment_items sai
        JOIN stock_adjustments sa ON sai.adjustment_no = sa.entry_no
        WHERE IFNULL(sa.is_deleted, 0) = 0
        GROUP BY sai.product_id, LOWER(TRIM(sai.batch_number))
      ''');

      final List<Map<String, dynamic>> woRows = await db.rawQuery('''
        SELECT 
          swo.product_id,
          LOWER(TRIM(swo.batch_number)) as clean_batch,
          SUM(IFNULL(swo.quantity, 0)) as wo_qty
        FROM stock_write_offs swo
        GROUP BY swo.product_id, LOWER(TRIM(swo.batch_number))
      ''');

      final List<Map<String, dynamic>> pmList = await db.rawQuery('SELECT id, name FROM product_master');
      final Map<String, String> nameToIdMap = {};
      for (var pm in pmList) {
        final String id = pm['id']?.toString() ?? '';
        final String name = (pm['name']?.toString() ?? '').trim().toLowerCase();
        if (id.isNotEmpty && name.isNotEmpty) {
          nameToIdMap[name] = id;
        }
      }

      final Map<String, int> calculatedStockMap = {};
      final Map<String, int> nameBatchStockMap = {};

      void addStock(String prodId, String prodName, String batch, int qty) {
        if (batch.isEmpty) return;
        if (prodId.isNotEmpty) {
          final key = "$prodId|$batch";
          calculatedStockMap[key] = (calculatedStockMap[key] ?? 0) + qty;
        }
        if (prodName.isNotEmpty) {
          final nameKey = "${prodName.toLowerCase().trim()}|$batch";
          nameBatchStockMap[nameKey] = (nameBatchStockMap[nameKey] ?? 0) + qty;
        }
      }

      for (var r in purRows) {
        final pid = r['product_id']?.toString() ?? '';
        final pname = r['product_name']?.toString() ?? '';
        final b = r['clean_batch']?.toString() ?? '';
        final q = (r['pur_qty'] as num?)?.toInt() ?? 0;
        addStock(pid, pname, b, q);
      }

      for (var r in purRetRows) {
        final pname = r['product_name']?.toString() ?? '';
        final pid = nameToIdMap[pname.toLowerCase().trim()] ?? '';
        final b = r['clean_batch']?.toString() ?? '';
        final q = (r['ret_qty'] as num?)?.toInt() ?? 0;
        addStock(pid, pname, b, -q);
      }

      for (var r in saleRows) {
        final pid = r['product_id']?.toString() ?? '';
        final pname = r['product_name']?.toString() ?? '';
        final b = r['clean_batch']?.toString() ?? '';
        final q = (r['sale_qty'] as num?)?.toInt() ?? 0;
        addStock(pid, pname, b, -q);
      }

      for (var r in saleRetRows) {
        final pid = r['product_id']?.toString() ?? '';
        final pname = r['product_name']?.toString() ?? '';
        final b = r['clean_batch']?.toString() ?? '';
        final q = (r['sale_ret_qty'] as num?)?.toInt() ?? 0;
        addStock(pid, pname, b, q);
      }

      for (var r in adjRows) {
        final pid = r['product_id']?.toString() ?? '';
        final b = r['clean_batch']?.toString() ?? '';
        final q = (r['adj_qty'] as num?)?.toInt() ?? 0;
        addStock(pid, '', b, q);
      }

      for (var r in woRows) {
        final pid = r['product_id']?.toString() ?? '';
        final b = r['clean_batch']?.toString() ?? '';
        final q = (r['wo_qty'] as num?)?.toInt() ?? 0;
        addStock(pid, '', b, -q);
      }

      final List<Map<String, dynamic>> allBatches = await db.rawQuery('''
        SELECT sb.rowid, sb.product_id, sb.batch_number, pm.name as master_name
        FROM stock_batches sb
        LEFT JOIN product_master pm ON sb.product_id = pm.id
      ''');

      await db.transaction((txn) async {
        final batch = txn.batch();
        for (var bRow in allBatches) {
          int rowId = (bRow['rowid'] as num).toInt();
          String pId = bRow['product_id']?.toString() ?? '';
          String pName = (bRow['master_name']?.toString() ?? '').trim().toLowerCase();
          String bNo = (bRow['batch_number']?.toString() ?? '').trim().toLowerCase();
          String keyId = "$pId|$bNo";
          String keyName = "$pName|$bNo";

          int? trueStock = calculatedStockMap[keyId] ?? nameBatchStockMap[keyName];

          if (trueStock != null) {
            batch.rawUpdate('UPDATE stock_batches SET current_stock = ? WHERE rowid = ?', [trueStock, rowId]);
          } else {
            batch.rawUpdate('UPDATE stock_batches SET current_stock = 0 WHERE rowid = ?', [rowId]);
          }
        }
        await batch.commit(noResult: true);
      });
    } catch (e) {
      debugPrint("_recalculateStockFromLedgerDirect error: $e");
    }
  }

  final Map<String, int> _lastReservedSequences = {};
  Timer? _realtimeStreamTimer;
  Timer? _instantSyncDebounceTimer;
  DateTime? _lastStreamPollTime;

  /// Starts live multi-terminal channel listener stream
  void initRealtimeListeners() {
    _realtimeStreamTimer?.cancel();
    _lastStreamPollTime = DateTime.now();
    _realtimeStreamTimer = Timer.periodic(const Duration(minutes: 15), (_) async {
      if (_isSyncing || _isWiping || !ServerConfigService.instance.isServerModeEnabled || !ServerConfigService.instance.isConnected) {
        return;
      }
      try {
        final config = ServerConfigService.instance;
        final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
        final sinceStr = (_lastStreamPollTime ?? DateTime.now().subtract(const Duration(minutes: 15))).toUtc().toIso8601String();
        final uri = Uri.parse('$cleanUrl/rest/v1/stock_batches?updated_at=gt.$sinceStr&select=id&limit=1');
        final res = await http.get(uri, headers: config.restHeaders).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final List<dynamic> items = jsonDecode(res.body);
          if (items.isNotEmpty) {
            _lastStreamPollTime = DateTime.now();
            triggerInstantSync();
          }
        }
      } catch (_) {}
    });
  }

  /// Queues and instantly patches a record in Supabase cloud setting is_deleted = 1
  Future<bool> markEntryDeletedInCloud(String table, String entryNo) async {
    final clean = entryNo.trim();
    if (clean.isEmpty) return false;

    // 1. Queue locally in pending_deletions table to prevent resurrection
    try {
      final db = await DbHelper.instance.database;
      await db.insert(
        'pending_deletions',
        {
          'table_name': table,
          'entry_no': clean,
          'deleted_at': DateTime.now().toIso8601String(),
          'is_synced': 0,
        },
        conflictAlgorithm: sql.ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint("Error queuing pending deletion locally: $e");
    }

    if (!ServerConfigService.instance.isConnected) return false;

    // 2. Execute cloud patch
    bool success = await _executeCloudDeletionPatch(table, clean);
    if (success) {
      try {
        final db = await DbHelper.instance.database;
        await db.update(
          'pending_deletions',
          {'is_synced': 1},
          where: 'table_name = ? AND (entry_no = ? OR entry_no LIKE ?)',
          whereArgs: [table, clean, "%_$clean"],
        );
      } catch (_) {}
    }
    return success;
  }

  Future<bool> _executeCloudDeletionPatch(String table, String clean) async {
    try {
      final config = ServerConfigService.instance;
      final cleanNo = clean.contains('_') ? clean.substring(clean.indexOf('_') + 1) : clean;
      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
      
      final encClean = Uri.encodeComponent(clean);
      final encCleanNo = Uri.encodeComponent(cleanNo);

      String orClause;
      if (table == 'sales_invoices') {
        orClause = 'entry_no.eq.$encClean,entry_no.eq.$encCleanNo,entry_no.like.%25_$encCleanNo,invoice_no.eq.$encClean,invoice_no.eq.$encCleanNo,invoice_no.like.%25_$encCleanNo';
      } else if (['suppliers', 'patients', 'doctors', 'staff', 'accounts', 'racks', 'generics', 'manufacturers', 'categories', 'product_master'].contains(table)) {
        orClause = 'id.eq.$encClean,id.eq.$encCleanNo,entry_no.eq.$encClean,entry_no.eq.$encCleanNo,name.eq.$encClean';
      } else {
        orClause = 'entry_no.eq.$encClean,entry_no.eq.$encCleanNo,entry_no.like.%25_$encCleanNo,id.eq.$encClean';
      }

      final uri = Uri.parse('$cleanUrl/rest/v1/$table?or=($orClause)');
      final res = await http.patch(
        uri,
        headers: config.restHeaders,
        body: jsonEncode({
          'is_deleted': 1,
          'updated_at': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 8));

      // Patch corresponding items table as well
      String? itemsTable;
      String fkCol = 'invoice_no';
      if (table == 'sales_invoices') { itemsTable = 'sales_items'; fkCol = 'invoice_no'; }
      else if (table == 'purchase_entries') { itemsTable = 'purchase_items'; fkCol = 'entry_no'; }
      else if (table == 'sales_return_invoices') { itemsTable = 'sales_return_items'; fkCol = 'return_no'; }
      else if (table == 'purchase_return_entries') { itemsTable = 'purchase_return_items'; fkCol = 'entry_no'; }

      if (itemsTable != null) {
        final itemsUri = Uri.parse('$cleanUrl/rest/v1/$itemsTable?or=($fkCol.eq.$encClean,$fkCol.eq.$encCleanNo,$fkCol.like.%25_$encCleanNo)');
        await http.patch(
          itemsUri,
          headers: config.restHeaders,
          body: jsonEncode({'is_deleted': 1}),
        ).timeout(const Duration(seconds: 8));
      }

      if (res.statusCode < 400) {
        debugPrint("Cloud Sync: Marked $table entry #$clean as deleted on Supabase.");
        return true;
      }
    } catch (e) {
      debugPrint("Cloud Sync error marking $table entry #$clean as deleted: $e");
    }
    return false;
  }

  /// Processes unsynced tombstones from sync_deletions_queue table and patches Supabase Cloud
  Future<void> processSyncDeletionsQueue() async {
    if (!ServerConfigService.instance.isConnected) return;
    try {
      final db = await DbHelper.instance.database;
      final queueCheck = await db.rawQuery(
        "SELECT COUNT(*) as cnt FROM sqlite_master WHERE type='table' AND name='sync_deletions_queue'"
      );
      if (queueCheck.isEmpty || (queueCheck.first['cnt'] as int? ?? 0) == 0) return;

      final queueList = await db.query(
        'sync_deletions_queue',
        where: 'is_synced = 0 OR is_synced IS NULL',
        limit: 50,
      );

      for (var row in queueList) {
        final String rowId = row['id']?.toString() ?? '';
        final String tName = row['table_name']?.toString() ?? '';
        final String recordId = row['record_id']?.toString() ?? '';

        if (tName.isNotEmpty && recordId.isNotEmpty) {
          bool patched = await _executeCloudDeletionPatch(tName, recordId);
          if (patched && rowId.isNotEmpty) {
            await db.update(
              'sync_deletions_queue',
              {'is_synced': 1},
              where: 'id = ?',
              whereArgs: [rowId],
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Error processing sync_deletions_queue: $e");
    }
  }

  /// Processes unsynced pending deletions and patches Supabase Cloud
  Future<void> processPendingDeletions() async {
    if (!ServerConfigService.instance.isConnected) return;
    await processSyncDeletionsQueue();
    try {
      final db = await DbHelper.instance.database;
      final pendingList = await db.query(
        'pending_deletions',
        where: 'is_synced = 0 OR is_synced IS NULL',
        limit: 50,
      );

      for (var row in pendingList) {
        final String tName = row['table_name']?.toString() ?? '';
        final String entryNo = row['entry_no']?.toString() ?? '';
        final int rowId = (row['id'] as num).toInt();

        if (tName.isNotEmpty && entryNo.isNotEmpty) {
          bool patched = await _executeCloudDeletionPatch(tName, entryNo);
          if (patched) {
            await db.update(
              'pending_deletions',
              {'is_synced': 1},
              where: 'id = ?',
              whereArgs: [rowId],
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Error processing pending deletions: $e");
    }
  }

  /// Pushes security audit logs, deletions, and rate overrides directly to the cloud audit table
  Future<bool> saveAuditLogToCloud({
    required String action,
    required String details,
    String severity = 'INFO',
    String? referenceId,
  }) async {
    if (!_isReady) return false;
    try {
      final config = ServerConfigService.instance;
      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
      final uri = Uri.parse('$cleanUrl/rest/v1/cloud_audit_logs');
      final body = jsonEncode({
        'action': action,
        'details': details,
        'severity': severity,
        'reference_id': referenceId ?? '',
        'branch_id': config.storeBranchId,
        'terminal_id': config.terminalId,
        'timestamp': DateTime.now().toIso8601String(),
      });
      final res = await http.post(uri, headers: config.restHeaders, body: body).timeout(const Duration(seconds: 4));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      debugPrint('saveAuditLogToCloud error: $e');
      return false;
    }
  }

  /// Posts telemetry health and error logs to cloud (Instant 0ms bypass when offline)
  Future<bool> pushTelemetryLogToCloud({
    required String eventName,
    required String errorMessage,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_isReady || !ServerConfigService.instance.isConnected) return false;
    try {
      final config = ServerConfigService.instance;
      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
      final uri = Uri.parse('$cleanUrl/rest/v1/telemetry_logs');
      final body = jsonEncode({
        'event_name': eventName,
        'error_message': errorMessage,
        'metadata': jsonEncode(metadata ?? {}),
        'terminal_id': config.terminalId,
        'branch_id': config.storeBranchId,
        'created_at': DateTime.now().toIso8601String(),
      });
      final res = await http.post(uri, headers: config.restHeaders, body: body).timeout(const Duration(seconds: 4));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Reports automated client health metrics (latency, local sync state, memory status) to cloud telemetry
  Future<bool> reportServerTelemetryHealth({
    int pingLatencyMs = 0,
    String statusNote = 'Healthy',
  }) async {
    if (!_isReady || !ServerConfigService.instance.isConnected) return false;
    return pushTelemetryLogToCloud(
      eventName: 'CLIENT_HEALTH_PING',
      errorMessage: statusNote,
      metadata: {
        'ping_latency_ms': pingLatencyMs,
        'unsynced_pending': _processedRowsCount,
        'is_syncing': _isSyncing,
        'last_sync_time': _lastSyncTime?.toIso8601String() ?? 'Never',
      },
    );
  }

  /// Direct fast cloud query for the latest max entry number on the server (Online-First with Atomic Collision Protection)
  Future<String?> fetchRemoteNextEntryNo(String table, String fy, {String? prefix}) async {
    if (!_isReady) return null;
    try {
      final config = ServerConfigService.instance;
      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
      
      final column = (table == 'prescriptions' || table == 'stock_write_offs') ? 'id' : 'entry_no';
      String query = '$cleanUrl/rest/v1/$table?select=$column&financial_year=eq.${Uri.encodeComponent(fy)}';
      if (prefix != null && prefix.trim().isNotEmpty) {
        final cleanPrefix = prefix.trim();
        query += '&$column=like.${Uri.encodeComponent('%$cleanPrefix%')}';
      }
      query += '&order=$column.desc&limit=1';

      final uri = Uri.parse(query);
      final res = await http.get(uri, headers: config.restHeaders).timeout(const Duration(milliseconds: 1500));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        if (data.isNotEmpty) {
          final rawVal = data.first[column]?.toString() ?? '';
          return rawVal;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Direct cloud fetch for recent 20 sales invoices
  Future<List<Map<String, dynamic>>> fetchRecentSalesInvoicesCloud({int limit = 20}) async {
    if (_isWiping || !_isReady) return [];
    try {
      final config = ServerConfigService.instance;
      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
      final uri = Uri.parse('$cleanUrl/rest/v1/sales_invoices?select=*&order=created_at.desc&limit=$limit');
      final res = await http.get(uri, headers: config.restHeaders).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('fetchRecentSalesInvoicesCloud error: $e');
    }
    return [];
  }

  /// Direct cloud fetch for recent 20 purchase entries
  Future<List<Map<String, dynamic>>> fetchRecentPurchaseEntriesCloud({int limit = 20}) async {
    if (_isWiping || !_isReady) return [];
    try {
      final config = ServerConfigService.instance;
      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
      final uri = Uri.parse('$cleanUrl/rest/v1/purchase_entries?select=*&order=created_at.desc&limit=$limit');
      final res = await http.get(uri, headers: config.restHeaders).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('fetchRecentPurchaseEntriesCloud error: $e');
    }
    return [];
  }

  /// Directly posts a sale invoice and items to Supabase cloud REST table.
  /// Uses the exact same safe upload path as offline retries.
  Future<bool> saveSaleDirectToCloud({
    required String entryNo,
    required String fy,
    required String dateStr,
    required String customerAcc,
    required String patient,
    required String mobile,
    required String doctor,
    required String doctorRegNo,
    required double subTotal,
    required double grandTotal,
    required double rcvdAmt,
    required List<Map<String, dynamic>> items,
  }) async {
    final invoiceMap = {
      'entry_no': entryNo,
      'invoice_no': entryNo,
      'financial_year': fy,
      'date': dateStr,
      'customer_acc': customerAcc,
      'patient': patient,
      'mobile': mobile,
      'doctor': doctor,
      'doctor_reg_no': doctorRegNo,
      'sub_total': subTotal,
      'grand_total': grandTotal,
      'net_amount': grandTotal,
      'rcvd_amt': rcvdAmt,
      'is_synced': 0,
      'is_cloud_synced': 0,
    };

    return await pushSalesInvoice(invoiceMap, items);
  }

  /// Single-Roundtrip Atomic RPC Sale Saving (Sub-30ms execution with standard REST fallback)
  Future<bool> saveSaleInvoiceAtomicRPC({
    required String entryNo,
    required String fy,
    required String dateStr,
    required String customerAcc,
    required String patient,
    required String mobile,
    required String doctor,
    required String doctorRegNo,
    required double subTotal,
    required double grandTotal,
    required double rcvdAmt,
    required List<Map<String, dynamic>> items,
  }) async {
    return saveSaleDirectToCloud(
      entryNo: entryNo, fy: fy, dateStr: dateStr, customerAcc: customerAcc,
      patient: patient, mobile: mobile, doctor: doctor, doctorRegNo: doctorRegNo,
      subTotal: subTotal, grandTotal: grandTotal, rcvdAmt: rcvdAmt, items: items,
    );
  }

  /// Single-Roundtrip Atomic RPC Purchase Saving (Sub-50ms execution with standard REST fallback)
  Future<bool> savePurchaseEntryAtomicRPC({
    required Map<String, dynamic> purchaseHeader,
    required List<Map<String, dynamic>> items,
  }) async {
    if (!_isReady) {
      return await pushPurchaseEntry(purchaseHeader, items);
    }

    try {
      final config = ServerConfigService.instance;
      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
      final branchId = config.storeBranchId;

      final headerPayload = Map<String, dynamic>.from(purchaseHeader);
      headerPayload['branch_id'] = branchId;
      headerPayload['terminal_id'] = (headerPayload['terminal_id']?.toString().trim().isNotEmpty == true)
          ? headerPayload['terminal_id'].toString().trim()
          : config.terminalId;
      headerPayload['updated_at'] = DateTime.now().toIso8601String();

      final itemsPayload = items.map((it) {
        final copy = Map<String, dynamic>.from(it);
        copy['branch_id'] = branchId;
        copy['terminal_id'] = (copy['terminal_id']?.toString().trim().isNotEmpty == true)
            ? copy['terminal_id'].toString().trim()
            : headerPayload['terminal_id'];
        return copy;
      }).toList();

      final rpcUri = Uri.parse('$cleanUrl/rest/v1/rpc/fn_save_purchase_entry_atomic');
      final res = await http.post(
        rpcUri,
        headers: config.restHeaders,
        body: jsonEncode({
          'p_purchase': headerPayload,
          'p_items': itemsPayload,
        }),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final resMap = jsonDecode(res.body);
        if (resMap is Map && resMap['success'] == true) {
          final db = await DbHelper.instance.database;
          final entryNo = purchaseHeader['entry_no']?.toString() ?? '';
          if (entryNo.isNotEmpty) {
            await db.rawUpdate(
              'UPDATE purchase_entries SET is_synced = 1, is_cloud_synced = 1 WHERE entry_no = ? OR sup_inv_no = ?',
              [entryNo, entryNo],
            );
            await db.rawUpdate(
              'UPDATE purchase_items SET is_synced = 1, is_cloud_synced = 1 WHERE entry_no = ?',
              [entryNo],
            );
          }
          notifyListeners();
          return true;
        } else {
          debugPrint('Cloud Purchase RPC rejected: ${resMap is Map ? resMap['message'] : res.body}');
        }
      }
    } catch (e) {
      debugPrint('savePurchaseEntryAtomicRPC error: $e');
    }

    // Fallback seamlessly to standard REST endpoints if RPC fails
    return await pushPurchaseEntry(purchaseHeader, items);
  }

  /// Loads stored last sync timestamp and initial sync completion state on app startup.
  Future<void> init() async {
    _isBulkImportActive = false;
    _syncPaused = false;
    _isRecoveryLocked = false;
    _cancelRequested = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      _isInitialSyncCompleted = prefs.getBool(_keyInitialSyncCompleted) ?? false;
      final storedTs = prefs.getString(_keyLastSyncTimestamp);
      if (storedTs != null && storedTs.isNotEmpty) {
        _lastSyncTime = DateTime.tryParse(storedTs);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading last sync timestamp: $e');
    }
  }

  Future<void> initCategoryTracker({required bool isExport, Set<String>? selectedCategories}) async {
    _isExportMode = isExport;
    _currentRecordsPerSec = 0.0;
    _currentEtaSeconds = 0;
    if (selectedCategories != null) {
      _activeSelectedCategoryIds = selectedCategories;
    }

    try {
      final db = await DbHelper.instance.database;
      final pBefore = (await db.rawQuery('SELECT COUNT(*) as cnt FROM product_master')).first['cnt'] as int? ?? 0;
      final bBefore = (await db.rawQuery('SELECT COUNT(*) as cnt FROM stock_batches')).first['cnt'] as int? ?? 0;
      final salBefore = (await db.rawQuery('SELECT COUNT(*) as cnt FROM sales_invoices WHERE is_deleted = 0')).first['cnt'] as int? ?? 0;
      final purBefore = (await db.rawQuery('SELECT COUNT(*) as cnt FROM purchase_entries WHERE is_deleted = 0')).first['cnt'] as int? ?? 0;
      final payBefore = (await db.rawQuery('SELECT COUNT(*) as cnt FROM patient_payments')).first['cnt'] as int? ?? 0;
      final supPayBefore = (await db.rawQuery('SELECT COUNT(*) as cnt FROM supplier_payments')).first['cnt'] as int? ?? 0;
      final credBefore = (await db.rawQuery('SELECT COUNT(*) as cnt FROM supplier_credit_notes')).first['cnt'] as int? ?? 0;
      final accBefore = (await db.rawQuery('SELECT COUNT(*) as cnt FROM accounts')).first['cnt'] as int? ?? 0;
      final vBefore = payBefore + supPayBefore + credBefore + accBefore;

      final srBefore = (await db.rawQuery('SELECT COUNT(*) as cnt FROM sales_return_invoices')).first['cnt'] as int? ?? 0;
      final prBefore = (await db.rawQuery('SELECT COUNT(*) as cnt FROM purchase_return_entries')).first['cnt'] as int? ?? 0;
      final patBefore = (await db.rawQuery('SELECT COUNT(*) as cnt FROM patients')).first['cnt'] as int? ?? 0;
      final supBefore = (await db.rawQuery('SELECT COUNT(*) as cnt FROM suppliers')).first['cnt'] as int? ?? 0;
      final docBefore = (await db.rawQuery('SELECT COUNT(*) as cnt FROM doctors')).first['cnt'] as int? ?? 0;

      final adjBefore = (await db.rawQuery('SELECT COUNT(*) as cnt FROM stock_adjustments')).first['cnt'] as int? ?? 0;
      final woBefore = (await db.rawQuery('SELECT COUNT(*) as cnt FROM stock_write_offs')).first['cnt'] as int? ?? 0;

      _categorySyncStatuses = [
        CategorySyncStatus(id: 'products', name: 'Registered Stocks', icon: Icons.medication_rounded, beforeCount: pBefore, totalCount: pBefore),
        CategorySyncStatus(id: 'batches', name: 'Inventory', icon: Icons.layers_rounded, beforeCount: bBefore, totalCount: bBefore),
        CategorySyncStatus(id: 'sales', name: 'Sales', icon: Icons.point_of_sale_rounded, beforeCount: salBefore, totalCount: salBefore),
        CategorySyncStatus(id: 'purchases', name: 'Purchase', icon: Icons.shopping_bag_rounded, beforeCount: purBefore, totalCount: purBefore),
        CategorySyncStatus(id: 'sales_returns', name: 'Sales Return', icon: Icons.assignment_return_rounded, beforeCount: srBefore, totalCount: srBefore),
        CategorySyncStatus(id: 'purchase_returns', name: 'Purchase Return', icon: Icons.unarchive_rounded, beforeCount: prBefore, totalCount: prBefore),
        CategorySyncStatus(id: 'prescriptions_adjustments', name: 'Adjustment', icon: Icons.tune_rounded, beforeCount: adjBefore, totalCount: adjBefore),
        CategorySyncStatus(id: 'damages', name: 'Damage', icon: Icons.remove_shopping_cart_rounded, beforeCount: woBefore, totalCount: woBefore),
        CategorySyncStatus(id: 'patients', name: 'Patients, Doctors & Phone Numbers', icon: Icons.people_alt_rounded, beforeCount: patBefore, totalCount: patBefore),
        CategorySyncStatus(id: 'suppliers_doctors', name: 'Suppliers & Wholesalers', icon: Icons.medical_services_rounded, beforeCount: supBefore + docBefore, totalCount: supBefore + docBefore),
        CategorySyncStatus(id: 'customer_account', name: 'Customer Account', icon: Icons.person_search_rounded, beforeCount: 0, totalCount: 0),
        CategorySyncStatus(id: 'wholesale_account', name: 'Wholesale Account', icon: Icons.store_rounded, beforeCount: 0, totalCount: 0),
        CategorySyncStatus(id: 'accounts_daybook', name: 'Daybook, Expenses & Petty Cash', icon: Icons.today_rounded, beforeCount: vBefore, totalCount: vBefore),
        CategorySyncStatus(id: 'month_book', name: 'Month Book', icon: Icons.calendar_month_rounded, beforeCount: 0, totalCount: 0),
        CategorySyncStatus(id: 'vouchers', name: 'Vouchers', icon: Icons.receipt_rounded, beforeCount: 0, totalCount: 0),
      ];
    } catch (_) {
      _categorySyncStatuses = [
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

    if (selectedCategories != null && selectedCategories.isNotEmpty) {
      _categorySyncStatuses.retainWhere((cat) => selectedCategories.contains(cat.id));
    }

    notifyListeners();
  }

  void updateCategoryProgress(String id, {required int processed, required int total, CategorySyncState? state}) {
    if (_categorySyncStatuses.isEmpty) return;
    final index = _categorySyncStatuses.indexWhere((c) => c.id == id);
    if (index != -1) {
      final cat = _categorySyncStatuses[index];
      if (total > 0) cat.totalCount = total;
      cat.processedCount = processed.clamp(0, cat.totalCount > 0 ? cat.totalCount : processed);
      if (state != null) {
        cat.state = state;
        if (state == CategorySyncState.completed && cat.totalCount > 0) {
          cat.processedCount = cat.totalCount;
        }
      }
    }

    _processedRowsCount = _categorySyncStatuses.fold(0, (sum, cat) => sum + cat.processedCount);
    final catTotal = _categorySyncStatuses.fold(0, (sum, cat) => sum + cat.totalCount);
    if (catTotal > 0) {
      _totalRowsToSync = catTotal;
    }

    if (_syncStartTime != null && _processedRowsCount > 0) {
      final elapsedMs = DateTime.now().difference(_syncStartTime!).inMilliseconds;
      if (elapsedMs >= 2000 && _processedRowsCount >= 100) {
        final rawSpeed = (_processedRowsCount / (elapsedMs / 1000.0));
        _currentRecordsPerSec = rawSpeed;
        final remaining = (_totalRowsToSync - _processedRowsCount).clamp(0, _totalRowsToSync);
        if (_currentRecordsPerSec > 0) {
          final rawEta = (remaining / _currentRecordsPerSec).round();
          _currentEtaSeconds = rawEta > 7200 ? 7200 : rawEta;
        } else {
          _currentEtaSeconds = 0;
        }
      } else {
        _currentRecordsPerSec = 0;
        _currentEtaSeconds = 0;
      }
    }

    syncProgressNotifier.value = _syncProgress;
    final now = DateTime.now();
    if (state != null || _lastProgressNotifyTime == null || now.difference(_lastProgressNotifyTime!).inMilliseconds > 250) {
      _lastProgressNotifyTime = now;
      // Schedule notifyListeners asynchronously to prevent call-stack deadlocks with active SQLite transactions
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (hasListeners) {
          notifyListeners();
        }
      });
    }
  }

  String get formattedEta {
    if (_currentEtaSeconds <= 0 || _processedRowsCount < 100) {
      return 'Calculating...';
    }
    if (_currentEtaSeconds > 3600) {
      final h = (_currentEtaSeconds / 3600).toStringAsFixed(1);
      return '${h}h remaining';
    }
    if (_currentEtaSeconds > 60) {
      final m = (_currentEtaSeconds / 60).ceil();
      return '${m}m remaining';
    }
    return '${_currentEtaSeconds}s remaining';
  }

  int _totalRowsToSync = 0;
  int _processedRowsCount = 0;
  DateTime? _syncStartTime;

  void _updateDynamicProgress(int newlyProcessedRows, String currentStepName) {
    _processedRowsCount += newlyProcessedRows;
    if (_totalRowsToSync <= 0) return;
    if (_processedRowsCount > _totalRowsToSync) {
      _processedRowsCount = _totalRowsToSync;
    }

    final double rawPct = (_processedRowsCount / _totalRowsToSync).clamp(0.0, 1.0);
    if (rawPct > _syncProgress) {
      _syncProgress = rawPct;
    }

    syncProgressNotifier.value = _syncProgress;

    // ⚡ FIX: Update any active background sync task progress so the top notification bell increments past 0%
    try {
      // If you have a reference or want to broadcast progress:
      // AppNotificationService.instance.updateActiveTaskProgress(rawPct, currentStepName);
    } catch (_) {}

    if (_syncStartTime != null) {
      final elapsedMs = DateTime.now().difference(_syncStartTime!).inMilliseconds;
      if (elapsedMs >= 2000 && _processedRowsCount >= 100) {
        final rawSpeed = (_processedRowsCount / (elapsedMs / 1000.0));
        _currentRecordsPerSec = rawSpeed;
        final int remainingRows = (_totalRowsToSync - _processedRowsCount).clamp(0, _totalRowsToSync);
        if (_currentRecordsPerSec > 0) {
          final rawEta = (remainingRows / _currentRecordsPerSec).round();
          _currentEtaSeconds = rawEta > 7200 ? 7200 : rawEta;
        } else {
          _currentEtaSeconds = 0;
        }

        final displayPct = (syncProgress * 100).toInt();
        if (_currentEtaSeconds > 0) {
          _syncStatusMessage = '$displayPct% - $currentStepName ($_processedRowsCount/$_totalRowsToSync) • ⏱️ $formattedEta';
        } else {
          _syncStatusMessage = '$displayPct% - $currentStepName ($_processedRowsCount/$_totalRowsToSync)...';
        }
      } else {
        _currentRecordsPerSec = 0;
        _currentEtaSeconds = 0;
        final displayPct = (syncProgress * 100).toInt();
        _syncStatusMessage = '$displayPct% - $currentStepName ($_processedRowsCount/$_totalRowsToSync) • Calculating ETA...';
      }
    }

    final now = DateTime.now();
    if (_lastProgressNotifyTime == null || now.difference(_lastProgressNotifyTime!).inMilliseconds > 250) {
      _lastProgressNotifyTime = now;
      notifyListeners();
    }
  }

  /// Triggers an immediate background cloud push/pull sync cycle without debounce delays
  void triggerInstantSync({
    bool isManualTransfer = false,
    Set<String>? selectedCategories,
    bool isSilent = false,
  }) {
    if (ServerConfigService.instance.isServerModeEnabled) {
      _instantSyncDebounceTimer?.cancel();
      _isSilentBackgroundSync = isSilent;
      unawaited(syncAllPendingData(
        isManualTransfer: isManualTransfer,
        selectedCategories: selectedCategories,
      ));
    }
  }

  /// Fetches all rows from a Supabase REST endpoint
  Future<List<dynamic>> fetchAllRows(String endpoint, {String timeFilter = ''}) async {
    final config = ServerConfigService.instance;
    List<dynamic> allRows = [];
    int offset = 0;
    const int limit = 1000;
    bool hasMore = true;

    while (hasMore) {
      if (_cancelRequested) break;
      int pageAttempt = 0;
      bool pageSuccess = false;

      while (pageAttempt < 2 && !pageSuccess) {
        pageAttempt++;
        try {
          final branchParam = config.storeBranchId.isNotEmpty ? 'branch_id=eq.${config.storeBranchId}&' : '';
          var uri = Uri.parse('${config.supabaseUrl}/rest/v1/$endpoint?${branchParam}select=*&limit=$limit&offset=$offset$timeFilter');
          var res = await http.get(uri, headers: config.restHeaders).timeout(const Duration(seconds: 25));

          if (res.statusCode >= 400 || (res.statusCode == 200 && jsonDecode(res.body) is List && (jsonDecode(res.body) as List).isEmpty && offset == 0)) {
            if (branchParam.isNotEmpty) {
              final fallbackUri = Uri.parse('${config.supabaseUrl}/rest/v1/$endpoint?select=*&limit=$limit&offset=$offset$timeFilter');
              final fallbackRes = await http.get(fallbackUri, headers: config.restHeaders).timeout(const Duration(seconds: 25));
              if (fallbackRes.statusCode == 200 && jsonDecode(fallbackRes.body) is List && (jsonDecode(fallbackRes.body) as List).isNotEmpty) {
                res = fallbackRes;
              }
            }
            if (timeFilter.isNotEmpty && (res.statusCode >= 400 || (jsonDecode(res.body) is List && (jsonDecode(res.body) as List).isEmpty))) {
              final fallbackUri = Uri.parse('${config.supabaseUrl}/rest/v1/$endpoint?${branchParam}select=*&limit=$limit&offset=$offset');
              final fallbackRes = await http.get(fallbackUri, headers: config.restHeaders).timeout(const Duration(seconds: 25));
              if (fallbackRes.statusCode == 200 && jsonDecode(fallbackRes.body) is List && (jsonDecode(fallbackRes.body) as List).isNotEmpty) {
                res = fallbackRes;
              } else if (branchParam.isNotEmpty) {
                final fallbackNoBranchUri = Uri.parse('${config.supabaseUrl}/rest/v1/$endpoint?select=*&limit=$limit&offset=$offset');
                final fallbackNoBranchRes = await http.get(fallbackNoBranchUri, headers: config.restHeaders).timeout(const Duration(seconds: 25));
                if (fallbackNoBranchRes.statusCode == 200) {
                  res = fallbackNoBranchRes;
                }
              }
            }
          }

          if (res.statusCode == 200) {
            final List items = res.body.length > 10240
                ? await compute(_parseJsonListIsolate, res.body)
                : (jsonDecode(res.body) as List<dynamic>);
            if (items.isEmpty) {
              hasMore = false;
              pageSuccess = true;
            } else {
              allRows.addAll(items);
              pageSuccess = true;
              offset += items.length;
              if (items.length < limit) {
                hasMore = false;
              }
            }
          } else {
            debugPrint('Supabase GET $endpoint status ${res.statusCode} (attempt $pageAttempt)');
            hasMore = false;
            break;
          }
        } catch (e) {
          debugPrint('Error fetching $endpoint offset $offset (attempt $pageAttempt): $e');
          if (pageAttempt < 2) {
            await Future.delayed(const Duration(milliseconds: 500));
          } else {
            hasMore = false;
          }
        }
      }
      await Future.delayed(Duration.zero);
    }
    return allRows;
  }

  /// Ensures 100% of the product master catalog is downloaded from Supabase Cloud to local SQLite.
  /// Runs automatically on PC2 startup / connection within < 3 seconds.
  Future<bool> ensureMasterCatalogDownloaded({PharmacyProvider? pharmacy}) async {
    final config = ServerConfigService.instance;
    if (config.supabaseUrl.isEmpty || config.supabaseAnonKey.isEmpty) return false;

    if (_isSyncing) return false;
    setBulkImportActive(true);

    try {
      final db = await DbHelper.instance.database;
      try {
        await db.execute('PRAGMA journal_mode = WAL;');
        await db.execute('PRAGMA synchronous = NORMAL;');
        await db.execute('PRAGMA busy_timeout = 30000;');
      } catch (_) {}

      final localProdCount = (await db.rawQuery('SELECT COUNT(*) as cnt FROM product_master')).first['cnt'] as int? ?? 0;

      final remoteProducts = await fetchAllRows('product_master');

      if (remoteProducts.isEmpty) {
        debugPrint('⚡ ensureMasterCatalogDownloaded: Cloud product_master is empty. Preserving local catalog ($localProdCount items).');
        return true;
      }

      // Safety Guard: Only truncate local catalog if cloud has a valid full catalog and local is wildly out of sync due to corruption
      if (remoteProducts.length > 100 && localProdCount > remoteProducts.length * 2.5) {
        debugPrint('⚡ ensureMasterCatalogDownloaded: Truncating local duplicates ($localProdCount local vs ${remoteProducts.length} cloud)...');
        try { await db.execute('PRAGMA foreign_keys = OFF;'); } catch (_) {}
        try {
          await db.execute('DROP TRIGGER IF EXISTS ad_product_master_fts;');
          await db.execute('DROP TRIGGER IF EXISTS au_product_master_fts;');
          await db.execute('DROP TRIGGER IF EXISTS ai_product_master_fts;');
        } catch (_) {}
        try { await db.execute('DELETE FROM product_master;'); } catch (_) {}
        try { await db.execute('DELETE FROM product_search_fts;'); } catch (_) {}
        try { await db.execute('PRAGMA foreign_keys = ON;'); } catch (_) {}
      }

      debugPrint('⚡ ensureMasterCatalogDownloaded: Downloaded ${remoteProducts.length} master products from cloud (Local count: $localProdCount)');

      const int chunkSize = 2000;
      for (int i = 0; i < remoteProducts.length; i += chunkSize) {
        if (_cancelRequested) break;
        final chunk = remoteProducts.sublist(i, min(i + chunkSize, remoteProducts.length));

        await db.transaction((txn) async {
          final batch = txn.batch();
          for (var item in chunk) {
            if (item is Map<String, dynamic>) {
              final prodId = (item['id'] ?? '').toString().trim();
              final prodName = (item['product_name'] ?? item['name'] ?? '').toString().trim();
              if (prodId.isEmpty || prodName.isEmpty) continue;

              batch.insert('product_master', {
                'id': prodId,
                'name': prodName,
                'generic_name': item['generic_name']?.toString() ?? '',
                'category_id': item['category_id']?.toString() ?? '',
                'sub_category_id': item['sub_category_id']?.toString() ?? '',
                'manufacturer_id': item['manufacturer_id']?.toString() ?? '',
                'rack_id': item['rack_id']?.toString() ?? '',
                'hsn_code': item['hsn_code']?.toString() ?? '',
                'gst_percent': _parseGstPercent(item, 12.0),
                's_disc_percent': _parseDiscPercent(item, 0.0),
                'schedule': item['schedule']?.toString() ?? 'H',
                'reorder_level': _toInt(item['reorder_level'], 10),
                'max_level': _toInt(item['max_level'], 100),
                'unit': item['unit']?.toString() ?? 'Strip',
                'packing': _toInt(item['packing'], 10),
                'mrp': _toDouble(item['mrp'], 0.0),
                'purchase_rate': _toDouble(item['purchase_rate'], 0.0),
                'sale_rate': _toDouble(item['selling_price'] ?? item['sale_rate'], 0.0),
                'patent': item['patent']?.toString() ?? '',
                'barcode': item['barcode']?.toString() ?? '',
                'is_controlled': _toInt(item['is_controlled'], 0),
                'is_banned': _toInt(item['is_banned'], 0),
                'is_nrx': _toInt(item['is_nrx'], 0),
                'is_active': _toInt(item['is_active'], 1),
                'is_disc_locked': _toInt(item['is_disc_locked'], 0),
                'preferred_wholesale': item['preferred_wholesale']?.toString() ?? '',
                'lead_time': _toInt(item['lead_time'], 2),
                'is_synced': 1,
                'updated_at': item['updated_at']?.toString() ?? DateTime.now().toIso8601String(),
              }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
            }
          }
          await batch.commit(noResult: true);
        });
        await Future.delayed(const Duration(milliseconds: 10)); // Yield briefly to renderer
      }

      if (pharmacy != null) {
        await pharmacy.syncInventoryFromDb();
      }
      return true;
    } catch (e) {
      debugPrint('Error in ensureMasterCatalogDownloaded: $e');
      return false;
    } finally {
      setBulkImportActive(false);
    }
  }

  Future<void> _safeChunkedSnapshotInsert(
    sql.Database db,
    String tableName,
    List<dynamic> rows, {
    int chunkSize = 500,
    bool setSyncedFlag = false,
  }) async {
    if (rows.isEmpty) return;

    final pragmaCols = await db.rawQuery('PRAGMA table_info($tableName)');
    final validCols = pragmaCols
        .map((c) => c['name']?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .toSet();

    for (int i = 0; i < rows.length; i += chunkSize) {
      if (_syncPaused) break;
      final chunk = rows.sublist(i, (i + chunkSize < rows.length) ? i + chunkSize : rows.length);
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final row in chunk) {
          if (row is Map<String, dynamic>) {
            final cleanRow = <String, dynamic>{};
            for (var entry in row.entries) {
              if (validCols.contains(entry.key)) {
                cleanRow[entry.key] = entry.value;
              }
            }

            // Map aliases for schema compatibility between cloud and local SQLite
            if (tableName == 'product_master') {
              if (!cleanRow.containsKey('name') || cleanRow['name'] == null || cleanRow['name'].toString().trim().isEmpty) {
                cleanRow['name'] = row['product_name'] ?? row['title'] ?? 'Unnamed Product';
              }
              if (!cleanRow.containsKey('sale_rate') && cleanRow.containsKey('selling_price')) {
                cleanRow['sale_rate'] = cleanRow['selling_price'];
              }
              if (!cleanRow.containsKey('gst_percent') && cleanRow.containsKey('gst_rate')) {
                cleanRow['gst_percent'] = cleanRow['gst_rate'];
              }
            } else if (tableName == 'stock_batches') {
              if (!cleanRow.containsKey('sale_rate') && cleanRow.containsKey('selling_rate')) {
                cleanRow['sale_rate'] = cleanRow['selling_rate'];
              }
              if (!cleanRow.containsKey('current_stock') && cleanRow.containsKey('current_quantity')) {
                cleanRow['current_stock'] = cleanRow['current_quantity'];
              }
            }

            if (setSyncedFlag && validCols.contains('is_synced')) {
              cleanRow['is_synced'] = 1;
            }

            // Ensure mandatory 'name' field is never null/empty for product_master
            if (tableName != 'product_master' || (cleanRow['name'] != null && cleanRow['name'].toString().trim().isNotEmpty)) {
              batch.insert(tableName, cleanRow, conflictAlgorithm: sql.ConflictAlgorithm.replace);
            }
          }
        }
        await batch.commit(noResult: true);
      });
      // Adaptive thread yielding to guarantee zero UI lock during active billing
      final yieldMs = DbHelper.instance.isBillingActiveInstance ? 25 : 5;
      await Future.delayed(Duration(milliseconds: yieldMs));
    }
  }

  /// Downloads today's complete snapshot (product master, stock batches, today's sales & purchases)
  /// into local SQLite for 100% complete offline resilience.
  Future<bool> downloadTodayCompleteSnapshot() async {
    final config = ServerConfigService.instance;
    if (config.supabaseUrl.isEmpty || config.supabaseAnonKey.isEmpty) return false;
    if (_syncPaused || _isRecoveryLocked || _cancelRequested) return false;

    try {
      debugPrint("🔄 Starting Automated Daily Data Snapshot Download...");
      final db = await DbHelper.instance.database;

      // 1. Sync Product Master & Stock Batches (Abort immediately if paused)
      final products = await fetchAllRows('product_master');
      if (_syncPaused || _isRecoveryLocked || _cancelRequested) return false;
      await _safeChunkedSnapshotInsert(db, 'product_master', products, setSyncedFlag: true);

      final batches = await fetchAllRows('stock_batches');
      if (_syncPaused || _isRecoveryLocked || _cancelRequested) return false;
      await _safeChunkedSnapshotInsert(db, 'stock_batches', batches, setSyncedFlag: true);

      // 2. Fetch Today's Sales Invoices & Items
      final salesInvoices = await fetchAllRows('sales_invoices');
      if (_syncPaused || _isRecoveryLocked || _cancelRequested) return false;
      await _safeChunkedSnapshotInsert(db, 'sales_invoices', salesInvoices, setSyncedFlag: true);

      final salesItems = await fetchAllRows('sales_items');
      if (_syncPaused || _isRecoveryLocked || _cancelRequested) return false;
      await _safeChunkedSnapshotInsert(db, 'sales_items', salesItems);

      // 3. Fetch Purchase Entries & Items
      final purchaseEntries = await fetchAllRows('purchase_entries');
      if (_syncPaused || _isRecoveryLocked || _cancelRequested) return false;
      await _safeChunkedSnapshotInsert(db, 'purchase_entries', purchaseEntries, setSyncedFlag: true);

      final purchaseItems = await fetchAllRows('purchase_items');
      if (_syncPaused || _isRecoveryLocked || _cancelRequested) return false;
      await _safeChunkedSnapshotInsert(db, 'purchase_items', purchaseItems);

      // Re-derive true stock batch quantities directly from local purchase/sales ledger
      try {
        await recalculateStockFromLedgerDirect(db);
      } catch (recErr) {
        debugPrint("Snapshot stock ledger recalculation note: $recErr");
      }

      debugPrint("✅ Automated Daily Snapshot Download completed successfully.");
      return true;
    } catch (e) {
      debugPrint("Daily Snapshot Download note: $e");
      return false;
    }
  }

  /// Performs a full or incremental synchronization between local SQLite and Supabase REST.
  Future<bool> syncAllPendingData({
    bool forceFull = false,
    bool isExportMode = true,
    bool isManualTransfer = false,
    Set<String>? selectedCategories,
  }) async {
    if (_syncPaused) {
      debugPrint('Sync cycle skipped because sync execution is paused for invoice recovery.');
      return false;
    }

    _isManualTransfer = isManualTransfer || _isManualTransfer;

    if (_isWiping) {
      debugPrint('Sync cycle skipped because database reset/wipe is in progress.');
      return false;
    }

    // Pure Cloud Live Mode Guard: Automatic full database export is disabled.
    // If pending offline records exist in local storage, automatically drain the queue!
    if (ServerConfigService.instance.isPureCloud && !_isManualTransfer) {
      final unsyncedCnt = await getUnsyncedTotalCount();
      if (unsyncedCnt > 0) {
        debugPrint('Pure Cloud Live Mode auto-drain: $unsyncedCnt pending offline record(s) found. Draining queue...');
        _isManualTransfer = true;
      }
    }

    // Auto Sync Disabled Guard: Skip automatic sync cycles when auto-sync is toggled off
    if (!ServerConfigService.instance.autoSyncEnabled && !_isManualTransfer) {
      debugPrint('Skipping automatic cloud sync cycle because Auto Sync is disabled.');
      _isSyncing = false;
      _isManualTransfer = false;
      notifyListeners();
      return true;
    }

    if (!_isReady) {
      _lastSyncError = 'Server Mode is disabled or disconnected.';
      _syncStatusMessage = _lastSyncError;
      notifyListeners();
      return false;
    }

    if (selectedCategories != null) {
      _activeSelectedCategoryIds = selectedCategories;
    }

    // Rule 1: High Priority for Manual Transfers.
    // If a manual transfer is requested while an auto/background sync is running, cancel the background sync immediately!
    if (isManualTransfer && _isSyncing && !_isManualTransfer) {
      debugPrint('Preempting active background auto-sync for higher priority MANUAL transfer...');
      _cancelRequested = true;
      int cancelWait = 0;
      while (_isSyncing && cancelWait < 20) {
        cancelWait++;
        await Future.delayed(const Duration(milliseconds: 100));
      }
      _cancelRequested = false;
    }

    // Quietly ignore automatic background syncs if any sync is already active
    if (!isManualTransfer && _isSyncing) {
      debugPrint('Auto-sync cycle skipped because another sync is in progress.');
      return false;
    }

    if (DbHelper.instance.isBillingActiveInstance && !isManualTransfer) {
      return false;
    }

    // If another sync operation is active, wait briefly for it to complete (bypass wait if continuing manual transfer)
    if (_isSyncing && !(_isManualTransfer && isManualTransfer)) {
      int waitCount = 0;
      while (_isSyncing && waitCount < 15) {
        waitCount++;
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (_isSyncing) {
        _lastSyncError = 'A cloud transfer operation is already in progress. Please wait a moment.';
        notifyListeners();
        return false;
      }
    }

    // Cooldown Guard for auto sync: If not forced and synced within last 10 seconds, check if any dirty records exist first
    if (!forceFull && !isManualTransfer && _lastSyncTime != null && DateTime.now().difference(_lastSyncTime!).inSeconds < 10) {
      final db = await DbHelper.instance.database;
      final unsyncedProds = (await db.rawQuery('SELECT COUNT(*) as cnt FROM product_master WHERE is_synced = 0 OR is_synced IS NULL')).first['cnt'] as int? ?? 0;
      final unsyncedSales = (await db.rawQuery('SELECT COUNT(*) as cnt FROM sales_invoices WHERE is_synced = 0 OR is_synced IS NULL')).first['cnt'] as int? ?? 0;
      final unsyncedPurchases = (await db.rawQuery('SELECT COUNT(*) as cnt FROM purchase_entries WHERE is_synced = 0 OR is_synced IS NULL')).first['cnt'] as int? ?? 0;
      if (unsyncedProds == 0 && unsyncedSales == 0 && unsyncedPurchases == 0) {
        debugPrint('SupabaseSyncService: Cooldown active and 0 unsynced records. Skipping sync cycle.');
        return true;
      }
    }

    // Rule 2: Always display manual transfer monitor UI on screen INSTANTLY on Frame 1
    _isManualTransfer = isManualTransfer;
    _isSyncing = true;
    _cancelRequested = false;
    _syncClient ??= http.Client();
    _syncStartTime = DateTime.now();
    _syncProgress = forceFull ? 0.05 : 0.01;
    _syncStatusMessage = isExportMode ? '5% - Connecting to Cloud Server...' : '5% - Connecting to Cloud Server...';
    notifyListeners(); // Instant UI Switch on button tap!

    try {
      if (isManualTransfer) {
        try {
          SupabaseRealtimeService.instance.disposeAll();
          debugPrint('SupabaseSyncService: Paused Realtime WebSocket listeners during manual high-speed sync.');
        } catch (_) {}
      }

      await initCategoryTracker(isExport: isExportMode, selectedCategories: selectedCategories);
      notifyListeners();

      final config = ServerConfigService.instance;
      final bool isAlive = config.isConnected ? true : await config.testConnection(config.supabaseUrl, config.supabaseAnonKey);
      if (!isAlive || _cancelRequested) {
        _lastSyncError = _cancelRequested
            ? 'Sync Cancelled by User.'
            : (config.lastErrorMessage.isNotEmpty ? config.lastErrorMessage : 'Server offline or unreachable.');
        _syncStatusMessage = _lastSyncError;
        _isSyncing = false;
        _isManualTransfer = false;
        debugPrint('SupabaseSyncService: Server unreachable or sync cancelled. Aborting.');
        notifyListeners();
        return false;
      }

        final db = await DbHelper.instance.database;

        // AUTOMATIC REMOTE WIPE DETECTOR (BYPASSED FOR DATA SAFETY)
        // Automatic local table wipes on startup are disabled to protect local data integrity.
        // Resets must be explicitly initiated via administrative settings button.

        // Process any pending offline cloud deletions first
        await processPendingDeletions();

        bool pulledNew = false;
        if (isExportMode) {
          // Calculate unsynced / pending rows for delta tracking in Export Mode
          if (forceFull) {
            final pCnt = _isCategorySelected('products') ? ((await db.rawQuery('SELECT COUNT(*) as cnt FROM product_master')).first['cnt'] as int? ?? 0) : 0;
            final bCnt = _isCategorySelected('batches') ? ((await db.rawQuery('SELECT COUNT(*) as cnt FROM stock_batches')).first['cnt'] as int? ?? 0) : 0;
            final patCnt = _isCategorySelected('patients') ? ((await db.rawQuery('SELECT COUNT(*) as cnt FROM patients')).first['cnt'] as int? ?? 0) : 0;
            final salCnt = _isCategorySelected('sales') ? ((await db.rawQuery('SELECT COUNT(*) as cnt FROM sales_invoices WHERE is_deleted = 0')).first['cnt'] as int? ?? 0) : 0;
            final purCnt = _isCategorySelected('purchases') ? ((await db.rawQuery('SELECT COUNT(*) as cnt FROM purchase_entries WHERE is_deleted = 0')).first['cnt'] as int? ?? 0) : 0;
            _totalRowsToSync = pCnt + bCnt + patCnt + salCnt + purCnt;
          } else {
            final pCnt = _isCategorySelected('products') ? ((await db.rawQuery('SELECT COUNT(*) as cnt FROM product_master WHERE is_synced = 0 OR is_synced IS NULL')).first['cnt'] as int? ?? 0) : 0;
            final bCnt = _isCategorySelected('batches') ? ((await db.rawQuery('SELECT COUNT(*) as cnt FROM stock_batches WHERE is_synced = 0 OR is_synced IS NULL')).first['cnt'] as int? ?? 0) : 0;
            final patCnt = _isCategorySelected('patients') ? ((await db.rawQuery('SELECT COUNT(*) as cnt FROM patients WHERE is_synced = 0 OR is_synced IS NULL')).first['cnt'] as int? ?? 0) : 0;
            final salCnt = _isCategorySelected('sales') ? ((await db.rawQuery('SELECT COUNT(*) as cnt FROM sales_invoices WHERE is_synced = 0 OR is_synced IS NULL')).first['cnt'] as int? ?? 0) : 0;
            final purCnt = _isCategorySelected('purchases') ? ((await db.rawQuery('SELECT COUNT(*) as cnt FROM purchase_entries WHERE is_synced = 0 OR is_synced IS NULL')).first['cnt'] as int? ?? 0) : 0;
            _totalRowsToSync = pCnt + bCnt + patCnt + salCnt + purCnt;
          }

          if (_totalRowsToSync <= 0) _totalRowsToSync = 1;
          _processedRowsCount = 0;

          final bool pushForceFull = forceFull;

          // 1. Sync Categories & Master Tables
          if (_isCategorySelected('products') || _isCategorySelected('suppliers_doctors')) {
            if (_cancelRequested) return false;
            await _syncMasterTables();
          }

          // 2. Sync Product Master
          if (_isCategorySelected('products')) {
            if (_cancelRequested) return false;
            await _syncProducts(forceFull: pushForceFull);
          }

          // 3. Sync Stock Batches & Quantities
          if (_isCategorySelected('batches')) {
            if (_cancelRequested) return false;
            await _syncStockBatches(forceFull: pushForceFull);
          }

          // 4. Sync Customers / Patients
          if (_isCategorySelected('patients')) {
            if (_cancelRequested) return false;
            await _syncCustomers();
          }

          // 5. Sync Sales Invoices & Returns
          if (_isCategorySelected('sales')) {
            if (_cancelRequested) return false;
            await _syncSalesInvoices(forceFull: pushForceFull);
          }
          if (_isCategorySelected('sales_returns')) {
            if (_cancelRequested) return false;
            await _syncSalesReturns();
          }

          // 6. Sync Purchase Entries, Returns & Adjustments
          if (_isCategorySelected('purchases')) {
            if (_cancelRequested) return false;
            await _syncPurchaseEntries(forceFull: pushForceFull);
          }
          if (_isCategorySelected('purchase_returns')) {
            if (_cancelRequested) return false;
            await _syncPurchaseReturns();
          }
          if (_isCategorySelected('prescriptions_adjustments')) {
            if (_cancelRequested) return false;
            await _syncStockAdjustments();
            if (_cancelRequested) return false;
            await _syncStockWriteOffs();
          }
          if (_isCategorySelected('accounts_daybook')) {
            if (_cancelRequested) return false;
            await _syncFinancialVouchers();
          }
          if (_isCategorySelected('prescriptions_adjustments')) {
            if (_cancelRequested) return false;
            await _syncPrescriptions();
          }

          if (_cancelRequested) return false;
          await _syncStaffUsers();
          await _syncPurchaseOrders();
          await _syncProductMappings();
          await _syncInvoiceEditHistory();
          await _syncStockLedger();

          if (!forceFull) {
            if (_cancelRequested) return false;
            pulledNew = await _pullRemoteData(forceFull: false);
          }
        } else {
          // IMPORT MODE (Cloud ──► Local Database)
          if (_cancelRequested) return false;
          _lastSyncError = '';
          pulledNew = await _pullRemoteData(forceFull: forceFull);
        }
        if (_cancelRequested) return false;

      if (pulledNew) {
        try {
          AppNotificationService.instance.addNotification(
            title: "Cloud Sync Updated",
            message: "⚡ New transactions & inventory synced from cloud server.",
            type: NotificationType.backup,
            actionRoute: "sales",
          );
        } catch (_) {}
      }

      _lastSyncTime = DateTime.now();
      _syncProgress = 1.0;
      for (var cat in _categorySyncStatuses) {
        cat.state = CategorySyncState.completed;
        if (cat.totalCount > 0) {
          cat.processedCount = cat.totalCount;
        }
      }

      // If all selected core categories completed 100%, clear any non-critical auxiliary table warnings
      final int totalAttempted = _categorySyncStatuses.fold(0, (sum, c) => sum + c.totalCount);
      final int totalProcessed = _categorySyncStatuses.fold(0, (sum, c) => sum + c.processedCount);
      if (totalAttempted > 0 && totalProcessed >= totalAttempted) {
        _lastSyncError = '';
      }
      if (forceFull) {
        _isInitialSyncCompleted = true;
        _syncStatusMessage = '100% - Initial Cloud Import Completed!';
      } else {
        _syncStatusMessage = '100% - Cloud Sync Completed!';
      }

      notifyListeners();

      // Show 100% Completed status briefly on screen, then auto-close the monitor card!
      await Future.delayed(const Duration(seconds: 2));

      _isSyncing = false;
      _isManualTransfer = false;
      notifyListeners();

      unawaited(checkAndPruneOldCloudData());

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyLastSyncTimestamp, _lastSyncTime!.toIso8601String());
        if (forceFull) {
          await prefs.setBool(_keyInitialSyncCompleted, true);
        }
      } catch (e) {
        debugPrint('Error persisting last sync state: $e');
      }

      unawaited(pruneCloudBlankDraftInvoices());

      debugPrint('SupabaseSyncService: Sync completed successfully (forceFull: $forceFull).');
      return true;
    } catch (e) {
      debugPrint('SupabaseSyncService error: $e');
      _syncStatusMessage = 'Sync failed: $e';
      return false;
    } finally {
      _isSyncing = false;
      _isManualTransfer = false;
      notifyListeners();
      try {
        await SupabaseRealtimeService.instance.initialize();
        SupabaseRealtimeService.instance.startAllRealtimeListeners();
      } catch (_) {}
    }
  }

  Future<T> _runWithDbRetry<T>(Future<T> Function() action, {int maxAttempts = 25}) async {
    int attempt = 0;
    while (attempt < maxAttempts) {
      attempt++;
      try {
        return await action();
      } catch (e) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('database is locked') || errStr.contains('code 5') || errStr.contains('sqliteexception(5)')) {
          if (attempt >= maxAttempts) rethrow;
          final delayMs = (150 * attempt).clamp(150, 800);
          await Future.delayed(Duration(milliseconds: delayMs));
        } else {
          rethrow;
        }
      }
    }
    return await action();
  }

  /// Force pushes local SQLite records to cloud for selected categories by resetting synced flags and running full sync.
  Future<bool> forcePushAllData({Set<String>? selectedCategories}) async {
    try {
      _lastSyncError = '';
      _isManualTransfer = true;
      _isSyncing = true;
      _syncProgress = 0.02;
      _syncStatusMessage = '2% - Preparing Database Records for Cloud Push...';

      if (selectedCategories != null) {
        _activeSelectedCategoryIds = selectedCategories;
      }

      // 1. Immediately initialize category trackers so exact row counts render on UI on Frame 1
      await initCategoryTracker(isExport: true, selectedCategories: selectedCategories);
      notifyListeners(); // Instant UI Response with populated trackers!

      final db = await DbHelper.instance.database;

      final Map<String, List<String>> categoryTableMap = {
        'products': ['product_master', 'categories', 'manufacturers', 'racks', 'generics'],
        'batches': ['stock_batches'],
        'sales': ['sales_invoices', 'sales_items'],
        'purchases': ['purchase_entries', 'purchase_items'],
        'accounts_daybook': ['accounts', 'supplier_payments', 'patient_payments', 'supplier_credit_notes'],
        'sales_returns': ['sales_return_invoices', 'sales_return_items'],
        'purchase_returns': ['purchase_return_entries', 'purchase_return_items'],
        'patients': ['patients'],
        'suppliers_doctors': ['suppliers', 'doctors', 'staff'],
        'prescriptions_adjustments': ['prescriptions', 'stock_adjustments', 'stock_adjustment_items', 'stock_write_offs'],
      };

      List<String> targetTables = [];
      if (selectedCategories != null && selectedCategories.isNotEmpty) {
        for (var cat in selectedCategories) {
          if (categoryTableMap.containsKey(cat)) {
            targetTables.addAll(categoryTableMap[cat]!);
          }
        }
      } else {
        targetTables = categoryTableMap.values.expand((t) => t).toList();
      }

      // 2. Delegate directly to syncAllPendingData (forceFull reads 100% of records instantly without requiring disk writes)
      return await syncAllPendingData(forceFull: true, isExportMode: true, isManualTransfer: true, selectedCategories: selectedCategories);
    } catch (e) {
      _lastSyncError = 'Push Exception: $e';
      debugPrint('forcePushAllData error: $e');
      _isSyncing = false;
      _isManualTransfer = false;
      notifyListeners();
      return false;
    }
  }

  /// Wipes remote cloud records for a specific category (e.g. 'products' / product_master)
  /// and immediately performs a full fresh upload of local PC data to Cloud.
  Future<bool> purgeAndReSyncCategory(String categoryKey) async {
    final config = ServerConfigService.instance;
    if (!config.isConnected || config.supabaseUrl.isEmpty || config.supabaseAnonKey.isEmpty) {
      _lastSyncError = 'Server is disconnected or missing credentials.';
      notifyListeners();
      return false;
    }

    _isManualTransfer = true;
    _isSyncing = true;
    _syncProgress = 0.02;
    _syncStatusMessage = '2% - Cleaning remote cloud data for $categoryKey...';
    notifyListeners();

    try {
      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
      final headers = Map<String, String>.from(config.restHeaders);

      List<String> targetEndpoints = [];
      if (categoryKey == 'products' || categoryKey == 'product_master') {
        targetEndpoints = ['product_master'];
      } else if (categoryKey == 'batches' || categoryKey == 'stock_batches') {
        targetEndpoints = ['stock_batches'];
      } else if (categoryKey == 'patients') {
        targetEndpoints = ['patients'];
      } else if (categoryKey == 'sales' || categoryKey == 'sales_invoices') {
        targetEndpoints = ['sales_items', 'sales_invoices'];
      } else if (categoryKey == 'purchases' || categoryKey == 'purchase_entries') {
        targetEndpoints = ['purchase_items', 'purchase_entries'];
      } else if (categoryKey == 'sales_returns') {
        targetEndpoints = ['sales_return_items', 'sales_return_invoices'];
      } else if (categoryKey == 'purchase_returns') {
        targetEndpoints = ['purchase_return_items', 'purchase_return_entries'];
      }

      for (final endpoint in targetEndpoints) {
        final keyCol = endpoint.contains('items') ? (endpoint == 'sales_items' || endpoint == 'sales_return_items' ? 'invoice_no' : 'entry_no') : 'entry_no';
        final deleteUri = Uri.parse('$cleanUrl/rest/v1/$endpoint?$keyCol=not.is.null');
        debugPrint('⚡ purgeAndReSyncCategory: Purging remote $endpoint at $deleteUri');
        final res = await http.delete(deleteUri, headers: headers).timeout(const Duration(seconds: 15));
        debugPrint('⚡ purgeAndReSyncCategory: Response status ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('⚡ purgeAndReSyncCategory warning during remote purge: $e');
    }

    final String selCat = (categoryKey == 'product_master') ? 'products' : (categoryKey == 'stock_batches' ? 'batches' : categoryKey);
    return await forcePushAllData(selectedCategories: {selCat});
  }

  static String _sanitizeEntryNo(dynamic raw) {
    if (raw == null) return '';
    final str = raw.toString().trim();
    if (str.isEmpty) return '';
    if (RegExp(r'^\d{4}-\d{2}_').hasMatch(str)) {
      return str.replaceFirst(RegExp(r'^\d{4}-\d{2}_'), '').trim();
    }
    return str;
  }

  static String _cleanString(dynamic val, [String defaultValue = '']) {
    if (val == null) return defaultValue;
    final str = val.toString().replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ').trim();
    return str.isEmpty ? defaultValue : str;
  }

  static String _calculateFY(DateTime dt) {
    int startYr = dt.year;
    if (dt.month < 4) startYr -= 1;
    return "$startYr-${(startYr + 1).toString().substring(2)}";
  }

  static double _toDouble(dynamic val, [double defaultValue = 0.0]) {
    if (val == null) return defaultValue;
    double d = defaultValue;
    if (val is num) {
      d = val.toDouble();
    } else {
      d = double.tryParse(val.toString()) ?? defaultValue;
    }
    if (!d.isFinite) return defaultValue;
    return d;
  }

  static double _parseGstPercent(Map<String, dynamic> item, [double defaultValue = 12.0]) {
    for (var key in ['gst_percent', 'gst_rate', 'tax_percent', 'tax_rate', 'gst_perc', 'gst_per', 'gst_pct', 'vat_percent', 'vat_rate', 'gst', 'tax']) {
      if (item.containsKey(key) && item[key] != null) {
        double val = _toDouble(item[key], -1.0);
        if (val >= 0.0) return val;
      }
    }
    return defaultValue;
  }

  static double _parseDiscPercent(Map<String, dynamic> item, [double defaultValue = 0.0]) {
    for (var key in ['disc_percent', 'discount_percent', 's_disc_percent', 'disc_perc', 'disc_per', 'disc_pct', 'dis_percent', 'dis_per', 'dis_pct', 's_disc', 'trade_disc', 'sch_disc', 'discount_pct', 'discount']) {
      if (item.containsKey(key) && item[key] != null) {
        double val = _toDouble(item[key], -1.0);
        if (val >= 0.0) return val;
      }
    }
    return defaultValue;
  }

  static int _toInt(dynamic val, [int defaultValue = 0]) {
    if (val == null) return defaultValue;
    if (val is num) return val.toInt();
    return int.tryParse(val.toString()) ?? defaultValue;
  }

  /// Pushes a single product to Supabase product_master REST table.
  Future<void> pushProduct(Map<String, dynamic> productData) async {
    if (!_isReady) return;
    try {
      final config = ServerConfigService.instance;
      final branchId = config.storeBranchId;
      final nameStr = productData['product_name']?.toString() ?? productData['name']?.toString() ?? '';
      final gstVal = _toDouble(productData['gst_rate'] ?? productData['gst_percent'], 12.0);
      final priceVal = _toDouble(productData['selling_price'] ?? productData['sale_rate'], 0.0);
      final mrpVal = _toDouble(productData['mrp'], 0.0);

      final payload = {
        'id': productData['id']?.toString() ?? '',
        'product_name': nameStr,
        'generic_name': productData['generic_name']?.toString() ?? '',
        'category_id': productData['category_id']?.toString() ?? '',
        'sub_category_id': productData['sub_category_id']?.toString() ?? '',
        'manufacturer_id': productData['manufacturer_id']?.toString() ?? '',
        'rack_id': productData['rack_id']?.toString() ?? '',
        'hsn_code': productData['hsn_code']?.toString() ?? '',
        'gst_rate': gstVal,
        's_disc_percent': _toDouble(productData['s_disc_percent']),
        'schedule': productData['schedule']?.toString() ?? 'H',
        'mrp': mrpVal,
        'purchase_rate': _toDouble(productData['purchase_rate']),
        'selling_price': priceVal,
        'reorder_level': _toInt(productData['reorder_level'], 10),
        'max_level': _toInt(productData['max_level'], 100),
        'unit': productData['unit']?.toString() ?? 'Strip',
        'packing': _toInt(productData['packing'], 10),
        'patent': productData['patent']?.toString() ?? '',
        'barcode': productData['barcode']?.toString() ?? '',
        'is_controlled': _toInt(productData['is_controlled'], 0),
        'is_banned': _toInt(productData['is_banned'], 0),
        'is_nrx': _toInt(productData['is_nrx'], 0),
        'is_active': _toInt(productData['is_active'], 1),
        'is_disc_locked': _toInt(productData['is_disc_locked'], 0),
        'preferred_wholesale': productData['preferred_wholesale']?.toString() ?? '',
        'lead_time': _toInt(productData['lead_time'], 2),
        'branch_id': branchId,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final uri = Uri.parse('${config.supabaseUrl}/rest/v1/product_master');
      if (payload['id'] != null && payload['id'].toString().isNotEmpty) {
        SupabaseRealtimeService.instance.markKeyRecentlyPushed(payload['id'].toString());
      }
      final res = await _safePostSingle(
        uri,
        headers: config.restHeaders,
        payload: payload,
        tableName: 'product_master',
      );
      if (res.statusCode < 400) {
        final db = await DbHelper.instance.database;
        await db.rawUpdate('UPDATE product_master SET is_synced = 1 WHERE id = ?', [payload['id']]);
      }
    } catch (e, stack) {
      debugPrint('Failed to push product to Supabase: $e');
      RemoteLoggerService.instance.logError(e, stackTrace: stack, library: 'SupabaseSyncService', context: 'pushProduct');
    }
  }

  /// Prunes empty zero-item draft invoices on Supabase Cloud
  Future<void> pruneCloudBlankDraftInvoices() async {
    if (!_isReady) return;
    try {
      final config = ServerConfigService.instance;
      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
      final uri = Uri.parse('$cleanUrl/rest/v1/sales_invoices?net_amount=eq.0&subtotal=eq.0&is_deleted=eq.0');
      final headers = {
        'apikey': config.supabaseAnonKey.trim(),
        'Authorization': 'Bearer ${config.supabaseAnonKey.trim()}',
      };
      final res = await http.delete(uri, headers: headers).timeout(const Duration(seconds: 6));
      if (res.statusCode < 400) {
        debugPrint('Cloud Sync: Successfully pruned blank draft invoices from Supabase.');
      }
    } catch (e) {
      debugPrint('Error pruning cloud blank draft invoices: $e');
    }
  }

  /// Pushes a stock batch update to Supabase stock_batches REST table.
  Future<void> pushStockBatch(Map<String, dynamic> batchData) async {
    if (!_isReady) return;
    try {
      final config = ServerConfigService.instance;
      final branchId = config.storeBranchId;
      final sellRate = _toDouble(batchData['selling_rate'] ?? batchData['sale_rate'], 0.0);
      final qty = _toInt(batchData['current_quantity'] ?? batchData['current_stock'], 0);
      final prodId = batchData['product_id']?.toString() ?? '';
      final batchNo = batchData['batch_number']?.toString() ?? '';
      final expiryStr = batchData['expiry_date']?.toString() ?? '';
      if (prodId.isEmpty || batchNo.isEmpty) return;

      final cleanKeyStr = '${prodId}_${batchNo}_$expiryStr'.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

      final payload = {
        'id': cleanKeyStr,
        'product_id': prodId,
        'batch_number': batchNo,
        'expiry_date': expiryStr,
        'mfg_date': batchData['mfg_date']?.toString() ?? '',
        'purchase_rate': _toDouble(batchData['purchase_rate'], 0.0),
        'landing_cost': _toDouble(batchData['landing_cost'], _toDouble(batchData['purchase_rate'])),
        'mrp': _toDouble(batchData['mrp'], 0.0),
        'selling_rate': sellRate,
        'current_quantity': qty,
        's_disc_percent': _toDouble(batchData['s_disc_percent']),
        'gst_percent': _toDouble(batchData['gst_percent'], 12.0),
        'rack': batchData['rack']?.toString() ?? '',
        'supplier_name': batchData['supplier_name']?.toString() ?? '',
        'packing': _toInt(batchData['packing'], 1),
        'is_active': _toInt(batchData['is_active'], 1),
        'financial_year': batchData['financial_year']?.toString() ?? '',
        'branch_id': branchId,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final uri = Uri.parse('${config.supabaseUrl}/rest/v1/stock_batches');
      SupabaseRealtimeService.instance.markKeyRecentlyPushed(prodId);
      SupabaseRealtimeService.instance.markKeyRecentlyPushed("${prodId}_$batchNo");

      var res = await _safePostSingle(
        uri,
        headers: config.restHeaders,
        payload: payload,
        tableName: 'stock_batches',
      );

      // Auto-heal foreign key violation if parent product is missing in cloud product_master
      if (res.statusCode >= 400 && res.body.contains('stock_batches_product_id_fkey')) {
        final db = await DbHelper.instance.database;
        final prodRows = await db.query('product_master', where: 'id = ?', whereArgs: [prodId], limit: 1);
        if (prodRows.isNotEmpty) {
          await pushProduct(prodRows.first);
          res = await _safePostSingle(
            uri,
            headers: config.restHeaders,
            payload: payload,
            tableName: 'stock_batches',
          );
        }
      }

      if (res.statusCode < 400) {
        final db = await DbHelper.instance.database;
        await db.rawUpdate('UPDATE stock_batches SET is_synced = 1 WHERE product_id = ? AND batch_number = ?', [prodId, batchNo]);
      }
    } catch (e, stack) {
      debugPrint('Failed to push batch to Supabase: $e');
      RemoteLoggerService.instance.logError(e, stackTrace: stack, library: 'SupabaseSyncService', context: 'pushStockBatch');
    }
  }

  /// Pushes a customer / patient record to Supabase patients REST table.
  Future<void> pushCustomer(Map<String, dynamic> customerData) async {
    if (!_isReady) return;
    try {
      final config = ServerConfigService.instance;
      final branchId = config.storeBranchId;
      final payload = Map<String, dynamic>.from(customerData);
      payload['branch_id'] = branchId;

      final uri = Uri.parse('${config.supabaseUrl}/rest/v1/patients');
      await _safePostSingle(
        uri,
        headers: config.restHeaders,
        payload: payload,
        tableName: 'patients',
      );
    } catch (e, stack) {
      debugPrint('Failed to push customer to Supabase: $e');
      RemoteLoggerService.instance.logError(e, stackTrace: stack, library: 'SupabaseSyncService', context: 'pushCustomer');
    }
  }

  /// Pushes a sales invoice and its line items to Supabase using fn_save_sale_invoice_atomic RPC.
  /// Returns [true] only if the complete atomic RPC transaction succeeds.
  /// Returns [false] on any error, timeout, or terminal/branch collision attempt.
  Future<bool> pushSalesInvoice(
      Map<String, dynamic> invoice, List<Map<String, dynamic>> items) async {
    if (_isRecoveryLocked || _syncPaused) {
      debugPrint('pushSalesInvoice skipped due to Active Invoice Recovery Lock.');
      return false;
    }

    if (!_isReady) return false;

    final rawEntryNo = invoice['entry_no']?.toString() ?? invoice['invoice_no']?.toString() ?? '';
    final entryNo = _sanitizeEntryNo(rawEntryNo);

    _activePushSalesInvoiceCount++;
    try {
      final grandTotal = _toDouble(invoice['grand_total'] ?? invoice['net_amount'] ?? invoice['total_amount']);
      final isDel = _toInt(invoice['is_deleted'], 0);

      if (entryNo.isEmpty) {
        debugPrint('SupabaseSyncService: pushSalesInvoice skipped - empty entry_no.');
        return false;
      }

      if (items.isEmpty && grandTotal <= 0 && isDel == 0) {
        debugPrint('SupabaseSyncService: Marking blank draft bill ($entryNo) as synced.');
        final db = await DbHelper.instance.database;
        await db.rawUpdate('UPDATE sales_invoices SET is_synced = 1, is_cloud_synced = 1 WHERE entry_no = ? OR invoice_no = ?', [entryNo, entryNo]);
        return true;
      }

      final config = ServerConfigService.instance;
      final branchId = config.storeBranchId;
      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);

      SupabaseRealtimeService.instance.markKeyRecentlyPushed(entryNo);

      final dateStr = invoice['date']?.toString() ?? DateTime.now().toIso8601String();
      DateTime parsedDt;
      try {
        parsedDt = DateTime.parse(dateStr);
      } catch (_) {
        parsedDt = DateTime.tryParse(dateStr.replaceAll('/', '-')) ?? DateTime.now();
      }
      final computedFy = _calculateFY(parsedDt);
      final fyStr = (invoice['financial_year'] != null && invoice['financial_year'].toString().isNotEmpty)
          ? invoice['financial_year'].toString()
          : computedFy;

      final patientName = (invoice['patient']?.toString() ?? '').isNotEmpty
          ? invoice['patient']?.toString()
          : ((invoice['customer_name']?.toString() ?? '').isNotEmpty
              ? invoice['customer_name']?.toString()
              : (invoice['customer_acc']?.toString() ?? 'Cash'));

      final terminalId = (invoice['terminal_id']?.toString().trim().isNotEmpty == true)
          ? invoice['terminal_id'].toString().trim()
          : config.terminalId;

      final custAcc = invoice['customer_acc']?.toString() ?? invoice['payment_mode']?.toString() ?? 'Cash';
      final mobPhone = invoice['mobile']?.toString() ?? invoice['customer_phone']?.toString() ?? '';
      final subTot = _toDouble(invoice['sub_total'] ?? invoice['subtotal']);
      final discAmt = _toDouble(invoice['discount'] ?? invoice['discount_amount'] ?? invoice['disc_amt']);
      final taxAmt = _toDouble(invoice['tax'] ?? invoice['tax_amount']);
      final netAmt = _toDouble(invoice['grand_total'] ?? invoice['net_amount'] ?? invoice['total_amount']);

      final invoicePayload = {
        'entry_no': entryNo,
        'invoice_no': invoice['invoice_no']?.toString() ?? entryNo,
        'financial_year': fyStr,
        'date': dateStr,
        'customer_acc': custAcc,
        'customer_name': patientName,
        'patient': invoice['patient']?.toString() ?? patientName,
        'customer_phone': mobPhone,
        'mobile': mobPhone,
        'doctor': invoice['doctor']?.toString() ?? '',
        'doctor_reg_no': invoice['doctor_reg_no']?.toString() ?? '',
        'done_by': invoice['done_by']?.toString() ?? 'Cashier',
        'terminal_id': terminalId,
        'shift_id': invoice['shift_id']?.toString() ?? 'SHIFT-01',
        'patient_age': _toInt(invoice['patient_age'], 0),
        'patient_gender': invoice['patient_gender']?.toString() ?? '',
        'patient_address': invoice['patient_address']?.toString() ?? '',
        'gstin_number': invoice['gstin_number']?.toString() ?? '',
        'place_of_supply': invoice['place_of_supply']?.toString() ?? '',
        'subtotal': subTot,
        'sub_total': subTot,
        'discount_amount': discAmt,
        'discount': discAmt,
        'discount_percent': _toDouble(invoice['discount_percent'] ?? invoice['disc_percent']),
        'additional_discount': _toDouble(invoice['additional_discount']),
        'other_charge': _toDouble(invoice['other_charge']),
        'tax_amount': taxAmt,
        'tax': taxAmt,
        'round_off': _toDouble(invoice['round_off']),
        'net_amount': netAmt,
        'grand_total': netAmt,
        'total_amount': netAmt,
        'rcvd_amt': _toDouble(invoice['rcvd_amt']),
        'payment_mode': invoice['payment_mode']?.toString() ?? 'CASH',
        'payment_remarks': invoice['payment_remarks']?.toString() ?? '',
        'secondary_acc': invoice['secondary_acc']?.toString() ?? '',
        'secondary_amt': _toDouble(invoice['secondary_amt']),
        'is_deleted': isDel,
        'is_paid': _toInt(invoice['is_paid'], 1),
        'tax_type': invoice['tax_type']?.toString() ?? 'Non Gst',
        'agent': invoice['agent']?.toString() ?? 'Admin',
        'sales_return_amt': _toDouble(invoice['sales_return_amt']),
        'order_type': _toInt(invoice['order_type'], 0),
        'branch_id': branchId,
      };

      final itemPayloads = items.map((it) {
        final prod = (it['product'] is Map) ? (it['product'] as Map<String, dynamic>) : <String, dynamic>{};
        final pId = it['product_id']?.toString() ?? prod['id']?.toString() ?? it['id']?.toString() ?? '';
        final pName = it['product_name']?.toString() ?? prod['name']?.toString() ?? '';
        final batchNum = it['batch_number']?.toString() ?? it['batch']?.toString() ?? prod['batch_number']?.toString() ?? prod['batch']?.toString() ?? '';
        final expDate = it['expiry_date']?.toString() ?? it['expiry']?.toString() ?? prod['expiry_date']?.toString() ?? prod['expiry']?.toString() ?? '';
        final quantity = _toInt(it['quantity'] ?? it['qty'], 1);
        final fQuantity = _toInt(it['f_qty'], 0);
        final packVal = _toInt(it['packing'] ?? it['packin'], 1);
        final mrpVal = _toDouble(it['mrp']);
        final sRateVal = _toDouble(it['s_rate'] ?? it['unit_price'] ?? it['sale_rate']);
        final pRateVal = _toDouble(it['purchase_rate'] ?? it['p_rate'] ?? prod['purchase_rate'] ?? prod['purchase_price']);
        final lCostVal = _toDouble(it['landing_cost'] ?? it['l_cost'] ?? pRateVal);
        final taxSpVal = _toDouble(it['taxable_sp'] ?? sRateVal);
        final discPct = _toDouble(it['disc_percent'] ?? it['discPercent']);
        final discAmtVal = _toDouble(it['disc_amt'] ?? it['discAmt']);
        final gstPct = _toDouble(it['gst_percent'] ?? it['tax_percent'] ?? 12.0);
        final gstAmtVal = _toDouble(it['gst_amt'] ?? it['tax_amount']);
        final totalVal = _toDouble(it['total_amount'] ?? it['total'] ?? it['net_amount']);

        return {
          'invoice_no': entryNo,
          'product_id': pId,
          'product_name': pName,
          'extra': it['extra']?.toString() ?? '',
          'batch_number': batchNum,
          'expiry_date': expDate,
          'quantity': quantity,
          'qty': quantity,
          'f_qty': fQuantity,
          'hsn_code': it['hsn_code']?.toString() ?? prod['hsn_code']?.toString() ?? '',
          'schedule': it['schedule']?.toString() ?? prod['schedule']?.toString() ?? 'H',
          'packing': packVal,
          'mrp': mrpVal,
          'purchase_rate': pRateVal,
          'landing_cost': lCostVal,
          'taxable_sp': taxSpVal,
          'unit_price': sRateVal,
          's_rate': sRateVal,
          'disc_percent': discPct,
          'disc_amt': discAmtVal,
          'gst_percent': gstPct,
          'gst_amt': gstAmtVal,
          'cgst_amt': _toDouble(it['cgst_amt'], gstAmtVal / 2),
          'sgst_amt': _toDouble(it['sgst_amt'], gstAmtVal / 2),
          'igst_amt': _toDouble(it['igst_amt']),
          'total_amount': totalVal,
          'net_amount': totalVal,
          'grand_total': totalVal,
          'profit': _toDouble(it['profit']),
          'supplier_name': it['supplier_name']?.toString() ?? '',
          'rack': it['rack']?.toString() ?? prod['rack']?.toString() ?? '',
          'branch_id': branchId,
          'terminal_id': terminalId,
        };
      }).toList();

      final rpcUri = Uri.parse('$cleanUrl/rest/v1/rpc/fn_save_sale_invoice_atomic');
      final rpcPayload = {
        'p_invoice': invoicePayload,
        'p_items': itemPayloads,
      };

      final response = await http.post(
        rpcUri,
        headers: config.restHeaders,
        body: jsonEncode(rpcPayload),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final resMap = jsonDecode(response.body);
        if (resMap is Map && resMap['success'] == true) {
          final db = await DbHelper.instance.database;
          await db.rawUpdate('UPDATE sales_invoices SET is_synced = 1, is_cloud_synced = 1 WHERE entry_no = ? OR invoice_no = ?', [entryNo, entryNo]);
          await db.rawUpdate('UPDATE sales_items SET is_synced = 1, is_cloud_synced = 1 WHERE invoice_no = ?', [entryNo]);
          AppLogger.instance.supabase("Cloud Sync: Invoice $entryNo and items saved atomically via RPC.");
          notifyListeners();
          return true;
        }
      }

      // Fallback: Direct REST Table Insertion if RPC is unavailable/404
      return await _pushSaleInvoiceRestFallback(
        entryNo: entryNo,
        invoicePayload: invoicePayload,
        itemPayloads: itemPayloads,
        config: config,
        cleanUrl: cleanUrl,
      );
    } catch (e, stack) {
      AppLogger.instance.error('SUPABASE', "Cloud Sync Exception for $entryNo", error: e, stackTrace: stack);
      RemoteLoggerService.instance.logError(e, stackTrace: stack, library: 'SupabaseSyncService', context: 'pushSalesInvoice');
      return false;
    } finally {
      _activePushSalesInvoiceCount--;
    }
  }

  /// REST fallback: pushes sales invoice header and line items to direct PostgREST tables.
  /// Verifies that BOTH the invoice header and line items succeed before marking local records as synced.
  Future<bool> _pushSaleInvoiceRestFallback({
    required String entryNo,
    required Map<String, dynamic> invoicePayload,
    required List<Map<String, dynamic>> itemPayloads,
    required ServerConfigService config,
    required String cleanUrl,
  }) async {
    final invUri = Uri.parse('$cleanUrl/rest/v1/sales_invoices?on_conflict=entry_no,terminal_id');
    final invRes = await http.post(
      invUri,
      headers: config.restHeaders,
      body: jsonEncode(invoicePayload),
    ).timeout(const Duration(seconds: 8));

    if (invRes.statusCode < 200 || invRes.statusCode >= 300) {
      AppLogger.instance.error('SUPABASE', "Cloud Sync HTTP ${invRes.statusCode} for $entryNo", details: invRes.body);
      return false;
    }

    if (itemPayloads.isNotEmpty) {
      final delUri = Uri.parse('$cleanUrl/rest/v1/sales_items?invoice_no=eq.${Uri.encodeComponent(entryNo)}');
      await http.delete(delUri, headers: config.restHeaders).timeout(const Duration(seconds: 2)).catchError((_) => http.Response('', 500));

      final itemsUri = Uri.parse('$cleanUrl/rest/v1/sales_items');
      final itemsRes = await http.post(
        itemsUri,
        headers: config.restHeaders,
        body: jsonEncode(itemPayloads),
      ).timeout(const Duration(seconds: 8));

      if (itemsRes.statusCode < 200 || itemsRes.statusCode >= 300) {
        AppLogger.instance.error(
          'SUPABASE',
          'Failed to sync items for invoice $entryNo (HTTP ${itemsRes.statusCode}); leaving dirty for retry.',
          details: itemsRes.body,
        );
        return false;
      }
    }

    final db = await DbHelper.instance.database;
    await db.rawUpdate('UPDATE sales_invoices SET is_synced = 1, is_cloud_synced = 1 WHERE entry_no = ? OR invoice_no = ?', [entryNo, entryNo]);
    await db.rawUpdate('UPDATE sales_items SET is_synced = 1, is_cloud_synced = 1 WHERE invoice_no = ?', [entryNo]);
    AppLogger.instance.supabase("Cloud Sync (Direct REST Fallback): Invoice $entryNo saved successfully.");
    notifyListeners();
    return true;
  }

  /// Pushes a purchase entry and its line items to Supabase REST endpoints.
  /// Returns [true] only if verified server confirmation succeeds for both header and line items.
  Future<bool> pushPurchaseEntry(
      Map<String, dynamic> purchase, List<Map<String, dynamic>> items) async {
    if (!_isReady) return false;
    try {
      final config = ServerConfigService.instance;
      final branchId = config.storeBranchId;
      final rawEntryNoVal = purchase['entry_no']?.toString() ?? '';
      final entryNoVal = _sanitizeEntryNo(rawEntryNoVal);
      if (entryNoVal.isEmpty) {
        debugPrint('SupabaseSyncService: pushPurchaseEntry skipped - empty entry_no.');
        return false;
      }
      SupabaseRealtimeService.instance.markKeyRecentlyPushed(entryNoVal);
      final purchasePayload = {
        'entry_no': entryNoVal,
        'date': purchase['date']?.toString() ?? '',
        'supplier_name': purchase['supplier_name']?.toString() ?? '',
        'sup_inv_no': cleanInvoiceNo(purchase['sup_inv_no']?.toString() ?? entryNoVal),
        'sup_inv_date': purchase['sup_inv_date']?.toString() ?? purchase['date']?.toString() ?? '',
        'done_by': purchase['done_by']?.toString() ?? '',
        'subtotal': _toDouble(purchase['subtotal'] ?? purchase['sub_total']),
        'sub_total': _toDouble(purchase['subtotal'] ?? purchase['sub_total']),
        'discount': _toDouble(purchase['discount']),
        'discount_amount': _toDouble(purchase['discount']),
        'other_charge': _toDouble(purchase['other_charge']),
        'round_off': _toDouble(purchase['round_off']),
        'grand_total': _toDouble(purchase['grand_total'] ?? purchase['inv_total']),
        'net_amount': _toDouble(purchase['grand_total'] ?? purchase['inv_total']),
        'inv_total': _toDouble(purchase['inv_total'] ?? purchase['grand_total'] ?? purchase['total_amount']),
        'total_amount': _toDouble(purchase['total_amount'] ?? purchase['inv_total'] ?? purchase['grand_total']),
        'remarks': purchase['remarks']?.toString() ?? '',
        'days': _toInt(purchase['days'], 0),
        'tax_type': purchase['tax_type']?.toString() ?? 'Gst',
        'financial_year': purchase['financial_year']?.toString() ?? '',
        'is_deleted': _toInt(purchase['is_deleted'], 0),
        'payment_status': _toInt(purchase['payment_status'], 0),
        'payment_mode': purchase['payment_mode']?.toString() ?? 'CREDIT',
        'branch_id': branchId,
        'terminal_id': (purchase['terminal_id']?.toString().trim().isNotEmpty == true)
            ? purchase['terminal_id'].toString().trim()
            : config.terminalId,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final entryUri = Uri.parse('${config.supabaseUrl}/rest/v1/purchase_entries?on_conflict=entry_no,terminal_id');
      final entryHeaders = Map<String, String>.from(config.restHeaders)..['Prefer'] = 'resolution=merge-duplicates';
      final res = await _safePostSingle(
        entryUri,
        headers: entryHeaders,
        payload: purchasePayload,
        tableName: 'purchase_entries',
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (items.isNotEmpty) {
          final itemPayloads = items.map((it) {
            return {
              'entry_no': entryNoVal,
              'product_id': it['product_id']?.toString() ?? '',
              'product_name': it['product_name']?.toString() ?? '',
              'extra': it['extra']?.toString() ?? '',
              'batch_number': it['batch']?.toString() ?? it['batch_number']?.toString() ?? '',
              'expiry_date': it['expiry']?.toString() ?? it['expiry_date']?.toString() ?? '',
              'quantity': _toInt(it['qty'] ?? it['quantity'], 1),
              'f_qty': _toInt(it['f_qty'], 0),
              'packing': _toInt(it['packin'] ?? it['packing'], 1),
              'mrp': _toDouble(it['mrp']),
              'unit_price': _toDouble(it['p_rate'] ?? it['unit_price']),
              'gross': _toDouble(it['gross']),
              'disc_percent': _toDouble(it['disc_percent']),
              'disc_amt': _toDouble(it['disc_amt']),
              'gst_percent': _toDouble(it['gst_percent'], 12.0),
              'gst_amt': _toDouble(it['gst_amt']),
              'total_amount': _toDouble(it['total'] ?? it['total_amount']),
              'rack': it['rack']?.toString() ?? '',
              'hsn_code': it['hsn_code']?.toString() ?? '',
              's_disc_percent': _toDouble(it['s_disc_percent']),
              'selling_rate': _toDouble(it['s_rate'] ?? it['selling_rate']),
              'landing_cost': _toDouble(it['l_cost'] ?? it['landing_cost']),
              'branch_id': branchId,
            };
          }).toList();

          final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
          final delUri = Uri.parse('$cleanUrl/rest/v1/purchase_items?entry_no=eq.${Uri.encodeComponent(entryNoVal)}');
          await http.delete(delUri, headers: config.restHeaders).timeout(const Duration(seconds: 2)).catchError((_) => http.Response('', 500));

          final itemsUri = Uri.parse('${config.supabaseUrl}/rest/v1/purchase_items');
          final itemHeaders = Map<String, String>.from(config.restHeaders);
          final resItems = await _safePost(
            itemsUri,
            headers: itemHeaders,
            payloads: itemPayloads,
            tableName: 'purchase_items',
          );

          if (resItems.statusCode < 200 || resItems.statusCode >= 300) {
            debugPrint('Cloud Sync: Purchase items push failed for $entryNoVal (${resItems.statusCode}). Retaining local pending entry.');
            AppLogger.instance.error(
              'SUPABASE',
              'Failed to sync items for purchase $entryNoVal (HTTP ${resItems.statusCode}); leaving dirty for retry.',
              details: resItems.body,
            );
            return false;
          }
        }

        // Mark local SQLite entry and line items as synced
        if (entryNoVal.isNotEmpty) {
          final db = await DbHelper.instance.database;
          await db.rawUpdate(
            'UPDATE purchase_entries SET is_synced = 1, is_cloud_synced = 1 WHERE entry_no = ? OR sup_inv_no = ?',
            [entryNoVal, entryNoVal],
          );
          await db.rawUpdate(
            'UPDATE purchase_items SET is_synced = 1, is_cloud_synced = 1 WHERE entry_no = ?',
            [entryNoVal],
          );
        }

        // Also push batch stock updates to Supabase stock_batches
        final db = await DbHelper.instance.database;
        for (var it in items) {
          final pId = it['product_id']?.toString() ?? '';
          final batchNum = it['batch']?.toString() ?? it['batch_number']?.toString() ?? '';
          if (pId.isNotEmpty && batchNum.isNotEmpty) {
            final res = await db.rawQuery(
              'SELECT SUM(current_stock) as total_stock FROM stock_batches WHERE product_id = ? AND LOWER(TRIM(batch_number)) = LOWER(TRIM(?))',
              [pId, batchNum],
            );
            final localStock = (res.isNotEmpty && res.first['total_stock'] != null)
                ? (res.first['total_stock'] as num).toInt()
                : 0;

            await pushStockBatch({
              'product_id': pId,
              'batch_number': batchNum,
              'expiry_date': it['expiry']?.toString() ?? it['expiry_date']?.toString() ?? '',
              'current_quantity': localStock,
              'current_stock': localStock,
              'purchase_rate': _toDouble(it['p_rate'] ?? it['unit_price']),
              'mrp': _toDouble(it['mrp']),
              'selling_rate': _toDouble(it['s_rate'] ?? it['selling_rate']),
              'packing': _toInt(it['packin'] ?? it['packing'], 1),
            });
          }
        }
        AppLogger.instance.supabase("Cloud Sync: Purchase entry $entryNoVal and items saved successfully via REST.");
        notifyListeners();
        return true;
      } else {
        AppLogger.instance.error('SUPABASE', "Cloud Sync HTTP ${res.statusCode} for purchase $entryNoVal", details: res.body);
        return false;
      }
    } catch (e, stack) {
      debugPrint('Failed to push purchase entry to Supabase: $e');
      AppLogger.instance.error('SUPABASE', "Cloud Sync Exception for purchase ${purchase['entry_no']}", error: e, stackTrace: stack);
      RemoteLoggerService.instance.logError(e, stackTrace: stack, library: 'SupabaseSyncService', context: 'pushPurchaseEntry');
      return false;
    }
  }

  // --- Private Helpers ---

  static final Set<String> _missingCloudTables = <String>{};

  void _checkResponseError(http.Response res, String tableName) {
    if (res.statusCode >= 400) {
      if (res.body.contains('PGRST205') || res.body.contains('Could not find the table')) {
        _missingCloudTables.add(tableName);
        debugPrint('Supabase notice: Optional cloud table "$tableName" does not exist yet. Skipping future pushes.');
        return;
      }
      String msg = 'Table "$tableName" HTTP ${res.statusCode}';
      try {
        final Map<String, dynamic> data = jsonDecode(res.body);
        if (data['message'] != null) {
          msg = 'Table "$tableName": ${data['message']}';
        } else if (data['code'] != null) {
          msg = 'Table "$tableName": Code ${data['code']}';
        }
      } catch (_) {
        if (res.body.isNotEmpty && res.body.length < 120) {
          msg = 'Table "$tableName": ${res.body}';
        }
      }
      _lastSyncError = msg;
      debugPrint('Supabase REST error: $_lastSyncError');
    }
  }

  static final Map<String, Set<String>> _unmappedColumns = {
    'sales_invoices': <String>{},
    'sales_items': <String>{},
    'product_master': <String>{'terminal_id'},
    'accounts': <String>{'is_cloud_synced', 'is_deleted', 'is_imported', 'terminal_id', 'updated_at'},
    'staff': <String>{'is_cloud_synced', 'is_deleted', 'is_imported', 'terminal_id', 'updated_at'},
  };

  static void markColumnUnmapped(String tableName, String colName) {
    if (colName.trim().isEmpty) return;
    _unmappedColumns.putIfAbsent(tableName, () => <String>{}).add(colName.trim());
    debugPrint('Recorded unmapped column "$colName" for table "$tableName". Future payloads will omit it automatically.');
  }

  static List<Map<String, dynamic>> sanitizePayloads(String tableName, List<Map<String, dynamic>> payloads) {
    final unmapped = _unmappedColumns[tableName];
    if (unmapped == null || unmapped.isEmpty) return payloads;

    return payloads.map((p) {
      final copy = Map<String, dynamic>.from(p);
      for (final col in unmapped) {
        copy.remove(col);
      }
      return copy;
    }).toList();
  }

  static Map<String, dynamic> sanitizeSinglePayload(String tableName, Map<String, dynamic> payload) {
    final unmapped = _unmappedColumns[tableName];
    if (unmapped == null || unmapped.isEmpty) return payload;

    final copy = Map<String, dynamic>.from(payload);
    for (final col in unmapped) {
      copy.remove(col);
    }
    return copy;
  }

  static List<Map<String, dynamic>> compactPayloads(List<Map<String, dynamic>> payloads) {
    if (payloads.isEmpty) return [];

    // Step 1: Clean individual maps
    final cleanedList = payloads.map((p) {
      final Map<String, dynamic> clean = {};
      p.forEach((k, v) {
        if (v != null) {
          if (v is String && v.isEmpty && k != 'id' && k != 'product_name' && k != 'product_id' && k != 'batch_number') return;
          clean[k] = v;
        }
      });
      return clean;
    }).toList();

    // Step 2: Collect union of all keys across the batch
    final Set<String> allKeys = {};
    for (var m in cleanedList) {
      allKeys.addAll(m.keys);
    }

    // Step 3: Enforce uniform key sets across all objects in the bulk array
    return cleanedList.map((m) {
      final Map<String, dynamic> uniformMap = {};
      for (var k in allKeys) {
        uniformMap[k] = m.containsKey(k) ? m[k] : null;
      }
      return uniformMap;
    }).toList();
  }

  /// Safely posts a list of JSON payloads to a Supabase REST table endpoint.
  Future<http.Response> _safePost(
    Uri uri, {
    required Map<String, String> headers,
    required List<Map<String, dynamic>> payloads,
    required String tableName,
    Duration timeout = const Duration(seconds: 15),
    int maxRetries = 3,
  }) async {
    if (_missingCloudTables.contains(tableName)) {
      return http.Response('[]', 200);
    }
    final cleanPayloads = sanitizePayloads(tableName, payloads);

    http.Response? lastResponse;
    Object? lastError;

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        var activePayloads = cleanPayloads;
        http.Response res = await http.post(uri, headers: headers, body: jsonEncode(activePayloads)).timeout(timeout);
        lastResponse = res;

        int colRetries = 0;
        while (res.statusCode >= 400 && colRetries < 15 && (res.body.contains('PGRST204') || res.body.contains('column'))) {
          colRetries++;
          final match = RegExp(r"Could not find the '([^']+)' column|column '([^']+)' does not exist", caseSensitive: false).firstMatch(res.body);
          final missingCol = match?.group(1) ?? match?.group(2);

          if (missingCol != null && missingCol.isNotEmpty) {
            markColumnUnmapped(tableName, missingCol);
            activePayloads = sanitizePayloads(tableName, payloads);

            try {
              res = await http.post(uri, headers: headers, body: jsonEncode(activePayloads)).timeout(timeout);
              lastResponse = res;
            } catch (_) {
              break;
            }
          } else {
            break;
          }
        }

        // Retry on 429 (Rate Limit), 502, 503, 504 (Gateway Timeout)
        if ((res.statusCode == 429 || res.statusCode >= 502) && attempt < maxRetries - 1) {
          debugPrint('HTTP post attempt ${attempt + 1} for $tableName returned status ${res.statusCode}, retrying in ${(attempt + 1)}s...');
          await Future.delayed(Duration(milliseconds: 1000 * (attempt + 1)));
          continue;
        }

        if (res.statusCode >= 400) {
          final plainHeaders = Map<String, String>.from(headers)..remove('Prefer');
          try {
            final retryRes = await http.post(uri, headers: plainHeaders, body: jsonEncode(activePayloads)).timeout(timeout);
            if (retryRes.statusCode < 400) {
              debugPrint('Plain POST retry for "$tableName" succeeded!');
              return retryRes;
            }
          } catch (_) {}
        }

        _checkResponseError(res, tableName);
        return res;
      } catch (e) {
        lastError = e;
        debugPrint('HTTP post network error on $tableName (attempt ${attempt + 1}/$maxRetries): $e');
        if (attempt < maxRetries - 1) {
          await Future.delayed(Duration(milliseconds: 1000 * (attempt + 1)));
        }
      }
    }

    if (lastResponse != null) {
      _checkResponseError(lastResponse, tableName);
      return lastResponse;
    }
    throw lastError ?? Exception('Failed HTTP POST request to $tableName after $maxRetries retries');
  }

  /// Safely posts a single JSON payload to a Supabase REST table endpoint.
  Future<http.Response> _safePostSingle(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, dynamic> payload,
    required String tableName,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_missingCloudTables.contains(tableName)) {
      return http.Response('[]', 200);
    }
    final cleanPayload = sanitizeSinglePayload(tableName, payload);

    http.Response res;
    try {
      res = await http.post(uri, headers: headers, body: jsonEncode(cleanPayload)).timeout(timeout);
    } catch (e) {
      debugPrint('HTTP post single network error on $tableName: $e');
      rethrow;
    }

    var activePayload = cleanPayload;
    int colRetries = 0;
    while (res.statusCode >= 400 && colRetries < 15 && (res.body.contains('PGRST204') || res.body.contains('column'))) {
      colRetries++;
      final match = RegExp(r"Could not find the '([^']+)' column|column '([^']+)' does not exist", caseSensitive: false).firstMatch(res.body);
      final missingCol = match?.group(1) ?? match?.group(2);

      if (missingCol != null && missingCol.isNotEmpty) {
        markColumnUnmapped(tableName, missingCol);
        activePayload = sanitizeSinglePayload(tableName, payload);

        try {
          res = await http.post(uri, headers: headers, body: jsonEncode(activePayload)).timeout(timeout);
        } catch (_) {
          break;
        }
      } else {
        break;
      }
    }

    if (res.statusCode >= 400) {
      final plainHeaders = Map<String, String>.from(headers)..remove('Prefer');
      try {
        final retryRes = await http.post(uri, headers: plainHeaders, body: jsonEncode(activePayload)).timeout(timeout);
        if (retryRes.statusCode < 400) {
          debugPrint('Plain single POST retry for "$tableName" succeeded!');
          return retryRes;
        }
      } catch (_) {}
    }

    _checkResponseError(res, tableName);
    return res;
  }

  Future<void> _syncMasterTables() async {
    try {
      updateCategoryProgress('suppliers_doctors', processed: 0, total: 0, state: CategorySyncState.transferring);
      notifyListeners();

      final db = await DbHelper.instance.database;
      final config = ServerConfigService.instance;
      final branchId = config.storeBranchId;
      final terminalId = config.terminalId;

      final masterTables = ['categories', 'manufacturers', 'racks', 'generics', 'suppliers', 'doctors', 'accounts', 'staff'];
      for (var tName in masterTables) {
        final rows = await db.query(tName, where: 'is_synced = 0 OR is_synced IS NULL');
        if (rows.isNotEmpty) {
          final payloads = rows.map((r) {
            final m = Map<String, dynamic>.from(r);
            m['branch_id'] = branchId;
            m['terminal_id'] = terminalId;
            m.remove('is_synced');
            return m;
          }).toList();
          final uri = Uri.parse('${config.supabaseUrl}/rest/v1/$tName?on_conflict=id');
          final res = await _safePost(
            uri,
            headers: config.restHeaders,
            payloads: payloads,
            tableName: tName,
            timeout: const Duration(seconds: 8),
          );
          if (res.statusCode < 400 || res.body.contains('row-level security policy')) {
            await _runWithDbRetry(() async {
              await db.transaction((txn) async {
                await txn.rawUpdate('UPDATE $tName SET is_synced = 1');
              });
            });
          }
          await Future.delayed(const Duration(milliseconds: 10));
        }
      }
      final supTotal = (await db.rawQuery('SELECT COUNT(*) as cnt FROM suppliers')).first['cnt'] as int? ?? 0;
      final docTotal = (await db.rawQuery('SELECT COUNT(*) as cnt FROM doctors')).first['cnt'] as int? ?? 0;
      final supDocTotal = supTotal + docTotal;
      updateCategoryProgress('suppliers_doctors', processed: supDocTotal, total: supDocTotal, state: CategorySyncState.completed);
    } catch (e) {
      debugPrint('Master table sync error: $e');
    }
  }

  Future<void> _syncProducts({bool forceFull = false}) async {
    if (_isWiping || ServerConfigService.instance.isWiping) return;
    try {
      final db = await DbHelper.instance.database;
      final totalInDb = (await db.rawQuery('SELECT COUNT(*) as cnt FROM product_master')).first['cnt'] as int? ?? 0;

      bool pushAll = forceFull;
      if (!pushAll && totalInDb > 0) {
        final remoteCount = await fetchRemoteCount('product_master');
        if (remoteCount < totalInDb) {
          pushAll = true;
          debugPrint('⚡ Auto-Discrepancy Push: Cloud product_master count ($remoteCount) is less than local PC ($totalInDb). Pushing all local products...');
        }
      }

      final products = pushAll
          ? await db.query('product_master')
          : await db.query('product_master', where: 'is_synced = 0 OR is_synced IS NULL');

      if (products.isEmpty) {
        updateCategoryProgress('products', processed: totalInDb, total: totalInDb, state: CategorySyncState.completed);
        return;
      }

      updateCategoryProgress('products', processed: 0, total: products.length, state: CategorySyncState.transferring);

      final config = ServerConfigService.instance;
      final branchId = config.storeBranchId;
      final terminalId = config.terminalId;
      final uri = Uri.parse('${config.supabaseUrl}/rest/v1/product_master?on_conflict=id');
      final exportHeaders = Map<String, String>.from(config.restHeaders)
        ..['Prefer'] = 'resolution=merge-duplicates, return=minimal';

      const int batchSize = 500;
      const int maxConcurrency = 4;

      final List<List<Map<String, dynamic>>> allChunks = [];
      for (int i = 0; i < products.length; i += batchSize) {
        allChunks.add(products.sublist(i, (i + batchSize < products.length) ? i + batchSize : products.length));
      }

      int processedTotal = 0;
      final List<String> deferredSuccessfulIds = [];
      int chunkIndex = 0;

      Future<void> flushDeferredIds() async {
        if (deferredSuccessfulIds.isEmpty) return;
        final idsToFlush = List<String>.from(deferredSuccessfulIds);
        deferredSuccessfulIds.clear();

        try {
          await db.transaction((txn) async {
            final batch = txn.batch();
            for (final id in idsToFlush) {
              batch.rawUpdate('UPDATE product_master SET is_synced = 1 WHERE id = ?', [id]);
            }
            await batch.commit(noResult: true);
          });
        } catch (e) {
          debugPrint('Error updating product_master is_synced status: $e');
        }
      }

      Future<void> worker() async {
        while (!_cancelRequested) {
          int currentIdx = -1;
          if (chunkIndex < allChunks.length) {
            currentIdx = chunkIndex++;
          }
          if (currentIdx < 0 || currentIdx >= allChunks.length) break;

          final chunk = allChunks[currentIdx];
          final rawPayloads = chunk.map((p) {
            String prodId = (p['id'] ?? '').toString().trim();
            if (prodId.isEmpty) {
              final rowId = p['rowid'] ?? p['id'];
              prodId = "PRD_${rowId ?? DateTime.now().millisecondsSinceEpoch}";
            }

            final nameStr = _cleanString(p['product_name'] ?? p['name'], 'Unnamed Product');
            final gstVal = _toDouble(p['gst_rate'] ?? p['gst_percent'], 12.0);
            final priceVal = _toDouble(p['selling_price'] ?? p['sale_rate'], 0.0);
            final mrpVal = _toDouble(p['mrp'], 0.0);

            return {
              'id': prodId,
              'product_name': nameStr,
              'generic_name': _cleanString(p['generic_name']),
              'category_id': _cleanString(p['category_id']),
              'sub_category_id': _cleanString(p['sub_category_id']),
              'manufacturer_id': _cleanString(p['manufacturer_id']),
              'rack_id': _cleanString(p['rack_id']),
              'hsn_code': _cleanString(p['hsn_code']),
              'gst_rate': gstVal,
              's_disc_percent': _toDouble(p['s_disc_percent']),
              'schedule': _cleanString(p['schedule'], 'H'),
              'mrp': mrpVal,
              'purchase_rate': _toDouble(p['purchase_rate']),
              'selling_price': priceVal,
              'reorder_level': _toInt(p['reorder_level'], 10),
              'max_level': _toInt(p['max_level'], 100),
              'unit': _cleanString(p['unit'], 'Strip'),
              'packing': _toInt(p['packing'], 10),
              'patent': _cleanString(p['patent']),
              'barcode': _cleanString(p['barcode']),
              'is_controlled': _toInt(p['is_controlled'], 0),
              'is_banned': _toInt(p['is_banned'], 0),
              'is_nrx': _toInt(p['is_nrx'], 0),
              'is_active': _toInt(p['is_active'], 1),
              'is_disc_locked': _toInt(p['is_disc_locked'], 0),
              'preferred_wholesale': _cleanString(p['preferred_wholesale']),
              'lead_time': _toInt(p['lead_time'], 2),
              'branch_id': branchId,
              'updated_at': DateTime.now().toIso8601String(),
            };
          }).toList();

          final Map<String, Map<String, dynamic>> uniquePayloadsMap = {};
          for (var item in rawPayloads) {
            final String idKey = item['id'].toString();
            if (idKey.isNotEmpty) {
              uniquePayloadsMap[idKey] = item;
            }
          }
          final payloads = compactPayloads(uniquePayloadsMap.values.toList());
          bool batchSuccess = false;
          try {
            final res = await _safePost(
              uri,
              headers: exportHeaders,
              payloads: payloads,
              tableName: 'product_master',
              timeout: const Duration(seconds: 45),
            );
            if (res.statusCode < 400) {
              batchSuccess = true;
              final ids = payloads.map((e) => e['id'].toString()).where((id) => id.isNotEmpty).toList();
              if (ids.isNotEmpty) {
                deferredSuccessfulIds.addAll(ids);
              }
            } else {
              debugPrint('Product batch chunk #$currentIdx failed (${res.statusCode}). Activating self-healing mini-chunk isolation fallback...');
              // Self-Healing Fallback: Split failed 150-item chunk into mini-chunks of 10 items
              const int miniBatchSize = 10;
              for (int m = 0; m < payloads.length; m += miniBatchSize) {
                if (_cancelRequested) break;
                final miniPayloads = payloads.sublist(m, (m + miniBatchSize < payloads.length) ? m + miniBatchSize : payloads.length);
                try {
                  final miniRes = await _safePost(
                    uri,
                    headers: exportHeaders,
                    payloads: miniPayloads,
                    tableName: 'product_master',
                    timeout: const Duration(seconds: 15),
                  );
                  if (miniRes.statusCode < 400) {
                    final miniIds = miniPayloads.map((e) => e['id'].toString()).where((id) => id.isNotEmpty).toList();
                    deferredSuccessfulIds.addAll(miniIds);
                    processedTotal += miniPayloads.length;
                    _updateDynamicProgress(miniPayloads.length, 'Syncing Products (Self-Healing)');
                  } else {
                    // Item-by-item single record isolation
                    for (var singleItem in miniPayloads) {
                      if (_cancelRequested) break;
                      try {
                        final singleRes = await _safePost(
                          uri,
                          headers: exportHeaders,
                          payloads: [singleItem],
                          tableName: 'product_master',
                          timeout: const Duration(seconds: 10),
                        );
                        if (singleRes.statusCode < 400) {
                          final singleId = singleItem['id']?.toString() ?? '';
                          if (singleId.isNotEmpty) deferredSuccessfulIds.add(singleId);
                          processedTotal += 1;
                          _updateDynamicProgress(1, 'Syncing Products (Single Item)');
                        } else {
                          final skippedName = singleItem['product_name'] ?? singleItem['id'] ?? 'Unknown Item';
                          debugPrint('Isolated bad product record: "$skippedName" (Status: ${singleRes.statusCode})');
                          _skippedItemLogs.add('Product: $skippedName (Status ${singleRes.statusCode})');
                        }
                      } catch (singleErr) {
                        final skippedName = singleItem['product_name'] ?? singleItem['id'] ?? 'Unknown Item';
                        debugPrint('Single product post error "$skippedName": $singleErr');
                        _skippedItemLogs.add('Product: $skippedName ($singleErr)');
                      }
                    }
                  }
                } catch (miniErr) {
                  debugPrint('Mini-chunk error: $miniErr');
                }
              }
            }
          } catch (e) {
            debugPrint('Product batch sync warning: $e');
          }

          if (batchSuccess) {
            _updateDynamicProgress(chunk.length, 'Syncing Products');
            processedTotal += chunk.length;
          }
          updateCategoryProgress('products', processed: processedTotal.clamp(0, products.length), total: products.length, state: CategorySyncState.transferring);

          // Yield 5ms microtask breather to main event loop so Flutter engine can render progress frame smoothly
          await Future.delayed(const Duration(milliseconds: 5));

          if (deferredSuccessfulIds.length >= 2500) {
            await flushDeferredIds();
          }
        }
      }

      final workers = List.generate(maxConcurrency, (_) => worker());
      await Future.wait(workers);
      await flushDeferredIds();

      final bool isFullSuccess = processedTotal >= products.length;
      if (!isFullSuccess) {
        _lastSyncError = 'Product Master Notice: $processedTotal of ${products.length} products uploaded to cloud server.';
      }
      updateCategoryProgress(
        'products',
        processed: processedTotal.clamp(0, products.length),
        total: products.length,
        state: isFullSuccess ? CategorySyncState.completed : CategorySyncState.error,
      );
    } catch (e) {
      debugPrint('Products sync error: $e');
      updateCategoryProgress('products', processed: 0, total: 0, state: CategorySyncState.error);
    }
  }

  Future<void> _syncStockBatches({bool forceFull = false}) async {
    if (_isWiping || ServerConfigService.instance.isWiping) return;
    try {
      final db = await DbHelper.instance.database;
      final totalInDb = (await db.rawQuery('SELECT COUNT(*) as cnt FROM stock_batches')).first['cnt'] as int? ?? 0;

      bool pushAll = forceFull;
      if (!pushAll && totalInDb > 0) {
        final remoteCount = await fetchRemoteCount('stock_batches');
        if (remoteCount < totalInDb) {
          pushAll = true;
          debugPrint('⚡ Auto-Discrepancy Push: Cloud stock_batches count ($remoteCount) is less than local PC ($totalInDb). Pushing all local batches...');
        }
      }

      final batches = pushAll
          ? await db.query('stock_batches')
          : await db.query('stock_batches', where: 'is_synced = 0 OR is_synced IS NULL');

      if (batches.isEmpty) {
        updateCategoryProgress('batches', processed: totalInDb, total: totalInDb, state: CategorySyncState.completed);
        return;
      }

      updateCategoryProgress('batches', processed: 0, total: batches.length, state: CategorySyncState.transferring);

      final config = ServerConfigService.instance;
      final branchId = config.storeBranchId;
      final terminalId = config.terminalId;
      final uri = Uri.parse('${config.supabaseUrl}/rest/v1/stock_batches?on_conflict=id');
      final exportHeaders = Map<String, String>.from(config.restHeaders)
        ..['Prefer'] = 'resolution=merge-duplicates, return=minimal';

      const int batchSize = 500;
      const int maxConcurrency = 4;

      final List<List<Map<String, dynamic>>> allChunks = [];
      for (int i = 0; i < batches.length; i += batchSize) {
        allChunks.add(batches.sublist(i, (i + batchSize < batches.length) ? i + batchSize : batches.length));
      }

      int processedTotal = 0;
      final List<MapEntry<String, String>> deferredSuccessfulPairs = [];
      int chunkIndex = 0;

      Future<void> flushDeferredPairs() async {
        if (deferredSuccessfulPairs.isEmpty) return;
        final pairsToFlush = List<MapEntry<String, String>>.from(deferredSuccessfulPairs);
        deferredSuccessfulPairs.clear();

        try {
          await db.transaction((txn) async {
            final batch = txn.batch();
            for (final pair in pairsToFlush) {
              batch.rawUpdate('UPDATE stock_batches SET is_synced = 1 WHERE product_id = ? AND batch_number = ?', [pair.key, pair.value]);
            }
            await batch.commit(noResult: true);
          });
        } catch (e) {
          debugPrint('Error updating stock_batches is_synced status: $e');
        }
      }

      Future<void> worker() async {
        while (!_cancelRequested) {
          int currentIdx = -1;
          if (chunkIndex < allChunks.length) {
            currentIdx = chunkIndex++;
          }
          if (currentIdx < 0 || currentIdx >= allChunks.length) break;

          final chunk = allChunks[currentIdx];
          final Map<String, Map<String, dynamic>> uniqueBatchesMap = {};
          for (var b in chunk) {
            final prodId = b['product_id']?.toString() ?? '';
            final batchNo = b['batch_number']?.toString() ?? '';
            if (prodId.isEmpty || batchNo.isEmpty) continue;

            final expiryStr = b['expiry_date']?.toString() ?? '';
            final sellRate = _toDouble(b['selling_rate'] ?? b['sale_rate'], 0.0);
            final purchaseRate = _toDouble(b['purchase_rate'], 0.0);
            final landingCost = _toDouble(b['landing_cost'], purchaseRate);
            final mrpVal = _toDouble(b['mrp'], 0.0);
            final qty = _toInt(b['current_quantity'] ?? b['current_stock'], 0);

            final cleanKeyStr = '${prodId}_${batchNo}_$expiryStr'.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
            if (uniqueBatchesMap.containsKey(cleanKeyStr)) {
              uniqueBatchesMap[cleanKeyStr]!['current_quantity'] = (uniqueBatchesMap[cleanKeyStr]!['current_quantity'] as int) + qty;
            } else {
              uniqueBatchesMap[cleanKeyStr] = {
                'id': cleanKeyStr,
                'product_id': prodId,
                'batch_number': batchNo,
                'expiry_date': expiryStr,
                'mfg_date': b['mfg_date']?.toString() ?? '',
                'purchase_rate': purchaseRate,
                'landing_cost': landingCost,
                'mrp': mrpVal,
                'selling_rate': sellRate,
                'current_quantity': qty,
                's_disc_percent': _toDouble(b['s_disc_percent']),
                'gst_percent': _toDouble(b['gst_percent'], 12.0),
                'rack': b['rack']?.toString() ?? '',
                'supplier_name': b['supplier_name']?.toString() ?? '',
                'packing': _toInt(b['packing'], 1),
                'is_active': _toInt(b['is_active'], 1),
                'financial_year': b['financial_year']?.toString() ?? '',
                'terminal_id': terminalId,
                'branch_id': branchId,
                'updated_at': DateTime.now().toIso8601String(),
              };
            }
          }

          final rawPayloads = uniqueBatchesMap.values.toList();
          final payloads = compactPayloads(rawPayloads);
          bool batchSuccess = false;
          if (payloads.isNotEmpty) {
            try {
              var res = await _safePost(
                uri,
                headers: exportHeaders,
                payloads: payloads,
                tableName: 'stock_batches',
                timeout: const Duration(seconds: 45),
              );
              if (res.statusCode >= 400 && res.body.contains('stock_batches_product_id_fkey')) {
                // Recover missing products from local product_master and push first
                final missingProductIds = payloads
                    .map((p) => p['product_id']?.toString() ?? '')
                    .where((id) => id.isNotEmpty)
                    .toSet();
                if (missingProductIds.isNotEmpty) {
                  final missingProds = await db.query(
                    'product_master',
                    where: 'id IN (${missingProductIds.map((_) => '?').join(',')})',
                    whereArgs: missingProductIds.toList(),
                  );
                  if (missingProds.isNotEmpty) {
                    final prodUri = Uri.parse('${config.supabaseUrl}/rest/v1/product_master?on_conflict=id');
                    final prodPayloads = compactPayloads(missingProds);
                    await _safePost(
                      prodUri,
                      headers: exportHeaders,
                      payloads: prodPayloads,
                      tableName: 'product_master',
                      timeout: const Duration(seconds: 45),
                    );
                  }
                }
                // Retry posting stock_batches chunk
                res = await _safePost(
                  uri,
                  headers: exportHeaders,
                  payloads: payloads,
                  tableName: 'stock_batches',
                  timeout: const Duration(seconds: 45),
                );
              }
              if (res.statusCode < 400) {
                batchSuccess = true;
                for (var p in payloads) {
                  final pid = p['product_id']?.toString() ?? '';
                  final bno = p['batch_number']?.toString() ?? '';
                  if (pid.isNotEmpty && bno.isNotEmpty) {
                    deferredSuccessfulPairs.add(MapEntry(pid, bno));
                  }
                }
              }
            } catch (e) {
              debugPrint('Stock batch sync warning: $e');
            }
          }

          if (batchSuccess) {
            _updateDynamicProgress(chunk.length, 'Syncing Inventory Batches');
            processedTotal += chunk.length;
          }
          updateCategoryProgress('batches', processed: processedTotal.clamp(0, batches.length), total: batches.length, state: CategorySyncState.transferring);

          // Yield 5ms microtask breather to main event loop so Flutter engine can render progress frame smoothly
          await Future.delayed(const Duration(milliseconds: 5));

          if (deferredSuccessfulPairs.length >= 2500) {
            await flushDeferredPairs();
          }
        }
      }

      final workers = List.generate(maxConcurrency, (_) => worker());
      await Future.wait(workers);
      await flushDeferredPairs();

      final bool isFullSuccess = processedTotal >= batches.length;
      if (!isFullSuccess) {
        _lastSyncError = 'Stock Batches Notice: $processedTotal of ${batches.length} batches uploaded to cloud server.';
      }
      updateCategoryProgress(
        'batches',
        processed: processedTotal.clamp(0, batches.length),
        total: batches.length,
        state: isFullSuccess ? CategorySyncState.completed : CategorySyncState.error,
      );
    } catch (e) {
      debugPrint('Stock batches sync error: $e');
      updateCategoryProgress('batches', processed: 0, total: 0, state: CategorySyncState.error);
    }
  }

  Future<void> _syncCustomers() async {
    try {
      final db = await DbHelper.instance.database;
      final patients = await db.query('patients', where: 'is_synced = 0 OR is_synced IS NULL');
      final config = ServerConfigService.instance;
      final branchId = config.storeBranchId;

      final totalInDb = (await db.rawQuery('SELECT COUNT(*) as cnt FROM patients')).first['cnt'] as int? ?? 0;

      if (patients.isEmpty) {
        updateCategoryProgress('patients', processed: totalInDb, total: totalInDb, state: CategorySyncState.completed);
        return;
      }

      updateCategoryProgress('patients', processed: 0, total: patients.length, state: CategorySyncState.transferring);

      const int batchSize = 50;
      for (int i = 0; i < patients.length; i += batchSize) {
        if (_cancelRequested) break;
        final chunk = patients.sublist(i, (i + batchSize < patients.length) ? i + batchSize : patients.length);
        final payloads = chunk.map((pat) {
          return {
            'id': pat['id']?.toString() ?? '',
            'name': pat['name']?.toString() ?? '',
            'mobile': pat['mobile']?.toString() ?? '',
            'address': pat['address']?.toString() ?? '',
            'branch_id': branchId,
          };
        }).toList();

        final uri = Uri.parse('${config.supabaseUrl}/rest/v1/patients');
        final res = await _safePost(
          uri,
          headers: config.restHeaders,
          payloads: payloads,
          tableName: 'patients',
          timeout: const Duration(seconds: 15),
        );
        if (res.statusCode < 400) {
          final ids = chunk.map((e) => e['id']?.toString() ?? '').where((id) => id.isNotEmpty).toList();
          if (ids.isNotEmpty) {
            final placeholders = List.filled(ids.length, '?').join(',');
            await db.rawUpdate('UPDATE patients SET is_synced = 1 WHERE id IN ($placeholders)', ids);
          }
          _updateDynamicProgress(chunk.length, 'Syncing Customers');
        }
        updateCategoryProgress('patients', processed: i + chunk.length, total: patients.length, state: CategorySyncState.transferring);
      }
      updateCategoryProgress('patients', processed: patients.length, total: patients.length, state: CategorySyncState.completed);
    } catch (e) {
      debugPrint('Patients sync error: $e');
    }
  }

  Future<void> _syncSalesInvoices({bool forceFull = false}) async {
    if (_isRecoveryLocked || _syncPaused) {
      debugPrint('_syncSalesInvoices skipped due to Active Invoice Recovery Lock.');
      return;
    }

    try {
      final db = await DbHelper.instance.database;
      final config = ServerConfigService.instance;
      final branchId = config.storeBranchId;

      final totalInvoices = forceFull
          ? ((await db.rawQuery('SELECT COUNT(*) as cnt FROM sales_invoices')).first['cnt'] as int? ?? 0)
          : ((await db.rawQuery('SELECT COUNT(*) as cnt FROM sales_invoices WHERE is_synced = 0 OR is_synced IS NULL')).first['cnt'] as int? ?? 0);

      final totalInDb = ((await db.rawQuery('SELECT COUNT(*) as cnt FROM sales_invoices')).first['cnt'] as int? ?? 0);

      if (totalInvoices == 0) {
        updateCategoryProgress('sales', processed: totalInDb, total: totalInDb, state: CategorySyncState.completed);
        return;
      }

      updateCategoryProgress('sales', processed: 0, total: totalInvoices, state: CategorySyncState.transferring);

      final int pageSize = forceFull ? 100 : 25;
      int offset = 0;
      bool hasMore = true;
      int consecutiveFailures = 0;
      int totalProcessedSoFar = 0;

      while (hasMore && !_cancelRequested) {
        final invoices = forceFull
            ? await db.query('sales_invoices', limit: pageSize, offset: offset)
            : await db.query('sales_invoices', where: 'is_synced = 0 OR is_synced IS NULL', limit: pageSize, offset: offset);

        if (invoices.isEmpty) {
          hasMore = false;
          break;
        }

        final List<Map<String, dynamic>> validInvoices = [];
        final List<String> blankEntries = [];

        for (var inv in invoices) {
          final net = _toDouble(inv['grand_total'] ?? inv['net_amount'] ?? inv['total_amount']);
          final isDel = _toInt(inv['is_deleted'], 0);
          final entryNo = inv['entry_no']?.toString() ?? inv['invoice_no']?.toString() ?? '';

          if (net > 0 || isDel == 1) {
            validInvoices.add(inv);
          } else if (entryNo.isNotEmpty) {
            final itemCheck = await db.rawQuery('SELECT 1 FROM sales_items WHERE invoice_no = ? OR invoice_no = ? LIMIT 1', [entryNo, cleanEntryNo(entryNo)]);
            if (itemCheck.isNotEmpty) {
              validInvoices.add(inv);
            } else {
              blankEntries.add(entryNo);
            }
          }
        }

        if (blankEntries.isNotEmpty) {
          final bPlaceholders = List.filled(blankEntries.length, '?').join(',');
          await db.rawUpdate('UPDATE sales_invoices SET is_synced = 1 WHERE entry_no IN ($bPlaceholders)', blankEntries);
        }

        if (validInvoices.isEmpty) {
          if (!forceFull) offset += pageSize;
          continue;
        }

        for (var inv in validInvoices) {
          final entryNo = inv['entry_no']?.toString() ?? inv['invoice_no']?.toString() ?? '';
          if (entryNo.isEmpty) continue;

          final items = await db.query(
            'sales_items',
            where: 'invoice_no = ?',
            whereArgs: [entryNo],
          );

          final bool success = await pushSalesInvoice(
            Map<String, dynamic>.from(inv),
            items.map((it) => Map<String, dynamic>.from(it)).toList(),
          );

          if (success) {
            consecutiveFailures = 0;
            _updateDynamicProgress(1, 'Syncing Sales Invoices');
          } else {
            consecutiveFailures++;
            if (consecutiveFailures >= 5) {
              debugPrint('Aborting sales invoices sync due to 5 consecutive single-invoice failures.');
              break;
            }
          }
          totalProcessedSoFar++;
        }

        updateCategoryProgress('sales', processed: totalProcessedSoFar, total: totalInvoices, state: CategorySyncState.transferring);
        if (forceFull) offset += pageSize;
        if (invoices.length < pageSize) hasMore = false;
        await Future.delayed(const Duration(milliseconds: 5));
      }
      final bool isSalesSuccess = totalProcessedSoFar >= totalInvoices;
      updateCategoryProgress(
        'sales',
        processed: totalProcessedSoFar.clamp(0, totalInvoices),
        total: totalInvoices,
        state: isSalesSuccess ? CategorySyncState.completed : CategorySyncState.error,
      );
    } catch (e) {
      debugPrint('Sales invoices sync warning: $e');
    }
  }

  Future<void> _syncPurchaseEntries({bool forceFull = false}) async {
    try {
      final db = await DbHelper.instance.database;
      final config = ServerConfigService.instance;
      final branchId = config.storeBranchId;

      final totalPurchases = forceFull
          ? ((await db.rawQuery('SELECT COUNT(*) as cnt FROM purchase_entries')).first['cnt'] as int? ?? 0)
          : ((await db.rawQuery('SELECT COUNT(*) as cnt FROM purchase_entries WHERE is_synced = 0 OR is_synced IS NULL')).first['cnt'] as int? ?? 0);

      final totalInDb = ((await db.rawQuery('SELECT COUNT(*) as cnt FROM purchase_entries')).first['cnt'] as int? ?? 0);

      if (totalPurchases == 0) {
        updateCategoryProgress('purchases', processed: totalInDb, total: totalInDb, state: CategorySyncState.completed);
        return;
      }

      updateCategoryProgress('purchases', processed: 0, total: totalPurchases, state: CategorySyncState.transferring);

      final int pageSize = forceFull ? 100 : 25;
      int offset = 0;
      bool hasMore = true;
      int consecutiveFailures = 0;
      int totalProcessedSoFar = 0;

      while (hasMore && !_cancelRequested) {
        final purchases = forceFull
            ? await db.query('purchase_entries', limit: pageSize, offset: offset)
            : await db.query('purchase_entries', where: 'is_synced = 0 OR is_synced IS NULL', limit: pageSize, offset: offset);

        if (purchases.isEmpty) {
          hasMore = false;
          break;
        }

        final payloads = purchases.map((pur) {
          final rawEntryNo = pur['entry_no']?.toString() ?? '';
          final dateStr = pur['date']?.toString() ?? '';
          DateTime parsedDt;
          try { parsedDt = DateTime.parse(dateStr); } catch (_) { parsedDt = DateTime.tryParse(dateStr.replaceAll('/', '-')) ?? DateTime.now(); }
          final computedFy = _calculateFY(parsedDt);
          final fyStr = (pur['financial_year'] != null && pur['financial_year'].toString().isNotEmpty)
              ? pur['financial_year'].toString()
              : computedFy;
          final cleanNo = rawEntryNo.contains('_') ? rawEntryNo.substring(rawEntryNo.indexOf('_') + 1) : rawEntryNo;
          final entryNo = rawEntryNo.contains('_') ? rawEntryNo : "${fyStr}_$cleanNo";

          return {
            'entry_no': entryNo,
            'date': pur['date']?.toString() ?? '',
            'supplier_name': pur['supplier_name']?.toString() ?? '',
            'sup_inv_no': cleanInvoiceNo(pur['sup_inv_no']?.toString() ?? ''),
            'sup_inv_date': pur['sup_inv_date']?.toString() ?? '',
            'done_by': pur['done_by']?.toString() ?? '',
            'inv_total': _toDouble(pur['inv_total'] ?? pur['grand_total']),
            'net_amount': _toDouble(pur['inv_total'] ?? pur['grand_total']),
            'sub_total': _toDouble(pur['sub_total']),
            'subtotal': _toDouble(pur['sub_total']),
            'discount': _toDouble(pur['discount']),
            'discount_amount': _toDouble(pur['discount']),
            'other_charge': _toDouble(pur['other_charge']),
            'round_off': _toDouble(pur['round_off']),
            'grand_total': _toDouble(pur['grand_total'] ?? pur['inv_total']),
            'total_amount': _toDouble(pur['total_amount'] ?? pur['grand_total']),
            'remarks': pur['remarks']?.toString() ?? '',
            'payment_status': _toInt(pur['payment_status'], 0),
            'payment_mode': pur['payment_mode']?.toString() ?? 'CREDIT',
            'financial_year': fyStr,
            'branch_id': branchId,
            'updated_at': DateTime.now().toIso8601String(),
          };
        }).toList();

        final uri = Uri.parse('${config.supabaseUrl}/rest/v1/purchase_entries?on_conflict=entry_no,terminal_id');
        final res = await _safePost(
          uri,
          headers: config.restHeaders,
          payloads: payloads,
          tableName: 'purchase_entries',
          timeout: const Duration(seconds: 15),
        );

        final bool headerBatchOk = res.statusCode < 400 || res.statusCode == 409;
        final entryNos = purchases.map((e) => e['entry_no']?.toString()).where((no) => no != null && no.isNotEmpty).cast<String>().toList();
        bool itemsBatchOk = true;

        if (headerBatchOk && entryNos.isNotEmpty) {
          final placeholders = List.filled(entryNos.length, '?').join(',');
          final items = await db.rawQuery('SELECT * FROM purchase_items WHERE entry_no IN ($placeholders)', entryNos);
          if (items.isNotEmpty) {
            final itemPayloads = items.map((it) {
              return {
                'entry_no': _sanitizeEntryNo(it['entry_no']?.toString() ?? ''),
                'product_id': it['product_id']?.toString() ?? '',
                'product_name': it['product_name']?.toString() ?? '',
                'extra': it['extra']?.toString() ?? '',
                'batch_number': it['batch']?.toString() ?? it['batch_number']?.toString() ?? '',
                'expiry_date': it['expiry']?.toString() ?? it['expiry_date']?.toString() ?? '',
                'quantity': _toInt(it['qty'] ?? it['quantity'], 1),
                'f_qty': _toInt(it['f_qty'], 0),
                'packing': _toInt(it['packin'] ?? it['packing'], 1),
                'mrp': _toDouble(it['mrp']),
                'unit_price': _toDouble(it['p_rate'] ?? it['unit_price']),
                'gross': _toDouble(it['gross']),
                'disc_percent': _toDouble(it['disc_percent']),
                'disc_amt': _toDouble(it['disc_amt']),
                'gst_percent': _toDouble(it['gst_percent'], 12.0),
                'gst_amt': _toDouble(it['gst_amt']),
                'total_amount': _toDouble(it['total'] ?? it['total_amount']),
                'rack': it['rack']?.toString() ?? '',
                'hsn_code': it['hsn_code']?.toString() ?? '',
                's_disc_percent': _toDouble(it['s_disc_percent']),
                'selling_rate': _toDouble(it['s_rate'] ?? it['selling_rate']),
                'landing_cost': _toDouble(it['l_cost'] ?? it['landing_cost']),
                'branch_id': branchId,
              };
            }).toList();
            final itemsUri = Uri.parse('${config.supabaseUrl}/rest/v1/purchase_items');
            final itemHeaders = Map<String, String>.from(config.restHeaders);
            final resItems = await _safePost(
              itemsUri,
              headers: itemHeaders,
              payloads: itemPayloads,
              tableName: 'purchase_items',
              timeout: const Duration(seconds: 15),
            );
            itemsBatchOk = resItems.statusCode < 400;
          }
        }

        if (headerBatchOk && itemsBatchOk) {
          consecutiveFailures = 0;
          final syncedEntries = purchases.map((e) => e['entry_no']?.toString() ?? '').where((e) => e.isNotEmpty).toList();
          if (syncedEntries.isNotEmpty) {
            final placeholders = List.filled(syncedEntries.length, '?').join(',');
            await db.rawUpdate('UPDATE purchase_entries SET is_synced = 1 WHERE entry_no IN ($placeholders)', syncedEntries);
          }
          _updateDynamicProgress(purchases.length, 'Syncing Purchase Entries');
        } else {
          consecutiveFailures++;
          if (!forceFull) offset += pageSize;
          if (consecutiveFailures >= 3) {
            debugPrint('Aborting purchase entries sync due to 3 consecutive batch failures.');
            break;
          }
        }

        totalProcessedSoFar += purchases.length;
        updateCategoryProgress('purchases', processed: totalProcessedSoFar, total: totalPurchases, state: CategorySyncState.transferring);
        if (forceFull) offset += pageSize;
        if (purchases.length < pageSize) hasMore = false;
        await Future.delayed(const Duration(milliseconds: 5));
      }
      final bool isPurSuccess = totalProcessedSoFar >= totalPurchases;
      updateCategoryProgress(
        'purchases',
        processed: totalProcessedSoFar.clamp(0, totalPurchases),
        total: totalPurchases,
        state: isPurSuccess ? CategorySyncState.completed : CategorySyncState.error,
      );
    } catch (e) {
      debugPrint('Purchase entries sync warning: $e');
    }
  }

  Future<void> _syncSalesReturns() async {
    try {
      final db = await DbHelper.instance.database;
      final totalInDb = (await db.rawQuery('SELECT COUNT(*) as cnt FROM sales_return_invoices')).first['cnt'] as int? ?? 0;
      final returns = await db.query('sales_return_invoices', where: 'is_synced = 0 OR is_synced IS NULL', limit: 200);
      final config = ServerConfigService.instance;
      final branchId = config.storeBranchId;

      if (returns.isNotEmpty) {
        final payloads = returns.map((r) {
          final m = Map<String, dynamic>.from(r);
          m['branch_id'] = branchId;
          m.remove('is_synced');
          return m;
        }).toList();

        final uri = Uri.parse('${config.supabaseUrl}/rest/v1/sales_return_invoices?on_conflict=entry_no,terminal_id');
        final res = await _safePost(
          uri,
          headers: config.restHeaders,
          payloads: payloads,
          tableName: 'sales_return_invoices',
          timeout: const Duration(seconds: 8),
        );

        final returnNos = returns.map((e) => e['entry_no']?.toString()).where((no) => no != null && no.isNotEmpty).cast<String>().toList();
        bool itemsOk = true;

        if (res.statusCode < 400 && returnNos.isNotEmpty) {
          final placeholders = List.filled(returnNos.length, '?').join(',');
          final items = await db.rawQuery('SELECT * FROM sales_return_items WHERE return_no IN ($placeholders)', returnNos);
          if (items.isNotEmpty) {
            final itemPayloads = items.map((it) {
              final m = Map<String, dynamic>.from(it);
              m['branch_id'] = branchId;
              m.remove('id');
              return m;
            }).toList();
            final itemsUri = Uri.parse('${config.supabaseUrl}/rest/v1/sales_return_items');
            final resItems = await _safePost(
              itemsUri,
              headers: config.restHeaders,
              payloads: itemPayloads,
              tableName: 'sales_return_items',
              timeout: const Duration(seconds: 8),
            );
            itemsOk = resItems.statusCode < 400;
          }

          if (itemsOk) {
            await db.rawUpdate('UPDATE sales_return_invoices SET is_synced = 1 WHERE entry_no IN ($placeholders)', returnNos);
          }
        }
      }
      updateCategoryProgress('sales_returns', processed: totalInDb, total: totalInDb, state: CategorySyncState.completed);
    } catch (e) {
      debugPrint('Sales returns sync error: $e');
    }
  }

  Future<void> _syncPurchaseReturns() async {
    try {
      final db = await DbHelper.instance.database;
      final totalInDb = (await db.rawQuery('SELECT COUNT(*) as cnt FROM purchase_return_entries')).first['cnt'] as int? ?? 0;
      final returns = await db.query('purchase_return_entries', where: 'is_synced = 0 OR is_synced IS NULL', limit: 200);
      final config = ServerConfigService.instance;
      final branchId = config.storeBranchId;

      if (returns.isNotEmpty) {
        final payloads = returns.map((r) {
          final m = Map<String, dynamic>.from(r);
          m['branch_id'] = branchId;
          m.remove('is_synced');
          return m;
        }).toList();

        final uri = Uri.parse('${config.supabaseUrl}/rest/v1/purchase_return_entries?on_conflict=entry_no,terminal_id');
        final res = await _safePost(
          uri,
          headers: config.restHeaders,
          payloads: payloads,
          tableName: 'purchase_return_entries',
          timeout: const Duration(seconds: 8),
        );

        final entryNos = returns.map((e) => e['entry_no']?.toString()).where((no) => no != null && no.isNotEmpty).cast<String>().toList();
        bool itemsOk = true;

        if (res.statusCode < 400 && entryNos.isNotEmpty) {
          final placeholders = List.filled(entryNos.length, '?').join(',');
          final items = await db.rawQuery('SELECT * FROM purchase_return_items WHERE entry_no IN ($placeholders)', entryNos);
          if (items.isNotEmpty) {
            final itemPayloads = items.map((it) {
              final m = Map<String, dynamic>.from(it);
              m['branch_id'] = branchId;
              m.remove('id');
              return m;
            }).toList();
            final itemsUri = Uri.parse('${config.supabaseUrl}/rest/v1/purchase_return_items');
            final resItems = await _safePost(
              itemsUri,
              headers: config.restHeaders,
              payloads: itemPayloads,
              tableName: 'purchase_return_items',
              timeout: const Duration(seconds: 8),
            );
            itemsOk = resItems.statusCode < 400;
          }

          if (itemsOk) {
            await db.rawUpdate('UPDATE purchase_return_entries SET is_synced = 1 WHERE entry_no IN ($placeholders)', entryNos);
          }
        }
      }
      updateCategoryProgress('purchase_returns', processed: totalInDb, total: totalInDb, state: CategorySyncState.completed);
    } catch (e) {
      debugPrint('Purchase returns sync error: $e');
    }
  }

  Future<void> _syncStockAdjustments() async {
    try {
      final db = await DbHelper.instance.database;
      final adjs = await db.query('stock_adjustments', where: 'is_synced = 0 OR is_synced IS NULL', limit: 200);
      final config = ServerConfigService.instance;
      final branchId = config.storeBranchId;

      if (adjs.isEmpty) return;
      final payloads = adjs.map((a) {
        final m = Map<String, dynamic>.from(a);
        m['branch_id'] = branchId;
        m.remove('is_synced');
        return m;
      }).toList();

      final uri = Uri.parse('${config.supabaseUrl}/rest/v1/stock_adjustments?on_conflict=entry_no,terminal_id');
      final res = await _safePost(
        uri,
        headers: config.restHeaders,
        payloads: payloads,
        tableName: 'stock_adjustments',
        timeout: const Duration(seconds: 8),
      );

      if (res.statusCode < 400) {
        await db.rawUpdate('UPDATE stock_adjustments SET is_synced = 1');
      }

      final adjNos = adjs.map((e) => e['entry_no']?.toString()).where((no) => no != null && no.isNotEmpty).cast<String>().toList();
      if (adjNos.isNotEmpty) {
        final placeholders = List.filled(adjNos.length, '?').join(',');
        final items = await db.rawQuery('SELECT * FROM stock_adjustment_items WHERE adjustment_no IN ($placeholders)', adjNos);
        if (items.isNotEmpty) {
          final itemPayloads = items.map((it) {
            final m = Map<String, dynamic>.from(it);
            m['branch_id'] = branchId;
            m.remove('id');
            return m;
          }).toList();
          final itemsUri = Uri.parse('${config.supabaseUrl}/rest/v1/stock_adjustment_items');
          await _safePost(
            itemsUri,
            headers: config.restHeaders,
            payloads: itemPayloads,
            tableName: 'stock_adjustment_items',
            timeout: const Duration(seconds: 8),
          );
        }
      }
    } catch (e) {
      debugPrint('Stock adjustments sync error: $e');
    }
  }

  Future<void> _syncStockWriteOffs() async {
    try {
      final db = await DbHelper.instance.database;
      final writeOffs = await db.query('stock_write_offs', where: 'is_synced = 0 OR is_synced IS NULL', limit: 200);
      final config = ServerConfigService.instance;
      final branchId = config.storeBranchId;

      if (writeOffs.isEmpty) return;
      final payloads = writeOffs.map((w) {
        final m = Map<String, dynamic>.from(w);
        m['branch_id'] = branchId;
        m.remove('is_synced');
        return m;
      }).toList();

      final uri = Uri.parse('${config.supabaseUrl}/rest/v1/stock_write_offs');
      final res = await _safePost(
        uri,
        headers: config.restHeaders,
        payloads: payloads,
        tableName: 'stock_write_offs',
        timeout: const Duration(seconds: 8),
      );
      if (res.statusCode < 400) {
        await db.rawUpdate('UPDATE stock_write_offs SET is_synced = 1');
      }
    } catch (e) {
      debugPrint('Stock write offs sync error: $e');
    }
  }

  Future<void> _syncFinancialVouchers() async {
    try {
      final db = await DbHelper.instance.database;
      final config = ServerConfigService.instance;
      final branchId = config.storeBranchId;

      final voucherTables = ['patient_payments', 'supplier_payments', 'supplier_credit_notes'];
      for (var tName in voucherTables) {
        final rows = await db.query(tName, where: 'is_synced = 0 OR is_synced IS NULL');
        if (rows.isNotEmpty) {
          final payloads = rows.map((r) {
            final m = Map<String, dynamic>.from(r);
            m['branch_id'] = branchId;
            m['updated_at'] = DateTime.now().toIso8601String();
            m.remove('is_synced');
            return m;
          }).toList();
          final uri = Uri.parse('${config.supabaseUrl}/rest/v1/$tName?on_conflict=id');
          final res = await _safePost(
            uri,
            headers: config.restHeaders,
            payloads: payloads,
            tableName: tName,
            timeout: const Duration(seconds: 8),
          );
          if (res.statusCode < 400) {
            final ids = rows.map((r) => r['id']?.toString()).where((id) => id != null && id.isNotEmpty).toList();
            if (ids.isNotEmpty) {
              final placeholders = List.filled(ids.length, '?').join(',');
              await db.rawUpdate('UPDATE $tName SET is_synced = 1 WHERE id IN ($placeholders)', ids);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Financial vouchers sync error: $e');
    }
  }

  Future<void> _syncPrescriptions() async {
    try {
      final db = await DbHelper.instance.database;
      final prescriptions = await db.query('prescriptions', where: 'is_synced = 0 OR is_synced IS NULL', limit: 200);
      final config = ServerConfigService.instance;
      final branchId = config.storeBranchId;

      if (prescriptions.isEmpty) return;

      final pPayloads = prescriptions.map((p) {
        final m = Map<String, dynamic>.from(p);
        m['branch_id'] = branchId;
        m['updated_at'] = DateTime.now().toIso8601String();
        m.remove('is_synced');
        return m;
      }).toList();

      final uri = Uri.parse('${config.supabaseUrl}/rest/v1/prescriptions?on_conflict=id');
      final res = await _safePost(
        uri,
        headers: config.restHeaders,
        payloads: pPayloads,
        tableName: 'prescriptions',
        timeout: const Duration(seconds: 8),
      );
      if (res.statusCode < 400) {
        final rxIds = prescriptions.map((p) => p['id']?.toString() ?? '').where((id) => id.isNotEmpty).toList();
        if (rxIds.isNotEmpty) {
          final placeholders = List.filled(rxIds.length, '?').join(',');
          final items = await db.rawQuery('SELECT * FROM prescription_items WHERE prescription_id IN ($placeholders)', rxIds);
          if (items.isNotEmpty) {
            final itemPayloads = items.map((it) {
              return {
                'id': it['id']?.toString() ?? '',
                'prescription_id': it['prescription_id']?.toString() ?? '',
                'name': it['name']?.toString() ?? '',
                'qty': (it['qty'] as num?)?.toDouble() ?? 1.0,
                'branch_id': branchId,
              };
            }).toList();
            final itemsUri = Uri.parse('${config.supabaseUrl}/rest/v1/prescription_items?on_conflict=id');
            await _safePost(
              itemsUri,
              headers: config.restHeaders,
              payloads: itemPayloads,
              tableName: 'prescription_items',
              timeout: const Duration(seconds: 8),
            );
          }
          await db.rawUpdate('UPDATE prescriptions SET is_synced = 1 WHERE id IN ($placeholders)', rxIds);
        }
      }
    } catch (e) {
      debugPrint('Prescriptions sync error: $e');
    }
  }

  Future<void> _syncStaffUsers() async {
    try {
      final db = await DbHelper.instance.database;
      final staffList = await db.query('staff', where: 'is_synced = 0 OR is_synced IS NULL');
      if (staffList.isEmpty) return;
      final config = ServerConfigService.instance;
      final branchId = config.storeBranchId;

      final payloads = staffList.map((s) {
        return {
          'id': s['id']?.toString() ?? '',
          'name': s['name']?.toString() ?? '',
          'role': s['role']?.toString() ?? 'CASHIER',
          'pin_hash': s['code']?.toString() ?? '',
          'is_active': _toInt(s['is_active'], 1),
          'branch_id': branchId,
        };
      }).toList();

      final uri = Uri.parse('${config.supabaseUrl}/rest/v1/staff_users?on_conflict=id');
      final res = await _safePost(
        uri,
        headers: config.restHeaders,
        payloads: payloads,
        tableName: 'staff_users',
        timeout: const Duration(seconds: 8),
      );
      if (res.statusCode < 400) {
        final ids = staffList.map((s) => s['id']?.toString()).where((id) => id != null && id.isNotEmpty).toList();
        if (ids.isNotEmpty) {
          final placeholders = List.filled(ids.length, '?').join(',');
          await db.rawUpdate('UPDATE staff SET is_synced = 1 WHERE id IN ($placeholders)', ids);
        }
      }
    } catch (e) {
      debugPrint('Staff users sync error: $e');
    }
  }

  Future<void> _syncPurchaseOrders() async {
    try {
      final db = await DbHelper.instance.database;
      final pos = await db.query('order_confirmations', where: 'is_synced = 0 OR is_synced IS NULL');
      if (pos.isEmpty) return;
      final config = ServerConfigService.instance;
      final branchId = config.storeBranchId;

      final payloads = pos.map((p) {
        return {
          'id': p['id']?.toString() ?? '',
          'po_number': p['order_number']?.toString() ?? p['id']?.toString() ?? '',
          'supplier_name': p['supplier_name']?.toString() ?? '',
          'order_date': p['order_date']?.toString() ?? '',
          'status': p['status']?.toString() ?? 'PENDING',
          'total_amount': _toDouble(p['total_amount']),
          'branch_id': branchId,
        };
      }).toList();

      final uri = Uri.parse('${config.supabaseUrl}/rest/v1/purchase_orders?on_conflict=id');
      final res = await _safePost(
        uri,
        headers: config.restHeaders,
        payloads: payloads,
        tableName: 'purchase_orders',
        timeout: const Duration(seconds: 8),
      );
      if (res.statusCode < 400) {
        final ids = pos.map((p) => p['id']?.toString()).where((id) => id != null && id.isNotEmpty).toList();
        if (ids.isNotEmpty) {
          final placeholders = List.filled(ids.length, '?').join(',');
          await db.rawUpdate('UPDATE order_confirmations SET is_synced = 1 WHERE id IN ($placeholders)', ids);
        }
      }
    } catch (e) {
      debugPrint('Purchase orders sync error: $e');
    }
  }

  Future<void> _syncProductMappings() async {
    try {
      final db = await DbHelper.instance.database;
      final maps = await db.query('ProductMappings', where: 'is_synced = 0 OR is_synced IS NULL');
      if (maps.isEmpty) return;
      final config = ServerConfigService.instance;
      final branchId = config.storeBranchId;

      final payloads = maps.map((m) {
        return {
          'wholesaler_name': m['wholesaler_name']?.toString() ?? '',
          'supplier_item_name': m['supplier_item_name']?.toString() ?? '',
          'master_product_id': m['master_product_id']?.toString() ?? '',
          'branch_id': branchId,
          'updated_at': DateTime.now().toIso8601String(),
        };
      }).toList();

      final uri = Uri.parse('${config.supabaseUrl}/rest/v1/product_mappings');
      final res = await _safePost(
        uri,
        headers: config.restHeaders,
        payloads: payloads,
        tableName: 'product_mappings',
        timeout: const Duration(seconds: 8),
      );
      if (res.statusCode < 400) {
        await db.rawUpdate('UPDATE ProductMappings SET is_synced = 1');
      }
    } catch (e) {
      debugPrint('Product mappings sync error: $e');
    }
  }

  Future<void> _syncInvoiceEditHistory() async {
    try {
      final db = await DbHelper.instance.database;
      final logs = await db.query('edit_history_logs', where: 'is_synced = 0 OR is_synced IS NULL');
      if (logs.isEmpty) return;
      final config = ServerConfigService.instance;
      final branchId = config.storeBranchId;

      final payloads = logs.map((l) {
        final invNo = (l['original_entry_no'] ?? l['invoice_no'] ?? '').toString().trim();
        dynamic origSnap;
        dynamic editSnap;
        try {
          if (l['previous_items_json'] != null) origSnap = jsonDecode(l['previous_items_json'].toString());
        } catch (_) {}
        try {
          if (l['new_items_json'] != null) editSnap = jsonDecode(l['new_items_json'].toString());
        } catch (_) {}

        return {
          'invoice_no': invNo,
          'edited_by': l['edited_by']?.toString() ?? l['user_name']?.toString() ?? 'Admin',
          'edit_reason': l['reason_for_edit']?.toString() ?? l['details']?.toString() ?? 'Invoice Modified',
          'original_snapshot': origSnap,
          'edited_snapshot': editSnap,
          'branch_id': branchId,
          'timestamp': l['edit_timestamp']?.toString() ?? l['timestamp']?.toString() ?? DateTime.now().toIso8601String(),
        };
      }).toList();

      final uri = Uri.parse('${config.supabaseUrl}/rest/v1/invoice_edit_history');
      final res = await _safePost(
        uri,
        headers: config.restHeaders,
        payloads: payloads,
        tableName: 'invoice_edit_history',
        timeout: const Duration(seconds: 8),
      );
      if (res.statusCode < 400) {
        await db.rawUpdate('UPDATE edit_history_logs SET is_synced = 1');
      }
    } catch (e) {
      debugPrint('Invoice edit history sync error: $e');
    }
  }

  Future<void> _syncStockLedger() async {
    try {
      final db = await DbHelper.instance.database;
      final ledgerRows = await db.query('stock_ledger', where: 'is_synced = 0 OR is_synced IS NULL', limit: 300);
      if (ledgerRows.isEmpty) return;
      final config = ServerConfigService.instance;
      final branchId = config.storeBranchId;

      final payloads = ledgerRows.map((l) {
        return {
          'product_id': l['product_id']?.toString() ?? '',
          'batch_number': l['batch_number']?.toString() ?? '',
          'transaction_type': l['transaction_type']?.toString() ?? 'MOVEMENT',
          'reference_no': l['reference_no']?.toString() ?? '',
          'qty_in': _toInt(l['qty_in'], 0),
          'qty_out': _toInt(l['qty_out'], 0),
          'closing_balance': _toInt(l['closing_balance'], 0),
          'branch_id': branchId,
          'timestamp': l['timestamp']?.toString() ?? DateTime.now().toIso8601String(),
        };
      }).toList();

      final uri = Uri.parse('${config.supabaseUrl}/rest/v1/stock_ledger');
      final res = await _safePost(
        uri,
        headers: config.restHeaders,
        payloads: payloads,
        tableName: 'stock_ledger',
        timeout: const Duration(seconds: 8),
      );
      if (res.statusCode < 400) {
        await db.rawUpdate('UPDATE stock_ledger SET is_synced = 1');
      }
    } catch (e) {
      debugPrint('Stock ledger sync error: $e');
    }
  }

  Future<int> fetchRemoteCount(String endpoint, {String? queryFilter}) async {
    try {
      final config = ServerConfigService.instance;
      if (!config.isConnected || config.supabaseUrl.isEmpty || config.supabaseAnonKey.isEmpty) {
        return 0;
      }
      final branchParam = config.storeBranchId.isNotEmpty ? 'branch_id=eq.${config.storeBranchId}&' : '';

      String filterParam = queryFilter ?? '';
      if (filterParam.isEmpty) {
        if (endpoint == 'sales_invoices') {
          filterParam = 'entry_no=not.is.null&customer_acc=not.eq.Special%20Order';
        } else if (endpoint == 'purchase_entries') {
          filterParam = 'entry_no=not.is.null';
        } else if (['sales_return_invoices', 'purchase_return_entries', 'patient_payments', 'supplier_payments', 'supplier_credit_notes'].contains(endpoint)) {
          filterParam = 'is_deleted=eq.0';
        }
      }

      final extraStr = filterParam.isNotEmpty ? '&$filterParam' : '';
      var uri = Uri.parse('${config.supabaseUrl}/rest/v1/$endpoint?${branchParam}select=count$extraStr');
      var res = await http.get(uri, headers: {
        'apikey': config.supabaseAnonKey.trim(),
        'Authorization': 'Bearer ${config.supabaseAnonKey.trim()}',
        'Prefer': 'count=exact',
      }).timeout(const Duration(seconds: 8));

      if ((res.statusCode == 400 || res.statusCode == 404) && branchParam.isNotEmpty) {
        uri = Uri.parse('${config.supabaseUrl}/rest/v1/$endpoint?select=count$extraStr');
        res = await http.get(uri, headers: {
          'apikey': config.supabaseAnonKey.trim(),
          'Authorization': 'Bearer ${config.supabaseAnonKey.trim()}',
          'Prefer': 'count=exact',
        }).timeout(const Duration(seconds: 8));
      }

      if (res.statusCode == 200 || res.statusCode == 206) {
        final rangeHeader = res.headers['content-range'];
        if (rangeHeader != null && rangeHeader.contains('/')) {
          final totalStr = rangeHeader.split('/').last;
          final cnt = int.tryParse(totalStr);
          if (cnt != null && cnt > 0) return cnt;
        }
        if (jsonDecode(res.body) is List) {
          final List list = jsonDecode(res.body);
          if (list.isNotEmpty && list.first is Map && list.first.containsKey('count')) {
            return (list.first['count'] as int?) ?? 0;
          }
        }
      }
    } catch (_) {}
    return 0;
  }
  /// Paginated Range-chunked fetch & save for large datasets (e.g. 50,000+ items).
  /// Uses Range pagination (Range: 0-999, 1000-1999) and writes each 1,000-item chunk
  /// directly into local SQLite using batch transactions without HTTP timeouts or UI lag.
  Future<int> fetchAndSaveInChunks({
    required String endpoint,
    required String categoryId,
    required String progressLabel,
    required Future<void> Function(sql.DatabaseExecutor txn, List<dynamic> chunkItems) processChunk,
    String customFilter = '',
  }) async {
    final config = ServerConfigService.instance;
    final db = await DbHelper.instance.database;
    int totalSaved = 0;
    int offset = 0;
    const int limit = 1000;
    bool hasMore = true;
    int totalRemote = 0;

    while (hasMore && !_cancelRequested) {
      final branchParam = config.storeBranchId.isNotEmpty ? 'branch_id=eq.${config.storeBranchId}&' : '';
      final filterStr = customFilter.isNotEmpty ? '&$customFilter' : '';
      final uri = Uri.parse('${config.supabaseUrl}/rest/v1/$endpoint?${branchParam}select=*&limit=$limit&offset=$offset$filterStr');

      final headers = Map<String, String>.from(config.restHeaders);
      headers['Range'] = '$offset-${offset + limit - 1}';
      headers.remove('Prefer');

      http.Response? res;
      try {
        res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
        if (res.statusCode >= 400 && branchParam.isNotEmpty) {
          final fallbackUri = Uri.parse('${config.supabaseUrl}/rest/v1/$endpoint?select=*&limit=$limit&offset=$offset$filterStr');
          res = await http.get(fallbackUri, headers: headers).timeout(const Duration(seconds: 20));
        }
      } catch (e) {
        debugPrint('Chunk fetch error for $endpoint at offset $offset: $e');
        await Future.delayed(const Duration(milliseconds: 500));
        try {
          res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
        } catch (_) {}
      }

      if (res != null && (res.statusCode == 200 || res.statusCode == 206)) {
        final rangeHeader = res.headers['content-range'];
        if (rangeHeader != null && rangeHeader.contains('/')) {
          final parsedTotal = int.tryParse(rangeHeader.split('/').last) ?? 0;
          if (parsedTotal > totalRemote) {
            totalRemote = parsedTotal;
          }
        }

        final List<dynamic> items = res.body.length > 10240
            ? await compute(_parseJsonListIsolate, res.body)
            : (jsonDecode(res.body) as List<dynamic>);

        if (items.isEmpty) {
          hasMore = false;
        } else {
          await db.transaction((txn) async {
            await processChunk(txn, items);
          });

          totalSaved += items.length;
          offset += items.length;

          final displayTotal = totalRemote > 0 ? totalRemote : totalSaved;
          _updateDynamicProgress(items.length, '$progressLabel ($totalSaved/$displayTotal)');
          updateCategoryProgress(categoryId, processed: totalSaved, total: displayTotal, state: CategorySyncState.transferring);

          if (items.length < limit) {
            hasMore = false;
          }
        }
      } else {
        hasMore = false;
      }
      await Future.delayed(Duration.zero);
    }

    updateCategoryProgress(categoryId, processed: totalSaved, total: totalSaved > 0 ? totalSaved : totalRemote, state: CategorySyncState.completed);
    return totalSaved;
  }

  Future<void> _saveProductMasterChunk(sql.DatabaseExecutor txn, List<dynamic> chunk) async {
    final chunkProdIds = chunk
        .map((e) => (e is Map<String, dynamic>) ? (e['id']?.toString() ?? '') : '')
        .where((id) => id.isNotEmpty)
        .toList();

    Set<String> unsyncedIds = {};
    if (chunkProdIds.isNotEmpty) {
      final placeholders = List.filled(chunkProdIds.length, '?').join(',');
      final unsyncedRes = await txn.query(
        'product_master',
        columns: ['id'],
        where: 'id IN ($placeholders) AND (is_synced = 0 OR is_synced IS NULL)',
        whereArgs: chunkProdIds,
      );
      unsyncedIds = unsyncedRes.map((r) => r['id'].toString()).toSet();
    }

    final batch = txn.batch();
    for (var item in chunk) {
      if (item is Map<String, dynamic>) {
        final prodName = item['product_name']?.toString() ?? item['name']?.toString() ?? '';
        final prodId = item['id']?.toString() ?? '';
        if (prodName.isEmpty || prodId.isEmpty) continue;

        if (unsyncedIds.contains(prodId)) continue;

        batch.insert('product_master', {
          'id': prodId,
          'name': prodName,
          'generic_name': item['generic_name']?.toString() ?? '',
          'category_id': item['category_id']?.toString() ?? '',
          'sub_category_id': item['sub_category_id']?.toString() ?? '',
          'manufacturer_id': item['manufacturer_id']?.toString() ?? '',
          'rack_id': item['rack_id']?.toString() ?? '',
          'hsn_code': item['hsn_code']?.toString() ?? '',
          'gst_percent': _parseGstPercent(item, 12.0),
          's_disc_percent': _parseDiscPercent(item, 0.0),
          'schedule': item['schedule']?.toString() ?? 'H',
          'reorder_level': _toInt(item['reorder_level'], 10),
          'max_level': _toInt(item['max_level'], 100),
          'unit': item['unit']?.toString() ?? 'Strip',
          'packing': _toInt(item['packing'], 10),
          'mrp': _toDouble(item['mrp'], 0.0),
          'purchase_rate': _toDouble(item['purchase_rate'], 0.0),
          'sale_rate': _toDouble(item['selling_price'] ?? item['sale_rate'], 0.0),
          'patent': item['patent']?.toString() ?? '',
          'barcode': item['barcode']?.toString() ?? '',
          'is_controlled': _toInt(item['is_controlled'], 0),
          'is_banned': _toInt(item['is_banned'], 0),
          'is_nrx': _toInt(item['is_nrx'], 0),
          'is_active': _toInt(item['is_active'], 1),
          'is_disc_locked': _toInt(item['is_disc_locked'], 0),
          'preferred_wholesale': item['preferred_wholesale']?.toString() ?? '',
          'lead_time': _toInt(item['lead_time'], 2),
          'is_synced': 1,
          'updated_at': item['updated_at']?.toString() ?? DateTime.now().toIso8601String(),
        }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> _saveStockBatchesChunk(sql.DatabaseExecutor txn, List<dynamic> chunk) async {
    final chunkProdIds = chunk
        .map((e) => (e is Map<String, dynamic>) ? (e['product_id']?.toString() ?? '') : '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    Set<String> unsyncedBatchKeys = {};
    if (chunkProdIds.isNotEmpty) {
      final placeholders = List.filled(chunkProdIds.length, '?').join(',');
      final unsyncedRes = await txn.query(
        'stock_batches',
        columns: ['product_id', 'batch_number'],
        where: 'product_id IN ($placeholders) AND (is_synced = 0 OR is_synced IS NULL)',
        whereArgs: chunkProdIds,
      );
      unsyncedBatchKeys = unsyncedRes
          .map((r) => "${r['product_id']}_${r['batch_number'].toString().trim().toLowerCase()}")
          .toSet();
    }

    final batch = txn.batch();
    for (var item in chunk) {
      if (item is Map<String, dynamic>) {
        final prodId = item['product_id']?.toString() ?? '';
        final batchNo = item['batch_number']?.toString() ?? '';
        if (prodId.isEmpty || batchNo.isEmpty) continue;

        final key = "${prodId}_${batchNo.trim().toLowerCase()}";
        if (unsyncedBatchKeys.contains(key)) continue;

        batch.delete(
          'stock_batches',
          where: 'product_id = ? AND LOWER(TRIM(batch_number)) = LOWER(TRIM(?))',
          whereArgs: [prodId, batchNo],
        );

        batch.insert('stock_batches', {
          'product_id': prodId,
          'batch_number': batchNo,
          'expiry_date': item['expiry_date']?.toString() ?? '',
          'mfg_date': item['mfg_date']?.toString() ?? '',
          'current_stock': _toInt(item['current_quantity'] ?? item['current_stock'], 0),
          'purchase_rate': _toDouble(item['purchase_rate'], 0.0),
          'landing_cost': _toDouble(item['landing_cost'], _toDouble(item['purchase_rate'])),
          'mrp': _toDouble(item['mrp'], 0.0),
          'sale_rate': _toDouble(item['selling_rate'] ?? item['sale_rate'], 0.0),
          's_disc_percent': _parseDiscPercent(item, 0.0),
          'gst_percent': _parseGstPercent(item, 12.0),
          'rack': item['rack']?.toString() ?? '',
          'supplier_name': item['supplier_name']?.toString() ?? '',
          'packing': _toInt(item['packing'], 1),
          'is_active': _toInt(item['is_active'], 1),
          'financial_year': item['financial_year']?.toString() ?? '',
          'is_synced': 1,
        }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
      }
    }
    await batch.commit(noResult: true);
  }

  Future<bool> _pullRemoteData({bool forceFull = false}) async {
    if (!_isReady) return false;
    bool pulledNewData = false;
    try {
      final config = ServerConfigService.instance;
      final db = await DbHelper.instance.database;

      final String timeFilter = (!forceFull && _lastSyncTime != null)
          ? '&or=(created_at.gt.${_lastSyncTime!.toUtc().toIso8601String()},updated_at.gt.${_lastSyncTime!.toUtc().toIso8601String()})'
          : '';

      Future<List<dynamic>> fetchRows(String endpoint, {String? customFilter}) => fetchAllRows(endpoint, timeFilter: customFilter ?? timeFilter);

      void setPullProgress(double progress, String statusMsg) {
        if (!_isExportMode && progress > _syncProgress) {
          _syncProgress = progress;
        }
        _syncStatusMessage = statusMsg;
        notifyListeners();
      }

      // Reset category trackers to queued state for live import progress
      for (var cat in _categorySyncStatuses) {
        cat.state = CategorySyncState.queued;
        cat.processedCount = 0;
      }
      notifyListeners();

      // Pre-fetch remote row counts for selected endpoints in parallel
      final remoteCounts = await Future.wait([
        _isCategorySelected('products') ? fetchRemoteCount('product_master') : Future.value(0),
        _isCategorySelected('batches') ? fetchRemoteCount('stock_batches') : Future.value(0),
        _isCategorySelected('patients') ? fetchRemoteCount('patients') : Future.value(0),
        _isCategorySelected('sales') ? fetchRemoteCount('sales_invoices') : Future.value(0),
        _isCategorySelected('sales_returns') ? fetchRemoteCount('sales_return_invoices') : Future.value(0),
        _isCategorySelected('purchases') ? fetchRemoteCount('purchase_entries') : Future.value(0),
        _isCategorySelected('purchase_returns') ? fetchRemoteCount('purchase_return_entries') : Future.value(0),
        _isCategorySelected('suppliers_doctors') ? fetchRemoteCount('suppliers') : Future.value(0),
        _isCategorySelected('suppliers_doctors') ? fetchRemoteCount('doctors') : Future.value(0),
      ]);

      int pRemoteCount = remoteCounts[0];
      int bRemoteCount = remoteCounts[1];
      int patRemoteCount = remoteCounts[2];
      int salRemoteCount = remoteCounts[3];
      int srRemoteCount = remoteCounts[4];
      int purRemoteCount = remoteCounts[5];
      int prRemoteCount = remoteCounts[6];
      int supDocRemoteCount = remoteCounts[7] + remoteCounts[8];

      // Local count queries to detect if cloud count > local count on startup/reconnection
      final pLocalCount = (await db.rawQuery('SELECT COUNT(*) as cnt FROM product_master')).first['cnt'] as int? ?? 0;
      final bLocalCount = (await db.rawQuery('SELECT COUNT(*) as cnt FROM stock_batches')).first['cnt'] as int? ?? 0;
      final salLocalCount = (await db.rawQuery('SELECT COUNT(*) as cnt FROM sales_invoices WHERE is_deleted = 0')).first['cnt'] as int? ?? 0;
      final purLocalCount = (await db.rawQuery('SELECT COUNT(*) as cnt FROM purchase_entries WHERE is_deleted = 0')).first['cnt'] as int? ?? 0;

      final String pFilter = (pRemoteCount > pLocalCount) ? '' : timeFilter;
      final String bFilter = (bRemoteCount > bLocalCount) ? '' : timeFilter;
      final String salFilter = (salRemoteCount > salLocalCount) ? '' : timeFilter;
      final String purFilter = (purRemoteCount > purLocalCount) ? '' : timeFilter;

      updateCategoryProgress('products', processed: 0, total: pRemoteCount, state: CategorySyncState.queued);
      updateCategoryProgress('batches', processed: 0, total: bRemoteCount, state: CategorySyncState.queued);
      updateCategoryProgress('sales', processed: 0, total: salRemoteCount, state: CategorySyncState.queued);
      updateCategoryProgress('purchases', processed: 0, total: purRemoteCount, state: CategorySyncState.queued);
      updateCategoryProgress('sales_returns', processed: 0, total: srRemoteCount, state: CategorySyncState.queued);
      updateCategoryProgress('purchase_returns', processed: 0, total: prRemoteCount, state: CategorySyncState.queued);
      updateCategoryProgress('patients', processed: 0, total: patRemoteCount, state: CategorySyncState.queued);
      updateCategoryProgress('suppliers_doctors', processed: 0, total: supDocRemoteCount, state: CategorySyncState.queued);

      _totalRowsToSync = pRemoteCount + bRemoteCount + patRemoteCount + salRemoteCount + srRemoteCount + purRemoteCount + prRemoteCount + supDocRemoteCount;
      if (_totalRowsToSync <= 0) _totalRowsToSync = 1;
      _processedRowsCount = 0;
      _syncStartTime = DateTime.now();
      notifyListeners();

      // Pre-fetch HTTP payloads in parallel background streams for lightweight endpoints
      final Future<List<dynamic>> patFuture = _isCategorySelected('patients') ? fetchRows('patients') : Future.value([]);
      final Future<List<dynamic>> salFuture = _isCategorySelected('sales') ? fetchRows('sales_invoices', customFilter: salFilter) : Future.value([]);
      final Future<List<dynamic>> purFuture = _isCategorySelected('purchases') ? fetchRows('purchase_entries', customFilter: purFilter) : Future.value([]);
      final Future<List<dynamic>> srFuture = _isCategorySelected('sales_returns') ? fetchRows('sales_return_invoices') : Future.value([]);
      final Future<List<dynamic>> prFuture = _isCategorySelected('purchase_returns') ? fetchRows('purchase_return_entries') : Future.value([]);

      // 0. Pull Master Tables (Doctors, Suppliers, Categories, Manufacturers, Racks, Generics, Accounts, Staff)
      if (_isCategorySelected('suppliers_doctors') || _isCategorySelected('products')) {
        updateCategoryProgress('suppliers_doctors', processed: 0, total: supDocRemoteCount, state: CategorySyncState.transferring);
        setPullProgress(0.02, 'Downloading Master Data (Doctors, Suppliers, Racks)...');
        final mTables = ['categories', 'manufacturers', 'racks', 'generics', 'suppliers', 'doctors', 'accounts', 'staff'];
        int supDocSaved = 0;
        for (var tName in mTables) {
          if (_cancelRequested) return false;
          try {
            final mRows = await fetchRows(tName);
            if (mRows.isNotEmpty) {
              await db.transaction((txn) async {
                final pragmaCols = await txn.rawQuery('PRAGMA table_info($tName)');
                final validCols = pragmaCols.map((c) => c['name']?.toString() ?? '').where((n) => n.isNotEmpty).toSet();

                for (var row in mRows) {
                  if (row is Map<String, dynamic>) {
                    final id = row['id']?.toString() ?? '';
                    final name = row['name']?.toString() ?? '';
                    if (id.isEmpty && name.isEmpty) continue;

                    if (validCols.isEmpty || validCols.contains('is_synced')) {
                      final unsyncedCheck = await txn.query(
                        tName,
                        columns: ['is_synced'],
                        where: 'id = ? AND (is_synced = 0 OR is_synced IS NULL)',
                        whereArgs: [id],
                        limit: 1,
                      );
                      if (unsyncedCheck.isNotEmpty) {
                        continue;
                      }
                    }

                    final m = Map<String, dynamic>.from(row);
                    m.remove('branch_id');
                    m.remove('created_at');
                    m.remove('updated_at');

                    final Map<String, dynamic> cleanM = {};
                    for (var entry in m.entries) {
                      if (validCols.isEmpty || validCols.contains(entry.key)) {
                        cleanM[entry.key] = entry.value;
                      }
                    }
                    if (validCols.isEmpty || validCols.contains('is_synced')) {
                      cleanM['is_synced'] = 1;
                    }
                    await txn.insert(tName, cleanM, conflictAlgorithm: sql.ConflictAlgorithm.replace);
                  }
                }
              });
              pulledNewData = true;
              if (tName == 'suppliers' || tName == 'doctors') {
                supDocSaved += mRows.length;
                _updateDynamicProgress(mRows.length, 'Importing $tName');
                updateCategoryProgress('suppliers_doctors', processed: supDocSaved, total: supDocRemoteCount > 0 ? supDocRemoteCount : supDocSaved, state: CategorySyncState.transferring);
              }
            }
          } catch (e) {
            debugPrint('Error pulling master table $tName: $e');
          }
        }
        updateCategoryProgress('suppliers_doctors', processed: supDocSaved, total: supDocSaved > 0 ? supDocSaved : supDocRemoteCount, state: CategorySyncState.completed);
      }

      // 1. Pull Product Master using Range-chunked pagination (1000 items per chunk)
      if (_isCategorySelected('products')) {
        updateCategoryProgress('products', processed: 0, total: pRemoteCount, state: CategorySyncState.transferring);
        try {
          await db.execute('DROP TRIGGER IF EXISTS ad_product_master_fts;');
          await db.execute('DROP TRIGGER IF EXISTS au_product_master_fts;');
          await db.execute('DROP TRIGGER IF EXISTS ai_product_master_fts;');
        } catch (_) {}

        final countSaved = await fetchAndSaveInChunks(
          endpoint: 'product_master',
          categoryId: 'products',
          progressLabel: 'Importing Registered Products',
          customFilter: pFilter,
          processChunk: _saveProductMasterChunk,
        );
        if (countSaved > 0) pulledNewData = true;

        try {
          await db.execute('''
            CREATE TRIGGER IF NOT EXISTS ai_product_master_fts AFTER INSERT ON product_master BEGIN
              INSERT INTO product_search_fts(id, name, generic_name, barcode, hsn_code, rack_id)
              VALUES (new.id, new.name, IFNULL(new.generic_name, ''), IFNULL(new.barcode, ''), IFNULL(new.hsn_code, ''), IFNULL(new.rack_id, ''));
            END;
          ''');
          await db.execute('''
            CREATE TRIGGER IF NOT EXISTS au_product_master_fts AFTER UPDATE OF name, generic_name, barcode, hsn_code, rack_id ON product_master BEGIN
              DELETE FROM product_search_fts WHERE id = old.id;
              INSERT INTO product_search_fts(id, name, generic_name, barcode, hsn_code, rack_id)
              VALUES (new.id, new.name, IFNULL(new.generic_name, ''), IFNULL(new.barcode, ''), IFNULL(new.hsn_code, ''), IFNULL(new.rack_id, ''));
            END;
          ''');
          await db.execute('''
            CREATE TRIGGER IF NOT EXISTS ad_product_master_fts AFTER DELETE ON product_master BEGIN
              DELETE FROM product_search_fts WHERE id = old.id;
            END;
          ''');

          if (countSaved > 0) {
            await db.execute('''
              INSERT INTO product_search_fts(id, name, generic_name, barcode, hsn_code, rack_id)
              SELECT id, name, IFNULL(generic_name, ''), IFNULL(barcode, ''), IFNULL(hsn_code, ''), IFNULL(rack_id, '')
              FROM product_master
              WHERE id NOT IN (SELECT id FROM product_search_fts);
            ''');
          }
        } catch (ftsErr) {
          debugPrint('Error finalizing product_search_fts post-pull: $ftsErr');
        }
      }

      // 2. Pull Stock Batches using Range-chunked pagination (1000 items per chunk)
      if (_isCategorySelected('batches')) {
        updateCategoryProgress('batches', processed: 0, total: bRemoteCount, state: CategorySyncState.transferring);
        final countSaved = await fetchAndSaveInChunks(
          endpoint: 'stock_batches',
          categoryId: 'batches',
          progressLabel: 'Importing Stock Batches',
          customFilter: bFilter,
          processChunk: _saveStockBatchesChunk,
        );
        if (countSaved > 0) {
          await db.rawDelete('''
            DELETE FROM stock_batches
            WHERE rowid NOT IN (
              SELECT MAX(rowid)
              FROM stock_batches
              GROUP BY product_id, LOWER(TRIM(batch_number))
            )
          ''');
          pulledNewData = true;
        }
      }

      // 3. Pull Customers / Patients
      updateCategoryProgress('patients', processed: 0, total: patRemoteCount, state: CategorySyncState.transferring);
      final patItems = await patFuture;
      final totalPat = patItems.length;
      if (totalPat > 0) {
        updateCategoryProgress('patients', processed: 0, total: totalPat, state: CategorySyncState.transferring);
        const chunkSize = 150;
        int savedPat = 0;
        for (var i = 0; i < totalPat; i += chunkSize) {
          if (_cancelRequested) return false;
          final end = (i + chunkSize < totalPat) ? i + chunkSize : totalPat;
          final chunk = patItems.sublist(i, end);
          await db.transaction((txn) async {
            for (var item in chunk) {
              if (item is Map<String, dynamic>) {
                final patId = item['id']?.toString() ?? '';
                if (patId.isEmpty) continue;

                // Protect local unsynced patient edits from cloud overwrite
                final unsyncedCheck = await txn.query(
                  'patients',
                  columns: ['is_synced'],
                  where: 'id = ? AND (is_synced = 0 OR is_synced IS NULL)',
                  whereArgs: [patId],
                  limit: 1,
                );
                if (unsyncedCheck.isNotEmpty) {
                  continue;
                }

                await txn.insert('patients', {
                  'id': patId,
                  'name': item['name']?.toString() ?? '',
                  'mobile': item['mobile']?.toString() ?? '',
                  'address': item['address']?.toString() ?? '',
                  'is_synced': 1,
                }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
              }
            }
          });
          savedPat += chunk.length;
          _updateDynamicProgress(chunk.length, 'Importing Patients & Customers');
          updateCategoryProgress('patients', processed: savedPat, total: totalPat, state: CategorySyncState.transferring);
          await Future.delayed(const Duration(milliseconds: 20));
        }
        pulledNewData = true;
      }
      updateCategoryProgress('patients', processed: totalPat, total: totalPat, state: CategorySyncState.completed);

      // 4. Pull Sales Invoices & Line Items
      updateCategoryProgress('sales', processed: 0, total: salRemoteCount, state: CategorySyncState.transferring);
      final salItems = await salFuture;
      final totalSal = salItems.length;
      if (totalSal > 0) {
        updateCategoryProgress('sales', processed: 0, total: totalSal, state: CategorySyncState.transferring);
        const chunkSize = 150;
        int savedSal = 0;
        for (var i = 0; i < totalSal; i += chunkSize) {
          if (_cancelRequested) return false;
          final end = (i + chunkSize < totalSal) ? i + chunkSize : totalSal;
          final chunk = salItems.sublist(i, end);
          await db.transaction((txn) async {
            for (var item in chunk) {
              if (item is Map<String, dynamic>) {
                final rawEntryNo = item['entry_no']?.toString() ?? item['invoice_no']?.toString() ?? '';
                if (rawEntryNo.isEmpty) continue;
                final dateStr = item['date']?.toString() ?? DateFormat('dd/MM/yyyy').format(DateTime.now());
                DateTime parsedDt;
                try {
                  parsedDt = DateTime.parse(dateStr);
                } catch (_) {
                  parsedDt = DateTime.tryParse(dateStr.replaceAll('/', '-')) ?? DateTime.now();
                }
                final computedFy = _calculateFY(parsedDt);
                final fyStr = (item['financial_year'] != null && item['financial_year'].toString().isNotEmpty)
                    ? item['financial_year'].toString()
                    : computedFy;
                final cleanNo = rawEntryNo.contains('_') ? rawEntryNo.substring(rawEntryNo.indexOf('_') + 1) : rawEntryNo;
                final entryNo = rawEntryNo.contains('_') ? rawEntryNo : "${fyStr}_$cleanNo";

                final pendingDel = await txn.query(
                  'pending_deletions',
                  where: 'table_name = ? AND (entry_no = ? OR entry_no = ? OR entry_no LIKE ?)',
                  whereArgs: ['sales_invoices', entryNo, cleanNo, "%_$cleanNo"],
                  limit: 1,
                );
                if (pendingDel.isNotEmpty && _toInt(item['is_deleted'], 0) == 0) {
                  continue; // Ignore incoming active cloud record if this entry is queued in pending_deletions!
                }

                final existing = await txn.query(
                  'sales_invoices',
                  columns: ['is_synced', 'is_deleted'],
                  where: 'entry_no = ? OR entry_no = ? OR invoice_no = ? OR invoice_no = ? OR entry_no LIKE ? OR invoice_no LIKE ?',
                  whereArgs: [entryNo, cleanNo, entryNo, cleanNo, "%_$cleanNo", "%_$cleanNo"],
                  limit: 1,
                );
                if (existing.isNotEmpty) {
                  final int isSynced = _toInt(existing.first['is_synced'], 1);
                  final int isDeletedLocally = _toInt(existing.first['is_deleted'], 0);
                  final int isDeletedRemotely = _toInt(item['is_deleted'], 0);

                  if (isSynced == 0) continue; // Protect local unsynced edits from cloud overwrite
                  if (isDeletedLocally == 1 && isDeletedRemotely == 0) {
                    continue; // Protect local deletion from being overwritten by active cloud record
                  }
                }

                final docVal = (item['doctor'] ?? item['doctor_name'] ?? item['dr_name'] ?? item['dr'] ?? item['doc_name'] ?? item['doc'] ?? '').toString().trim();
                final docRegVal = (item['doctor_reg_no'] ?? item['doc_reg_no'] ?? item['reg_no'] ?? '').toString().trim();

                await txn.insert('sales_invoices', {
                  'entry_no': entryNo,
                  'invoice_no': item['invoice_no']?.toString() ?? entryNo,
                  'date': dateStr,
                  'customer_name': item['customer_name']?.toString() ?? item['patient']?.toString() ?? '',
                  'patient': item['patient']?.toString() ?? item['customer_name']?.toString() ?? '',
                  'mobile': item['customer_phone']?.toString() ?? item['mobile']?.toString() ?? '',
                  'doctor': (docVal.isNotEmpty && docVal.toLowerCase() != 'unknown' && docVal.toLowerCase() != 'dr. unknown') ? docVal : 'D1',
                  'doctor_reg_no': docRegVal,
                  'sub_total': _toDouble(item['subtotal'] ?? item['sub_total']),
                  'total_amount': _toDouble(item['net_amount'] ?? item['grand_total'] ?? item['total_amount']),
                  'grand_total': _toDouble(item['net_amount'] ?? item['grand_total'] ?? item['total_amount']),
                  'discount': _toDouble(item['discount'] ?? item['discount_amount'] ?? item['disc_amt'] ?? item['dis_amt']),
                  'discount_percent': _toDouble(item['discount_percent'] ?? item['disc_percent'] ?? item['disc_per']),
                  'additional_discount': _toDouble(item['additional_discount']),
                  'other_charge': _toDouble(item['other_charge']),
                  'tax': _toDouble(item['tax_amount'] ?? item['tax']),
                  'round_off': _toDouble(item['round_off']),
                  'rcvd_amt': _toDouble(item['rcvd_amt']),
                  'payment_mode': item['payment_mode']?.toString() ?? 'CASH',
                  'payment_remarks': item['payment_remarks']?.toString() ?? '',
                  'secondary_acc': item['secondary_acc']?.toString() ?? '',
                  'secondary_amt': _toDouble(item['secondary_amt']),
                  'is_deleted': _toInt(item['is_deleted'], 0),
                  'is_paid': _toInt(item['is_paid'], 1),
                  'tax_type': item['tax_type']?.toString() ?? 'Non Gst',
                  'agent': item['agent']?.toString() ?? 'Admin',
                  'sales_return_amt': _toDouble(item['sales_return_amt']),
                  'order_type': _toInt(item['order_type'], 0),
                  'financial_year': fyStr,
                  'is_synced': 1,
                }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
              }
            }
          });
          savedSal += chunk.length;
          _updateDynamicProgress(chunk.length, 'Importing Sales Invoices');
          updateCategoryProgress('sales', processed: savedSal, total: totalSal, state: CategorySyncState.transferring);
          await Future.delayed(const Duration(milliseconds: 20));
        }
        pulledNewData = true;
      }

      final sItems = await fetchRows('sales_items');
      if (sItems.isNotEmpty) {
        final invRows = await db.query(
          'sales_invoices',
          columns: ['entry_no', 'invoice_no', 'is_synced'],
        );
        final Map<String, String> invMap = {};
        for (var r in invRows) {
          final isSynced = _toInt(r['is_synced'], 1);
          if (isSynced == 1) {
            final eNo = r['entry_no']?.toString() ?? '';
            final iNo = r['invoice_no']?.toString() ?? '';
            final cleanE = cleanEntryNo(eNo);
            final cleanI = cleanEntryNo(iNo);

            if (eNo.isNotEmpty) {
              invMap[eNo] = eNo;
              invMap[eNo.toLowerCase()] = eNo;
            }
            if (iNo.isNotEmpty) {
              invMap[iNo] = eNo;
              invMap[iNo.toLowerCase()] = eNo;
            }
            if (cleanE.isNotEmpty) {
              invMap[cleanE] = eNo;
              invMap["SALE-$cleanE"] = eNo;
              invMap["sale-$cleanE"] = eNo;
            }
            if (cleanI.isNotEmpty) {
              invMap[cleanI] = eNo;
              invMap["SALE-$cleanI"] = eNo;
              invMap["sale-$cleanI"] = eNo;
            }
            if (eNo.contains('_')) {
              final suff = eNo.substring(eNo.indexOf('_') + 1);
              if (suff.isNotEmpty) invMap[suff] = eNo;
            }
          }
        }

        const chunkSize = 150;
        final Set<String> clearedInvoices = {};
        final Set<String> insertedSalesItemSigs = {};

        for (var i = 0; i < sItems.length; i += chunkSize) {
          if (_cancelRequested) return false;
          final end = (i + chunkSize < sItems.length) ? i + chunkSize : sItems.length;
          final chunk = sItems.sublist(i, end);
          await db.transaction((txn) async {
            final batch = txn.batch();
            for (var item in chunk) {
              if (item is Map<String, dynamic>) {
                final invNo = item['invoice_no']?.toString() ?? '';
                final prodId = item['product_id']?.toString() ?? '';
                if (invNo.isEmpty) continue;

                final cleanInvNo = cleanEntryNo(invNo);
                final targetInvoiceEntryNo = invMap[invNo] ?? invMap[invNo.toLowerCase()] ?? invMap[cleanInvNo] ?? invMap["SALE-$cleanInvNo"];
                if (targetInvoiceEntryNo == null) continue;

                final batchVal = (item['batch_number'] ?? item['batch'] ?? item['batch_no'] ?? '').toString().trim();
                int itemQty = _toInt(item['quantity'] ?? item['qty'], 1);
                final pName = item['product_name']?.toString() ?? '';

                final itemKey = "${targetInvoiceEntryNo}_${prodId.isNotEmpty ? prodId : pName}_${batchVal.toLowerCase()}_$itemQty";
                if (insertedSalesItemSigs.contains(itemKey)) continue;

                if (!clearedInvoices.contains(targetInvoiceEntryNo)) {
                  clearedInvoices.add(targetInvoiceEntryNo);
                  final cleanTgt = cleanEntryNo(targetInvoiceEntryNo);
                  batch.delete(
                    'sales_items',
                    where: 'invoice_no = ? OR invoice_no = ? OR invoice_no LIKE ?',
                    whereArgs: [targetInvoiceEntryNo, cleanTgt, "%_$cleanTgt"],
                  );
                }
                insertedSalesItemSigs.add(itemKey);

                int parsedPacking = _toInt(item['packing'] ?? item['packin'] ?? item['pack_size'], 1);
                if (parsedPacking <= 0) parsedPacking = 1;

                double parsedMrp = _toDouble(item['mrp'] ?? item['mrp_price'] ?? 0.0);
                double sRateVal = _toDouble(item['s_rate'] ?? item['sale_rate'] ?? item['unit_price']);
                if (sRateVal <= 0 && parsedMrp > 0) sRateVal = (parsedMrp / parsedPacking);

                double pRateVal = _toDouble(item['purchase_rate']);
                double lCostVal = _toDouble(item['landing_cost'], pRateVal);

                double gstPctVal = _parseGstPercent(item, 12.0);
                double discPctVal = _parseDiscPercent(item, 0.0);
                double discAmtVal = _toDouble(item['disc_amt'] ?? item['discount_amount'] ?? item['disc_amount'] ?? item['dis_amt']);
                double totalVal = _toDouble(item['total_amount'] ?? item['total']);
                double profitVal = _toDouble(item['profit']);

                if (profitVal == 0.0 && totalVal > 0) {
                  double unitLandingCost = lCostVal > 0 ? (lCostVal / parsedPacking) : (pRateVal / parsedPacking);
                  profitVal = totalVal - (unitLandingCost * itemQty);
                }

                String expiryVal = (item['expiry_date'] ?? item['expiry'] ?? item['exp_date'] ?? item['exp'] ?? item['expdate'] ?? item['expiry_dt'] ?? '').toString().trim();
                String rackVal = item['rack']?.toString() ?? '';

                batch.insert('sales_items', {
                  'invoice_no': targetInvoiceEntryNo,
                  'product_id': prodId,
                  'product_name': item['product_name']?.toString() ?? '',
                  'extra': item['extra']?.toString() ?? '',
                  'batch_number': batchVal,
                  'expiry_date': expiryVal,
                  'qty': itemQty,
                  'quantity': itemQty,
                  'packin': parsedPacking,
                  'packing': parsedPacking,
                  'mrp': parsedMrp,
                  'purchase_rate': pRateVal,
                  'landing_cost': lCostVal,
                  'taxable_sp': _toDouble(item['taxable_sp'] ?? (sRateVal > 0 ? sRateVal : (parsedMrp / parsedPacking))),
                  's_rate': sRateVal,
                  'sale_rate': sRateVal,
                  'disc_percent': discPctVal,
                  'disc_amt': discAmtVal,
                  'gst_percent': gstPctVal,
                  'tax_percent': gstPctVal,
                  'gst_amt': _toDouble(item['gst_amt'] ?? item['tax_amount']),
                  'cgst_amt': _toDouble(item['cgst_amt']),
                  'sgst_amt': _toDouble(item['sgst_amt']),
                  'igst_amt': _toDouble(item['igst_amt']),
                  'total': totalVal,
                  'profit': profitVal,
                  'supplier_name': item['supplier_name']?.toString() ?? '',
                  'rack': rackVal,
                }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
              }
            }
            await batch.commit(noResult: true);
          });
          _updateDynamicProgress(chunk.length, 'Importing Sales Line Items');
          await Future.delayed(const Duration(milliseconds: 20));
        }
      }
      updateCategoryProgress('sales', processed: totalSal, total: totalSal, state: CategorySyncState.completed);

      // 5. Pull Sales Return Receipts
      updateCategoryProgress('sales_returns', processed: 0, total: srRemoteCount, state: CategorySyncState.transferring);
      final srItems = await srFuture;
      final totalSr = srItems.length;
      if (totalSr > 0) {
        updateCategoryProgress('sales_returns', processed: 0, total: totalSr, state: CategorySyncState.transferring);
        const chunkSize = 50;
        int savedSr = 0;
        for (var i = 0; i < totalSr; i += chunkSize) {
          if (_cancelRequested) return false;
          final end = (i + chunkSize < totalSr) ? i + chunkSize : totalSr;
          final chunk = srItems.sublist(i, end);
          await db.transaction((txn) async {
            for (var item in chunk) {
              if (item is Map<String, dynamic>) {
                final entryNo = item['entry_no']?.toString() ?? '';
                if (entryNo.isEmpty) continue;
                final cleanNo = entryNo.contains('_') ? entryNo.substring(entryNo.indexOf('_') + 1) : entryNo;

                final pendingDel = await txn.query(
                  'pending_deletions',
                  where: 'table_name = ? AND (entry_no = ? OR entry_no = ? OR entry_no LIKE ?)',
                  whereArgs: ['sales_return_invoices', entryNo, cleanNo, "%_$cleanNo"],
                  limit: 1,
                );
                if (pendingDel.isNotEmpty && _toInt(item['is_deleted'], 0) == 0) {
                  continue;
                }

                final existing = await txn.query(
                  'sales_return_invoices',
                  columns: ['is_synced', 'is_deleted'],
                  where: 'entry_no = ? OR entry_no = ?',
                  whereArgs: [entryNo, cleanNo],
                  limit: 1,
                );
                if (existing.isNotEmpty) {
                  final int isSynced = _toInt(existing.first['is_synced'], 1);
                  final int isDeletedLocally = _toInt(existing.first['is_deleted'], 0);
                  final int isDeletedRemotely = _toInt(item['is_deleted'], 0);
                  if (isSynced == 0) continue;
                  if (isDeletedLocally == 1 && isDeletedRemotely == 0) continue;
                }
                await txn.insert('sales_return_invoices', {
                  'entry_no': entryNo,
                  'date': item['date']?.toString() ?? '',
                  'customer_acc': item['customer_acc']?.toString() ?? '',
                  'patient': item['patient']?.toString() ?? '',
                  'doctor': item['doctor']?.toString() ?? '',
                  'sub_total': _toDouble(item['sub_total']),
                  'discount': _toDouble(item['discount']),
                  'tax': _toDouble(item['tax']),
                  'round_off': _toDouble(item['round_off']),
                  'grand_total': _toDouble(item['grand_total']),
                  'narration': item['narration']?.toString() ?? '',
                  'gst_mode': _toInt(item['gst_mode'], 1),
                  'original_invoice_no': item['original_invoice_no']?.toString() ?? '',
                  'is_deleted': _toInt(item['is_deleted'], 0),
                  'is_imported': 1,
                  'financial_year': item['financial_year']?.toString() ?? '',
                }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
              }
            }
          });
          savedSr += chunk.length;
          _updateDynamicProgress(chunk.length, 'Importing Sales Returns');
          updateCategoryProgress('sales_returns', processed: savedSr, total: totalSr, state: CategorySyncState.transferring);
        }
        pulledNewData = true;
      }

      final srLineItems = await fetchRows('sales_return_items');
      if (srLineItems.isNotEmpty) {
        final srRows = await db.query('sales_return_invoices', columns: ['entry_no', 'is_synced']);
        final Map<String, String> srMap = {};
        for (var r in srRows) {
          final isSynced = _toInt(r['is_synced'], 1);
          if (isSynced == 1) {
            final eNo = r['entry_no']?.toString() ?? '';
            if (eNo.isNotEmpty) srMap[eNo] = eNo;
            if (eNo.contains('_')) {
              final clean = eNo.substring(eNo.indexOf('_') + 1);
              if (clean.isNotEmpty) srMap[clean] = eNo;
            }
          }
        }

        final Set<String> clearedSalesReturns = {};
        await db.transaction((txn) async {
          for (var item in srLineItems) {
            if (item is Map<String, dynamic>) {
              final retNo = item['return_no']?.toString() ?? '';
              if (retNo.isEmpty) continue;
              final targetRetNo = srMap[retNo];
              if (targetRetNo == null) continue;

              if (!clearedSalesReturns.contains(targetRetNo)) {
                clearedSalesReturns.add(targetRetNo);
                final cleanTgt = cleanEntryNo(targetRetNo);
                await txn.delete(
                  'sales_return_items',
                  where: 'return_no = ? OR return_no = ? OR return_no LIKE ?',
                  whereArgs: [targetRetNo, cleanTgt, "%_$cleanTgt"],
                );
              }

              await txn.insert('sales_return_items', {
                'return_no': targetRetNo,
                'product_id': item['product_id']?.toString() ?? '',
                'product_name': item['product_name']?.toString() ?? '',
                'batch_number': item['batch_number']?.toString() ?? '',
                'expiry_date': item['expiry_date']?.toString() ?? '',
                'quantity': _toInt(item['quantity'], 1),
                'mrp': _toDouble(item['mrp']),
                'sale_rate': _toDouble(item['sale_rate']),
                'disc_percent': _toDouble(item['disc_percent']),
                'disc_amt': _toDouble(item['disc_amt']),
                'hsn_code': item['hsn_code']?.toString() ?? '',
                'total': _toDouble(item['total']),
                'purchase_rate': _toDouble(item['purchase_rate']),
                'landing_cost': _toDouble(item['landing_cost']),
                'supplier_name': item['supplier_name']?.toString() ?? '',
                'packing': _toInt(item['packing'], 1),
                'gst_percent': _toDouble(item['gst_percent'], 12.0),
              }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
            }
          }
        });
      }
      updateCategoryProgress('sales_returns', processed: totalSr, total: totalSr, state: CategorySyncState.completed);

      // 6. Pull Purchase Inward Entries & Items
      updateCategoryProgress('purchases', processed: 0, total: purRemoteCount, state: CategorySyncState.transferring);
      final purItems = await purFuture;
      final totalPur = purItems.length;
      if (totalPur > 0) {
        updateCategoryProgress('purchases', processed: 0, total: totalPur, state: CategorySyncState.transferring);
        const chunkSize = 50;
        int savedPur = 0;
        for (var i = 0; i < totalPur; i += chunkSize) {
          if (_cancelRequested) return false;
          final end = (i + chunkSize < totalPur) ? i + chunkSize : totalPur;
          final chunk = purItems.sublist(i, end);
          await db.transaction((txn) async {
            for (var item in chunk) {
              if (item is Map<String, dynamic>) {
                final rawEntryNo = item['entry_no']?.toString() ?? '';
                if (rawEntryNo.isEmpty) continue;
                final dateStr = item['date']?.toString() ?? DateFormat('dd/MM/yyyy').format(DateTime.now());
                DateTime parsedDt;
                try {
                  parsedDt = DateTime.parse(dateStr);
                } catch (_) {
                  parsedDt = DateTime.tryParse(dateStr.replaceAll('/', '-')) ?? DateTime.now();
                }
                final computedFy = _calculateFY(parsedDt);
                final fyStr = (item['financial_year'] != null && item['financial_year'].toString().isNotEmpty)
                    ? item['financial_year'].toString()
                    : computedFy;
                final cleanNo = rawEntryNo.contains('_') ? rawEntryNo.substring(rawEntryNo.indexOf('_') + 1) : rawEntryNo;
                final entryNo = rawEntryNo.contains('_') ? rawEntryNo : "${fyStr}_$cleanNo";

                final pendingDel = await txn.query(
                  'pending_deletions',
                  where: 'table_name = ? AND (entry_no = ? OR entry_no = ? OR entry_no LIKE ?)',
                  whereArgs: ['purchase_entries', entryNo, cleanNo, "%_$cleanNo"],
                  limit: 1,
                );
                if (pendingDel.isNotEmpty && _toInt(item['is_deleted'], 0) == 0) {
                  continue; // Ignore incoming active cloud record if this entry is queued in pending_deletions!
                }

                final existing = await txn.query(
                  'purchase_entries',
                  columns: ['is_synced', 'is_deleted'],
                  where: 'entry_no = ? OR entry_no = ? OR sup_inv_no = ? OR sup_inv_no = ? OR entry_no LIKE ?',
                  whereArgs: [entryNo, cleanNo, entryNo, cleanNo, "%_$cleanNo"],
                  limit: 1,
                );
                if (existing.isNotEmpty) {
                  final int isSynced = _toInt(existing.first['is_synced'], 1);
                  final int isDeletedLocally = _toInt(existing.first['is_deleted'], 0);
                  final int isDeletedRemotely = _toInt(item['is_deleted'], 0);

                  if (isSynced == 0) continue; // Protect local unsynced edits from cloud overwrite
                  if (isDeletedLocally == 1 && isDeletedRemotely == 0) {
                    continue; // Protect local deletion from being overwritten by active cloud record
                  }
                }

                final String remoteSupInv = cleanInvoiceNo((item['sup_inv_no'] ?? item['invoice_no'])?.toString() ?? '');
                final String remoteDoneBy = item['done_by']?.toString() ?? '';
                final double remoteInvTot = _toDouble(item['inv_total'] ?? item['grand_total'] ?? item['net_amount']);

                String finalSupInv = remoteSupInv.isNotEmpty 
                    ? remoteSupInv 
                    : (existing.isNotEmpty ? (existing.first['sup_inv_no']?.toString() ?? entryNo) : entryNo);
                String finalDoneBy = remoteDoneBy.isNotEmpty 
                    ? remoteDoneBy 
                    : (existing.isNotEmpty ? (existing.first['done_by']?.toString() ?? '') : '');
                double finalInvTotal = remoteInvTot > 0 
                    ? remoteInvTot 
                    : (existing.isNotEmpty ? _toDouble(existing.first['inv_total']) : 0.0);

                await txn.insert('purchase_entries', {
                  'entry_no': entryNo,
                  'sup_inv_no': finalSupInv,
                  'sup_inv_date': item['sup_inv_date']?.toString() ?? '',
                  'date': dateStr,
                  'supplier_name': item['supplier_name']?.toString() ?? '',
                  'done_by': finalDoneBy,
                  'sub_total': _toDouble(item['subtotal'] ?? item['sub_total']),
                  'discount': _toDouble(item['discount_amount'] ?? item['discount']),
                  'other_charge': _toDouble(item['other_charge']),
                  'round_off': _toDouble(item['round_off']),
                  'grand_total': _toDouble(item['net_amount'] ?? item['grand_total'] ?? item['inv_total']),
                  'inv_total': finalInvTotal,
                  'remarks': item['remarks']?.toString() ?? '',
                  'payment_status': _toInt(item['payment_status'], 0),
                  'payment_mode': item['payment_mode']?.toString() ?? 'CREDIT',
                  'payment_remarks': item['payment_remarks']?.toString() ?? '',
                  'payment_date': item['payment_date']?.toString() ?? '',
                  'paid_amount': _toDouble(item['paid_amount']),
                  'days': _toInt(item['days'], 0),
                  'is_deleted': _toInt(item['is_deleted'], 0),
                  'tax_type': item['tax_type']?.toString() ?? 'Gst',
                  'financial_year': fyStr,
                  'is_synced': 1,
                }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
              }
            }
          });
          savedPur += chunk.length;
          _updateDynamicProgress(chunk.length, 'Importing Purchase Entries');
          updateCategoryProgress('purchases', processed: savedPur, total: totalPur, state: CategorySyncState.transferring);
        }
        pulledNewData = true;
      }

      final purLineItems = await fetchRows('purchase_items');
      if (purLineItems.isNotEmpty) {
        final purRows = await db.query('purchase_entries', columns: ['entry_no', 'sup_inv_no', 'is_synced']);
        final Map<String, String> purMap = {};
        for (var r in purRows) {
          final isSynced = _toInt(r['is_synced'], 1);
          if (isSynced == 1) {
            final eNo = r['entry_no']?.toString() ?? '';
            final sNo = r['sup_inv_no']?.toString() ?? '';
            if (eNo.isNotEmpty) purMap[eNo] = eNo;
            if (sNo.isNotEmpty && eNo.isNotEmpty) purMap[sNo] = eNo;
            if (eNo.contains('_')) {
              final clean = eNo.substring(eNo.indexOf('_') + 1);
              if (clean.isNotEmpty) purMap[clean] = eNo;
            }
          }
        }

        const chunkSize = 100;
        final Set<String> clearedPurEntries = {};
        final Set<String> insertedPurItemSigs = {};

        for (var i = 0; i < purLineItems.length; i += chunkSize) {
          if (_cancelRequested) return false;
          final end = (i + chunkSize < purLineItems.length) ? i + chunkSize : purLineItems.length;
          final chunk = purLineItems.sublist(i, end);
          await db.transaction((txn) async {
            final batch = txn.batch();
            for (var item in chunk) {
              if (item is Map<String, dynamic>) {
                final entryNo = item['entry_no']?.toString() ?? '';
                if (entryNo.isEmpty) continue;

                final targetEntryNo = purMap[entryNo];
                if (targetEntryNo == null) continue;

                final prodId = item['product_id']?.toString() ?? '';
                final pName = item['product_name']?.toString() ?? '';
                final batchVal = (item['batch_number'] ?? item['batch'] ?? '').toString().trim();
                final int itemQty = _toInt(item['quantity'] ?? item['qty'], 1);

                final itemKey = "${targetEntryNo}_${prodId.isNotEmpty ? prodId : pName}_${batchVal.toLowerCase()}_$itemQty";
                if (insertedPurItemSigs.contains(itemKey)) continue;

                if (!clearedPurEntries.contains(targetEntryNo)) {
                  clearedPurEntries.add(targetEntryNo);
                  final cleanTgt = cleanEntryNo(targetEntryNo);
                  batch.delete(
                    'purchase_items',
                    where: 'entry_no = ? OR entry_no = ? OR entry_no LIKE ?',
                    whereArgs: [targetEntryNo, cleanTgt, "%_$cleanTgt"],
                  );
                }
                insertedPurItemSigs.add(itemKey);

                batch.insert('purchase_items', {
                  'entry_no': targetEntryNo,
                  'product_id': item['product_id']?.toString() ?? '',
                  'product_name': item['product_name']?.toString() ?? '',
                  'extra': item['extra']?.toString() ?? '',
                  'batch': item['batch_number']?.toString() ?? item['batch']?.toString() ?? '',
                  'expiry': item['expiry_date']?.toString() ?? item['expiry']?.toString() ?? '',
                  'qty': _toInt(item['quantity'] ?? item['qty'], 1),
                  'f_qty': _toInt(item['f_qty'], 0),
                  'packin': _toInt(item['packing'], 1),
                  'mrp': _toDouble(item['mrp']),
                  'p_rate': _toDouble(item['unit_price'] ?? item['p_rate']),
                  'gross': _toDouble(item['gross']),
                  'disc_percent': _toDouble(item['disc_percent']),
                  'disc_amt': _toDouble(item['disc_amt']),
                  'gst_percent': _toDouble(item['gst_percent'], 12.0),
                  'gst_amt': _toDouble(item['gst_amt']),
                  'total': _toDouble(item['total_amount'] ?? item['total']),
                  'rack': item['rack']?.toString() ?? '',
                  'hsn_code': item['hsn_code']?.toString() ?? '',
                  's_disc_percent': _toDouble(item['s_disc_percent']),
                  's_rate': _toDouble(item['selling_rate'] ?? item['s_rate']),
                  'l_cost': _toDouble(item['landing_cost'] ?? item['l_cost']),
                }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
              }
            }
            await batch.commit(noResult: true);
          });
          _updateDynamicProgress(chunk.length, 'Importing Purchase Line Items');
        }
      }
      updateCategoryProgress('purchases', processed: totalPur, total: totalPur, state: CategorySyncState.completed);

      // 7. Pull Purchase Return Entries & Items
      updateCategoryProgress('purchase_returns', processed: 0, total: prRemoteCount, state: CategorySyncState.transferring);
      final prItems = await prFuture;
      final totalPr = prItems.length;
      if (totalPr > 0) {
        updateCategoryProgress('purchase_returns', processed: 0, total: totalPr, state: CategorySyncState.transferring);
        const chunkSize = 500;
        int savedPr = 0;
        for (var i = 0; i < totalPr; i += chunkSize) {
          if (_cancelRequested) return false;
          final end = (i + chunkSize < totalPr) ? i + chunkSize : totalPr;
          final chunk = prItems.sublist(i, end);
          await db.transaction((txn) async {
            for (var item in chunk) {
              if (item is Map<String, dynamic>) {
                final entryNo = item['entry_no']?.toString() ?? '';
                if (entryNo.isEmpty) continue;
                final cleanNo = entryNo.contains('_') ? entryNo.substring(entryNo.indexOf('_') + 1) : entryNo;

                final pendingDel = await txn.query(
                  'pending_deletions',
                  where: 'table_name = ? AND (entry_no = ? OR entry_no = ? OR entry_no LIKE ?)',
                  whereArgs: ['purchase_return_entries', entryNo, cleanNo, "%_$cleanNo"],
                  limit: 1,
                );
                if (pendingDel.isNotEmpty && _toInt(item['is_deleted'], 0) == 0) {
                  continue;
                }

                final existing = await txn.query(
                  'purchase_return_entries',
                  columns: ['is_synced', 'is_deleted'],
                  where: 'entry_no = ? OR entry_no = ?',
                  whereArgs: [entryNo, cleanNo],
                  limit: 1,
                );
                if (existing.isNotEmpty) {
                  final int isSynced = _toInt(existing.first['is_synced'], 1);
                  final int isDeletedLocally = _toInt(existing.first['is_deleted'], 0);
                  final int isDeletedRemotely = _toInt(item['is_deleted'], 0);
                  if (isSynced == 0) continue;
                  if (isDeletedLocally == 1 && isDeletedRemotely == 0) continue;
                }
                await txn.insert('purchase_return_entries', {
                  'entry_no': entryNo,
                  'date': item['date']?.toString() ?? '',
                  'supplier_name': item['supplier_name']?.toString() ?? '',
                  'original_purchase_no': item['original_purchase_no']?.toString() ?? '',
                  'done_by': item['done_by']?.toString() ?? '',
                  'grand_total': _toDouble(item['grand_total']),
                  'gst_mode': _toInt(item['gst_mode'], 1),
                  'is_deleted': _toInt(item['is_deleted'], 0),
                  'is_imported': 1,
                  'financial_year': item['financial_year']?.toString() ?? '',
                }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
              }
            }
          });
          savedPr += chunk.length;
          _updateDynamicProgress(chunk.length, 'Importing Purchase Returns');
          updateCategoryProgress('purchase_returns', processed: savedPr, total: totalPr, state: CategorySyncState.transferring);
        }
        pulledNewData = true;
      }

      final prLineItems = await fetchRows('purchase_return_items');
      if (prLineItems.isNotEmpty) {
        final prRows = await db.query('purchase_return_entries', columns: ['entry_no', 'is_synced']);
        final Map<String, String> prMap = {};
        for (var r in prRows) {
          final isSynced = _toInt(r['is_synced'], 1);
          if (isSynced == 1) {
            final eNo = r['entry_no']?.toString() ?? '';
            if (eNo.isNotEmpty) prMap[eNo] = eNo;
            if (eNo.contains('_')) {
              final clean = eNo.substring(eNo.indexOf('_') + 1);
              if (clean.isNotEmpty) prMap[clean] = eNo;
            }
          }
        }

        final Set<String> clearedPurReturns = {};
        await db.transaction((txn) async {
          for (var item in prLineItems) {
            if (item is Map<String, dynamic>) {
              final entryNo = item['entry_no']?.toString() ?? '';
              if (entryNo.isEmpty) continue;
              final targetEntryNo = prMap[entryNo];
              if (targetEntryNo == null) continue;

              if (!clearedPurReturns.contains(targetEntryNo)) {
                clearedPurReturns.add(targetEntryNo);
                final cleanTgt = cleanEntryNo(targetEntryNo);
                await txn.delete(
                  'purchase_return_items',
                  where: 'entry_no = ? OR entry_no = ? OR entry_no LIKE ?',
                  whereArgs: [targetEntryNo, cleanTgt, "%_$cleanTgt"],
                );
              }

              await txn.insert('purchase_return_items', {
                'entry_no': targetEntryNo,
                'product_name': item['product_name']?.toString() ?? '',
                'batch': item['batch']?.toString() ?? '',
                'expiry': item['expiry']?.toString() ?? '',
                'qty': _toInt(item['qty'], 1),
                'loose_qty': _toInt(item['loose_qty'], 0),
                'f_qty': _toInt(item['f_qty'], 0),
                'unit': item['unit']?.toString() ?? '',
                'packin': _toInt(item['packin'], 1),
                'mrp': _toDouble(item['mrp']),
                'p_rate': _toDouble(item['p_rate']),
                's_rate': _toDouble(item['s_rate']),
                'disc_percent': _toDouble(item['disc_percent']),
                'gst_percent': _toDouble(item['gst_percent'], 12.0),
                'total': _toDouble(item['total']),
                'reason': item['reason']?.toString() ?? '',
                'supplier': item['supplier']?.toString() ?? '',
                'hsn_code': item['hsn_code']?.toString() ?? '',
                'sup_inv_no': item['sup_inv_no']?.toString() ?? '',
              }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
            }
          }
        });
      }
      updateCategoryProgress('purchase_returns', processed: totalPr, total: totalPr, state: CategorySyncState.completed);

      // 8. Pull Financial Vouchers & Prescriptions
      final vTables = ['patient_payments', 'supplier_payments', 'supplier_credit_notes'];
      for (var vTable in vTables) {
        if (_cancelRequested) return false;
        try {
          final vRows = await fetchRows(vTable);
          if (vRows.isNotEmpty) {
            await db.transaction((txn) async {
              for (var row in vRows) {
                if (row is Map<String, dynamic>) {
                  final id = row['id']?.toString() ?? '';
                  if (id.isEmpty) continue;

                  // Protect local unsynced voucher edits from cloud overwrite
                  final unsyncedCheck = await txn.query(
                    vTable,
                    columns: ['is_synced'],
                    where: 'id = ? AND (is_synced = 0 OR is_synced IS NULL)',
                    whereArgs: [id],
                    limit: 1,
                  );
                  if (unsyncedCheck.isNotEmpty) {
                    continue;
                  }

                  final m = Map<String, dynamic>.from(row);
                  m.remove('branch_id');
                  m.remove('created_at');
                  m.remove('updated_at');
                  m['is_synced'] = 1;
                  await txn.insert(vTable, m, conflictAlgorithm: sql.ConflictAlgorithm.replace);
                }
              }
            });
            pulledNewData = true;
          }
        } catch (_) {}
      }

      try {
        final rxRows = await fetchRows('prescriptions');
        if (rxRows.isNotEmpty) {
          if (_cancelRequested) return false;
          await db.transaction((txn) async {
            for (var row in rxRows) {
              if (row is Map<String, dynamic>) {
                final id = row['id']?.toString() ?? '';
                if (id.isEmpty) continue;
                final m = Map<String, dynamic>.from(row);
                m.remove('branch_id');
                m.remove('created_at');
                m.remove('updated_at');
                m['is_synced'] = 1;
                await txn.insert('prescriptions', m, conflictAlgorithm: sql.ConflictAlgorithm.replace);
              }
            }
          });
          pulledNewData = true;
        }

        final rxItemRows = await fetchRows('prescription_items');
        if (rxItemRows.isNotEmpty) {
          if (_cancelRequested) return false;
          await db.transaction((txn) async {
            for (var row in rxItemRows) {
              if (row is Map<String, dynamic>) {
                final rxId = row['prescription_id']?.toString() ?? '';
                if (rxId.isEmpty) continue;
                final m = Map<String, dynamic>.from(row);
                m.remove('branch_id');
                m.remove('created_at');
                await txn.insert('prescription_items', m, conflictAlgorithm: sql.ConflictAlgorithm.replace);
              }
            }
          });
          pulledNewData = true;
        }
      } catch (_) {}

      if (pulledNewData) {
        onDataPulled?.call();
      }
      await syncAllPendingCloudRecords();
      return true;
    } catch (e) {
      debugPrint('_pullRemoteData error: $e');
      _lastSyncError = 'Cloud Import Failed: $e';
      return false;
    }
  }

  /// Wipes a single cloud REST table on Supabase in single-pass bulk or chunked batches until 0 rows remain.
  Future<bool> wipeCloudTable({
    required String endpoint,
    required Map<String, String> baseHeaders,
    required String supabaseUrl,
  }) async {
    final headers = Map<String, String>.from(baseHeaders);
    headers['Prefer'] = 'return=minimal';

    final cleanUrl = ServerConfigService.cleanServerUrl(supabaseUrl);

    // Fast Pre-Flight Check: Verify if table exists or is already empty on Supabase
    try {
      final checkUri = Uri.parse('$cleanUrl/rest/v1/$endpoint?select=*&limit=1');
      final checkRes = await http.get(checkUri, headers: baseHeaders).timeout(const Duration(seconds: 4));
      
      if (checkRes.statusCode == 404 || checkRes.body.contains('PGRST205') || checkRes.body.contains('Could not find the table')) {
        debugPrint('⚡ Cloud Table $endpoint does not exist on Supabase - Wiped (0 rows).');
        return true; // 0 rows exist on Supabase
      }
      
      if (checkRes.statusCode < 400 && (checkRes.body.trim() == '[]' || checkRes.body.trim().isEmpty)) {
        debugPrint('⚡ Instant Bulk Wipe Succeeded for $endpoint (Already 0 rows)');
        return true; // Already 0 rows on Supabase
      }
    } catch (_) {}

    // List of candidate query filters that match all rows in PostgREST
    final List<String> candidateFilters = [];
    if (endpoint == 'sales_invoices' ||
        endpoint == 'purchase_entries' ||
        endpoint == 'sales_return_invoices' ||
        endpoint == 'purchase_return_entries' ||
        endpoint == 'stock_adjustments' ||
        endpoint == 'stock_write_offs' ||
        endpoint == 'prescriptions') {
      candidateFilters.addAll([
        'entry_no=not.is.null',
        'branch_id=not.is.null',
        'id=not.is.null',
        'created_at=not.is.null',
      ]);
    } else {
      candidateFilters.addAll([
        'invoice_no=not.is.null',
        'id=not.is.null',
        'branch_id=not.is.null',
        'entry_no=not.is.null',
        'created_at=not.is.null',
      ]);
    }

    // Phase 1: Instant Single-Pass Bulk DELETE (Deletes all rows in 1 query)
    for (final filter in candidateFilters) {
      try {
        final deleteUri = Uri.parse('$cleanUrl/rest/v1/$endpoint?$filter');
        final delRes = await http.delete(deleteUri, headers: headers).timeout(const Duration(seconds: 15));
        
        if (delRes.statusCode < 400) {
          // Fast verification check: confirm 0 rows remain
          final verifyUri = Uri.parse('$cleanUrl/rest/v1/$endpoint?select=*&limit=1');
          final getRes = await http.get(verifyUri, headers: baseHeaders).timeout(const Duration(seconds: 5));
          if (getRes.statusCode < 400) {
            final body = getRes.body.trim();
            if (body == '[]' || body.isEmpty) {
              debugPrint('⚡ Instant Bulk Wipe Succeeded for $endpoint ($filter)');
              return true;
            }
          }
        }
      } catch (e) {
        debugPrint('Bulk wipe attempt for $endpoint ($filter): $e');
      }
    }

    // Phase 2: High-Speed Chunked Fallback (5,000 items per batch)
    final List<String> pkCandidates = ['id', 'invoice_no', 'entry_no', 'batch_id', 'name'];
    for (final pkCol in pkCandidates) {
      try {
        final fetchUri = Uri.parse('$cleanUrl/rest/v1/$endpoint?select=$pkCol&limit=5000');
        int loopCount = 0;
        bool colWorked = false;

        while (loopCount < 100) {
          final getRes = await http.get(fetchUri, headers: baseHeaders).timeout(const Duration(seconds: 8));
          if (getRes.statusCode >= 400) {
            break; // Column doesn't exist
          }

          final List<dynamic> rows = jsonDecode(getRes.body);
          if (rows.isEmpty) {
            return true; // 0 rows left
          }

          colWorked = true;
          final List<String> keyValues = rows
              .map((r) => r[pkCol]?.toString() ?? '')
              .where((k) => k.isNotEmpty)
              .toList();

          if (keyValues.isEmpty) {
            break;
          }

          final encodedKeys = keyValues.map((k) => Uri.encodeComponent(k)).join(',');
          final deleteUri = Uri.parse('$cleanUrl/rest/v1/$endpoint?$pkCol=in.($encodedKeys)');

          final delRes = await http.delete(deleteUri, headers: headers).timeout(const Duration(seconds: 12));
          if (delRes.statusCode >= 400) {
            debugPrint('Chunk delete notice for $endpoint ($pkCol) status: ${delRes.statusCode}');
            colWorked = false;
            break;
          }

          loopCount++;
        }

        if (colWorked) {
          try {
            final verifyUri = Uri.parse('$cleanUrl/rest/v1/$endpoint?select=*&limit=1');
            final verifyRes = await http.get(verifyUri, headers: baseHeaders).timeout(const Duration(seconds: 3));
            if (verifyRes.statusCode < 400) {
              final body = verifyRes.body.trim();
              if (body == '[]' || body.isEmpty) {
                return true;
              }
            }
          } catch (_) {
            return true;
          }
        }
      } catch (e) {
        debugPrint('Wipe chunk fallback notice for $endpoint ($pkCol): $e');
      }
    }

    return false;
  }

  List<String> _getEndpointsForCategories(Set<String>? selectedCategories) {
    if (selectedCategories == null || selectedCategories.isEmpty) {
      return [
        'sales_items',
        'sales_invoices',
        'purchase_items',
        'purchase_entries',
        'sales_return_items',
        'sales_return_invoices',
        'purchase_return_items',
        'purchase_return_entries',
        'prescription_items',
        'prescriptions',
        'patient_payments',
        'supplier_payments',
        'supplier_credit_notes',
        'stock_adjustments',
        'stock_write_offs',
        'stock_batches',
        'product_master',
        'patients',
        'suppliers',
        'doctors',
        'categories',
        'manufacturers',
        'racks',
        'generics',
        'accounts',
        'staff',
      ];
    }

    final Set<String> endpoints = {};
    if (selectedCategories.contains('sales')) {
      endpoints.add('sales_items');
      endpoints.add('sales_invoices');
    }
    if (selectedCategories.contains('purchases')) {
      endpoints.add('purchase_items');
      endpoints.add('purchase_entries');
    }
    if (selectedCategories.contains('sales_returns')) {
      endpoints.add('sales_return_items');
      endpoints.add('sales_return_invoices');
    }
    if (selectedCategories.contains('purchase_returns')) {
      endpoints.add('purchase_return_items');
      endpoints.add('purchase_return_entries');
    }
    if (selectedCategories.contains('prescriptions_adjustments')) {
      endpoints.add('prescription_items');
      endpoints.add('prescriptions');
      endpoints.add('stock_adjustments');
      endpoints.add('stock_adjustment_items');
    }
    if (selectedCategories.contains('sales') || selectedCategories.contains('accounts_daybook')) {
      endpoints.add('daily_financial_summaries');
    }
    if (selectedCategories.contains('damages')) endpoints.add('stock_write_offs');
    if (selectedCategories.contains('customer_account') || selectedCategories.contains('accounts_daybook')) {
      endpoints.add('patient_payments');
    }
    if (selectedCategories.contains('wholesale_account') || selectedCategories.contains('accounts_daybook')) {
      endpoints.add('supplier_payments');
    }
    if (selectedCategories.contains('vouchers')) {
      endpoints.add('supplier_credit_notes');
    }
    if (selectedCategories.contains('batches')) endpoints.add('stock_batches');
    if (selectedCategories.contains('products')) endpoints.add('product_master');
    if (selectedCategories.contains('patients')) endpoints.add('patients');
    if (selectedCategories.contains('suppliers_doctors')) {
      endpoints.add('suppliers');
      endpoints.add('doctors');
    }

    return endpoints.toList();
  }

  /// Wipes selected cloud REST tables on Supabase and clears matching local SQLite tables with progress updates and detailed statistics.
  Future<Map<String, dynamic>> wipeAllCloudAndLocalData({
    Set<String>? selectedCategoryIds,
    Function(double progress, String status)? onProgress,
  }) async {
    _isWiping = true;
    _cancelRequested = true; // Instantly signal any active background sync operation to abort
    ServerConfigService.instance.setWiping(true);

    // Stop background periodic delta sync and realtime stream subscriptions during reset to eliminate SQLite lock contention
    DeltaSyncService.instance.stopPeriodicSync();
    SupabaseRealtimeService.instance.disposeAll();

    // Brief wait for any in-flight background sync cycles or DB operations to yield SQLite lock
    int waitCount = 0;
    while (_isSyncing && waitCount < 20) {
      waitCount++;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    await Future.delayed(const Duration(milliseconds: 300));

    int cloudSuccessCount = 0;
    List<String> failedEndpoints = [];
    bool localSuccess = false;

    try {
      final config = ServerConfigService.instance;
      final List<String> endpoints = _getEndpointsForCategories(selectedCategoryIds);

      if (_isReady && config.supabaseUrl.isNotEmpty) {
        final headers = Map<String, String>.from(config.restHeaders);

        for (int i = 0; i < endpoints.length; i++) {
          final endpoint = endpoints[i];
          double pct = (i / endpoints.length) * 0.8;
          onProgress?.call(pct, 'Wiping Cloud Table: $endpoint (${i + 1}/${endpoints.length})...');

          final wiped = await wipeCloudTable(
            endpoint: endpoint,
            baseHeaders: headers,
            supabaseUrl: config.supabaseUrl,
          );

          if (wiped) {
            cloudSuccessCount++;
          } else {
            failedEndpoints.add(endpoint);
          }
        }
      }

      onProgress?.call(0.85, 'Preparing Local SQLite for Reset...');

      final db = await DbHelper.instance.database;

      final Set<String> localTablesToClear = Set<String>.from(endpoints);
      
      // Add specific auxiliary local tables ONLY when relevant categories are selected
      if (selectedCategoryIds == null || selectedCategoryIds.isEmpty || selectedCategoryIds.length >= 14) {
        localTablesToClear.addAll([
          'sales_drafts',
          'purchase_drafts',
          'stock_ledger',
          'batch_master',
          'rack_history',
          'edit_history_logs',
          'stock_enquiries',
          'monthly_closing_balances',
          'order_confirmations',
          'order_confirmation_items',
          'pending_deletions',
          'voucher_sequences',
        ]);
      } else {
        if (selectedCategoryIds.contains('sales')) {
          localTablesToClear.add('sales_drafts');
          localTablesToClear.add('edit_history_logs');
        }
        if (selectedCategoryIds.contains('purchases')) {
          localTablesToClear.add('purchase_drafts');
        }
        if (selectedCategoryIds.contains('batches')) {
          localTablesToClear.add('batch_master');
          localTablesToClear.add('stock_ledger');
        }
      }
      final List<String> allLocalTables = localTablesToClear.toList();

      // Drop FTS triggers & disable foreign keys so SQLite can use instant B-tree page truncation
      bool ftsTriggersDropped = false;
      try {
        await db.execute('PRAGMA foreign_keys = OFF;');
      } catch (_) {}

      if (allLocalTables.contains('product_master')) {
        try {
          await db.execute('DROP TRIGGER IF EXISTS ad_product_master_fts;');
          await db.execute('DROP TRIGGER IF EXISTS au_product_master_fts;');
          await db.execute('DROP TRIGGER IF EXISTS ai_product_master_fts;');
          ftsTriggersDropped = true;
        } catch (_) {}
      }

      // Fast-path: Wrap table clear in a single IMMEDIATE transaction for ultra-fast bulk page truncation (<0.1s)
      try {
        await db.execute('BEGIN IMMEDIATE;');

        for (int i = 0; i < allLocalTables.length; i++) {
          final tbl = allLocalTables[i];
          double pct = 0.85 + (((i + 1) / allLocalTables.length) * 0.12);
          onProgress?.call(pct, 'Clearing Local Table (${i + 1}/${allLocalTables.length}): $tbl...');

          try {
            await db.execute('DELETE FROM $tbl;');
          } catch (_) {
            // Table may exist only on Supabase
          }
        }

        try { await db.execute('DELETE FROM product_search_fts;'); } catch (_) {}
        try { await db.execute('DELETE FROM sqlite_sequence;'); } catch (_) {}

        if (selectedCategoryIds != null && selectedCategoryIds.isNotEmpty && selectedCategoryIds.length < 14) {
          for (final cat in selectedCategoryIds) {
            if (cat == 'sales') {
              try { await db.execute("DELETE FROM voucher_sequences WHERE voucher_type LIKE 'sales_invoices%';"); } catch (_) {}
            } else if (cat == 'purchases') {
              try { await db.execute("DELETE FROM voucher_sequences WHERE voucher_type LIKE 'purchase_entries%' OR voucher_type LIKE 'purchase_invoices%';"); } catch (_) {}
            } else if (cat == 'sales_returns') {
              try { await db.execute("DELETE FROM voucher_sequences WHERE voucher_type LIKE 'sales_return_invoices%';"); } catch (_) {}
            } else if (cat == 'purchase_returns') {
              try { await db.execute("DELETE FROM voucher_sequences WHERE voucher_type LIKE 'purchase_return_entries%';"); } catch (_) {}
            } else if (cat == 'prescriptions_adjustments') {
              try { await db.execute("DELETE FROM voucher_sequences WHERE voucher_type LIKE 'stock_adjustments%' OR voucher_type LIKE 'prescriptions%';"); } catch (_) {}
            } else if (cat == 'damages') {
              try { await db.execute("DELETE FROM voucher_sequences WHERE voucher_type LIKE 'stock_write_offs%';"); } catch (_) {}
            }
          }
        }

        await db.execute('COMMIT;');
      } catch (e) {
        debugPrint('Bulk transaction wipe warning, attempting table-by-table fallback: $e');
        try { await db.execute('ROLLBACK;'); } catch (_) {}
        for (int i = 0; i < allLocalTables.length; i++) {
          final tbl = allLocalTables[i];
          try { await db.execute('DELETE FROM $tbl;'); } catch (_) {}
        }
      }

      // Re-create FTS triggers if they were dropped
      if (ftsTriggersDropped) {
        try {
          await db.execute('''
            CREATE TRIGGER IF NOT EXISTS ai_product_master_fts AFTER INSERT ON product_master BEGIN
              INSERT INTO product_search_fts(id, name, generic_name, barcode, hsn_code, rack_id)
              VALUES (new.id, new.name, IFNULL(new.generic_name, ''), IFNULL(new.barcode, ''), IFNULL(new.hsn_code, ''), IFNULL(new.rack_id, ''));
            END;
          ''');
          await db.execute('''
            CREATE TRIGGER IF NOT EXISTS au_product_master_fts AFTER UPDATE OF name, generic_name, barcode, hsn_code, rack_id ON product_master BEGIN
              DELETE FROM product_search_fts WHERE id = old.id;
              INSERT INTO product_search_fts(id, name, generic_name, barcode, hsn_code, rack_id)
              VALUES (new.id, new.name, IFNULL(new.generic_name, ''), IFNULL(new.barcode, ''), IFNULL(new.hsn_code, ''), IFNULL(new.rack_id, ''));
            END;
          ''');
          await db.execute('''
            CREATE TRIGGER IF NOT EXISTS ad_product_master_fts AFTER DELETE ON product_master BEGIN
              DELETE FROM product_search_fts WHERE id = old.id;
            END;
          ''');
        } catch (_) {}
      }

      try {
        await db.execute('PRAGMA foreign_keys = ON;');
      } catch (_) {}

      localSuccess = true;
      try {
        await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE);');
      } catch (_) {}

      onProgress?.call(1.0, '100% - Full System Reset Completed!');
      _lastSyncTime = DateTime.now();
      _syncStatusMessage = 'System database reset to 0.';
      notifyListeners();

      return {
        'success': localSuccess && failedEndpoints.isEmpty,
        'cloudSuccessCount': cloudSuccessCount,
        'cloudTotalCount': endpoints.length,
        'localSuccess': localSuccess,
        'failedEndpoints': failedEndpoints,
      };
    } catch (e) {
      debugPrint('Wipe all error: $e');
      return {
        'success': false,
        'cloudSuccessCount': cloudSuccessCount,
        'cloudTotalCount': 20,
        'localSuccess': localSuccess,
        'failedEndpoints': failedEndpoints,
        'error': e.toString(),
      };
    } finally {
      _isWiping = false;
      _cancelRequested = false;
      ServerConfigService.instance.setWiping(false);

      // Restart periodic delta sync & realtime listeners if server mode is enabled
      if (ServerConfigService.instance.isServerModeEnabled && ServerConfigService.instance.isConnected) {
        if (ServerConfigService.instance.autoSyncEnabled) {
          DeltaSyncService.instance.startPeriodicSync();
        }
        unawaited(Future.delayed(const Duration(milliseconds: 500), () async {
          try {
            await SupabaseRealtimeService.instance.initialize();
            SupabaseRealtimeService.instance.startAllRealtimeListeners();
          } catch (_) {}
        }));
      }
    }
  }

  /// Checks the Cloud Retention Timer and prunes historical transaction line items
  Future<bool> checkAndPruneOldCloudData() async {
    if (!_isReady) return false;

    final config = ServerConfigService.instance;
    final int timerYears = config.cloudDataPruningTimerYears;
    if (timerYears <= 0) {
      return false;
    }

    final cutoffDate = DateTime.now().subtract(Duration(days: 365 * timerYears));
    final cutoffDateStr = DateFormat('yyyy-MM-dd').format(cutoffDate);

    try {
      final db = await DbHelper.instance.database;

      final localSalesCount = (await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM sales_invoices WHERE date < ? AND is_deleted = 0',
        [cutoffDateStr],
      )).first['cnt'] as int? ?? 0;

      final localPurchaseCount = (await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM purchase_entries WHERE date < ? AND is_deleted = 0',
        [cutoffDateStr],
      )).first['cnt'] as int? ?? 0;

      if (localSalesCount == 0 && localPurchaseCount == 0) {
        return false;
      }

      final branchId = config.storeBranchId;
      final headers = Map<String, String>.from(config.restHeaders);

      final salesUri = Uri.parse('${config.supabaseUrl}/rest/v1/sales_items?branch_id=eq.$branchId&created_at=lt.$cutoffDateStr');
      final salesResp = await http.delete(salesUri, headers: headers).timeout(const Duration(seconds: 10));

      final purchaseUri = Uri.parse('${config.supabaseUrl}/rest/v1/purchase_items?branch_id=eq.$branchId&created_at=lt.$cutoffDateStr');
      final purchaseResp = await http.delete(purchaseUri, headers: headers).timeout(const Duration(seconds: 10));

      debugPrint('Cloud Pruning completed. Sales status: ${salesResp.statusCode}, Purchase status: ${purchaseResp.statusCode}');
      return true;
    } catch (e) {
      debugPrint('Error during cloud pruning: $e');
      return false;
    }
  }

  /// Returns the complete PostgreSQL SQL DDL script to paste into Supabase SQL Editor.
  static String generatePostgresSqlSchema() {
    return r'''
-- ========================================================
-- PHARMAPRO ERP - SUPABASE POSTGRESQL PRODUCTION SETUP
-- Run this in Supabase SQL Editor
-- ========================================================

-- STEP 1: DROP OVERLOADED FUNCTIONS (FIXES PGRST203 AMBIGUITY ERRORS)
DROP FUNCTION IF EXISTS public.fn_next_sequence_number(text, text);
DROP FUNCTION IF EXISTS public.fn_next_sequence_number(text, text, text);
DROP FUNCTION IF EXISTS public.fn_next_sequence_number(text);
DROP FUNCTION IF EXISTS public.fn_claim_next_invoice_no(text, text);
DROP FUNCTION IF EXISTS public.fn_claim_next_sale_invoice_no(text, text, text);

DROP FUNCTION IF EXISTS public.fn_save_purchase_entry_atomic(jsonb, jsonb);
DROP FUNCTION IF EXISTS public.fn_save_purchase_entry_atomic(jsonb);

DROP FUNCTION IF EXISTS public.fn_save_sale_invoice_atomic(jsonb, jsonb);
DROP FUNCTION IF EXISTS public.fn_save_sale_invoice_atomic_ui(jsonb, jsonb);
DROP FUNCTION IF EXISTS public.fn_save_sale_invoice_atomic_v2(jsonb, jsonb);

-- STEP 2: AUTOMATED TIMESTAMP TRIGGER FOR DELTA SYNCING & FAST INDEXING
CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE INDEX IF NOT EXISTS idx_sales_invoices_fast ON sales_invoices(financial_year, terminal_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_stock_batches_fast ON stock_batches(financial_year, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_product_master_fast ON product_master(updated_at DESC);

-- MULTI-TERMINAL ATOMIC SEQUENCE RPC
CREATE OR REPLACE FUNCTION fn_next_sequence_number(p_table TEXT, p_fy TEXT) 
RETURNS TEXT AS $$
DECLARE
    v_max INT := 0;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext(p_table || '_' || p_fy));

    IF p_table = 'sales_invoices' THEN
        SELECT COALESCE(MAX(
            NULLIF(regexp_replace(entry_no, '^.*?[_-]', ''), '')::INT
        ), 0) INTO v_max 
        FROM sales_invoices 
        WHERE financial_year = p_fy;
    ELSIF p_table = 'purchase_entries' THEN
        SELECT COALESCE(MAX(
            NULLIF(regexp_replace(entry_no, '^.*?[_-]', ''), '')::INT
        ), 0) INTO v_max 
        FROM purchase_entries 
        WHERE financial_year = p_fy;
    ELSE
        RETURN NULL;
    END IF;
    RETURN (v_max + 1)::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ATOMIC SEQUENCE RESERVATION ALIAS (Step 1 requirement)
CREATE OR REPLACE FUNCTION fn_claim_next_invoice_no(p_table TEXT, p_fy TEXT) 
RETURNS TEXT AS $$
BEGIN
    RETURN fn_next_sequence_number(p_table, p_fy);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ATOMIC SALE INVOICE UPSERT FUNCTION WITH CHILD ITEM REPLACEMENT & COLLISION CHECKING
DROP FUNCTION IF EXISTS public.fn_save_sale_invoice_atomic(JSONB, JSONB);

CREATE OR REPLACE FUNCTION public.fn_save_sale_invoice_atomic(
  p_invoice JSONB,
  p_items JSONB DEFAULT '[]'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_entry_no TEXT;
  v_terminal_id TEXT;
  v_branch_id TEXT;
  v_existing_terminal TEXT;
  v_existing_branch TEXT;
BEGIN
  -- Extract key identifiers
  v_entry_no := p_invoice->>'entry_no';
  v_terminal_id := TRIM(COALESCE(p_invoice->>'terminal_id', ''));
  v_branch_id := TRIM(COALESCE(p_invoice->>'branch_id', ''));

  -- Mandatory field validation
  IF v_entry_no IS NULL OR v_entry_no = '' OR v_terminal_id = '' OR v_branch_id = '' THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'INVALID_INPUT',
      'message', 'Missing required entry_no, terminal_id, or branch_id'
    );
  END IF;

  -- Server-side check: reject empty p_items array BEFORE changing header or deleting items
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'EMPTY_ITEMS',
      'message', 'Rejected: p_items array cannot be empty or null'
    );
  END IF;

  -- Row-level lock check for existing invoice ownership
  SELECT terminal_id, branch_id
  INTO v_existing_terminal, v_existing_branch
  FROM public.sales_invoices
  WHERE entry_no = v_entry_no
  FOR UPDATE;

  IF FOUND THEN
    v_existing_terminal := TRIM(COALESCE(v_existing_terminal, ''));
    v_existing_branch := TRIM(COALESCE(v_existing_branch, ''));

    -- Collision check: reject if belonging to another terminal/branch or ownership is unknown
    IF v_existing_terminal = '' OR v_existing_branch = '' OR v_existing_terminal <> v_terminal_id OR v_existing_branch <> v_branch_id THEN
      RETURN jsonb_build_object(
        'success', false,
        'reason', 'COLLISION',
        'message', 'Invoice entry_no already exists under a different terminal/branch or unknown ownership'
      );
    END IF;

    -- Update existing header safely (Retry from same terminal & branch)
    UPDATE public.sales_invoices
    SET
      invoice_no = COALESCE(p_invoice->>'invoice_no', v_entry_no),
      financial_year = COALESCE(p_invoice->>'financial_year', ''),
      date = COALESCE(p_invoice->>'date', ''),
      customer_acc = COALESCE(p_invoice->>'customer_acc', p_invoice->>'payment_mode', 'Cash'),
      customer_name = COALESCE(p_invoice->>'customer_name', p_invoice->>'patient', ''),
      patient = COALESCE(p_invoice->>'patient', p_invoice->>'customer_name', ''),
      customer_phone = COALESCE(p_invoice->>'customer_phone', p_invoice->>'mobile', ''),
      mobile = COALESCE(p_invoice->>'mobile', p_invoice->>'customer_phone', ''),
      doctor = COALESCE(p_invoice->>'doctor', ''),
      doctor_reg_no = COALESCE(p_invoice->>'doctor_reg_no', ''),
      done_by = COALESCE(p_invoice->>'done_by', 'Cashier'),
      terminal_id = v_terminal_id,
      shift_id = COALESCE(p_invoice->>'shift_id', 'SHIFT-01'),
      patient_age = COALESCE(NULLIF(p_invoice->>'patient_age', '')::INT, 0),
      patient_gender = COALESCE(p_invoice->>'patient_gender', ''),
      patient_address = COALESCE(p_invoice->>'patient_address', ''),
      gstin_number = COALESCE(p_invoice->>'gstin_number', ''),
      place_of_supply = COALESCE(p_invoice->>'place_of_supply', ''),
      subtotal = COALESCE(NULLIF(p_invoice->>'subtotal', '')::NUMERIC, NULLIF(p_invoice->>'sub_total', '')::NUMERIC, 0.0),
      sub_total = COALESCE(NULLIF(p_invoice->>'sub_total', '')::NUMERIC, NULLIF(p_invoice->>'subtotal', '')::NUMERIC, 0.0),
      discount_amount = COALESCE(NULLIF(p_invoice->>'discount_amount', '')::NUMERIC, NULLIF(p_invoice->>'discount', '')::NUMERIC, 0.0),
      discount = COALESCE(NULLIF(p_invoice->>'discount', '')::NUMERIC, NULLIF(p_invoice->>'discount_amount', '')::NUMERIC, 0.0),
      discount_percent = COALESCE(NULLIF(p_invoice->>'discount_percent', '')::NUMERIC, 0.0),
      additional_discount = COALESCE(NULLIF(p_invoice->>'additional_discount', '')::NUMERIC, 0.0),
      other_charge = COALESCE(NULLIF(p_invoice->>'other_charge', '')::NUMERIC, 0.0),
      tax_amount = COALESCE(NULLIF(p_invoice->>'tax_amount', '')::NUMERIC, NULLIF(p_invoice->>'tax', '')::NUMERIC, 0.0),
      tax = COALESCE(NULLIF(p_invoice->>'tax', '')::NUMERIC, NULLIF(p_invoice->>'tax_amount', '')::NUMERIC, 0.0),
      round_off = COALESCE(NULLIF(p_invoice->>'round_off', '')::NUMERIC, 0.0),
      net_amount = COALESCE(NULLIF(p_invoice->>'net_amount', '')::NUMERIC, NULLIF(p_invoice->>'grand_total', '')::NUMERIC, NULLIF(p_invoice->>'total_amount', '')::NUMERIC, 0.0),
      grand_total = COALESCE(NULLIF(p_invoice->>'grand_total', '')::NUMERIC, NULLIF(p_invoice->>'net_amount', '')::NUMERIC, NULLIF(p_invoice->>'total_amount', '')::NUMERIC, 0.0),
      total_amount = COALESCE(NULLIF(p_invoice->>'total_amount', '')::NUMERIC, NULLIF(p_invoice->>'grand_total', '')::NUMERIC, NULLIF(p_invoice->>'net_amount', '')::NUMERIC, 0.0),
      rcvd_amt = COALESCE(NULLIF(p_invoice->>'rcvd_amt', '')::NUMERIC, 0.0),
      payment_mode = COALESCE(p_invoice->>'payment_mode', 'CASH'),
      payment_remarks = COALESCE(p_invoice->>'payment_remarks', ''),
      secondary_acc = COALESCE(p_invoice->>'secondary_acc', ''),
      secondary_amt = COALESCE(NULLIF(p_invoice->>'secondary_amt', '')::NUMERIC, 0.0),
      is_deleted = COALESCE(NULLIF(p_invoice->>'is_deleted', '')::INT, 0),
      is_paid = COALESCE(NULLIF(p_invoice->>'is_paid', '')::INT, 1),
      tax_type = COALESCE(p_invoice->>'tax_type', 'Non Gst'),
      agent = COALESCE(p_invoice->>'agent', 'Admin'),
      sales_return_amt = COALESCE(NULLIF(p_invoice->>'sales_return_amt', '')::NUMERIC, 0.0),
      order_type = COALESCE(NULLIF(p_invoice->>'order_type', '')::INT, 0),
      branch_id = v_branch_id,
      updated_at = NOW()
    WHERE entry_no = v_entry_no;

  ELSE
    -- Insert new header safely with unique_violation exception handler for simultaneous first uploads
    BEGIN
      INSERT INTO public.sales_invoices (
        entry_no, invoice_no, financial_year, date, customer_acc, customer_name, patient,
        customer_phone, mobile, doctor, doctor_reg_no, done_by, terminal_id, shift_id,
        patient_age, patient_gender, patient_address, gstin_number, place_of_supply,
        subtotal, sub_total, discount_amount, discount, discount_percent, additional_discount,
        other_charge, tax_amount, tax, round_off, net_amount, grand_total, total_amount,
        rcvd_amt, payment_mode, payment_remarks, secondary_acc, secondary_amt,
        is_deleted, is_paid, tax_type, agent, sales_return_amt, order_type,
        branch_id, updated_at
      ) VALUES (
        v_entry_no,
        COALESCE(p_invoice->>'invoice_no', v_entry_no),
        COALESCE(p_invoice->>'financial_year', ''),
        COALESCE(p_invoice->>'date', ''),
        COALESCE(p_invoice->>'customer_acc', p_invoice->>'payment_mode', 'Cash'),
        COALESCE(p_invoice->>'customer_name', p_invoice->>'patient', ''),
        COALESCE(p_invoice->>'patient', p_invoice->>'customer_name', ''),
        COALESCE(p_invoice->>'customer_phone', p_invoice->>'mobile', ''),
        COALESCE(p_invoice->>'mobile', p_invoice->>'customer_phone', ''),
        COALESCE(p_invoice->>'doctor', ''),
        COALESCE(p_invoice->>'doctor_reg_no', ''),
        COALESCE(p_invoice->>'done_by', 'Cashier'),
        v_terminal_id,
        COALESCE(p_invoice->>'shift_id', 'SHIFT-01'),
        COALESCE(NULLIF(p_invoice->>'patient_age', '')::INT, 0),
        COALESCE(p_invoice->>'patient_gender', ''),
        COALESCE(p_invoice->>'patient_address', ''),
        COALESCE(p_invoice->>'gstin_number', ''),
        COALESCE(p_invoice->>'place_of_supply', ''),
        COALESCE(NULLIF(p_invoice->>'subtotal', '')::NUMERIC, NULLIF(p_invoice->>'sub_total', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'sub_total', '')::NUMERIC, NULLIF(p_invoice->>'subtotal', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'discount_amount', '')::NUMERIC, NULLIF(p_invoice->>'discount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'discount', '')::NUMERIC, NULLIF(p_invoice->>'discount_amount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'discount_percent', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'additional_discount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'other_charge', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'tax_amount', '')::NUMERIC, NULLIF(p_invoice->>'tax', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'tax', '')::NUMERIC, NULLIF(p_invoice->>'tax_amount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'round_off', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'net_amount', '')::NUMERIC, NULLIF(p_invoice->>'grand_total', '')::NUMERIC, NULLIF(p_invoice->>'total_amount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'grand_total', '')::NUMERIC, NULLIF(p_invoice->>'net_amount', '')::NUMERIC, NULLIF(p_invoice->>'total_amount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'total_amount', '')::NUMERIC, NULLIF(p_invoice->>'grand_total', '')::NUMERIC, NULLIF(p_invoice->>'net_amount', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'rcvd_amt', '')::NUMERIC, 0.0),
        COALESCE(p_invoice->>'payment_mode', 'CASH'),
        COALESCE(p_invoice->>'payment_remarks', ''),
        COALESCE(p_invoice->>'secondary_acc', ''),
        COALESCE(NULLIF(p_invoice->>'secondary_amt', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'is_deleted', '')::INT, 0),
        COALESCE(NULLIF(p_invoice->>'is_paid', '')::INT, 1),
        COALESCE(p_invoice->>'tax_type', 'Non Gst'),
        COALESCE(p_invoice->>'agent', 'Admin'),
        COALESCE(NULLIF(p_invoice->>'sales_return_amt', '')::NUMERIC, 0.0),
        COALESCE(NULLIF(p_invoice->>'order_type', '')::INT, 0),
        v_branch_id,
        NOW()
      );
    EXCEPTION WHEN unique_violation THEN
      -- A concurrent transaction inserted entry_no at the exact same moment
      SELECT terminal_id, branch_id
      INTO v_existing_terminal, v_existing_branch
      FROM public.sales_invoices
      WHERE entry_no = v_entry_no
      FOR UPDATE;

      v_existing_terminal := TRIM(COALESCE(v_existing_terminal, ''));
      v_existing_branch := TRIM(COALESCE(v_existing_branch, ''));

      IF v_existing_terminal = '' OR v_existing_branch = '' OR v_existing_terminal <> v_terminal_id OR v_existing_branch <> v_branch_id THEN
        RETURN jsonb_build_object(
          'success', false,
          'reason', 'COLLISION',
          'message', 'Concurrent collision: Invoice entry_no was created by another terminal/branch'
        );
      END IF;

      -- If same terminal and branch, update header consistently before replacing line items
      UPDATE public.sales_invoices
      SET
        invoice_no = COALESCE(p_invoice->>'invoice_no', v_entry_no),
        financial_year = COALESCE(p_invoice->>'financial_year', ''),
        date = COALESCE(p_invoice->>'date', ''),
        customer_acc = COALESCE(p_invoice->>'customer_acc', p_invoice->>'payment_mode', 'Cash'),
        customer_name = COALESCE(p_invoice->>'customer_name', p_invoice->>'patient', ''),
        patient = COALESCE(p_invoice->>'patient', p_invoice->>'customer_name', ''),
        customer_phone = COALESCE(p_invoice->>'customer_phone', p_invoice->>'mobile', ''),
        mobile = COALESCE(p_invoice->>'mobile', p_invoice->>'customer_phone', ''),
        doctor = COALESCE(p_invoice->>'doctor', ''),
        doctor_reg_no = COALESCE(p_invoice->>'doctor_reg_no', ''),
        done_by = COALESCE(p_invoice->>'done_by', 'Cashier'),
        terminal_id = v_terminal_id,
        shift_id = COALESCE(p_invoice->>'shift_id', 'SHIFT-01'),
        patient_age = COALESCE(NULLIF(p_invoice->>'patient_age', '')::INT, 0),
        patient_gender = COALESCE(p_invoice->>'patient_gender', ''),
        patient_address = COALESCE(p_invoice->>'patient_address', ''),
        gstin_number = COALESCE(p_invoice->>'gstin_number', ''),
        place_of_supply = COALESCE(p_invoice->>'place_of_supply', ''),
        subtotal = COALESCE(NULLIF(p_invoice->>'subtotal', '')::NUMERIC, NULLIF(p_invoice->>'sub_total', '')::NUMERIC, 0.0),
        sub_total = COALESCE(NULLIF(p_invoice->>'sub_total', '')::NUMERIC, NULLIF(p_invoice->>'subtotal', '')::NUMERIC, 0.0),
        discount_amount = COALESCE(NULLIF(p_invoice->>'discount_amount', '')::NUMERIC, NULLIF(p_invoice->>'discount', '')::NUMERIC, 0.0),
        discount = COALESCE(NULLIF(p_invoice->>'discount', '')::NUMERIC, NULLIF(p_invoice->>'discount_amount', '')::NUMERIC, 0.0),
        discount_percent = COALESCE(NULLIF(p_invoice->>'discount_percent', '')::NUMERIC, 0.0),
        additional_discount = COALESCE(NULLIF(p_invoice->>'additional_discount', '')::NUMERIC, 0.0),
        other_charge = COALESCE(NULLIF(p_invoice->>'other_charge', '')::NUMERIC, 0.0),
        tax_amount = COALESCE(NULLIF(p_invoice->>'tax_amount', '')::NUMERIC, NULLIF(p_invoice->>'tax', '')::NUMERIC, 0.0),
        tax = COALESCE(NULLIF(p_invoice->>'tax', '')::NUMERIC, NULLIF(p_invoice->>'tax_amount', '')::NUMERIC, 0.0),
        round_off = COALESCE(NULLIF(p_invoice->>'round_off', '')::NUMERIC, 0.0),
        net_amount = COALESCE(NULLIF(p_invoice->>'net_amount', '')::NUMERIC, NULLIF(p_invoice->>'grand_total', '')::NUMERIC, NULLIF(p_invoice->>'total_amount', '')::NUMERIC, 0.0),
        grand_total = COALESCE(NULLIF(p_invoice->>'grand_total', '')::NUMERIC, NULLIF(p_invoice->>'net_amount', '')::NUMERIC, NULLIF(p_invoice->>'total_amount', '')::NUMERIC, 0.0),
        total_amount = COALESCE(NULLIF(p_invoice->>'total_amount', '')::NUMERIC, NULLIF(p_invoice->>'grand_total', '')::NUMERIC, NULLIF(p_invoice->>'net_amount', '')::NUMERIC, 0.0),
        rcvd_amt = COALESCE(NULLIF(p_invoice->>'rcvd_amt', '')::NUMERIC, 0.0),
        payment_mode = COALESCE(p_invoice->>'payment_mode', 'CASH'),
        payment_remarks = COALESCE(p_invoice->>'payment_remarks', ''),
        secondary_acc = COALESCE(p_invoice->>'secondary_acc', ''),
        secondary_amt = COALESCE(NULLIF(p_invoice->>'secondary_amt', '')::NUMERIC, 0.0),
        is_deleted = COALESCE(NULLIF(p_invoice->>'is_deleted', '')::INT, 0),
        is_paid = COALESCE(NULLIF(p_invoice->>'is_paid', '')::INT, 1),
        tax_type = COALESCE(p_invoice->>'tax_type', 'Non Gst'),
        agent = COALESCE(p_invoice->>'agent', 'Admin'),
        sales_return_amt = COALESCE(NULLIF(p_invoice->>'sales_return_amt', '')::NUMERIC, 0.0),
        order_type = COALESCE(NULLIF(p_invoice->>'order_type', '')::INT, 0),
        branch_id = v_branch_id,
        updated_at = NOW()
      WHERE entry_no = v_entry_no;
    END;
  END IF;

  -- Atomically replace line items in sales_items (using invoice_no foreign key)
  DELETE FROM public.sales_items WHERE invoice_no = v_entry_no;

  IF p_items IS NOT NULL AND jsonb_array_length(p_items) > 0 THEN
    INSERT INTO public.sales_items (
      invoice_no, product_id, product_name, extra, batch_number, expiry_date,
      quantity, f_qty, hsn_code, schedule, packing, mrp, purchase_rate, landing_cost,
      taxable_sp, unit_price, disc_percent, disc_amt, gst_percent, gst_amt,
      cgst_amt, sgst_amt, igst_amt, total_amount, profit, supplier_name, rack, branch_id
    )
    SELECT
      v_entry_no,
      COALESCE(item->>'product_id', ''),
      COALESCE(item->>'product_name', ''),
      COALESCE(item->>'extra', ''),
      COALESCE(item->>'batch_number', ''),
      COALESCE(item->>'expiry_date', ''),
      COALESCE(NULLIF(item->>'quantity', '')::INT, NULLIF(item->>'qty', '')::INT, 1),
      COALESCE(NULLIF(item->>'f_qty', '')::INT, 0),
      COALESCE(item->>'hsn_code', ''),
      COALESCE(item->>'schedule', 'H'),
      COALESCE(NULLIF(item->>'packing', '')::INT, NULLIF(item->>'packin', '')::INT, 1),
      COALESCE(NULLIF(item->>'mrp', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'purchase_rate', '')::NUMERIC, NULLIF(item->>'p_rate', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'landing_cost', '')::NUMERIC, NULLIF(item->>'l_cost', '')::NUMERIC, NULLIF(item->>'purchase_rate', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'taxable_sp', '')::NUMERIC, NULLIF(item->>'unit_price', '')::NUMERIC, NULLIF(item->>'s_rate', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'unit_price', '')::NUMERIC, NULLIF(item->>'s_rate', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'disc_percent', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'disc_amt', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'gst_percent', '')::NUMERIC, 12.0),
      COALESCE(NULLIF(item->>'gst_amt', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'cgst_amt', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'sgst_amt', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'igst_amt', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'total_amount', '')::NUMERIC, NULLIF(item->>'net_amount', '')::NUMERIC, NULLIF(item->>'total', '')::NUMERIC, 0.0),
      COALESCE(NULLIF(item->>'profit', '')::NUMERIC, 0.0),
      COALESCE(item->>'supplier_name', ''),
      COALESCE(item->>'rack', ''),
      v_branch_id
    FROM jsonb_array_elements(p_items) AS item;
  END IF;

  RETURN jsonb_build_object('success', true, 'entry_no', v_entry_no);
END;
$$;

-- ATOMIC PURCHASE ENTRY UPSERT WITH CHILD LINE ITEM REPLACEMENT
CREATE OR REPLACE FUNCTION fn_save_purchase_entry_atomic(p_purchase JSONB, p_items JSONB) 
RETURNS VOID AS $$
DECLARE
    v_entry_no TEXT;
    v_item JSONB;
BEGIN
    v_entry_no := p_purchase->>'entry_no';
    
    INSERT INTO purchase_entries (
        entry_no, sup_inv_no, sup_inv_date, financial_year, date, supplier_name,
        done_by, subtotal, discount_amount, other_charge, round_off, net_amount,
        inv_total, remarks, payment_status, payment_mode, branch_id, updated_at
    ) VALUES (
        v_entry_no,
        p_purchase->>'sup_inv_no',
        p_purchase->>'sup_inv_date',
        p_purchase->>'financial_year',
        p_purchase->>'date',
        p_purchase->>'supplier_name',
        p_purchase->>'done_by',
        COALESCE((p_purchase->>'subtotal')::NUMERIC, (p_purchase->>'sub_total')::NUMERIC, 0.0),
        COALESCE((p_purchase->>'discount_amount')::NUMERIC, (p_purchase->>'discount')::NUMERIC, 0.0),
        COALESCE((p_purchase->>'other_charge')::NUMERIC, 0.0),
        COALESCE((p_purchase->>'round_off')::NUMERIC, 0.0),
        COALESCE((p_purchase->>'net_amount')::NUMERIC, (p_purchase->>'grand_total')::NUMERIC, 0.0),
        COALESCE((p_purchase->>'inv_total')::NUMERIC, 0.0),
        p_purchase->>'remarks',
        COALESCE((p_purchase->>'payment_status')::INT, 0),
        COALESCE(p_purchase->>'payment_mode', 'CREDIT'),
        COALESCE(p_purchase->>'branch_id', 'MAIN_STORE'),
        NOW()
    )
    ON CONFLICT (entry_no) DO UPDATE SET
        supplier_name = EXCLUDED.supplier_name,
        sup_inv_no = EXCLUDED.sup_inv_no,
        net_amount = EXCLUDED.net_amount,
        inv_total = EXCLUDED.inv_total,
        updated_at = NOW();

    DELETE FROM purchase_items WHERE entry_no = v_entry_no;

    IF p_items IS NOT NULL THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
        LOOP
            INSERT INTO purchase_items (
                entry_no, product_id, product_name, batch_number, expiry_date,
                quantity, f_qty, packing, mrp, unit_price, gross, disc_percent,
                disc_amt, gst_percent, gst_amt, total_amount, branch_id
            ) VALUES (
                v_entry_no,
                v_item->>'product_id',
                v_item->>'product_name',
                COALESCE(v_item->>'batch_number', v_item->>'batch', ''),
                COALESCE(v_item->>'expiry_date', v_item->>'expiry', ''),
                COALESCE((v_item->>'quantity')::INT, (v_item->>'qty')::INT, 1),
                COALESCE((v_item->>'f_qty')::INT, 0),
                COALESCE((v_item->>'packing')::INT, (v_item->>'packin')::INT, 1),
                COALESCE((v_item->>'mrp')::NUMERIC, 0.0),
                COALESCE((v_item->>'unit_price')::NUMERIC, (v_item->>'p_rate')::NUMERIC, 0.0),
                COALESCE((v_item->>'gross')::NUMERIC, 0.0),
                COALESCE((v_item->>'disc_percent')::NUMERIC, 0.0),
                COALESCE((v_item->>'disc_amt')::NUMERIC, 0.0),
                COALESCE((v_item->>'gst_percent')::NUMERIC, 12.0),
                COALESCE((v_item->>'gst_amt')::NUMERIC, 0.0),
                COALESCE((v_item->>'total_amount')::NUMERIC, (v_item->>'total')::NUMERIC, 0.0),
                COALESCE(v_item->>'branch_id', 'MAIN_STORE')
            );
        END LOOP;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 1. Categories Table
CREATE TABLE IF NOT EXISTS categories (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  is_active INTEGER DEFAULT 1,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Manufacturers Table
CREATE TABLE IF NOT EXISTS manufacturers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  is_active INTEGER DEFAULT 1,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Racks Table
CREATE TABLE IF NOT EXISTS racks (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  is_active INTEGER DEFAULT 1,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. Generics Table
CREATE TABLE IF NOT EXISTS generics (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  use TEXT,
  is_active INTEGER DEFAULT 1,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. Suppliers Table
CREATE TABLE IF NOT EXISTS suppliers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT,
  mobile TEXT,
  address TEXT,
  email TEXT,
  gst_in TEXT,
  dl_number TEXT,
  current_balance REAL DEFAULT 0.0,
  is_active INTEGER DEFAULT 1,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 6. Doctors Table
CREATE TABLE IF NOT EXISTS doctors (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  mobile TEXT,
  specialization TEXT,
  reg_no TEXT,
  is_active INTEGER DEFAULT 1,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 7. Accounts Table
CREATE TABLE IF NOT EXISTS accounts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT,
  balance REAL DEFAULT 0.0,
  is_active INTEGER DEFAULT 1,
  color TEXT,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 8. Staff Table
CREATE TABLE IF NOT EXISTS staff (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT,
  role TEXT,
  code TEXT,
  is_active INTEGER DEFAULT 1,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 9. Product Master Table
CREATE TABLE IF NOT EXISTS product_master (
  id TEXT PRIMARY KEY,
  product_name TEXT NOT NULL,
  generic_name TEXT,
  category_id TEXT,
  sub_category_id TEXT,
  manufacturer_id TEXT,
  rack_id TEXT,
  hsn_code TEXT,
  gst_rate REAL DEFAULT 12.0,
  s_disc_percent REAL DEFAULT 0.0,
  schedule TEXT DEFAULT 'H',
  mrp REAL DEFAULT 0.0,
  purchase_rate REAL DEFAULT 0.0,
  selling_price REAL DEFAULT 0.0,
  reorder_level INTEGER DEFAULT 10,
  max_level INTEGER DEFAULT 100,
  unit TEXT DEFAULT 'Strip',
  packing INTEGER DEFAULT 10,
  patent TEXT,
  barcode TEXT,
  is_controlled INTEGER DEFAULT 0,
  is_banned INTEGER DEFAULT 0,
  is_nrx INTEGER DEFAULT 0,
  is_active INTEGER DEFAULT 1,
  is_disc_locked INTEGER DEFAULT 0,
  preferred_wholesale TEXT,
  lead_time INTEGER DEFAULT 2,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 10. Stock Batches Table
CREATE TABLE IF NOT EXISTS stock_batches (
  id TEXT PRIMARY KEY,
  product_id TEXT REFERENCES product_master(id) ON DELETE CASCADE,
  batch_number TEXT NOT NULL,
  expiry_date TEXT NOT NULL,
  mfg_date TEXT,
  purchase_rate REAL DEFAULT 0.0,
  landing_cost REAL DEFAULT 0.0,
  mrp REAL DEFAULT 0.0,
  selling_rate REAL DEFAULT 0.0,
  current_quantity INTEGER DEFAULT 0,
  s_disc_percent REAL DEFAULT 0.0,
  gst_percent REAL DEFAULT 12.0,
  rack TEXT,
  supplier_name TEXT,
  packing INTEGER DEFAULT 1,
  is_active INTEGER DEFAULT 1,
  financial_year TEXT,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  CONSTRAINT chk_stock_non_negative CHECK (current_quantity >= 0)
);

-- 11. Sales Invoices Table
CREATE TABLE IF NOT EXISTS sales_invoices (
  entry_no TEXT PRIMARY KEY,
  invoice_no TEXT,
  financial_year TEXT,
  date TEXT NOT NULL,
  customer_acc TEXT,
  customer_name TEXT,
  patient TEXT,
  customer_phone TEXT,
  mobile TEXT,
  doctor TEXT,
  doctor_reg_no TEXT,
  done_by TEXT,
  terminal_id TEXT DEFAULT 'POS-01',
  shift_id TEXT,
  patient_age INT DEFAULT 0,
  patient_gender TEXT,
  patient_address TEXT,
  gstin_number TEXT,
  place_of_supply TEXT,
  subtotal REAL DEFAULT 0.0,
  sub_total REAL DEFAULT 0.0,
  discount_amount REAL DEFAULT 0.0,
  discount REAL DEFAULT 0.0,
  discount_percent REAL DEFAULT 0.0,
  additional_discount REAL DEFAULT 0.0,
  other_charge REAL DEFAULT 0.0,
  tax_amount REAL DEFAULT 0.0,
  tax REAL DEFAULT 0.0,
  round_off REAL DEFAULT 0.0,
  net_amount REAL DEFAULT 0.0,
  grand_total REAL DEFAULT 0.0,
  total_amount REAL DEFAULT 0.0,
  rcvd_amt REAL DEFAULT 0.0,
  payment_mode TEXT DEFAULT 'CASH',
  payment_remarks TEXT,
  secondary_acc TEXT,
  secondary_amt REAL DEFAULT 0.0,
  is_deleted INTEGER DEFAULT 0,
  is_paid INTEGER DEFAULT 1,
  tax_type TEXT DEFAULT 'Non Gst',
  agent TEXT DEFAULT 'Admin',
  sales_return_amt REAL DEFAULT 0.0,
  order_type INTEGER DEFAULT 0,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 12. Sales Items Table
CREATE TABLE IF NOT EXISTS sales_items (
  id BIGSERIAL PRIMARY KEY,
  invoice_no TEXT REFERENCES sales_invoices(entry_no) ON DELETE CASCADE,
  product_id TEXT,
  product_name TEXT,
  extra TEXT,
  batch_number TEXT,
  expiry_date TEXT,
  quantity INTEGER DEFAULT 1,
  f_qty INTEGER DEFAULT 0,
  hsn_code TEXT,
  schedule TEXT,
  packing INTEGER DEFAULT 1,
  mrp REAL DEFAULT 0.0,
  purchase_rate REAL DEFAULT 0.0,
  landing_cost REAL DEFAULT 0.0,
  taxable_sp REAL DEFAULT 0.0,
  unit_price REAL DEFAULT 0.0,
  disc_percent REAL DEFAULT 0.0,
  disc_amt REAL DEFAULT 0.0,
  gst_percent REAL DEFAULT 12.0,
  gst_amt REAL DEFAULT 0.0,
  cgst_amt REAL DEFAULT 0.0,
  sgst_amt REAL DEFAULT 0.0,
  igst_amt REAL DEFAULT 0.0,
  total_amount REAL DEFAULT 0.0,
  profit REAL DEFAULT 0.0,
  supplier_name TEXT,
  rack TEXT,
  is_deleted INTEGER DEFAULT 0,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  terminal_id TEXT DEFAULT 'POS-01',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- SAFELY ENSURE ALL ENTERPRISE & COMPATIBILITY COLUMNS EXIST ON PRE-EXISTING TABLES
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS customer_acc TEXT;
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS customer_name TEXT;
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS patient TEXT;
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS customer_phone TEXT;
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS mobile TEXT;
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS subtotal REAL DEFAULT 0.0;
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS sub_total REAL DEFAULT 0.0;
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS discount_amount REAL DEFAULT 0.0;
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS discount REAL DEFAULT 0.0;
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS tax_amount REAL DEFAULT 0.0;
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS tax REAL DEFAULT 0.0;
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS net_amount REAL DEFAULT 0.0;
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS grand_total REAL DEFAULT 0.0;
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS total_amount REAL DEFAULT 0.0;
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS done_by TEXT;
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS shift_id TEXT;
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS patient_age INT DEFAULT 0;
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS patient_gender TEXT;
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS patient_address TEXT;
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS gstin_number TEXT;
ALTER TABLE public.sales_invoices ADD COLUMN IF NOT EXISTS place_of_supply TEXT;

ALTER TABLE public.sales_items ADD COLUMN IF NOT EXISTS purchase_rate REAL DEFAULT 0.0;
ALTER TABLE public.sales_items ADD COLUMN IF NOT EXISTS landing_cost REAL DEFAULT 0.0;
ALTER TABLE public.sales_items ADD COLUMN IF NOT EXISTS taxable_sp REAL DEFAULT 0.0;
ALTER TABLE public.sales_items ADD COLUMN IF NOT EXISTS f_qty INT DEFAULT 0;
ALTER TABLE public.sales_items ADD COLUMN IF NOT EXISTS hsn_code TEXT;
ALTER TABLE public.sales_items ADD COLUMN IF NOT EXISTS schedule TEXT;
ALTER TABLE public.sales_items ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';

-- 13. Sales Return Invoices Table
CREATE TABLE IF NOT EXISTS sales_return_invoices (
  entry_no TEXT PRIMARY KEY,
  date TEXT NOT NULL,
  customer_acc TEXT,
  patient TEXT,
  doctor TEXT,
  sub_total REAL DEFAULT 0.0,
  discount REAL DEFAULT 0.0,
  tax REAL DEFAULT 0.0,
  round_off REAL DEFAULT 0.0,
  grand_total REAL DEFAULT 0.0,
  narration TEXT,
  gst_mode INTEGER DEFAULT 1,
  original_invoice_no TEXT,
  is_deleted INTEGER DEFAULT 0,
  financial_year TEXT,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 14. Sales Return Items Table
CREATE TABLE IF NOT EXISTS sales_return_items (
  id BIGSERIAL PRIMARY KEY,
  return_no TEXT REFERENCES sales_return_invoices(entry_no) ON DELETE CASCADE,
  product_id TEXT,
  product_name TEXT,
  batch_number TEXT,
  expiry_date TEXT,
  quantity INTEGER DEFAULT 1,
  mrp REAL DEFAULT 0.0,
  sale_rate REAL DEFAULT 0.0,
  disc_percent REAL DEFAULT 0.0,
  disc_amt REAL DEFAULT 0.0,
  hsn_code TEXT,
  total REAL DEFAULT 0.0,
  purchase_rate REAL DEFAULT 0.0,
  landing_cost REAL DEFAULT 0.0,
  supplier_name TEXT,
  packing INTEGER DEFAULT 1,
  gst_percent REAL DEFAULT 12.0,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 15. Purchase Entries Table
CREATE TABLE IF NOT EXISTS purchase_entries (
  entry_no TEXT PRIMARY KEY,
  sup_inv_no TEXT,
  sup_inv_date TEXT,
  financial_year TEXT,
  date TEXT NOT NULL,
  supplier_name TEXT,
  done_by TEXT,
  subtotal REAL DEFAULT 0.0,
  discount_amount REAL DEFAULT 0.0,
  other_charge REAL DEFAULT 0.0,
  tax_amount REAL DEFAULT 0.0,
  round_off REAL DEFAULT 0.0,
  net_amount REAL DEFAULT 0.0,
  inv_total REAL DEFAULT 0.0,
  remarks TEXT,
  payment_status INTEGER DEFAULT 0,
  payment_mode TEXT DEFAULT 'CREDIT',
  payment_remarks TEXT,
  payment_date TEXT,
  paid_amount REAL DEFAULT 0.0,
  days INTEGER DEFAULT 0,
  is_deleted INTEGER DEFAULT 0,
  tax_type TEXT DEFAULT 'Gst',
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 16. Purchase Items Table
CREATE TABLE IF NOT EXISTS purchase_items (
  id BIGSERIAL PRIMARY KEY,
  entry_no TEXT REFERENCES purchase_entries(entry_no) ON DELETE CASCADE,
  product_id TEXT,
  product_name TEXT,
  extra TEXT,
  batch_number TEXT,
  expiry_date TEXT,
  quantity INTEGER DEFAULT 1,
  f_qty INTEGER DEFAULT 0,
  packing INTEGER DEFAULT 1,
  mrp REAL DEFAULT 0.0,
  unit_price REAL DEFAULT 0.0,
  gross REAL DEFAULT 0.0,
  disc_percent REAL DEFAULT 0.0,
  disc_amt REAL DEFAULT 0.0,
  gst_percent REAL DEFAULT 12.0,
  gst_amt REAL DEFAULT 0.0,
  total_amount REAL DEFAULT 0.0,
  rack TEXT,
  hsn_code TEXT,
  s_disc_percent REAL DEFAULT 0.0,
  selling_rate REAL DEFAULT 0.0,
  landing_cost REAL DEFAULT 0.0,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  terminal_id TEXT DEFAULT 'POS-01',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.purchase_items ADD COLUMN IF NOT EXISTS terminal_id TEXT DEFAULT 'POS-01';

-- 17. Purchase Return Entries Table
CREATE TABLE IF NOT EXISTS purchase_return_entries (
  entry_no TEXT PRIMARY KEY,
  date TEXT NOT NULL,
  supplier_name TEXT,
  original_purchase_no TEXT,
  done_by TEXT,
  grand_total REAL DEFAULT 0.0,
  gst_mode INTEGER DEFAULT 1,
  is_deleted INTEGER DEFAULT 0,
  financial_year TEXT,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 18. Purchase Return Items Table
CREATE TABLE IF NOT EXISTS purchase_return_items (
  id BIGSERIAL PRIMARY KEY,
  entry_no TEXT REFERENCES purchase_return_entries(entry_no) ON DELETE CASCADE,
  product_name TEXT,
  batch_number TEXT,
  expiry_date TEXT,
  quantity INTEGER DEFAULT 1,
  loose_qty INTEGER DEFAULT 0,
  f_qty INTEGER DEFAULT 0,
  unit TEXT,
  packing INTEGER DEFAULT 1,
  mrp REAL DEFAULT 0.0,
  unit_price REAL DEFAULT 0.0,
  selling_rate REAL DEFAULT 0.0,
  disc_percent REAL DEFAULT 0.0,
  gst_percent REAL DEFAULT 12.0,
  total REAL DEFAULT 0.0,
  reason TEXT,
  supplier TEXT,
  hsn_code TEXT,
  sup_inv_no TEXT,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 19. Stock Adjustments Table
CREATE TABLE IF NOT EXISTS stock_adjustments (
  entry_no TEXT PRIMARY KEY,
  date TEXT NOT NULL,
  done_by TEXT,
  reason TEXT,
  grand_total REAL DEFAULT 0.0,
  is_deleted INTEGER DEFAULT 0,
  financial_year TEXT,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 20. Stock Adjustment Items Table
CREATE TABLE IF NOT EXISTS stock_adjustment_items (
  id BIGSERIAL PRIMARY KEY,
  adjustment_no TEXT REFERENCES stock_adjustments(entry_no) ON DELETE CASCADE,
  product_id TEXT,
  batch_number TEXT,
  qty INTEGER DEFAULT 0,
  purchase_rate REAL DEFAULT 0.0,
  total REAL DEFAULT 0.0,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 21. Stock Write Offs (Damages) Table
CREATE TABLE IF NOT EXISTS stock_write_offs (
  id TEXT PRIMARY KEY,
  date TEXT NOT NULL,
  product_id TEXT,
  batch_number TEXT,
  quantity INTEGER DEFAULT 0,
  reason TEXT,
  loss_value REAL DEFAULT 0.0,
  financial_year TEXT,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 22. Patients Table
CREATE TABLE IF NOT EXISTS patients (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  mobile TEXT,
  address TEXT,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 23. Patient Payments Table
CREATE TABLE IF NOT EXISTS patient_payments (
  id TEXT PRIMARY KEY,
  patient_name TEXT,
  date TEXT,
  amount REAL DEFAULT 0.0,
  invoice_no TEXT,
  payment_method TEXT,
  remarks TEXT,
  is_deleted INTEGER DEFAULT 0,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 24. Supplier Payments Table
CREATE TABLE IF NOT EXISTS supplier_payments (
  id TEXT PRIMARY KEY,
  supplier_name TEXT,
  date TEXT,
  amount REAL DEFAULT 0.0,
  invoice_no TEXT,
  payment_method TEXT,
  remarks TEXT,
  is_deleted INTEGER DEFAULT 0,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 25. Supplier Credit Notes Table
CREATE TABLE IF NOT EXISTS supplier_credit_notes (
  id TEXT PRIMARY KEY,
  supplier_name TEXT,
  date TEXT,
  amount REAL DEFAULT 0.0,
  invoice_no TEXT,
  remarks TEXT,
  is_deleted INTEGER DEFAULT 0,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 26. Prescriptions Table
CREATE TABLE IF NOT EXISTS prescriptions (
  id TEXT PRIMARY KEY,
  prescription_no INTEGER DEFAULT 0,
  patient_name TEXT,
  doctor_name TEXT,
  disease_name TEXT,
  mobile TEXT,
  days INTEGER DEFAULT 0,
  date TEXT,
  sale_entry_no TEXT,
  is_active INTEGER DEFAULT 1,
  is_imported INTEGER DEFAULT 0,
  is_deleted INTEGER DEFAULT 0,
  financial_year TEXT,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 27. Prescription Items Table
CREATE TABLE IF NOT EXISTS prescription_items (
  id BIGSERIAL PRIMARY KEY,
  prescription_id TEXT REFERENCES prescriptions(id) ON DELETE CASCADE,
  name TEXT,
  qty REAL DEFAULT 0.0,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 28. Cloud Audit & Telemetry Logging Tables
CREATE TABLE IF NOT EXISTS cloud_audit_logs (
  id BIGSERIAL PRIMARY KEY,
  action TEXT NOT NULL,
  details TEXT,
  severity TEXT DEFAULT 'INFO',
  reference_id TEXT,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  terminal_id TEXT DEFAULT 'POS-01',
  timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS telemetry_logs (
  id BIGSERIAL PRIMARY KEY,
  event_name TEXT NOT NULL,
  error_message TEXT,
  metadata TEXT,
  branch_id TEXT DEFAULT 'MAIN_STORE',
  terminal_id TEXT DEFAULT 'POS-01',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ========================================================
-- INDEXES & PERFORMANCE
-- ========================================================
CREATE INDEX IF NOT EXISTS idx_prod_master_branch ON product_master(branch_id);
CREATE INDEX IF NOT EXISTS idx_prod_master_updated ON product_master(updated_at);
CREATE INDEX IF NOT EXISTS idx_stock_batches_branch_prod ON stock_batches(branch_id, product_id);
CREATE INDEX IF NOT EXISTS idx_stock_batches_updated ON stock_batches(updated_at);
CREATE INDEX IF NOT EXISTS idx_sales_inv_branch_fy ON sales_invoices(branch_id, financial_year);
CREATE INDEX IF NOT EXISTS idx_sales_inv_updated ON sales_invoices(updated_at);
CREATE INDEX IF NOT EXISTS idx_sales_items_inv ON sales_items(invoice_no);
CREATE INDEX IF NOT EXISTS idx_pur_entries_branch_fy ON purchase_entries(branch_id, financial_year);
CREATE INDEX IF NOT EXISTS idx_pur_items_entry ON purchase_items(entry_no);
CREATE INDEX IF NOT EXISTS idx_sales_ret_inv_branch ON sales_return_invoices(branch_id);
CREATE INDEX IF NOT EXISTS idx_pur_ret_entries_branch ON purchase_return_entries(branch_id);
CREATE INDEX IF NOT EXISTS idx_stock_adj_branch ON stock_adjustments(branch_id);
CREATE INDEX IF NOT EXISTS idx_stock_wo_branch ON stock_write_offs(branch_id);

-- ========================================================
-- ENABLE REALTIME PUBLICATION FOR MULTI-PC SCREEN SYNC
-- ========================================================
DO $$ 
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'sales_invoices') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE sales_invoices;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'purchase_entries') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE purchase_entries;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'product_master') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE product_master;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'stock_batches') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE stock_batches;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'stock_adjustments') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE stock_adjustments;
  END IF;
END $$;

-- Enable Row Level Security (RLS) & Grant App Permissions
DO $$ 
DECLARE
  t text;
BEGIN
  FOR t IN SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS "Allow All Access" ON public.%I', t);
    EXECUTE format('CREATE POLICY "Allow All Access" ON public.%I FOR ALL TO anon, authenticated USING (true) WITH CHECK (true)', t);
  END LOOP;
END $$;

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
''';
  }
}

List<dynamic> _parseJsonListIsolate(String body) => jsonDecode(body) as List<dynamic>;

