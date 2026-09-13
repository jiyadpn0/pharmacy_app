import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'app_date_picker.dart';

enum FilterType { text, numeric, date }

class ColumnFilterState {
  final FilterType type;
  bool isActive = false;

  // Text Filter State
  Set<String> selectedValues = {};
  String textSearch = "";
  String textOperator = "Contains"; // Contains, Starts with, Ends with, Equals, Does not equal

  // Numeric Filter State
  double? min;
  double? max;
  double? rangeStart;
  double? rangeEnd;
  String numericOperator = "Equals"; // Equals, Greater than, Less than, Between
  double? numericValue;

  // Date Filter State
  Set<DateTime> selectedDates = {};
  String datePeriod = "Specific Date Periods"; // Yesterday, Today, Tomorrow, Last Week, etc.
  DateTime? startDate;
  DateTime? endDate;
  String dateOperator = "Is Same Day"; // Is Same Day, Equals, Before, After, Between

  ColumnFilterState({required this.type});

  void clear() {
    isActive = false;
    selectedValues.clear();
    textSearch = "";
    min = null; max = null; rangeStart = null; rangeEnd = null;
    numericValue = null;
    selectedDates.clear();
    startDate = null; endDate = null;
  }

  bool matches(dynamic value) {
    if (!isActive) return true;

    // Check unique values selection first
    if (selectedValues.isNotEmpty) {
      if (!selectedValues.contains(value.toString())) return false;
    }

    if (type == FilterType.text) {
      if (textSearch.isEmpty) return true;
      String v = value.toString().toLowerCase();
      String s = textSearch.toLowerCase();
      switch (textOperator) {
        case "Contains": return v.contains(s);
        case "Does not contain": return !v.contains(s);
        case "Starts with": return v.startsWith(s);
        case "Ends with": return v.endsWith(s);
        case "Equals": return v == s;
        case "Does not equal": return v != s;
        default: return true;
      }
    } else if (type == FilterType.numeric) {
      double? v = double.tryParse(value.toString());
      if (v == null) return false;
      if (numericOperator == "Between") {
        if (rangeStart != null && v < rangeStart!) return false;
        if (rangeEnd != null && v > rangeEnd!) return false;
        return true;
      } else {
        if (numericValue == null) return true;
        switch (numericOperator) {
          case "Equals": return v == numericValue;
          case "Greater than": return v > numericValue!;
          case "Less than": return v < numericValue!;
          default: return true;
        }
      }
    } else if (type == FilterType.date) {
      DateTime? v;
      if (value is DateTime) {
        v = value;
      } else if (value is String) {
        // Try parsing common formats
        try {
          if (value.contains('/')) {
            final parts = value.split('/');
            if (parts.length == 3) {
              v = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
            } else if (parts.length == 2) {
              v = DateTime(2000 + int.parse(parts[1]), int.parse(parts[0]));
            }
          } else {
            v = DateTime.tryParse(value);
          }
        } catch (_) {}
      }
      if (v == null) return false;

      if (datePeriod != "Specific Date Periods" && datePeriod != "Custom Range") {
        DateTime now = DateTime.now();
        switch (datePeriod) {
          case "Yesterday": return isSameDay(v, now.subtract(const Duration(days: 1)));
          case "Today": return isSameDay(v, now);
          case "Tomorrow": return isSameDay(v, now.add(const Duration(days: 1)));
          case "Last Week": {
            DateTime start = now.subtract(Duration(days: now.weekday + 6));
            DateTime end = start.add(const Duration(days: 6));
            return v.isAfter(start) && v.isBefore(end.add(const Duration(days: 1)));
          }
          case "This Week": {
            DateTime start = now.subtract(Duration(days: now.weekday - 1));
            return v.isAfter(start.subtract(const Duration(days: 1))) && v.isBefore(start.add(const Duration(days: 7)));
          }
          case "Last Month": return v.year == (now.month == 1 ? now.year - 1 : now.year) && v.month == (now.month == 1 ? 12 : now.month - 1);
          case "This Month": return v.year == now.year && v.month == now.month;
          case "Next Month": return v.year == (now.month == 12 ? now.year + 1 : now.year) && v.month == (now.month == 12 ? 1 : now.month + 1);
          case "Last Year": return v.year == now.year - 1;
          case "This Year": return v.year == now.year;
          case "Next Year": return v.year == now.year + 1;
          default: return true;
        }
      }

      if (startDate != null && v.isBefore(startDate!)) return false;
      if (endDate != null && v.isAfter(endDate!)) return false;
      return true;
    }
    return true;
  }

  bool isSameDay(DateTime d1, DateTime d2) => d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
}

class FilterableHeader extends StatefulWidget {
  final String title;
  final double width;
  final FilterType type;
  final ColumnFilterState filterState;
  final List<dynamic> allValues; // All unique values for this column in the current dataset
  final VoidCallback onFilterChanged;
  final TextAlign textAlign;

