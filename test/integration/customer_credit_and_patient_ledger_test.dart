import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmacy_app/database/db_helper.dart';
import 'package:pharmacy_app/services/customer_ledger_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Pillar 2: Customer Credit / Udhar Ledger (Khata) Tests', () {
    late Database db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});

      db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE patients (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              mobile TEXT,
              address TEXT,
              current_balance REAL DEFAULT 0.0,
              is_deleted INTEGER DEFAULT 0
            );
          ''');

          await db.execute('''
            CREATE TABLE sales_invoices (
              entry_no TEXT PRIMARY KEY,
              date TEXT NOT NULL,
              customer_acc TEXT,
              patient TEXT,
              mobile TEXT,
              doctor TEXT,
              grand_total REAL,
              rcvd_amt REAL DEFAULT 0.0,
              is_paid INTEGER DEFAULT 1,
              financial_year TEXT,
              is_deleted INTEGER DEFAULT 0
            );
          ''');

          await db.execute('''
            CREATE TABLE sales_return_invoices (
              entry_no TEXT PRIMARY KEY,
              date TEXT NOT NULL,
              patient TEXT,
              original_invoice_no TEXT,
              grand_total REAL,
              is_deleted INTEGER DEFAULT 0
            );
          ''');

          await db.execute('''
            CREATE TABLE patient_payments (
              id TEXT PRIMARY KEY,
              patient_name TEXT,
              date TEXT,
              amount REAL,
              invoice_no TEXT,
              payment_method TEXT,
              remarks TEXT
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

    test('1. Customer Balances: Live SQLite balance queries without cache drift', () async {
      const patient = "Rahul Sharma";

      await db.insert('patients', {
        'id': 'PAT_101',
        'name': patient,
        'mobile': '9876543210',
        'current_balance': 450.0,
      });

      final balances = await CustomerLedgerService.instance.fetchAllPatientBalances();
      expect(balances[patient], equals(450.0));

      final singleBal = await CustomerLedgerService.instance.fetchPatientBalance(patient);
      expect(singleBal, equals(450.0));
    });

    test('2. Customer Ledger: Unified statement of Sales, Immediate settlements, Returns and Payments', () async {
      const patient = "Amit Verma";
      final baseDate = DateTime(2026, 11, 1);

      await db.insert('patients', {
        'id': 'PAT_102',
        'name': patient,
        'mobile': '9988776655',
        'current_balance': 0.0,
      });

      // Event 1: Cash sale of ₹300 on Nov 1 (Fully Paid)
      await db.insert('sales_invoices', {
        'entry_no': 'SALE-001',
        'date': baseDate.toIso8601String(),
        'customer_acc': 'Cash',
        'patient': patient,
        'grand_total': 300.0,
        'rcvd_amt': 300.0,
        'is_paid': 1,
      });

      // Event 2: Credit sale of ₹1,200 on Nov 5 with ₹200 advance payment
      await db.insert('sales_invoices', {
        'entry_no': 'SALE-002',
        'date': baseDate.add(const Duration(days: 4)).toIso8601String(),
        'customer_acc': 'Credit',
        'patient': patient,
        'grand_total': 1200.0,
        'rcvd_amt': 200.0,
        'is_paid': 0,
      });

      // Event 3: Patient payment receipt of ₹500 on Nov 10
      await db.insert('patient_payments', {
        'id': 'RCPT-101',
        'patient_name': patient,
        'date': baseDate.add(const Duration(days: 9)).toIso8601String(),
        'amount': 500.0,
        'invoice_no': 'SALE-002',
        'payment_method': 'UPI',
        'remarks': 'Part payment via GPay',
      });

      // Event 4: Sales return of ₹100 on Nov 15
      await db.insert('sales_return_invoices', {
        'entry_no': 'SRET-001',
        'date': baseDate.add(const Duration(days: 14)).toIso8601String(),
        'patient': patient,
        'original_invoice_no': 'SALE-002',
        'grand_total': 100.0,
      });

      // Fetch unified ledger
      final ledger = await CustomerLedgerService.instance.fetchPatientLedger(patient);

      // Verify transaction list:
      // SALE-001: Debit 300
      // SALE-001 Receipt: Credit 300
      // SALE-002: Debit 1200
      // SALE-002 Upfront: Credit 200
      // RCPT-101: Credit 500
      // SRET-001: Credit 100
      // Total rows = 6
      expect(ledger.length, equals(6));

      double totalDebit = 0.0;
      double totalCredit = 0.0;
      for (var row in ledger) {
        totalDebit += (row['debit'] as num).toDouble();
        totalCredit += (row['credit'] as num).toDouble();
      }

      expect(totalDebit, equals(1500.0)); // 300 + 1200
      expect(totalCredit, equals(1100.0)); // 300 (cash bill) + 200 (upfront) + 500 (rcpt) + 100 (return)

      // Net Outstanding Udhar Due from customer:
      // ₹1,500.00 - ₹1,100.00 = ₹400.00!
      final double outstanding = totalDebit - totalCredit;
      expect(outstanding, equals(400.0));

      // Verify chronological ordering
      for (int i = 0; i < ledger.length - 1; i++) {
        final DateTime d1 = ledger[i]['date'] as DateTime;
        final DateTime d2 = ledger[i + 1]['date'] as DateTime;
        expect(d1.isBefore(d2) || d1.isAtSameMomentAs(d2), isTrue);
      }
    });
  });
}
