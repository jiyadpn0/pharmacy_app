import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import 'backup_service.dart';
import 'daily_snapshot_service.dart';
import 'database_maintenance_service.dart';

class DayClosingSummary {
  final DateTime date;
  final int totalInvoices;
  final double totalSales;
  final double cashSales;
  final double upiSales;
  final double cardSales;
  final double creditSales;
  final double cashReturns;
  final double customerCashCollected;
  final double supplierCashPaid;
  final double cashPurchases;
  final double openingFloat;
  final double expectedCash;
  final double countedCash;
  final double variance;
  final List<Map<String, dynamic>> terminals;
  final Map<int, int> denominations;
  final bool isClosed;
  final String? closedAt;
  final String? closedBy;
  final String? backupPath;
  final String? notes;

  DayClosingSummary({
    required this.date,
    required this.totalInvoices,
    required this.totalSales,
    required this.cashSales,
    required this.upiSales,
    required this.cardSales,
    required this.creditSales,
    required this.cashReturns,
    required this.customerCashCollected,
    required this.supplierCashPaid,
    required this.cashPurchases,
    required this.openingFloat,
    required this.expectedCash,
    required this.countedCash,
    required this.variance,
    required this.terminals,
    required this.denominations,
    this.isClosed = false,
    this.closedAt,
    this.closedBy,
    this.backupPath,
    this.notes,
  });

  Map<String, dynamic> toMap() => {
        'closing_date': DateFormat('yyyy-MM-dd').format(date),
        'opening_float': openingFloat,
        'cash_sales': cashSales,
        'upi_sales': upiSales,
        'card_sales': cardSales,
        'credit_sales': creditSales,
        'total_sales': totalSales,
        'cash_returns': cashReturns,
        'customer_cash_collected': customerCashCollected,
        'supplier_cash_paid': supplierCashPaid,
        'cash_purchases': cashPurchases,
        'expected_cash': expectedCash,
        'counted_cash': countedCash,
        'variance': variance,
        'denominations_json': jsonEncode(denominations.map((k, v) => MapEntry(k.toString(), v))),
        'closed_by': closedBy ?? 'Admin',
        'closed_at': closedAt ?? DateTime.now().toIso8601String(),
        'backup_path': backupPath ?? '',
        'notes': notes ?? '',
      };
}

class DayClosingService {
  DayClosingService._();
  static final DayClosingService instance = DayClosingService._();

  Future<Database> get _db async => await DbHelper.instance.database;

