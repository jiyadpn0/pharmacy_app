import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pharmacy_app/database/db_helper.dart';
import 'package:pharmacy_app/services/day_closing_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    DbHelper.instance.setMockDatabase(db);

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales_invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_no TEXT,
        date TEXT,
        payment_mode TEXT,
        grand_total REAL,
        sub_total REAL DEFAULT 0.0,
        tax REAL DEFAULT 0.0,
        terminal_id TEXT,
        done_by TEXT,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_no TEXT,
        cgst_amt REAL DEFAULT 0.0,
        sgst_amt REAL DEFAULT 0.0,
        gst_amt REAL DEFAULT 0.0,
        profit REAL DEFAULT 0.0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales_return_invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_no TEXT,
        date TEXT,
        payment_mode TEXT,
        grand_total REAL,
        is_deleted INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS patient_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT,
        payment_method TEXT,
        amount REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplier_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT,
        payment_method TEXT,
        amount REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_no TEXT,
        date TEXT,
        payment_mode TEXT,
        grand_total REAL,
        is_deleted INTEGER DEFAULT 0
      )
    ''');
  });

  tearDown(() async {
    DbHelper.instance.setMockDatabase(null);
    await db.close();
  });

  test('DayClosingService computes complete cash drawer liquidity equation and records settlement', () async {
    final closingDate = DateTime.parse('2026-03-30');
    const dateStr = '2026-03-30';

    // 1. Inward Transactions:
    // Sales: Cash = 1000, UPI = 500, Card = 300, Credit = 200
    await db.insert('sales_invoices', {
      'entry_no': 'INV-001',
      'date': dateStr,
      'payment_mode': 'CASH',
      'grand_total': 1000.0,
      'terminal_id': 'POS-01',
      'done_by': 'Cashier 1',
    });
    await db.insert('sales_invoices', {
      'entry_no': 'INV-002',
      'date': dateStr,
      'payment_mode': 'UPI',
      'grand_total': 500.0,
      'terminal_id': 'POS-01',
      'done_by': 'Cashier 1',
    });
    await db.insert('sales_invoices', {
      'entry_no': 'INV-003',
      'date': dateStr,
      'payment_mode': 'CARD',
      'grand_total': 300.0,
      'terminal_id': 'POS-02',
      'done_by': 'Cashier 2',
    });
    await db.insert('sales_invoices', {
      'entry_no': 'INV-004',
      'date': dateStr,
      'payment_mode': 'CREDIT',
      'grand_total': 200.0,
      'terminal_id': 'POS-02',
      'done_by': 'Cashier 2',
    });

    // Customer Credit Cash Collection: 400
    await db.insert('patient_payments', {
      'date': dateStr,
      'payment_method': 'CASH',
      'amount': 400.0,
    });

    // 2. Outward Transactions:
    // Cash Sales Return Refund: 150
    await db.insert('sales_return_invoices', {
      'entry_no': 'RET-001',
      'date': dateStr,
      'payment_mode': 'CASH',
      'grand_total': 150.0,
    });

    // Supplier Cash Payment: 250
    await db.insert('supplier_payments', {
      'date': dateStr,
      'payment_method': 'CASH',
      'amount': 250.0,
    });

    // Cash Purchase: 200
    await db.insert('purchase_entries', {
      'entry_no': 'PUR-001',
      'date': dateStr,
      'payment_mode': 'CASH',
      'grand_total': 200.0,
    });

    // Act: Fetch Summary with Opening Float = 500.0
    final summary = await DayClosingService.instance.getDaySummary(
      closingDate,
      openingFloat: 500.0,
    );

    // Verify Sales Breakdown
    expect(summary.totalInvoices, 4);
    expect(summary.totalSales, 2000.0);
    expect(summary.cashSales, 1000.0);
    expect(summary.upiSales, 500.0);
    expect(summary.cardSales, 300.0);
    expect(summary.creditSales, 200.0);

    // Verify Inflows & Outflows
    expect(summary.openingFloat, 500.0);
    expect(summary.customerCashCollected, 400.0);
    expect(summary.cashReturns, 150.0);
    expect(summary.supplierCashPaid, 250.0);
    expect(summary.cashPurchases, 200.0);

    // Expected Drawer Cash Equation:
    // Opening (500) + Cash Sales (1000) + Khata Collections (400) - Returns (150) - Supplier (250) - Purchases (200)
    // = 1900 - 600 = 1300.0
    expect(summary.expectedCash, 1300.0);

    // Verify Terminals Breakdown
    expect(summary.terminals.length, 2);

    // Test Denominations & Closing Settlement
    final denoms = {
      500: 2, // 1000
      200: 1, // 200
      100: 1, // 100
      50: 0,
      20: 0,
      10: 0,
      1: 0,
    }; // Total counted = 1300.0

    final finalClosing = await DayClosingService.instance.recordDayClosing(
      date: closingDate,
      openingFloat: 500.0,
      countedCash: 1300.0,
      denominations: denoms,
      closedBy: 'Pharmacist John',
      notes: 'Shift balanced and reconciled without variance.',
    );

    expect(finalClosing.isClosed, isTrue);
    expect(finalClosing.countedCash, 1300.0);
    expect(finalClosing.expectedCash, 1300.0);
    expect(finalClosing.variance, 0.0);
    expect(finalClosing.closedBy, 'Pharmacist John');

    // Verify persistence in SQLite
    final reloaded = await DayClosingService.instance.getDaySummary(closingDate);
    expect(reloaded.isClosed, isTrue);
    expect(reloaded.countedCash, 1300.0);
    expect(reloaded.expectedCash, 1300.0);
    expect(reloaded.notes, 'Shift balanced and reconciled without variance.');
  });
}
