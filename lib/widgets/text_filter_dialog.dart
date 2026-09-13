import 'package:flutter/material.dart';

class TextFilterDialog extends StatefulWidget {
  final String columnName;
  final List<String> uniqueValues;

  const TextFilterDialog({
    super.key,
    required this.columnName,
    required this.uniqueValues,
  });

  @override
  State<TextFilterDialog> createState() => _TextFilterDialogState();
}

class _TextFilterDialogState extends State<TextFilterDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedCondition = "Begins With";
  final TextEditingController _textCtrl = TextEditingController();
  final List<String> _textConditions = [
    "Equals", "Does Not Equal", "Contains", "Does Not Contain",
    "Begins With", "Ends With", "Is like", "Is not like",
    "Is Blank", "Is Not Blank", "Custom Filter"
  ];
  final TextEditingController _searchCtrl = TextEditingController();
  List<String> _displayValues = [];
  Set<String> _selectedValues = {};
  bool _isAllSelected = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _displayValues = widget.uniqueValues;
    _selectedValues = widget.uniqueValues.toSet();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _textCtrl.dispose();
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
                Tab(text: "Txt"),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildValuesTab(),
                _buildTextFiltersTab(),
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
                          'type': 'text',
                          'condition': _selectedCondition,
                          'value': _textCtrl.text,
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
          )
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

  Widget _buildTextFiltersTab() {
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
                items: _textConditions.map((String value) {
                  return DropdownMenuItem<String>(value: value, child: Text(value));
                }).toList(),
                onChanged: (newValue) => setState(() => _selectedCondition = newValue!),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!["Is Blank", "Is Not Blank"].contains(_selectedCondition))
            SizedBox(
              height: 24,
              child: TextField(
                controller: _textCtrl,
                style: const TextStyle(fontSize: 10),
                decoration: const InputDecoration(
                    hintText: "Value...",
                    hintStyle: TextStyle(fontSize: 10),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8)
                ),
              ),
            ),
        ],
      ),
    );
  }
}
