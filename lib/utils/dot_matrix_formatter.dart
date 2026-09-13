import 'package:intl/intl.dart';
import '../models/erp_models.dart';

class DotMatrixFormatter {
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

    // 3. TABLE COLUMN SIZING
    int wSl = 2;
    int wHsn = 6;
    int wBatch = 7;
    int wExp = 5;
    int wQty = 3;
    int wMrp = 7;
    int wDisc = 6;
    int wRate = 7;
    int wTot = 8;
    int wItem = columns - (wSl + wHsn + wBatch + wExp + wQty + wMrp + wDisc + wRate + wTot + 9);
    if (wItem < 12) wItem = 12;

    String th = "${"SL".padRight(wSl)} "
        "${"HSN".padRight(wHsn)} "
        "${"PRODUCT / MFR".padRight(wItem)} "
        "${"BATCH".padRight(wBatch)} "
        "${"EXP".padRight(wExp)} "
        "${"QTY".padLeft(wQty)} "
        "${"MRP".padLeft(wMrp)} "
        "${"DISC".padLeft(wDisc)} "
        "${"RATE".padLeft(wRate)} "
        "${"TOTAL".padLeft(wTot)}";

    buffer.writeln(th);
    buffer.writeln(divider);

    // 4. ITEM ROWS
    for (int i = 0; i < invoice.items.length; i++) {
      final item = invoice.items[i];
      List<String> nameLines = _wrapText(item.product.name.toUpperCase(), wItem);

      if (item.product.manufacturer.isNotEmpty) {
        nameLines.add("[MFR: ${item.product.manufacturer.toUpperCase()}]");
      }

      String sl = (i + 1).toString().padRight(wSl);
      String hsn = (item.product.hsnCode.isNotEmpty ? item.product.hsnCode : "3004").padRight(wHsn);
      if (hsn.length > wHsn) hsn = hsn.substring(0, wHsn);

      String nameChunk = nameLines[0].padRight(wItem);

      String batch = item.product.batch.toUpperCase();
      if (batch.length > wBatch) {
        batch = batch.substring(0, wBatch);
      } else {
        batch = batch.padRight(wBatch);
      }

      String exp = item.product.expiry;
      if (exp.length > wExp) {
        exp = exp.substring(0, wExp);
      } else {
        exp = exp.padRight(wExp);
      }

      String qty = item.qty.toString().padLeft(wQty);

      double packSize = item.product.packSize > 0 ? item.product.packSize.toDouble() : 1.0;
      double stripMrp = item.mrp > 0 ? item.mrp : (item.product.mrp * packSize);

      double itemDisc = item.discAmt > 0
          ? item.discAmt
          : ((stripMrp * item.qty * item.discPercent) / 100.0);

      double rate = item.sRate > 0 ? item.sRate : item.product.salePrice;

      String mrpStr = stripMrp.toStringAsFixed(2).padLeft(wMrp);
      String discStr = itemDisc.toStringAsFixed(2).padLeft(wDisc);
      String rateStr = rate.toStringAsFixed(2).padLeft(wRate);
      String totStr = item.total.toStringAsFixed(2).padLeft(wTot);

      buffer.writeln("$sl $hsn $nameChunk $batch $exp $qty $mrpStr $discStr $rateStr $totStr");

      for (int lineIdx = 1; lineIdx < nameLines.length; lineIdx++) {
        String emptyPrefix = "${"".padRight(wSl)} ${"".padRight(wHsn)}";
        String spilledName = nameLines[lineIdx].padRight(wItem);
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