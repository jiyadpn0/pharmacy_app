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
    final file = File(path);
    if (!file.existsSync()) {
      return {'success': false, 'message': 'File not found.'};
    }

    final bytes = file.readAsBytesSync();
    if (bytes.isEmpty) {
      return {'success': false, 'message': 'File is empty.'};
    }

    // 1. Lightning-fast byte newline counter (< 1ms)
    int totalRowsFound = 0;
    for (int i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0x0A) totalRowsFound++;
    }
    if (totalRowsFound == 0) totalRowsFound = 1;

    // 2. Fast preview read: Parse max 30 rows only (< 1ms)
    final rawRows = _getRawRowsFromFile(path, maxRows: 30);
    if (rawRows.isEmpty) {
      return {'success': false, 'message': 'No data found in file.'};
    }

    int headerRowIdx = findExcelHeaderRowIndex(rawRows);

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
      if (rowData.values.any((v) => v.trim().isNotEmpty)) {
        fetched.add(rowData);
      }
    }

    return {
      'success': true,
      'headers': header,
      'fetched': fetched,
      'totalRows': totalRowsFound,
    };
  }

  static List<Map<String, dynamic>> _parseExcelIsolate(String path) {
    final rawRows = _getRawRowsFromFile(path);
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

  static List<List<String>> _parseExcelRawRowsIsolate(String path) {
    return _getRawRowsFromFile(path);
  }

  // --- ⚡ MULTI-FORMAT UNIVERSAL EXCEL & CSV ENGINE ---

  static List<List<String>> _getRawRowsFromFile(String path, {int maxRows = 0}) {
    try {
      final file = File(path);
      if (!file.existsSync()) return [];

      Uint8List bytes = file.readAsBytesSync();
      if (bytes.isEmpty) return [];

      // Signature Checks
      bool isZipXlsx = bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04;
      bool isBiff2 = bytes.length >= 2 && bytes[0] == 0x09 && bytes[1] == 0x00;
      bool isOle2Biff8 = bytes.length >= 8 && bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0;

      if (isZipXlsx) {
        try {
          final rows = _parseXlsxBytes((maxRows > 0) ? file.readAsBytesSync() : bytes, maxRows: maxRows);
          if (rows.isNotEmpty) return rows;
        } catch (_) {}
      }

      if (isBiff2) {
        final rows = _parseBiff2Bytes(bytes, maxRows: maxRows);
        if (rows.isNotEmpty) return rows;
      }

      if (isOle2Biff8) {
        final rows = _parseOle2Bytes(bytes, maxRows: maxRows);
        if (rows.isNotEmpty) return rows;
      }

      Uint8List parseBytes = (maxRows > 0 && bytes.length > 65536) ? bytes.sublist(0, 65536) : bytes;

      // Fallback: Disguised HTML table / SpreadsheetML XML / Delimited CSV
      return _parseDisguisedOrCsvBytes(parseBytes, maxRows: maxRows);
    } catch (e) {
      debugPrint("Error reading raw Excel rows: $e");
      return [];
    }
  }

  static List<List<String>> _parseXlsxBytes(Uint8List bytes, {int maxRows = 0}) {
    var excel = Excel.decodeBytes(bytes);
    List<List<String>> results = [];
    for (var tableKey in excel.tables.keys) {
      var table = excel.tables[tableKey];
      if (table == null || table.rows.isEmpty) continue;
      for (var row in table.rows) {
        List<String> rowValues = [];
        for (var cell in row) {
          rowValues.add(_getCellValue(cell?.value));
        }
        if (rowValues.any((e) => e.trim().isNotEmpty)) {
          results.add(rowValues);
          if (maxRows > 0 && results.length >= maxRows) break;
        }
      }
      if (results.isNotEmpty) break;
    }
    return results;
  }

  static List<List<String>> _parseBiff2Bytes(Uint8List bytes, {int maxRows = 0}) {
    ByteData bd = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
    int pos = 0;
    Map<int, Map<int, String>> rows = {};
    int maxRow = -1;
    int maxCol = -1;

    while (pos + 4 <= bytes.length) {
      int opcode = bd.getUint16(pos, Endian.little);
      int length = bd.getUint16(pos + 2, Endian.little);
      pos += 4;
      if (pos + length > bytes.length) break;

      if (opcode == 0x0004 && length >= 8) { // LABEL Record
        int r = bd.getUint16(pos, Endian.little);
        int c = bd.getUint16(pos + 2, Endian.little);
        int strLen = bd.getUint8(pos + 7);
        if (8 + strLen <= length) {
          String val = String.fromCharCodes(bytes.sublist(pos + 8, pos + 8 + strLen));
          rows.putIfAbsent(r, () => {})[c] = _cleanString(val);
          if (r > maxRow) maxRow = r;
          if (c > maxCol) maxCol = c;
        }
      } else if (opcode == 0x0003 && length >= 15) { // NUMBER Record
        int r = bd.getUint16(pos, Endian.little);
        int c = bd.getUint16(pos + 2, Endian.little);
        double val = bd.getFloat64(pos + 7, Endian.little);
        String valStr = val == val.roundToDouble() ? val.toInt().toString() : val.toString();
        rows.putIfAbsent(r, () => {})[c] = valStr;
        if (r > maxRow) maxRow = r;
        if (c > maxCol) maxCol = c;
      }
      pos += length;
      if (maxRows > 0 && rows.length >= maxRows + 5) break;
    }

    List<List<String>> table = [];
    for (int r = 0; r <= maxRow; r++) {
      List<String> rowData = [];
      if (rows.containsKey(r)) {
        for (int c = 0; c <= maxCol; c++) {
          rowData.add(rows[r]![c] ?? "");
        }
      }
      if (rowData.isNotEmpty && rowData.any((e) => e.trim().isNotEmpty)) {
        table.add(rowData);
        if (maxRows > 0 && table.length >= maxRows) break;
      }
    }
    return table;
  }

  static List<List<String>> _parseOle2Bytes(Uint8List bytes, {int maxRows = 0}) {
    ByteData bd = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
    int pos = 0;

    // 1. Scan for Shared String Table (SST record 0x00FC)
    List<String> sstStrings = [];
    while (pos + 4 <= bytes.length) {
      int opcode = bd.getUint16(pos, Endian.little);
      int length = bd.getUint16(pos + 2, Endian.little);
      if (opcode == 0x00FC && pos + 4 + length <= bytes.length) {
        int sstPos = pos + 4;
        if (length >= 8) {
          int cstUnique = bd.getUint32(sstPos + 4, Endian.little);
          int p = sstPos + 8;
          for (int i = 0; i < cstUnique && p < sstPos + length; i++) {
            if (p + 3 > sstPos + length) break;
            int cch = bd.getUint16(p, Endian.little);
            int flags = bd.getUint8(p + 2);
            p += 3;
            bool isUtf16 = (flags & 0x01) != 0;
            int runCount = (flags & 0x08) != 0 ? bd.getUint16(p, Endian.little) : 0;
            if ((flags & 0x08) != 0) p += 2;
            int cbExtRst = (flags & 0x04) != 0 ? bd.getUint32(p, Endian.little) : 0;
            if ((flags & 0x04) != 0) p += 4;

            String str = "";
            if (!isUtf16) {
              if (p + cch <= bytes.length) {
                str = String.fromCharCodes(bytes.sublist(p, p + cch));
                p += cch;
              }
            } else {
              if (p + cch * 2 <= bytes.length) {
                List<int> units = [];
                for (int u = 0; u < cch; u++) {
                  units.add(bd.getUint16(p + u * 2, Endian.little));
                }
                str = String.fromCharCodes(units);
                p += cch * 2;
              }
            }
            p += runCount * 4 + cbExtRst;
            sstStrings.add(_cleanString(str));
          }
        }
        break;
      }
      pos += 4 + length;
      if (length <= 0) pos++;
    }

    // 2. Scan cell records: LABELSST (0x00FD), LABEL (0x0004/0x0204), NUMBER (0x0003/0x0203), RK (0x027E)
    pos = 0;
    Map<int, Map<int, String>> rows = {};
    int maxRow = -1;
    int maxCol = -1;

    while (pos + 4 <= bytes.length) {
      int opcode = bd.getUint16(pos, Endian.little);
      int length = bd.getUint16(pos + 2, Endian.little);
      int recData = pos + 4;
      pos += 4 + length;
      if (length <= 0) { pos++; continue; }
      if (recData + length > bytes.length) break;

      if (opcode == 0x00FD && length >= 10) { // LABELSST
        int r = bd.getUint16(recData, Endian.little);
        int c = bd.getUint16(recData + 2, Endian.little);
        int sstIdx = bd.getUint32(recData + 6, Endian.little);
        if (sstIdx < sstStrings.length) {
          rows.putIfAbsent(r, () => {})[c] = sstStrings[sstIdx];
          if (r > maxRow) maxRow = r;
          if (c > maxCol) maxCol = c;
        }
      } else if ((opcode == 0x0004 || opcode == 0x0204) && length >= 8) { // LABEL
        int r = bd.getUint16(recData, Endian.little);
        int c = bd.getUint16(recData + 2, Endian.little);
        int strLen = bd.getUint16(recData + 6, Endian.little);
        if (recData + 8 + strLen <= bytes.length) {
          String val = String.fromCharCodes(bytes.sublist(recData + 8, recData + 8 + strLen));
          rows.putIfAbsent(r, () => {})[c] = _cleanString(val);
          if (r > maxRow) maxRow = r;
          if (c > maxCol) maxCol = c;
        }
      } else if ((opcode == 0x0003 || opcode == 0x0203) && length >= 14) { // NUMBER
        int r = bd.getUint16(recData, Endian.little);
        int c = bd.getUint16(recData + 2, Endian.little);
        double val = bd.getFloat64(recData + (length >= 15 ? 7 : 6), Endian.little);
        String valStr = val == val.roundToDouble() ? val.toInt().toString() : val.toString();
        rows.putIfAbsent(r, () => {})[c] = valStr;
        if (r > maxRow) maxRow = r;
        if (c > maxCol) maxCol = c;
      } else if (opcode == 0x027E && length >= 10) { // RK
        int r = bd.getUint16(recData, Endian.little);
        int c = bd.getUint16(recData + 2, Endian.little);
        int rk = bd.getUint32(recData + 6, Endian.little);
        String valStr = _decodeRk(rk);
        rows.putIfAbsent(r, () => {})[c] = valStr;
        if (r > maxRow) maxRow = r;
        if (c > maxCol) maxCol = c;
      }

      if (maxRows > 0 && rows.length >= maxRows + 5) break;
    }

    List<List<String>> table = [];
    for (int r = 0; r <= maxRow; r++) {
      List<String> rowData = [];
      if (rows.containsKey(r)) {
        for (int c = 0; c <= maxCol; c++) {
          rowData.add(rows[r]![c] ?? "");
        }
      }
      if (rowData.isNotEmpty && rowData.any((e) => e.trim().isNotEmpty)) {
        table.add(rowData);
        if (maxRows > 0 && table.length >= maxRows) break;
      }
    }
    return table;
  }

  static String _decodeRk(int rk) {
    bool isInt = (rk & 0x02) != 0;
    bool div100 = (rk & 0x01) != 0;
    num value;
    if (isInt) {
      value = (rk >> 2);
    } else {
      int raw64 = (rk & 0xFFFFFFFC) << 32;
      ByteData tmp = ByteData(8);
      tmp.setUint64(0, raw64, Endian.big);
      value = tmp.getFloat64(0, Endian.big);
    }
    if (div100) value = value / 100.0;
    return value == value.roundToDouble() ? value.toInt().toString() : value.toString();
  }

  static List<List<String>> _parseDisguisedOrCsvBytes(Uint8List bytes, {int maxRows = 0}) {
    String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      try {
        content = latin1.decode(bytes);
      } catch (_) {
        content = String.fromCharCodes(bytes);
      }
    }

    if (content.startsWith('\uFEFF')) {
      content = content.substring(1);
    }

    // 1. SpreadsheetML XML check
    if (content.contains('<Workbook') && content.contains('<Worksheet')) {
      List<List<String>> rows = [];
      final rowRegExp = RegExp(r'<Row.*?>([\s\S]*?)</Row>', caseSensitive: false);
      final cellRegExp = RegExp(r'<Cell.*?>[\s\S]*?<Data.*?>([\s\S]*?)</Data>[\s\S]*?</Cell>|<Cell.*?/>', caseSensitive: false);
      final htmlTagRegExp = RegExp(r'<[^>]*>');

      for (final rowMatch in rowRegExp.allMatches(content)) {
        String rowContent = rowMatch.group(1) ?? "";
        List<String> rowData = [];
        for (final cellMatch in cellRegExp.allMatches(rowContent)) {
          String cellVal = cellMatch.group(1) ?? "";
          cellVal = cellVal.replaceAll(htmlTagRegExp, '').replaceAll('&nbsp;', ' ').trim();
          rowData.add(_cleanString(cellVal));
        }
        if (rowData.isNotEmpty && rowData.any((e) => e.trim().isNotEmpty)) {
          rows.add(rowData);
          if (maxRows > 0 && rows.length >= maxRows) break;
        }
      }
      if (rows.isNotEmpty) return rows;
    }

    // 2. HTML <table> check
    if (content.toLowerCase().contains('<table') && content.toLowerCase().contains('<tr')) {
      List<List<String>> rows = [];
      final trRegExp = RegExp(r'<tr.*?>(.*?)</tr>', caseSensitive: false, dotAll: true);
      final tdRegExp = RegExp(r'<t[dh].*?>(.*?)</t[dh]>', caseSensitive: false, dotAll: true);
      final htmlTagRegExp = RegExp(r'<[^>]*>', multiLine: true);

      for (final trMatch in trRegExp.allMatches(content)) {
        String trContent = trMatch.group(1) ?? "";
        List<String> rowData = [];
        for (final tdMatch in tdRegExp.allMatches(trContent)) {
          String cellContent = tdMatch.group(1) ?? "";
          cellContent = cellContent.replaceAll(htmlTagRegExp, '').replaceAll('&nbsp;', ' ').trim();
          rowData.add(_cleanString(cellContent));
        }
        if (rowData.isNotEmpty && rowData.any((e) => e.trim().isNotEmpty)) {
          rows.add(rowData);
          if (maxRows > 0 && rows.length >= maxRows) break;
        }
      }
      if (rows.isNotEmpty) return rows;
    }

    // 3. Delimited CSV / TSV text parsing
    return _nativeCsvParse(content, maxRows: maxRows);
  }

  static final RegExp _controlCharsRegExp = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]');

  static List<List<String>> _nativeCsvParse(String content, {int maxRows = 0}) {
    if (content.startsWith('\uFEFF')) {
      content = content.substring(1);
    }

    int sampleEnd = content.indexOf('\n');
    for (int i = 0; i < 4 && sampleEnd != -1; i++) {
      sampleEnd = content.indexOf('\n', sampleEnd + 1);
    }
    String sample = sampleEnd == -1 ? content : content.substring(0, sampleEnd);

    int tabCount = 0, semiCount = 0, commaCount = 0;
    for (int code in sample.codeUnits) {
      if (code == 9) {
        tabCount++;
      } else if (code == 59) semiCount++;
      else if (code == 44) commaCount++;
    }

    int delimiterCode = 44; // ','
    if (tabCount > commaCount && tabCount > semiCount) {
      delimiterCode = 9; // '\t'
    } else if (semiCount > commaCount && semiCount > tabCount) {
      delimiterCode = 59; // ';'
    }

    final List<List<String>> rows = [];
    final List<int> units = content.codeUnits;
    final int length = units.length;

    bool inQuotes = false;
    int cellStart = 0;
    List<String> currentRow = [];

    for (int i = 0; i < length; i++) {
      int charCode = units[i];

      if (charCode == 34) { // '"'
        inQuotes = !inQuotes;
      } else if (charCode == delimiterCode && !inQuotes) {
        String cell = content.substring(cellStart, i);
        if (cell.contains('"')) {
          cell = cell.replaceAll('"', '').trim();
        }
        currentRow.add(_cleanString(cell));
        cellStart = i + 1;
      } else if ((charCode == 10 || charCode == 13) && !inQuotes) { // '\n' or '\r'
        if (i > cellStart || currentRow.isNotEmpty) {
          String cell = content.substring(cellStart, i);
          if (cell.contains('"')) {
            cell = cell.replaceAll('"', '').trim();
          }
          currentRow.add(_cleanString(cell));
        }

        if (currentRow.any((e) => e.isNotEmpty)) {
          rows.add(currentRow);
          if (maxRows > 0 && rows.length >= maxRows) break;
        }

        currentRow = [];
        if (charCode == 13 && i + 1 < length && units[i + 1] == 10) {
          i++;
        }
        cellStart = i + 1;
      }
    }

    if (cellStart < length || currentRow.isNotEmpty) {
      if (maxRows == 0 || rows.length < maxRows) {
        if (cellStart < length) {
          String cell = content.substring(cellStart, length);
          if (cell.contains('"')) {
            cell = cell.replaceAll('"', '').trim();
          }
          currentRow.add(_cleanString(cell));
        }
        if (currentRow.any((e) => e.isNotEmpty)) {
          rows.add(currentRow);
        }
      }
    }

    return rows;
  }

  static String _cleanString(String raw) {
    if (raw.isEmpty) return "";
    String s = cleanInvoiceNo(raw);
    
    // Strip trailing .0 from Excel number parsing
    if (s.endsWith(".0")) {
      s = s.substring(0, s.length - 2);
    }
    
    if (s.contains('\uFEFF') || s.contains('\u200B')) {
      s = s.replaceAll('\uFEFF', '').replaceAll('\u200B', '');
    }
    if (_controlCharsRegExp.hasMatch(s)) {
      s = s.replaceAll(_controlCharsRegExp, '');
    }
    return s.trim();
  }

  static String _getCellValue(dynamic val) {
    if (val == null) return "";

    dynamic realValue = val;
    try {
      if (val is CellValue) {
        realValue = (val as dynamic).value;
      }
    } catch (_) {
      realValue = val;
    }

    if (realValue == null) return "";

    // Prevent integers turning into floats (e.g. 1024 -> "1024.0" -> "1024")
    if (realValue is num && realValue == realValue.toInt()) {
      return realValue.toInt().toString();
    }

    if (realValue is DateTime) {
      return "${realValue.year.toString().padLeft(4, '0')}-${realValue.month.toString().padLeft(2, '0')}-${realValue.day.toString().padLeft(2, '0')}";
    }

    return _cleanString(realValue.toString());
  }

  static String getExcelColumnLetter(int index) {
    String letter = "";
    int temp = index;
    while (temp >= 0) {
      letter = String.fromCharCode((temp % 26) + 65) + letter;
      temp = (temp ~/ 26) - 1;
    }
    return "$letter:$letter";
  }

  static int findExcelHeaderRowIndex(List<List<String>> rawRows) {
    if (rawRows.isEmpty) return 0;

    const headerKeywords = [
      'product', 'name', 'item', 'particulars', 'description',
      'packing', 'pack', 'unit', 'batch', 'expiry', 'exp',
      'mrp', 'rate', 'price', 'cost', 'p.rate', 's.rate',
      'qty', 'quantity', 'stock', 'rack', 'hsn', 'hsncode',
      'gst', 'tax', 'disc', 'total', 'amount', 'date', 'invoice', 'entry'
    ];

    int bestHeaderIdx = -1;
    int maxScore = -1;
    int scanLimit = rawRows.length < 15 ? rawRows.length : 15;

    for (int r = 0; r < scanLimit; r++) {
      final currentRow = rawRows[r];

      // Rule 1: Must have text in the row directly below
      bool hasDataBelow = false;
      if (r + 1 < rawRows.length) {
        hasDataBelow = rawRows[r + 1].any((cell) => cell.trim().isNotEmpty);
      }
      if (!hasDataBelow) continue; // Skip if row below is blank

      // Require at least 2 non-empty cells
      int nonBlankCols = currentRow.where((cell) => cell.trim().isNotEmpty).length;
      if (nonBlankCols < 2) continue;

      // Confidence scoring
      int keywordHits = 0;
      for (var cell in currentRow) {
        String clean = cell.toLowerCase().trim();
        if (clean.isNotEmpty && headerKeywords.any((kw) => clean.contains(kw))) {
          keywordHits++;
        }
      }

      int score = (keywordHits * 10) + nonBlankCols;
      if (score > maxScore) {
        maxScore = score;
        bestHeaderIdx = r;
      }
    }

    return bestHeaderIdx != -1 ? bestHeaderIdx : 0;
  }
}
