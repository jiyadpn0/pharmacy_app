import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/db_helper.dart';
import 'whatsapp_service.dart';

class ChronicRefillItem {
  final String invoiceNo;
  final String patientName;
  final String patientMobile;
  final String productName;
  final String saleDateStr;
  final DateTime saleDate;
  final DateTime refillDueDate;
  final int qty;

  ChronicRefillItem({
    required this.invoiceNo,
    required this.patientName,
    required this.patientMobile,
    required this.productName,
    required this.saleDateStr,
    required this.saleDate,
    required this.refillDueDate,
    required this.qty,
  });
}

class ChronicRefillService {
  static final ChronicRefillService instance = ChronicRefillService._internal();
  ChronicRefillService._internal();

  /// Identifies chronic medications sold 20-35 days ago requiring 30-day refilling
  Future<List<ChronicRefillItem>> getPendingRefills() async {
    final db = await DbHelper.instance.database;
    final now = DateTime.now();
    final date35DaysAgo = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 35)));
    final date20DaysAgo = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 20)));

    const query = '''
      SELECT 
        si.entry_no,
        si.patient_name,
        si.patient_mobile,
        si.date,
        sitem.product_name,
        sitem.qty
      FROM sales_invoices si
      JOIN sales_items sitem ON si.entry_no = sitem.invoice_no
      WHERE si.date >= ? AND si.date <= ?
    ''';

    final rows = await db.rawQuery(query, [date35DaysAgo, date20DaysAgo]);
    List<ChronicRefillItem> results = [];

    for (var r in rows) {
      final pName = r['product_name']?.toString() ?? '';
      final pMobile = r['patient_mobile']?.toString() ?? '';
      final pPatient = r['patient_name']?.toString() ?? 'Customer';
      final entryNo = r['entry_no']?.toString() ?? '';
      final dateStr = r['date']?.toString() ?? '';

      if (dateStr.isEmpty) continue;
      DateTime? saleDate = DateTime.tryParse(dateStr);
      if (saleDate == null) continue;

      final refillDueDate = saleDate.add(const Duration(days: 30));

      results.add(ChronicRefillItem(
        invoiceNo: entryNo,
        patientName: pPatient,
        patientMobile: pMobile,
        productName: pName,
        saleDateStr: dateStr,
        saleDate: saleDate,
        refillDueDate: refillDueDate,
        qty: (r['qty'] as num?)?.toInt() ?? 1,
      ));
    }

    results.sort((a, b) => a.refillDueDate.compareTo(b.refillDueDate));
    return results;
  }

  /// Sends a formatted chronic refill WhatsApp reminder to patient
  Future<bool> sendWhatsAppRefillReminder(
    BuildContext context, {
    required ChronicRefillItem item,
    required String companyName,
  }) async {
    if (item.patientMobile.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Patient phone number is missing."), backgroundColor: Colors.red),
      );
      return false;
    }

    final phone = WhatsAppService.sanitizePhoneNumber(item.patientMobile);
    final dueStr = DateFormat('dd MMM yyyy').format(item.refillDueDate);

    final text = "Hello *${item.patientName.toUpperCase()}*,\n\n"
        "Your 30-day supply of *${item.productName}* from *${companyName.toUpperCase()}* is due for refill on *$dueStr*.\n\n"
        "Reply to this message to confirm your refill order for Store Pickup or Home Delivery!\n\n"
        "Thank you for choosing $companyName!";

    return await WhatsAppService.sendCustomMessage(
      context: context,
      phone: phone,
      text: text,
    );
  }
}
