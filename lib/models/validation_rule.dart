import 'dart:convert';

/// Generalized Data Model representing a dynamic color validation rule for any Entry screen.
class ValidationRule {
  String id;
  String entryType; // "PURCHASE", "SALES", "PURCHASE_RETURN", "SALES_RETURN", "DAMAGE", "STOCK_ADJUSTMENT"
  bool enabled;
  String fieldA;
  String operator; // ">=", ">", "<=", "<", "=", "!="
  bool isFieldBHeading;
  String fieldB; // Heading name or numeric constant
  int bgColorHex; // Box background color int
  int textColorHex; // Text color int
  String description;

  ValidationRule({
    required this.id,
    this.entryType = "PURCHASE",
    this.enabled = true,
    required this.fieldA,
    required this.operator,
    this.isFieldBHeading = false,
    required this.fieldB,
    required this.bgColorHex,
    required this.textColorHex,
    required this.description,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entryType': entryType,
      'enabled': enabled,
      'fieldA': fieldA,
      'operator': operator,
      'isFieldBHeading': isFieldBHeading,
      'fieldB': fieldB,
      'bgColorHex': bgColorHex,
      'textColorHex': textColorHex,
      'description': description,
    };
  }

  factory ValidationRule.fromJson(Map<String, dynamic> json) {
    return ValidationRule(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      entryType: json['entryType'] ?? "PURCHASE",
      enabled: json['enabled'] ?? true,
      fieldA: json['fieldA'] ?? "L.Cost / P.Rate",
      operator: json['operator'] ?? ">=",
      isFieldBHeading: json['isFieldBHeading'] ?? false,
      fieldB: json['fieldB'] ?? "MRP",
      bgColorHex: (json['bgColorHex'] as num?)?.toInt() ?? (json['colorHex'] as num?)?.toInt() ?? 0xFFEF4444,
      textColorHex: (json['textColorHex'] as num?)?.toInt() ?? 0xFFFFFFFF,
      description: json['description'] ?? "",
    );
  }

  ValidationRule copyWith({
    String? id,
    String? entryType,
    bool? enabled,
    String? fieldA,
    String? operator,
    bool? isFieldBHeading,
    String? fieldB,
    int? bgColorHex,
    int? textColorHex,
    String? description,
  }) {
    return ValidationRule(
      id: id ?? this.id,
      entryType: entryType ?? this.entryType,
      enabled: enabled ?? this.enabled,
      fieldA: fieldA ?? this.fieldA,
      operator: operator ?? this.operator,
      isFieldBHeading: isFieldBHeading ?? this.isFieldBHeading,
      fieldB: fieldB ?? this.fieldB,
      bgColorHex: bgColorHex ?? this.bgColorHex,
      textColorHex: textColorHex ?? this.textColorHex,
      description: description ?? this.description,
    );
  }

