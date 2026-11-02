import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/erp_models.dart';

/// Service providing direct, ultra-fast binary ESC/POS thermal receipt printing (<0.2s).
/// Bypasses PDF rendering pipeline to eliminate counter queues during peak billing.
class EscPosPrinterService {
  static final EscPosPrinterService instance = EscPosPrinterService._init();
  EscPosPrinterService._init();

  // ESC/POS Command Byte Constants
  static const List<int> cmdInit = [0x1B, 0x40]; // ESC @
  static const List<int> cmdAlignLeft = [0x1B, 0x61, 0x00]; // ESC a 0
  static const List<int> cmdAlignCenter = [0x1B, 0x61, 0x01]; // ESC a 1
  static const List<int> cmdAlignRight = [0x1B, 0x61, 0x02]; // ESC a 2
  static const List<int> cmdBoldOn = [0x1B, 0x45, 0x01]; // ESC E 1
  static const List<int> cmdBoldOff = [0x1B, 0x45, 0x00]; // ESC E 0
  static const List<int> cmdDoubleSize = [0x1D, 0x21, 0x11]; // GS ! 0x11
  static const List<int> cmdNormalSize = [0x1D, 0x21, 0x00]; // GS ! 0x00
  static const List<int> cmdPaperCut = [0x1D, 0x56, 0x42, 0x00]; // GS V 66 0
  static const List<int> cmdCashDrawer = [0x1B, 0x70, 0x00, 0x19, 0xFA]; // ESC p 0 25 250

  /// Converts sales invoice data into raw binary ESC/POS byte stream for 3-inch (80mm / 48 char) thermal printers
  Uint8List generateReceiptBytes({
    required CompanyProfile company,
    required String invoiceNo,
    required String dateStr,
    required String patientName,
    required String doctorName,
    required List<Map<String, dynamic>> items, // [{name, qty, mrp, rate, amount, batch, expiry}]
    required double totalAmount,
    required double totalDiscount,
    required double gstTotal,
    required String paymentMode,
    int widthChars = 48,
  }) {
    List<int> bytes = [];

    // Initialize
    bytes.addAll(cmdInit);

    // Header: Company Name & Address
    bytes.addAll(cmdAlignCenter);
    bytes.addAll(cmdBoldOn);
    bytes.addAll(cmdDoubleSize);
    bytes.addAll(_encodeString("${company.name}\n"));
    bytes.addAll(cmdNormalSize);
    bytes.addAll(cmdBoldOff);

    if (company.address.isNotEmpty) {
      bytes.addAll(_encodeString("${company.address}\n"));
    }
    if (company.phone.isNotEmpty) {
      bytes.addAll(_encodeString("Ph: ${company.phone}\n"));
    }
    if (company.gstIn.isNotEmpty) {
      bytes.addAll(_encodeString("GSTIN: ${company.gstIn} | DL: ${company.dlNumber}\n"));
    }

    bytes.addAll(_encodeString("-" * widthChars + "\n"));

    // Invoice Meta
    bytes.addAll(cmdAlignLeft);
    bytes.addAll(_encodeString('Inv No: $invoiceNo\nDate: $dateStr\n'));
    if (patientName.isNotEmpty) {
      bytes.addAll(_encodeString("Patient: $patientName\n"));
    }
    if (doctorName.isNotEmpty) {
      bytes.addAll(_encodeString("Doctor : $doctorName\n"));
    }

    bytes.addAll(_encodeString("-" * widthChars + "\n"));

    // Table Column Headers
    bytes.addAll(cmdBoldOn);
    bytes.addAll(_encodeString("Item Name           Batch   Qty   Rate    Amt\n"));
    bytes.addAll(cmdBoldOff);
    bytes.addAll(_encodeString("-" * widthChars + "\n"));

    // Table Item Rows
    for (var item in items) {
      String name = (item['name']?.toString() ?? '').trim();
      if (name.length > 19) name = name.substring(0, 19);

      String batch = (item['batch']?.toString() ?? '').trim();
      if (batch.length > 7) batch = batch.substring(0, 7);

      String qty = (item['qty']?.toString() ?? '1');
      String rate = (item['rate'] as num?)?.toStringAsFixed(2) ?? '0.00';
      String amt = (item['amount'] as num?)?.toStringAsFixed(2) ?? '0.00';

      String rowLine = 
        "${name.padRight(20)}${batch.padRight(8)}${qty.padLeft(4)}${rate.padLeft(7)}${amt.padLeft(8)}\n";

      bytes.addAll(_encodeString(rowLine));
    }

    bytes.addAll(_encodeString("-" * widthChars + "\n"));

    // Totals Section
    bytes.addAll(cmdAlignRight);
    bytes.addAll(cmdBoldOn);
    bytes.addAll(_encodeString("TOTAL AMOUNT: RS. ${totalAmount.toStringAsFixed(2)}\n"));
    bytes.addAll(cmdBoldOff);

    if (totalDiscount > 0) {
      bytes.addAll(_encodeString("You Saved: RS. ${totalDiscount.toStringAsFixed(2)}\n"));
    }
    bytes.addAll(_encodeString("Mode: $paymentMode | Incl. GST: RS. ${gstTotal.toStringAsFixed(2)}\n"));

    bytes.addAll(_encodeString("-" * widthChars + "\n"));

    // Footer
    bytes.addAll(cmdAlignCenter);
    bytes.addAll(_encodeString("Thank You! Get Well Soon.\n"));
    bytes.addAll(_encodeString("Powered by PharmaPro ERP\n\n\n"));

    // Cash Drawer Kick & Auto Paper Cut
    bytes.addAll(cmdCashDrawer);
    bytes.addAll(cmdPaperCut);

    return Uint8List.fromList(bytes);
  }

  /// Sends raw ESC/POS bytes directly over TCP Socket to network thermal printer (<0.2s)
  Future<bool> printDirectTcp({
    required Uint8List bytes,
    required String ipAddress,
    int port = 9100,
  }) async {
    try {
      final socket = await Socket.connect(ipAddress, port, timeout: const Duration(seconds: 3));
      socket.add(bytes);
      await socket.flush();
      await socket.close();
      debugPrint("ESC/POS direct TCP print job sent successfully to $ipAddress:$port");
      return true;
    } catch (e) {
      debugPrint("ESC/POS direct TCP print error: $e");
      return false;
    }
  }

  List<int> _encodeString(String input) {
    return utf8.encode(input);
  }
}
