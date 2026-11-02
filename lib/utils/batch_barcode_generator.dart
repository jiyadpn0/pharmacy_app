import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/erp_models.dart';

class BatchBarcodeGenerator {
  /// Generates a PDF label sheet (e.g. 24 or 40 labels per A4 page) for a given stock batch
  static Future<void> printBatchLabelSheet(
    BuildContext context, {
    required Product product,
    required String batchNumber,
    required String expiryStr,
    required double mrp,
    required double salePrice,
    int labelsCount = 24,
    int labelsPerRow = 3,
  }) async {
    final pdf = pw.Document();

    final barcodeData = "${product.name}|${batchNumber.trim()}|${mrp.toStringAsFixed(2)}";

    // Calculate grid layout parameters
    final int itemsPerPage = labelsCount;
    const int totalPages = 1;

    for (int p = 0; p < totalPages; p++) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(16),
          build: (pw.Context ctx) {
            return pw.GridView(
              crossAxisCount: labelsPerRow,
              childAspectRatio: 2.2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: List.generate(itemsPerPage, (index) {
                return pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      // Product Name
                      pw.Text(
                        product.name.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: pw.TextOverflow.clip,
                        textAlign: pw.TextAlign.center,
                      ),
                      // Batch & Expiry
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            "B: $batchNumber",
                            style: const pw.TextStyle(fontSize: 7),
                          ),
                          pw.Text(
                            "EXP: $expiryStr",
                            style: const pw.TextStyle(fontSize: 7),
                          ),
                        ],
                      ),
                      // Barcode
                      pw.Container(
                        height: 22,
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.code128(),
                          data: barcodeData,
                          drawText: false,
                        ),
                      ),
                      // MRP & Price
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            "MRP: Rs.${mrp.toStringAsFixed(2)}",
                            style: const pw.TextStyle(fontSize: 7),
                          ),
                          pw.Text(
                            "OUR: Rs.${salePrice.toStringAsFixed(2)}",
                            style: pw.TextStyle(
                              fontSize: 7,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            );
          },
        ),
      );
    }

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: "Batch_Labels_${product.name}_$batchNumber.pdf",
    );
  }
}
