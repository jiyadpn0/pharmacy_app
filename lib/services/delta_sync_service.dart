import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';
import '../database/db_helper.dart';
import '../utils/app_logger.dart';
import '../utils/app_formatters.dart';
import 'supabase_sync_service.dart';
import 'server_config_service.dart';
import 'stock_outbox_service.dart';

/// Non-blocking, incremental background sync engine (Delta Sync).
/// Periodically syncs unsynced local invoices and fetches changed products/stock
/// from central server without blocking the UI billing thread.
class DeltaSyncService {
  static final DeltaSyncService instance = DeltaSyncService._init();
  DeltaSyncService._init();

  final _lock = Lock();
  Timer? _syncTimer;
  int _consecutiveFailures = 0;
  final Random _random = Random();
  bool _isSyncing = false;

  bool get isSyncing => _isSyncing;

  /// Starts background adaptive periodic delta sync with exponential backoff & jitter
  void startPeriodicSync({Duration? interval}) {
    stopPeriodicSync();
    _scheduleNextSync(interval ?? const Duration(seconds: 10));
    debugPrint("DeltaSyncService: Adaptive periodic sync started.");
  }

  void _scheduleNextSync(Duration delay) {
    _syncTimer?.cancel();
    _syncTimer = Timer(delay, () async {
      final success = await _executeDeltaSyncCycle();
      if (success) {
        _consecutiveFailures = 0;
        // Normal cadence: 10 to 15 seconds randomized jitter
        final nextDelaySec = 10 + _random.nextInt(6);
        _scheduleNextSync(Duration(seconds: nextDelaySec));
      } else {
        _consecutiveFailures++;
        // Exponential backoff capped at 120 seconds + randomized jitter
        final backoffBase = min(120, 10 * pow(2, min(_consecutiveFailures, 4)).toInt());
        final jitter = _random.nextInt(10);
        final nextDelaySec = backoffBase + jitter;
        debugPrint("DeltaSyncService: Retry scheduled in ${nextDelaySec}s (Failure count: $_consecutiveFailures)");
        _scheduleNextSync(Duration(seconds: nextDelaySec));
      }
    });
  }

