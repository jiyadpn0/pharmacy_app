import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// --- SHARED DATA STRUCTURES ---

class IntPair {
  final int row;
  final int col;
  const IntPair(this.row, this.col);
  
  @override
  bool operator ==(Object other) => other is IntPair && other.row == row && other.col == col;
  
  @override
  int get hashCode => Object.hash(row, col);
}

// --- SHARED TEXT FORMATTERS ---

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.length > 4) text = text.substring(0, 4);

    String res = "";
    for (int i = 0; i < text.length; i++) {
      if (i == 0) {
        // First digit of month cannot be > 1
        int d = int.tryParse(text[i]) ?? 0;
        if (d > 1) {
          res = "0$d/"; // Auto-pad if user types '5' for month (becomes '05/')
          continue;
        }
      }
      if (i == 1) {
        // If first digit was '1', second digit cannot be > 2 (Max month 12)
        if (text[0] == '1') {
          int d = int.tryParse(text[i]) ?? 0;
          if (d > 2) text = "${text[0]}2"; // Cap at 12
        }
      }
      res += text[i];
      if (i == 1 && text.length > 2) res += "/";
    }

    return TextEditingValue(
      text: res,
      selection: TextSelection.collapsed(offset: res.length),
    );
  }
}

/// ERP-grade Expiry TextEditingController that maintains a fixed 5-character
/// "--/--" centered watermark mask overlay (Photos 1 -> 5 behavior).
class ExpiryTextEditingController extends TextEditingController {
  ExpiryTextEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final rawText = text;
    // Extract digits only
    final digits = rawText.replaceAll(RegExp(r'[^0-9]'), '');

    final baseStyle = style ?? const TextStyle(color: Colors.black, fontWeight: FontWeight.bold);
    final normalStyle = baseStyle;
    final watermarkStyle = baseStyle.copyWith(
      color: (baseStyle.color ?? Colors.black).withValues(alpha: 0.38),
      fontWeight: FontWeight.normal,
    );

    if (digits.isEmpty) {
      // Photo 1: |--/--
      return TextSpan(text: "--/--", style: watermarkStyle);
    }

    if (digits.length == 1) {
      // Photo 2: 0|/--
      return TextSpan(
        children: [
          TextSpan(text: digits[0], style: normalStyle),
          TextSpan(text: "/--", style: watermarkStyle),
        ],
      );
    }

    if (digits.length == 2) {
      // Photo 3: 01|/--
      final monthStr = digits.substring(0, 2);
      return TextSpan(
        children: [
          TextSpan(text: monthStr, style: normalStyle),
          TextSpan(text: "/--", style: watermarkStyle),
        ],
      );
    }

    if (digits.length == 3) {
      // Photo 4: 01/2|-
      final monthStr = digits.substring(0, 2);
      final yearFirst = digits.substring(2, 3);
      return TextSpan(
        children: [
          TextSpan(text: "$monthStr/$yearFirst", style: normalStyle),
          TextSpan(text: "-", style: watermarkStyle),
        ],
      );
    }

    // Photo 5: 01/28|
    final monthStr = digits.substring(0, 2);
    final yearStr = digits.substring(2, 4);
    return TextSpan(
      text: "$monthStr/$yearStr",
      style: normalStyle,
    );
  }
}

// --- GLOBAL UTILS & CURRENCY EXTENSIONS ---

String cleanBatch(String batch) {
  // Removes (*1), (*2) etc. suffixes and trims whitespace
  return batch.replaceAll(RegExp(r'\s*\(\*\d+\)'), '').trim();
}

/// Formats any transaction entry number (Sales, Purchase, Returns, Adjustments) for user display as a plain number (e.g., "1", "15", "23").
/// Preserves the underlying canonical invoice key (e.g., "T2-1", "T1-15", "SO-5") for internal database & cloud sync logic.
String formatSaleDisplayNo(String? entryNo) {
  if (entryNo == null || entryNo.trim().isEmpty) return "";
  String clean = entryNo.trim();
  if (clean.contains('_')) {
    clean = clean.substring(clean.lastIndexOf('_') + 1);
  }
  // Remove terminal and module prefixes like T1-, T2-, T01-, POS-01-, SO-, SALE-, PUR-, SRET-, PRET-, ADJ-
  clean = clean.replaceAll(RegExp(r'^(T\d+|POS[-_]?\d+|SALE|PUR|SO|ORD|SRET|PRET|ADJ)[-_]', caseSensitive: false), '');
  final match = RegExp(r'(\d+)$').firstMatch(clean);
  if (match != null) {
    return match.group(1)!;
  }
  final digits = clean.replaceAll(RegExp(r'^\D+'), '').replaceAll(RegExp(r'\D+$'), '');
  if (digits.isNotEmpty) return digits;
  return clean;
}

