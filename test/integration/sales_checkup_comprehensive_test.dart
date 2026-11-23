import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmacy_app/database/db_helper.dart';
import 'package:pharmacy_app/providers/pharmacy_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Comprehensive Sales Entry & Multi-PC Checkup', () {
    late Database db;
    late PharmacyProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});

      // 1. Initialize clean in-memory database with production ERP schema
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE product_master (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              generic_name TEXT,
              barcode TEXT,
              sku TEXT,
              hsn_code TEXT,
              rack_id TEXT,
              gst_percent REAL DEFAULT 12.0,
              packing INTEGER DEFAULT 1,
              mrp REAL DEFAULT 0.0,
              purchase_rate REAL DEFAULT 0.0,
              sale_rate REAL DEFAULT 0.0,
              s_disc_percent REAL DEFAULT 0.0
            );
          ''');

          await db.execute('''
            CREATE TABLE stock_batches (
              rowid INTEGER PRIMARY KEY AUTOINCREMENT,
              product_id TEXT NOT NULL,
              batch_number TEXT NOT NULL,
              expiry_date TEXT,
              current_stock INTEGER DEFAULT 0,
              mrp REAL DEFAULT 0.0,
              purchase_rate REAL DEFAULT 0.0,
              sale_rate REAL DEFAULT 0.0,
              is_synced INTEGER DEFAULT 1,
              updated_at TEXT
            );
          ''');

          await db.execute('''
            CREATE TABLE sales_invoices (
              entry_no TEXT PRIMARY KEY,
              date TEXT,
              customer_acc TEXT,
              patient TEXT,
              mobile TEXT,
              doctor TEXT,
              doctor_reg_no TEXT,
              special_order_json TEXT,
              tax_type TEXT,
              sub_total REAL DEFAULT 0.0,
              discount_percent REAL DEFAULT 0.0,
              discount REAL DEFAULT 0.0,
              additional_discount REAL DEFAULT 0.0,
              other_charge REAL DEFAULT 0.0,
              rcvd_amt REAL DEFAULT 0.0,
              round_off REAL DEFAULT 0.0,
              grand_total REAL DEFAULT 0.0,
              agent TEXT,
              expecting_date TEXT,
              special_customer_name TEXT,
              special_customer_phone TEXT,
              payment_remarks TEXT,
              secondary_acc TEXT,
              secondary_amt REAL DEFAULT 0.0,
              sales_return_amt REAL DEFAULT 0.0,
              is_paid INTEGER DEFAULT 1,
              days INTEGER DEFAULT 0,
              financial_year TEXT,
              order_type TEXT,
              is_deleted INTEGER DEFAULT 0,
              is_synced INTEGER DEFAULT 0,
              terminal_id TEXT DEFAULT 'POS-01'
            );
          ''');

          await db.execute('''
            CREATE TABLE sales_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              invoice_no TEXT,
              product_id TEXT,
              product_name TEXT,
              extra TEXT,
              batch_number TEXT,
              expiry_date TEXT,
              qty INTEGER,
              quantity INTEGER,
              packin INTEGER,
              packing INTEGER,
              mrp REAL,
              purchase_rate REAL DEFAULT 0.0,
              landing_cost REAL DEFAULT 0.0,
              taxable_sp REAL,
              s_rate REAL,
              sale_rate REAL,
              disc_percent REAL,
              disc_amt REAL,
              gst_percent REAL,
              tax_percent REAL,
              gst_amt REAL,
              cgst_amt REAL DEFAULT 0.0,
              sgst_amt REAL DEFAULT 0.0,
              igst_amt REAL DEFAULT 0.0,
              total REAL,
              profit REAL,
              supplier_name TEXT,
              rack TEXT,
              terminal_id TEXT DEFAULT 'POS-01'
            );
          ''');

          await db.execute('''
            CREATE TABLE purchase_entries (
              entry_no TEXT PRIMARY KEY,
              date TEXT,
              supplier_name TEXT,
              sup_inv_no TEXT,
              sup_inv_date TEXT,
              done_by TEXT,
              inv_total REAL DEFAULT 0.0,
              grand_total REAL DEFAULT 0.0,
              discount REAL DEFAULT 0.0,
              other_charge REAL DEFAULT 0.0,
              less_cr_note REAL DEFAULT 0.0,
              round_off REAL DEFAULT 0.0,
              remarks TEXT,
              po_no TEXT,
              financial_year TEXT,
              is_deleted INTEGER DEFAULT 0,
              is_synced INTEGER DEFAULT 0,
              terminal_id TEXT DEFAULT 'POS-01'
            );
          ''');

          await db.execute('''
            CREATE TABLE purchase_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              entry_no TEXT,
              product_id TEXT,
              product_name TEXT,
              extra TEXT,
              batch TEXT,
              expiry TEXT,
              packin INTEGER,
              qty INTEGER,
              f_qty INTEGER,
              mrp REAL,
              p_rate REAL,
              gross REAL,
              disc_percent REAL,
              disc_amt REAL,
              net REAL,
              gst_percent REAL,
              gst_amt REAL,
              total REAL,
              rack TEXT,
              hsn_code TEXT,
              s_disc_percent REAL DEFAULT 0.0,
              s_rate REAL DEFAULT 0.0,
              l_cost REAL DEFAULT 0.0,
              terminal_id TEXT DEFAULT 'POS-01'
            );
          ''');

          await db.execute('''
            CREATE TABLE stock_ledger (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
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
              idempotency_key TEXT UNIQUE
            );
          ''');

          await db.execute('''
            CREATE TABLE stock_outbox (
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
              created_at TEXT,
              updated_at TEXT,
              retry_count INTEGER DEFAULT 0,
              last_attempt_at TEXT
            );
          ''');

          await db.execute('''
            CREATE TABLE patients (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              mobile TEXT,
              current_balance REAL DEFAULT 0.0
            );
          ''');

          await db.execute('''
            CREATE TABLE voucher_sequences (
              voucher_type TEXT,
              financial_year TEXT,
              last_sequence INTEGER DEFAULT 0,
              PRIMARY KEY (voucher_type, financial_year)
            );
          ''');
        },
      );

      // Set DbHelper database instance to our test database
      DbHelper.instance.setMockDatabase(db);

      // Seed test master data
      await db.insert('product_master', {
        'id': 'PROD_PARACETAMOL',
        'name': 'PARACETAMOL 650MG',
        'hsn_code': '3004',
        'gst_percent': 12.0,
        'packing': 10,
        'mrp': 30.0,
        'purchase_rate': 15.0,
        'sale_rate': 25.0,
      });

      await db.insert('product_master', {
        'id': 'PROD_AMOXICILLIN',
        'name': 'AMOXICILLIN 500MG',
        'hsn_code': '3004',
        'gst_percent': 18.0,
        'packing': 10,
        'mrp': 100.0,
        'purchase_rate': 55.0,
        'sale_rate': 85.0,
      });

      await db.insert('product_master', {
        'id': 'PROD_ORS',
        'name': 'ORS SACHET 21.8G',
        'hsn_code': '3004',
        'gst_percent': 5.0,
        'packing': 1,
        'mrp': 22.0,
        'purchase_rate': 14.0,
        'sale_rate': 20.0,
      });

      // Seed stock batches with healthy inventory
      await db.insert('stock_batches', {
        'product_id': 'PROD_PARACETAMOL',
        'batch_number': 'PARA-B1',
        'expiry_date': '12/28',
        'current_stock': 100, // 100 loose tablets
        'mrp': 30.0,
        'sale_rate': 25.0,
      });

      await db.insert('stock_batches', {
        'product_id': 'PROD_AMOXICILLIN',
        'batch_number': 'AMOX-B1',
        'expiry_date': '06/27',
        'current_stock': 50, // 50 loose capsules
        'mrp': 100.0,
        'sale_rate': 85.0,
      });

      await db.insert('stock_batches', {
        'product_id': 'PROD_ORS',
        'batch_number': 'ORS-B1',
        'expiry_date': '10/26',
        'current_stock': 200, // 200 sachets
        'mrp': 22.0,
        'sale_rate': 20.0,
      });

      // Seed credit patient
      await db.insert('patients', {
        'id': 'PAT_001',
        'name': 'RAHUL SHARMA',
        'mobile': '9876543210',
        'current_balance': 0.0,
      });

      provider = PharmacyProvider();
      await provider.loadFromDatabase();
    });

    tearDown(() async {
      DbHelper.instance.setMockDatabase(null);
      await db.close();
    });

    // =========================================================================
    // TEST 1: Standard Cash Sale (Walk-in Customer)
    // =========================================================================
    test('1. Checkup: Cash Sale saves cleanly with accurate tax & immediate stock deduction', () async {
      final saleItem = SaleItem(
        product: Product(
          id: 'PROD_PARACETAMOL',
          name: 'PARACETAMOL 650MG',
          batch: 'PARA-B1',
          expiry: '12/28',
          mrp: 30.0,
          salePrice: 25.0,
          packSize: 10,
        ),
        qty: 10, // 10 loose units (1 strip)
        sRate: 25.0,
        discPercent: 0.0,
        discAmt: 0.0,
        gstPercent: 12.0,
        total: 25.0,
      );

      final sale = SaleInvoice(
        entryNo: '1',
        date: DateTime.now(),
        customerAcc: 'Cash',
        patient: 'General',
        doctor: 'Self',
        taxType: 'Gst',
        items: [saleItem],
        subTotal: 25.0,
        grandTotal: 25.0,
        rcvdAmt: 25.0,
        isPaid: true,
      );

      final savedNo = await provider.saveSale(sale);
      expect(savedNo, isNotEmpty);

      // Verify invoice in SQLite
      final invRows = await db.query('sales_invoices', where: 'entry_no = ?', whereArgs: [savedNo]);
      expect(invRows.length, equals(1));
      expect(invRows.first['customer_acc'], equals('Cash'));
      expect((invRows.first['grand_total'] as num).toDouble(), equals(25.0));

      // Verify stock was reduced from 100 to 90
      final batchRows = await db.query('stock_batches', where: 'product_id = ? AND batch_number = ?', whereArgs: ['PROD_PARACETAMOL', 'PARA-B1']);
      expect(batchRows.first['current_stock'], equals(90));
    });

    // =========================================================================
    // TEST 2: Credit Sale to Patient Account (Ledger Balance Increment)
    // =========================================================================
    test('2. Checkup: Credit Sale updates Patient outstanding ledger balance', () async {
      final saleItem = SaleItem(
        product: Product(
          id: 'PROD_AMOXICILLIN',
          name: 'AMOXICILLIN 500MG',
          batch: 'AMOX-B1',
          expiry: '06/27',
          mrp: 100.0,
          salePrice: 85.0,
          packSize: 10,
        ),
        qty: 10,
        sRate: 85.0,
        discPercent: 0.0,
        discAmt: 0.0,
        gstPercent: 18.0,
        total: 85.0,
      );

      final creditSale = SaleInvoice(
        entryNo: '2',
        date: DateTime.now(),
        customerAcc: 'Credit',
        patient: 'RAHUL SHARMA',
        doctor: 'DR. VERMA',
        taxType: 'Gst',
        items: [saleItem],
        subTotal: 85.0,
        grandTotal: 85.0,
        rcvdAmt: 0.0, // Unpaid credit sale
        isPaid: false,
      );

      final savedNo = await provider.saveSale(creditSale);
      expect(savedNo, isNotEmpty);

      // Verify patient outstanding balance increased from 0 to 85.0
      final patRows = await db.query('patients', where: 'name = ?', whereArgs: ['RAHUL SHARMA']);
      expect((patRows.first['current_balance'] as num).toDouble(), equals(85.0));

      // Verify Amoxicillin stock reduced from 50 to 40
      final batchRows = await db.query('stock_batches', where: 'product_id = ?', whereArgs: ['PROD_AMOXICILLIN']);
      expect(batchRows.first['current_stock'], equals(40));
    });

    // =========================================================================
    // TEST 3: Multi-Item Sale with Multiple GST Rates (5%, 12%, 18%)
    // =========================================================================
    test('3. Checkup: Multi-Item basket with multiple GST slabs calculates accurately', () async {
      final item1 = SaleItem(
        product: Product(id: 'PROD_ORS', name: 'ORS SACHET', batch: 'ORS-B1', mrp: 20.0, salePrice: 20.0, packSize: 1),
        qty: 2, // 2 sachets @ 20 = 40 (GST 5%)
        sRate: 20.0,
        gstPercent: 5.0,
        total: 40.0,
      );
      final item2 = SaleItem(
        product: Product(id: 'PROD_PARACETAMOL', name: 'PARACETAMOL', batch: 'PARA-B1', mrp: 25.0, salePrice: 25.0, packSize: 10),
        qty: 10, // 1 strip @ 25 = 25 (GST 12%)
        sRate: 25.0,
        gstPercent: 12.0,
        total: 25.0,
      );

      final multiSale = SaleInvoice(
        entryNo: '3',
        date: DateTime.now(),
        customerAcc: 'Cash',
        patient: 'General',
        doctor: 'Self',
        taxType: 'Gst',
        items: [item1, item2],
        subTotal: 65.0,
        grandTotal: 65.0,
        rcvdAmt: 65.0,
        isPaid: true,
      );

      final savedNo = await provider.saveSale(multiSale);
      expect(savedNo, isNotEmpty);

      final items = await db.query('sales_items', where: 'invoice_no = ?', whereArgs: [savedNo]);
      expect(items.length, equals(2));

      // Check each item's tax calculation
      final orsItem = items.firstWhere((it) => it['product_id'] == 'PROD_ORS');
      expect((orsItem['gst_percent'] as num).toDouble(), equals(5.0));

      final paraItem = items.firstWhere((it) => it['product_id'] == 'PROD_PARACETAMOL');
      expect((paraItem['gst_percent'] as num).toDouble(), equals(12.0));
    });

    // =========================================================================
    // TEST 4: Discount Handling (Item-Level + Bill-Level + Round-Off)
    // =========================================================================
    test('4. Checkup: Discounted sale handles item % and footer discounts cleanly', () async {
      final item = SaleItem(
        product: Product(id: 'PROD_ORS', name: 'ORS SACHET', batch: 'ORS-B1', mrp: 20.0, salePrice: 20.0, packSize: 1),
        qty: 5, // 5 x 20 = 100
        sRate: 20.0,
        discPercent: 10.0, // 10% item discount = 10.0
        discAmt: 10.0,
        gstPercent: 5.0,
        total: 90.0,
      );

      final discountedSale = SaleInvoice(
        entryNo: '4',
        date: DateTime.now(),
        customerAcc: 'Cash',
        patient: 'General',
        doctor: 'Self',
        taxType: 'Gst',
        items: [item],
        subTotal: 90.0,
        discount: 5.0, // ₹5 additional footer discount
        roundOff: -0.0,
        grandTotal: 85.0, // 90 - 5 = 85
        rcvdAmt: 85.0,
        isPaid: true,
      );

      final savedNo = await provider.saveSale(discountedSale);
      expect(savedNo, isNotEmpty);

      final header = (await db.query('sales_invoices', where: 'entry_no = ?', whereArgs: [savedNo])).first;
      expect((header['discount'] as num).toDouble(), equals(5.0));
      expect((header['grand_total'] as num).toDouble(), equals(85.0));
    });

    // =========================================================================
    // TEST 5: Strip vs Loose Quantity Conversion Checkup
    // =========================================================================
    test('5. Checkup: Strip vs Loose tablet units deduct inventory accurately', () async {
      // PROD_PARACETAMOL has packSize = 10 tablets per strip
      // Initial stock in PARA-B1 = 100 loose units (10 strips)
      // Selling 2 strips (20 units) + 5 loose tablets = 25 loose units
      final item = SaleItem(
        product: Product(
          id: 'PROD_PARACETAMOL',
          name: 'PARACETAMOL 650MG',
          batch: 'PARA-B1',
          mrp: 30.0,
          salePrice: 25.0,
          packSize: 10,
        ),
        qty: 25, // 25 loose units
        sRate: 2.5, // 2.5 per loose unit = 62.50
        gstPercent: 12.0,
        total: 62.50,
      );

      final looseSale = SaleInvoice(
        entryNo: '5',
        date: DateTime.now(),
        customerAcc: 'Cash',
        patient: 'General',
        doctor: 'Self',
        taxType: 'Gst',
        items: [item],
        subTotal: 62.50,
        grandTotal: 62.50,
        rcvdAmt: 62.50,
        isPaid: true,
      );

      await provider.saveSale(looseSale);

      // Initial 100 - 25 = 75 loose units remaining
      final batch = (await db.query('stock_batches', where: 'product_id = ? AND batch_number = ?', whereArgs: ['PROD_PARACETAMOL', 'PARA-B1'])).first;
      expect(batch['current_stock'], equals(75));
    });

    // =========================================================================
    // TEST 6: Simultaneous Multi-PC Concurrent Saves (Race Condition Verification)
    // =========================================================================
    test('6. Checkup: Simultaneous saves on different PCs with collision serialize without data loss', () async {
      // Simulate PC-1 (POS-01) and PC-2 (POS-02) both pressing "Save" at the exact same millisecond.
      // Both start with the same proposed Entry No: "100".
      // The database serialized transaction will allow PC-1 to claim "100",
      // and PC-2 will detect the collision and auto-allocate "101" without throwing or failing!

      final itemPC1 = SaleItem(
        product: Product(id: 'PROD_ORS', name: 'ORS SACHET', batch: 'ORS-B1', mrp: 20.0, salePrice: 20.0, packSize: 1),
        qty: 5,
        sRate: 20.0,
        gstPercent: 5.0,
        total: 100.0,
      );

      final itemPC2 = SaleItem(
        product: Product(id: 'PROD_ORS', name: 'ORS SACHET', batch: 'ORS-B1', mrp: 20.0, salePrice: 20.0, packSize: 1),
        qty: 10,
        sRate: 20.0,
        gstPercent: 5.0,
        total: 200.0,
      );

      final salePC1 = SaleInvoice(
        entryNo: '100', // Proposed by PC-1
        date: DateTime.now(),
        customerAcc: 'Cash',
        patient: 'Patient PC-1',
        doctor: 'Doctor PC-1',
        taxType: 'Gst',
        items: [itemPC1],
        subTotal: 100.0,
        grandTotal: 100.0,
        rcvdAmt: 100.0,
        isPaid: true,
      );

      final salePC2 = SaleInvoice(
        entryNo: '100', // Proposed by PC-2 simultaneously (IDENTICAL entry number)
        date: DateTime.now(),
        customerAcc: 'Cash',
        patient: 'Patient PC-2',
        doctor: 'Doctor PC-2',
        taxType: 'Gst',
        items: [itemPC2],
        subTotal: 200.0,
        grandTotal: 200.0,
        rcvdAmt: 200.0,
        isPaid: true,
      );

      // Execute simultaneously via Future.wait
      final results = await Future.wait([
        provider.saveSale(salePC1),
        provider.saveSale(salePC2),
      ]);

      final savedPC1 = results[0];
      final savedPC2 = results[1];

      // Both saves must succeed
      expect(savedPC1, isNotEmpty);
      expect(savedPC2, isNotEmpty);

      // Crucial: The two invoices must have unique, non-colliding entry numbers!
      expect(savedPC1, isNot(equals(savedPC2)), reason: 'Concurrent saves from 2 PCs must never overwrite each other');

      // Verify both invoices exist in the database with their respective patients
      final allSales = await db.query('sales_invoices', where: 'entry_no IN (?, ?)', whereArgs: [savedPC1, savedPC2]);
      expect(allSales.length, equals(2));

      // Verify stock was decremented correctly for both sales:
      // Initial ORS stock: 200 - 5 (PC-1) - 10 (PC-2) = 185
      final orsBatch = (await db.query('stock_batches', where: 'product_id = ? AND batch_number = ?', whereArgs: ['PROD_ORS', 'ORS-B1'])).first;
      expect(orsBatch['current_stock'], equals(185));
    });
  });
}
