import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';

/// Comprehensive snapshot of SQLite database size, memory, and structural integrity.
class DatabaseHealthReport {
  final int dbSizeBytes;
  final int walSizeBytes;
  final int shmSizeBytes;
  final int pageCount;
  final int pageSize;
  final int freelistCount;
  final bool isHealthy;
  final String integrityMessage;
  final int walLogFrames;
  final int walCheckpointedFrames;
  final bool walBusy;
  final DateTime timestamp;

  const DatabaseHealthReport({
    required this.dbSizeBytes,
    required this.walSizeBytes,
    required this.shmSizeBytes,
    required this.pageCount,
    required this.pageSize,
    required this.freelistCount,
    required this.isHealthy,
    required this.integrityMessage,
    required this.walLogFrames,
    required this.walCheckpointedFrames,
    required this.walBusy,
    required this.timestamp,
  });

  double get dbSizeMb => dbSizeBytes / (1024 * 1024);
  double get walSizeMb => walSizeBytes / (1024 * 1024);
  double get shmSizeKb => shmSizeBytes / 1024;
  double get totalSizeMb => (dbSizeBytes + walSizeBytes + shmSizeBytes) / (1024 * 1024);
  double get reclaimableMb => (freelistCount * pageSize) / (1024 * 1024);

  Map<String, dynamic> toMap() => {
        'db_size_bytes': dbSizeBytes,
        'wal_size_bytes': walSizeBytes,
        'shm_size_bytes': shmSizeBytes,
        'db_size_mb': dbSizeMb,
        'wal_size_mb': walSizeMb,
        'total_size_mb': totalSizeMb,
        'page_count': pageCount,
        'page_size': pageSize,
        'freelist_count': freelistCount,
        'reclaimable_mb': reclaimableMb,
        'is_healthy': isHealthy,
        'integrity_message': integrityMessage,
        'wal_log_frames': walLogFrames,
        'wal_checkpointed_frames': walCheckpointedFrames,
        'wal_busy': walBusy,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Execution metrics resulting from a WAL compaction and database optimization cycle.
class MaintenanceResult {
  final bool success;
  final String message;
  final int initialWalSizeBytes;
  final int finalWalSizeBytes;
  final int initialDbSizeBytes;
  final int finalDbSizeBytes;
  final bool quickCheckPassed;
  final String quickCheckResult;
  final int checkpointedFrames;
  final int remainingFrames;
  final Duration duration;

  const MaintenanceResult({
    required this.success,
    required this.message,
    required this.initialWalSizeBytes,
    required this.finalWalSizeBytes,
    required this.initialDbSizeBytes,
    required this.finalDbSizeBytes,
    required this.quickCheckPassed,
    required this.quickCheckResult,
    required this.checkpointedFrames,
    required this.remainingFrames,
    required this.duration,
  });

  double get walFreedMb =>
      (initialWalSizeBytes > finalWalSizeBytes ? initialWalSizeBytes - finalWalSizeBytes : 0) / (1024 * 1024);

  Map<String, dynamic> toMap() => {
        'success': success,
        'message': message,
        'wal_freed_mb': walFreedMb,
        'initial_wal_size_bytes': initialWalSizeBytes,
        'final_wal_size_bytes': finalWalSizeBytes,
        'initial_db_size_bytes': initialDbSizeBytes,
        'final_db_size_bytes': finalDbSizeBytes,
        'quick_check_passed': quickCheckPassed,
        'quick_check_result': quickCheckResult,
        'checkpointed_frames': checkpointedFrames,
        'remaining_frames': remainingFrames,
        'duration_ms': duration.inMilliseconds,
      };
}

/// Detailed multi-layered pre-flight audit report checking physical SQLite integrity,
/// relational foreign keys, stock ledger alignment, and sync outbox queues.
class PreFlightAuditReport {
  final bool sqliteIntegrityOk;
  final List<String> integrityErrors;
  final int foreignKeyViolationsCount;
  final List<String> foreignKeyViolationDetails;
  final int discrepantBatchesCount;
  final int negativeStockBatchesCount;
  final int zeroPricedBatchesCount;
  final int expiredActiveBatchesCount;
  final int pendingOutboxCount;
  final int failedOutboxCount;
  final int totalTablesCount;
  final int totalActiveBatches;
  final DateTime timestamp;

  const PreFlightAuditReport({
    required this.sqliteIntegrityOk,
    required this.integrityErrors,
    required this.foreignKeyViolationsCount,
    required this.foreignKeyViolationDetails,
    required this.discrepantBatchesCount,
    required this.negativeStockBatchesCount,
    required this.zeroPricedBatchesCount,
    required this.expiredActiveBatchesCount,
    required this.pendingOutboxCount,
    required this.failedOutboxCount,
    required this.totalTablesCount,
    required this.totalActiveBatches,
    required this.timestamp,
  });

  bool get isProductionReady =>
      sqliteIntegrityOk &&
      foreignKeyViolationsCount == 0 &&
      discrepantBatchesCount == 0 &&
      negativeStockBatchesCount == 0 &&
      failedOutboxCount == 0;

  String get healthGrade {
    if (!sqliteIntegrityOk || foreignKeyViolationsCount > 10) return "CRITICAL";
    if (discrepantBatchesCount > 0 || negativeStockBatchesCount > 0 || failedOutboxCount > 0) return "ATTENTION";
    if (zeroPricedBatchesCount > 0 || expiredActiveBatchesCount > 0) return "GOOD";
    return "EXCELLENT";
  }

  Map<String, dynamic> toMap() => {
        'sqlite_integrity_ok': sqliteIntegrityOk,
        'integrity_errors': integrityErrors,
        'foreign_key_violations_count': foreignKeyViolationsCount,
        'foreign_key_violation_details': foreignKeyViolationDetails,
        'discrepant_batches_count': discrepantBatchesCount,
        'negative_stock_batches_count': negativeStockBatchesCount,
        'zero_priced_batches_count': zeroPricedBatchesCount,
        'expired_active_batches_count': expiredActiveBatchesCount,
        'pending_outbox_count': pendingOutboxCount,
        'failed_outbox_count': failedOutboxCount,
        'total_tables_count': totalTablesCount,
        'total_active_batches': totalActiveBatches,
        'is_production_ready': isProductionReady,
        'health_grade': healthGrade,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Execution outcome of an automated repair cycle (stock ledger reconciliation,
/// outbox poison-pill unclogging, indexing, and storage defragmentation).
class AutoHealResult {
  final bool success;
  final String message;
  final String? backupCreatedPath;
  final int batchesReconciled;
  final int uncloggedOutboxEvents;
  final bool vacuumCompleted;
  final bool reindexCompleted;
  final double initialDbMb;
  final double finalDbMb;
  final Duration duration;

  const AutoHealResult({
    required this.success,
    required this.message,
    this.backupCreatedPath,
    required this.batchesReconciled,
    required this.uncloggedOutboxEvents,
    required this.vacuumCompleted,
    required this.reindexCompleted,
    required this.initialDbMb,
    required this.finalDbMb,
    required this.duration,
  });

  double get spaceReclaimedMb => (initialDbMb > finalDbMb) ? (initialDbMb - finalDbMb) : 0.0;

  Map<String, dynamic> toMap() => {
        'success': success,
        'message': message,
        'backup_created_path': backupCreatedPath,
        'batches_reconciled': batchesReconciled,
        'unclogged_outbox_events': uncloggedOutboxEvents,
        'vacuum_completed': vacuumCompleted,
        'reindex_completed': reindexCompleted,
        'initial_db_mb': initialDbMb,
        'final_db_mb': finalDbMb,
        'space_reclaimed_mb': spaceReclaimedMb,
        'duration_ms': duration.inMilliseconds,
      };
}

/// Service dedicated to preventing SQLite WAL disk bloat, ensuring data integrity,
/// and optimizing query planner statistics without locking active POS terminals.
class DatabaseMaintenanceService extends ChangeNotifier {
  DatabaseMaintenanceService._();
  static final DatabaseMaintenanceService instance = DatabaseMaintenanceService._();

  Timer? _periodicTimer;
  bool _isMaintenanceRunning = false;
  DatabaseHealthReport? _lastReport;
  MaintenanceResult? _lastResult;
  PreFlightAuditReport? _lastAudit;
  AutoHealResult? _lastHealResult;

  bool get isMaintenanceRunning => _isMaintenanceRunning;
  DatabaseHealthReport? get lastReport => _lastReport;
  MaintenanceResult? get lastResult => _lastResult;
  PreFlightAuditReport? get lastAudit => _lastAudit;
  AutoHealResult? get lastHealResult => _lastHealResult;

  /// Retrieves file and internal SQLite engine diagnostics
  Future<DatabaseHealthReport> getHealthReport({Database? targetDb}) async {
    final db = targetDb ?? await DbHelper.instance.database;
    if (!db.isOpen) {
      return DatabaseHealthReport(
        dbSizeBytes: 0,
        walSizeBytes: 0,
        shmSizeBytes: 0,
        pageCount: 0,
        pageSize: 4096,
        freelistCount: 0,
        isHealthy: false,
        integrityMessage: 'database closed',
        walLogFrames: 0,
        walCheckpointedFrames: 0,
        walBusy: false,
        timestamp: DateTime.now(),
      );
    }

    int dbSize = 0;
    int walSize = 0;
    int shmSize = 0;

    if (!kIsWeb) {
      try {
        final dbDirPath = await getDatabasesPath();
        final dbFile = File(join(dbDirPath, 'pharmacy.db'));
        final walFile = File(join(dbDirPath, 'pharmacy.db-wal'));
        final shmFile = File(join(dbDirPath, 'pharmacy.db-shm'));

        if (await dbFile.exists()) dbSize = await dbFile.length();
        if (await walFile.exists()) walSize = await walFile.length();
        if (await shmFile.exists()) shmSize = await shmFile.length();
      } catch (e) {
        debugPrint("DatabaseMaintenanceService file size check note: $e");
      }
    }

    int pageCount = 0;
    int pageSize = 4096;
    int freelistCount = 0;
    try {
      final pcRes = await db.rawQuery('PRAGMA page_count;');
      pageCount = Sqflite.firstIntValue(pcRes) ?? 0;

      final psRes = await db.rawQuery('PRAGMA page_size;');
      pageSize = Sqflite.firstIntValue(psRes) ?? 4096;

      final fcRes = await db.rawQuery('PRAGMA freelist_count;');
      freelistCount = Sqflite.firstIntValue(fcRes) ?? 0;
    } catch (e) {
      debugPrint("DatabaseMaintenanceService pragma read error: $e");
    }

    // Passive WAL inspection
    int walLog = 0;
    int walCheckpointed = 0;
    bool walBusy = false;
    try {
      final walRows = await db.rawQuery('PRAGMA wal_checkpoint(PASSIVE);');
      if (walRows.isNotEmpty) {
        final first = walRows.first;
        walBusy = (first['busy'] as num?)?.toInt() == 1;
        walLog = (first['log'] as num?)?.toInt() ?? 0;
        walCheckpointed = (first['checkpointed'] as num?)?.toInt() ?? 0;
      }
    } catch (e) {
      debugPrint("DatabaseMaintenanceService passive checkpoint error: $e");
    }

    // Quick integrity check
    bool isHealthy = true;
    String integrityMsg = 'ok';
    try {
      final qcRows = await db.rawQuery('PRAGMA quick_check;');
      if (qcRows.isNotEmpty) {
        integrityMsg = qcRows.first.values.first?.toString() ?? 'ok';
        isHealthy = integrityMsg.toLowerCase() == 'ok';
      }
    } catch (e) {
      integrityMsg = e.toString();
      isHealthy = false;
    }

    final report = DatabaseHealthReport(
      dbSizeBytes: dbSize,
      walSizeBytes: walSize,
      shmSizeBytes: shmSize,
      pageCount: pageCount,
      pageSize: pageSize,
      freelistCount: freelistCount,
      isHealthy: isHealthy,
      integrityMessage: integrityMsg,
      walLogFrames: walLog,
      walCheckpointedFrames: walCheckpointed,
      walBusy: walBusy,
      timestamp: DateTime.now(),
    );

    _lastReport = report;
    notifyListeners();
    return report;
  }

  /// Performs WAL compaction (TRUNCATE), query planner optimization, and quick integrity audit.
  /// If active readers hold locks on the WAL, falls back to non-blocking PASSIVE checkpoint
  /// without failing or interrupting running transactions.
  Future<MaintenanceResult> performMaintenance({
    Database? targetDb,
    bool truncateWal = true,
    bool runOptimize = true,
  }) async {
    if (_isMaintenanceRunning) {
      return const MaintenanceResult(
        success: false,
        message: "Database maintenance is already in progress.",
        initialWalSizeBytes: 0,
        finalWalSizeBytes: 0,
        initialDbSizeBytes: 0,
        finalDbSizeBytes: 0,
        quickCheckPassed: false,
        quickCheckResult: "Busy",
        checkpointedFrames: 0,
        remainingFrames: 0,
        duration: Duration.zero,
      );
    }

    _isMaintenanceRunning = true;
    notifyListeners();

    final stopwatch = Stopwatch()..start();
    final db = targetDb ?? await DbHelper.instance.database;

    int initialDbSize = 0;
    int initialWalSize = 0;
    String dbDirPath = '';

    if (!kIsWeb) {
      try {
        dbDirPath = await getDatabasesPath();
        final dbFile = File(join(dbDirPath, 'pharmacy.db'));
        final walFile = File(join(dbDirPath, 'pharmacy.db-wal'));
        if (await dbFile.exists()) initialDbSize = await dbFile.length();
        if (await walFile.exists()) initialWalSize = await walFile.length();
      } catch (e) {
        debugPrint("Initial file size note: $e");
      }
    }

    int checkpointedFrames = 0;
    int remainingFrames = 0;
    bool checkpointSuccess = true;

    // Step 1: WAL Checkpoint (TRUNCATE or PASSIVE)
    try {
      final pragmaCmd = truncateWal ? 'PRAGMA wal_checkpoint(TRUNCATE);' : 'PRAGMA wal_checkpoint(PASSIVE);';
      final res = await db.rawQuery(pragmaCmd);
      if (res.isNotEmpty) {
        final row = res.first;
        final busy = (row['busy'] as num?)?.toInt() == 1;
        final log = (row['log'] as num?)?.toInt() ?? 0;
        final chk = (row['checkpointed'] as num?)?.toInt() ?? 0;
        checkpointedFrames = chk;
        remainingFrames = (log >= chk) ? (log - chk) : 0;

        if (busy && truncateWal) {
          debugPrint("TRUNCATE checkpoint reported busy readers. Executing PASSIVE checkpoint fallback.");
          await db.rawQuery('PRAGMA wal_checkpoint(PASSIVE);');
        }
      }
    } catch (e) {
      debugPrint("WAL checkpoint execution error: $e");
      checkpointSuccess = false;
    }

    // Step 2: Query planner statistics update (PRAGMA optimize)
    if (runOptimize) {
      try {
        await db.execute('PRAGMA optimize;');
      } catch (e) {
        debugPrint("PRAGMA optimize note: $e");
      }
    }

    // Step 3: Fast B-Tree integrity check
    bool quickCheckPassed = false;
    String quickCheckResult = "unknown";
    try {
      final qcRes = await db.rawQuery('PRAGMA quick_check;');
      if (qcRes.isNotEmpty) {
        quickCheckResult = qcRes.first.values.first?.toString() ?? 'ok';
        quickCheckPassed = quickCheckResult.toLowerCase() == 'ok';
      }
    } catch (e) {
      quickCheckResult = e.toString();
      quickCheckPassed = false;
    }

    // Measure final file sizes
    int finalDbSize = initialDbSize;
    int finalWalSize = initialWalSize;
    if (!kIsWeb && dbDirPath.isNotEmpty) {
      try {
        final dbFile = File(join(dbDirPath, 'pharmacy.db'));
        final walFile = File(join(dbDirPath, 'pharmacy.db-wal'));
        if (await dbFile.exists()) finalDbSize = await dbFile.length();
        if (await walFile.exists()) finalWalSize = await walFile.length();
      } catch (e) {
        debugPrint("Final file size note: $e");
      }
    }

    stopwatch.stop();
    _isMaintenanceRunning = false;

    final freedMb = (initialWalSize > finalWalSize ? initialWalSize - finalWalSize : 0) / (1024 * 1024);
    final statusMsg = checkpointSuccess && quickCheckPassed
        ? "Database maintenance completed in ${stopwatch.elapsedMilliseconds}ms. "
            "${freedMb > 0.05 ? 'Compacted WAL: freed ${freedMb.toStringAsFixed(2)} MB. ' : ''}"
            "Integrity verified (OK)."
        : "Database maintenance completed with warnings: $quickCheckResult";

    final result = MaintenanceResult(
      success: checkpointSuccess && quickCheckPassed,
      message: statusMsg,
      initialWalSizeBytes: initialWalSize,
      finalWalSizeBytes: finalWalSize,
      initialDbSizeBytes: initialDbSize,
      finalDbSizeBytes: finalDbSize,
      quickCheckPassed: quickCheckPassed,
      quickCheckResult: quickCheckResult,
      checkpointedFrames: checkpointedFrames,
      remainingFrames: remainingFrames,
      duration: stopwatch.elapsed,
    );

    _lastResult = result;
    // Refresh cached health report if database is open
    if (db.isOpen) {
      try {
        await getHealthReport(targetDb: db);
      } catch (e) {
        debugPrint("Post-maintenance health report note: $e");
      }
    }

    return result;
  }

  /// Starts an automated, non-disruptive background maintenance loop
  void startPeriodicMaintenance({
    Duration interval = const Duration(minutes: 30),
    int walBloatThresholdBytes = 10 * 1024 * 1024, // 10 MB threshold for automatic TRUNCATE
  }) {
    stopPeriodicMaintenance();

    _periodicTimer = Timer.periodic(interval, (timer) async {
      try {
        final report = await getHealthReport();
        // If WAL is larger than threshold, run TRUNCATE; otherwise light PASSIVE checkpoint
        final needsTruncate = report.walSizeBytes >= walBloatThresholdBytes;
        await performMaintenance(truncateWal: needsTruncate, runOptimize: true);
      } catch (e) {
        debugPrint("Periodic database maintenance note: $e");
      }
    });

    debugPrint("DatabaseMaintenanceService: Periodic maintenance scheduled every ${interval.inMinutes} minutes.");
  }

  /// Stops the background maintenance timer
  void stopPeriodicMaintenance() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  Future<bool> _tableExists(Database db, String tableName) async {
    try {
      final res = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
        [tableName],
      );
      return res.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Runs an exhaustive multi-layered diagnostic audit checking B-Tree integrity,
  /// foreign key validity, inventory ledger-to-batch alignment, and sync outbox queues.
  Future<PreFlightAuditReport> runPreFlightAudit({Database? targetDb}) async {
    final db = targetDb ?? await DbHelper.instance.database;
    if (!db.isOpen) {
      return PreFlightAuditReport(
        sqliteIntegrityOk: false,
        integrityErrors: const ['Database is closed'],
        foreignKeyViolationsCount: 0,
        foreignKeyViolationDetails: const [],
        discrepantBatchesCount: 0,
        negativeStockBatchesCount: 0,
        zeroPricedBatchesCount: 0,
        expiredActiveBatchesCount: 0,
        pendingOutboxCount: 0,
        failedOutboxCount: 0,
        totalTablesCount: 0,
        totalActiveBatches: 0,
        timestamp: DateTime.now(),
      );
    }

    // 1. Deep SQLite Integrity Check
    bool integrityOk = true;
    final List<String> integrityErrors = [];
    try {
      final intCheckRows = await db.rawQuery('PRAGMA integrity_check(100);');
      for (var r in intCheckRows) {
        final val = r.values.first?.toString() ?? '';
        if (val.toLowerCase() != 'ok') {
          integrityOk = false;
          integrityErrors.add(val);
        }
      }
    } catch (e) {
      integrityOk = false;
      integrityErrors.add("Integrity check failed: $e");
    }

    // 2. Foreign Key Check
    final List<String> fkErrors = [];
    try {
      final fkRows = await db.rawQuery('PRAGMA foreign_key_check;');
      for (var r in fkRows) {
        final table = r['table']?.toString() ?? 'unknown';
        final rowid = r['rowid']?.toString() ?? '0';
        final parent = r['parent']?.toString() ?? 'unknown';
        fkErrors.add("Table '$table' [row $rowid] broken FK to '$parent'");
      }
    } catch (e) {
      debugPrint("Foreign key check note: $e");
    }

    // 3. Inventory & Ledger Diagnostics
    int discrepantBatches = 0;
    int negativeStockBatches = 0;
    int zeroPricedBatches = 0;
    int expiredActiveBatches = 0;
    int totalActiveBatches = 0;

    final hasStockBatches = await _tableExists(db, 'stock_batches');
    final hasStockLedger = await _tableExists(db, 'stock_ledger');

    if (hasStockBatches) {
      try {
        final activeRes = await db.rawQuery(
          'SELECT COUNT(*) as cnt FROM stock_batches WHERE current_stock > 0'
        );
        totalActiveBatches = Sqflite.firstIntValue(activeRes) ?? 0;

        final negRes = await db.rawQuery(
          'SELECT COUNT(*) as cnt FROM stock_batches WHERE current_stock < 0'
        );
        negativeStockBatches = Sqflite.firstIntValue(negRes) ?? 0;

        final zeroRes = await db.rawQuery(
          'SELECT COUNT(*) as cnt FROM stock_batches WHERE (purchase_rate <= 0 OR mrp <= 0) AND current_stock > 0'
        );
        zeroPricedBatches = Sqflite.firstIntValue(zeroRes) ?? 0;

        final nowIso = DateTime.now().toIso8601String().substring(0, 10);
        final expRes = await db.rawQuery(
          'SELECT COUNT(*) as cnt FROM stock_batches WHERE expiry_date < ? AND current_stock > 0',
          [nowIso],
        );
        expiredActiveBatches = Sqflite.firstIntValue(expRes) ?? 0;

        // Discrepancy comparison against ledger
        if (hasStockLedger) {
          final discRows = await db.rawQuery('''
            SELECT sb.rowid
            FROM stock_batches sb
            LEFT JOIN (
              SELECT product_id, LOWER(TRIM(batch_number)) as clean_batch,
                     SUM(qty_in) - SUM(qty_out) as computed_stock
              FROM stock_ledger
              GROUP BY product_id, LOWER(TRIM(batch_number))
            ) sl ON sb.product_id = sl.product_id AND LOWER(TRIM(sb.batch_number)) = sl.clean_batch
            WHERE sb.current_stock != IFNULL(sl.computed_stock, 0)
          ''');
          discrepantBatches = discRows.length;
        }
      } catch (e) {
        debugPrint("Inventory audit query note: $e");
      }
    }

    // 4. Outbox Queue Diagnostics
    int pendingOutbox = 0;
    int failedOutbox = 0;
    final hasOutbox = await _tableExists(db, 'stock_outbox');
    if (hasOutbox) {
      try {
        final pendingRes = await db.rawQuery(
          "SELECT COUNT(*) as cnt FROM stock_outbox WHERE status = 'pending'"
        );
        pendingOutbox = Sqflite.firstIntValue(pendingRes) ?? 0;

        final failedRes = await db.rawQuery(
          "SELECT COUNT(*) as cnt FROM stock_outbox WHERE status = 'failed' OR retry_count >= 5"
        );
        failedOutbox = Sqflite.firstIntValue(failedRes) ?? 0;
      } catch (e) {
        debugPrint("Outbox audit query note: $e");
      }
    }

    // 5. Total User Tables Count
    int totalTables = 0;
    try {
      final tblRes = await db.rawQuery(
        "SELECT COUNT(*) as cnt FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
      );
      totalTables = Sqflite.firstIntValue(tblRes) ?? 0;
    } catch (_) {}

    final report = PreFlightAuditReport(
      sqliteIntegrityOk: integrityOk,
      integrityErrors: integrityErrors,
      foreignKeyViolationsCount: fkErrors.length,
      foreignKeyViolationDetails: fkErrors,
      discrepantBatchesCount: discrepantBatches,
      negativeStockBatchesCount: negativeStockBatches,
      zeroPricedBatchesCount: zeroPricedBatches,
      expiredActiveBatchesCount: expiredActiveBatches,
      pendingOutboxCount: pendingOutbox,
      failedOutboxCount: failedOutbox,
      totalTablesCount: totalTables,
      totalActiveBatches: totalActiveBatches,
      timestamp: DateTime.now(),
    );

    _lastAudit = report;
    notifyListeners();
    return report;
  }

  /// Executes automatic healing:
  /// 1. Takes safety backup snapshot if [backupCallback] is supplied.
  /// 2. Reconciles batch balances from immutable ledger entries.
  /// 3. Unclogs poison-pill / failed sync outbox events.
  /// 4. Rebuilds B-Tree indexes (REINDEX), gathers optimizer statistics (ANALYZE), and compacts storage (VACUUM).
  Future<AutoHealResult> performAutoHealing({
    Database? targetDb,
    Future<String?> Function()? backupCallback,
    bool reconcileStock = true,
    bool unclogOutbox = true,
    bool vacuumAndReindex = true,
  }) async {
    final stopwatch = Stopwatch()..start();
    final db = targetDb ?? await DbHelper.instance.database;

    String? backupPath;
    if (backupCallback != null) {
      try {
        backupPath = await backupCallback();
      } catch (e) {
        debugPrint("Pre-heal backup note: $e");
      }
    }

    int initialDbBytes = 0;
    if (!kIsWeb) {
      try {
        final dbDirPath = await getDatabasesPath();
        final dbFile = File(join(dbDirPath, 'pharmacy.db'));
        if (await dbFile.exists()) initialDbBytes = await dbFile.length();
      } catch (_) {}
    }

    int batchesReconciled = 0;
    if (reconcileStock) {
      final hasBatches = await _tableExists(db, 'stock_batches');
      final hasLedger = await _tableExists(db, 'stock_ledger');

      if (hasBatches && hasLedger) {
        try {
          final discrepancyRows = await db.rawQuery('''
            SELECT sb.rowid, sb.product_id, sb.batch_number, sb.current_stock,
                   IFNULL(sl.computed_stock, 0) as target_stock
            FROM stock_batches sb
            LEFT JOIN (
              SELECT product_id, LOWER(TRIM(batch_number)) as clean_batch,
                     SUM(qty_in) - SUM(qty_out) as computed_stock
              FROM stock_ledger
              GROUP BY product_id, LOWER(TRIM(batch_number))
            ) sl ON sb.product_id = sl.product_id AND LOWER(TRIM(sb.batch_number)) = sl.clean_batch
            WHERE sb.current_stock != IFNULL(sl.computed_stock, 0)
          ''');

          if (discrepancyRows.isNotEmpty) {
            await db.transaction((txn) async {
              final batch = txn.batch();
              for (var row in discrepancyRows) {
                final rowId = (row['rowid'] as num).toInt();
                final targetStock = (row['target_stock'] as num).toInt();
                batch.rawUpdate(
                  'UPDATE stock_batches SET current_stock = ? WHERE rowid = ?',
                  [targetStock, rowId],
                );
              }
              await batch.commit(noResult: true);
            });
            batchesReconciled = discrepancyRows.length;
          }
        } catch (e) {
          debugPrint("Auto-heal stock reconciliation error: $e");
        }
      }
    }

    int uncloggedCount = 0;
    if (unclogOutbox) {
      final hasOutbox = await _tableExists(db, 'stock_outbox');
      if (hasOutbox) {
        try {
          uncloggedCount = await db.rawUpdate('''
            UPDATE stock_outbox
            SET status = 'pending', retry_count = 0, error_message = NULL, updated_at = ?
            WHERE status = 'failed' OR retry_count >= 5
          ''', [DateTime.now().toIso8601String()]);
        } catch (e) {
          debugPrint("Auto-heal outbox error: $e");
        }
      }
    }

    bool reindexDone = false;
    bool vacuumDone = false;
    if (vacuumAndReindex) {
      try {
        await db.execute('REINDEX;');
        reindexDone = true;
      } catch (e) {
        debugPrint("REINDEX error: $e");
      }

      try {
        await db.execute('ANALYZE;');
        await db.execute('PRAGMA optimize;');
      } catch (e) {
        debugPrint("ANALYZE/PRAGMA optimize error: $e");
      }

      try {
        await db.execute('VACUUM;');
        vacuumDone = true;
      } catch (e) {
        debugPrint("VACUUM error: $e");
      }
    }

    int finalDbBytes = initialDbBytes;
    if (!kIsWeb) {
      try {
        final dbDirPath = await getDatabasesPath();
        final dbFile = File(join(dbDirPath, 'pharmacy.db'));
        if (await dbFile.exists()) finalDbBytes = await dbFile.length();
      } catch (_) {}
    }

    stopwatch.stop();

    final result = AutoHealResult(
      success: true,
      message: "Database auto-healing complete in ${stopwatch.elapsedMilliseconds}ms. "
          "$batchesReconciled batches reconciled with ledger. "
          "$uncloggedCount outbox queues unclogged. "
          "${vacuumDone ? 'Storage vacuumed & reindexed.' : ''}",
      backupCreatedPath: backupPath,
      batchesReconciled: batchesReconciled,
      uncloggedOutboxEvents: uncloggedCount,
      vacuumCompleted: vacuumDone,
      reindexCompleted: reindexDone,
      initialDbMb: initialDbBytes / (1024 * 1024),
      finalDbMb: finalDbBytes / (1024 * 1024),
      duration: stopwatch.elapsed,
    );

    _lastHealResult = result;
    // Re-run audit to reflect healed state
    await runPreFlightAudit(targetDb: db);
    notifyListeners();
    return result;
  }
}
