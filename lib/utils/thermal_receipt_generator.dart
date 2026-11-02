import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/erp_models.dart';

class ThermalReceiptGenerator {
  static Future<Uint8List> buildThermalReceipt(
    dynamic invoice, 
    CompanyProfile company,
  ) async {
    final pdf = pw.Document();
    
    // Custom narrow thermal page format (80mm width = approx 226 points)
    const thermalPageFormat = PdfPageFormat(80 * PdfPageFormat.mm, 200 * PdfPageFormat.mm, marginAll: 5 * PdfPageFormat.mm);

    String partyName = "Cash";
    if (invoice is SaleInvoice) {
      partyName = invoice.customerAcc.isNotEmpty ? invoice.customerAcc : "Cash";
    } else if (invoice is PurchaseEntry) {
      partyName = invoice.supplierName.isNotEmpty ? invoice.supplierName : "Wholesaler";
    } else {
      try {
        partyName = invoice.customerAcc ?? invoice.supplierName ?? "Cash";
      } catch (_) {}
    }

    pdf.addPage(
      pw.Page(
        pageFormat: thermalPageFormat,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Center(
                child: pw.Text(company.name.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              ),
              if (company.address.isNotEmpty)
                pw.Center(
                  child: pw.Text(company.address, style: const pw.TextStyle(fontSize: 8)),
                ),
              if (company.phone.isNotEmpty)
                pw.Center(
                  child: pw.Text("Ph: ${company.phone}", style: const pw.TextStyle(fontSize: 8)),
                ),
              pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 0.5),
              
              // Invoice Info
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Inv: ${invoice.entryNo}", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Dt: ${invoice.date.toString().substring(0, 10)}", style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
              pw.Text("Customer/Party: $partyName", style: const pw.TextStyle(fontSize: 9)),
              pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 0.5),

              // Items Header
              pw.Row(
                children: [
                  pw.Expanded(flex: 4, child: pw.Text("Item", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                  pw.Expanded(flex: 1, child: pw.Text("Qty", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                  pw.Expanded(flex: 2, child: pw.Text("Total", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                ],
              ),
              pw.SizedBox(height: 2),

              // Items List
              ...((invoice.items as List<dynamic>?) ?? []).map<pw.Widget>((item) {
                String name = "";
                if (item is SaleItem) {
                  name = item.product.manufacturer.isNotEmpty
                      ? "${item.product.name} [MFR: ${item.product.manufacturer}]"
                      : item.product.name;
                } else if (item is PurchaseItem) {
                  name = item.productName;
                } else {
                  try {
                    name = item.productName;
                  } catch (_) {
                    try {
                      name = item.product.name;
                    } catch (_) {
                      name = item.toString();
                    }
                  }
                }

                int qty = 0;
                try {
                  qty = item.qty;
                } catch (_) {}

                double total = 0.0;
                try {
                  total = item.total;
                } catch (_) {}

                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2),
                  child: pw.Row(
                    children: [
                      pw.Expanded(flex: 4, child: pw.Text(name, style: const pw.TextStyle(fontSize: 8), maxLines: 1)),
                      pw.Expanded(flex: 1, child: pw.Text("$qty", style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.right)),
                      pw.Expanded(flex: 2, child: pw.Text(total.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.right)),
                    ],
                  ),
                );
              }),

              pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 0.5),

              // Totals
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("GRAND TOTAL:", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  pw.Text("INR ${invoice.grandTotal.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 8),

              // Dynamic UPI QR Code on Thermal Receipt
              () {
                final cleanVpa = company.upiVpaId.isNotEmpty ? company.upiVpaId : "sahakarmedicals@upi";
                final payeeName = company.upiPayeeName.isNotEmpty ? company.upiPayeeName : company.name;
                final amt = invoice.grandTotal.toStringAsFixed(2);
                final ref = Uri.encodeComponent("Bill-${invoice.entryNo}");
                final upiPayload = "upi://pay?pa=$cleanVpa&pn=${Uri.encodeComponent(payeeName)}&am=$amt&tn=$ref&cu=INR";

                return pw.Center(
                  child: pw.Column(
                    children: [
                      pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 0.5),
                      pw.Text("SCAN & PAY VIA UPI", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      pw.Container(
                        width: 90,
                        height: 90,
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: upiPayload,
                          drawText: false,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text("UPI ID: $cleanVpa", style: const pw.TextStyle(fontSize: 7)),
                      pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 0.5),
                    ],
                  ),
                );
              }(),

              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.Text("Thank You! Visit Again.", style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
              ),
            ],
          );
        },
      ),
    );

    return await pdf.save();
  }
}
