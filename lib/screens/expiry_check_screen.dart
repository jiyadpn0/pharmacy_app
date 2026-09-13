import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pharmacy_provider.dart';
import '../providers/app_provider.dart';
import '../utils/theme_constants.dart';
import 'damage_expiry_screen.dart';
import '../widgets/erp_tooltip.dart';
import '../utils/app_formatters.dart';
import '../utils/report_pdf_generator.dart';
import '../utils/printer_service.dart';

class ExpiryCheckScreen extends StatefulWidget {
  const ExpiryCheckScreen({super.key});

  @override
  State<ExpiryCheckScreen> createState() => _ExpiryCheckScreenState();
}

class _ExpiryCheckScreenState extends State<ExpiryCheckScreen> {
  int _monthsLimit = 3;
  String _selectedStatus = "Expiring Soon";
  final Map<String, Map<String, dynamic>> _activeFilters = {};
  double _headerHeight = 52.0;

  final Map<String, double> _colWidths = {
    'name': 250, 'batch': 120, 'rack': 80, 'category': 120, 'stock': 80, 'expiry': 120
  };

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
    });
  }

  void _openAdvancedFilter(String colKey, String title, Offset position) async {
    final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);
    final rawList = _selectedStatus == "Expired" ? pharmacy.getExpiredProducts() : pharmacy.getExpiringProducts(_monthsLimit);
    
    List<String> uniqueVals = rawList.map((p) {
      if (colKey == 'name') return p.name;
      if (colKey == 'batch') return p.batch;
      if (colKey == 'rack') return p.rack;
      if (colKey == 'category') return p.category;
      if (colKey == 'stock') return p.stock.toString();
      if (colKey == 'expiry') return p.expiry;
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
      setState(() {});
    }
  }

  bool _matchesFilter(dynamic val, String colKey) {
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

  @override
  Widget build(BuildContext context) {
    final pharmacy = Provider.of<PharmacyProvider>(context);
    final expiring = pharmacy.getExpiringProducts(_monthsLimit);
    final expired = pharmacy.getExpiredProducts();

    final rawList = _selectedStatus == "Expired" ? expired : expiring;
    final filtered = rawList.where((p) {
      return _matchesFilter(p.name, 'name') &&
             _matchesFilter(p.batch, 'batch') &&
             _matchesFilter(p.rack, 'rack') &&
             _matchesFilter(p.category, 'category') &&
             _matchesFilter(p.stock, 'stock') &&
             _matchesFilter(p.expiry, 'expiry');
    }).toList();

    final c = AppColors.of(context);
    return Row(
      children: [
        _buildExpirySidebar(c, expired.length, expiring.length, filtered),
        Expanded(
          child: Container(
            color: c.background,
            child: Column(
              children: [
                _buildExpiryHeader(),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    decoration: AppStyles.cardDecorationOf(context),
                    clipBehavior: Clip.antiAlias,
                    child: _buildExpiryGrid(filtered, isCritical: _selectedStatus == "Expired"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpirySidebar(AppThemeColors c, int expiredCount, int expiringCount, List<Product> filteredItems) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: c.sidebarBg,
        border: Border(right: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.event_busy_rounded, color: AppColors.danger, size: 24),
              ),
              const SizedBox(width: 16),
              const Text("EXPIRY TRACK", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 40),
          Text("INVENTORY STATUS", style: AppStyles.label),
          const SizedBox(height: 16),
          _buildFilterTab("Expiring Soon", Icons.timer_rounded, count: expiringCount.toString(), color: AppColors.warning),
          _buildFilterTab("Expired", Icons.report_problem_rounded, count: expiredCount.toString(), color: AppColors.danger),
          const SizedBox(height: 40),
          Text("ANALYTICS RANGE", style: AppStyles.label),
          const SizedBox(height: 16),
          _buildRangeTab(1),
          _buildRangeTab(3),
          _buildRangeTab(6),
          _buildRangeTab(12),
          const Spacer(),
          _actionBtn("PRINT EXPIRY LIST", Icons.print_rounded, AppColors.primary, onTap: () => _printExpiryList(filteredItems)),
          if (_selectedStatus == "Expired" && filteredItems.isNotEmpty) ...[
            const SizedBox(height: 10),
            _actionBtn(
              "RETURN TO SUPPLIER",
              Icons.assignment_return_rounded,
              Colors.orange.shade800,
              onTap: () => _convertToPurchaseReturn(filteredItems),
            ),
          ],
        ],
      ),
    );
  }

  void _convertToPurchaseReturn(List<Product> items) {
    if (items.isEmpty) return;
    final app = Provider.of<AppProvider>(context, listen: false);
    app.openPurchaseReturn(initialExpiredItems: items);
  }

  void _printExpiryList(List<Product> items) async {
    if (items.isEmpty) return;
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);
    
    final headers = ["Name", "Batch", "Expiry", "Stock", "Rack", "Category"];
    final data = items.map((p) => [
      p.name,
      p.batch,
      p.expiry,
      p.stock.toString(),
      p.rack,
      p.category,
    ]).toList();

    final doc = await ReportPdfGenerator.buildReportPdf(
      title: "Expiry Inventory Report",
      headers: headers,
      data: data,
      company: pharma.companyProfile,
      subtitle: "Type: $_selectedStatus | Range: $_monthsLimit Months | Count: ${items.length}",
    );

    if (!mounted) return;
    PrinterService.showProfessionalPreview(
      context: context,
      doc: doc,
      title: "Expiry Report Preview",
    );
  }

  Widget _buildFilterTab(String label, IconData icon, {required String count, required Color color}) {
    bool isSelected = _selectedStatus == label;
    return InkWell(
      onTap: () => setState(() => _selectedStatus = label),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))] : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? color : Colors.blueGrey.shade300),
            const SizedBox(width: 16),
            Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600, color: isSelected ? AppColors.primary : Colors.blueGrey.shade600))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Text(count, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRangeTab(int months) {
    bool isSelected = _monthsLimit == months;
    return InkWell(
      onTap: () => setState(() => _monthsLimit = months),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: 16, color: isSelected ? AppColors.secondary : Colors.grey),
            const SizedBox(width: 12),
            Text("Within $months Months", style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500, color: isSelected ? AppColors.primary : Colors.blueGrey)),
          ],
        ),
      ),
    );
  }

  Widget _buildExpiryHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: Colors.blueGrey),
          const SizedBox(width: 12),
          Text(
            "Reviewing products that are ${ _selectedStatus == 'Expired' ? 'already beyond their shelf life' : 'approaching their expiry dates' }.",
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.blueGrey.shade600),
          ),
          const Spacer(),
          _actionBtn("REMOVE EXPIRED STOCK", Icons.delete_sweep_rounded, AppColors.danger, width: 220, onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const DamageExpiryScreen()));
          }),
        ],
      ),
    );
  }

  Widget _buildExpiryGrid(List<Product> products, {required bool isCritical}) {
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            height: _headerHeight,
            color: const Color(0xFFF5F5F5), // Standardized ERP Header Background
            child: Row(
              children: [
                const SizedBox(width: 40, child: Center(child: Text("SL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)))),
                _hdr("MEDICINE NAME", 'name', flex: 1),
                _hdr("BATCH NO", 'batch', width: _colWidths['batch']!),
                _hdr("RACK", 'rack', width: _colWidths['rack']!),
                _hdr("CATEGORY", 'category', width: _colWidths['category']!),
                _hdr("STOCK", 'stock', width: _colWidths['stock']!),
                _hdr("EXPIRY DATE", 'expiry', width: _colWidths['expiry']!),
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 40 + _colWidths.values.fold(0.0, (sum, w) => sum + w),
              child: ListView.builder(
                itemCount: products.length,
                itemBuilder: (context, i) {
                  final p = products[i];
                  return Container(
                    height: 40,
                    decoration: BoxDecoration(color: i % 2 == 0 ? Colors.white : Colors.grey.shade50, border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
                    child: Row(
                      children: [
                        _Cell("${i + 1}", width: 40, align: TextAlign.center, color: Colors.grey),
                        _Cell(p.name, width: _colWidths['name']!, fontWeight: FontWeight.w800, color: AppColors.primary),
                        _Cell(cleanBatch(p.batch), width: _colWidths['batch']!, fontWeight: FontWeight.bold),
                        _Cell(p.rack, width: _colWidths['rack']!, color: AppColors.accent, fontWeight: FontWeight.w900),
                        _Cell(p.category, width: _colWidths['category']!),
                        _Cell("${p.stock} units", width: _colWidths['stock']!, align: TextAlign.right, fontWeight: FontWeight.w900),
                        _Cell(p.expiry, width: _colWidths['expiry']!, align: TextAlign.center, color: isCritical ? AppColors.danger : AppColors.warning, fontWeight: FontWeight.w900),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _hdr(String title, String key, {double? width, int? flex}) {
    return _Hdr(
      title: title,
      width: width ?? _colWidths[key]!,
      flex: flex,
      onQuickFilter: (c, v) => _applyQuickFilter(key, c, v),
      onAdvancedTap: (pos) => _openAdvancedFilter(key, title, pos),
      onResize: (v) => setState(() => _colWidths[key] = v.clamp(40, 500)),
      onHeightResize: (v) => setState(() => _headerHeight = v.clamp(40, 150)),
    );
  }
}

class _Hdr extends StatefulWidget {
  final String title;
  final double width;
  final int? flex;
  final String columnType;
  final Function(String condition, String value) onQuickFilter;
  final Function(Offset position)? onAdvancedTap;
  final Function(double) onResize;
  final Function(double) onHeightResize;

  const _Hdr({required this.title, required this.width, this.flex, required this.onQuickFilter, this.onAdvancedTap, required this.onResize, required this.onHeightResize}) : columnType = 'text';

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
      if (_quickCtrl.text.isNotEmpty) widget.onQuickFilter(_quickCondition, _quickCtrl.text);
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
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8, top: 4, bottom: 2),
                        child: Text(
                          widget.title,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
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
                  margin: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTapDown: _showQuickConditionMenu,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          color: Colors.grey.shade100,
                          alignment: Alignment.center,
                          child: Text(
                              _getConditionSymbol(),
                              style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _quickCtrl,
                          style: const TextStyle(fontSize: 10),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                            border: InputBorder.none,
                          ),
                          onChanged: (val) {
                            widget.onQuickFilter(_quickCondition, val);
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Resize handles
            Positioned(
              right: 0, top: 0, bottom: 0,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) => widget.onResize(widget.width + details.delta.dx),
                  child: Container(width: 4),
                ),
              ),
            ),
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) {
                     final rb = context.findRenderObject() as RenderBox;
                     widget.onHeightResize(rb.size.height + details.delta.dy);
                  },
                  child: Container(height: 4),
                ),
              ),
            )
          ],
        ),
      ),
    );
    return widget.flex != null ? Expanded(flex: widget.flex!, child: content) : content;
  }
}

class _Cell extends StatelessWidget {
  final String text; final double? width; final int? flex; final TextAlign align; final Color? color; final FontWeight fontWeight;
  const _Cell(this.text, {this.width, this.align = TextAlign.left, this.color, this.fontWeight = FontWeight.w600}) : flex = null;
  @override Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget child = ERPTooltip(
      message: text,
      child: Container(
        width: width, alignment: align == TextAlign.left ? Alignment.centerLeft : Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(text, textAlign: align, style: TextStyle(fontSize: 13, color: color ?? c.primaryText, fontWeight: fontWeight), overflow: TextOverflow.ellipsis),
      ),
    );
    return flex != null ? Expanded(flex: flex!, child: child) : child;
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

Widget _actionBtn(String label, IconData icon, Color color, {VoidCallback? onTap, double? width}) {
  return SizedBox(
    width: width ?? double.infinity,
    child: ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
    ),
  );
}
