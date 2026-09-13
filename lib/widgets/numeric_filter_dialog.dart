import 'package:flutter/material.dart';

class NumericFilterDialog extends StatefulWidget {
  final String columnName;
  final double minValue;
  final double maxValue;
  final List<String> uniqueValues;

  const NumericFilterDialog({
    super.key,
    required this.columnName,
    this.minValue = 0,
    this.maxValue = 10000,
    this.uniqueValues = const [],
  });

  @override
  State<NumericFilterDialog> createState() => _NumericFilterDialogState();
}

class _NumericFilterDialogState extends State<NumericFilterDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedCondition = "Between";
  late double _currentMin;
  late double _currentMax;
  final TextEditingController _fromCtrl = TextEditingController();
  final TextEditingController _toCtrl = TextEditingController();
  final TextEditingController _singleValueCtrl = TextEditingController();

  final List<String> _numericConditions = [
    "Equals", "Does Not Equal", "Is Null", "Is Not Null", "Between",
    "Greater Than", "Greater Than Or Equal To", "Less Than",
    "Less Than Or Equal To", "Top N", "Bottom N", "Above Average",
    "Below Average", "Custom Filter"
  ];

  final TextEditingController _searchCtrl = TextEditingController();
  List<String> _displayValues = [];
  Set<String> _selectedValues = {};
  bool _isAllSelected = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _currentMin = widget.minValue;
    _currentMax = widget.maxValue;
    _fromCtrl.text = _currentMin.toStringAsFixed(0);
    _toCtrl.text = _currentMax.toStringAsFixed(0);

    _displayValues = widget.uniqueValues;
    _selectedValues = widget.uniqueValues.toSet();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _singleValueCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filterChecklist(String query) {
    setState(() {
      if (query.isEmpty) {
        _displayValues = widget.uniqueValues;
      } else {
        _displayValues = widget.uniqueValues
            .where((v) => v.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _updateSliderFromText() {
    double? from = double.tryParse(_fromCtrl.text);
    double? to = double.tryParse(_toCtrl.text);
    if (from != null && to != null && from <= to) {
      setState(() {
        _currentMin = from.clamp(widget.minValue, widget.maxValue);
        _currentMax = to.clamp(widget.minValue, widget.maxValue);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: 225,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          Container(
            height: 35,
            color: Colors.grey.shade200,
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.blue,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.blue,
              labelStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
              labelPadding: EdgeInsets.zero,
              tabs: const [
                Tab(text: "Vals"),
                Tab(text: "Num"),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildValuesTab(),
                _buildNumericFiltersTab(),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade300))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  height: 22,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, {'condition': 'Clear'}),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                    child: const Text("Clear", style: TextStyle(color: Colors.grey, fontSize: 9)),
                  ),
                ),
                SizedBox(
                  height: 22,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_tabController.index == 0) {
                        Navigator.pop(context, {
                          'type': 'checklist',
                          'values': _selectedValues.toList(),
                        });
                      } else {
                        Navigator.pop(context, {
                          'type': 'numeric',
                          'condition': _selectedCondition,
                          'from': _currentMin,
                          'to': _currentMax,
                          'value': double.tryParse(_singleValueCtrl.text) ?? 0.0,
                        });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade200,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text("OK", style: TextStyle(fontSize: 9)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValuesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(4.0),
          child: SizedBox(
            height: 24,
            child: TextField(
              controller: _searchCtrl,
              onChanged: _filterChecklist,
              style: const TextStyle(fontSize: 10),
              decoration: const InputDecoration(
                hintText: "Search...",
                hintStyle: TextStyle(fontSize: 10),
                suffixIcon: Icon(Icons.search, size: 12),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.only(left: 4, bottom: 12),
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              CheckboxListTile(
                value: _isAllSelected,
                title: const Text("(All)", style: TextStyle(fontSize: 10)),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                onChanged: (val) {
                  setState(() {
                    _isAllSelected = val ?? false;
                    if (_isAllSelected) {
                      _selectedValues.addAll(_displayValues);
                    } else {
                      _selectedValues.removeAll(_displayValues);
                    }
                  });
                },
              ),
              ..._displayValues.map((value) {
                return CheckboxListTile(
                  value: _selectedValues.contains(value),
                  title: Text(value, style: const TextStyle(fontSize: 10)),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedValues.add(value);
                      } else {
                        _selectedValues.remove(value);
                        _isAllSelected = false;
                      }
                    });
                  },
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNumericFiltersTab() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedCondition,
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down, size: 16),
                style: const TextStyle(fontSize: 10, color: Colors.black87),
                items: _numericConditions.map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (newValue) => setState(() => _selectedCondition = newValue!),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_selectedCondition == "Between") ...[
            Row(
              children: [
                const Text("From ", style: TextStyle(fontSize: 10)),
                Expanded(
                  child: SizedBox(
                    height: 24,
                    child: TextField(
                      controller: _fromCtrl,
                      style: const TextStyle(fontSize: 10),
                      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8)),
                      onSubmitted: (_) => _updateSliderFromText(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text("To ", style: TextStyle(fontSize: 10)),
                Expanded(
                  child: SizedBox(
                    height: 24,
                    child: TextField(
                      controller: _toCtrl,
                      style: const TextStyle(fontSize: 10),
                      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8)),
                      onSubmitted: (_) => _updateSliderFromText(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 30,
              child: RangeSlider(
                values: RangeValues(_currentMin, _currentMax),
                min: widget.minValue,
                max: widget.maxValue,
                divisions: 100,
                onChanged: (RangeValues values) {
                  setState(() {
                    _currentMin = values.start;
                    _currentMax = values.end;
                    _fromCtrl.text = _currentMin.toStringAsFixed(0);
                    _toCtrl.text = _currentMax.toStringAsFixed(0);
                  });
                },
              ),
            ),
          ] else if (!["Is Null", "Is Not Null"].contains(_selectedCondition)) ...[
            SizedBox(
              height: 24,
              child: TextField(
                controller: _singleValueCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 10),
                decoration: const InputDecoration(
                    hintText: "Value...",
                    hintStyle: TextStyle(fontSize: 10),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8)
                ),
                onChanged: (v) {
                  double? val = double.tryParse(v);
                  if (val != null) {
                    setState(() {
                      _currentMin = val;
                    });
                  }
                },
              ),
            ),
          ]
        ],
      ),
    );
  }
}
