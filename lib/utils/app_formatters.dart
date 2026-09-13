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

// --- GLOBAL UTILS & CURRENCY EXTENSIONS ---

String cleanBatch(String batch) {
  // Removes (*1), (*2) etc. suffixes and trims whitespace
  return batch.replaceAll(RegExp(r'\s*\(\*\d+\)'), '').trim();
}

String cleanEntryNo(String entryNo) {
  if (entryNo.contains('_')) {
    return entryNo.substring(entryNo.indexOf('_') + 1);
  }
  return entryNo;
}

String cleanInvoiceNo(dynamic val) {
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

  String s = val.toString().trim();
  if (s.isEmpty) return "";

  if (s.contains('year:') && s.contains('month:') && s.contains('day:')) {
    return s;
  }

  // Extract content if wrapped in parentheses or prefixed with "value:"
  if (s.contains('(') && s.contains(')')) {
    int start = s.indexOf('(');
    int end = s.lastIndexOf(')');
    if (end > start) {
      String inner = s.substring(start + 1, end).trim();
      if (inner.contains('year:') && inner.contains('month:') && inner.contains('day:')) {
        return inner;
      }
      s = inner;
    }
  }

  if (s.toLowerCase().startsWith('value:')) {
    s = s.substring(6).trim();
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
