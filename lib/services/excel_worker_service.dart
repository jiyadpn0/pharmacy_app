import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import '../utils/app_formatters.dart';

class ExcelWorkerService {
  /// Offloads heavy Excel decoding and row extraction to a background isolate
  static Future<List<Map<String, dynamic>>> parseExcelFileInBackground(String filePath) async {
    return await compute(_parseExcelIsolate, filePath);
  }

  /// Offloads raw rows extraction (matrix of strings) to a background isolate
  static Future<List<List<String>>> parseExcelRawRowsInBackground(String filePath) async {
    return await compute(_parseExcelRawRowsIsolate, filePath);
  }

  /// Offloads ultra-fast preview analysis (reading only headers and first 10 rows + total rows count) to background isolate
  static Future<Map<String, dynamic>> analyzeExcelPreviewInBackground(String filePath) async {
    return await compute(_analyzeExcelPreviewIsolate, filePath);
  }

  static Map<String, dynamic> _analyzeExcelPreviewIsolate(String path) {
    if (path.toLowerCase().endsWith('.csv')) {
      final content = _readCsvContent(path);
      final rawRows = _nativeCsvParse(content);
      if (rawRows.isEmpty) return {'success': false, 'message': 'No data found in file.'};
      
      int totalRowsFound = rawRows.length;
      int headerRowIdx = 0;
      int maxCols = 0;
      for (int r = 0; r < (rawRows.length < 10 ? rawRows.length : 10); r++) {
        int nonEmtpy = rawRows[r].where((cell) => cell.trim().isNotEmpty).length;
        if (nonEmtpy > maxCols) {
          maxCols = nonEmtpy;
          headerRowIdx = r;
        }
      }

      final header = rawRows[headerRowIdx].map((e) => e.trim()).toList();
      while (header.isNotEmpty && header.last.isEmpty) {
        header.removeLast();
      }

      List<Map<String, String>> fetched = [];
      for (int i = headerRowIdx + 1; i < rawRows.length && fetched.length < 10; i++) {
        final row = rawRows[i];
        if (row.isEmpty) continue;
        Map<String, String> rowData = {};
        for (int j = 0; j < header.length; j++) {
          if (j < row.length) {
            rowData[header[j]] = row[j];
          }
        }
        fetched.add(rowData);
      }

      return {
        'success': true,
        'headers': header,
        'fetched': fetched,
        'totalRows': totalRowsFound,
      };
    }

    final bytes = File(path).readAsBytesSync();
    final excel = Excel.decodeBytes(bytes);

    for (var table in excel.tables.keys) {
      final sheet = excel.tables[table];
      if (sheet == null || sheet.maxRows == 0) continue;

      int totalRowsFound = sheet.maxRows;
      final allRows = sheet.rows;
      if (allRows.isEmpty) continue;

      int headerRowIdx = 0;
      int maxCols = 0;
      int checkLimit = allRows.length < 10 ? allRows.length : 10;
      for (int r = 0; r < checkLimit; r++) {
        int nonEmtpy = allRows[r].where((cell) => cell?.value != null && cell!.value.toString().trim().isNotEmpty).length;
        if (nonEmtpy > maxCols) {
          maxCols = nonEmtpy;
          headerRowIdx = r;
        }
      }

      final headerRow = allRows[headerRowIdx];
      List<String> headersFound = headerRow.map((e) => _getCellValue(e?.value).trim()).toList();
      while (headersFound.isNotEmpty && headersFound.last.isEmpty) {
        headersFound.removeLast();
      }

      List<Map<String, String>> fetched = [];
      for (int i = headerRowIdx + 1; i < allRows.length && fetched.length < 10; i++) {
        final row = allRows[i];
        if (row.isEmpty) continue;
        Map<String, String> rowData = {};
        for (int j = 0; j < headersFound.length; j++) {
          if (j < row.length) {
            rowData[headersFound[j]] = _getCellValue(row[j]?.value);
          }
        }
        fetched.add(rowData);
      }

      return {
        'success': true,
        'headers': headersFound,
        'fetched': fetched,
        'totalRows': totalRowsFound,
      };
    }

    return {'success': false, 'message': 'No tables found in Excel file.'};
  }