  /// Stops background periodic sync worker loop
  void stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    debugPrint("DeltaSyncService: Background periodic sync stopped.");
  }

  /// Triggers a non-blocking background delta sync run
  Future<bool> triggerBackgroundSync({bool forcePostSave = false}) async {
    return await _executeDeltaSyncCycle(forcePostSave: forcePostSave);
  }

  /// Runs incremental catch-up delta sync (SELECT * WHERE updated_at > last_sync_time)
  /// upon network reconnection to recover any missed invoices or inventory updates within 15–20s.
  Future<bool> triggerReconnectionCatchupSync() async {
    SupabaseSyncService.instance.checkAndHealStuckRecoveryLock();
    if (_isSyncing || SupabaseSyncService.instance.isSyncing) {
      debugPrint("DeltaSyncService: Catch-up sync skipped because a sync cycle is already running.");
      return false;
    }
    if (SupabaseSyncService.instance.isRecoveryLocked || SupabaseSyncService.instance.isSyncPaused) {
      debugPrint("DeltaSyncService: Catch-up sync skipped because sync is paused.");
      return false;
    }
    final config = ServerConfigService.instance;
    if (config.isWiping || SupabaseSyncService.instance.isWiping) return false;
    if (!config.isServerModeEnabled || !config.isConnected) return false;

    // Drain durable outbox upon reconnection and reconcile stock
    await StockOutboxService.instance.drainOutbox();
    await StockOutboxService.instance.reconcileLocalStockFromCloud();

    return await _executeDeltaSyncCycle(forcePostSave: true);
  }

  /// Executes one cycle of background delta sync
  Future<bool> _executeDeltaSyncCycle({bool forcePostSave = false}) async {
    SupabaseSyncService.instance.checkAndHealStuckRecoveryLock();

    if (_isSyncing) return true;

    if (SupabaseSyncService.instance.isRecoveryLocked || SupabaseSyncService.instance.isSyncPaused) {
      debugPrint("DeltaSyncService: Cycle skipped due to Active Invoice Recovery Lock.");
      return true;
    }

    final config = ServerConfigService.instance;
    if (config.isWiping || SupabaseSyncService.instance.isWiping || SupabaseSyncService.instance.isSyncing || DbHelper.isBillingActive) {
      return true;
    }
    if (!config.isServerModeEnabled || !config.isConnected || !config.autoSyncEnabled) {
      return true; // Exit instantly if offline, server disconnected, or auto sync disabled
    }

    return await _lock.synchronized(() async {
      if (config.isWiping || SupabaseSyncService.instance.isWiping) return true;
      if (_isSyncing || SupabaseSyncService.instance.isRecoveryLocked || SupabaseSyncService.instance.isSyncPaused) {
        return true;
      }
      _isSyncing = true;
      try {
        final prefs = await SharedPreferences.getInstance();

        // 0. Drain durable local outbox first so pending atomic stock mutations reach server
        await StockOutboxService.instance.drainOutbox();

        // 1. Check for cloud resets / fetch missing cloud records across sales, purchases, and adjustments FIRST
        await SupabaseSyncService.instance.syncAllPendingCloudRecords();
        if (SupabaseSyncService.instance.isSyncPaused) return false;

        // 1b. Catch-up modified stock batches from Supabase Cloud (chunked delta with clock drift tolerance)
        try {
          final lastStockSyncStr = prefs.getString('last_stock_delta_sync_timestamp');
          DateTime? sinceDate;
          if (lastStockSyncStr != null && lastStockSyncStr.isNotEmpty) {
            sinceDate = DateTime.tryParse(lastStockSyncStr);
          }
          await StockOutboxService.instance.reconcileLocalStockFromCloud(since: sinceDate);
          await prefs.setString('last_stock_delta_sync_timestamp', DateTime.now().toUtc().toIso8601String());
        } catch (stockCatchErr) {
          debugPrint("DeltaSyncService stock catch-up notice: $stockCatchErr");
        }

        // 2. Push local unsynced sales invoices (if any remain)
        await _pushUnsyncedSales();
        if (SupabaseSyncService.instance.isSyncPaused) return false;

        // 3. Push local unsynced stock adjustments & purchases (if any remain)
        await _pushUnsyncedPurchases();
        if (SupabaseSyncService.instance.isSyncPaused) return false;

        // 3b. Push local unsynced stock batches (if any remain)
        await _pushUnsyncedStockBatches();
        if (SupabaseSyncService.instance.isSyncPaused) return false;

        // 3c. Push local unsynced sales returns & purchase returns (if any remain)
        await _pushUnsyncedSalesReturns();
        if (SupabaseSyncService.instance.isSyncPaused) return false;
        await _pushUnsyncedPurchaseReturns();
        if (SupabaseSyncService.instance.isSyncPaused) return false;

        // 3d. Push local unsynced stock adjustments (if any remain)
        await _pushUnsyncedStockAdjustments();
        if (SupabaseSyncService.instance.isSyncPaused) return false;

        // 3e. Push local unsynced patients & suppliers (if any remain)
        await _pushUnsyncedPatients();
        if (SupabaseSyncService.instance.isSyncPaused) return false;
        await _pushUnsyncedSuppliers();
        if (SupabaseSyncService.instance.isSyncPaused) return false;

        // 3f. Push newly registered products (if any remain)
        await _pushUnsyncedProducts();
        if (SupabaseSyncService.instance.isSyncPaused) return false;

        // 4. Automated Daily Snapshot Download check (runs once per calendar day) - Disabled in Pure Cloud mode
        final todayStr = DateTime.now().toIso8601String().substring(0, 10);
        final lastSnapshotDate = prefs.getString('last_daily_snapshot_date') ?? '';
        if (!config.isPureCloud && lastSnapshotDate != todayStr && !DbHelper.isBillingActive && !SupabaseSyncService.instance.isSyncPaused) {
          final success = await SupabaseSyncService.instance.downloadTodayCompleteSnapshot();
          if (success) {
            await prefs.setString('last_daily_snapshot_date', todayStr);
          }
        }

        if (SupabaseSyncService.instance.isSyncPaused) return false;

        // 5. Trigger Supabase pending data sync (disabled in Pure Cloud mode to prevent bulk PC data export)
        if (!config.isPureCloud) {
          await SupabaseSyncService.instance.syncAllPendingData().timeout(const Duration(seconds: 45));
        }

        // 6. Update last delta sync timestamp
        final nowStr = DateTime.now().toUtc().toIso8601String();
        await prefs.setString('last_delta_sync_timestamp', nowStr);
        return true;
      } catch (e) {
        debugPrint("DeltaSyncService background sync notice: $e");
        return false;
      } finally {
        _isSyncing = false;
      }
    });
  }

  /// Pushes local unsynced sales invoices to central server in background
  Future<void> _pushUnsyncedSales() async {
    if (SupabaseSyncService.instance.isRecoveryLocked || SupabaseSyncService.instance.isSyncPaused) {
      debugPrint("DeltaSyncService: _pushUnsyncedSales skipped due to Recovery Lock.");
      return;
    }

    final config = ServerConfigService.instance;
    if (config.isWiping || SupabaseSyncService.instance.isWiping || SupabaseSyncService.instance.isSyncing || !config.isServerModeEnabled || !config.isConnected) return;

    try {
      final db = await DbHelper.instance.database;

      final unsyncedSales = await db.query(
        'sales_invoices',
        where: 'is_synced = 0 OR is_cloud_synced = 0',
        limit: 20,
      );

      if (unsyncedSales.isEmpty) return;
      AppLogger.instance.supabase("Found ${unsyncedSales.length} unsynced sales invoices. Syncing in background...");

      for (var sale in unsyncedSales) {
        if (SupabaseSyncService.instance.isRecoveryLocked || SupabaseSyncService.instance.isSyncPaused) {
          debugPrint("DeltaSyncService: Aborting sale push loop due to Recovery Lock.");
          return;
        }

        final saleTerminal = (sale['terminal_id']?.toString() ?? '').trim().toUpperCase();
        if (saleTerminal.isNotEmpty && saleTerminal != config.terminalId.trim().toUpperCase()) {
          // Skip foreign terminal entries: this terminal is not the owner of this sale invoice!
          continue;
        }

        if (DbHelper.isBillingActive) {
          await Future.delayed(const Duration(milliseconds: 100));
        }

        final invNo = sale['invoice_no'] as String? ?? sale['entry_no'] as String?;
        if (invNo == null || invNo.isEmpty) continue;

        try {
          final cleanInv = cleanEntryNo(invNo);
          var items = await db.rawQuery(
            "SELECT * FROM sales_items WHERE invoice_no = ? OR invoice_no = ? OR invoice_no LIKE ? ESCAPE '\\'",
            [invNo, cleanInv, "%\\_$cleanInv"],
          );

          final grandTotal = (sale['grand_total'] as num?)?.toDouble() ?? 0.0;
          final isDel = (sale['is_deleted'] as num?)?.toInt() ?? 0;

          if (items.isEmpty) {
            if (grandTotal <= 0 && isDel == 0) {
              debugPrint("DeltaSyncService: Marking empty item draft invoice $invNo as synced.");
              await db.rawUpdate(
                'UPDATE sales_invoices SET is_synced = 1, is_cloud_synced = 1 WHERE entry_no = ? OR invoice_no = ?',
                [invNo, invNo],
              );
            } else {
              debugPrint("DeltaSyncService: Invoice $invNo has total $grandTotal but no items found; leaving dirty for retry.");
            }
            continue;
          }

          final success = await SupabaseSyncService.instance.pushSalesInvoice(
            Map<String, dynamic>.from(sale),
            items.map((it) => Map<String, dynamic>.from(it)).toList(),
          ).timeout(const Duration(seconds: 10), onTimeout: () {
            AppLogger.instance.warn("SUPABASE", "pushSalesInvoice timed out for $invNo");
            return false;
          });

          if (success) {
            await db.rawUpdate(
              'UPDATE sales_invoices SET is_synced = 1, is_cloud_synced = 1 WHERE entry_no = ? OR invoice_no = ?',
              [invNo, invNo],
            );
            await db.rawUpdate(
              'UPDATE sales_items SET is_synced = 1, is_cloud_synced = 1 WHERE invoice_no = ?',
              [invNo],
            );
            AppLogger.instance.supabase("Successfully synced sales invoice $invNo to cloud.");
          } else {
            AppLogger.instance.warn("SUPABASE", "Invoice $invNo push pending / failed.");
          }
        } catch (err) {
          AppLogger.instance.error("SUPABASE", "DeltaSyncService error syncing invoice $invNo", error: err);
          // Continue loop to allow other invoices to sync rather than crashing the batch
        }
      }
    } catch (e) {
      AppLogger.instance.error("SUPABASE", "DeltaSyncService _pushUnsyncedSales error", error: e);
    }
  }

  /// Pushes local unsynced purchase entries to central server in background
  Future<void> _pushUnsyncedPurchases() async {
    if (SupabaseSyncService.instance.isRecoveryLocked || SupabaseSyncService.instance.isSyncPaused) {
      debugPrint("DeltaSyncService: _pushUnsyncedPurchases skipped due to Recovery Lock.");
      return;
    }

    final config = ServerConfigService.instance;
    if (config.isWiping || SupabaseSyncService.instance.isWiping || SupabaseSyncService.instance.isSyncing || !config.isServerModeEnabled || !config.isConnected) return;

    try {
      await SupabaseSyncService.instance.checkDatabaseEpoch();
      final db = await DbHelper.instance.database;

      final unsyncedPurchases = await db.query(
        'purchase_entries',
        where: 'is_synced = 0 OR is_cloud_synced = 0',
        limit: 20,
      );

      if (unsyncedPurchases.isEmpty) return;

      for (var purchase in unsyncedPurchases) {
        if (SupabaseSyncService.instance.isRecoveryLocked || SupabaseSyncService.instance.isSyncPaused) {
          debugPrint("DeltaSyncService: Aborting purchase push loop due to Recovery Lock.");
          return;
        }

        final purTerminal = (purchase['terminal_id']?.toString() ?? '').trim().toUpperCase();
        if (purTerminal.isNotEmpty && purTerminal != config.terminalId.trim().toUpperCase()) {
          // Skip foreign terminal entries: this terminal is not the owner of this purchase entry!
          continue;
        }

        if (DbHelper.isBillingActive) {
          await Future.delayed(const Duration(milliseconds: 100));
        }

        final entryNo = purchase['entry_no'] as String?;
        if (entryNo == null || entryNo.isEmpty) continue;

        try {
          final cleanEnt = cleanEntryNo(entryNo);
          var items = await db.rawQuery(
            "SELECT * FROM purchase_items WHERE entry_no = ? OR entry_no = ? OR entry_no LIKE ? ESCAPE '\\'",
            [entryNo, cleanEnt, "%\\_$cleanEnt"],
          );

          final grandTotal = (purchase['grand_total'] as num?)?.toDouble() ?? (purchase['inv_total'] as num?)?.toDouble() ?? 0.0;
          if (items.isEmpty) {
            if (grandTotal <= 0) {
              debugPrint("DeltaSyncService: Marking empty item purchase $entryNo as synced (no line items).");
              await db.rawUpdate(
                'UPDATE purchase_entries SET is_synced = 1, is_cloud_synced = 1 WHERE entry_no = ?',
                [entryNo],
              );
            } else {
              debugPrint("DeltaSyncService: Purchase $entryNo has total $grandTotal but no items found; leaving dirty for retry.");
            }
            continue;
          }

          bool synced = await SupabaseSyncService.instance.savePurchaseEntryAtomicRPC(
            purchaseHeader: Map<String, dynamic>.from(purchase),
            items: items.map((it) => Map<String, dynamic>.from(it)).toList(),
          );

          if (!synced) {
            synced = await SupabaseSyncService.instance.pushPurchaseEntry(
              Map<String, dynamic>.from(purchase),
              items.map((it) => Map<String, dynamic>.from(it)).toList(),
            ).timeout(const Duration(seconds: 15), onTimeout: () {
              AppLogger.instance.warn("SUPABASE", "pushPurchaseEntry timed out for $entryNo");
              return false;
            });
          }

          if (synced) {
            await DbHelper.instance.runWriteQuery((dbHandle) async {
              await dbHandle.update(
                'purchase_entries',
                {'is_synced': 1, 'is_cloud_synced': 1},
                where: 'entry_no = ?',
                whereArgs: [entryNo],
              );
              await dbHandle.update(
                'purchase_items',
                {'is_synced': 1, 'is_cloud_synced': 1},
                where: 'entry_no = ?',
                whereArgs: [entryNo],
              );
            });
            AppLogger.instance.supabase("Successfully synced purchase entry $entryNo to cloud.");
          } else {
            AppLogger.instance.error(
              "SUPABASE",
              "DeltaSyncService: Failed to sync purchase entry $entryNo to cloud; leaving dirty for retry.",
            );
          }
        } catch (err) {
          AppLogger.instance.error("SUPABASE", "DeltaSyncService error syncing purchase entry $entryNo", error: err);
          // Continue loop to allow other purchase entries to sync
        }
      }
    } catch (e) {
      AppLogger.instance.error("SUPABASE", "DeltaSyncService _pushUnsyncedPurchases error", error: e);
    }
  }

  /// Pushes local unsynced stock batches to central server in background
  Future<void> _pushUnsyncedStockBatches() async {
    if (SupabaseSyncService.instance.isRecoveryLocked || SupabaseSyncService.instance.isSyncPaused) {
      return;
    }

    final config = ServerConfigService.instance;
    if (config.isWiping || SupabaseSyncService.instance.isWiping || SupabaseSyncService.instance.isSyncing || !config.isServerModeEnabled || !config.isConnected) return;

    try {
      final db = await DbHelper.instance.database;
      final unsyncedBatches = await db.query(
        'stock_batches',
        where: 'is_synced = 0 OR is_synced IS NULL',
        limit: 50,
      );

      if (unsyncedBatches.isEmpty) return;

      for (var batch in unsyncedBatches) {
        if (SupabaseSyncService.instance.isRecoveryLocked || SupabaseSyncService.instance.isSyncPaused) return;
        await SupabaseSyncService.instance.pushStockBatch(batch);
      }
    } catch (e) {
      debugPrint("DeltaSyncService _pushUnsyncedStockBatches error: $e");
    }
  }

  /// Pushes local unsynced sales return receipts to central server in background
  Future<void> _pushUnsyncedSalesReturns() async {
    if (SupabaseSyncService.instance.isRecoveryLocked || SupabaseSyncService.instance.isSyncPaused) return;
    final config = ServerConfigService.instance;
    if (config.isWiping || SupabaseSyncService.instance.isWiping || SupabaseSyncService.instance.isSyncing || !config.isServerModeEnabled || !config.isConnected) return;

    try {
      final db = await DbHelper.instance.database;

      final unsyncedReturns = await db.query(
        'sales_return_invoices',
        where: 'is_synced = 0 OR is_synced IS NULL',
        limit: 20,
      );

      if (unsyncedReturns.isEmpty) return;

      for (var ret in unsyncedReturns) {
        if (SupabaseSyncService.instance.isRecoveryLocked || SupabaseSyncService.instance.isSyncPaused) return;
        final entryNo = ret['entry_no']?.toString() ?? '';
        if (entryNo.isEmpty) continue;

        try {
          final items = await db.query('sales_return_items', where: 'return_no = ?', whereArgs: [entryNo]);
          final ok = await SupabaseSyncService.instance.pushSalesReturn(
            Map<String, dynamic>.from(ret),
            items.map((it) => Map<String, dynamic>.from(it)).toList(),
          );
          if (ok) {
            AppLogger.instance.supabase("Successfully synced sales return receipt $entryNo to cloud.");
          }
        } catch (e) {
          debugPrint("DeltaSyncService _pushUnsyncedSalesReturns error for $entryNo: $e");
        }
      }
    } catch (e) {
      debugPrint("DeltaSyncService _pushUnsyncedSalesReturns error: $e");
    }
  }

  /// Pushes local unsynced purchase return entries to central server in background
  Future<void> _pushUnsyncedPurchaseReturns() async {
    if (SupabaseSyncService.instance.isRecoveryLocked || SupabaseSyncService.instance.isSyncPaused) return;
    final config = ServerConfigService.instance;
    if (config.isWiping || SupabaseSyncService.instance.isWiping || SupabaseSyncService.instance.isSyncing || !config.isServerModeEnabled || !config.isConnected) return;

    try {
      final db = await DbHelper.instance.database;

      final unsyncedReturns = await db.query(
        'purchase_return_entries',
        where: 'is_synced = 0 OR is_synced IS NULL',
        limit: 20,
      );

      if (unsyncedReturns.isEmpty) return;

      for (var ret in unsyncedReturns) {
        if (SupabaseSyncService.instance.isRecoveryLocked || SupabaseSyncService.instance.isSyncPaused) return;
        final entryNo = ret['entry_no']?.toString() ?? '';
        if (entryNo.isEmpty) continue;

        try {
          final items = await db.query('purchase_return_items', where: 'entry_no = ?', whereArgs: [entryNo]);
          final ok = await SupabaseSyncService.instance.pushPurchaseReturn(
            Map<String, dynamic>.from(ret),
            items.map((it) => Map<String, dynamic>.from(it)).toList(),
          );
          if (ok) {
            AppLogger.instance.supabase("Successfully synced purchase return entry $entryNo to cloud.");
          }
        } catch (e) {
          debugPrint("DeltaSyncService _pushUnsyncedPurchaseReturns error for $entryNo: $e");
        }
      }
    } catch (e) {
      debugPrint("DeltaSyncService _pushUnsyncedPurchaseReturns error: $e");
    }
  }

  /// Pushes local unsynced stock adjustments to central server in background
  Future<void> _pushUnsyncedStockAdjustments() async {
    if (SupabaseSyncService.instance.isRecoveryLocked || SupabaseSyncService.instance.isSyncPaused) return;
    final config = ServerConfigService.instance;
    if (config.isWiping || SupabaseSyncService.instance.isWiping || SupabaseSyncService.instance.isSyncing || !config.isServerModeEnabled || !config.isConnected) return;

    try {
      final db = await DbHelper.instance.database;

      final unsynced = await db.query(
        'stock_adjustments',
        where: 'is_synced = 0 OR is_synced IS NULL',
        limit: 20,
      );

      if (unsynced.isEmpty) return;

      for (var adj in unsynced) {
        if (SupabaseSyncService.instance.isRecoveryLocked || SupabaseSyncService.instance.isSyncPaused) return;
        final entryNo = adj['entry_no']?.toString() ?? '';
        if (entryNo.isEmpty) continue;

        try {
          final items = await db.query('stock_adjustment_items', where: 'adjustment_no = ?', whereArgs: [entryNo]);
          final ok = await SupabaseSyncService.instance.pushStockAdjustment(
            Map<String, dynamic>.from(adj),
            items.map((it) => Map<String, dynamic>.from(it)).toList(),
          );
          if (ok) {
            AppLogger.instance.supabase("Successfully synced stock adjustment $entryNo to cloud.");
          }
        } catch (e) {
          debugPrint("DeltaSyncService _pushUnsyncedStockAdjustments error for $entryNo: $e");
        }
      }
    } catch (e) {
      debugPrint("DeltaSyncService _pushUnsyncedStockAdjustments error: $e");
    }
  }

  /// Pushes local unsynced patients to central server in background
  Future<void> _pushUnsyncedPatients() async {
    if (SupabaseSyncService.instance.isRecoveryLocked || SupabaseSyncService.instance.isSyncPaused) return;
    final config = ServerConfigService.instance;
    if (config.isWiping || SupabaseSyncService.instance.isWiping || SupabaseSyncService.instance.isSyncing || !config.isServerModeEnabled || !config.isConnected) return;

    try {
      final db = await DbHelper.instance.database;
      final unsyncedPatients = await db.query(
        'patients',
        where: 'is_synced = 0 OR is_synced IS NULL',
        limit: 50,
      );

      if (unsyncedPatients.isEmpty) return;

      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
      final uri = Uri.parse('$cleanUrl/rest/v1/patients?on_conflict=id');
      final headers = Map<String, String>.from(config.restHeaders)..['Prefer'] = 'resolution=merge-duplicates';

      for (var p in unsyncedPatients) {
        if (SupabaseSyncService.instance.isRecoveryLocked || SupabaseSyncService.instance.isSyncPaused) return;
        var patId = (p['id']?.toString() ?? '').trim();
        if (patId.isEmpty) {
          patId = 'PAT_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';
          await db.rawUpdate('UPDATE patients SET id = ? WHERE rowid = ?', [patId, p['rowid'] ?? p['id']]);
        }

        final pPayload = {
          'id': patId,
          'name': p['name']?.toString() ?? '',
          'mobile': p['mobile']?.toString() ?? '',
          'address': p['address']?.toString() ?? '',
          'branch_id': config.storeBranchId,
          'terminal_id': config.terminalId,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };

        try {
          final res = await config.httpClient.post(
            uri,
            headers: headers,
            body: jsonEncode(pPayload),
          ).timeout(const Duration(seconds: 8));

          if (res.statusCode >= 200 && res.statusCode < 300) {
            await db.rawUpdate('UPDATE patients SET is_synced = 1, is_cloud_synced = 1 WHERE id = ?', [patId]);
          }
        } catch (e) {
          debugPrint("DeltaSyncService _pushUnsyncedPatients error: $e");
        }
      }
    } catch (e) {
      debugPrint("DeltaSyncService _pushUnsyncedPatients exception: $e");
    }
  }

  /// Pushes local unsynced suppliers to central server in background
  Future<void> _pushUnsyncedSuppliers() async {
    if (SupabaseSyncService.instance.isRecoveryLocked || SupabaseSyncService.instance.isSyncPaused) return;
    final config = ServerConfigService.instance;
    if (config.isWiping || SupabaseSyncService.instance.isWiping || SupabaseSyncService.instance.isSyncing || !config.isServerModeEnabled || !config.isConnected) return;

    try {
      final db = await DbHelper.instance.database;
      final unsyncedSuppliers = await db.query(
        'suppliers',
        where: 'is_synced = 0 OR is_synced IS NULL',
        limit: 50,
      );

      if (unsyncedSuppliers.isEmpty) return;

      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
      final uri = Uri.parse('$cleanUrl/rest/v1/suppliers?on_conflict=id');
      final headers = Map<String, String>.from(config.restHeaders)..['Prefer'] = 'resolution=merge-duplicates';

      for (var s in unsyncedSuppliers) {
        if (SupabaseSyncService.instance.isRecoveryLocked || SupabaseSyncService.instance.isSyncPaused) return;
        final sMap = Map<String, dynamic>.from(s);
        sMap['branch_id'] = config.storeBranchId;
        sMap.remove('is_synced');
        final supId = (sMap['id']?.toString() ?? '').trim();
        if (supId.isEmpty) {
          sMap['id'] = 'SUP_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';
        }

        try {
          final res = await config.httpClient.post(
            uri,
            headers: headers,
            body: jsonEncode(sMap),
          ).timeout(const Duration(seconds: 8));

          if (res.statusCode >= 200 && res.statusCode < 300) {
            await db.rawUpdate('UPDATE suppliers SET is_synced = 1 WHERE id = ?', [sMap['id']]);
          }
        } catch (e) {
          debugPrint("DeltaSyncService _pushUnsyncedSuppliers error: $e");
        }
      }
    } catch (e) {
      debugPrint("DeltaSyncService _pushUnsyncedSuppliers exception: $e");
    }
  }

  /// Pushes local unsynced products to central server in background
  Future<void> _pushUnsyncedProducts() async {
    if (SupabaseSyncService.instance.isRecoveryLocked || SupabaseSyncService.instance.isSyncPaused) return;
    final config = ServerConfigService.instance;
    if (config.isWiping || SupabaseSyncService.instance.isWiping || SupabaseSyncService.instance.isSyncing || !config.isServerModeEnabled || !config.isConnected) return;

    try {
      final db = await DbHelper.instance.database;
      final unsynced = await db.query(
        'product_master',
        where: 'is_synced = 0 OR is_synced IS NULL',
        limit: 50,
      );

      if (unsynced.isEmpty) return;

      for (var p in unsynced) {
        if (SupabaseSyncService.instance.isRecoveryLocked || SupabaseSyncService.instance.isSyncPaused) return;
        try {
          await SupabaseSyncService.instance.pushProduct(Map<String, dynamic>.from(p));
        } catch (e) {
          debugPrint("DeltaSyncService _pushUnsyncedProducts error for ${p['id']}: $e");
        }
      }
    } catch (e) {
      debugPrint("DeltaSyncService _pushUnsyncedProducts exception: $e");
    }
  }
}
