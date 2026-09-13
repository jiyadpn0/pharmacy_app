import 'package:flutter/foundation.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import '../models/erp_models.dart';

class PdfWorkerService {
  /// Offloads PDF document compilation to a background worker isolate
  static Future<Uint8List> generateInvoicePdfInBackground({
    required SaleInvoice invoice,
    required CompanyProfile company,
  }) async {
    // Pack data into a serializable map or transfer domain models safely
    return await compute(_compilePdfIsolate, {
      'entryNo': invoice.entryNo,
      'date': invoice.date.toIso8601String(),
      'customerAcc': invoice.customerAcc,
      'patient': invoice.patient,
      'grandTotal': invoice.grandTotal,
      'companyName': company.name,
      'companyAddress': company.address,
      'companyGst': company.gstIn,
    });
  }

  static Future<Uint8List> _compilePdfIsolate(Map<String, dynamic> data) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                data['companyName']?.toString() ?? '',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                data['companyAddress']?.toString() ?? '',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.Divider(),
              pw.SizedBox(height: 10),
              pw.Text(
                "Invoice No: ${data['entryNo']}",
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text("Date: ${data['date']}"),
              pw.Text("Customer: ${data['customerAcc']} (${data['patient']})"),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text(
                    "Grand Total: INR ${data['grandTotal']}",
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return await pdf.save();
  }
}
