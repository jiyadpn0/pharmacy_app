import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmacy_app/database/db_helper.dart';
import 'package:pharmacy_app/services/gst_report_service.dart';
import 'package:pharmacy_app/utils/tax_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DbHelper.instance.setMockDatabase(db);

    // Sales schemas
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales_invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_no TEXT,
        date TEXT,
        grand_total REAL,
        sub_total REAL DEFAULT 0.0,
        tax REAL DEFAULT 0.0,
        gstin_number TEXT,
        customer_acc TEXT,
        patient TEXT,
        mobile TEXT,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_no TEXT,
        product_id INTEGER,
        extra TEXT,
        qty REAL DEFAULT 1,
        total REAL DEFAULT 0.0,
        gst_amt REAL DEFAULT 0.0,
        cgst_amt REAL DEFAULT 0.0,
        sgst_amt REAL DEFAULT 0.0,
        igst_amt REAL DEFAULT 0.0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_master (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        hsn_code TEXT
      )
    ''');

    // Purchase schemas
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_no TEXT,
        date TEXT,
        tax_type TEXT,
        grand_total REAL,
        supplier_name TEXT,
        supplier_gstin TEXT,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_no TEXT,
        product_id INTEGER,
        net REAL DEFAULT 0.0,
        gst_amt REAL DEFAULT 0.0,
        total REAL DEFAULT 0.0
      )
    ''');

    // Purchase Return schemas
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_return_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_no TEXT,
        date TEXT,
        grand_total REAL,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_return_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_no TEXT,
        total REAL DEFAULT 0.0,
        gst_percent REAL DEFAULT 12.0
      )
    ''');
  });

  tearDown(() async {
    DbHelper.instance.setMockDatabase(null);
    await db.close();
  });

  group('Pillar 7: GST Statutory Reporting & HSN Auditor Tests', () {
    test('TaxCalculator.isValidGstin accurately validates Indian GSTIN formats', () {
      expect(TaxCalculator.isValidGstin('32AAAAA0000A1Z5'), isTrue);
      expect(TaxCalculator.isValidGstin('29ABCDE1234F2Z5'), isTrue);
      expect(TaxCalculator.isValidGstin('07AAAAA0000A1Z5'), isTrue);

      // Invalid GSTINs
      expect(TaxCalculator.isValidGstin(null), isFalse);
      expect(TaxCalculator.isValidGstin(''), isFalse);
      expect(TaxCalculator.isValidGstin('URD'), isFalse);
      expect(TaxCalculator.isValidGstin('9876543210'), isFalse); // Mobile number
      expect(TaxCalculator.isValidGstin('32AAAAA0000A1Z'), isFalse); // 14 chars
      expect(TaxCalculator.isValidGstin('32AAAAA0000A1Z55'), isFalse); // 16 chars
      expect(TaxCalculator.isValidGstin('32AAAAA0000A1!5'), isFalse); // Special character
    });

    test('GstReportService.fetchHsnSummary aggregates outward supplies by HSN code (Table 12)', () async {
      // 1. Insert product master
      await db.insert('product_master', {'id': 101, 'name': 'PARACETAMOL 650', 'hsn_code': '3004'});
      await db.insert('product_master', {'id': 102, 'name': 'SURGICAL GAUZE', 'hsn_code': '3005'});

      const testDate = '2026-03-15';
      await db.insert('sales_invoices', {
        'entry_no': 'INV-001',
        'date': testDate,
        'grand_total': 1120.0,
        'is_deleted': 0,
      });

      // 2 items under HSN 3004
      await db.insert('sales_items', {
        'invoice_no': 'INV-001',
        'product_id': 101,
        'extra': '3004',
        'qty': 10,
        'total': 112.0,
        'gst_amt': 12.0,
        'cgst_amt': 6.0,
        'sgst_amt': 6.0,
        'igst_amt': 0.0,
      });

      await db.insert('sales_items', {
        'invoice_no': 'INV-001',
        'product_id': 101,
        'extra': '3004',
        'qty': 20,
        'total': 224.0,
        'gst_amt': 24.0,
        'cgst_amt': 12.0,
        'sgst_amt': 12.0,
        'igst_amt': 0.0,
      });

      // 1 item under HSN 3005
      await db.insert('sales_items', {
        'invoice_no': 'INV-001',
        'product_id': 102,
        'extra': '3005',
        'qty': 5,
        'total': 560.0,
        'gst_amt': 60.0,
        'cgst_amt': 30.0,
        'sgst_amt': 30.0,
        'igst_amt': 0.0,
      });

      final hsnSummary = await GstReportService.instance.fetchHsnSummary(
        DateTime.parse('2026-03-01'),
        DateTime.parse('2026-03-31'),
      );

      expect(hsnSummary.length, equals(2));

      // Sorted by taxable_value DESC (3005 has 500 taxable, 3004 has 300 taxable)
      final hsn3005 = hsnSummary.firstWhere((h) => h.hsnCode == '3005');
      expect(hsn3005.totalQty, equals(5.0));
      expect(hsn3005.totalValue, equals(560.0));
      expect(hsn3005.taxableValue, equals(500.0));
      expect(hsn3005.cgstAmount, equals(30.0));
      expect(hsn3005.sgstAmount, equals(30.0));
      expect(hsn3005.totalTax, equals(60.0));

      final hsn3004 = hsnSummary.firstWhere((h) => h.hsnCode == '3004');
      expect(hsn3004.totalQty, equals(30.0)); // 10 + 20
      expect(hsn3004.totalValue, equals(336.0)); // 112 + 224
      expect(hsn3004.taxableValue, equals(300.0)); // 100 + 200
      expect(hsn3004.cgstAmount, equals(18.0)); // 6 + 12
      expect(hsn3004.sgstAmount, equals(18.0)); // 6 + 12
      expect(hsn3004.totalTax, equals(36.0));
    });

    test('GstReportService.computeGstr3bSummary computes Table 3.1, Table 4 ITC and Table 5 Net Payable', () async {
      const txDate = '2026-03-10';

      // 1. Sales: Outward Supplies -> Taxable ₹10,000, CGST ₹600, SGST ₹600
      await db.insert('sales_invoices', {
        'entry_no': 'INV-101',
        'date': txDate,
        'grand_total': 11200.0,
        'is_deleted': 0,
      });
      await db.insert('sales_items', {
        'invoice_no': 'INV-101',
        'product_id': 1,
        'qty': 100,
        'total': 11200.0,
        'gst_amt': 1200.0,
        'cgst_amt': 600.0,
        'sgst_amt': 600.0,
        'igst_amt': 0.0,
      });

      // 2. Purchases: Inward Supplies eligible for ITC -> Taxable ₹8,000, Total GST ₹800 (CGST ₹400, SGST ₹400)
      await db.insert('purchase_entries', {
        'entry_no': 'PUR-201',
        'date': txDate,
        'supplier_name': 'MEDICHEM DISTRIBUTORS',
        'grand_total': 8800.0,
        'is_deleted': 0,
      });
      await db.insert('purchase_items', {
        'entry_no': 'PUR-201',
        'product_id': 1,
        'net': 8000.0,
        'gst_amt': 800.0,
        'total': 8800.0,
      });

      // 3. Purchase Returns / Debit Notes: ITC Reversal -> Total ₹1,120 at 12% GST (GST component ₹120 -> CGST ₹60, SGST ₹60)
      await db.insert('purchase_return_entries', {
        'entry_no': 'PR-301',
        'date': txDate,
        'grand_total': 1120.0,
        'is_deleted': 0,
      });
      await db.insert('purchase_return_items', {
        'entry_no': 'PR-301',
        'total': 1120.0,
        'gst_percent': 12.0,
      });

      final summary = await GstReportService.instance.computeGstr3bSummary(
        DateTime.parse('2026-03-01'),
        DateTime.parse('2026-03-31'),
      );

      // Table 3.1 Outward
      expect(summary.outwardTaxable, equals(10000.0));
      expect(summary.outwardCgst, equals(600.0));
      expect(summary.outwardSgst, equals(600.0));
      expect(summary.outwardTotalTax, equals(1200.0));

      // Table 4 Eligible ITC
      expect(summary.itcTaxable, equals(8000.0));
      expect(summary.itcCgst, equals(400.0));
      expect(summary.itcSgst, equals(400.0));
      expect(summary.itcTotalTax, equals(800.0));

      // Table 4(B) ITC Reversals (₹1120 * 12 / 112 = ₹120 total gst -> 60 CGST, 60 SGST)
      expect(summary.itcReversalsCgst, closeTo(60.0, 0.01));
      expect(summary.itcReversalsSgst, closeTo(60.0, 0.01));

      // Table 4(C) Net Available ITC (400 - 60 = 340)
      expect(summary.netItcCgst, closeTo(340.0, 0.01));
      expect(summary.netItcSgst, closeTo(340.0, 0.01));

      // Table 5 Net Tax Payable in Cash
      // CGST Payable = 600 - 340 = 260
      // SGST Payable = 600 - 340 = 260
      // Total Net Payable = 260 + 260 = 520
      expect(summary.payableCgst, closeTo(260.0, 0.01));
      expect(summary.payableSgst, closeTo(260.0, 0.01));
      expect(summary.totalNetPayable, closeTo(520.0, 0.01));
    });

    test('GSTR-3B handles zero or excess ITC gracefully without negative liabilities', () async {
      const txDate = '2026-03-20';

      // Outward ₹100 CGST / ₹100 SGST
      await db.insert('sales_invoices', {
        'entry_no': 'INV-301',
        'date': txDate,
        'grand_total': 2240.0,
        'is_deleted': 0,
      });
      await db.insert('sales_items', {
        'invoice_no': 'INV-301',
        'product_id': 1,
        'qty': 10,
        'total': 2240.0,
        'gst_amt': 200.0,
        'cgst_amt': 100.0,
        'sgst_amt': 100.0,
        'igst_amt': 0.0,
      });

      // Inward with MORE ITC than sales (₹500 CGST / ₹500 SGST)
      await db.insert('purchase_entries', {
        'entry_no': 'PUR-401',
        'date': txDate,
        'supplier_name': 'WHOLESALE PHARMA',
        'grand_total': 11000.0,
        'is_deleted': 0,
      });
      await db.insert('purchase_items', {
        'entry_no': 'PUR-401',
        'product_id': 1,
        'net': 10000.0,
        'gst_amt': 1000.0,
        'total': 11000.0,
      });

      final summary = await GstReportService.instance.computeGstr3bSummary(
        DateTime.parse('2026-03-01'),
        DateTime.parse('2026-03-31'),
      );

      // Payable must never be negative
      expect(summary.payableCgst, equals(0.0));
      expect(summary.payableSgst, equals(0.0));
      expect(summary.totalNetPayable, equals(0.0));
    });
  });
}
