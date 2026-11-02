import 'package:flutter/material.dart';
import '../database/db_helper.dart';

/// Provider handling GST reports, GSTR-1 outward supplies, GSTR-3B ITC, and tax summary engine.
class GstProvider extends ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Fetches GSTR-3B & GSTR-1 Tax Summary (Outward Supplies & Input Tax Credit)
  Future<Map<String, dynamic>> getGstSummary(DateTime fromDate, DateTime toDate) async {
    _isLoading = true;
    notifyListeners();

    try {
      final db = await DbHelper.instance.database;
      String fromStr = fromDate.toIso8601String().split('T')[0];
      String toStr = toDate.toIso8601String().split('T')[0];

      // Outward Supplies (Sales - GSTR-1 Base)
      final outward = await db.rawQuery('''
        SELECT 
          IFNULL(SUM(si.taxable_sp * si.qty), 0) as taxable_value,
          IFNULL(SUM(CASE WHEN sn.tax_type = 'Gst' THEN si.gst_amt / 2 ELSE 0 END), 0) as cgst_collected,
          IFNULL(SUM(CASE WHEN sn.tax_type = 'Gst' THEN si.gst_amt / 2 ELSE 0 END), 0) as sgst_collected,
          IFNULL(SUM(CASE WHEN sn.tax_type = 'Interstate' THEN si.gst_amt ELSE 0 END), 0) as igst_collected
        FROM sales_items si
        JOIN sales_invoices sn ON si.invoice_no = sn.entry_no
        WHERE date(sn.date) BETWEEN ? AND ? AND sn.is_deleted = 0
      ''', [fromStr, toStr]);

      // Input Tax Credit (Purchases - GSTR-3B Base)
      final itc = await db.rawQuery('''
        SELECT 
          IFNULL(SUM(pi.net), 0) as taxable_value,
          IFNULL(SUM(CASE WHEN pe.tax_type != 'Interstate' THEN pi.gst_amt / 2 ELSE 0 END), 0) as cgst_itc,
          IFNULL(SUM(CASE WHEN pe.tax_type != 'Interstate' THEN pi.gst_amt / 2 ELSE 0 END), 0) as sgst_itc,
          IFNULL(SUM(CASE WHEN pe.tax_type = 'Interstate' THEN pi.gst_amt ELSE 0 END), 0) as igst_itc
        FROM purchase_items pi
        JOIN purchase_entries pe ON pi.entry_no = pe.entry_no
        WHERE date(pe.date) BETWEEN ? AND ?
      ''', [fromStr, toStr]);

      return {
        'outward': outward.isNotEmpty ? outward.first : {},
        'itc': itc.isNotEmpty ? itc.first : {},
      };
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetches Schedule H / H1 / X drug controller register
  Future<List<Map<String, dynamic>>> getScheduleDrugRegister(
    DateTime fromDate,
    DateTime toDate,
    String scheduleType,
  ) async {
    final db = await DbHelper.instance.database;
    String fromStr = fromDate.toIso8601String().split('T')[0];
    String toStr = toDate.toIso8601String().split('T')[0];

    return await db.rawQuery('''
      SELECT 
        sn.date,
        sn.patient as patient_name,
        sn.mobile as patient_contact,
        sn.doctor as doctor_name,
        sn.doctor_reg_no,
        p.name as medicine_name,
        si.batch_number as batch_no,
        si.qty as sold_quantity
      FROM sales_items si
      JOIN sales_invoices sn ON si.invoice_no = sn.entry_no
      JOIN product_master p ON si.product_id = p.id
      WHERE date(sn.date) BETWEEN ? AND ? 
        AND sn.is_deleted = 0 
        AND p.schedule = ? COLLATE NOCASE
      ORDER BY sn.date ASC
    ''', [fromStr, toStr, scheduleType]);
  }
}
