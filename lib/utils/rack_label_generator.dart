import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart';
import '../models/erp_models.dart';

class RackLabelGenerator {
  /// Generates printable PDF document matching Rack Label format:
  /// Thick outer black box borders, thin orange inner grid lines,
  /// 2 columns of product names, and large bold Rack ID at bottom-right in Times New Roman.
  static Future<pw.Document> generatePdfLabels({
    required List<String> racks,
    required List<Product> productMaster,
    required String pharmacyName,
  }) async {
    final pdf = pw.Document();

    Map<String, List<String>> rackItems = {};
    for (var r in racks) {
      final items = productMaster
          .where((p) => p.rack == r)
          .map((p) => p.name.trim())
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      rackItems[r] = items;
    }

    final List<String> sortedRacks = List.from(racks);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        header: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                "PHARMA RACK LABELS - $pharmacyName",
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.black, font: pw.Font.timesBold()),
              ),
              pw.Text(
                "Cut along outer thick black borders to paste on physical boxes",
                style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700, font: pw.Font.times()),
              ),
            ],
          ),
        ),
        build: (pw.Context context) {
          List<pw.Widget> cardRows = [];
          for (int i = 0; i < sortedRacks.length; i += 2) {
            final rack1 = sortedRacks[i];
            final rack2 = (i + 1 < sortedRacks.length) ? sortedRacks[i + 1] : null;

            cardRows.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 12),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _buildPdfRackCardWidget(rack1, rackItems[rack1] ?? []),
                    if (rack2 != null)
                      _buildPdfRackCardWidget(rack2, rackItems[rack2] ?? [])
                    else
                      pw.SizedBox(width: 265, height: 160),
                  ],
                ),
              ),
            );
          }
          return cardRows;
        },
      ),
    );

    return pdf;
  }

  static pw.Widget _buildPdfRackCardWidget(String rackName, List<String> items) {
    final int total = items.length;
    final int col1Count = (total / 2).ceil();
    final col1 = items.take(col1Count).toList();
    final col2 = items.skip(col1Count).take(8).toList();

    const orangeColor = PdfColor.fromInt(0xFFFF9900);

    return pw.Container(
      width: 265,
      height: 160,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 2.5),
      ),
      child: pw.Column(
        children: List.generate(4, (r) {
          final p1 = r < col1.length ? col1[r] : "";
          final p2 = r < col2.length ? col2[r] : "";
          final isLastRow = (r == 3);

          return pw.Expanded(
            child: pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  bottom: isLastRow ? pw.BorderSide.none : const pw.BorderSide(color: orangeColor, width: 0.8),
                ),
              ),
              child: pw.Row(
                children: [
                  if (isLastRow && p1.isEmpty && p2.isEmpty)
                    pw.Expanded(
                      flex: 8,
                      child: pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(right: pw.BorderSide(color: orangeColor, width: 0.8)),
                        ),
                      ),
                    )
                  else ...[
                    // Col 1 Item
                    pw.Expanded(
                      flex: 4,
                      child: pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(right: pw.BorderSide(color: orangeColor, width: 0.8)),
                        ),
                        alignment: pw.Alignment.centerLeft,
                        child: pw.Text(
                          p1,
                          maxLines: 1,
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, font: pw.Font.timesBold()),
                        ),
                      ),
                    ),
                    // Col 2 Item
                    pw.Expanded(
                      flex: 4,
                      child: pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(right: pw.BorderSide(color: orangeColor, width: 0.8)),
                        ),
                        alignment: pw.Alignment.centerLeft,
                        child: pw.Text(
                          p2,
                          maxLines: 1,
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, font: pw.Font.timesBold()),
                        ),
                      ),
                    ),
                  ],
                  // Col 3: Rack Code placement on bottom row
                  pw.Expanded(
                    flex: 3,
                    child: isLastRow
                        ? pw.Container(
                            alignment: pw.Alignment.center,
                            child: pw.Text(
                              rackName,
                              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, font: pw.Font.timesBold()),
                            ),
                          )
                        : pw.Container(),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Opens interactive print preview or directly prints PDF rack cards
  static Future<void> printPdfLabels({
    required List<String> racks,
    required List<Product> productMaster,
    required String pharmacyName,
  }) async {
    final pdf = await generatePdfLabels(
      racks: racks,
      productMaster: productMaster,
      pharmacyName: pharmacyName,
    );
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Rack_Labels_$pharmacyName',
    );
  }

  /// Saves PDF rack cards to a chosen file path
  static Future<bool> savePdfLabelsToFile({
    required List<String> racks,
    required List<Product> productMaster,
    required String pharmacyName,
    required String savePath,
  }) async {
    final pdf = await generatePdfLabels(
      racks: racks,
      productMaster: productMaster,
      pharmacyName: pharmacyName,
    );
    final bytes = await pdf.save();
    final file = File(savePath);
    await file.writeAsBytes(bytes);
    return true;
  }

  /// Generates and exports Excel rack cards with user's customized formatting:
  /// - Thick solid black outer box borders, thin orange inner grid lines.
  /// - Times New Roman font for all text.
  /// - Left box in Columns B, C, D, E and Right box in Columns G, H, I, J.
  /// - Bottom line cells (B..D and G..I) merged on the last line of each rack card, with Rack ID on the right.
  /// - Exactly ONE empty row between vertically adjacent rack blocks.
  static Future<bool> exportExcelLabelsToFile({
    required List<String> racks,
    required List<Product> productMaster,
    required String savePath,
  }) async {
    var excel = Excel.createExcel();
    var sheet = excel['RACK'];
    excel.delete('Sheet1');

    Map<String, List<String>> rackItems = {};
    for (var r in racks) {
      final items = productMaster
          .where((p) => p.rack == r)
          .map((p) => p.name.trim())
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      rackItems[r] = items;
    }

    final sortedRacks = List<String>.from(racks);

    var thickBlack = Border(borderStyle: BorderStyle.Thick, borderColorHex: ExcelColor.black);
    var thinOrange = Border(borderStyle: BorderStyle.Thin, borderColorHex: ExcelColor.fromHexString('#FF9900'));

    // Track running row index (0-based)
    // Start at row 1 (which is Excel Row 2, leaving Row 1 as a 1-line top margin)
    int currentStartRow = 1;

    for (int blockIdx = 0; blockIdx < (sortedRacks.length / 2).ceil(); blockIdx++) {
      int i1 = blockIdx * 2;
      int i2 = i1 + 1;

      final rack1 = sortedRacks[i1];
      final rack2 = (i2 < sortedRacks.length) ? sortedRacks[i2] : null;

      final items1 = rackItems[rack1] ?? [];
      final items2 = rack2 != null ? (rackItems[rack2] ?? []) : <String>[];

      // Determine item columns for Left Box
      final mid1 = (items1.length / 2).ceil();
      final col1A = items1.take(mid1).toList();
      final col1B = items1.skip(mid1).take(8).toList();

      // Determine item columns for Right Box
      final mid2 = (items2.length / 2).ceil();
      final col2A = items2.take(mid2).toList();
      final col2B = items2.skip(mid2).take(8).toList();

      int maxItems = items1.length > items2.length ? items1.length : items2.length;
      int itemRowsNeeded = (maxItems / 2).ceil();
      // Box height: minimum 3 rows (2 item rows + 1 merged bottom row, or 3 item rows with rack ID on 3rd row)
      int boxHeight = itemRowsNeeded > 3 ? 4 : 3;

      int startRow = currentStartRow;

      // Populate Left Box (Cols 1..4 = B, C, D, E)
      for (int r = 0; r < boxHeight; r++) {
        int rIdx = startRow + r;
        bool isLastRow = (r == boxHeight - 1);

        for (int c = 1; c <= 4; c++) {
          var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rIdx));

          Border topB = (r == 0) ? thickBlack : thinOrange;
          Border bottomB = isLastRow ? thickBlack : thinOrange;
          Border leftB = (c == 1) ? thickBlack : thinOrange;
          Border rightB = (c == 4) ? thickBlack : thinOrange;

          bool isRackCodeCell = (c == 4 && isLastRow);

          String cellVal = "";
          if (isRackCodeCell) {
            cellVal = rack1;
          } else if (c == 1 && r < col1A.length) {
            cellVal = col1A[r];
          } else if (c == 2 && r < col1B.length) {
            cellVal = col1B[r];
          }

          // Always assign a TextCellValue so Excel generates cell XML with style index
          cell.value = TextCellValue(cellVal);

          cell.cellStyle = CellStyle(
            topBorder: topB,
            bottomBorder: bottomB,
            leftBorder: leftB,
            rightBorder: rightB,
            fontFamily: 'Times New Roman',
            bold: true,
            fontSize: isRackCodeCell ? 18 : 9,
            horizontalAlign: isRackCodeCell ? HorizontalAlign.Center : HorizontalAlign.Left,
            verticalAlign: VerticalAlign.Center,
          );
        }

        // Merge bottom line cells B..D if last row has no separate items
        if (isLastRow) {
          bool hasItemInB = r < col1A.length && col1A[r].isNotEmpty;
          bool hasItemInC = r < col1B.length && col1B[r].isNotEmpty;
          if (!hasItemInB && !hasItemInC) {
            sheet.merge(
              CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rIdx),
              CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rIdx),
            );
          }
        }
      }

      // Populate Right Box (Cols 6..9 = G, H, I, J)
      if (rack2 != null) {
        for (int r = 0; r < boxHeight; r++) {
          int rIdx = startRow + r;
          bool isLastRow = (r == boxHeight - 1);

          for (int c = 6; c <= 9; c++) {
            var cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rIdx));

            Border topB = (r == 0) ? thickBlack : thinOrange;
            Border bottomB = isLastRow ? thickBlack : thinOrange;
            Border leftB = (c == 6) ? thickBlack : thinOrange;
            Border rightB = (c == 9) ? thickBlack : thinOrange;

            bool isRackCodeCell = (c == 9 && isLastRow);

            String cellVal = "";
            if (isRackCodeCell) {
              cellVal = rack2;
            } else if (c == 6 && r < col2A.length) {
              cellVal = col2A[r];
            } else if (c == 7 && r < col2B.length) {
              cellVal = col2B[r];
            }

            // Always assign a TextCellValue so Excel generates cell XML with style index
            cell.value = TextCellValue(cellVal);

            cell.cellStyle = CellStyle(
              topBorder: topB,
              bottomBorder: bottomB,
              leftBorder: leftB,
              rightBorder: rightB,
              fontFamily: 'Times New Roman',
              bold: true,
              fontSize: isRackCodeCell ? 18 : 9,
              horizontalAlign: isRackCodeCell ? HorizontalAlign.Center : HorizontalAlign.Left,
              verticalAlign: VerticalAlign.Center,
            );
          }

          if (isLastRow) {
            bool hasItemInG = r < col2A.length && col2A[r].isNotEmpty;
            bool hasItemInH = r < col2B.length && col2B[r].isNotEmpty;
            if (!hasItemInG && !hasItemInH) {
              sheet.merge(
                CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rIdx),
                CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rIdx),
              );
            }
          }
        }
      }

      // Move next block start row: boxHeight rows for current box + 1 EMPTY ROW between racks!
      currentStartRow += boxHeight + 1;
    }

    final bytes = excel.save();
    if (bytes != null) {
      final file = File(savePath);
      await file.writeAsBytes(bytes);
      return true;
    }
    return false;
  }
}