  /// Default recommended rule presets per entry type
  static List<ValidationRule> getDefaultRules(String entryType) {
    switch (entryType.toUpperCase()) {
      case "SALES":
        return [
          ValidationRule(
            id: "sales_rule_1",
            entryType: "SALES",
            enabled: true,
            fieldA: "Disc %",
            operator: ">",
            isFieldBHeading: false,
            fieldB: "10",
            bgColorHex: 0xFFFFD54F, // Yellow
            textColorHex: 0xFF000000, // Black
            description: "High Discount Warning (> 10%)",
          ),
          ValidationRule(
            id: "sales_rule_2",
            entryType: "SALES",
            enabled: true,
            fieldA: "Expiry (Months)",
            operator: "<=",
            isFieldBHeading: false,
            fieldB: "3",
            bgColorHex: 0xFFE53935, // Red
            textColorHex: 0xFFFFFFFF, // White
            description: "Critical Near-Expiry (<= 3 Months)",
          ),
          ValidationRule(
            id: "sales_rule_3",
            entryType: "SALES",
            enabled: true,
            fieldA: "Expiry (Months)",
            operator: "<=",
            isFieldBHeading: false,
            fieldB: "6",
            bgColorHex: 0xFFFB8C00, // Orange
            textColorHex: 0xFFFFFFFF, // White
            description: "Short Expiry Warning (<= 6 Months)",
          ),
        ];

      case "PURCHASE_RETURN":
        return [
          ValidationRule(
            id: "pur_ret_rule_1",
            entryType: "PURCHASE_RETURN",
            enabled: true,
            fieldA: "Expiry (Months)",
            operator: "<=",
            isFieldBHeading: false,
            fieldB: "3",
            bgColorHex: 0xFFE53935, // Red
            textColorHex: 0xFFFFFFFF, // White
            description: "Critical Near-Expiry (<= 3 Months)",
          ),
          ValidationRule(
            id: "pur_ret_rule_2",
            entryType: "PURCHASE_RETURN",
            enabled: true,
            fieldA: "Pack Size",
            operator: "!=",
            isFieldBHeading: true,
            fieldB: "Master Pack",
            bgColorHex: 0xFFF59E0B, // Amber
            textColorHex: 0xFF000000, // Black
            description: "Pack Size Mismatch vs Master",
          ),
        ];

      case "SALES_RETURN":
        return [
          ValidationRule(
            id: "sal_ret_rule_1",
            entryType: "SALES_RETURN",
            enabled: true,
            fieldA: "Expiry (Months)",
            operator: "<=",
            isFieldBHeading: false,
            fieldB: "3",
            bgColorHex: 0xFFE53935, // Red
            textColorHex: 0xFFFFFFFF, // White
            description: "Critical Near-Expiry (<= 3 Months)",
          ),
        ];

      case "ORDER_BOOK":
        return [
          ValidationRule(
            id: "ord_book_rule_1",
            entryType: "ORDER_BOOK",
            enabled: true,
            fieldA: "1st Purchase (Days)",
            operator: ">",
            isFieldBHeading: false,
            fieldB: "90",
            bgColorHex: 0xFFFB8C00, // Orange
            textColorHex: 0xFFFFFFFF, // White
            description: "1st Purchase > 90 Days Ago",
          ),
          ValidationRule(
            id: "ord_book_rule_2",
            entryType: "ORDER_BOOK",
            enabled: true,
            fieldA: "Last Sale (Days)",
            operator: ">",
            isFieldBHeading: false,
            fieldB: "60",
            bgColorHex: 0xFFFFD54F, // Yellow
            textColorHex: 0xFF000000, // Black
            description: "Last Sale > 60 Days Ago",
          ),
        ];

      case "DAMAGE":
        return [
          ValidationRule(
            id: "dmg_rule_1",
            entryType: "DAMAGE",
            enabled: true,
            fieldA: "Expiry (Months)",
            operator: "<=",
            isFieldBHeading: false,
            fieldB: "3",
            bgColorHex: 0xFFE53935, // Red
            textColorHex: 0xFFFFFFFF, // White
            description: "Critical Near-Expiry (<= 3 Months)",
          ),
          ValidationRule(
            id: "dmg_rule_2",
            entryType: "DAMAGE",
            enabled: true,
            fieldA: "Loose Cost",
            operator: ">",
            isFieldBHeading: false,
            fieldB: "100",
            bgColorHex: 0xFFFB8C00, // Orange
            textColorHex: 0xFFFFFFFF, // White
            description: "High Damage Value Warning (> 100)",
          ),
        ];

      case "STOCK_ADJUSTMENT":
        return [
          ValidationRule(
            id: "stk_adj_rule_1",
            entryType: "STOCK_ADJUSTMENT",
            enabled: true,
            fieldA: "Variance Qty",
            operator: "!=",
            isFieldBHeading: false,
            fieldB: "0",
            bgColorHex: 0xFFFFD54F, // Yellow
            textColorHex: 0xFF000000, // Black
            description: "Stock Variance Detected (!= 0)",
          ),
          ValidationRule(
            id: "stk_adj_rule_2",
            entryType: "STOCK_ADJUSTMENT",
            enabled: true,
            fieldA: "Expiry (Months)",
            operator: "<=",
            isFieldBHeading: false,
            fieldB: "3",
            bgColorHex: 0xFFE53935, // Red
            textColorHex: 0xFFFFFFFF, // White
            description: "Critical Near-Expiry (<= 3 Months)",
          ),
        ];

      case "PURCHASE":
      default:
        return [
          ValidationRule(
            id: "pur_rule_1",
            entryType: "PURCHASE",
            enabled: true,
            fieldA: "L.Cost / P.Rate",
            operator: ">=",
            isFieldBHeading: true,
            fieldB: "MRP",
            bgColorHex: 0xFFEF4444, // Red
            textColorHex: 0xFFFFFFFF, // White
            description: "Negative Margin (Landed Cost >= MRP)",
          ),
          ValidationRule(
            id: "pur_rule_2",
            entryType: "PURCHASE",
            enabled: true,
            fieldA: "P.Rate",
            operator: ">",
            isFieldBHeading: true,
            fieldB: "Prev P.Rate",
            bgColorHex: 0xFFFEE2E2, // Light Red
            textColorHex: 0xFFDC2626, // Red Text
            description: "Price Increase vs Previous Rate",
          ),
          ValidationRule(
            id: "pur_rule_3",
            entryType: "PURCHASE",
            enabled: true,
            fieldA: "P.Rate",
            operator: "<",
            isFieldBHeading: true,
            fieldB: "Prev P.Rate",
            bgColorHex: 0xFFD1FAE5, // Light Green
            textColorHex: 0xFF059669, // Green Text
            description: "Price Decrease vs Previous Rate",
          ),
          ValidationRule(
            id: "pur_rule_4",
            entryType: "PURCHASE",
            enabled: true,
            fieldA: "Disc %",
            operator: ">",
            isFieldBHeading: false,
            fieldB: "15",
            bgColorHex: 0xFFFFD54F, // Yellow
            textColorHex: 0xFF000000, // Black
            description: "High Discount Warning (> 15%)",
          ),
          ValidationRule(
            id: "pur_rule_5",
            entryType: "PURCHASE",
            enabled: true,
            fieldA: "Expiry (Months)",
            operator: "<=",
            isFieldBHeading: false,
            fieldB: "3",
            bgColorHex: 0xFFE53935, // Red
            textColorHex: 0xFFFFFFFF, // White
            description: "Critical Near-Expiry (<= 3 Months)",
          ),
          ValidationRule(
            id: "pur_rule_6",
            entryType: "PURCHASE",
            enabled: true,
            fieldA: "Expiry (Months)",
            operator: "<=",
            isFieldBHeading: false,
            fieldB: "6",
            bgColorHex: 0xFFFB8C00, // Orange
            textColorHex: 0xFFFFFFFF, // White
            description: "Short Expiry Warning (<= 6 Months)",
          ),
          ValidationRule(
            id: "pur_rule_7",
            entryType: "PURCHASE",
            enabled: true,
            fieldA: "Pack Size",
            operator: "!=",
            isFieldBHeading: true,
            fieldB: "Master Pack",
            bgColorHex: 0xFFF59E0B, // Amber
            textColorHex: 0xFF000000, // Black
            description: "Pack Size Mismatch vs Product Master",
          ),
        ];
    }
  }

