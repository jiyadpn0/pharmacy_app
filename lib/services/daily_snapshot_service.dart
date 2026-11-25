import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import 'backup_service.dart';
import 'server_config_service.dart';
import 'sync_event_bus.dart';

/// Enterprise Automated Midnight Cloud Snapshot & Owner Mobile Pulse Service
class DailySnapshotService extends ChangeNotifier {
  DailySnapshotService._internal();
  static final DailySnapshotService instance = DailySnapshotService._internal();

  Timer? _midnightTimer;
  bool _isSnapshotting = false;
  Map<String, dynamic>? _latestSnapshot;
  static bool _dailySnapshotsTableMissing = false;

  bool get isSnapshotting => _isSnapshotting;
  Map<String, dynamic>? get latestCachedSnapshot => _latestSnapshot;

  /// Ensures local SQLite daily_store_snapshots table exists
  static Future<void> ensureTableExists(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_store_snapshots (
        id TEXT PRIMARY KEY,
        snapshot_date TEXT NOT NULL,
        branch_id TEXT DEFAULT 'MAIN_STORE',
        terminal_id TEXT DEFAULT 'POS-01',
        total_invoices INTEGER DEFAULT 0,
        total_sales REAL DEFAULT 0,
        cash_sales REAL DEFAULT 0,
        upi_sales REAL DEFAULT 0,
        card_sales REAL DEFAULT 0,
        credit_sales REAL DEFAULT 0,
        total_cgst REAL DEFAULT 0,
        total_sgst REAL DEFAULT 0,
        total_gst REAL DEFAULT 0,
        total_net_sales REAL DEFAULT 0,
        total_purchase_cost REAL DEFAULT 0,
        gross_margin_est REAL DEFAULT 0,
        total_inventory_valuation_cost REAL DEFAULT 0,
        total_inventory_valuation_mrp REAL DEFAULT 0,
        total_active_batches INTEGER DEFAULT 0,
        total_products_count INTEGER DEFAULT 0,
        low_stock_items_count INTEGER DEFAULT 0,
        expiring_soon_count INTEGER DEFAULT 0,
        terminal_breakdown TEXT,
        raw_payload TEXT,
        is_synced INTEGER DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now', 'localtime')),
        synced_at TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_dss_date ON daily_store_snapshots(snapshot_date);');
  }

  /// Starts background midnight scheduler (triggers at 23:59:00 every night)
  void startMidnightScheduler() {
    _midnightTimer?.cancel();

    final now = DateTime.now();
    DateTime nextRun = DateTime(now.year, now.month, now.day, 23, 59, 0);
    if (now.isAfter(nextRun)) {
      nextRun = nextRun.add(const Duration(days: 1));
    }

    final initialDelay = nextRun.difference(now);
    debugPrint("[DailySnapshot] Midnight scheduler armed. Next trigger in ${initialDelay.inMinutes} mins ($nextRun)");

    _midnightTimer = Timer(initialDelay, () async {
      debugPrint("[DailySnapshot] 🕛 Midnight snapshot trigger activated!");
      try {
        await generateAndPushTodaySnapshot();

        // Automated Nightly Physical Backup & USB Mirroring Trigger
        try {
          debugPrint("[DailySnapshot] 🛡️ Triggering Automated Nightly Physical & USB Backup...");
          await BackupService.createDatabaseBackup(mirrorToSecondary: true);
        } catch (bErr) {
          debugPrint("[DailySnapshot] Nightly physical backup notice: $bErr");
        }
      } catch (e, stack) {
        debugPrint("[DailySnapshot] Error in midnight snapshot execution: $e\n$stack");
      }
      // Re-schedule for subsequent days (24h)
      startMidnightScheduler();
    });
  }

  /// Generates and pushes snapshot for today
  Future<Map<String, dynamic>> generateAndPushTodaySnapshot() async {
    return await generateAndPushSnapshot(date: DateTime.now());
  }

  /// Generates full snapshot, writes to local SQLite, and pushes to Supabase Cloud
  Future<Map<String, dynamic>> generateAndPushSnapshot({DateTime? date}) async {
    if (_isSnapshotting) {
      debugPrint("[DailySnapshot] Snapshot already in progress, returning latest.");
      return _latestSnapshot ?? {};
    }

    _isSnapshotting = true;
    notifyListeners();

    try {
      final db = await DbHelper.instance.database;
      await ensureTableExists(db);

      final targetDate = date ?? DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(targetDate);
      final branchId = ServerConfigService.instance.storeBranchId;
      final terminalId = ServerConfigService.instance.terminalId;
      final snapshotId = 'SNAPSHOT_${dateStr}_$branchId';

      // 1. Sales Invoices Summary
      final salesSummaryRes = await db.rawQuery('''
        SELECT 
          COUNT(*) as total_invoices,
          COALESCE(SUM(grand_total), 0) as total_sales,
          COALESCE(SUM(CASE WHEN LOWER(payment_mode) = 'cash' THEN grand_total ELSE 0 END), 0) as cash_sales,
          COALESCE(SUM(CASE WHEN LOWER(payment_mode) = 'upi' OR LOWER(payment_mode) = 'online' THEN grand_total ELSE 0 END), 0) as upi_sales,
          COALESCE(SUM(CASE WHEN LOWER(payment_mode) = 'card' THEN grand_total ELSE 0 END), 0) as card_sales,
          COALESCE(SUM(CASE WHEN LOWER(payment_mode) = 'credit' THEN grand_total ELSE 0 END), 0) as credit_sales,
          COALESCE(SUM(tax), 0) as total_tax,
          COALESCE(SUM(sub_total), 0) as total_net_sales
        FROM sales_invoices
        WHERE date(date) = ? AND (is_deleted = 0 OR is_deleted IS NULL)
      ''', [dateStr]);

      final salesRow = salesSummaryRes.isNotEmpty ? salesSummaryRes.first : {};
      final int totalInvoices = (salesRow['total_invoices'] as num?)?.toInt() ?? 0;
      final double totalSales = (salesRow['total_sales'] as num?)?.toDouble() ?? 0.0;
      final double cashSales = (salesRow['cash_sales'] as num?)?.toDouble() ?? 0.0;
      final double upiSales = (salesRow['upi_sales'] as num?)?.toDouble() ?? 0.0;
      final double cardSales = (salesRow['card_sales'] as num?)?.toDouble() ?? 0.0;
      final double creditSales = (salesRow['credit_sales'] as num?)?.toDouble() ?? 0.0;
      final double totalNetSales = (salesRow['total_net_sales'] as num?)?.toDouble() ?? (totalSales - ((salesRow['total_tax'] as num?)?.toDouble() ?? 0.0));

      // 2. Sales Items GST & Profit Summary
      final itemsSummaryRes = await db.rawQuery('''
        SELECT 
          COALESCE(SUM(cgst_amt), 0) as total_cgst,
          COALESCE(SUM(sgst_amt), 0) as total_sgst,
          COALESCE(SUM(gst_amt), 0) as total_gst,
          COALESCE(SUM(profit), 0) as gross_profit
        FROM sales_items
        WHERE invoice_no IN (
          SELECT entry_no FROM sales_invoices WHERE date(date) = ? AND (is_deleted = 0 OR is_deleted IS NULL)
        )
      ''', [dateStr]);

      final itemsRow = itemsSummaryRes.isNotEmpty ? itemsSummaryRes.first : {};
      final double totalCgst = (itemsRow['total_cgst'] as num?)?.toDouble() ?? 0.0;
      final double totalSgst = (itemsRow['total_sgst'] as num?)?.toDouble() ?? 0.0;
      final double totalGst = (itemsRow['total_gst'] as num?)?.toDouble() ?? (totalCgst + totalSgst);
      final double grossMarginEst = (itemsRow['gross_profit'] as num?)?.toDouble() ?? 0.0;

      // 3. Purchase Entries on that Date
      final purchasesRes = await db.rawQuery('''
        SELECT COALESCE(SUM(grand_total), 0) as total_purchases
        FROM purchase_entries
        WHERE date(date) = ? AND (is_deleted = 0 OR is_deleted IS NULL)
      ''', [dateStr]);
      final double totalPurchaseCost = (purchasesRes.first['total_purchases'] as num?)?.toDouble() ?? 0.0;

      // 4. Multi-Terminal Breakdown
      final terminalRes = await db.rawQuery('''
        SELECT 
          COALESCE(NULLIF(TRIM(terminal_id), ''), 'POS-01') as terminal_id,
          COALESCE(NULLIF(TRIM(done_by), ''), 'Cashier') as staff_name,
          COUNT(*) as total_invoices,
          SUM(grand_total) as total_sales,
          SUM(CASE WHEN LOWER(payment_mode) = 'cash' THEN grand_total ELSE 0 END) as cash_sales,
          SUM(CASE WHEN LOWER(payment_mode) = 'upi' OR LOWER(payment_mode) = 'online' THEN grand_total ELSE 0 END) as upi_sales,
          SUM(CASE WHEN LOWER(payment_mode) = 'card' THEN grand_total ELSE 0 END) as card_sales,
          SUM(CASE WHEN LOWER(payment_mode) = 'credit' THEN grand_total ELSE 0 END) as credit_sales
        FROM sales_invoices
        WHERE date(date) = ? AND (is_deleted = 0 OR is_deleted IS NULL)
        GROUP BY COALESCE(NULLIF(TRIM(terminal_id), ''), 'POS-01'), COALESCE(NULLIF(TRIM(done_by), ''), 'Cashier')
        ORDER BY terminal_id ASC
      ''', [dateStr]);

      final List<Map<String, dynamic>> terminalBreakdown = terminalRes.map((r) => {
        'terminal_id': r['terminal_id']?.toString() ?? 'POS-01',
        'staff_name': r['staff_name']?.toString() ?? 'Cashier',
        'total_invoices': (r['total_invoices'] as num?)?.toInt() ?? 0,
        'total_sales': (r['total_sales'] as num?)?.toDouble() ?? 0.0,
        'cash_sales': (r['cash_sales'] as num?)?.toDouble() ?? 0.0,
        'upi_sales': (r['upi_sales'] as num?)?.toDouble() ?? 0.0,
        'card_sales': (r['card_sales'] as num?)?.toDouble() ?? 0.0,
        'credit_sales': (r['credit_sales'] as num?)?.toDouble() ?? 0.0,
      }).toList();

      // 5. Inventory Valuation Snapshot
      final inventoryRes = await db.rawQuery('''
        SELECT 
          COUNT(*) as active_batches,
          COALESCE(SUM(current_stock), 0) as total_units,
          COALESCE(SUM(current_stock * purchase_rate), 0) as total_valuation_cost,
          COALESCE(SUM(current_stock * mrp), 0) as total_valuation_mrp
        FROM stock_batches
        WHERE current_stock > 0
      ''');

      final invRow = inventoryRes.isNotEmpty ? inventoryRes.first : {};
      final int totalActiveBatches = (invRow['active_batches'] as num?)?.toInt() ?? 0;
      final double totalValuationCost = (invRow['total_valuation_cost'] as num?)?.toDouble() ?? 0.0;
      final double totalValuationMrp = (invRow['total_valuation_mrp'] as num?)?.toDouble() ?? 0.0;

      // Products count
      final prodCountRes = await db.rawQuery('SELECT COUNT(*) as count FROM product_master;');
      final int totalProductsCount = (prodCountRes.first['count'] as num?)?.toInt() ?? 0;

      // Low stock count (batches where current_stock <= 10)
      final lowStockRes = await db.rawQuery('''
        SELECT COUNT(DISTINCT product_id) as count 
        FROM stock_batches 
        WHERE current_stock > 0 AND current_stock <= 10;
      ''');
      final int lowStockCount = (lowStockRes.first['count'] as num?)?.toInt() ?? 0;

      // Expiring soon within 90 days
      final expiryThreshold = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 90)));
      final expiryRes = await db.rawQuery('''
        SELECT COUNT(*) as count 
        FROM stock_batches 
        WHERE current_stock > 0 
          AND expiry_date IS NOT NULL 
          AND expiry_date != '' 
          AND expiry_date <= ?;
      ''', [expiryThreshold]);
      final int expiringSoonCount = (expiryRes.first['count'] as num?)?.toInt() ?? 0;