  static String _readCsvContent(String path) {
    final bytes = File(path).readAsBytesSync();
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  static List<Map<String, dynamic>> _parseExcelIsolate(String path) {
    if (path.toLowerCase().endsWith('.csv')) {
      return _parseCsvToMapList(path);
    }

    final bytes = File(path).readAsBytesSync();
    final excel = Excel.decodeBytes(bytes);
    List<Map<String, dynamic>> results = [];

    for (var table in excel.tables.keys) {
      final sheet = excel.tables[table];
      if (sheet == null || sheet.maxRows <= 1) continue;

      final allRows = sheet.rows;
      if (allRows.isEmpty) continue;

      // Smart header row finder: scan first 6 rows for table header keywords
      int headerRowIdx = 0;
      for (int r = 0; r < allRows.length && r < 6; r++) {
        final rowStr = allRows[r].map((e) => _getCellValue(e?.value).toLowerCase()).join(' ');
        if (rowStr.contains('entry no') || rowStr.contains('invoice') || rowStr.contains('product') || rowStr.contains('date')) {
          headerRowIdx = r;
          break;
        }
      }

      final header = allRows[headerRowIdx].map((e) => _getCellValue(e?.value).toLowerCase().trim()).toList();
      
      for (int i = headerRowIdx + 1; i < allRows.length; i++) {
        final row = allRows[i];
        if (row.isEmpty) continue;

        Map<String, dynamic> rowMap = {};
        for (int j = 0; j < header.length; j++) {
          if (j < row.length && row[j] != null) {
            rowMap[header[j]] = _getCellValue(row[j]!.value);
          }
        }
        results.add(rowMap);
      }
    }
    return results;
  }

  static List<List<String>> _parseExcelRawRowsIsolate(String path) {
    if (path.toLowerCase().endsWith('.csv')) {
      final content = _readCsvContent(path);
      return _nativeCsvParse(content);
    }

    final bytes = File(path).readAsBytesSync();
    final excel = Excel.decodeBytes(bytes);
    List<List<String>> results = [];

    for (var table in excel.tables.keys) {
      final sheet = excel.tables[table];
      if (sheet == null || sheet.maxRows == 0) continue;

      // Access sheet.rows only once to prevent memory exhaustion
      final allRows = sheet.rows;
      for (final row in allRows) {
        List<String> rowValues = [];
        for (var cell in row) {
          rowValues.add(_getCellValue(cell?.value));
        }
        results.add(rowValues);
      }
    }
    return results;
  }

  static List<Map<String, dynamic>> _parseCsvToMapList(String path) {
    final content = _readCsvContent(path);
    final rawRows = _nativeCsvParse(content);
    if (rawRows.length <= 1) return [];

    int headerRowIdx = 0;
    for (int r = 0; r < rawRows.length && r < 6; r++) {
      final rowStr = rawRows[r].map((e) => e.toLowerCase()).join(' ');
      if (rowStr.contains('entry no') || rowStr.contains('invoice') || rowStr.contains('product') || rowStr.contains('date')) {
        headerRowIdx = r;
        break;
      }
    }

    final header = rawRows[headerRowIdx].map((e) => e.toLowerCase().trim()).toList();
    List<Map<String, dynamic>> results = [];

    for (int i = headerRowIdx + 1; i < rawRows.length; i++) {
      final row = rawRows[i];
      if (row.isEmpty) continue;

      Map<String, dynamic> rowMap = {};
      for (int j = 0; j < header.length; j++) {
        if (j < row.length) {
          rowMap[header[j]] = row[j];
        }
      }
      results.add(rowMap);
    }
    return results;
  }

  static List<List<String>> _nativeCsvParse(String content) {
    final firstLine = content.split(RegExp(r'\r?\n')).first;
    final tabCount = '\t'.allMatches(firstLine).length;
    final semiCount = ';'.allMatches(firstLine).length;
    final commaCount = ','.allMatches(firstLine).length;

    String delimiter = ',';
    if (tabCount > commaCount && tabCount > semiCount) {
      delimiter = '\t';
    } else if (semiCount > commaCount && semiCount > tabCount) {
      delimiter = ';';
    }

    List<List<String>> rows = [];
    bool inQuotes = false;
    List<String> currentRow = [];
    StringBuffer currentCell = StringBuffer();

    for (int i = 0; i < content.length; i++) {
      String char = content[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == delimiter && !inQuotes) {
        currentRow.add(_getCellValue(currentCell.toString()));
        currentCell.clear();
      } else if (char == '\n' && !inQuotes) {
        currentRow.add(_getCellValue(currentCell.toString()));
        if (currentRow.any((e) => e.trim().isNotEmpty)) {
          rows.add(currentRow);
        }
        currentRow = [];
        currentCell.clear();
      } else if (char != '\r') {
        currentCell.write(char);
      }
    }
    if (currentCell.isNotEmpty || currentRow.isNotEmpty) {
      currentRow.add(_getCellValue(currentCell.toString()));
      if (currentRow.any((e) => e.trim().isNotEmpty)) {
        rows.add(currentRow);
      }
    }
    return rows;
  }

  static String _getCellValue(dynamic val) {
    if (val == null) return "";

    if (val is DateTime) {
      return "${val.year.toString().padLeft(4, '0')}-${val.month.toString().padLeft(2, '0')}-${val.day.toString().padLeft(2, '0')} ${val.hour.toString().padLeft(2, '0')}:${val.minute.toString().padLeft(2, '0')}:${val.second.toString().padLeft(2, '0')}";
    }

    try {
      dynamic v = val;
      final typeStr = v.runtimeType.toString();
      if (typeStr.contains('Date') || typeStr.contains('Time')) {
        int? y = v.year as int?;
        int? m = v.month as int?;
        int? d = v.day as int?;
        int h = (v.hour as int?) ?? 0;
        int min = (v.minute as int?) ?? 0;
        int sec = (v.second as int?) ?? 0;

        if (y != null && m != null && d != null && y > 1900) {
          return "${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')} ${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}";
        }
      }
    } catch (_) {}

    return cleanInvoiceNo(val);
  }
}
