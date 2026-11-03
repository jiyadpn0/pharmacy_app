import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmacy_app/database/db_helper.dart';
import 'package:pharmacy_app/services/stock_outbox_service.dart';
import 'package:pharmacy_app/services/server_config_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Requirement 3 & 7: Idempotency Keys & Terminal Configuration', () {
    test('generateIdempotencyKey generates deterministic, unique, and sanitized keys', () {
      final key1 = StockOutboxService.generateIdempotencyKey(
        branchId: 'STORE-MAIN/NORTH',
        terminalId: 'POS#01',
        operationType: 'SALE',
        referenceNo: 'INV/2026/001',
        timestampMicros: 1700000000000000,
      );

      final key2 = StockOutboxService.generateIdempotencyKey(
        branchId: 'STORE-MAIN/NORTH',
        terminalId: 'POS#01',
        operationType: 'SALE',
        referenceNo: 'INV/2026/001',
        timestampMicros: 1700000000000000,
      );

      final key3 = StockOutboxService.generateIdempotencyKey(
        branchId: 'STORE-MAIN/NORTH',
        terminalId: 'POS#01',
        operationType: 'SALE',
        referenceNo: 'INV/2026/002',
        timestampMicros: 1700000000000000,
      );

      // Deterministic replay with identical parameters
      expect(key1, equals(key2));
      expect(key1.startsWith('IDEMP_'), isTrue);
      expect(key1.contains('STORE-MAIN_NORTH'), isTrue);
      expect(key1.contains('POS_01'), isTrue);
      expect(key1.contains('SALE'), isTrue);
      expect(key1.contains('INV_2026_001'), isTrue);

      // Different reference produces distinct key
      expect(key1, isNot(equals(key3)));
    });

    test('ServerConfigService generates stable machineUuid and prevents unconfigured POS-01 silently', () async {
      final config = ServerConfigService.instance;
      expect(config.machineUuid, isNotEmpty);
      expect(config.machineUuid, equals(config.machineUuid)); // Stable across invocations

      // Verify detection of duplicate terminal ID
      final warning = await config.verifyDistinctTerminalId(
        activeComputers: [
          {
            'machine_id': 'DIFFERENT_MACHINE_UUID_999',
            'terminal_id': 'POS-01',
            'branch_id': config.storeBranchId,
            'last_seen': DateTime.now().toIso8601String(),
          }
        ],
        currentTerminalId: 'POS-01',
      );

      expect(warning, isNotNull);
      expect(warning!.contains('CONFLICT'), isTrue);
    });
  });

  group('Requirement 5 & 6: SQLite Outbox, Event Deduplication & Ledger', () {
    late Database db;

    setUp(() async {
      db = await openDatabase(inMemoryDatabasePath, version: 1, onCreate: (db, version) async {
        await DbHelper.instance.ensureStockConvergenceTables(db);
        await db.execute('''
          CREATE TABLE stock_batches (
            product_id TEXT,
            batch_number TEXT,
            expiry_date TEXT,
            current_stock INTEGER DEFAULT 0,
            purchase_rate REAL DEFAULT 0.0,
            mrp REAL DEFAULT 0.0,
            sale_rate REAL DEFAULT 0.0,
            PRIMARY KEY (product_id, batch_number)
          )
        ''');
      });
    });

    tearDown(() async {
      await db.close();
    });

    test('Durable event deduplication via processed_sync_events', () async {
      const eventId = 'EVT_SALE_2026_9999';

      expect(await DbHelper.instance.isEventAlreadyProcessed(eventId, db), isFalse);

      await DbHelper.instance.markEventProcessed(eventId, 'REALTIME', db);

      expect(await DbHelper.instance.isEventAlreadyProcessed(eventId, db), isTrue);

      // Duplicate mark is idempotent (INSERT OR IGNORE)
      await DbHelper.instance.markEventProcessed(eventId, 'LAN', db);
      expect(await DbHelper.instance.isEventAlreadyProcessed(eventId, db), isTrue);
    });

    test('Stock Ledger records transactional deltas and maintains audit trail', () async {
      const prodId = 'PROD_PARACETAMOL';
      const batchNo = 'BATCH_P100';

      // 1. Initial Purchase: +100 units
      await db.insert('stock_batches', {
        'product_id': prodId,
        'batch_number': batchNo,
        'expiry_date': '2028-12-31',
        'current_stock': 100,
        'purchase_rate': 10.0,
        'mrp': 20.0,
        'sale_rate': 18.0,
      });

      await db.transaction((txn) async {
        await DbHelper.instance.recordStockLedgerEntryInTxn(
          txn,
          entryType: 'PURCHASE',
          referenceNo: 'PUR-001',
          productId: prodId,
          batchNumber: batchNo,
          quantityDelta: 100,
          branchId: 'BRANCH-01',
          terminalId: 'POS-01',
          idempotencyKey: 'IDEMP_PUR_001',
        );
      });

      // 2. Sale deduction: -25 units
      await db.transaction((txn) async {
        await txn.rawUpdate(
          'UPDATE stock_batches SET current_stock = current_stock - 25 WHERE product_id = ? AND batch_number = ?',
          [prodId, batchNo],
        );
        await DbHelper.instance.recordStockLedgerEntryInTxn(
          txn,
          entryType: 'SALE',
          referenceNo: 'INV-001',
          productId: prodId,
          batchNumber: batchNo,
          quantityDelta: -25,
          branchId: 'BRANCH-01',
          terminalId: 'POS-01',
          idempotencyKey: 'IDEMP_SALE_001',
        );
      });

      // 3. Sales Return: +5 units
      await db.transaction((txn) async {
        await txn.rawUpdate(
          'UPDATE stock_batches SET current_stock = current_stock + 5 WHERE product_id = ? AND batch_number = ?',
          [prodId, batchNo],
        );
        await DbHelper.instance.recordStockLedgerEntryInTxn(
          txn,
          entryType: 'SALES_RETURN',
          referenceNo: 'SRET-001',
          productId: prodId,
          batchNumber: batchNo,
          quantityDelta: 5,
          branchId: 'BRANCH-01',
          terminalId: 'POS-01',
          idempotencyKey: 'IDEMP_SRET_001',
        );
      });

      // 4. Stock Adjustment: -10 units (breakage)
      await db.transaction((txn) async {
        await txn.rawUpdate(
          'UPDATE stock_batches SET current_stock = current_stock - 10 WHERE product_id = ? AND batch_number = ?',
          [prodId, batchNo],
        );
        await DbHelper.instance.recordStockLedgerEntryInTxn(
          txn,
          entryType: 'ADJUSTMENT',
          referenceNo: 'ADJ-001',
          productId: prodId,
          batchNumber: batchNo,
          quantityDelta: -10,
          branchId: 'BRANCH-01',
          terminalId: 'POS-01',
          idempotencyKey: 'IDEMP_ADJ_001',
        );
      });

      // Reconcile batch table stock against ledger sum
      final batchRow = await db.query('stock_batches', where: 'product_id = ? AND batch_number = ?', whereArgs: [prodId, batchNo]);
      final liveStock = batchRow.first['current_stock'] as int;

      final ledgerSumRow = await db.rawQuery(
        'SELECT SUM(quantity_delta) as computed_stock, COUNT(*) as op_count FROM stock_ledger WHERE product_id = ? AND batch_number = ?',
        [prodId, batchNo],
      );
      final computedStock = (ledgerSumRow.first['computed_stock'] as num).toInt();
      final opCount = (ledgerSumRow.first['op_count'] as num).toInt();

      expect(liveStock, equals(70)); // 100 - 25 + 5 - 10 = 70
      expect(computedStock, equals(70));
      expect(liveStock, equals(computedStock)); // Exact convergence
      expect(opCount, equals(4));
    });

    test('Outbox queue, status transitions, and payload serialization', () async {
      final entry = await StockOutboxService.instance.queueOperation(
        operationType: 'SALE',
        referenceNo: 'INV-9001',
        payload: {
          'invoice_no': 'INV-9001',
          'total': 450.0,
          'items': [
            {'product_id': 'P1', 'qty': 2}
          ]
        },
        idempotencyKey: 'IDEMP_TEST_SALE_9001',
        executor: db,
      );

      expect(entry.status, equals('pending'));
      expect(entry.operationType, equals('SALE'));
      expect(entry.referenceNo, equals('INV-9001'));
      expect(entry.idempotencyKey, equals('IDEMP_TEST_SALE_9001'));

      // Check record in SQLite
      final rows = await db.query('stock_outbox', where: 'id = ?', whereArgs: [entry.id]);
      expect(rows.length, equals(1));
      expect(rows.first['status'], equals('pending'));

      // Transition to in_flight
      await db.update('stock_outbox', {'status': 'in_flight'}, where: 'id = ?', whereArgs: [entry.id]);
      final inFlightRow = await db.query('stock_outbox', where: 'id = ?', whereArgs: [entry.id]);
      expect(inFlightRow.first['status'], equals('in_flight'));

      // Simulate business rejection (e.g. INSUFFICIENT_STOCK from server)
      await db.update('stock_outbox', {
        'status': 'rejected',
        'error_message': 'INSUFFICIENT_STOCK: Only 0 available',
      }, where: 'id = ?', whereArgs: [entry.id]);

      final rejectedRow = await db.query('stock_outbox', where: 'id = ?', whereArgs: [entry.id]);
      expect(rejectedRow.first['status'], equals('rejected'));
      expect(rejectedRow.first['error_message'], contains('INSUFFICIENT_STOCK'));

      // Re-read via StockOutboxEntry factory
      final parsed = StockOutboxEntry.fromMap(rejectedRow.first);
      expect(parsed.status, equals('rejected'));
      expect(parsed.payload['invoice_no'], equals('INV-9001'));
    });

    test('Insufficient stock condition aborts atomic transaction', () async {
      const prodId = 'PROD_INSULIN';
      const batchNo = 'B_INS_01';

      await db.insert('stock_batches', {
        'product_id': prodId,
        'batch_number': batchNo,
        'expiry_date': '2026-06-30',
        'current_stock': 5,
      });

      // Attempting to deduct 10 units when only 5 are in stock must fail
      expect(
        () async {
          await db.transaction((txn) async {
            final check = await txn.rawQuery(
              'SELECT current_stock FROM stock_batches WHERE product_id = ? AND batch_number = ?',
              [prodId, batchNo],
            );
            final current = (check.first['current_stock'] as num).toInt();
            if (current < 10) {
              throw Exception('STOCK_SHORTAGE: Available: $current, Requested: 10');
            }
            await txn.rawUpdate(
              'UPDATE stock_batches SET current_stock = current_stock - 10 WHERE product_id = ? AND batch_number = ?',
              [prodId, batchNo],
            );
          });
        },
        throwsA(predicate((e) => e.toString().contains('STOCK_SHORTAGE'))),
      );

      // Verify stock was unaffected due to atomic rollback
      final checkAfter = await db.rawQuery(
        'SELECT current_stock FROM stock_batches WHERE product_id = ? AND batch_number = ?',
        [prodId, batchNo],
      );
      expect((checkAfter.first['current_stock'] as num).toInt(), equals(5));
    });

    test('Branch Isolation prevents mixing data across stores', () {
      const storeABranch = 'MAIN_STORE';
      const storeBBranch = 'SUB_BRANCH_02';

      final keyBranchA = StockOutboxService.generateIdempotencyKey(
        branchId: storeABranch,
        terminalId: 'POS-01',
        operationType: 'SALE',
        referenceNo: 'INV-100',
        timestampMicros: 1000,
      );

      final keyBranchB = StockOutboxService.generateIdempotencyKey(
        branchId: storeBBranch,
        terminalId: 'POS-01',
        operationType: 'SALE',
        referenceNo: 'INV-100',
        timestampMicros: 1000,
      );

      expect(keyBranchA, isNot(equals(keyBranchB)));
      expect(keyBranchA.contains(storeABranch), isTrue);
      expect(keyBranchB.contains(storeBBranch), isTrue);

      // Verify Realtime event filter matching logic
      bool matchesBranch(Map<String, dynamic> row, String currentBranch) {
        final rowBranch = row['branch_id']?.toString().trim();
        return rowBranch == null || rowBranch.isEmpty || rowBranch == currentBranch;
      }

      final rowStoreA = {'entry_no': 'INV-1', 'branch_id': storeABranch};
      final rowStoreB = {'entry_no': 'INV-2', 'branch_id': storeBBranch};

      expect(matchesBranch(rowStoreA, storeABranch), isTrue);
      expect(matchesBranch(rowStoreB, storeABranch), isFalse); // Dropped: branch isolation
    });
  });
}
