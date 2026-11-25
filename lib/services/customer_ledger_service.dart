import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';

/// CustomerLedgerService
///
/// Centralized service for customer/patient credit (Udhar / Khata) ledgers,
/// transaction statements, and live balance reconciliations.
class CustomerLedgerService {
  CustomerLedgerService._();
  static final CustomerLedgerService instance = CustomerLedgerService._();

  /// Fetches the unified, chronological ledger statement for [patientName].
  ///
  /// Combines:
  /// 1. Sales Invoices (Debit)
  /// 2. Immediate Cash/UPI/Card invoice settlements (Credit)
  /// 3. Sales Returns (Credit)
  /// 4. Direct Patient Payments / Receipts (Credit)
  Future<List<Map<String, dynamic>>> fetchPatientLedger(String patientName) async {
    final db = await DbHelper.instance.database;
    final List<Map<String, dynamic>> ledger = [];

    // 1. Sales Invoices
    try {
      final List<Map<String, dynamic>> sales = await db.query(
        'sales_invoices',
        where: 'patient = ? COLLATE NOCASE AND (is_deleted = 0 OR is_deleted IS NULL)',
        whereArgs: [patientName],
        orderBy: 'date ASC',
      );

      for (var s in sales) {
        DateTime dt = DateTime.tryParse(s['date'].toString()) ?? DateTime.now();
        double grand = (s['grand_total'] as num?)?.toDouble() ?? 0.0;
        double rcvd = (s['rcvd_amt'] as num?)?.toDouble() ?? 0.0;
        int isPaid = (s['is_paid'] as int?) ?? 0;
        String custAcc = s['customer_acc']?.toString() ?? 'Cash';

        ledger.add({
          'date': dt,
          'reference': s['entry_no']?.toString() ?? '',
          'debit': grand,
          'credit': 0.0,
          'type': 'SALE',
          'method': custAcc,
          'invoice': s['entry_no']?.toString() ?? '',
          'remarks': 'Sale Invoice #$grand',
        });

        // Immediate receipt / settlement on bill
        double autoCredit = (isPaid == 1 || custAcc == 'Cash' || custAcc == 'UPI' || custAcc == 'Card')
            ? (rcvd > 0 ? rcvd : grand)
            : rcvd;

        if (autoCredit > 0) {
          ledger.add({
            'date': dt,
            'reference': 'RCPT-${s['entry_no'] ?? ''}',
            'debit': 0.0,
            'credit': autoCredit,
            'type': 'RECEIPT',
            'method': custAcc,
            'invoice': s['entry_no']?.toString() ?? '',
            'remarks': 'Paid on Bill - $custAcc',
          });
        }
      }
    } catch (e) {
      debugPrint("CustomerLedgerService sales fetch error: $e");
    }

    // 2. Sales Returns
    try {
      final List<Map<String, dynamic>> returns = await db.query(
        'sales_return_invoices',
        where: 'patient = ? COLLATE NOCASE AND (is_deleted = 0 OR is_deleted IS NULL)',
        whereArgs: [patientName],
        orderBy: 'date ASC',
      );

      for (var sr in returns) {
        DateTime dt = DateTime.tryParse(sr['date'].toString()) ?? DateTime.now();
        ledger.add({
          'date': dt,
          'reference': sr['entry_no']?.toString() ?? '',
          'debit': 0.0,
          'credit': (sr['grand_total'] as num?)?.toDouble() ?? 0.0,
          'type': 'SALE RETURN',
          'method': '',
          'invoice': sr['original_invoice_no']?.toString() ?? '',
          'remarks': "Return against Inv ${sr['original_invoice_no'] ?? ''}",
        });
      }
    } catch (e) {
      debugPrint("CustomerLedgerService sales return fetch error: $e");
    }

    // 3. Manual Receipts / Patient Payments
    try {
      final List<Map<String, dynamic>> payments = await db.query(
        'patient_payments',
        where: 'patient_name = ? COLLATE NOCASE',
        whereArgs: [patientName],
        orderBy: 'date ASC',
      );

      for (var pay in payments) {
        DateTime dt = DateTime.tryParse(pay['date'].toString()) ?? DateTime.now();
        ledger.add({
          'date': dt,
          'reference': pay['id']?.toString() ?? '',
          'debit': 0.0,
          'credit': (pay['amount'] as num?)?.toDouble() ?? 0.0,
          'type': 'RECEIPT',
          'method': pay['payment_method']?.toString() ?? 'CASH',
          'invoice': pay['invoice_no']?.toString() ?? '',
          'remarks': pay['remarks']?.toString() ?? 'Payment Received',
        });
      }
    } catch (e) {
      debugPrint("CustomerLedgerService patient payments fetch error: $e");
    }

    // Sort chronologically
    ledger.sort((a, b) {
      DateTime da = a['date'] as DateTime;
      DateTime db = b['date'] as DateTime;
      return da.compareTo(db);
    });

    return ledger;
  }

  /// Fetches live balances of all patients from the `patients` table.
  Future<Map<String, double>> fetchAllPatientBalances() async {
    final db = await DbHelper.instance.database;
    final Map<String, double> balances = {};
    try {
      final List<Map<String, dynamic>> rows = await db.query(
        'patients',
        columns: ['name', 'current_balance'],
        where: 'is_deleted = 0 OR is_deleted IS NULL',
      );
      for (var row in rows) {
        final name = row['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) {
          balances[name] = (row['current_balance'] as num?)?.toDouble() ?? 0.0;
        }
      }
    } catch (e) {
      debugPrint("CustomerLedgerService fetchAllPatientBalances error: $e");
    }
    return balances;
  }

  /// Fetches live balance for a single patient from the `patients` table.
  Future<double> fetchPatientBalance(String patientName) async {
    final db = await DbHelper.instance.database;
    try {
      final List<Map<String, dynamic>> rows = await db.query(
        'patients',
        columns: ['current_balance'],
        where: 'name = ? COLLATE NOCASE AND (is_deleted = 0 OR is_deleted IS NULL)',
        whereArgs: [patientName.trim()],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return (rows.first['current_balance'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (e) {
      debugPrint("CustomerLedgerService fetchPatientBalance error: $e");
    }
    return 0.0;
  }
}
