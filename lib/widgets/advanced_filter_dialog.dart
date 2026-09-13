import 'package:flutter/material.dart';
import '../models/filter_models.dart';

class AdvancedFilterDialog extends StatefulWidget {
  final String columnName;
  final ColumnType columnType;
  final List<String> uniqueColumnValues; // Pass all unique values from your grid column here
  final AdvancedFilterRule? existingRule;

  const AdvancedFilterDialog({
    super.key,
    required this.columnName,
    required this.columnType,
    required this.uniqueColumnValues,
    this.existingRule,
  });

  @override
  State<AdvancedFilterDialog> createState() => _AdvancedFilterDialogState();
}

class _AdvancedFilterDialogState extends State<AdvancedFilterDialog> {
  late List<String> _filteredUniqueValues;
  List<String> _selectedValues = [];

  FilterOperation _selectedOp = FilterOperation.none;
  final TextEditingController _val1Ctrl = TextEditingController();
  final TextEditingController _val2Ctrl = TextEditingController(); // For 'between'
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredUniqueValues = widget.uniqueColumnValues;

    if (widget.existingRule != null) {
      _selectedValues = List.from(widget.existingRule!.selectedValues);
      _selectedOp = widget.existingRule!.operation;
      if (widget.existingRule!.value1 != null) _val1Ctrl.text = widget.existingRule!.value1.toString();
      if (widget.existingRule!.value2 != null) _val2Ctrl.text = widget.existingRule!.value2.toString();
    } else {
      // By default, select all values in the list
      _selectedValues = List.from(widget.uniqueColumnValues);
    }
  }

  void _applyFilter() {
    final rule = AdvancedFilterRule(
      type: widget.columnType,
      operation: _selectedOp,
      value1: _val1Ctrl.text.isNotEmpty ? _val1Ctrl.text : null,
      value2: _val2Ctrl.text.isNotEmpty ? _val2Ctrl.text : null,
      selectedValues: _selectedValues,
    );
    Navigator.of(context).pop(rule);
  }

  void _clearFilter() {
    Navigator.of(context).pop(AdvancedFilterRule(type: widget.columnType));
  }

  @override
  Widget build(BuildContext context) {
    String filterTabName = widget.columnType == ColumnType.text
        ? "Text Filters"
        : widget.columnType == ColumnType.number ? "Numeric Filters" : "Date Filters";

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: SizedBox(
        width: 320,
        height: 450,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              // HEADER
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: Colors.grey.shade200,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Filter: ${widget.columnName}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    InkWell(onTap: () => Navigator.pop(context), child: const Icon(Icons.close, size: 18)),
                  ],
                ),
              ),

              // TABS
              TabBar(
                labelColor: Colors.blue.shade700,
                unselectedLabelColor: Colors.grey.shade700,
                indicatorColor: Colors.blue.shade700,
                tabs: [
                  const Tab(text: "Values"),
                  Tab(text: filterTabName),
                ],
              ),

              // TAB VIEWS
              Expanded(
                child: TabBarView(
                  children: [
                    _buildValuesTab(),
                    _buildRulesTab(),
                  ],
                ),
              ),

              // BOTTOM ACTIONS
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(onPressed: _clearFilter, child: const Text("Clear Filter")),
                    ElevatedButton(
                      onPressed: _applyFilter,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
                      child: const Text("OK"),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  // --- TAB 1: VALUES (Checkbox List) ---
  Widget _buildValuesTab() {
    bool isAllSelected = _selectedValues.length == widget.uniqueColumnValues.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: SizedBox(
            height: 32,
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 16),
                hintText: "Search...",
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (val) {
                setState(() {
                  _filteredUniqueValues = widget.uniqueColumnValues
                      .where((e) => e.toLowerCase().contains(val.toLowerCase())).toList();
                });
              },
            ),
          ),
        ),
        CheckboxListTile(
          title: const Text("(Select All)", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          value: isAllSelected,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          onChanged: (val) {
            setState(() {
              if (val == true) {
                _selectedValues = List.from(widget.uniqueColumnValues);
              } else {
                _selectedValues.clear();
              }
            });
          },
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _filteredUniqueValues.length,
            itemBuilder: (context, index) {
              final val = _filteredUniqueValues[index];
              return CheckboxListTile(
                title: Text(val, style: const TextStyle(fontSize: 13)),
                value: _selectedValues.contains(val),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                onChanged: (isChecked) {
                  setState(() {
                    if (isChecked == true) {
                      _selectedValues.add(val);
                    } else {
                      _selectedValues.remove(val);
                    }
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // --- TAB 2: RULES (Text/Number/Date dropdowns) ---
  Widget _buildRulesTab() {
    List<DropdownMenuItem<FilterOperation>> opItems = [];

    if (widget.columnType == ColumnType.text) {
      opItems = const [
        DropdownMenuItem(value: FilterOperation.none, child: Text("Select Operator...")),
        DropdownMenuItem(value: FilterOperation.equals, child: Text("Equals")),
        DropdownMenuItem(value: FilterOperation.doesNotEqual, child: Text("Does Not Equal")),
        DropdownMenuItem(value: FilterOperation.contains, child: Text("Contains")),
        DropdownMenuItem(value: FilterOperation.doesNotContain, child: Text("Does Not Contain")),
        DropdownMenuItem(value: FilterOperation.beginsWith, child: Text("Begins With")),
      ];
    } else if (widget.columnType == ColumnType.number) {
      opItems = const [
        DropdownMenuItem(value: FilterOperation.none, child: Text("Select Operator...")),
        DropdownMenuItem(value: FilterOperation.equals, child: Text("Equals")),
        DropdownMenuItem(value: FilterOperation.greaterThan, child: Text("Greater Than")),
        DropdownMenuItem(value: FilterOperation.lessThan, child: Text("Less Than")),
        DropdownMenuItem(value: FilterOperation.between, child: Text("Between")),
      ];
    } else if (widget.columnType == ColumnType.date) {
      opItems = const [
        DropdownMenuItem(value: FilterOperation.none, child: Text("Select Operator...")),
        DropdownMenuItem(value: FilterOperation.equals, child: Text("Specific Date (Equals)")),
        DropdownMenuItem(value: FilterOperation.between, child: Text("Custom Range (Between)")),
        DropdownMenuItem(value: FilterOperation.today, child: Text("Today")),
        DropdownMenuItem(value: FilterOperation.thisMonth, child: Text("This Month")),
        DropdownMenuItem(value: FilterOperation.lastMonth, child: Text("Last Month")),
      ];
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<FilterOperation>(
            initialValue: _selectedOp,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
            items: opItems,
            onChanged: (val) => setState(() => _selectedOp = val!),
          ),
          const SizedBox(height: 16),

          // Show input fields only if the operation requires a user-typed value
          if (_selectedOp != FilterOperation.none &&
              _selectedOp != FilterOperation.today &&
              _selectedOp != FilterOperation.thisMonth &&
              _selectedOp != FilterOperation.lastMonth) ...[

            TextFormField(
              controller: _val1Ctrl,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: widget.columnType == ColumnType.date ? "YYYY-MM-DD" : "Value",
              ),
            ),

            if (_selectedOp == FilterOperation.between) ...[
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Center(child: Text("AND"))),
              TextFormField(
                controller: _val2Ctrl,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: widget.columnType == ColumnType.date ? "YYYY-MM-DD" : "Value 2",
                ),
              ),
            ]
          ]
        ],
      ),
    );
  }
}
