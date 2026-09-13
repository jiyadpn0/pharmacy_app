import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/erp_models.dart';
import '../services/print_spooler_service.dart';
import '../services/whatsapp_service.dart';
import 'app_dialogs.dart';
import 'dot_matrix_formatter.dart';
import 'invoice_pdf_generator.dart';
import 'thermal_receipt_generator.dart';

class PrinterService {
  /// Sends raw ESC/POS text to network/USB socket or Windows raw printer spooler
  static Future<void> printDotMatrix({
    required SaleInvoice invoice,
    int columns = 80,
    String storeName = "SAHAKAR MEDICALS & SURGICALS",
    String storeAddress = "KALPETTA TOWN, WAYANAD",
    String headerTitle = "TAX INVOICE / CASH MEMO",
    String? printerIpOrPort, 
  }) async {
    final String rawText = DotMatrixFormatter.generateInvoiceText(
      invoice: invoice,
      columns: columns,
      storeName: storeName,
      storeAddress: storeAddress,
      headerTitle: headerTitle,
    );

    // Direct Socket Connection for Network / Ethernet Thermal / Dot-Matrix Printers
    if (printerIpOrPort != null && printerIpOrPort.contains('.')) {
      try {
        final socket = await Socket.connect(printerIpOrPort, 9100, timeout: const Duration(seconds: 3));
        socket.add(Uint8List.fromList(rawText.codeUnits));
        await socket.flush();
        await socket.close();
        return;
      } catch (e) {
        debugPrint("Direct socket print failed: $e. Using Windows spooler fallback.");
      }
    }

    // Calculate exact dynamic page height based on line count to prevent 12cm blank paper feeding!
    final List<String> textLines = rawText.trim().split('\n');
    final int lineCount = textLines.length;
    final double lineMultiplier = columns == 136 ? 3.8 : 4.0;
    final double dynamicHeightMm = (lineCount * lineMultiplier) + 10.0;

    // Windows / Desktop Platform Spooler Fallback
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async {
        final doc = pw.Document();
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(
              columns == 136 ? 300 * PdfPageFormat.mm : 210 * PdfPageFormat.mm,
              dynamicHeightMm * PdfPageFormat.mm, // Dynamic height stops printer immediately at Pharmacist Signature!
              marginLeft: 6,
              marginTop: 4,
              marginRight: 6,
              marginBottom: 4,
            ),
            build: (pw.Context context) {
              return pw.Text(
                rawText.trim(),
                style: pw.TextStyle(
                  font: pw.Font.courier(),
                  fontSize: columns == 136 ? 8 : 9.5,
                  lineSpacing: 1.0,
                ),
              );
            },
          ),
        );
        return doc.save();
      },
      name: 'Invoice_${invoice.entryNo}_Raw',
    );
  }

  /// High-resolution PDF graphical layout
  static Future<void> printPdfInvoice({
    required SaleInvoice invoice,
    required CompanyProfile companyProfile,
    bool directPrint = false,
  }) async {
    if (directPrint) {
      final doc = await InvoicePdfGenerator.buildPdfDocument(invoice, companyProfile);
      final pdfBytes = await doc.save();
      
      List<Printer> printers = await Printing.listPrinters();
      Printer? defaultPrinter;
      try {
        defaultPrinter = printers.firstWhere((p) => p.isDefault);
      } catch (e) {
        if (printers.isNotEmpty) defaultPrinter = printers.first;
      }
      
      if (defaultPrinter != null) {
        await Printing.directPrintPdf(
          printer: defaultPrinter,
          onLayout: (_) async => pdfBytes,
        );
      }
    } else {
      await InvoicePdfGenerator.generateAndPrint(invoice, companyProfile);
    }
  }

  /// Enqueues Dot-Matrix print job to background print spooler queue
  static void printDotMatrixBackground({
    required SaleInvoice invoice,
    int columns = 80,
    String storeName = "SAHAKAR MEDICALS & SURGICALS",
    String storeAddress = "KALPETTA TOWN, WAYANAD",
    String headerTitle = "TAX INVOICE / CASH MEMO",
    String? printerIpOrPort,
  }) {
    PrintSpoolerService.enqueuePrintTask(() async {
      await printDotMatrix(
        invoice: invoice,
        columns: columns,
        storeName: storeName,
        storeAddress: storeAddress,
        headerTitle: headerTitle,
        printerIpOrPort: printerIpOrPort,
      );
    });
  }

  /// Enqueues PDF invoice print job to background print spooler queue
  static void printPdfInvoiceBackground({
    required SaleInvoice invoice,
    required CompanyProfile companyProfile,
    bool directPrint = false,
  }) {
    PrintSpoolerService.enqueuePrintTask(() async {
      await printPdfInvoice(
        invoice: invoice,
        companyProfile: companyProfile,
        directPrint: directPrint,
      );
    });
  }

  /// Interactive Modal for Counter Billing Checkout
  static Future<void> showPrintDialog({
    required BuildContext context,
    required SaleInvoice invoice,
    required CompanyProfile companyProfile,
    int dotMatrixColumns = 80,
  }) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: const Row(
          children: [
            Icon(Icons.print_rounded, color: Colors.blueGrey),
            SizedBox(width: 10),
            Text("Dispatch Invoice Print", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.receipt_long_rounded, color: Colors.orange.shade800),
              ),
              title: const Text("80mm Thermal POS Receipt", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text("Fast thermal receipt format (80mm / 3 inch)"),
              onTap: () async {
                Navigator.pop(ctx);
                final bytes = await ThermalReceiptGenerator.buildThermalReceipt(invoice, companyProfile);
                await Printing.layoutPdf(
                  onLayout: (_) async => bytes,
                  name: 'Thermal_Receipt_${invoice.entryNo}',
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.flash_on_rounded, color: Colors.green.shade700),
              ),
              title: const Text("Fast Dot Matrix Bill", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("Instant monospace continuous feed ($dotMatrixColumns Col)"),
              onTap: () {
                Navigator.pop(ctx);
                printDotMatrix(
                  invoice: invoice,
                  columns: dotMatrixColumns,
                  storeName: companyProfile.name.isNotEmpty ? companyProfile.name : "SAHAKAR MEDICALS & SURGICALS",
                  storeAddress: companyProfile.address.isNotEmpty ? companyProfile.address : "KALPETTA TOWN, WAYANAD",
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.picture_as_pdf_rounded, color: Colors.blue.shade700),
              ),
              title: const Text("Standard Graphical Invoice", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text("A4 / Half-sheet laser or digital copy"),
              onTap: () {
                Navigator.pop(ctx);
                printPdfInvoice(invoice: invoice, companyProfile: companyProfile);
              },
            ),
            const Divider(),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.remove_red_eye_rounded, color: Colors.purple.shade700),
              ),
              title: const Text("Professional Print Preview", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text("Inspect visual layout and pages"),
              onTap: () async {
                Navigator.pop(ctx);
                final doc = await InvoicePdfGenerator.buildPdfDocument(invoice, companyProfile);
                if (!context.mounted) return;
                showProfessionalPreview(
                  context: context, 
                  doc: doc, 
                  title: "Invoice Preview - ${invoice.entryNo}"
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Saves a PDF document to PC memory / disk via Windows File Picker
  static Future<void> savePdfToDisk(BuildContext context, pw.Document doc, String defaultFileName) async {
    try {
      final bytes = await doc.save();
      String cleanName = defaultFileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      if (!cleanName.toLowerCase().endsWith('.pdf')) {
        cleanName = '$cleanName.pdf';
      }

      String? outputPath = await FilePicker.saveFile(
        dialogTitle: 'Save PDF Document',
        fileName: cleanName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (outputPath != null) {
        if (!outputPath.toLowerCase().endsWith('.pdf')) {
          outputPath = '$outputPath.pdf';
        }
        final file = File(outputPath);
        await file.writeAsBytes(bytes);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                  const SizedBox(width: 10),
                  Expanded(child: Text("PDF saved successfully to:\n$outputPath")),
                ],
              ),
              backgroundColor: const Color(0xFF0F172A),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        AppDialogs.showFastDialog(
          context: context,
          title: "Save PDF Error",
          content: "Could not save PDF file: $e",
        );
      }
    }
  }

  /// Opens Gmail Compose in browser and copies PDF file to Clipboard for easy attachment
  static Future<void> openGmailWithPdf(BuildContext context, pw.Document doc, String subject) async {
    try {
      final bytes = await doc.save();
      Directory docsDir;
      try {
        docsDir = await getApplicationDocumentsDirectory();
      } catch (_) {
        docsDir = Directory.systemTemp;
      }

      final invFolder = Directory('${docsDir.path}${Platform.pathSeparator}Pharmacy_Invoices');
      if (!await invFolder.exists()) {
        await invFolder.create(recursive: true);
      }

      final cleanName = subject.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final pdfPath = '${invFolder.path}${Platform.pathSeparator}$cleanName.pdf';
      final file = File(pdfPath);
      await file.writeAsBytes(bytes);

      // Copy PDF file to Windows Clipboard (CF_HDROP)
      await WhatsAppService.copyFileToClipboard(pdfPath);

      // Open Gmail compose URL in PC default browser
      final encodedSub = Uri.encodeComponent(subject);
      final gmailUrl = "https://mail.google.com/mail/?view=cm&fs=1&tf=1&su=$encodedSub";

      if (Platform.isWindows) {
        final escapedUrl = gmailUrl.replaceAll("'", "''");
        await Process.run('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', "Start-Process '$escapedUrl'"]);
        Process.run('explorer.exe', ['/select,', pdfPath]);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.mail_rounded, color: Colors.lightBlueAccent, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Gmail Compose Opened!\nPDF file saved & copied to clipboard. Press Ctrl + V in Gmail to attach.",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF0F172A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Colors.lightBlueAccent, width: 1.5)),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        AppDialogs.showFastDialog(
          context: context,
          title: "Gmail Error",
          content: "Could not open Gmail: $e",
        );
      }
    }
  }

  /// Full-screen professional print preview modal with Save to Memory & Gmail options
  static void showProfessionalPreview({
    required BuildContext context,
    required pw.Document doc,
    String? title,
  }) {
    final String displayTitle = title ?? "Professional PDF Preview";

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.85,
          height: MediaQuery.of(context).size.height * 0.9,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade900,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf_rounded, color: Colors.amberAccent, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        displayTitle,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: () {
                        savePdfToDisk(context, doc, displayTitle);
                      },
                      icon: const Icon(Icons.save_alt_rounded, size: 18),
                      label: const Text("Save to Memory", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEA4335),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: () {
                        openGmailWithPdf(context, doc, displayTitle);
                      },
                      icon: const Icon(Icons.mail_rounded, size: 18),
                      label: const Text("Share via Gmail", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(ctx),
                      tooltip: "Close Preview",
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PdfPreview(
                  build: (format) => doc.save(),
                  allowPrinting: true,
                  allowSharing: true,
                  canChangePageFormat: true,
                  canChangeOrientation: true,
                  maxPageWidth: 700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Centralized printer dispatcher that routes print jobs based on active profile or options
Future<void> printWithCurrentProfile({
  required BuildContext context,
  required dynamic invoice,
  required CompanyProfile companyProfile,
  Future<pw.Document> Function()? a4PdfBuilder,
  bool isAutoGeneratedSupInv = false,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final String printMode = prefs.getString('printer_mode') ?? "dialog"; // "dialog", "a4", "thermal", "dot_matrix"

  if (printMode == "thermal") {
    final bytes = await ThermalReceiptGenerator.buildThermalReceipt(invoice, companyProfile);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Thermal_Receipt_${invoice.entryNo}',
    );
    return;
  }

  if (printMode == "a4") {
    pw.Document doc;
    if (a4PdfBuilder != null) {
      doc = await a4PdfBuilder();
    } else if (invoice is SaleInvoice) {
      doc = await InvoicePdfGenerator.buildPdfDocument(invoice, companyProfile);
    } else if (invoice is PurchaseEntry) {
      doc = await InvoicePdfGenerator.buildPurchasePdf(invoice, companyProfile, isAutoGenerated: isAutoGeneratedSupInv);
    } else {
      doc = await InvoicePdfGenerator.buildPdfDocument(invoice, companyProfile);
    }

    if (!context.mounted) return;
    PrinterService.showProfessionalPreview(
      context: context,
      doc: doc,
      title: "Invoice Preview - ${invoice.entryNo}",
    );
    return;
  }

  if (printMode == "dot_matrix" && invoice is SaleInvoice) {
    final int cols = prefs.getInt('printer_columns') ?? 80;
    await PrinterService.printDotMatrix(
      invoice: invoice,
      columns: cols,
      storeName: companyProfile.name.isNotEmpty ? companyProfile.name : "SAHAKAR MEDICALS & SURGICALS",
      storeAddress: companyProfile.address.isNotEmpty ? companyProfile.address : "KALPETTA TOWN, WAYANAD",
    );
    return;
  }

  // Default / "dialog": Show centralized print options modal
  if (invoice is SaleInvoice) {
    await PrinterService.showPrintDialog(
      context: context,
      invoice: invoice,
      companyProfile: companyProfile,
    );
  } else if (invoice is PurchaseEntry) {
    pw.Document doc;
    if (a4PdfBuilder != null) {
      doc = await a4PdfBuilder();
    } else {
      doc = await InvoicePdfGenerator.buildPurchasePdf(invoice, companyProfile, isAutoGenerated: isAutoGeneratedSupInv);
    }
    if (!context.mounted) return;
    PrinterService.showProfessionalPreview(
      context: context,
      doc: doc,
      title: "Purchase Entry Preview - ${invoice.entryNo}",
    );
  }
}
