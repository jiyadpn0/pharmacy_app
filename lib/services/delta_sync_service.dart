import 'dart:async';
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
    if (config.isWiping || SupabaseSyncService.instance.isWiping || SupabaseSyncService.instance.isSyncing) {
      return true;
    }
    if (!config.isServerModeEnabled || !config.isConnected || !config.autoSyncEnabled) {
      return true; // Exit instantly if offline, server disconnected, or auto sync disabled
    }

    return await _lock.synchronized(() async {
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

        // 2. Push local unsynced sales invoices (if any remain)
        await _pushUnsyncedSales();
        if (SupabaseSyncService.instance.isSyncPaused) return false;

        // 3. Push local unsynced stock adjustments & purchases (if any remain)
        await _pushUnsyncedPurchases();
        if (SupabaseSyncService.instance.isSyncPaused) return false;

        // 4. Automated Daily Snapshot Download check (runs once per calendar day)
        final todayStr = DateTime.now().toIso8601String().substring(0, 10);
        final lastSnapshotDate = prefs.getString('last_daily_snapshot_date') ?? '';
        if (lastSnapshotDate != todayStr && !DbHelper.isBillingActive && !SupabaseSyncService.instance.isSyncPaused) {
          final success = await SupabaseSyncService.instance.downloadTodayCompleteSnapshot();
          if (success) {
            await prefs.setString('last_daily_snapshot_date', todayStr);
          }
        }

        if (SupabaseSyncService.instance.isSyncPaused) return false;

        // 5. Trigger Supabase pending data sync
        await SupabaseSyncService.instance.syncAllPendingData().timeout(const Duration(seconds: 45));

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

        if (DbHelper.isBillingActive) {
          await Future.delayed(const Duration(milliseconds: 100));
        }

        final invNo = sale['invoice_no'] as String? ?? sale['entry_no'] as String?;
        if (invNo == null || invNo.isEmpty) continue;

        try {
          final cleanInv = cleanEntryNo(invNo);
          var items = await db.query(
            'sales_items',
            where: 'invoice_no = ? OR invoice_no = ? OR invoice_no LIKE ?',
            whereArgs: [invNo, cleanInv, "%_$cleanInv"],
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
      AppLogger.instance.supabase("Found ${unsyncedPurchases.length} unsynced purchase entries. Syncing in background...");

      for (var purchase in unsyncedPurchases) {
        if (SupabaseSyncService.instance.isRecoveryLocked || SupabaseSyncService.instance.isSyncPaused) {
          debugPrint("DeltaSyncService: Aborting purchase push loop due to Recovery Lock.");
          return;
        }

        if (DbHelper.isBillingActive) {
          await Future.delayed(const Duration(milliseconds: 100));
        }

        final entryNo = purchase['entry_no'] as String?;
        if (entryNo == null || entryNo.isEmpty) continue;

        try {
          final cleanEnt = cleanEntryNo(entryNo);
          var items = await db.query(
            'purchase_items',
            where: 'entry_no = ? OR entry_no = ? OR entry_no LIKE ?',
            whereArgs: [entryNo, cleanEnt, "%_$cleanEnt"],
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
}
