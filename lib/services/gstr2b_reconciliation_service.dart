import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';

enum Gstr2bMatchStatus { matched, missingInBooks, taxMismatch }

class Gstr2bReconciliationItem {
  final String supplierGstin;
  final String supplierName;
  final String invoiceNo;
  final String invoiceDate;
  final double portalTaxableVal;
  final double portalTaxAmt;
  final double booksTaxableVal;
  final double booksTaxAmt;
  final Gstr2bMatchStatus status;

  Gstr2bReconciliationItem({
    required this.supplierGstin,
    required this.supplierName,
    required this.invoiceNo,
    required this.invoiceDate,
    required this.portalTaxableVal,
    required this.portalTaxAmt,
    required this.booksTaxableVal,
    required this.booksTaxAmt,
    required this.status,
  });
}

class Gstr2bReconciliationService {
  static final Gstr2bReconciliationService instance = Gstr2bReconciliationService._internal();
  Gstr2bReconciliationService._internal();

  /// Parses GSTR-2B JSON content and reconciles against purchase_entries in SQLite
  Future<List<Gstr2bReconciliationItem>> reconcileGstr2bJson(String jsonContent) async {
    List<Gstr2bReconciliationItem> results = [];
    final db = await DbHelper.instance.database;

    try {
      final Map<String, dynamic> data = jsonDecode(jsonContent);
      final List<dynamic> docList = data['docdata']?['b2b'] ?? data['b2b'] ?? [];

      for (var supplierDoc in docList) {
        final String ctin = supplierDoc['ctin']?.toString() ?? 'UNKNOWN';
        final String tradeName = supplierDoc['trdName']?.toString() ?? supplierDoc['cname']?.toString() ?? ctin;
        final List<dynamic> invList = supplierDoc['inv'] ?? [];

        for (var inv in invList) {
          final String inum = inv['inum']?.toString() ?? '';
          final String idt = inv['idt']?.toString() ?? '';
          final double val = (inv['val'] as num?)?.toDouble() ?? 0.0;

          double portalTaxable = 0.0;
          double portalTax = 0.0;

          final List<dynamic> items = inv['itms'] ?? [];
          for (var itm in items) {
            final Map<String, dynamic> det = itm['itm_det'] ?? itm;
            portalTaxable += (det['txval'] as num?)?.toDouble() ?? 0.0;
            portalTax += ((det['iamt'] as num?)?.toDouble() ?? 0.0) +
                ((det['camt'] as num?)?.toDouble() ?? 0.0) +
                ((det['samt'] as num?)?.toDouble() ?? 0.0);
          }

          // Query books for matching invoice
          final booksRes = await db.query(
            'purchase_entries',
            where: 'entry_no LIKE ? OR entry_no = ?',
            whereArgs: ['%$inum%', inum],
          );

          if (booksRes.isEmpty) {
            results.add(Gstr2bReconciliationItem(
              supplierGstin: ctin,
              supplierName: tradeName,
              invoiceNo: inum,
              invoiceDate: idt,
              portalTaxableVal: portalTaxable,
              portalTaxAmt: portalTax,
              booksTaxableVal: 0.0,
              booksTaxAmt: 0.0,
              status: Gstr2bMatchStatus.missingInBooks,
            ));
          } else {
            final bookEntry = booksRes.first;
            final double booksTotal = (bookEntry['total_amount'] as num?)?.toDouble() ?? 0.0;
            final double booksTax = (bookEntry['total_gst'] as num?)?.toDouble() ?? 0.0;

            final double diff = (portalTax - booksTax).abs();
            final status = diff < 2.0 ? Gstr2bMatchStatus.matched : Gstr2bMatchStatus.taxMismatch;

            results.add(Gstr2bReconciliationItem(
              supplierGstin: ctin,
              supplierName: tradeName,
              invoiceNo: inum,
              invoiceDate: idt,
              portalTaxableVal: portalTaxable,
              portalTaxAmt: portalTax,
              booksTaxableVal: booksTotal - booksTax,
              booksTaxAmt: booksTax,
              status: status,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint("GSTR-2B JSON Parse Error: $e");
    }

    return results;
  }
}