  Future<void> _ensureTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS day_closing_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        closing_date TEXT UNIQUE,
        opening_float REAL DEFAULT 0.0,
        cash_sales REAL DEFAULT 0.0,
        upi_sales REAL DEFAULT 0.0,
        card_sales REAL DEFAULT 0.0,
        credit_sales REAL DEFAULT 0.0,
        total_sales REAL DEFAULT 0.0,
        cash_returns REAL DEFAULT 0.0,
        customer_cash_collected REAL DEFAULT 0.0,
        supplier_cash_paid REAL DEFAULT 0.0,
        cash_purchases REAL DEFAULT 0.0,
        expected_cash REAL DEFAULT 0.0,
        counted_cash REAL DEFAULT 0.0,
        variance REAL DEFAULT 0.0,
        denominations_json TEXT,
        closed_by TEXT,
        closed_at TEXT,
        backup_path TEXT,
        notes TEXT
      )
    ''');
  }

  /// Calculates the complete multi-source cash drawer summary for [date]
  Future<DayClosingSummary> getDaySummary(
    DateTime date, {
    double openingFloat = 0.0,
    double? customCountedCash,
    Map<int, int>? customDenominations,
  }) async {
    final db = await _db;
    await _ensureTable(db);
    final dateStr = DateFormat('yyyy-MM-dd').format(date);

    // 1. Check if an existing day closing record is already saved
    final existingRows = await db.query(
      'day_closing_records',
      where: 'closing_date = ?',
      whereArgs: [dateStr],
      limit: 1,
    );

    Map<int, int> denoms = customDenominations ?? {
      500: 0,
      200: 0,
      100: 0,
      50: 0,
      20: 0,
      10: 0,
      1: 0, // Coins
    };

    bool isAlreadyClosed = false;
    String? closedAt;
    String? closedBy;
    String? backupPath;
    String? notes;
    double savedOpeningFloat = openingFloat;
    double? savedCountedCash = customCountedCash;

    if (existingRows.isNotEmpty) {
      final ex = existingRows.first;
      isAlreadyClosed = true;
      closedAt = ex['closed_at']?.toString();
      closedBy = ex['closed_by']?.toString();
      backupPath = ex['backup_path']?.toString();
      notes = ex['notes']?.toString();
      savedOpeningFloat = (ex['opening_float'] as num?)?.toDouble() ?? openingFloat;
      if (customCountedCash == null) {
        savedCountedCash = (ex['counted_cash'] as num?)?.toDouble();
      }

      final denomsStr = ex['denominations_json']?.toString();
      if (customDenominations == null && denomsStr != null && denomsStr.isNotEmpty) {
        try {
          final decoded = jsonDecode(denomsStr) as Map<String, dynamic>;
          denoms = decoded.map((k, v) => MapEntry(int.tryParse(k) ?? 0, (v as num).toInt()));
        } catch (_) {}
      }
    }

    // 2. Query Sales Invoices
    int totalInvoices = 0;
    double totalSales = 0.0;
    double cashSales = 0.0;
    double upiSales = 0.0;
    double cardSales = 0.0;
    double creditSales = 0.0;

    try {
      final res = await db.rawQuery('''
        SELECT 
          COUNT(*) as total_invoices,
          SUM(grand_total) as total_sales,
          SUM(CASE WHEN LOWER(payment_mode) = 'cash' THEN grand_total ELSE 0 END) as cash_sales,
          SUM(CASE WHEN LOWER(payment_mode) = 'upi' OR LOWER(payment_mode) = 'online' THEN grand_total ELSE 0 END) as upi_sales,
          SUM(CASE WHEN LOWER(payment_mode) = 'card' THEN grand_total ELSE 0 END) as card_sales,
          SUM(CASE WHEN LOWER(payment_mode) = 'credit' THEN grand_total ELSE 0 END) as credit_sales
        FROM sales_invoices
        WHERE date(date) = ? AND (is_deleted = 0 OR is_deleted IS NULL)
      ''', [dateStr]);

      if (res.isNotEmpty) {
        final r = res.first;
        totalInvoices = (r['total_invoices'] as num?)?.toInt() ?? 0;
        totalSales = (r['total_sales'] as num?)?.toDouble() ?? 0.0;
        cashSales = (r['cash_sales'] as num?)?.toDouble() ?? 0.0;
        upiSales = (r['upi_sales'] as num?)?.toDouble() ?? 0.0;
        cardSales = (r['card_sales'] as num?)?.toDouble() ?? 0.0;
        creditSales = (r['credit_sales'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (e) {
      debugPrint("DayClosingService sales fetch error: $e");
    }

    // 3. Multi-terminal breakdown
    final List<Map<String, dynamic>> terminalBreakdown = [];
    try {
      final terminalRes = await db.rawQuery('''
        SELECT 
          COALESCE(NULLIF(TRIM(terminal_id), ''), 'POS-01') as terminal_id,
          COALESCE(NULLIF(TRIM(done_by), ''), 'Cashier') as staff_name,
          COUNT(*) as total_invoices,
          SUM(grand_total) as total_sales,
          SUM(CASE WHEN LOWER(payment_mode) = 'cash' THEN grand_total ELSE 0 END) as cash_sales,
          SUM(CASE WHEN LOWER(payment_mode) = 'upi' OR LOWER(payment_mode) = 'online' THEN grand_total ELSE 0 END) as upi_sales,
          SUM(CASE WHEN LOWER(payment_mode) = 'card' THEN grand_total ELSE 0 END) as card_sales,
          SUM(CASE WHEN LOWER(payment_mode) = 'credit' THEN grand_total ELSE 0 END) as credit_sales
        FROM sales_invoices
        WHERE date(date) = ? AND (is_deleted = 0 OR is_deleted IS NULL)
        GROUP BY COALESCE(NULLIF(TRIM(terminal_id), ''), 'POS-01'), COALESCE(NULLIF(TRIM(done_by), ''), 'Cashier')
        ORDER BY terminal_id ASC
      ''', [dateStr]);

      for (var r in terminalRes) {
        terminalBreakdown.add({
          'terminal_id': r['terminal_id']?.toString() ?? 'POS-01',
          'staff_name': r['staff_name']?.toString() ?? 'Cashier',
          'total_invoices': (r['total_invoices'] as num?)?.toInt() ?? 0,
          'total_sales': (r['total_sales'] as num?)?.toDouble() ?? 0.0,
          'cash_sales': (r['cash_sales'] as num?)?.toDouble() ?? 0.0,
          'upi_sales': (r['upi_sales'] as num?)?.toDouble() ?? 0.0,
          'card_sales': (r['card_sales'] as num?)?.toDouble() ?? 0.0,
          'credit_sales': (r['credit_sales'] as num?)?.toDouble() ?? 0.0,
        });
      }
    } catch (e) {
      debugPrint("DayClosingService terminal breakdown error: $e");
    }

    // 4. Sales Returns (Cash refunded to patients)
    double cashReturns = 0.0;
    try {
      final retRes = await db.rawQuery('''
        SELECT SUM(grand_total) as cash_returns
        FROM sales_return_invoices
        WHERE date(date) = ? AND (is_deleted = 0 OR is_deleted IS NULL) AND LOWER(payment_mode) = 'cash'
      ''', [dateStr]);
      if (retRes.isNotEmpty && retRes.first['cash_returns'] != null) {
        cashReturns = (retRes.first['cash_returns'] as num).toDouble();
      }
    } catch (e) {
      debugPrint("DayClosingService cash returns error: $e");
    }

    // 5. Customer Credit Collections (Patient cash payments on Khata/Udhar)
    double customerCashCollected = 0.0;
    try {
      final payRes = await db.rawQuery('''
        SELECT SUM(amount) as cash_collected
        FROM patient_payments
        WHERE date(date) = ? AND LOWER(payment_method) = 'cash'
      ''', [dateStr]);
      if (payRes.isNotEmpty && payRes.first['cash_collected'] != null) {
        customerCashCollected = (payRes.first['cash_collected'] as num).toDouble();
      }
    } catch (e) {
      debugPrint("DayClosingService customer cash collections error: $e");
    }

    // 6. Supplier Cash Payments (Voucher payments to suppliers in cash)
    double supplierCashPaid = 0.0;
    try {
      final supRes = await db.rawQuery('''
        SELECT SUM(amount) as cash_paid
        FROM supplier_payments
        WHERE date(date) = ? AND LOWER(payment_method) = 'cash'
      ''', [dateStr]);
      if (supRes.isNotEmpty && supRes.first['cash_paid'] != null) {
        supplierCashPaid = (supRes.first['cash_paid'] as num).toDouble();
      }
    } catch (e) {
      debugPrint("DayClosingService supplier cash paid error: $e");
    }

    // 7. Cash Purchases (Goods purchased against immediate cash)
    double cashPurchases = 0.0;
    try {
      final purRes = await db.rawQuery('''
        SELECT SUM(grand_total) as cash_purchases
        FROM purchase_entries
        WHERE date(date) = ? AND (is_deleted = 0 OR is_deleted IS NULL) AND LOWER(payment_mode) = 'cash'
      ''', [dateStr]);
      if (purRes.isNotEmpty && purRes.first['cash_purchases'] != null) {
        cashPurchases = (purRes.first['cash_purchases'] as num).toDouble();
      }
    } catch (e) {
      debugPrint("DayClosingService cash purchases error: $e");
    }

    // 8. Expected Cash in Drawer Equation:
    // Expected Cash = Opening Float + Cash Sales + Customer Cash Collected - Cash Returns - Supplier Cash Paid - Cash Purchases
    final double expectedCash = savedOpeningFloat + cashSales + customerCashCollected - cashReturns - supplierCashPaid - cashPurchases;

    // Calculate counted cash from denominations if user hasn't overridden counted cash
    double denomSum = 0.0;
    denoms.forEach((denom, count) {
      denomSum += (denom * count);
    });

    final double countedCash = savedCountedCash ?? (denomSum > 0 ? denomSum : cashSales);
    final double variance = countedCash - expectedCash;

    return DayClosingSummary(
      date: date,
      totalInvoices: totalInvoices,
      totalSales: totalSales,
      cashSales: cashSales,
      upiSales: upiSales,
      cardSales: cardSales,
      creditSales: creditSales,
      cashReturns: cashReturns,
      customerCashCollected: customerCashCollected,
      supplierCashPaid: supplierCashPaid,
      cashPurchases: cashPurchases,
      openingFloat: savedOpeningFloat,
      expectedCash: expectedCash,
      countedCash: countedCash,
      variance: variance,
      terminals: terminalBreakdown,
      denominations: denoms,
      isClosed: isAlreadyClosed,
      closedAt: closedAt,
      closedBy: closedBy,
      backupPath: backupPath,
      notes: notes,
    );
  }

  /// Finalizes the day closing, creates an atomic database backup, and syncs cloud snapshot
  Future<DayClosingSummary> recordDayClosing({
    required DateTime date,
    required double openingFloat,
    required double countedCash,
    required Map<int, int> denominations,
    String closedBy = 'Admin',
    String notes = '',
  }) async {
    final db = await _db;
    await _ensureTable(db);

    // Compute live summary numbers
    final summary = await getDaySummary(
      date,
      openingFloat: openingFloat,
      customCountedCash: countedCash,
      customDenominations: denominations,
    );

    // 1. Perform WAL compaction, query planner optimization, and integrity check
    try {
      await DatabaseMaintenanceService.instance.performMaintenance(truncateWal: true);
    } catch (e) {
      debugPrint("Day closing database maintenance warning: $e");
    }

    // 2. Create atomic zero-loss database backup
    String? backupPath;
    try {
      backupPath = await BackupService.createDatabaseBackup();
    } catch (e) {
      debugPrint("Day closing backup creation warning: $e");
    }

    final finalSummary = DayClosingSummary(
      date: date,
      totalInvoices: summary.totalInvoices,
      totalSales: summary.totalSales,
      cashSales: summary.cashSales,
      upiSales: summary.upiSales,
      cardSales: summary.cardSales,
      creditSales: summary.creditSales,
      cashReturns: summary.cashReturns,
      customerCashCollected: summary.customerCashCollected,
      supplierCashPaid: summary.supplierCashPaid,
      cashPurchases: summary.cashPurchases,
      openingFloat: openingFloat,
      expectedCash: summary.expectedCash,
      countedCash: countedCash,
      variance: countedCash - summary.expectedCash,
      terminals: summary.terminals,
      denominations: denominations,
      isClosed: true,
      closedAt: DateTime.now().toIso8601String(),
      closedBy: closedBy,
      backupPath: backupPath,
      notes: notes,
    );

    // 2. Persist to day_closing_records
    await db.insert(
      'day_closing_records',
      finalSummary.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // 3. Update cloud daily snapshot asynchronously
    unawaited(() async {
      try {
        await DailySnapshotService.instance.generateAndPushSnapshot(date: date);
      } catch (e) {
        debugPrint("DailySnapshotService background push error: $e");
      }
    }());

    return finalSummary;
  }
}