  static String encodeMap(Map<String, List<ValidationRule>> map) {
    Map<String, dynamic> rawMap = {};
    map.forEach((key, list) {
      rawMap[key.toUpperCase()] = list.map((r) => r.toJson()).toList();
    });
    return jsonEncode(rawMap);
  }

  static Map<String, List<ValidationRule>> decodeMap(String jsonStr) {
    Map<String, List<ValidationRule>> resultMap = {};
    try {
      final Map<String, dynamic> parsed = jsonDecode(jsonStr);
      parsed.forEach((key, valList) {
        if (valList is List) {
          resultMap[key.toUpperCase()] = valList.map((e) => ValidationRule.fromJson(e as Map<String, dynamic>)).toList();
        }
      });
    } catch (_) {}

    // Ensure default fallback rules for missing, empty, or legacy single-rule entry types
    final entryTypes = ["PURCHASE", "SALES", "PURCHASE_RETURN", "SALES_RETURN", "DAMAGE", "STOCK_ADJUSTMENT", "ORDER_BOOK"];
    for (var et in entryTypes) {
      final existing = resultMap[et];
      bool isLegacySingleRule = existing != null && existing.length == 1 && (existing.first.id.startsWith("DEF_") || existing.first.description.contains("Landing Cost / Purchase Rate exceeds MRP"));
      if (existing == null || existing.isEmpty || isLegacySingleRule) {
        resultMap[et] = getDefaultRules(et);
      }
    }

    return resultMap;
  }
}

/// Backwards compatibility alias
typedef PurchaseValidationRule = ValidationRule;
