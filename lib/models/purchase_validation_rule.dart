import 'dart:convert';

/// Data model representing a dynamic Purchase Entry color validation rule.
class PurchaseValidationRule {
  String id;
  bool enabled;
  String fieldA;
  String operator; // ">=", ">", "<=", "<", "=", "!="
  bool isFieldBHeading;
  String fieldB; // Column Heading name or numeric constant
  int colorHex; // e.g. 0xFFE53935
  String description;

  PurchaseValidationRule({
    required this.id,
    this.enabled = true,
    required this.fieldA,
    required this.operator,
    this.isFieldBHeading = false,
    required this.fieldB,
    required this.colorHex,
    required this.description,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'enabled': enabled,
      'fieldA': fieldA,
      'operator': operator,
      'isFieldBHeading': isFieldBHeading,
      'fieldB': fieldB,
      'colorHex': colorHex,
      'description': description,
    };
  }

  factory PurchaseValidationRule.fromJson(Map<String, dynamic> json) {
    return PurchaseValidationRule(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      enabled: json['enabled'] ?? true,
      fieldA: json['fieldA'] ?? "L.Cost / P.Rate",
      operator: json['operator'] ?? ">=",
      isFieldBHeading: json['isFieldBHeading'] ?? false,
      fieldB: json['fieldB'] ?? "MRP",
      colorHex: (json['colorHex'] as num?)?.toInt() ?? 0xFFE53935,
      description: json['description'] ?? "",
    );
  }

  PurchaseValidationRule copyWith({
    String? id,
    bool? enabled,
    String? fieldA,
    String? operator,
    bool? isFieldBHeading,
    String? fieldB,
    int? colorHex,
    String? description,
  }) {
    return PurchaseValidationRule(
      id: id ?? this.id,
      enabled: enabled ?? this.enabled,
      fieldA: fieldA ?? this.fieldA,
      operator: operator ?? this.operator,
      isFieldBHeading: isFieldBHeading ?? this.isFieldBHeading,
      fieldB: fieldB ?? this.fieldB,
      colorHex: colorHex ?? this.colorHex,
      description: description ?? this.description,
    );
  }

  /// Default recommended rule presets
  static List<PurchaseValidationRule> getDefaultRules() {
    return [
      PurchaseValidationRule(
        id: "rule_1",
        enabled: true,
        fieldA: "L.Cost / P.Rate",
        operator: ">=",
        isFieldBHeading: true,
        fieldB: "MRP",
        colorHex: 0xFFEF4444, // Soft Red
        description: "Negative Margin (Landed Cost >= MRP)",
      ),
      PurchaseValidationRule(
        id: "rule_2",
        enabled: true,
        fieldA: "P.Rate",
        operator: ">",
        isFieldBHeading: true,
        fieldB: "Prev P.Rate",
        colorHex: 0xFFDC2626, // Red
        description: "Price Increase vs Previous Purchase Rate",
      ),
      PurchaseValidationRule(
        id: "rule_3",
        enabled: true,
        fieldA: "P.Rate",
        operator: "<",
        isFieldBHeading: true,
        fieldB: "Prev P.Rate",
        colorHex: 0xFF10B981, // Green
        description: "Price Decrease vs Previous Purchase Rate",
      ),
      PurchaseValidationRule(
        id: "rule_4",
        enabled: true,
        fieldA: "Disc %",
        operator: ">",
        isFieldBHeading: false,
        fieldB: "15",
        colorHex: 0xFFFFD54F, // Yellow
        description: "High Discount Warning (> 15%)",
      ),
      PurchaseValidationRule(
        id: "rule_5",
        enabled: true,
        fieldA: "Expiry (Months)",
        operator: "<=",
        isFieldBHeading: false,
        fieldB: "3",
        colorHex: 0xFFE53935, // Red
        description: "Critical Near-Expiry (<= 3 Months)",
      ),
      PurchaseValidationRule(
        id: "rule_6",
        enabled: true,
        fieldA: "Expiry (Months)",
        operator: "<=",
        isFieldBHeading: false,
        fieldB: "6",
        colorHex: 0xFFFB8C00, // Orange
        description: "Short Expiry Warning (<= 6 Months)",
      ),
      PurchaseValidationRule(
        id: "rule_7",
        enabled: true,
        fieldA: "Pack Size",
        operator: "!=",
        isFieldBHeading: true,
        fieldB: "Master Pack",
        colorHex: 0xFFF59E0B, // Amber
        description: "Pack Size Mismatch vs Product Master",
      ),
    ];
  }

  static String encodeList(List<PurchaseValidationRule> rules) {
    return jsonEncode(rules.map((r) => r.toJson()).toList());
  }

  static List<PurchaseValidationRule> decodeList(String jsonStr) {
    try {
      final List parsed = jsonDecode(jsonStr);
      return parsed.map((e) => PurchaseValidationRule.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return getDefaultRules();
    }
  }
}
