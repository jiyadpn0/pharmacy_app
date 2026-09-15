import 'package:intl/intl.dart';
import '../models/erp_models.dart';

class DotMatrixFormatter {
  static String _clampLeft(String text, int width) {
    if (text.length > width) return text.substring(0, width);
    return text.padLeft(width);
  }

  static String _clampRight(String text, int width) {
    if (text.length > width) return text.substring(0, width);
    return text.padRight(width);
  }

  /// Word-aware wrapping engine to prevent breaking medicine names mid-word
  static List<String> _wrapText(String text, int maxWidth) {
    if (text.isEmpty) return [""];
    List<String> lines = [];
    List<String> words = text.split(' ');
    String currentLine = "";

    for (String word in words) {
      if ((currentLine + word).length > maxWidth) {
        if (currentLine.isNotEmpty) {
          lines.add(currentLine.trim());
          currentLine = "";
        }
        while (word.length > maxWidth) {
          lines.add(word.substring(0, maxWidth));
          word = word.substring(maxWidth);
        }
        currentLine = "$word ";
      } else {
        currentLine += "$word ";
      }
    }
    if (currentLine.trim().isNotEmpty) {
      lines.add(currentLine.trim());
    }
    return lines;
  }

  /// Generates a monospace text stream for ESC/POS and Dot Matrix printers
  static String generateInvoiceText({
    required SaleInvoice invoice,
    int columns = 80,
    String storeName = "SAHAKAR MEDICALS & SURGICALS",
    String storeAddress = "KALPETTA TOWN, WAYANAD",
    String headerTitle = "TAX INVOICE / CASH MEMO",
  }) {
    StringBuffer buffer = StringBuffer();
    String divider = "".padRight(columns, '-');

    String centerText(String text) {
      if (text.length >= columns) return text.substring(0, columns);
      int leftPadding = ((columns - text.length) / 2).floor();
      return text.padLeft(text.length + leftPadding).padRight(columns);
    }

    // 1. STORE HEADER
    buffer.writeln(divider);
    buffer.writeln(centerText(storeName.toUpperCase()));
    buffer.writeln(centerText(storeAddress.toUpperCase()));
    buffer.writeln(centerText(headerTitle.toUpperCase()));
    buffer.writeln(divider);

    // 2. INVOICE META DATA (SANITIZED PADDING)
    String invStr = "INV NO: ${invoice.entryNo}";
    String dateStr = "DATE: ${DateFormat('dd/MM/yyyy hh:mm a').format(invoice.date)}";
    if (invStr.length + dateStr.length >= columns) {
      buffer.writeln(invStr);
      buffer.writeln(dateStr.padLeft(columns));
    } else {
      buffer.writeln(invStr.padRight(columns - dateStr.length) + dateStr);
    }

    String patStr = "PATIENT: ${invoice.patient.toUpperCase()}";
    String docStr = "DOC: ${invoice.doctor.toUpperCase()}";
    if (patStr.length + docStr.length >= columns) {
      int maxPat = (columns * 0.6).toInt();
      if (patStr.length > maxPat) patStr = "${patStr.substring(0, maxPat - 2)}..";
      int remainingForDoc = columns - patStr.length - 1;
      if (docStr.length > remainingForDoc) docStr = "${docStr.substring(0, remainingForDoc - 2)}..";
    }
    
    int padWidth = columns - docStr.length;
    buffer.writeln(patStr.padRight(padWidth > 0 ? padWidth : patStr.length) + docStr);
    buffer.writeln(divider);

    // 3. TABLE COLUMN SIZING (Strictly clamped for 80 and 136 columns)
    int wSl = columns >= 136 ? 3 : 2;
    int wHsn = columns >= 136 ? 8 : 5;
    int wBatch = columns >= 136 ? 10 : 6;
    int wExp = columns >= 136 ? 6 : 5;
    int wQty = columns >= 136 ? 5 : 3;
    int wMrp = columns >= 136 ? 9 : 7;
    int wDisc = columns >= 136 ? 8 : 6;
    int wRate = columns >= 136 ? 9 : 7;
    int wTot = columns >= 136 ? 10 : 8;

    int fixedWidthSum = wSl + wHsn + wBatch + wExp + wQty + wMrp + wDisc + wRate + wTot + 9;
    int wItem = columns - fixedWidthSum;
    if (wItem < 12) wItem = 12;

    String th = "${_clampRight("SL", wSl)} "
        "${_clampRight("HSN", wHsn)} "
        "${_clampRight("PRODUCT / MFR", wItem)} "
        "${_clampRight("BATCH", wBatch)} "
        "${_clampRight("EXP", wExp)} "
        "${_clampLeft("QTY", wQty)} "
        "${_clampLeft("MRP", wMrp)} "
        "${_clampLeft("DISC", wDisc)} "
        "${_clampLeft("RATE", wRate)} "
        "${_clampLeft("TOTAL", wTot)}";

    buffer.writeln(th);
    buffer.writeln(divider);

    // 4. ITEM ROWS
    for (int i = 0; i < invoice.items.length; i++) {
      final item = invoice.items[i];
      List<String> nameLines = _wrapText(item.product.name.toUpperCase(), wItem);

      if (item.product.manufacturer.isNotEmpty) {
        nameLines.add("[MFR: ${item.product.manufacturer.toUpperCase()}]");
      }

      String sl = _clampRight((i + 1).toString(), wSl);
      String hsn = _clampRight((item.product.hsnCode.isNotEmpty ? item.product.hsnCode : "3004"), wHsn);
      String nameChunk = _clampRight(nameLines[0], wItem);
      String batch = _clampRight(item.product.batch.toUpperCase(), wBatch);
      String exp = _clampRight(item.product.expiry, wExp);
      String qty = _clampLeft(item.qty.toString(), wQty);

      double packSize = item.product.packSize > 0 ? item.product.packSize.toDouble() : 1.0;
      double stripMrp = item.mrp > 0 ? item.mrp : (item.product.mrp * packSize);

      double itemDisc = item.discAmt > 0
          ? item.discAmt
          : ((stripMrp * item.qty * item.discPercent) / 100.0);

      double rate = item.sRate > 0 ? item.sRate : item.product.salePrice;

      String mrpStr = _clampLeft(stripMrp.toStringAsFixed(2), wMrp);
      String discStr = _clampLeft(itemDisc.toStringAsFixed(2), wDisc);
      String rateStr = _clampLeft(rate.toStringAsFixed(2), wRate);
      String totStr = _clampLeft(item.total.toStringAsFixed(2), wTot);

      buffer.writeln("$sl $hsn $nameChunk $batch $exp $qty $mrpStr $discStr $rateStr $totStr");

      for (int lineIdx = 1; lineIdx < nameLines.length; lineIdx++) {
        String emptyPrefix = "${_clampRight("", wSl)} ${_clampRight("", wHsn)}";
        String spilledName = _clampRight(nameLines[lineIdx], wItem);
        buffer.writeln("$emptyPrefix $spilledName");
      }
    }
    buffer.writeln(divider);

    // 5. STATUTORY GST SUMMARY & TOTALS
    Map<double, double> taxableBase = {};
    Map<double, double> cgstMap = {};
    Map<double, double> sgstMap = {};

    for (var item in invoice.items) {
      if (item.gstPercent > 0) {
        double base = item.total;
        taxableBase[item.gstPercent] = (taxableBase[item.gstPercent] ?? 0) + base;
        cgstMap[item.gstPercent] = (cgstMap[item.gstPercent] ?? 0) + item.cgstAmt;
        sgstMap[item.gstPercent] = (sgstMap[item.gstPercent] ?? 0) + item.sgstAmt;
      }
    }

    if (taxableBase.isNotEmpty) {
      buffer.writeln("GST BREAKDOWN (INCLUDED IN MRP):");
      buffer.writeln("RATE%   TAXABLE       CGST       SGST");
      taxableBase.forEach((rate, base) {
        String r = "${rate.toStringAsFixed(1)}%".padRight(7);
        String b = base.toStringAsFixed(2).padLeft(9);
        String c = (cgstMap[rate] ?? 0).toStringAsFixed(2).padLeft(10);
        String s = (sgstMap[rate] ?? 0).toStringAsFixed(2).padLeft(10);
        buffer.writeln("$r $b $c $s");
      });
      buffer.writeln(divider);
    }

    String subTotStr  = "SUBTOTAL:    ${invoice.subTotal.toStringAsFixed(2)}";
    String totDiscStr = "TOTAL DISC:  ${invoice.discount.toStringAsFixed(2)}";
    String grandStr   = "GRAND TOTAL: ${invoice.grandTotal.toStringAsFixed(2)}";

    buffer.writeln(subTotStr.padLeft(columns));
    if (invoice.discount > 0) buffer.writeln(totDiscStr.padLeft(columns));
    buffer.writeln(grandStr.padLeft(columns));
    buffer.writeln(divider);

    buffer.writeln(centerText("THANK YOU! VISIT AGAIN - COMPUTERIZED BILLING"));
    buffer.writeln(centerText("Medicines once sold will not be taken back"));
    buffer.writeln(divider);

    // 6. TIME (LEFT) AND PHARMACIST SIGNATURE (RIGHT)
    String timeStr = "TIME: ${DateFormat('hh:mm a').format(invoice.date)}";
    String sigStr = "PHARMACIST SIGNATURE";
    int footerPad = columns - timeStr.length - sigStr.length;
    if (footerPad > 0) {
      buffer.writeln(timeStr + "".padLeft(footerPad) + sigStr);
    } else {
      buffer.writeln(timeStr);
      buffer.writeln(sigStr.padLeft(columns));
    }

    return buffer.toString().trimRight();
  }
}