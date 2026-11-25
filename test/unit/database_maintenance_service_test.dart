import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmacy_app/services/database_maintenance_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DatabaseMaintenanceService Tests', () {
    late Database db;

    setUp(() async {
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (d, v) async {
          await d.execute('''
            CREATE TABLE test_table (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT,
              val REAL
            );
          ''');
          // Insert sample records to allocate pages
          for (int i = 0; i < 50; i++) {
            await d.insert('test_table', {'name': 'Item $i', 'val': i * 1.5});
          }
        },
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('getHealthReport returns valid SQLite page stats and verified integrity', () async {
      final report = await DatabaseMaintenanceService.instance.getHealthReport(targetDb: db);

      expect(report.isHealthy, isTrue);
      expect(report.integrityMessage.toLowerCase(), equals('ok'));
      expect(report.pageSize, greaterThanOrEqualTo(512));
      expect(report.pageCount, greaterThan(0));
      expect(report.freelistCount, greaterThanOrEqualTo(0));
      expect(report.timestamp, isNotNull);
    });

    test('performMaintenance executes checkpoint, optimize, and quick_check successfully', () async {
      final result = await DatabaseMaintenanceService.instance.performMaintenance(
        targetDb: db,
        truncateWal: true,
        runOptimize: true,
      );

      expect(result.success, isTrue);
      expect(result.quickCheckPassed, isTrue);
      expect(result.quickCheckResult.toLowerCase(), equals('ok'));
      expect(result.duration.inMilliseconds, greaterThanOrEqualTo(0));
      expect(result.message, contains('Database maintenance completed'));
      expect(result.message, contains('Integrity verified (OK)'));
    });

    test('Health report cached on service matches last execution', () async {
      await DatabaseMaintenanceService.instance.getHealthReport(targetDb: db);
      final cached = DatabaseMaintenanceService.instance.lastReport;

      expect(cached, isNotNull);
      expect(cached!.isHealthy, isTrue);
      expect(cached.pageCount, greaterThan(0));
    });

    test('Periodic maintenance timer starts and stops cleanly', () {
      final service = DatabaseMaintenanceService.instance;
      service.startPeriodicMaintenance(interval: const Duration(minutes: 10));
      // Should not throw and timer is active
      service.stopPeriodicMaintenance();
      // Should safely cancel
    });

    test('runPreFlightAudit evaluates clean database as EXCELLENT and production ready', () async {
      final audit = await DatabaseMaintenanceService.instance.runPreFlightAudit(targetDb: db);

      expect(audit.sqliteIntegrityOk, isTrue);
      expect(audit.foreignKeyViolationsCount, equals(0));
      expect(audit.discrepantBatchesCount, equals(0));
      expect(audit.negativeStockBatchesCount, equals(0));
      expect(audit.failedOutboxCount, equals(0));
      expect(audit.isProductionReady, isTrue);
      expect(audit.healthGrade, equals('EXCELLENT'));
      expect(audit.totalTablesCount, greaterThanOrEqualTo(1));
    });

    test('runPreFlightAudit detects inventory ledger discrepancies and performAutoHealing repairs them', () async {
      // Create stock_batches, stock_ledger, and stock_outbox
      await db.execute('''
        CREATE TABLE stock_batches (
          rowid INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id TEXT,
          batch_number TEXT,
          expiry_date TEXT,
          purchase_rate REAL,
          mrp REAL,
          current_stock INTEGER
        );
      ''');
      await db.execute('''
        CREATE TABLE stock_ledger (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id TEXT,
          batch_number TEXT,
          qty_in INTEGER,
          qty_out INTEGER
        );
      ''');
      await db.execute('''
        CREATE TABLE stock_outbox (
          id TEXT PRIMARY KEY,
          status TEXT,
          retry_count INTEGER,
          error_message TEXT,
          updated_at TEXT
        );
      ''');

      // 1. Insert batch with corrupted current_stock (shows 100, but ledger only has 30 in and 10 out = 20)
      await db.insert('stock_batches', {
        'product_id': 'PROD_AMOX',
        'batch_number': 'B123',
        'expiry_date': '2028-12-31',
        'purchase_rate': 45.0,
        'mrp': 65.0,
        'current_stock': 100, // Corrupted cached stock
      });

      // 2. Insert batch with negative stock
      await db.insert('stock_batches', {
        'product_id': 'PROD_PARA',
        'batch_number': 'P999',
        'expiry_date': '2028-12-31',
        'purchase_rate': 12.0,
        'mrp': 20.0,
        'current_stock': -5, // Negative stock anomaly
      });

      // Insert matching ledger row for B123
      await db.insert('stock_ledger', {
        'product_id': 'PROD_AMOX',
        'batch_number': 'B123',
        'qty_in': 30,
        'qty_out': 10,
      });

      // Insert matching ledger row for P999 to resolve to 0
      await db.insert('stock_ledger', {
        'product_id': 'PROD_PARA',
        'batch_number': 'P999',
        'qty_in': 0,
        'qty_out': 0,
      });

      // 3. Insert poisoned outbox item
      await db.insert('stock_outbox', {
        'id': 'OUT_ERR_01',
        'status': 'failed',
        'retry_count': 6,
        'error_message': 'Transient timeout network error',
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Run Audit before healing
      final preAudit = await DatabaseMaintenanceService.instance.runPreFlightAudit(targetDb: db);
      expect(preAudit.sqliteIntegrityOk, isTrue);
      expect(preAudit.discrepantBatchesCount, equals(2)); // Both AMOX and PARA mismatch
      expect(preAudit.negativeStockBatchesCount, equals(1)); // PARA is -5
      expect(preAudit.failedOutboxCount, equals(1)); // OUT_ERR_01
      expect(preAudit.isProductionReady, isFalse);
      expect(preAudit.healthGrade, equals('ATTENTION'));

      // Perform Auto-Healing
      final healResult = await DatabaseMaintenanceService.instance.performAutoHealing(
        targetDb: db,
        backupCallback: () async => 'C:\\mock_backups\\test_snapshot.db',
        reconcileStock: true,
        unclogOutbox: true,
        vacuumAndReindex: true,
      );

      expect(healResult.success, isTrue);
      expect(healResult.backupCreatedPath, equals('C:\\mock_backups\\test_snapshot.db'));
      expect(healResult.batchesReconciled, equals(2));
      expect(healResult.uncloggedOutboxEvents, equals(1));
      expect(healResult.vacuumCompleted, isTrue);
      expect(healResult.reindexCompleted, isTrue);

      // Verify healed state in database
      final amoxRow = await db.query('stock_batches', where: 'product_id = ?', whereArgs: ['PROD_AMOX']);
      expect(amoxRow.first['current_stock'], equals(20)); // Reconciled from 30 - 10 = 20!

      final paraRow = await db.query('stock_batches', where: 'product_id = ?', whereArgs: ['PROD_PARA']);
      expect(paraRow.first['current_stock'], equals(0)); // Reconciled from negative -5 to 0!

      final outboxRow = await db.query('stock_outbox', where: 'id = ?', whereArgs: ['OUT_ERR_01']);
      expect(outboxRow.first['status'], equals('pending'));
      expect(outboxRow.first['retry_count'], equals(0));

      // Post-heal audit should now be completely healthy
      final postAudit = DatabaseMaintenanceService.instance.lastAudit;
      expect(postAudit, isNotNull);
      expect(postAudit!.discrepantBatchesCount, equals(0));
      expect(postAudit.negativeStockBatchesCount, equals(0));
      expect(postAudit.failedOutboxCount, equals(0));
      expect(postAudit.isProductionReady, isTrue);
      expect(postAudit.healthGrade, equals('EXCELLENT'));
    });
  });
}
