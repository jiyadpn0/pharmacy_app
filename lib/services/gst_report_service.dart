import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';

class GstHsnRow {
  final String hsnCode;
  final String description;
  final String uqc;
  final double totalQty;
  final double totalValue;
  final double taxableValue;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final double totalTax;

  GstHsnRow({
    required this.hsnCode,
    required this.description,
    required this.uqc,
    required this.totalQty,
    required this.totalValue,
    required this.taxableValue,
    required this.cgstAmount,
    required this.sgstAmount,
    required this.igstAmount,
    required this.totalTax,
  });

  Map<String, dynamic> toMap() => {
        'hsn_code': hsnCode,
        'description': description,
        'uqc': uqc,
        'total_qty': totalQty,
        'total_value': totalValue,
        'taxable_value': taxableValue,
        'cgst': cgstAmount,
        'sgst': sgstAmount,
        'igst': igstAmount,
        'total_tax': totalTax,
      };
}

class Gstr3bSummary {
  final double outwardTaxable;
  final double outwardCgst;
  final double outwardSgst;
  final double outwardIgst;
  final double outwardTotalTax;

  final double itcTaxable;
  final double itcCgst;
  final double itcSgst;
  final double itcIgst;
  final double itcTotalTax;

  final double itcReversalsCgst;
  final double itcReversalsSgst;
  final double itcReversalsIgst;

  final double netItcCgst;
  final double netItcSgst;
  final double netItcIgst;

  final double payableCgst;
  final double payableSgst;
  final double payableIgst;
  final double totalNetPayable;

  Gstr3bSummary({
    required this.outwardTaxable,
    required this.outwardCgst,
    required this.outwardSgst,
    required this.outwardIgst,
    required this.outwardTotalTax,
    required this.itcTaxable,
    required this.itcCgst,
    required this.itcSgst,
    required this.itcIgst,
    required this.itcTotalTax,
    required this.itcReversalsCgst,
    required this.itcReversalsSgst,
    required this.itcReversalsIgst,
    required this.netItcCgst,
    required this.netItcSgst,
    required this.netItcIgst,
    required this.payableCgst,
    required this.payableSgst,
    required this.payableIgst,
    required this.totalNetPayable,
  });
}

class GstReportService {
  GstReportService._();
  static final GstReportService instance = GstReportService._();

  Future<Database> get _db async => await DbHelper.instance.database;

  /// Fetches HSN-wise outward supplies summary matching statutory GSTR-1 Table 12
  Future<List<GstHsnRow>> fetchHsnSummary(DateTime from, DateTime to) async {
    final db = await _db;
    final fromStr = DateFormat('yyyy-MM-dd').format(from);
    final toStr = DateFormat('yyyy-MM-dd').format(to);

    try {
      final rows = await db.rawQuery('''
        SELECT 
          COALESCE(NULLIF(TRIM(si.extra), ''), NULLIF(TRIM(p.hsn_code), ''), '3004') as hsn_code,
          COALESCE(NULLIF(TRIM(p.name), ''), 'MEDICAMENTS') as description,
          'BOX' as uqc,
          SUM(COALESCE(si.qty, 0)) as total_qty,
          SUM(COALESCE(si.total, 0.0)) as total_value,
          SUM(COALESCE(si.total, 0.0) - COALESCE(si.gst_amt, 0.0)) as taxable_value,
          SUM(COALESCE(si.cgst_amt, 0.0)) as cgst_amount,
          SUM(COALESCE(si.sgst_amt, 0.0)) as sgst_amount,
          SUM(COALESCE(si.igst_amt, 0.0)) as igst_amount,
          SUM(COALESCE(si.gst_amt, 0.0)) as total_tax
        FROM sales_items si
        JOIN sales_invoices sn ON si.invoice_no = sn.entry_no
        LEFT JOIN product_master p ON si.product_id = p.id
        WHERE date(sn.date) BETWEEN ? AND ? AND (sn.is_deleted = 0 OR sn.is_deleted IS NULL)
        GROUP BY COALESCE(NULLIF(TRIM(si.extra), ''), NULLIF(TRIM(p.hsn_code), ''), '3004')
        ORDER BY taxable_value DESC
      ''', [fromStr, toStr]);

      return rows.map((r) {
        return GstHsnRow(
          hsnCode: r['hsn_code']?.toString() ?? '3004',
          description: r['description']?.toString() ?? 'MEDICAMENTS',
          uqc: r['uqc']?.toString() ?? 'BOX',
          totalQty: (r['total_qty'] as num?)?.toDouble() ?? 0.0,
          totalValue: (r['total_value'] as num?)?.toDouble() ?? 0.0,
          taxableValue: (r['taxable_value'] as num?)?.toDouble() ?? 0.0,
          cgstAmount: (r['cgst_amount'] as num?)?.toDouble() ?? 0.0,
          sgstAmount: (r['sgst_amount'] as num?)?.toDouble() ?? 0.0,
          igstAmount: (r['igst_amount'] as num?)?.toDouble() ?? 0.0,
          totalTax: (r['total_tax'] as num?)?.toDouble() ?? 0.0,
        );
      }).toList();
    } catch (e) {
      debugPrint("GstReportService fetchHsnSummary error: $e");
      return [];
    }
  }

