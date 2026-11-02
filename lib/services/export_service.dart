import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import '../models/product_ranking.dart';

class ExportService {
  static final ExportService instance = ExportService._internal();
  ExportService._internal();

  Uint8List? exportProductRankingToExcel(
    List<ProductRanking> rankings,
    List<Map<String, dynamic>> customMetricColumns, {
    bool showRanking = true,
    bool showMonths = true,
  }) {
    try {
      var excel = Excel.createExcel();
      Sheet sheet = excel['Product Ranking'];
      excel.delete('Sheet1');

      List<CellValue> header = [
        TextCellValue('ID'),
        TextCellValue('Product Name'),
        TextCellValue('Pack'),
        TextCellValue('Category'),
        TextCellValue('Rack'),
        TextCellValue('MRP'),
        TextCellValue('Purchase Rate'),
        TextCellValue('Generic Name'),
        TextCellValue('Preferred Wholesale'),
        TextCellValue('Current Stock'),
      ];

      if (showRanking) {
        header.add(TextCellValue('Rank Score'));
      }

      sheet.appendRow(header);

      for (var r in rankings) {
        List<CellValue> row = [
          TextCellValue(r.id),
          TextCellValue(r.name),
          IntCellValue(r.pack),
          TextCellValue(r.category),
          TextCellValue(r.rack),
          DoubleCellValue(r.mrp),
          DoubleCellValue(r.pRate),
          TextCellValue(r.genericName),
          TextCellValue(r.preferredWholesale),
          DoubleCellValue(r.currentStock),
        ];

        if (showRanking) {
          row.add(DoubleCellValue(r.weightedScore));
        }

        sheet.appendRow(row);
      }

      final bytes = excel.save();
      return bytes != null ? Uint8List.fromList(bytes) : null;
    } catch (e) {
      debugPrint("Excel Export Error: $e");
      return null;
    }
  }
}
