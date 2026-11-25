import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmacy_app/database/db_helper.dart';
import 'package:pharmacy_app/services/stock_service.dart';
import 'package:pharmacy_app/repositories/stock_repository.dart';
import 'package:pharmacy_app/screens/opening_stock_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (d, v) async {
        await d.execute('''
          CREATE TABLE product_master (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            mrp REAL DEFAULT 0.0,
            purchase_rate REAL DEFAULT 0.0,
            sale_rate REAL DEFAULT 0.0,
            rack_id TEXT,
            packing INTEGER DEFAULT 1,
            gst_percent REAL DEFAULT 12.0,
            hsn_code TEXT,
            category_id TEXT,
            is_active INTEGER DEFAULT 1
          )
        ''');

        await d.execute('''
          CREATE TABLE batch_master (
            batch_id TEXT PRIMARY KEY,
            product_id TEXT NOT NULL,
            batch_number TEXT NOT NULL,
            expiry_date TEXT NOT NULL,
            mfg_date TEXT,
            supplier_id TEXT,
            supplier_name TEXT,
            packing INTEGER DEFAULT 1,
            purchase_rate REAL DEFAULT 0.0,
            landing_cost REAL DEFAULT 0.0,
            mrp REAL DEFAULT 0.0,
            sale_rate REAL DEFAULT 0.0,
            gst_percent REAL DEFAULT 12.0,
            rack TEXT,
            is_active INTEGER DEFAULT 1,
            created_at TEXT
          )
        ''');

        await d.execute('''
          CREATE TABLE stock_batches (
            product_id TEXT,
            batch_number TEXT,
            expiry_date TEXT,
            mfg_date TEXT,
            current_stock INTEGER DEFAULT 0,
            purchase_rate REAL DEFAULT 0.0,
            landing_cost REAL DEFAULT 0.0,
            mrp REAL DEFAULT 0.0,
            sale_rate REAL DEFAULT 0.0,
            s_disc_percent REAL DEFAULT 0.0,
            gst_percent REAL DEFAULT 12.0,
            rack TEXT,
            supplier_name TEXT,
            packing INTEGER DEFAULT 1,
            is_active INTEGER DEFAULT 1,
            financial_year TEXT,
            PRIMARY KEY (product_id, batch_number, expiry_date, purchase_rate, landing_cost, mrp, sale_rate, packing, supplier_name, gst_percent)
          )
        ''');

        await d.execute('''
          CREATE TABLE stock_ledger (
            ledger_id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            batch_id TEXT NOT NULL,
            batch_number TEXT,
            product_id TEXT NOT NULL,
            voucher_type TEXT NOT NULL,
            voucher_no TEXT NOT NULL,
            qty_in INTEGER NOT NULL DEFAULT 0,
            qty_out INTEGER NOT NULL DEFAULT 0,
            quantity_delta INTEGER NOT NULL DEFAULT 0,
            closing_balance INTEGER NOT NULL DEFAULT 0,
            purchase_rate REAL DEFAULT 0.0,
            mrp REAL DEFAULT 0.0,
            supplier_name TEXT,
            remarks TEXT,
            user_id TEXT,
            financial_year TEXT,
            branch_id TEXT DEFAULT 'MAIN_STORE',
            terminal_id TEXT DEFAULT 'POS-01',
            idempotency_key TEXT UNIQUE
          )
        ''');
      },
    );

    DbHelper.instance.setMockDatabase(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Opening Stock & Store Migration Tests', () {
    test('StagedOpeningStockItem accurately computes total loose units and dual valuation', () {
      final item = StagedOpeningStockItem(
        productName: 'Paracetamol 650mg',
        batchNumber: 'PCM-101',
        expiryDate: '12/28',
        packSize: 10,
        packsQty: 25,
        looseQty: 4,
        purchaseRate: 18.50,
        mrp: 25.00,
        saleRate: 22.00,
        rack: 'A1',
        gstPercent: 12.0,
        hsnCode: '3004',
      );

      // Total Loose Units = (25 * 10) + 4 = 254 units
      expect(item.totalLooseUnits, equals(254));

      // 254 loose units / 10 = 25.4 packs * 18.50 = 469.90 Purchase Value
      expect(item.totalPurchaseValue, closeTo(469.90, 0.01));

      // 25.4 packs * 25.00 = 635.00 MRP Value
      expect(item.totalMrpValue, closeTo(635.00, 0.01));

      // Retail Gross Margin %: ((635 - 469.9) / 635) * 100 = 25.999%
      final marginPct = ((item.totalMrpValue - item.totalPurchaseValue) / item.totalMrpValue) * 100;
      expect(marginPct, closeTo(26.0, 0.1));
    });

    test('Opening Stock Inward correctly records StockLedgerEntry and updates live inventory', () async {
      const prodId = 'PROD_AMOX_500';
      await db.insert('product_master', {
        'id': prodId,
        'name': 'Amoxicillin 500mg',
        'mrp': 120.0,
        'purchase_rate': 85.0,
        'sale_rate': 110.0,
        'rack_id': 'B3',
        'packing': 10,
        'gst_percent': 12.0,
        'hsn_code': '3004',
        'category_id': 'General',
        'is_active': 1,
      });

      // Process Opening Stock Inward of 50 packs (500 loose units)
      await StockService.instance.processStockIn(
        productId: prodId,
        batchNumber: 'OPN-AMX-01',
        expiryDate: '06/28',
        totalLooseQty: 500,
        voucherType: 'OPENING_STOCK',
        voucherNo: 'OPN_INIT_101',
        packing: 10,
        purchaseRate: 85.0,
        landingCost: 85.0,
        mrp: 120.0,
        saleRate: 110.0,
        gstPercent: 12.0,
        rack: 'B3',
        remarks: 'Opening Shop Inventory Audit',
      );

      // Verify Stock Ledger Entry
      final ledgerRows = await db.query('stock_ledger', where: 'product_id = ?', whereArgs: [prodId]);
      expect(ledgerRows.length, equals(1));
      expect(ledgerRows.first['voucher_type'], equals('OPENING_STOCK'));
      expect(ledgerRows.first['voucher_no'], equals('OPN_INIT_101'));
      expect(ledgerRows.first['qty_in'], equals(500));
      expect(ledgerRows.first['qty_out'], equals(0));
      // Verify Batch Master
      final batchRows = await db.query('batch_master', where: 'product_id = ?', whereArgs: [prodId]);
      expect(batchRows.length, equals(1));
      expect(batchRows.first['batch_number'], equals('OPN-AMX-01'));
      expect(batchRows.first['purchase_rate'], equals(85.0));
      expect(batchRows.first['mrp'], equals(120.0));

      // Verify Live Stock Calculation
      final batchId = batchRows.first['batch_id'] as String;
      final liveStock = await StockRepository.instance.getLiveStockForBatch(batchId);
      expect(liveStock, equals(500));
    });
  });
}
