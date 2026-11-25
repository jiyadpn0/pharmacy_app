import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';

/// SupplierLedgerService
///
/// Centralized service for supplier accounts payable (AP) ledgers,
/// transaction statements, and live balance reconciliations.
class SupplierLedgerService {
  SupplierLedgerService._();
  static final SupplierLedgerService instance = SupplierLedgerService._();

  /// Fetches the unified, chronological ledger statement for [supplierName].
  ///
  /// Combines:
  /// 1. Purchase Invoices (Credit)
  /// 2. Immediate Cash/Bank invoice settlements (Debit)
  /// 3. Direct Supplier Payments / AP Vouchers (Debit)
  /// 4. Supplier Credit Notes (Debit)
  /// 5. Purchase Returns / Debit Notes (Debit)
  Future<List<Map<String, dynamic>>> fetchSupplierLedger(String supplierName) async {
    final db = await DbHelper.instance.database;
    final List<Map<String, dynamic>> ledger = [];

    // 1. Purchases (Inward Invoices)
    try {
      final List<Map<String, dynamic>> purchases = await db.query(
        'purchase_entries',
        where: 'supplier_name = ? COLLATE NOCASE AND (is_deleted = 0 OR is_deleted IS NULL)',
        whereArgs: [supplierName],
        orderBy: 'date ASC',
      );

      for (var p in purchases) {
        DateTime dt = DateTime.tryParse(p['date'].toString()) ?? DateTime.now();
        double totalAmt = (p['grand_total'] as num?)?.toDouble() ?? (p['inv_total'] as num?)?.toDouble() ?? 0.0;
        ledger.add({
          'date': dt,
          'reference': p['entry_no']?.toString() ?? '',
          'sup_inv_no': p['sup_inv_no']?.toString() ?? '',
          'debit': 0.0,
          'credit': totalAmt,
          'type': 'PURCHASE',
          'method': p['payment_mode']?.toString() ?? 'CREDIT',
          'remarks': p['remarks']?.toString() ?? '',
        });

        // Immediate invoice settlement (Cash purchase or upfront payment)
        double paidAmt = (p['paid_amount'] as num?)?.toDouble() ?? 0.0;
        int paymentStatus = (p['payment_status'] as int?) ?? 0;
        if (paymentStatus == 1 && paidAmt == 0.0) {
          paidAmt = totalAmt;
        }
        if (paidAmt > 0) {
          DateTime payDt = p['payment_date'] != null ? (DateTime.tryParse(p['payment_date'].toString()) ?? dt) : dt;
          ledger.add({
            'date': payDt,
            'reference': 'PAY-${p['entry_no'] ?? ''}',
            'sup_inv_no': p['sup_inv_no']?.toString() ?? '',
            'debit': paidAmt,
            'credit': 0.0,
            'type': 'PAYMENT',
            'method': p['payment_mode']?.toString() ?? 'CASH',
            'remarks': (p['payment_remarks']?.toString().isNotEmpty ?? false) ? p['payment_remarks'] : 'Paid on Bill',
          });
        }
      }
    } catch (e) {
      debugPrint("SupplierLedgerService purchases fetch error: $e");
    }

    // 2. Direct Supplier Payments (Accounts Payable vouchers)
    try {
      final List<Map<String, dynamic>> payments = await db.query(
        'supplier_payments',
        where: 'supplier_name = ? COLLATE NOCASE',
        whereArgs: [supplierName],
        orderBy: 'date ASC',
      );
      for (var pay in payments) {
        DateTime dt = DateTime.tryParse(pay['date'].toString()) ?? DateTime.now();
        ledger.add({
          'date': dt,
          'reference': pay['id']?.toString() ?? '',
          'sup_inv_no': pay['invoice_no']?.toString() ?? '',
          'debit': (pay['amount'] as num?)?.toDouble() ?? 0.0,
          'credit': 0.0,
          'type': 'PAYMENT',
          'method': pay['payment_method']?.toString() ?? 'CASH',
          'remarks': pay['remarks']?.toString() ?? 'Voucher Payment',
        });
      }
    } catch (e) {
      debugPrint("SupplierLedgerService supplier_payments fetch error: $e");
    }

    // 3. Supplier Credit Notes
    try {
      final List<Map<String, dynamic>> creditNotes = await db.query(
        'supplier_credit_notes',
        where: 'supplier_name = ? COLLATE NOCASE',
        whereArgs: [supplierName],
        orderBy: 'date ASC',
      );
      for (var cn in creditNotes) {
        DateTime dt = DateTime.tryParse(cn['date'].toString()) ?? DateTime.now();
        ledger.add({
          'date': dt,
          'reference': cn['id']?.toString() ?? '',
          'sup_inv_no': cn['invoice_no']?.toString() ?? '',
          'debit': (cn['amount'] as num?)?.toDouble() ?? 0.0,
          'credit': 0.0,
          'type': 'CREDIT NOTE',
          'method': '',
          'remarks': cn['remarks']?.toString() ?? 'Credit Note',
        });
      }
    } catch (e) {
      debugPrint("SupplierLedgerService credit notes fetch error: $e");
    }

    // 4. Purchase Returns (Debit Notes)
    try {
      final List<Map<String, dynamic>> returns = await db.query(
        'purchase_return_entries',
        where: 'supplier_name = ? COLLATE NOCASE AND (is_deleted = 0 OR is_deleted IS NULL)',
        whereArgs: [supplierName],
        orderBy: 'date ASC',
      );

      for (var pr in returns) {
        DateTime dt = DateTime.tryParse(pr['date'].toString()) ?? DateTime.now();
        ledger.add({
          'date': dt,
          'reference': pr['entry_no']?.toString() ?? '',
          'sup_inv_no': pr['sup_inv_no']?.toString() ?? '',
          'debit': (pr['grand_total'] as num?)?.toDouble() ?? (pr['net_amount'] as num?)?.toDouble() ?? 0.0,
          'credit': 0.0,
          'type': 'PURCHASE RETURN',
          'method': '',
          'remarks': 'Purchase Return',
        });
      }
    } catch (e) {
      debugPrint("SupplierLedgerService purchase returns fetch error: $e");
    }

    // Sort chronologically
    ledger.sort((a, b) {
      DateTime da = a['date'] as DateTime;
      DateTime db = b['date'] as DateTime;
      return da.compareTo(db);
    });

    return ledger;
  }

  /// Fetches live balances of all suppliers from the `suppliers` table.
  Future<Map<String, double>> fetchAllSupplierBalances() async {
    final db = await DbHelper.instance.database;
    final Map<String, double> balances = {};
    try {
      final List<Map<String, dynamic>> rows = await db.query(
        'suppliers',
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
      debugPrint("SupplierLedgerService fetchAllSupplierBalances error: $e");
    }
    return balances;
  }
}
