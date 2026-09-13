import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../providers/pharmacy_provider.dart';
import '../models/erp_models.dart';
import 'app_formatters.dart';

class InvoicePdfGenerator {
  static Future<void> generateAndPrint(SaleInvoice invoice, CompanyProfile company) async {
    final doc = await buildPdfDocument(invoice, company);
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
  }

  static Future<pw.Document> buildPdfDocument(SaleInvoice invoice, CompanyProfile company) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(company.name, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                    pw.Text(company.address, style: const pw.TextStyle(fontSize: 9)),
                    pw.Text("Phone: ${company.phone}", style: const pw.TextStyle(fontSize: 9)),
                    pw.Text("GSTIN: ${company.gstIn}", style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text("TAX INVOICE", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                    pw.Text("Invoice No: ${invoice.entryNo}", style: const pw.TextStyle(fontSize: 9)),
                    pw.Text("Date: ${DateFormat('dd/MM/yyyy').format(invoice.date)}", style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ],
            ),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("Patient: ${invoice.patient} | Mob: ${invoice.mobile}", style: const pw.TextStyle(fontSize: 9)),
                pw.Text("Doctor: ${invoice.doctor}", style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (context) => [
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: const {
              0: pw.FixedColumnWidth(20),  // Sl
              1: pw.FixedColumnWidth(40),  // HSN
              2: pw.FlexColumnWidth(3),    // Product
              3: pw.FixedColumnWidth(45),  // Batch
              4: pw.FixedColumnWidth(35),  // Exp
              5: pw.FixedColumnWidth(25),  // Qty
              6: pw.FixedColumnWidth(40),  // MRP
              7: pw.FixedColumnWidth(40),  // Disc
              8: pw.FixedColumnWidth(40),  // Rate
              9: pw.FixedColumnWidth(50),  // Total
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _th("Sl"),
                  _th("HSN"),
                  _th("Product Description / MFR"),
                  _th("Batch"),
                  _th("Exp"),
                  _th("Qty"),
                  _th("M.R.P"),
                  _th("Disc"),
                  _th("Rate"),
                  _th("Total"),
                ],
              ),
              ...invoice.items.asMap().entries.map((e) {
                final i = e.key + 1;
                final item = e.value;
                final double itemDisc = item.discAmt > 0
                    ? item.discAmt
                    : ((item.mrp * item.qty * item.discPercent) / 100.0);
                final String hsnStr = item.product.hsnCode.isNotEmpty ? item.product.hsnCode : "3004";
                final double packSize = item.product.packSize > 0 ? item.product.packSize.toDouble() : 1.0;
                final double stripMrp = item.mrp > 0 ? item.mrp : (item.product.mrp * packSize);
                final double rate = item.sRate > 0 ? item.sRate : item.product.salePrice;

                return pw.TableRow(
                  children: [
                    _td("$i"),
                    _td(hsnStr),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(item.product.name, style: const pw.TextStyle(fontSize: 9)),
                          if (item.product.manufacturer.isNotEmpty)
                            pw.Text("MFR: ${item.product.manufacturer}", style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                        ],
                      ),
                    ),
                    _td(item.product.batch),
                    _td(item.product.expiry),
                    _td("${item.qty}"),
                    _td(stripMrp.toStringAsFixed(2)),
                    _td(itemDisc.toStringAsFixed(2)),
                    _td(rate.toStringAsFixed(2)),
                    _td(item.total.toStringAsFixed(2)),
                  ],
                );
              }),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("TIME: ${DateFormat('hh:mm a').format(invoice.date)}", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text("Medicines once sold will not be taken back", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  _totalRow("Sub Total:", invoice.subTotal),
                  if (invoice.discount > 0) _totalRow("Discount:", invoice.discount),
                  if (invoice.roundOff != 0) _totalRow("Round Off:", invoice.roundOff),
                  pw.Divider(),
                  pw.Text("Grand Total: ₹${invoice.grandTotal.toStringAsFixed(2)}", 
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                  pw.SizedBox(height: 20),
                  pw.Text("PHARMACIST SIGNATURE: ____________________", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    return doc;
  }

  static Future<void> generateAndPrintPurchase(PurchaseEntry entry, CompanyProfile company, {bool isAutoGenerated = false}) async {
    final doc = await buildPurchasePdf(entry, company, isAutoGenerated: isAutoGenerated);
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
  }

  static Future<pw.Document> buildPurchasePdf(PurchaseEntry entry, CompanyProfile company, {bool isAutoGenerated = false}) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(company.name, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                      if (company.address.isNotEmpty) pw.Text(company.address, style: const pw.TextStyle(fontSize: 9)),
                      if (company.phone.isNotEmpty) pw.Text("Phone: ${company.phone}", style: const pw.TextStyle(fontSize: 9)),
                      if (company.gstIn.isNotEmpty) pw.Text("GSTIN: ${company.gstIn}", style: const pw.TextStyle(fontSize: 9)),
                      if (company.dlNumber.isNotEmpty) pw.Text("DL No: ${company.dlNumber}", style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text("PURCHASE INVOICE", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                      pw.Text("Entry No: ${entry.entryNo}", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.Text("Entry Date: ${DateFormat('dd/MM/yyyy').format(entry.date)}", style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1, color: PdfColors.grey400),
            ],
          );
        },
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text("Smart Pharmacy ERP - Purchase Document", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
              pw.Text("Page ${context.pageNumber} of ${context.pagesCount}", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            ],
          ),
        ),
        build: (pw.Context context) {
          final cleanedSupInvNo = cleanInvoiceNo(entry.supInvNo);
          return [
            // Supplier Details Card
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("SUPPLIER DETAILS", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                      pw.Text(entry.supplierName.isNotEmpty ? entry.supplierName : "N/A", style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Row(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          pw.Text("Sup Inv No: ", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                          pw.Text(
                            cleanedSupInvNo.isEmpty ? "AUTO-GENERATED" : cleanedSupInvNo,
                            style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                              color: cleanedSupInvNo.isEmpty || isAutoGenerated
                                  ? PdfColors.red700
                                  : PdfColors.black,
                            ),
                          ),
                          if (isAutoGenerated && cleanedSupInvNo.isNotEmpty)
                            pw.Text(" (Auto)", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.red700)),
                        ],
                      ),
                      pw.Text("Sup Inv Date: ${DateFormat('dd/MM/yyyy').format(entry.supInvDate)}", style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // Items Table
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: {
                0: const pw.FixedColumnWidth(25),  // Sl
                1: const pw.FlexColumnWidth(3.5),  // Product
                2: const pw.FlexColumnWidth(1.2),  // HSN
                3: const pw.FlexColumnWidth(1.5),  // Batch
                4: const pw.FlexColumnWidth(1.2),  // Exp
                5: const pw.FixedColumnWidth(30),  // Qty
                6: const pw.FixedColumnWidth(25),  // Free
                7: const pw.FlexColumnWidth(1.2),  // P.Rate
                8: const pw.FlexColumnWidth(1.2),  // MRP
                9: const pw.FixedColumnWidth(30),  // Disc%
                10: const pw.FixedColumnWidth(30), // GST%
                11: const pw.FlexColumnWidth(1.5), // Total
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
                  children: [
                    _th("Sl", align: pw.TextAlign.center),
                    _th("Product Name"),
                    _th("HSN"),
                    _th("Batch"),
                    _th("Exp"),
                    _th("Qty", align: pw.TextAlign.center),
                    _th("Free", align: pw.TextAlign.center),
                    _th("P.Rate", align: pw.TextAlign.right),
                    _th("MRP", align: pw.TextAlign.right),
                    _th("Disc%", align: pw.TextAlign.center),
                    _th("GST%", align: pw.TextAlign.center),
                    _th("Total", align: pw.TextAlign.right),
                  ],
                ),
                ...entry.items.asMap().entries.map((e) {
                  final i = e.key + 1;
                  final item = e.value;
                  return pw.TableRow(
                    decoration: e.key % 2 == 1 ? const pw.BoxDecoration(color: PdfColors.grey50) : null,
                    children: [
                      _td("$i", align: pw.TextAlign.center),
                      _td(item.productName),
                      _td(item.hsnCode),
                      _td(item.batch),
                      _td(item.expiry),
                      _td("${item.qty}", align: pw.TextAlign.center),
                      _td("${item.fQty}", align: pw.TextAlign.center),
                      _td(item.pRate.toStringAsFixed(2), align: pw.TextAlign.right),
                      _td(item.mrp.toStringAsFixed(2), align: pw.TextAlign.right),
                      _td("${item.discPercent.toStringAsFixed(0)}%", align: pw.TextAlign.center),
                      _td("${item.gstPercent.toStringAsFixed(0)}%", align: pw.TextAlign.center),
                      _td(item.total.toStringAsFixed(2), align: pw.TextAlign.right),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 12),

            // Totals Summary Box
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text("Total Items: ${entry.items.length}", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.Text("Total Qty: ${entry.items.fold<int>(0, (sum, i) => sum + i.qty)} (+ ${entry.items.fold<int>(0, (sum, i) => sum + i.fQty)} Free)", style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
                pw.Container(
                  width: 200,
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    color: PdfColors.grey50,
                  ),
                  child: pw.Column(
                    children: [
                      _totalRow("Sub Total:", entry.subTotal),
                      if (entry.discount > 0) _totalRow("Discount:", entry.discount),
                      if (entry.otherCharge > 0) _totalRow("Other Charges:", entry.otherCharge),
                      if (entry.roundOff != 0) _totalRow("Round Off:", entry.roundOff),
                      pw.Divider(thickness: 0.5),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text("Grand Total:", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                          pw.Text("₹${entry.grandTotal.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ];
        },
      ),
    );

    return doc;
  }

  static Future<void> generateAndPrintSaleReturn(SaleReturnInvoice invoice, CompanyProfile company) async {
    final doc = await buildSaleReturnPdf(invoice, company);
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
  }

  static Future<pw.Document> buildSaleReturnPdf(SaleReturnInvoice invoice, CompanyProfile company) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(company.name, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                    pw.Text(company.address, style: const pw.TextStyle(fontSize: 9)),
                    pw.Text("Phone: ${company.phone}", style: const pw.TextStyle(fontSize: 9)),
                    pw.Text("GSTIN: ${company.gstIn}", style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text("SALES RETURN", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
                    pw.Text("Return No: ${invoice.entryNo}", style: const pw.TextStyle(fontSize: 9)),
                    pw.Text("Date: ${DateFormat('dd/MM/yyyy').format(invoice.date)}", style: const pw.TextStyle(fontSize: 9)),
                    pw.Text("Ref Invoice: ${invoice.originalInvoiceNo}", style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ],
            ),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("Customer: ${invoice.customerAcc} | Patient: ${invoice.patient}", style: const pw.TextStyle(fontSize: 9)),
                pw.Text("Doctor: ${invoice.doctor}", style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (context) => [
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _th("Sl"),
                  _th("Product Description"),
                  _th("Batch"),
                  _th("Exp"),
                  _th("Qty"),
                  _th("M.R.P"),
                  _th("S.Rate"),
                  _th("Total"),
                ],
              ),
              ...invoice.items.asMap().entries.map((e) {
                final i = e.key + 1;
                final item = e.value;
                return pw.TableRow(
                  children: [
                    _td("$i"),
                    _td(item.product.name),
                    _td(item.product.batch),
                    _td(item.product.expiry),
                    _td("${item.qty}"),
                    _td(item.mrp.toStringAsFixed(2)),
                    _td(item.sRate.toStringAsFixed(2)),
                    _td(item.total.toStringAsFixed(2)),
                  ],
                );
              }),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text(
                "Grand Total: Rs. ${invoice.grandTotal.toStringAsFixed(2)}",
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.red900),
              ),
            ],
          ),
        ],
      ),
    );

    return doc;
  }

  static Future<void> generateAndPrintPurchaseReturn(List<PurchaseReturnItem> items, String entryNo, DateTime date, String supplier, String originalInv, CompanyProfile company, {bool showSupplierCol = true, bool showInvNoCol = true, bool showEntryNoCol = false, String entryNoWithFY = ""}) async {
    final doc = await buildPurchaseReturnPdf(items, entryNo, date, supplier, originalInv, company, showSupplierCol: showSupplierCol, showInvNoCol: showInvNoCol, showEntryNoCol: showEntryNoCol, entryNoWithFY: entryNoWithFY);
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
  }

  static Future<pw.Document> buildPurchaseReturnPdf(
    List<PurchaseReturnItem> items, 
    String entryNo, 
    DateTime date, 
    String supplier, 
    String originalInv, 
    CompanyProfile company, {
    bool showSupplierCol = true, 
    bool showInvNoCol = true, 
    bool showEntryNoCol = false, 
    String entryNoWithFY = ""
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(company.name, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                      pw.Text(company.address, style: const pw.TextStyle(fontSize: 9), maxLines: 2),
                      pw.Text("GSTIN: ${company.gstIn}", style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text("PURCHASE RETURN", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900)),
                    pw.Text("Return No: $entryNo", style: const pw.TextStyle(fontSize: 9)),
                    pw.Text("Date: ${DateFormat('dd/MM/yyyy').format(date)}", style: const pw.TextStyle(fontSize: 9)),
                    if (originalInv.isNotEmpty) pw.Text("Orig Pur No: $originalInv", style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ],
            ),
            pw.Divider(),
            if (showSupplierCol && supplier.isNotEmpty)
              pw.Text("Supplier: $supplier", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold), maxLines: 1),
            pw.SizedBox(height: 6),
          ],
        ),
        build: (context) => [
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _th("Sl"),
                  _th("Product"),
                  _th("Batch"),
                  _th("Exp"),
                  _th("Qty"),
                  if (showSupplierCol) _th("Supplier"),
                  if (showInvNoCol) _th("Inv No"),
                  _th("P.Rate"),
                  _th("Total"),
                ],
              ),
              ...items.asMap().entries.map((e) {
                final i = e.key + 1;
                final item = e.value;
                return pw.TableRow(
                  children: [
                    _td("$i"),
                    _td(item.product.name),
                    _td(item.product.batch),
                    _td(item.product.expiry),
                    _td("${item.qty}"),
                    if (showSupplierCol) _td(item.supplier),
                    if (showInvNoCol) _td(item.supInvNo),
                    _td(item.pRate.toStringAsFixed(2)),
                    _td(item.total.toStringAsFixed(2)),
                  ],
                );
              }),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text(
                "Grand Total: Rs. ${items.fold(0.0, (sum, i) => sum + i.total).toStringAsFixed(2)}",
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.orange900),
              ),
            ],
          ),
        ],
      ),
    );

    return doc;
  }

  static pw.Widget _th(String text, {pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(text, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9), textAlign: align));
  static pw.Widget _td(String text, {pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(text, style: const pw.TextStyle(fontSize: 9), textAlign: align));
  static pw.Widget _totalRow(String label, double val) => pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
      pw.SizedBox(width: 20),
      pw.Text(val.toStringAsFixed(2), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
    ],
  );
}
