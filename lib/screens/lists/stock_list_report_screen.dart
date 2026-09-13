import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/pharmacy_provider.dart';
import '../../widgets/advanced_filter.dart';
import '../../widgets/erp_tooltip.dart';
import '../../utils/app_formatters.dart';
import '../../utils/theme_constants.dart';

class StockListReportScreen extends StatefulWidget {
  const StockListReportScreen({super.key});

  @override
  State<StockListReportScreen> createState() => _StockListReportScreenState();
}

class _StockListReportScreenState extends State<StockListReportScreen> {
  final Map<int, Map<String, dynamic>> _activeFilters = {};
  final Map<int, ColumnFilterState> _advancedFilters = {};
  final Map<int, _SummaryType> _colSummaryTypes = {};
  final List<double> _colW = [250, 150, 70, 100, 75, 65, 65, 50, 80, 90, 60, 45, 100, 100, 60];
  double _headerHeight = 52.0;
  int _selectedRowIndex = -1;
  int _selectedColIndex = -1;

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < _colW.length; i++) {
      FilterType type = FilterType.text;
      if ([2, 5, 6, 7, 8, 9, 11].contains(i)) type = FilterType.numeric;
      if (i == 4) type = FilterType.date;
      _advancedFilters[i] = ColumnFilterState(type: type);
    }
  }

  void _applyQuickFilter(int idx, String condition, String value) {
    setState(() {
      if (condition == 'Clear' || value.isEmpty) {
        _activeFilters.remove(idx);
      } else {
        _activeFilters[idx] = {
          'condition': condition,
          'value': value,
        };
      }
    });
  }

  bool _matchesFilter(Product p) {
    if (_activeFilters.isNotEmpty) {
      for (var entry in _activeFilters.entries) {
        int colIdx = entry.key;
        String condition = entry.value['condition'];
        String filterVal = entry.value['value'].toString().toLowerCase();
        dynamic rawVal = _getColValue(p, colIdx);
        String itemVal = rawVal?.toString().toLowerCase() ?? "";
        bool match = true;
        switch (condition) {
          case 'Equals': match = itemVal == filterVal; break;
          case 'Does Not Equal': match = itemVal != filterVal; break;
          case 'Contains': match = itemVal.contains(filterVal); break;
          case 'Does Not Contain': match = !itemVal.contains(filterVal); break;
          case 'Begins With': match = itemVal.startsWith(filterVal); break;
          case 'Ends With': match = itemVal.endsWith(filterVal); break;
          case 'Greater Than':
            double? iNum = double.tryParse(itemVal); double? fNum = double.tryParse(filterVal);
            match = iNum != null && fNum != null && iNum > fNum; break;
          case 'Less Than':
            double? iNum = double.tryParse(itemVal); double? fNum = double.tryParse(filterVal);
            match = iNum != null && fNum != null && iNum < fNum; break;
          default: match = true;
        }
        if (!match) return false;
      }
    }
    for (int i = 0; i < _colW.length; i++) {
      if (_advancedFilters.containsKey(i)) {
        if (!_advancedFilters[i]!.matches(_getColValue(p, i))) return false;
      }
    }
    return true;
  }

  String _fmt(double v) => v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0*$'), '');

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PharmacyProvider>();
    final List<Product> inventoryItems = provider.products.where((p) => p.stock > 0).toList();
    final List<Product> filteredItems = inventoryItems.where((p) => _matchesFilter(p)).toList();

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(filteredItems.length),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 40 + _colW.fold<double>(0.0, (a, b) => a + b),
                child: Column(
                  children: [
                    _buildTableHeader(),
                    Expanded(
                      child: ListView.builder(
                        itemExtent: 35.0,
                        itemCount: filteredItems.length,
                        itemBuilder: (context, index) {
                          final p = filteredItems[index];
                          final isRowSelected = _selectedRowIndex == index;
                          return InkWell(
                            onTap: () => setState(() { _selectedRowIndex = index; _selectedColIndex = -1; }),
                            child: Container(
                              height: 35,
                              decoration: BoxDecoration(color: isRowSelected ? Colors.blue.shade50 : Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 0.5))),
                              child: Row(
                                children: [
                                  _Cell("${index + 1}", width: 40, textAlign: TextAlign.right),
                                  _Cell(p.name, width: _colW[0], fontWeight: FontWeight.bold, isSelected: _selectedColIndex == 0),
                                  _Cell(p.manufacturer, width: _colW[1], isSelected: _selectedColIndex == 1),
                                  _StockCell(p.stock, width: _colW[2], isSelected: _selectedColIndex == 2),
                                  _Cell(cleanBatch(p.batch), width: _colW[3], color: Colors.green.shade900, isSelected: _selectedColIndex == 3),
                                  _Cell(p.expiry, width: _colW[4], textAlign: TextAlign.left, isSelected: _selectedColIndex == 4),
                                  _Cell(_fmt(p.mrp), width: _colW[5], textAlign: TextAlign.right, isSelected: _selectedColIndex == 5),
                                  _Cell(_fmt(p.purchaseRate), width: _colW[6], textAlign: TextAlign.right, isSelected: _selectedColIndex == 6),
                                  _Cell("${p.packSize}", width: _colW[7], textAlign: TextAlign.left, isSelected: _selectedColIndex == 7),
                                  _Cell(_fmt(p.stock * (p.mrp / (p.packSize == 0 ? 1 : p.packSize))), width: _colW[8], textAlign: TextAlign.right, fontWeight: FontWeight.bold, color: Colors.blue.shade900, isSelected: _selectedColIndex == 8),
                                  _Cell(_fmt(p.stock * (p.purchaseRate / (p.packSize == 0 ? 1 : p.packSize))), width: _colW[9], textAlign: TextAlign.right, fontWeight: FontWeight.bold, color: Colors.green.shade900, isSelected: _selectedColIndex == 9),
                                  _Cell(p.rack, width: _colW[10], textAlign: TextAlign.left, isSelected: _selectedColIndex == 10),
                                  _Cell("${p.gstPercent.toStringAsFixed(0)}%", width: _colW[11], textAlign: TextAlign.left, isSelected: _selectedColIndex == 11),
                                  _Cell(p.category, width: _colW[12], isSelected: _selectedColIndex == 12),
                                  _Cell(p.subCategory, width: _colW[13], isSelected: _selectedColIndex == 13),
                                  Container(
                                    width: _colW[14],
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(color: _selectedColIndex == 14 ? Colors.blue.withValues(alpha: 0.1) : null, border: const Border(right: BorderSide(color: Colors.grey, width: 0.5))),
                                    child: IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18), padding: EdgeInsets.zero, onPressed: () => _confirmDeleteProduct(context, p)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    _buildSummaryRow(filteredItems),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteProduct(BuildContext context, Product product) {
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("Delete Product?"), content: Text("Are you sure you want to delete '${product.name}'? This will remove it from inventory."), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")), ElevatedButton(onPressed: () async { await Provider.of<PharmacyProvider>(context, listen: false).deleteProduct(product.id); if (ctx.mounted) { Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("'${product.name}' deleted."), backgroundColor: Colors.red)); } }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text("DELETE"))]));
  }

  Widget _buildSummaryRow(List<Product> products) {
    final Map<int, String> summaryValues = {};

    if (products.isNotEmpty) {
      _colSummaryTypes.forEach((colIndex, type) {
        if (type == _SummaryType.none) return;

        final values = products.map((p) {
          final val = _getColValue(p, colIndex);
          if (val is num) return val.toDouble();
          return double.tryParse(val.toString()) ?? 0.0;
        }).toList();

        switch (type) {
          case _SummaryType.sum:
            summaryValues[colIndex] = _fmt(values.fold(0.0, (a, b) => a + b));
            break;
          case _SummaryType.min:
            summaryValues[colIndex] = _fmt(values.reduce((a, b) => a < b ? a : b));
            break;
          case _SummaryType.max:
            summaryValues[colIndex] = _fmt(values.reduce((a, b) => a > b ? a : b));
            break;
          case _SummaryType.count:
            summaryValues[colIndex] = products.length.toString();
            break;
          case _SummaryType.average:
            summaryValues[colIndex] = _fmt(values.fold(0.0, (a, b) => a + b) / products.length);
            break;
          case _SummaryType.none:
            break;
        }
      });
    }

    return Container(
      height: 35,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        border: Border(top: BorderSide(color: Colors.grey.shade400, width: 1)),
      ),
      child: Row(
        children: [
          Container(width: 40, decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.white, width: 0.5)))),
          ...List.generate(_colW.length, (i) => _summaryCell(i, _colW[i], summaryValues[i] ?? "")),
        ],
      ),
    );
  }

  Widget _summaryCell(int colIndex, double width, String displayValue) {
    return GestureDetector(
      onSecondaryTapDown: (details) => _showSummaryMenu(details.globalPosition, colIndex),
      child: Container(
        width: width,
        height: 35,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.white, width: 0.5))),
        child: Text(
          displayValue,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  void _showSummaryMenu(Offset position, int colIndex) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<_SummaryType>(context: context, position: RelativeRect.fromRect(position & const Size(40, 40), Offset.zero & overlay.size), items: [_summaryMenuItem(_SummaryType.sum, "Σ Sum"), _summaryMenuItem(_SummaryType.min, ".|l Min"), _summaryMenuItem(_SummaryType.max, ".|I Max"), _summaryMenuItem(_SummaryType.count, "N Count"), _summaryMenuItem(_SummaryType.average, "Σ/N Average"), const PopupMenuDivider(), _summaryMenuItem(_SummaryType.none, "✓ None")]).then((value) { if (value != null) setState(() => _colSummaryTypes[colIndex] = value); });
  }

  PopupMenuItem<_SummaryType> _summaryMenuItem(_SummaryType type, String text) => PopupMenuItem(value: type, height: 30, child: Text(text, style: const TextStyle(fontSize: 11)));

  dynamic _getColValue(Product p, int colIndex) {
    switch (colIndex) {
      case 0: return p.name; case 1: return p.manufacturer; case 2: return p.stock; case 3: return p.batch; case 4: return p.expiry;
      case 5: return p.mrp; case 6: return p.purchaseRate; case 7: return p.packSize;
      case 8: return p.stock * (p.mrp / (p.packSize == 0 ? 1 : p.packSize));
      case 9: return p.stock * (p.purchaseRate / (p.packSize == 0 ? 1 : p.packSize));
      case 10: return p.rack; case 11: return p.gstPercent; case 12: return p.category; case 13: return p.subCategory;
      default: return "";
    }
  }

  Widget _buildHeader(int count) {
    return Container(padding: const EdgeInsets.all(12), color: const Color(0xFF003366), child: const Row(children: [Icon(Icons.inventory, color: Colors.white, size: 20), SizedBox(width: 10), Text("INVENTORY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))]));
  }

  Widget _buildTableHeader() {
    return Container(
      height: _headerHeight,
      color: const Color(0xFFF5F5F5), // Standardized ERP Header Background
      child: Row(
        children: [
          const SizedBox(width: 40, child: Center(child: Text("SL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)))),
          _hdr("MEDICINE NAME", 0, flex: 1),
          _hdr("PATENT", 1),
          _hdr("STOCK", 2, columnType: 'numeric'),
          _hdr("BATCH", 3),
          _hdr("EXPIRY", 4),
          _hdr("MRP", 5, columnType: 'numeric'),
          _hdr("L COST", 6, columnType: 'numeric'),
          _hdr("PACK", 7, columnType: 'numeric'),
          _hdr("MRP VALUE", 8, columnType: 'numeric'),
          _hdr("TOTAL L COST VALUE", 9, columnType: 'numeric'),
          _hdr("RACK", 10),
          _hdr("GST", 11, columnType: 'numeric'),
          _hdr("CATEGORY", 12),
          _hdr("SUB CAT", 13),
          Container(width: _colW[14], padding: const EdgeInsets.symmetric(horizontal: 8), alignment: Alignment.centerLeft, child: const Text("DELETE", style: TextStyle(color: Colors.blueGrey, fontSize: 10, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _hdr(String title, int idx, {double? width, int? flex, String columnType = 'text'}) {
    return _Hdr(
      title: title,
      width: width ?? _colW[idx],
      flex: flex?.toDouble(),
      columnType: columnType,
      onQuickFilter: (c, v) => _applyQuickFilter(idx, c, v),
      onAdvancedTap: (pos) => _openAdvancedFilterDialog(idx, pos),
      onResize: (v) => setState(() => _colW[idx] = v.clamp(40, 500)),
      onHeightResize: (v) => setState(() => _headerHeight = v.clamp(40, 150)),
    );
  }

  void _openAdvancedFilterDialog(int idx, Offset position) async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final allItems = provider.products.where((p) => p.stock > 0).toList();
    final List<dynamic> values = allItems.map((p) => _getColValue(p, idx)).toList();
    final state = _advancedFilters[idx]!;
    await showDialog(context: context, barrierColor: Colors.transparent, builder: (ctx) => Stack(children: [Positioned(left: position.dx, top: position.dy + 10, child: AdvancedFilterPopup(type: state.type, filterState: state, allValues: values, onApply: () { state.isActive = true; setState(() {}); Navigator.pop(ctx); }, onClear: () { state.clear(); setState(() {}); Navigator.pop(ctx); }))]));
  }
}

class _Cell extends StatelessWidget {
  final String text; final double width; final TextAlign textAlign; final FontWeight fontWeight; final Color? color; final bool isSelected;
  const _Cell(this.text, {required this.width, this.textAlign = TextAlign.left, this.fontWeight = FontWeight.normal, this.color, this.isSelected = false});
  @override Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ERPTooltip(
      message: text,
      child: Container(width: width, padding: const EdgeInsets.symmetric(horizontal: 8), alignment: textAlign == TextAlign.left ? Alignment.centerLeft : Alignment.centerRight, decoration: BoxDecoration(color: isSelected ? Colors.blue.withValues(alpha: 0.1) : null, border: Border(right: BorderSide(color: c.border, width: 0.5))), child: Text(text, style: TextStyle(fontSize: 12, fontWeight: fontWeight, color: color ?? c.primaryText), overflow: TextOverflow.ellipsis)),
    );
  }
}

class _StockCell extends StatelessWidget {
  final int stock; final double width; final bool isSelected;
  const _StockCell(this.stock, {required this.width, this.isSelected = false});
  @override Widget build(BuildContext context) => ERPTooltip(
    message: "$stock units",
    child: Container(width: width, padding: const EdgeInsets.symmetric(horizontal: 8), alignment: Alignment.centerRight, decoration: BoxDecoration(color: isSelected ? Colors.blue.withValues(alpha: 0.1) : null, border: const Border(right: BorderSide(color: Colors.grey, width: 0.5))), child: Text("$stock", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue))),
  );
}

enum _SummaryType { none, sum, min, max, count, average }

class _Hdr extends StatefulWidget {
  final String title; final double width; final double? flex; final String columnType; final Function(String condition, String value) onQuickFilter; final Function(Offset position)? onAdvancedTap; final Function(double) onResize; final Function(double) onHeightResize;
  const _Hdr({required this.title, required this.width, this.flex, this.columnType = 'text', required this.onQuickFilter, this.onAdvancedTap, required this.onResize, required this.onHeightResize});
  @override State<_Hdr> createState() => _HdrState();
}

class _HdrState extends State<_Hdr> {
  String _quickCondition = 'Contains'; final TextEditingController _quickCtrl = TextEditingController(); bool _isHovered = false;
  @override void initState() { super.initState(); _quickCondition = widget.columnType == 'text' ? 'Contains' : 'Equals'; }
  @override void dispose() { _quickCtrl.dispose(); super.dispose(); }
  String _getConditionSymbol() { switch (_quickCondition) { case 'Equals': return '='; case 'Does Not Equal': return '≠'; case 'Contains': return 'inc'; case 'Does Not Contain': return '!inc'; case 'Begins With': return 'A..'; case 'Ends With': return '..Z'; case 'Greater Than': return '>'; case 'Less Than': return '<'; default: return '='; } }
  void _showQuickConditionMenu(TapDownDetails details) async { final items = widget.columnType == 'text' ? ['Equals', 'Does Not Equal', 'Contains', 'Does Not Contain', 'Begins With', 'Ends With'] : ['Equals', 'Does Not Equal', 'Greater Than', 'Less Than']; final result = await showMenu<String>(context: context, position: RelativeRect.fromLTRB(details.globalPosition.dx, details.globalPosition.dy + 10, details.globalPosition.dx, 0), items: items.map((e) => PopupMenuItem(value: e, height: 30, child: Text(e, style: const TextStyle(fontSize: 12)))).toList()); if (result != null) { setState(() => _quickCondition = result); if (_quickCtrl.text.isNotEmpty) { widget.onQuickFilter(_quickCondition, _quickCtrl.text); } } }
  @override Widget build(BuildContext context) {
    bool showFilter = _isHovered || _quickCtrl.text.isNotEmpty;
    Widget content = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true), onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        width: widget.width, decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade300, width: 1), bottom: BorderSide(color: Colors.grey.shade400, width: 1))),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [Expanded(child: Padding(padding: const EdgeInsets.only(left: 8, top: 4, bottom: 2), child: Text(widget.title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade800), overflow: TextOverflow.ellipsis))), Opacity(opacity: showFilter ? 1.0 : 0.0, child: GestureDetector(onTapDown: (details) => widget.onAdvancedTap?.call(details.globalPosition), child: Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.filter_alt_outlined, size: 14, color: Colors.blueGrey.shade600))))]),
                Container(height: 20, margin: const EdgeInsets.fromLTRB(4, 0, 4, 4), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(2)), child: Row(children: [GestureDetector(onTapDown: _showQuickConditionMenu, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4), color: Colors.grey.shade100, alignment: Alignment.center, child: Text(_getConditionSymbol(), style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)))), Expanded(child: TextField(controller: _quickCtrl, style: const TextStyle(fontSize: 10), decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6), border: InputBorder.none), onChanged: (val) { widget.onQuickFilter(_quickCondition, val); setState(() {}); }))]))
              ],
            ),
            Positioned(right: 0, top: 0, bottom: 0, child: MouseRegion(cursor: SystemMouseCursors.resizeLeftRight, child: GestureDetector(behavior: HitTestBehavior.opaque, onHorizontalDragUpdate: (details) => widget.onResize(widget.width + details.delta.dx), child: Container(width: 4)))),
            Positioned(left: 0, right: 0, bottom: 0, child: MouseRegion(cursor: SystemMouseCursors.resizeUpDown, child: GestureDetector(behavior: HitTestBehavior.opaque, onVerticalDragUpdate: (details) { final rb = context.findRenderObject() as RenderBox; widget.onHeightResize(rb.size.height + details.delta.dy); }, child: Container(height: 4)))),
          ],
        ),
      ),
    );
    if (widget.flex != null) return Expanded(flex: (widget.flex! * 10).toInt(), child: content);
    return content;
  }
}
