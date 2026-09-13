enum ColumnType { text, number, date }

enum FilterOperation {
  // General
  none, equals, doesNotEqual,
  // Text
  contains, doesNotContain, beginsWith, endsWith,
  // Number/Date
  greaterThan, greaterThanOrEqual, lessThan, lessThanOrEqual, between,
  // Date specific
  today, yesterday, thisMonth, lastMonth, thisYear, lastYear,
}

class AdvancedFilterRule {
  final ColumnType type;
  final FilterOperation operation;
  final dynamic value1;
  final dynamic value2; // Used for 'Between'
  final List<String> selectedValues; // Used for the Checkbox 'Values' tab

  AdvancedFilterRule({
    required this.type,
    this.operation = FilterOperation.none,
    this.value1,
    this.value2,
    this.selectedValues = const [],
  });

  bool get hasRule => operation != FilterOperation.none || selectedValues.isNotEmpty;
}
