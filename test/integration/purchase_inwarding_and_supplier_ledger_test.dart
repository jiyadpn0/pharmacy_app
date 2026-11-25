import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmacy_app/database/db_helper.dart';
import 'package:pharmacy_app/services/supplier_ledger_service.dart';
import 'package:pharmacy_app/utils/tax_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Pillar 1: Purchase Inwarding & Supplier Accounts Payable Tests', () {
    late Database db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});

      db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE suppliers (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              address TEXT,
              phone TEXT,
              gst_in TEXT,
              dl_number TEXT,
              current_balance REAL DEFAULT 0.0,
              is_deleted INTEGER DEFAULT 0
            );
          ''');

          await db.execute('''
            CREATE TABLE purchase_entries (
              entry_no TEXT PRIMARY KEY,
              date TEXT NOT NULL,
              supplier_name TEXT,
              sup_inv_no TEXT,
              sup_inv_date TEXT,
              done_by TEXT,
              inv_total REAL DEFAULT 0.0,
              remarks TEXT,
              sub_total REAL DEFAULT 0.0,
              discount REAL DEFAULT 0.0,
              other_charge REAL DEFAULT 0.0,
              round_off REAL DEFAULT 0.0,
              grand_total REAL,
              payment_status INTEGER DEFAULT 0,
              payment_mode TEXT,
              payment_remarks TEXT,
              payment_date TEXT,
              paid_amount REAL DEFAULT 0.0,
              days INTEGER DEFAULT 0,
              financial_year TEXT,
              tax_type TEXT DEFAULT 'Gst',
              is_deleted INTEGER DEFAULT 0
            );
          ''');

          await db.execute('''
            CREATE TABLE purchase_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              entry_no TEXT NOT NULL,
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
              s_disc_percent REAL,
              s_rate REAL,
              l_cost REAL
            );
          ''');

          await db.execute('''
            CREATE TABLE supplier_payments (
              id TEXT PRIMARY KEY,
              supplier_name TEXT,
              date TEXT,
              amount REAL,
              invoice_no TEXT,
              payment_method TEXT,
              remarks TEXT
            );
          ''');

          await db.execute('''
            CREATE TABLE supplier_credit_notes (
              id TEXT PRIMARY KEY,
              supplier_name TEXT,
              date TEXT,
              amount REAL,
              invoice_no TEXT,
              remarks TEXT
            );
          ''');

          await db.execute('''
            CREATE TABLE purchase_return_entries (
              entry_no TEXT PRIMARY KEY,
              date TEXT NOT NULL,
              supplier_name TEXT,
              original_purchase_no TEXT,
              done_by TEXT,
              gst_mode INTEGER DEFAULT 1,
              grand_total REAL,
              financial_year TEXT,
              sup_inv_no TEXT,
              is_deleted INTEGER DEFAULT 0
            );
          ''');
        },
      );

      DbHelper.instance.setMockDatabase(db);
    });

    tearDown(() async {
      DbHelper.instance.setMockDatabase(null);
      await db.close();
    });

    test('1. Scheme Calculation: 10 + 2 Free with 5% Trade Discount & 12% GST yields diluted Landed Cost', () {
      // Billed: 10 strips, Free: 2 strips (Total 12 strips)
      // Rate: ₹100, Trade Discount: 5%, GST: 12%
      // Gross = 10 * 100 = 1000
      // Disc = 50 -> Taxable = 950
      // GST = 950 * 0.12 = 114
      // Total Invoice Line = 1064
      // Landed Cost per Pack = 1064 / 12 = 88.666... ~ ₹88.67
      final landedCost = TaxCalculator.calculateLandedCostPerPack(
        purchaseRate: 100.0,
        qty: 10,
        fQty: 2,
        discPercent: 5.0,
        gstPercent: 12.0,
      );

      expect(double.parse(landedCost.toStringAsFixed(2)), equals(88.67));

      // Unit Cost per tablet (pack size: 10)
      final unitCost = TaxCalculator.calculateLooseUnitCost(
        landingCostPerPack: landedCost,
        packSize: 10,
      );
      expect(unitCost, equals(8.87));
    });

    test('2. Supplier Ledger: Unified Statement of Credit Purchases, Cash Purchases, Payments & Returns', () async {
      const supplier = "Cipla Healthcare Ltd";

      // Insert Supplier Record
      await db.insert('suppliers', {
        'id': 'SUP_001',
        'name': supplier,
        'current_balance': 0.0,
      });

      final baseDate = DateTime(2026, 11, 1);

      // Event 1: Credit Purchase of ₹1,064 on Nov 1
      await db.insert('purchase_entries', {
        'entry_no': 'PUR-101',
        'date': baseDate.toIso8601String(),
        'supplier_name': supplier,
        'sup_inv_no': 'INV-9901',
        'grand_total': 1064.0,
        'inv_total': 1064.0,
        'payment_mode': 'CREDIT',
        'payment_status': 0,
        'paid_amount': 0.0,
      });

      // Event 2: Immediate Cash Purchase of ₹500 on Nov 5 (Paid on invoice)
      await db.insert('purchase_entries', {
        'entry_no': 'PUR-102',
        'date': baseDate.add(const Duration(days: 4)).toIso8601String(),
        'supplier_name': supplier,
        'sup_inv_no': 'INV-9902',
        'grand_total': 500.0,
        'inv_total': 500.0,
        'payment_mode': 'CASH',
        'payment_status': 1,
        'paid_amount': 500.0,
        'payment_date': baseDate.add(const Duration(days: 4)).toIso8601String(),
      });

      // Event 3: Voucher Payment of ₹500 against PUR-101 on Nov 10
      await db.insert('supplier_payments', {
        'id': 'PAY-201',
        'supplier_name': supplier,
        'date': baseDate.add(const Duration(days: 9)).toIso8601String(),
        'amount': 500.0,
        'invoice_no': 'INV-9901',
        'payment_method': 'NEFT/BANK',
        'remarks': 'Partial payment for INV-9901',
      });

      // Event 4: Supplier Credit Note of ₹64 on Nov 15 (Rate difference)
      await db.insert('supplier_credit_notes', {
        'id': 'CN-301',
        'supplier_name': supplier,
        'date': baseDate.add(const Duration(days: 14)).toIso8601String(),
        'amount': 64.0,
        'invoice_no': 'INV-9901',
        'remarks': 'Rate difference credit',
      });

      // Event 5: Purchase Return of ₹200 on Nov 20 (Breakage return)
      await db.insert('purchase_return_entries', {
        'entry_no': 'PRET-401',
        'date': baseDate.add(const Duration(days: 19)).toIso8601String(),
        'supplier_name': supplier,
        'sup_inv_no': 'INV-9901',
        'grand_total': 200.0,
      });

      // Fetch unified ledger
      final ledger = await SupplierLedgerService.instance.fetchSupplierLedger(supplier);

      // Verify transaction count:
      // PUR-101 (Credit 1064)
      // PUR-102 (Credit 500)
      // PUR-102 Payment (Debit 500)
      // PAY-201 (Debit 500)
      // CN-301 (Debit 64)
      // PRET-401 (Debit 200)
      // Total rows = 6
      expect(ledger.length, equals(6));

      // Calculate totals
      double totalCredit = 0.0;
      double totalDebit = 0.0;
      for (var row in ledger) {
        totalCredit += (row['credit'] as num).toDouble();
        totalDebit += (row['debit'] as num).toDouble();
      }

      expect(totalCredit, equals(1564.0)); // 1064 + 500
      expect(totalDebit, equals(1264.0));  // 500 (cash bill) + 500 (payment) + 64 (credit note) + 200 (return)

      // Outstanding Net Balance:
      // ₹1,564.00 - ₹1,264.00 = ₹300.00 Due to supplier!
      final double outstanding = totalCredit - totalDebit;
      expect(outstanding, equals(300.0));

      // Verify chronological ordering
      for (int i = 0; i < ledger.length - 1; i++) {
        final DateTime d1 = ledger[i]['date'] as DateTime;
        final DateTime d2 = ledger[i + 1]['date'] as DateTime;
        expect(d1.isBefore(d2) || d1.isAtSameMomentAs(d2), isTrue);
      }
    });
  });
}