      final snapshotMap = <String, dynamic>{
        'id': snapshotId,
        'snapshot_date': dateStr,
        'branch_id': branchId,
        'terminal_id': terminalId,
        'total_invoices': totalInvoices,
        'total_sales': totalSales,
        'cash_sales': cashSales,
        'upi_sales': upiSales,
        'card_sales': cardSales,
        'credit_sales': creditSales,
        'total_cgst': totalCgst,
        'total_sgst': totalSgst,
        'total_gst': totalGst,
        'total_net_sales': totalNetSales,
        'total_purchase_cost': totalPurchaseCost,
        'gross_margin_est': grossMarginEst,
        'total_inventory_valuation_cost': totalValuationCost,
        'total_inventory_valuation_mrp': totalValuationMrp,
        'total_active_batches': totalActiveBatches,
        'total_products_count': totalProductsCount,
        'low_stock_items_count': lowStockCount,
        'expiring_soon_count': expiringSoonCount,
        'terminal_breakdown': terminalBreakdown,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      // 6. Write Locally to SQLite
      await db.insert('daily_store_snapshots', {
        'id': snapshotId,
        'snapshot_date': dateStr,
        'branch_id': branchId,
        'terminal_id': terminalId,
        'total_invoices': totalInvoices,
        'total_sales': totalSales,
        'cash_sales': cashSales,
        'upi_sales': upiSales,
        'card_sales': cardSales,
        'credit_sales': creditSales,
        'total_cgst': totalCgst,
        'total_sgst': totalSgst,
        'total_gst': totalGst,
        'total_net_sales': totalNetSales,
        'total_purchase_cost': totalPurchaseCost,
        'gross_margin_est': grossMarginEst,
        'total_inventory_valuation_cost': totalValuationCost,
        'total_inventory_valuation_mrp': totalValuationMrp,
        'total_active_batches': totalActiveBatches,
        'total_products_count': totalProductsCount,
        'low_stock_items_count': lowStockCount,
        'expiring_soon_count': expiringSoonCount,
        'terminal_breakdown': jsonEncode(terminalBreakdown),
        'raw_payload': jsonEncode(snapshotMap),
        'is_synced': 0,
        'created_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      _latestSnapshot = snapshotMap;

      // 7. Push to Supabase Cloud
      final bool cloudPushed = await _pushSnapshotToCloud(snapshotMap);
      if (cloudPushed) {
        await db.update(
          'daily_store_snapshots',
          {'is_synced': 1, 'synced_at': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [snapshotId],
        );
      }

      SyncEventBus.instance.notifyTableChanged('daily_store_snapshots');
      return snapshotMap;
    } catch (e, stack) {
      debugPrint("[DailySnapshot] Error generating snapshot: $e\n$stack");
      rethrow;
    } finally {
      _isSnapshotting = false;
      notifyListeners();
    }
  }

  /// Multi-tier push: writes to daily_store_snapshots and server_metadata
  Future<bool> _pushSnapshotToCloud(Map<String, dynamic> snapshot) async {
    final serverConfig = ServerConfigService.instance;
    if (!serverConfig.isServerModeEnabled || !serverConfig.isConnected) {
      debugPrint("[DailySnapshot] Cloud offline or server mode disabled, snapshot safely preserved locally.");
      return false;
    }

    final headers = Map<String, String>.from(serverConfig.restHeaders)
      ..['Content-Type'] = 'application/json'
      ..['Prefer'] = 'resolution=merge-duplicates';

    final snapshotJson = jsonEncode(snapshot);
    final dateStr = snapshot['snapshot_date']?.toString() ?? DateFormat('yyyy-MM-dd').format(DateTime.now());

    bool success = false;

    // 1. Try upserting to daily_store_snapshots table (skip if table does not exist on Supabase)
    if (!_dailySnapshotsTableMissing) {
      try {
        final snapUri = Uri.parse('${serverConfig.supabaseUrl}/rest/v1/daily_store_snapshots');
        final res = await http.post(snapUri, headers: headers, body: snapshotJson).timeout(const Duration(seconds: 10));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          debugPrint("[DailySnapshot] Successfully upserted to daily_store_snapshots table in Supabase!");
          success = true;
        } else if (res.statusCode == 404) {
          _dailySnapshotsTableMissing = true;
          debugPrint("[DailySnapshot] daily_store_snapshots table not present in Supabase; routing to server_metadata.");
        } else {
          debugPrint("[DailySnapshot] daily_store_snapshots response: ${res.statusCode} ${res.body}");
        }
      } catch (e) {
        debugPrint("[DailySnapshot] Note: daily_store_snapshots endpoint push notice: $e");
      }
    }

    // 2. Always upsert to server_metadata (ensures zero data loss even if custom table not yet run)
    try {
      final metaUri = Uri.parse('${serverConfig.supabaseUrl}/rest/v1/server_metadata');

      final compactPulse = {
        'date': dateStr,
        'branch_id': snapshot['branch_id'],
        'total_sales': snapshot['total_sales'],
        'cash_sales': snapshot['cash_sales'],
        'upi_sales': snapshot['upi_sales'],
        'total_invoices': snapshot['total_invoices'],
        'inventory_valuation_cost': snapshot['total_inventory_valuation_cost'],
        'inventory_valuation_mrp': snapshot['total_inventory_valuation_mrp'],
        'low_stock_count': snapshot['low_stock_items_count'],
        'expiring_count': snapshot['expiring_soon_count'],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final metaRows = [
        {'key': 'daily_snapshot_$dateStr', 'value': snapshotJson},
        {'key': 'latest_daily_snapshot', 'value': snapshotJson},
        {'key': 'owner_mobile_pulse', 'value': jsonEncode(compactPulse)},
      ];

      final metaRes = await http.post(
        metaUri,
        headers: headers,
        body: jsonEncode(metaRows),
      ).timeout(const Duration(seconds: 10));

      if (metaRes.statusCode >= 200 && metaRes.statusCode < 300) {
        debugPrint("[DailySnapshot] Successfully committed daily snapshot & owner mobile pulse to server_metadata!");
        success = true;
      }
    } catch (e) {
      debugPrint("[DailySnapshot] server_metadata push notice: $e");
    }

    return success;
  }

  /// Retrieves snapshot history from local SQLite
  Future<List<Map<String, dynamic>>> getSnapshotHistory({int limit = 30}) async {
    final db = await DbHelper.instance.database;
    await ensureTableExists(db);

    final rows = await db.query(
      'daily_store_snapshots',
      orderBy: 'snapshot_date DESC',
      limit: limit,
    );

    return rows.map((r) {
      final raw = r['raw_payload']?.toString();
      if (raw != null && raw.isNotEmpty) {
        try {
          return jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {}
      }
      return Map<String, dynamic>.from(r);
    }).toList();
  }

  /// Retrieves the latest snapshot from local SQLite or Supabase
  Future<Map<String, dynamic>?> getLatestSnapshot() async {
    if (_latestSnapshot != null) return _latestSnapshot;

    final db = await DbHelper.instance.database;
    await ensureTableExists(db);

    final rows = await db.query(
      'daily_store_snapshots',
      orderBy: 'snapshot_date DESC',
      limit: 1,
    );

    if (rows.isNotEmpty) {
      final raw = rows.first['raw_payload']?.toString();
      if (raw != null && raw.isNotEmpty) {
        try {
          _latestSnapshot = jsonDecode(raw) as Map<String, dynamic>;
          return _latestSnapshot;
        } catch (_) {}
      }
      _latestSnapshot = Map<String, dynamic>.from(rows.first);
      return _latestSnapshot;
    }

    return null;
  }

  /// Stops background midnight scheduler
  void stopMidnightScheduler() {
    _midnightTimer?.cancel();
    _midnightTimer = null;
  }

  @override
  void dispose() {
    stopMidnightScheduler();
    super.dispose();
  }
}