  /// Computes official GSTR-3B Tax Summary (Table 3.1 Outward, Table 4 ITC, Table 5 Net Payable)
  Future<Gstr3bSummary> computeGstr3bSummary(
    DateTime from,
    DateTime to, {
    String companyGstin = "32AAAAA0000A1Z5",
  }) async {
    final db = await _db;
    final fromStr = DateFormat('yyyy-MM-dd').format(from);
    final toStr = DateFormat('yyyy-MM-dd').format(to);

    // 1. Table 3.1 Outward Taxable Supplies (Gross Sales - Sales Returns)
    double outwardTaxable = 0.0;
    double outwardCgst = 0.0;
    double outwardSgst = 0.0;
    double outwardIgst = 0.0;

    try {
      final sRes = await db.rawQuery('''
        SELECT 
          SUM(COALESCE(si.total, 0.0) - COALESCE(si.gst_amt, 0.0)) as taxable,
          SUM(COALESCE(si.cgst_amt, 0.0)) as cgst,
          SUM(COALESCE(si.sgst_amt, 0.0)) as sgst,
          SUM(COALESCE(si.igst_amt, 0.0)) as igst
        FROM sales_items si
        JOIN sales_invoices sn ON si.invoice_no = sn.entry_no
        WHERE date(sn.date) BETWEEN ? AND ? AND (sn.is_deleted = 0 OR sn.is_deleted IS NULL)
      ''', [fromStr, toStr]);

      if (sRes.isNotEmpty && sRes.first['taxable'] != null) {
        outwardTaxable = (sRes.first['taxable'] as num?)?.toDouble() ?? 0.0;
        outwardCgst = (sRes.first['cgst'] as num?)?.toDouble() ?? 0.0;
        outwardSgst = (sRes.first['sgst'] as num?)?.toDouble() ?? 0.0;
        outwardIgst = (sRes.first['igst'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (e) {
      debugPrint("GstReportService sRes error: $e");
    }

    // 2. Table 4 Inward Supplies Eligible for ITC (Purchases)
    double itcTaxable = 0.0;
    double itcCgst = 0.0;
    double itcSgst = 0.0;
    double itcIgst = 0.0;

    try {
      final pRes = await db.rawQuery('''
        SELECT 
          SUM(COALESCE(pi.net, 0.0)) as taxable,
          SUM(COALESCE(pi.gst_amt, 0.0)) as total_gst
        FROM purchase_items pi
        JOIN purchase_entries pe ON pi.entry_no = pe.entry_no
        WHERE date(pe.date) BETWEEN ? AND ? AND (pe.is_deleted = 0 OR pe.is_deleted IS NULL)
      ''', [fromStr, toStr]);

      if (pRes.isNotEmpty && pRes.first['taxable'] != null) {
        itcTaxable = (pRes.first['taxable'] as num?)?.toDouble() ?? 0.0;
        final totalGst = (pRes.first['total_gst'] as num?)?.toDouble() ?? 0.0;
        // In local state transactions, GST splits 50/50 into CGST & SGST
        itcCgst = totalGst / 2.0;
        itcSgst = totalGst / 2.0;
      }
    } catch (e) {
      debugPrint("GstReportService pRes error: $e");
    }

    // 3. Table 4(B) ITC Reversals (from Purchase Returns / Debit Notes)
    double itcReversalsCgst = 0.0;
    double itcReversalsSgst = 0.0;
    double itcReversalsIgst = 0.0;

    try {
      final prRes = await db.rawQuery('''
        SELECT 
          SUM(COALESCE(pri.total, 0.0) * (COALESCE(pri.gst_percent, 12.0) / (100.0 + COALESCE(pri.gst_percent, 12.0)))) as return_gst
        FROM purchase_return_items pri
        JOIN purchase_return_entries pre ON pri.entry_no = pre.entry_no
        WHERE date(pre.date) BETWEEN ? AND ? AND (pre.is_deleted = 0 OR pre.is_deleted IS NULL)
      ''', [fromStr, toStr]);

      if (prRes.isNotEmpty && prRes.first['return_gst'] != null) {
        final retGst = (prRes.first['return_gst'] as num?)?.toDouble() ?? 0.0;
        itcReversalsCgst = retGst / 2.0;
        itcReversalsSgst = retGst / 2.0;
      }
    } catch (e) {
      debugPrint("GstReportService prRes error: $e");
    }

    // 4. Net Available ITC (Table 4(C) = 4(A) - 4(B))
    final double netItcCgst = (itcCgst - itcReversalsCgst) > 0 ? (itcCgst - itcReversalsCgst) : 0.0;
    final double netItcSgst = (itcSgst - itcReversalsSgst) > 0 ? (itcSgst - itcReversalsSgst) : 0.0;
    final double netItcIgst = (itcIgst - itcReversalsIgst) > 0 ? (itcIgst - itcReversalsIgst) : 0.0;

    // 5. Table 5 Net Tax Payable in Cash
    final double payableCgst = (outwardCgst - netItcCgst) > 0 ? (outwardCgst - netItcCgst) : 0.0;
    final double payableSgst = (outwardSgst - netItcSgst) > 0 ? (outwardSgst - netItcSgst) : 0.0;
    final double payableIgst = (outwardIgst - netItcIgst) > 0 ? (outwardIgst - netItcIgst) : 0.0;
    final double totalNetPayable = payableCgst + payableSgst + payableIgst;

    return Gstr3bSummary(
      outwardTaxable: outwardTaxable,
      outwardCgst: outwardCgst,
      outwardSgst: outwardSgst,
      outwardIgst: outwardIgst,
      outwardTotalTax: outwardCgst + outwardSgst + outwardIgst,
      itcTaxable: itcTaxable,
      itcCgst: itcCgst,
      itcSgst: itcSgst,
      itcIgst: itcIgst,
      itcTotalTax: itcCgst + itcSgst + itcIgst,
      itcReversalsCgst: itcReversalsCgst,
      itcReversalsSgst: itcReversalsSgst,
      itcReversalsIgst: itcReversalsIgst,
      netItcCgst: netItcCgst,
      netItcSgst: netItcSgst,
      netItcIgst: netItcIgst,
      payableCgst: payableCgst,
      payableSgst: payableSgst,
      payableIgst: payableIgst,
      totalNetPayable: totalNetPayable,
    );
  }
}