  const FilterableHeader({
    super.key,
    required this.title,
    required this.width,
    required this.type,
    required this.filterState,
    required this.allValues,
    required this.onFilterChanged,
    this.textAlign = TextAlign.left,
  });

  @override
  State<FilterableHeader> createState() => _FilterableHeaderState();
}

class _FilterableHeaderState extends State<FilterableHeader> {
  bool _isHovered = false;

  void _showFilterPopup() {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => Stack(
        children: [
          Positioned(
            left: offset.dx,
            top: offset.dy + 32, // Adjusted for new header height
            child: AdvancedFilterPopup(
              type: widget.type,
              filterState: widget.filterState,
              allValues: widget.allValues,
              onApply: () {
                widget.onFilterChanged();
                Navigator.pop(ctx);
              },
              onClear: () {
                widget.filterState.clear();
                widget.onFilterChanged();
                Navigator.pop(ctx);
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        width: widget.width,
        height: 32, // Reduced from 35
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Colors.white24, width: 0.5)),
        ),
        child: Stack(
          children: [
            Align(
              alignment: widget.textAlign == TextAlign.center
                  ? Alignment.center
                  : (widget.textAlign == TextAlign.right ? Alignment.centerRight : Alignment.centerLeft),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  widget.title,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white), // Reduced from 11
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (_isHovered || widget.filterState.isActive)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: IconButton(
                  icon: Icon(
                      Icons.filter_alt,
                      size: 13, // Reduced from 14
                      color: widget.filterState.isActive ? Colors.orange : Colors.white70
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _showFilterPopup,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AdvancedFilterPopup extends StatefulWidget {
  final FilterType type;
  final ColumnFilterState filterState;
  final List<dynamic> allValues;
  final VoidCallback onApply;
  final VoidCallback onClear;

  const AdvancedFilterPopup({
    super.key,
    required this.type,
    required this.filterState,
    required this.allValues,
    required this.onApply,
    required this.onClear,
  });

  @override
  State<AdvancedFilterPopup> createState() => _AdvancedFilterPopupState();
}

class _AdvancedFilterPopupState extends State<AdvancedFilterPopup> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  List<dynamic> _filteredListValues = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _filteredListValues = widget.allValues.toSet().toList();
    _filteredListValues.sort();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 280, // Reduced from 300
        height: 375, // Reduced from 400
        decoration: BoxDecoration(
          color: const Color(0xFFF0F2F5),
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          children: [
            Container(
              height: 32, // Reduced from 35
              color: Colors.grey.shade300,
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.black,
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: Colors.blue,
                labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                tabs: [
                  const Tab(text: "Values"),
                  Tab(text: widget.type == FilterType.text ? "Text Filters" :
                  widget.type == FilterType.numeric ? "Numeric Filters" : "Date Filters"),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildValuesTab(),
                  _buildLogicTab(),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(6.0), // Reduced from 8.0
              child: Row(
                children: [
                  TextButton(
                      onPressed: widget.onClear,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                      child: const Text("Clear Filter", style: TextStyle(fontSize: 11))),
                  const Spacer(),
                  SizedBox(
                    height: 28,
                    child: ElevatedButton(
                      onPressed: () {
                        widget.filterState.isActive = true;
                        widget.onApply();
                      },
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                      child: const Text("Apply", style: TextStyle(fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    height: 28,
                    child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                        child: const Text("Close", style: TextStyle(fontSize: 11))),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildValuesTab() {
    return Padding(
      padding: const EdgeInsets.all(6.0), // Reduced from 8.0
      child: Column(
        children: [
          SizedBox(
            height: 32,
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: "Enter text to search...",
                prefixIcon: Icon(Icons.search, size: 16), // Reduced from 18
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(fontSize: 11),
              onChanged: (v) {
                setState(() {
                  _filteredListValues = widget.allValues
                      .where((val) => val.toString().toLowerCase().contains(v.toLowerCase()))
                      .toSet()
                      .toList();
                  _filteredListValues.sort();
                });
              },
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: ListView.builder(
                itemCount: _filteredListValues.length + 1,
                itemBuilder: (ctx, i) {
                  if (i == 0) {
                    bool allSelected = widget.filterState.selectedValues.length == widget.allValues.toSet().length;
                    return SizedBox(
                      height: 32,
                      child: CheckboxListTile(
                        title: const Text("(All)", style: TextStyle(fontSize: 11)), // Reduced from 12
                        value: allSelected,
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        onChanged: (v) {
                          setState(() {
                            if (v!) {
                              widget.filterState.selectedValues = widget.allValues.map((e) => e.toString()).toSet();
                            } else {
                              widget.filterState.selectedValues.clear();
                            }
                          });
                        },
                      ),
                    );
                  }
                  final val = _filteredListValues[i - 1].toString();
                  return SizedBox(
                    height: 32,
                    child: CheckboxListTile(
                      title: Text(val, style: const TextStyle(fontSize: 11)), // Reduced from 12
                      value: widget.filterState.selectedValues.contains(val),
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      onChanged: (v) {
                        setState(() {
                          if (v!) {
                            widget.filterState.selectedValues.add(val);
                          } else {
                            widget.filterState.selectedValues.remove(val);
                          }
                        });
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogicTab() {
    if (widget.type == FilterType.text) {
      return _buildTextLogic();
    } else if (widget.type == FilterType.numeric) {
      return _buildNumericLogic();
    } else {
      return _buildDateLogic();
    }
  }

  Widget _buildTextLogic() {
    return Padding(
      padding: const EdgeInsets.all(12.0), // Reduced from 16
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: widget.filterState.textOperator,
            decoration: const InputDecoration(labelText: "Condition", isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
            style: const TextStyle(fontSize: 11, color: Colors.black),
            items: ["Contains", "Does not contain", "Starts with", "Ends with", "Equals", "Does not equal"]
                .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 11)))).toList(),
            onChanged: (v) => setState(() => widget.filterState.textOperator = v!),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 35,
            child: TextField(
              decoration: const InputDecoration(labelText: "Value", border: OutlineInputBorder(), isDense: true, labelStyle: TextStyle(fontSize: 11)),
              style: const TextStyle(fontSize: 11),
              onChanged: (v) => widget.filterState.textSearch = v,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumericLogic() {
    return Padding(
      padding: const EdgeInsets.all(12.0), // Reduced from 16
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: widget.filterState.numericOperator,
            decoration: const InputDecoration(labelText: "Condition", isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
            style: const TextStyle(fontSize: 11, color: Colors.black),
            items: ["Equals", "Greater than", "Less than", "Between"]
                .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 11)))).toList(),
            onChanged: (v) => setState(() => widget.filterState.numericOperator = v!),
          ),
          const SizedBox(height: 12),
          if (widget.filterState.numericOperator == "Between") ...[
            Row(
              children: [
                Expanded(child: SizedBox(
                  height: 35,
                  child: TextField(
                    decoration: const InputDecoration(labelText: "From", border: OutlineInputBorder(), isDense: true, labelStyle: TextStyle(fontSize: 11)),
                    style: const TextStyle(fontSize: 11),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => widget.filterState.rangeStart = double.tryParse(v),
                  ),
                )),
                const SizedBox(width: 8),
                Expanded(child: SizedBox(
                  height: 35,
                  child: TextField(
                    decoration: const InputDecoration(labelText: "To", border: OutlineInputBorder(), isDense: true, labelStyle: TextStyle(fontSize: 11)),
                    style: const TextStyle(fontSize: 11),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => widget.filterState.rangeEnd = double.tryParse(v),
                  ),
                )),
              ],
            )
          ] else
            SizedBox(
              height: 35,
              child: TextField(
                decoration: const InputDecoration(labelText: "Value", border: OutlineInputBorder(), isDense: true, labelStyle: TextStyle(fontSize: 11)),
                style: const TextStyle(fontSize: 11),
                keyboardType: TextInputType.number,
                onChanged: (v) => widget.filterState.numericValue = double.tryParse(v),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDateLogic() {
    return Padding(
      padding: const EdgeInsets.all(12.0), // Reduced from 16
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: widget.filterState.datePeriod,
            decoration: const InputDecoration(labelText: "Period", isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
            style: const TextStyle(fontSize: 11, color: Colors.black),
            items: ["Specific Date Periods", "Custom Range"]
                .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 11)))).toList(),
            onChanged: (v) => setState(() => widget.filterState.datePeriod = v!),
          ),
          const SizedBox(height: 12),
          if (widget.filterState.datePeriod == "Specific Date Periods")
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    _dateChip("Yesterday"), _dateChip("Today"), _dateChip("Tomorrow"),
                    _dateChip("Last Week"), _dateChip("This Week"), _dateChip("Next Week"),
                    _dateChip("Last Month"), _dateChip("This Month"), _dateChip("Next Month"),
                    _dateChip("Last Year"), _dateChip("This Year"), _dateChip("Next Year"),
                  ],
                ),
              ),
            )
          else ...[
            _dateField("Start Date", widget.filterState.startDate, (d) => setState(() => widget.filterState.startDate = d)),
            const SizedBox(height: 8),
            _dateField("End Date", widget.filterState.endDate, (d) => setState(() => widget.filterState.endDate = d)),
          ]
        ],
      ),
    );
  }

  Widget _dateChip(String label) {
    bool isSelected = widget.filterState.datePeriod == label;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 9)), // Reduced from 10
      selected: isSelected,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: (v) => setState(() => widget.filterState.datePeriod = label),
    );
  }

  Widget _dateField(String label, DateTime? date, Function(DateTime) onPick) {
    return InkWell(
      onTap: () async {
        final picked = await showAppDatePicker(
            context: context,
            initialDate: date ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100)
        );
        if (picked != null) onPick(picked);
      },
      child: Container(
        height: 32, // Reduced from 36
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4)),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 10)),
            const Spacer(),
            Text(date != null ? DateFormat('dd/MM/yy').format(date) : "Select", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
