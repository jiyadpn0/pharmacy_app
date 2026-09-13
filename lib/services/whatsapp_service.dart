import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/erp_models.dart';
import '../utils/app_dialogs.dart';
import '../utils/invoice_pdf_generator.dart';

class WhatsAppService {
  /// Sanitizes phone numbers by removing non-digit characters and adding India prefix (91) if 10 digits.
  static String sanitizePhoneNumber(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'\D'), '');
    if (cleaned.length == 10) {
      cleaned = '91$cleaned';
    }
    return cleaned;
  }

  /// Sends a formatted Purchase Order to a Wholesaler/Supplier via WhatsApp.
  static Future<bool> sendPurchaseOrder({
    required BuildContext context,
    required String supplierName,
    required String supplierMobile,
    required String companyName,
    required List<dynamic> items,
  }) async {
    if (items.isEmpty) {
      AppDialogs.showFastDialog(
        context: context,
        title: "No Items",
        content: "There are no draft purchase items to dispatch via WhatsApp.",
      );
      return false;
    }

    String phone = sanitizePhoneNumber(supplierMobile);

    final StringBuffer sb = StringBuffer();
    sb.writeln("*PURCHASE ORDER FROM ${companyName.toUpperCase()}*");
    sb.writeln("-----------------------------------------");
    sb.writeln("Supplier: *${supplierName.toUpperCase()}*");
    sb.writeln("Date: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}");
    sb.writeln("-----------------------------------------");
    sb.writeln("Please arrange dispatch for the following items:\n");

    int count = 1;
    for (var item in items) {
      String name = "Item";
      int qty = 0;

      if (item is Map) {
        name = (item['name'] ?? item['productName'] ?? "Item").toString();
        qty = (item['qty'] as num?)?.toInt() ?? (item['strips'] as num?)?.toInt() ?? 0;
      } else {
        try {
          name = (item.name ?? item.productName ?? "Item").toString();
        } catch (_) {}

        try {
          qty = (item.qty as num?)?.toInt() ?? 0;
        } catch (_) {
          try {
            qty = (item.displayOrderQty as num?)?.toInt() ?? 0;
          } catch (_) {}
        }
      }

      if (qty > 0) {
        sb.writeln("$count. *$name* - Qty: *$qty strips/packs*");
        count++;
      }
    }

    sb.writeln("\n-----------------------------------------");
    sb.writeln("Thank you! Sent via Pharmacy ERP.");

    return await _launchWhatsAppUrl(context: context, phone: phone, text: sb.toString());
  }

  /// Copies a local file onto the Windows System Clipboard as a File Drop List (CF_HDROP)
  /// so pressing Ctrl+V in WhatsApp Web/Desktop instantly pastes/attaches the actual PDF file!
  static Future<bool> copyFileToClipboard(String filePath) async {
    if (!Platform.isWindows) return false;
    try {
      final escapedPath = filePath.replaceAll("'", "''");
      final psScript = "\$col = New-Object System.Collections.Specialized.StringCollection; \$null = \$col.Add('$escapedPath'); Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Clipboard]::SetFileDropList(\$col)";
      final result = await Process.run('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', psScript]);
      return result.exitCode == 0;
    } catch (e) {
      debugPrint("Error copying file to clipboard: $e");
      return false;
    }
  }

  /// Prompts the user to enter or confirm receiver's WhatsApp phone number.
  static Future<String?> promptReceiverPhone({
    required BuildContext context,
    required String title,
    required String defaultPhone,
    required String recipientName,
  }) async {
    final phoneCtrl = TextEditingController(text: defaultPhone);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.phone_outlined, color: Color(0xFF25D366)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (recipientName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  "Recipient: ${recipientName.toUpperCase()}",
                  style: const TextStyle(color: Colors.tealAccent, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                labelText: "Receiver's WhatsApp Number",
                labelStyle: const TextStyle(color: Colors.tealAccent),
                hintText: "e.g. 9876543210",
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                prefixIcon: const Icon(Icons.phone, color: Colors.tealAccent),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 10),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.tealAccent, size: 16),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "The PDF will be automatically copied to Clipboard. Once WhatsApp opens, press Ctrl + V in the chat box to attach the document!",
                    style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx, phoneCtrl.text.trim()),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text("SEND WHATSAPP", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Sends a Sales Invoice summary receipt AND generates + copies PDF to Clipboard for instant Ctrl+V attachment.
  static Future<bool> sendSalesInvoiceWithPdf({
    required BuildContext context,
    required SaleInvoice invoice,
    required CompanyProfile companyProfile,
  }) async {
    String custName = invoice.patient.trim().isEmpty ? "Valued Customer" : invoice.patient.trim();

    final enteredPhone = await promptReceiverPhone(
      context: context,
      title: "Send Invoice PDF via WhatsApp",
      defaultPhone: invoice.mobile,
      recipientName: custName,
    );

    if (enteredPhone == null || enteredPhone.trim().isEmpty) return false;
    String custMobile = sanitizePhoneNumber(enteredPhone.trim());

    // 1. Generate & Save PDF Document
    String? pdfPath;
    try {
      final pdfDoc = await InvoicePdfGenerator.buildPdfDocument(invoice, companyProfile);
      final pdfBytes = await pdfDoc.save();

      Directory? docsDir;
      try {
        docsDir = await getApplicationDocumentsDirectory();
      } catch (_) {
        docsDir = Directory.systemTemp;
      }

      final invFolder = Directory('${docsDir.path}${Platform.pathSeparator}Pharmacy_Invoices');
      if (!await invFolder.exists()) {
        await invFolder.create(recursive: true);
      }

      String cleanEntry = (invoice.entryNo.isEmpty ? "DRAFT" : invoice.entryNo).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      pdfPath = '${invFolder.path}${Platform.pathSeparator}Invoice_$cleanEntry.pdf';
      final pdfFile = File(pdfPath);
      await pdfFile.writeAsBytes(pdfBytes);

      // Copy PDF file to Clipboard (CF_HDROP) for instant Ctrl+V in WhatsApp
      await copyFileToClipboard(pdfPath);

      // Highlight PDF in Windows Explorer as additional fallback
      if (Platform.isWindows) {
        Process.run('explorer.exe', ['/select,', pdfPath]);
      }
    } catch (e) {
      debugPrint("PDF Generation for WhatsApp Error: $e");
    }

    // 2. Format Clean Text Message
    final StringBuffer sb = StringBuffer();
    sb.writeln("*TAX INVOICE RECEIPT*");
    sb.writeln("*${companyProfile.name.toUpperCase()}*");
    sb.writeln("-----------------------------------------");
    sb.writeln("Invoice No: *${invoice.entryNo.isEmpty ? "DRAFT" : invoice.entryNo}*");
    sb.writeln("Customer: *${custName.toUpperCase()}*");
    sb.writeln("Date: ${DateFormat('yyyy-MM-dd').format(invoice.date)}");
    sb.writeln("-----------------------------------------");

    if (invoice.items.isNotEmpty) {
      sb.writeln("*Items Purchased:*");
      for (var it in invoice.items) {
        if (it.product.name.trim().isNotEmpty && it.qty > 0) {
          sb.writeln("• ${it.product.name} (Qty: ${it.qty}) - ₹${it.total.toStringAsFixed(2)}");
        }
      }
      sb.writeln("-----------------------------------------");
    }

    sb.writeln("*GRAND TOTAL: ₹${invoice.grandTotal.toStringAsFixed(2)}*");
    sb.writeln("-----------------------------------------");
    if (pdfPath != null) {
      sb.writeln("*Detailed PDF Invoice copied to Clipboard. Press Ctrl+V in chat to attach.*");
    }
    sb.writeln("Thank you for your visit! Wish you good health.");
    if (companyProfile.phone.isNotEmpty) {
      sb.writeln("Contact us: ${companyProfile.phone}");
    }

    // 3. Launch WhatsApp URL
    bool launched = await _launchWhatsAppUrl(context: context, phone: custMobile, text: sb.toString());
    if (!context.mounted) return false;

    if (launched && pdfPath != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.content_paste_go_rounded, color: Colors.tealAccent, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  "PDF Invoice Copied to Clipboard!\nPress Ctrl + V in the WhatsApp chat box to attach the file.",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFF25D366), width: 1.5)),
          duration: const Duration(seconds: 8),
        ),
      );
    }

    return launched;
  }

  /// Sends a Sales Return credit note receipt AND generates + copies PDF to Clipboard for instant Ctrl+V attachment.
  static Future<bool> sendSalesReturnWithPdf({
    required BuildContext context,
    required SaleReturnInvoice returnInvoice,
    required String customerMobile,
    required CompanyProfile companyProfile,
  }) async {
    String custName = returnInvoice.patient.trim().isEmpty ? "Valued Customer" : returnInvoice.patient.trim();

    final enteredPhone = await promptReceiverPhone(
      context: context,
      title: "Send Sales Return PDF via WhatsApp",
      defaultPhone: customerMobile,
      recipientName: custName,
    );

    if (enteredPhone == null || enteredPhone.trim().isEmpty) return false;
    String custMobile = sanitizePhoneNumber(enteredPhone.trim());

    // 1. Generate & Save PDF Document for Sales Return
    String? pdfPath;
    try {
      final pdfDoc = await InvoicePdfGenerator.buildSaleReturnPdf(returnInvoice, companyProfile);
      final pdfBytes = await pdfDoc.save();

      Directory? docsDir;
      try {
        docsDir = await getApplicationDocumentsDirectory();
      } catch (_) {
        docsDir = Directory.systemTemp;
      }

      final invFolder = Directory('${docsDir.path}${Platform.pathSeparator}Pharmacy_Invoices');
      if (!await invFolder.exists()) {
        await invFolder.create(recursive: true);
      }

      String cleanEntry = (returnInvoice.entryNo.isEmpty ? "RETURN_DRAFT" : returnInvoice.entryNo).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      pdfPath = '${invFolder.path}${Platform.pathSeparator}Sales_Return_$cleanEntry.pdf';
      final pdfFile = File(pdfPath);
      await pdfFile.writeAsBytes(pdfBytes);

      // Copy PDF file to Clipboard (CF_HDROP) for instant Ctrl+V in WhatsApp
      await copyFileToClipboard(pdfPath);

      // Highlight PDF in Windows Explorer as additional fallback
      if (Platform.isWindows) {
        Process.run('explorer.exe', ['/select,', pdfPath]);
      }
    } catch (e) {
      debugPrint("PDF Generation for WhatsApp Sales Return Error: $e");
    }

    // 2. Format Clean Text Message
    final StringBuffer sb = StringBuffer();
    sb.writeln("*SALES RETURN / CREDIT NOTE*");
    sb.writeln("*${companyProfile.name.toUpperCase()}*");
    sb.writeln("-----------------------------------------");
    sb.writeln("Return Entry No: *${returnInvoice.entryNo.isEmpty ? "DRAFT" : returnInvoice.entryNo}*");
    if (returnInvoice.originalInvoiceNo.isNotEmpty) {
      sb.writeln("Original Invoice: *${returnInvoice.originalInvoiceNo}*");
    }
    sb.writeln("Customer: *${custName.toUpperCase()}*");
    sb.writeln("Date: ${DateFormat('yyyy-MM-dd').format(returnInvoice.date)}");
    sb.writeln("-----------------------------------------");

    if (returnInvoice.items.isNotEmpty) {
      sb.writeln("*Returned Items:*");
      for (var it in returnInvoice.items) {
        if (it.product.name.trim().isNotEmpty && it.qty > 0) {
          sb.writeln("• ${it.product.name} (Qty: ${it.qty}) - ₹${it.total.toStringAsFixed(2)}");
        }
      }
      sb.writeln("-----------------------------------------");
    }

    sb.writeln("*TOTAL CREDIT AMOUNT: ₹${returnInvoice.grandTotal.toStringAsFixed(2)}*");
    sb.writeln("-----------------------------------------");
    if (pdfPath != null) {
      sb.writeln("*Sales Return PDF Credit Note copied to Clipboard. Press Ctrl+V in chat to attach.*");
    }
    sb.writeln("Thank you!");
    if (companyProfile.phone.isNotEmpty) {
      sb.writeln("Contact us: ${companyProfile.phone}");
    }

    // 3. Launch WhatsApp URL
    bool launched = await _launchWhatsAppUrl(context: context, phone: custMobile, text: sb.toString());
    if (!context.mounted) return false;

    if (launched && pdfPath != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.content_paste_go_rounded, color: Colors.tealAccent, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Sales Return PDF Copied to Clipboard!\nPress Ctrl + V in the WhatsApp chat box to attach the document.",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFF25D366), width: 1.5)),
          duration: const Duration(seconds: 8),
        ),
      );
    }

    return launched;
  }

  /// Sends a Daily Business Summary report to the pharmacy owner's WhatsApp
  static Future<bool> sendDailyClosingSummary({
    required BuildContext context,
    required String ownerPhone,
    required CompanyProfile companyProfile,
    required DateTime date,
    required double totalSales,
    required int totalInvoices,
    required double cashReceived,
    required double upiReceived,
    required double cardReceived,
    required double creditSales,
  }) async {
    final StringBuffer sb = StringBuffer();
    sb.writeln("*DAILY CLOSING BUSINESS SUMMARY*");
    sb.writeln("*${companyProfile.name.toUpperCase()}*");
    sb.writeln("Date: ${DateFormat('yyyy-MM-dd').format(date)}");
    sb.writeln("-----------------------------------------");
    sb.writeln("Total Bills Issued: *$totalInvoices*");
    sb.writeln("Total Sales Revenue: *₹${totalSales.toStringAsFixed(2)}*");
    sb.writeln("-----------------------------------------");
    sb.writeln("Cash Collections: ₹${cashReceived.toStringAsFixed(2)}");
    sb.writeln("UPI / Online: ₹${upiReceived.toStringAsFixed(2)}");
    sb.writeln("Card Collections: ₹${cardReceived.toStringAsFixed(2)}");
    sb.writeln("Credit Outstanding: ₹${creditSales.toStringAsFixed(2)}");
    sb.writeln("-----------------------------------------");
    sb.writeln("Report Generated: ${DateFormat('hh:mm a').format(DateTime.now())}");

    return await _launchWhatsAppUrl(context: context, phone: ownerPhone, text: sb.toString());
  }

  /// Backup legacy overload method for simple text dispatch
  static Future<bool> sendSalesInvoice({
    required BuildContext context,
    required String customerName,
    required String customerMobile,
    required String invoiceNo,
    required double grandTotal,
    required String companyName,
    required String companyPhone,
    List<SaleItem>? items,
  }) async {
    final inv = SaleInvoice(
      entryNo: invoiceNo,
      date: DateTime.now(),
      customerAcc: "Cash",
      patient: customerName,
      mobile: customerMobile,
      doctor: "",
      items: items ?? [],
      subTotal: grandTotal,
      discount: 0,
      grandTotal: grandTotal,
      taxType: "Gst",
    );
    final comp = CompanyProfile(name: companyName, phone: companyPhone);
    return await sendSalesInvoiceWithPdf(context: context, invoice: inv, companyProfile: comp);
  }

  static Future<bool> _launchWhatsAppUrl({
    required BuildContext context,
    required String phone,
    required String text,
  }) async {
    final encodedText = Uri.encodeComponent(text);
    final urlStr = phone.isNotEmpty
        ? "https://wa.me/$phone?text=$encodedText"
        : "https://wa.me/?text=$encodedText";

    try {
      if (Platform.isWindows) {
        // Use PowerShell Start-Process to guarantee opening in PC's Default Browser (Chrome, Edge, etc.)
        final escapedUrl = urlStr.replaceAll("'", "''");
        final psCommand = "Start-Process '$escapedUrl'";
        final result = await Process.run('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', psCommand]);
        if (result.exitCode != 0) {
          // Fallback to cmd start
          await Process.run('cmd', ['/c', 'start', '""', '"$urlStr"'], runInShell: true);
        }
        return true;
      } else if (Platform.isMacOS) {
        await Process.run('open', [urlStr]);
        return true;
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [urlStr]);
        return true;
      } else {
        await Process.run('cmd', ['/c', 'start', '""', '"$urlStr"'], runInShell: true);
        return true;
      }
    } catch (e) {
      if (context.mounted) {
        AppDialogs.showFastDialog(
          context: context,
          title: "WhatsApp Dispatch Error",
          content: "Unable to launch WhatsApp web/desktop link in default browser.\n\nDetails: $e",
        );
      }
      return false;
    }
  }
}
