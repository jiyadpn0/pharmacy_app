import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../providers/pharmacy_provider.dart';
import '../../utils/theme_constants.dart';

class ProductMappingReportScreen extends StatefulWidget {
  const ProductMappingReportScreen({super.key});

  @override
  State<ProductMappingReportScreen> createState() => _ProductMappingReportScreenState();
}

class _ProductMappingReportScreenState extends State<ProductMappingReportScreen> {
  final Map<String, Map<String, dynamic>> _activeFilters = {};
  List<ProductMapping> _displayData = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshData());
  }

  void _showMappingHeadingsHint() {
    final List<String> fields = [
      "Wholesaler", "Wholesaler Stock Number", "Wholesaler Stock Name",
      "(Mapped) My Stock Name", "Product ID"
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 10),
            Text("Mapping Export Headings", style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("The exported Excel file will contain these columns:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: fields.map((h) => Chip(
                  label: Text(h, style: const TextStyle(fontSize: 11)),
                  backgroundColor: Colors.blue.shade50,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                )).toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: fields.join("\t")));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Headings copied to clipboard!"), duration: Duration(seconds: 1)));
            },
            child: const Text("COPY ALL"),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK")),
        ],
      ),
    );
  }

  void _applyQuickFilter(String col, String condition, String value) {
    setState(() {
      if (condition == 'Clear' || value.isEmpty) {
        _activeFilters.remove(col);
      } else {
        _activeFilters[col] = {
          'condition': condition,
          'value': value,
        };
      }
      _applyFilters();
    });
  }

  void _openAdvancedFilter(String colKey, String title, Offset position) async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    List<String> uniqueVals = provider.productMappings.map((m) {
      if (colKey == 'wholesaler') return m.wholesalerName;
      if (colKey == 'external_code') return m.externalCode;
      if (colKey == 'external_name') return m.externalName;
      if (colKey == 'internal_name') return m.internalName;
      if (colKey == 'product_id') return m.productId;
      return "";
    }).toSet().toList();
    uniqueVals.sort();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => Stack(
        children: [
          Positioned(
            top: position.dy + 10,
            left: (position.dx - 100).clamp(0, MediaQuery.of(context).size.width - 250),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(4),
              child: _AdvancedFilterPopup(
                columnName: title,
                uniqueValues: uniqueVals,
                initialFilter: _activeFilters[colKey],
              ),
            ),
          )
        ],
      ),
    );

    if (result != null) {
      if (result['condition'] == 'Clear') {
        _activeFilters.remove(colKey);
      } else {
        _activeFilters[colKey] = result;
      }
      _applyFilters();
    }
  }

  bool _matchesFilterLogic(dynamic val, String colKey) {
    if (!_activeFilters.containsKey(colKey)) return true;
    final filter = _activeFilters[colKey]!;
    String condition = filter['condition'];

    if (condition == 'Values') {
      List<String> selected = List<String>.from(filter['selected']);
      return selected.contains(val?.toString() ?? "");
    }

    String filterVal = filter['value'].toString().toLowerCase();
    String itemVal = val?.toString().toLowerCase() ?? "";

    switch (condition) {
      case 'Equals': return itemVal == filterVal;
      case 'Does Not Equal': return itemVal != filterVal;
      case 'Contains': return itemVal.contains(filterVal);
      case 'Does Not Contain': return !itemVal.contains(filterVal);
      case 'Begins With': return itemVal.startsWith(filterVal);
      case 'Ends With': return itemVal.endsWith(filterVal);
      default: return true;
    }
  }

  void _refreshData() {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    setState(() {
      _displayData = List.from(provider.productMappings);
      _applyFilters();
    });
  }

  void _applyFilters() {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    List<ProductMapping> filtered = List.from(provider.productMappings);

    if (_activeFilters.isNotEmpty) {
      filtered = filtered.where((m) {
        return _matchesFilterLogic(m.wholesalerName, 'wholesaler') &&
               _matchesFilterLogic(m.externalCode, 'external_code') &&
               _matchesFilterLogic(m.externalName, 'external_name') &&
               _matchesFilterLogic(m.internalName, 'internal_name') &&
               _matchesFilterLogic(m.productId, 'product_id');
      }).toList();
    }

    setState(() {
      _displayData = filtered;
    });
  }

  void _export() async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Select where to save Product Mapping Excel:',
      fileName: 'product_mappings_export.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (outputFile != null) {
      try {
        final bytes = await provider.exportProductMappingsToExcelBytes();
        if (bytes != null) {
          await File(outputFile).writeAsBytes(bytes);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text("Mappings exported successfully!")));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text("Export failed: $e")));
        }
      }
    }
  }

  void _deleteMapping(ProductMapping mapping) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Mapping?"),
        content: Text("Are you sure you want to delete the mapping for '${mapping.externalName}'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () async {
              final provider = Provider.of<PharmacyProvider>(context, listen: false);
              await provider.deleteProductMapping(mapping.id, mapping.wholesalerName, mapping.externalName, mapping.externalCode);
              Navigator.pop(ctx);
              _refreshData();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("DELETE"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildDataGrid()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 200,
      color: const Color(0xFFF1F5F9),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("MAPPING ACTIONS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _refreshData,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text("Refresh List"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _export,
            icon: const Icon(Icons.download, size: 16),
            label: const Text("Export Excel"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _showMappingHeadingsHint,
            icon: const Icon(Icons.priority_high, size: 14),
            label: const Text("Headings Info", style: TextStyle(fontSize: 10)),
            style: TextButton.styleFrom(foregroundColor: Colors.blueGrey, padding: EdgeInsets.zero),
          ),
          const Spacer(),
          const Text("TOTAL MAPPINGS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.grey)),
          Text("${_displayData.length}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Colors.blueGrey)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFE2E8F0),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: const Text(
        "PRODUCT MAPPING MANAGER (AUTO-GENERATED FROM PURCHASE)",
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
      ),
    );
  }

  Widget _buildDataGrid() {
    return Column(
      children: [
        Container(
          color: const Color(0xFFF5F5F5), // Standardized ERP Header Background
          child: Row(
            children: [
              _Hdr(title: "Wholesaler", flex: 2, onQuickFilter: (c, v) => _applyQuickFilter('wholesaler', c, v), onAdvancedTap: (pos) => _openAdvancedFilter('wholesaler', "Wholesaler", pos)),
              _Hdr(title: "Wholesaler Stock Number", flex: 1.5, onQuickFilter: (c, v) => _applyQuickFilter('external_code', c, v), onAdvancedTap: (pos) => _openAdvancedFilter('external_code', "Wholesaler Stock Number", pos)),
              _Hdr(title: "Wholesaler Stock Name", flex: 3, onQuickFilter: (c, v) => _applyQuickFilter('external_name', c, v), onAdvancedTap: (pos) => _openAdvancedFilter('external_name', "Wholesaler Stock Name", pos)),
              _Hdr(title: "(Mapped) My Stock Name", flex: 3, onQuickFilter: (c, v) => _applyQuickFilter('internal_name', c, v), onAdvancedTap: (pos) => _openAdvancedFilter('internal_name', "Mapped My Stock Name", pos)),
              _Hdr(title: "Product ID", flex: 1.5, onQuickFilter: (c, v) => _applyQuickFilter('product_id', c, v), onAdvancedTap: (pos) => _openAdvancedFilter('product_id', "Product ID", pos)),
              const Expanded(flex: 10, child: Center(child: Text("Actions", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)))),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _displayData.length,
            itemBuilder: (ctx, i) {
              final columns = [
                _ColInfo("wholesaler", "Wholesaler", flex: 2),
                _ColInfo("external_code", "Wholesaler Stock Number", flex: 1.5),
                _ColInfo("external_name", "Wholesaler Stock Name", flex: 3),
                _ColInfo("internal_name", "(Mapped) My Stock Name", flex: 3),
                _ColInfo("product_id", "Product ID", flex: 1.5),
                _ColInfo("actions", "Actions", flex: 1),
              ];
              return _buildGridRow(_displayData[i], columns, i);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGridRow(ProductMapping m, List<_ColInfo> columns, int index) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: index % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC),
        border: const Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 0.5)),
      ),
      child: Row(
        children: columns.map((col) {
          if (col.key == "actions") {
            return Expanded(
              flex: (col.flex * 10).toInt(),
              child: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 16),
                onPressed: () => _deleteMapping(m),
                tooltip: "Delete Mapping",
              ),
            );
          }

          String text = "";
          if (col.key == "wholesaler") {
            text = m.wholesalerName;
          } else if (col.key == "external_code") text = m.externalCode;
          else if (col.key == "external_name") text = m.externalName;
          else if (col.key == "internal_name") text = m.internalName;
          else if (col.key == "product_id") text = m.productId;

          return Expanded(
            flex: (col.flex * 10).toInt(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              child: Text(text, style: const TextStyle(fontSize: 11, color: Color(0xFF334155)), overflow: TextOverflow.ellipsis),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _Hdr extends StatefulWidget {
  final String title;
  final double? width;
  final num? flex;
  final TextAlign align;
  final String columnType;
  final Function(String condition, String value)? onQuickFilter;
  final Function(Offset position)? onAdvancedTap;

  const _Hdr({
    super.key,
    required this.title,
    this.width,
    this.flex,
    this.align = TextAlign.left,
    this.columnType = 'text',
    this.onQuickFilter,
    this.onAdvancedTap,
  });

  @override
  State<_Hdr> createState() => _HdrState();
}

class _HdrState extends State<_Hdr> {
  String _quickCondition = 'Contains';
  final TextEditingController _quickCtrl = TextEditingController();
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _quickCondition = widget.columnType == 'text' ? 'Contains' : 'Equals';
  }

  @override
  void dispose() {
    _quickCtrl.dispose();
    super.dispose();
  }

  String _getConditionSymbol() {
    switch (_quickCondition) {
      case 'Equals': return '=';
      case 'Does Not Equal': return '≠';
      case 'Contains': return 'inc';
      case 'Does Not Contain': return '!inc';
      case 'Begins With': return 'A..';
      case 'Ends With': return '..Z';
      default: return '=';
    }
  }

  void _showQuickConditionMenu(TapDownDetails details) async {
    final items = ['Equals', 'Does Not Equal', 'Contains', 'Does Not Contain', 'Begins With', 'Ends With'];
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(details.globalPosition.dx, details.globalPosition.dy + 10, details.globalPosition.dx, 0),
      items: items.map((e) => PopupMenuItem(value: e, height: 30, child: Text(e, style: const TextStyle(fontSize: 12)))).toList(),
    );
    if (result != null) {
      setState(() => _quickCondition = result);
      if (_quickCtrl.text.isNotEmpty) widget.onQuickFilter?.call(_quickCondition, _quickCtrl.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool showFilter = _isHovered || _quickCtrl.text.isNotEmpty;
    Widget content = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        width: widget.width,
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: Colors.grey.shade300, width: 1),
            bottom: BorderSide(color: Colors.grey.shade400, width: 1),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Padding(padding: const EdgeInsets.only(left: 8, top: 4), child: Text(widget.title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade800), overflow: TextOverflow.ellipsis))),
                Opacity(
                  opacity: showFilter ? 1.0 : 0.0,
                  child: GestureDetector(
                    onTapDown: (details) => widget.onAdvancedTap?.call(details.globalPosition),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.filter_alt_outlined, size: 14, color: Colors.blueGrey.shade600),
                    ),
                  ),
                ),
              ],
            ),
            Container(
              height: 20,
              margin: const EdgeInsets.fromLTRB(4, 2, 4, 4),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                children: [
                  GestureDetector(onTapDown: _showQuickConditionMenu, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4), color: Colors.grey.shade100, child: Text(_getConditionSymbol(), style: const TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.bold)))),
                  Expanded(child: TextField(controller: _quickCtrl, style: const TextStyle(fontSize: 10), decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6), border: InputBorder.none), onChanged: (v) { widget.onQuickFilter?.call(_quickCondition, v); setState(() {}); })),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (widget.flex != null) return Expanded(flex: (widget.flex! * 10).toInt(), child: content);
    return content;
  }
}

