import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmacy_app/database/db_helper.dart';
import 'package:pharmacy_app/services/database_maintenance_service.dart';
import 'package:pharmacy_app/services/stock_outbox_service.dart';
import 'package:pharmacy_app/services/server_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DbHelper.instance.setMockDatabase(db);

    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_master (
        id TEXT PRIMARY KEY,
        name TEXT,
        manufacturer_id TEXT,
        category_id TEXT,
        hsn_code TEXT,
        is_active INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_batches (
        product_id TEXT,
        batch_number TEXT,
        expiry_date TEXT,
        current_stock INTEGER DEFAULT 0,
        purchase_rate REAL DEFAULT 0.0,
        mrp REAL DEFAULT 0.0,
        packing INTEGER DEFAULT 1,
        supplier_name TEXT,
        is_synced INTEGER DEFAULT 0,
        updated_at TEXT,
        PRIMARY KEY (product_id, batch_number)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_ledger (
        ledger_id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT,
        batch_id TEXT,
        batch_number TEXT,
        product_id TEXT,
        voucher_type TEXT,
        voucher_no TEXT,
        qty_in INTEGER DEFAULT 0,
        qty_out INTEGER DEFAULT 0,
        quantity_delta INTEGER DEFAULT 0,
        closing_balance INTEGER DEFAULT 0,
        purchase_rate REAL DEFAULT 0.0,
        mrp REAL DEFAULT 0.0,
        supplier_name TEXT,
        remarks TEXT,
        user_id TEXT,
        financial_year TEXT,
        branch_id TEXT,
        terminal_id TEXT,
        idempotency_key TEXT,
        is_synced INTEGER DEFAULT 0,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_return_entries (
        entry_no TEXT PRIMARY KEY,
        date TEXT,
        supplier_name TEXT,
        original_purchase_no TEXT,
        done_by TEXT,
        grand_total REAL,
        gst_mode INTEGER,
        financial_year TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_return_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_no TEXT,
        product_name TEXT,
        batch TEXT,
        expiry TEXT,
        qty INTEGER,
        loose_qty INTEGER,
        f_qty INTEGER,
        unit TEXT,
        packin INTEGER,
        mrp REAL,
        p_rate REAL,
        s_rate REAL,
        disc_percent REAL,
        gst_percent REAL,
        total REAL,
        reason TEXT,
        supplier TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id TEXT PRIMARY KEY,
        name TEXT,
        phone TEXT,
        address TEXT,
        gst_in TEXT,
        dl_number TEXT,
        current_balance REAL DEFAULT 0.0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stock_outbox (
        id TEXT PRIMARY KEY,
        idempotency_key TEXT UNIQUE,
        operation_type TEXT,
        reference_no TEXT,
        branch_id TEXT,
        terminal_id TEXT,
        user_id TEXT,
        payload TEXT,
        status TEXT,
        error_message TEXT,
        retry_count INTEGER DEFAULT 0,
        last_attempt_at TEXT,
        created_at TEXT,
        updated_at TEXT
      )
    ''');
  });

  tearDown(() async {
    DbHelper.instance.setMockDatabase(null);
    await db.close();
  });

  group('Phase 2: Supplier Expiry Debit Note & Credit Claim Generator Tests', () {
    test('Debit note generation creates matching ledger movement, stock deduction, and outbox sync', () async {
      const productId = "PROD_EXP_001";
      const batchNo = "BATCH-APR26";
      const supplierName = "Apex Healthcare Distributors";
      const pRate = 45.0;
      const mrp = 75.0;
      const initialStock = 100;
      const returnQty = 30;

      // Seed product, supplier, and initial stock
      await db.insert('suppliers', {
        'id': 'SUP_001',
        'name': supplierName,
        'current_balance': 15000.0,
      });

      await db.insert('stock_batches', {
        'product_id': productId,
        'batch_number': batchNo,
        'expiry_date': '2026-04-30',
        'current_stock': initialStock,
        'purchase_rate': pRate,
        'mrp': mrp,
        'packing': 1,
        'supplier_name': supplierName,
      });

      // Opening stock in ledger so computed balance equals initial stock
      await db.insert('stock_ledger', {
        'timestamp': DateTime.now().toIso8601String(),
        'batch_id': batchNo,
        'batch_number': batchNo,
        'product_id': productId,
        'voucher_type': 'OPENING_STOCK',
        'voucher_no': 'INIT',
        'qty_in': initialStock,
        'qty_out': 0,
        'quantity_delta': initialStock,
        'purchase_rate': pRate,
        'mrp': mrp,
        'supplier_name': supplierName,
      });

      // Verify baseline health before return
      final baselineAudit = await DatabaseMaintenanceService.instance.runPreFlightAudit();
      expect(baselineAudit.discrepantBatchesCount, equals(0));
      expect(baselineAudit.negativeStockBatchesCount, equals(0));

      // Simulate Debit Note Generation Workflow
      const entryNo = "PRET-DN-TEST-998877";
      final now = DateTime.now();
      const lineTotal = pRate * returnQty;

      await db.transaction((txn) async {
        // 1. Insert Header
        await txn.insert('purchase_return_entries', {
          'entry_no': entryNo,
          'date': now.toIso8601String(),
          'supplier_name': supplierName,
          'original_purchase_no': '',
          'done_by': 'Admin',
          'grand_total': lineTotal,
          'gst_mode': 1,
          'financial_year': '2026-2027',
        });

        // 2. Insert Item
        await txn.insert('purchase_return_items', {
          'entry_no': entryNo,
          'product_name': 'Amoxicillin 500mg',
          'batch': batchNo,
          'expiry': '2026-04-30',
          'qty': returnQty,
          'loose_qty': 0,
          'f_qty': 0,
          'unit': 'Strip',
          'packin': 1,
          'mrp': mrp,
          'p_rate': pRate,
          's_rate': mrp,
          'disc_percent': 0.0,
          'gst_percent': 12.0,
          'total': lineTotal,
          'reason': 'Near Expiry Return',
          'supplier': supplierName,
        });

        // 3. Deduct Stock Batch
        await txn.rawUpdate(
          'UPDATE stock_batches SET current_stock = MAX(0, current_stock - ?), is_synced = 0, updated_at = ? WHERE product_id = ? AND batch_number = ? COLLATE NOCASE',
          [returnQty, DateTime.now().toUtc().toIso8601String(), productId, batchNo],
        );

        // 4. Record Immutable Stock Ledger Entry
        final idempKey = StockOutboxService.generateIdempotencyKey(
          branchId: ServerConfigService.instance.storeBranchId,
          terminalId: ServerConfigService.instance.terminalId,
          operationType: 'PURCHASE_RETURN',
          referenceNo: "$entryNo-$productId-$batchNo",
        );
        await DbHelper.instance.recordStockLedgerEntryInTxn(
          txn,
          entryType: 'PURCHASE_RETURN',
          referenceNo: entryNo,
          productId: productId,
          batchNumber: batchNo,
          quantityDelta: -returnQty,
          qtyIn: 0,
          qtyOut: returnQty,
          purchaseRate: pRate,
          mrp: mrp,
          supplierName: supplierName,
          remarks: 'Near-Expiry Wholesaler Debit Note / Claim',
          branchId: ServerConfigService.instance.storeBranchId,
          terminalId: ServerConfigService.instance.terminalId,
          idempotencyKey: idempKey,
        );

        // 5. Reduce Supplier Ledger Balance
        await txn.rawUpdate(
          'UPDATE suppliers SET current_balance = current_balance - ? WHERE name = ? COLLATE NOCASE',
          [lineTotal, supplierName],
        );
      });

      // Queue into StockOutbox
      final outboxIdempKey = StockOutboxService.generateIdempotencyKey(
        branchId: ServerConfigService.instance.storeBranchId,
        terminalId: ServerConfigService.instance.terminalId,
        operationType: 'PURCHASE_RETURN',
        referenceNo: entryNo,
      );
      await StockOutboxService.instance.queueOperation(
        operationType: 'PURCHASE_RETURN',
        referenceNo: entryNo,
        payload: {
          'entry_no': entryNo,
          'supplier_name': supplierName,
          'grand_total': lineTotal,
        },
        idempotencyKey: outboxIdempKey,
      );

      // --- VERIFICATIONS ---
      // 1. Stock Batch deducted correctly
      final updatedBatch = await db.query('stock_batches', where: 'product_id = ?', whereArgs: [productId]);
      expect(updatedBatch.first['current_stock'], equals(initialStock - returnQty));

      // 2. Stock Ledger has matching negative movement
      final ledgerEntries = await db.query(
        'stock_ledger',
        where: 'voucher_no = ? AND voucher_type = ?',
        whereArgs: [entryNo, 'PURCHASE_RETURN'],
      );
      expect(ledgerEntries.length, equals(1));
      expect(ledgerEntries.first['qty_out'], equals(returnQty));
      expect(ledgerEntries.first['quantity_delta'], equals(-returnQty));

      // 3. Supplier Balance deducted by exact credit claim amount
      final updatedSup = await db.query('suppliers', where: 'name = ?', whereArgs: [supplierName]);
      expect((updatedSup.first['current_balance'] as num).toDouble(), equals(15000.0 - lineTotal));

      // 4. Outbox queued operation exists with pending status
      final outboxEntries = await db.query('stock_outbox', where: 'reference_no = ?', whereArgs: [entryNo]);
      expect(outboxEntries.length, equals(1));
      expect(outboxEntries.first['operation_type'], equals('PURCHASE_RETURN'));
      expect(outboxEntries.first['status'], equals('pending'));

      // 5. Pre-Flight Health Audit confirms ZERO discrepancies between stock_batches and stock_ledger
      final postAudit = await DatabaseMaintenanceService.instance.runPreFlightAudit();
      expect(postAudit.discrepantBatchesCount, equals(0), reason: 'Stock batches and stock ledger must remain 100% reconciled');
      expect(postAudit.negativeStockBatchesCount, equals(0));
      expect(postAudit.sqliteIntegrityOk, isTrue);
      expect(postAudit.isProductionReady, isTrue);
    });
  });
}