String cleanEntryNo(String entryNo) {
  String clean = entryNo.trim();
  if (clean.isEmpty) return "";

  // Handle financial year underscores (e.g., '2026-27_T2-1' -> 'T2-1')
  if (clean.contains('_')) {
    clean = clean.substring(clean.indexOf('_') + 1);
  }

  // Preserve canonical sales key prefixes like T1-1, T2-15, T01-5
  if (RegExp(r'^T\d+[-_]\d+$', caseSensitive: false).hasMatch(clean)) {
    return clean;
  }

  // Remove standard module prefixes
  clean = clean.replaceAll(RegExp(r'^(SO|ORD|SRET|PRET|ADJ|SALE|PUR)-', caseSensitive: false), '');

  // Strip non-canonical terminal / station / computer name prefix (e.g., 'main-1', 'pos-01-1')
  clean = clean.replaceAll(RegExp(r'^[a-zA-Z0-9_\s]+[-_](?=\d+$)'), '');

  // Catch remaining non-digits at start/end
  clean = clean.replaceAll(RegExp(r'^\D+'), '').replaceAll(RegExp(r'\D+$'), '');

  return clean;
}

String cleanInvoiceNo(dynamic val) {
  if (val == null) return "";
  if (val is String) {
    String s = val.trim();
    if (s.isEmpty) return "";
    if (!s.contains('(') && !s.contains('{') && !s.contains('value:')) {
      return s;
    }
  }
  if (val is num || val is bool) return val.toString();
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

  String s = val.toString().trim();
  if (s.isEmpty) return "";

  if (s.contains('year:') && s.contains('month:') && s.contains('day:')) {
    return s;
  }

  // Iteratively unwrap all Excel cell wrapper objects (TextCellValue, SharedString, TextSpan, CellValue, value:)
  for (int iter = 0; iter < 10; iter++) {
    final lowerS = s.toLowerCase();
    bool changed = false;

    if (lowerS.startsWith('textcellvalue(') ||
        lowerS.startsWith('sharedstring(') ||
        lowerS.startsWith('textspan(') ||
        lowerS.startsWith('intcellvalue(') ||
        lowerS.startsWith('doublecellvalue(') ||
        lowerS.startsWith('stringcellvalue(') ||
        lowerS.startsWith('numbercellvalue(') ||
        lowerS.startsWith('formulacellvalue(') ||
        lowerS.startsWith('cellvalue(') ||
        lowerS.startsWith('datacell(')) {
      int start = s.indexOf('(');
      int end = s.lastIndexOf(')');
      if (start != -1 && end > start) {
        s = s.substring(start + 1, end).trim();
        changed = true;
      }
    }

    if (s.toLowerCase().startsWith('value:')) {
      s = s.substring(6).trim();
      changed = true;
    }

    if (s.toLowerCase().startsWith('text:')) {
      s = s.substring(5).trim();
      changed = true;
    }

    if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      s = s.substring(1, s.length - 1).trim();
      changed = true;
    }

    if (s.startsWith("'") && s.endsWith("'") && s.length >= 2) {
      s = s.substring(1, s.length - 1).trim();
      changed = true;
    }

    if (!changed) break;
  }

  s = s.trim();

  // Convert scientific notation (e.g., "2.50007E+14", "2.50E+14") or trailing decimals ("25000700000000.0")
  if ((s.contains('e') || s.contains('E') || s.contains('.')) && !s.contains('-') && !s.contains('/')) {
    double? d = double.tryParse(s);
    if (d != null && d == d.roundToDouble() && d > 100000) {
      return d.toStringAsFixed(0);
    }
  }

  return s;
}

class AppFormatters {
  static String formatIsoDate(DateTime dt) {
    return "${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
  }

  static String formatDate(DateTime dt) {
    return "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";
  }

  static String formatNumber(num number) {
    if (number is int) {
      return number.toString().replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
            (Match m) => '${m[1]},',
          );
    }
    return number.toStringAsFixed(2);
  }
}

extension CurrencyFormatting on int {
  String toRupeesString() {
    double rupees = this / 100.0;
    return rupees.toStringAsFixed(2);
  }

  double toRupees() {
    return this / 100.0;
  }
}

extension NumCurrencyExt on num {
  double get asCurrency => ((this * 100).roundToDouble()) / 100.0;

  int toPaise() {
    return (this * 100).round();
  }
}