class _AdvancedFilterPopup extends StatefulWidget {
  final String columnName;
  final List<String> uniqueValues;
  final Map<String, dynamic>? initialFilter;
  const _AdvancedFilterPopup({required this.columnName, required this.uniqueValues, this.initialFilter});
  @override State<_AdvancedFilterPopup> createState() => _AdvancedFilterPopupState();
}

class _AdvancedFilterPopupState extends State<_AdvancedFilterPopup> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<String> _filteredValues = [];
  Set<String> _selectedValues = {};

  @override
  void initState() {
    super.initState();
    _filteredValues = List.from(widget.uniqueValues);
    if (widget.initialFilter != null && widget.initialFilter!['selected'] != null) {
      _selectedValues = Set<String>.from(widget.initialFilter!['selected']);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250, height: 350,
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4)),
      child: Column(
        children: [
          Container(padding: const EdgeInsets.all(8), color: Colors.blueGrey.shade50, child: Row(children: [Text(widget.columnName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))])),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(hintText: "Search values...", prefixIcon: Icon(Icons.search, size: 16), isDense: true, border: OutlineInputBorder()),
              onChanged: (v) => setState(() => _filteredValues = widget.uniqueValues.where((e) => e.toLowerCase().contains(v.toLowerCase())).toList()),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredValues.length,
              itemBuilder: (ctx, i) => CheckboxListTile(
                title: Text(_filteredValues[i], style: const TextStyle(fontSize: 11)),
                value: _selectedValues.contains(_filteredValues[i]),
                onChanged: (v) => setState(() => v! ? _selectedValues.add(_filteredValues[i]) : _selectedValues.remove(_filteredValues[i])),
                dense: true, visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                TextButton(onPressed: () => Navigator.pop(context, {'condition': 'Clear'}), child: const Text("Clear")),
                const Spacer(),
                ElevatedButton(onPressed: () => Navigator.pop(context, {'condition': 'Values', 'selected': _selectedValues.toList()}), child: const Text("Apply")),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _ColInfo {
  final String key;
  final String label;
  final double flex;
  _ColInfo(this.key, this.label, {this.flex = 1});
}
