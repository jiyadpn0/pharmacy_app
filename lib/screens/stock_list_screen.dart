import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pharmacy_provider.dart';
import '../providers/app_provider.dart';
import '../utils/app_dialogs.dart';
import '../utils/theme_constants.dart';
import '../widgets/erp_tooltip.dart';
import '../utils/report_pdf_generator.dart';
import '../utils/printer_service.dart';

class StockListScreen extends StatefulWidget {
  const StockListScreen({super.key});

  @override
  State<StockListScreen> createState() => _StockListScreenState();
}

class _StockListScreenState extends State<StockListScreen> {
  String _selectedCategory = "Inventory";
  final Map<int, Map<String, dynamic>> _activeFilters = {};
  double _headerHeight = 52.0;
  int? _selectedRowIndex;

  final Map<int, double> _colWidths = {
    0: 250, // MEDICINE DESCRIPTION
    1: 100, // HSN CODE
    2: 70,  // PACK
    3: 120, // CATEGORY
    4: 120, // SUB CAT
    5: 120, // PATENT
    6: 70,  // GST %
    7: 100, // STOCK QTY
    8: 100, // PURCHASE RATE
    9: 100, // SALES PRICE
    10: 100,// MRP
    11: 150,// GENERIC NAME
    12: 80, // RACK
    13: 80, // S.DISC %
    14: 80, // SCHEDULE
    15: 80, // REORDER LEVEL
    16: 80, // MAX LEVEL
  };

  // CODE MASTER FIX: RAM Cache for filtered products to stop Build-Loop UI Freezing
  List<Product> _filteredProducts = [];

  String _getColValue(Product p, int colIdx, PharmacyProvider provider) {
    switch (colIdx) {
      case 0: return p.name;
      case 1: return p.hsnCode;
      case 2: return p.packSize.toString();
      case 3: return p.category;
      case 4: return p.subCategory;
      case 5: return p.patent;
      case 6: return p.gstPercent.toString();
      case 7: return p.stock.toString();
      case 8: return p.purchaseRate.toString();
      case 9: return p.salePrice.toString();
      case 10: return p.mrp.toString();
      case 11:
        String gen = p.genericName.trim();
        if (gen.isEmpty) {
          gen = provider.resolveGenericName(p.name, productId: p.id);
          if (gen.isNotEmpty) {
            p.genericName = gen;
          }
        }
        return gen;
      case 12: return p.rack;
      case 13: return p.sDiscPercent.toString();
      case 14: return p.schedule;
      case 15: return p.reorderLevel.toString();
      case 16: return p.maxLevel.toString();
      default: return "";
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recalculateFilters();
  }

  void _recalculateFilters([PharmacyProvider? pProvider]) {
    if (!mounted) return;
    final provider = pProvider ?? Provider.of<PharmacyProvider>(context, listen: false);
    setState(() {
      _filteredProducts = provider.productMaster.where((p) => _matchesFilter(p)).toList();
      _selectedRowIndex = null;
    });
  }

  @override
  void initState() {
    super.initState();
  }

  void _applyQuickFilter(int idx, String condition, String value) {
    if (condition == 'Clear' || value.isEmpty) {
      _activeFilters.remove(idx);
    } else {
      _activeFilters[idx] = {
        'condition': condition,
        'value': value,
      };
    }
    _recalculateFilters(); // CODE MASTER FIX
  }

  void _openAdvancedFilter(int idx, String title, Offset position) async {
    final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);
    List<String> uniqueVals = pharmacy.productMaster.map((p) => _getColValue(p, idx, pharmacy)).toSet().toList();
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
                initialFilter: _activeFilters[idx],
              ),
            ),
          )
        ],
      ),
    );

    if (result != null) {
      if (result['condition'] == 'Clear') {
        _activeFilters.remove(idx);
      }
      _recalculateFilters(); // CODE MASTER FIX
    }
  }

  void _printStockList() async {
    if (_filteredProducts.isEmpty) return;
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);
    
    final headers = [
      "Name", "HSN", "Pack", "Category", "SubCat", "Patent", "GST%",
      "Stock", "P.Rate", "S.Rate", "MRP", "Generic", "Rack",
      "S.Disc%", "Sch", "Reorder", "Max"
    ];
    final data = _filteredProducts.map((p) => [
      p.name,
      p.hsnCode,
      p.packSize.toString(),
      p.category,
      p.subCategory,
      p.patent,
      "${p.gstPercent.toStringAsFixed(0)}%",
      p.stock.toString(),
      p.purchaseRate.toStringAsFixed(2),
      p.salePrice.toStringAsFixed(2),
      p.mrp.toStringAsFixed(2),
      _getColValue(p, 11, pharma),
      p.rack,
      "${p.sDiscPercent.toStringAsFixed(1)}%",
      p.schedule,
      p.reorderLevel.toString(),
      p.maxLevel.toString(),
    ]).toList();

    final doc = await ReportPdfGenerator.buildReportPdf(
      title: "Stock Inventory Report",
      headers: headers,
      data: data,
      company: pharma.companyProfile,
      subtitle: "Filter: $_selectedCategory | Count: ${_filteredProducts.length}",
    );

    if (!mounted) return;
    PrinterService.showProfessionalPreview(
      context: context,
      doc: doc,
      title: "Stock Inventory Preview",
    );
  }

  bool _isExpired(String expiry) {
    if (expiry.isEmpty || expiry == "--/--") return false;
    try {
      final parts = expiry.split('/');
      if (parts.length == 2) {
        int month = int.parse(parts[0]);
        int year = int.parse(parts[1]);
        if (year < 100) year += 2000;
        final expDate = DateTime(year, month + 1, 0);
        return expDate.isBefore(DateTime.now());
      }
    } catch (_) {}
    return false;
  }

  bool _matchesFilter(Product p) {
    // 1. Sidebar Category/Status Filter
    if (_selectedCategory == "Low Stock Items") {
      if (p.stock >= 10) return false;
    } else if (_selectedCategory == "Expired Products") {
      if (!_isExpired(p.expiry)) return false;
    } else if (_selectedCategory == "Negative Stock") {
      if (p.stock >= 0) return false;
    } else if (_selectedCategory == "Inventory") {
      if (p.stock <= 0) return false;
    } else if (_selectedCategory != "All Inventory") {
      // It's a specific category
      if (p.category != _selectedCategory) return false;
    }

    // 2. Column-specific Advanced/Quick Filters
    if (_activeFilters.isEmpty) return true;

    final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);

    for (var entry in _activeFilters.entries) {
      int colIdx = entry.key;
      final filter = entry.value;
      String condition = filter['condition'];

      String itemVal = _getColValue(p, colIdx, pharmacy);

      if (condition == 'Values') {
        List<String> selected = List<String>.from(filter['selected']);
        if (!selected.contains(itemVal)) return false;
        continue;
      }

      String filterVal = filter['value'].toString().toLowerCase();
      itemVal = itemVal.toLowerCase();

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
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final provider = Provider.of<PharmacyProvider>(context);
    final allProducts = provider.productMaster;

    return Row(
      children: [
        _buildInventorySidebar(c, provider),
        Expanded(
          child: Container(
            color: c.background,
            child: Column(
              children: [
                _buildInventoryHeader(_filteredProducts.length),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    decoration: AppStyles.cardDecorationOf(context),
                    clipBehavior: Clip.antiAlias,
                    child: _buildStockGrid(_filteredProducts, allProducts),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInventorySidebar(AppThemeColors c, PharmacyProvider provider) {
    final all = provider.productMaster;
    int physicalCount = all.where((p) => p.stock > 0).length;
    int lowStockCount = all.where((p) => p.stock < 10).length;
    int expiredCount = all.where((p) => _isExpired(p.expiry)).length;
    int negativeStockCount = all.where((p) => p.stock < 0).length;

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: c.sidebarBg,
        border: Border(right: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.inventory_2_rounded, color: AppColors.accent, size: 24),
                ),
                const SizedBox(width: 16),
                const Text(
                  "INVENTORY",
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("FILTER BY STATUS", style: AppStyles.label),
                  const SizedBox(height: 16),
                  _buildFilterTab("All Inventory", Icons.grid_view_rounded),
                  _buildFilterTab("Inventory", Icons.inventory_rounded, count: physicalCount.toString()),
                  _buildFilterTab("Low Stock Items", Icons.warning_amber_rounded, count: lowStockCount.toString()),
                  _buildFilterTab("Expired Products", Icons.event_busy_rounded, count: expiredCount.toString()),
                  _buildFilterTab("Negative Stock", Icons.error_outline, count: negativeStockCount.toString()),
                  const SizedBox(height: 40),
                  Text("CATEGORIES", style: AppStyles.label),
                  const SizedBox(height: 16),
                  ...provider.categories
                      .where((c) => c != "General")
                      .map((cat) => _buildFilterTab(cat, Icons.medication_rounded)),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: _actionBtn("PRINT STOCK LIST", Icons.print_rounded, AppColors.primary, onTap: _printStockList),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTab(String label, IconData icon, {String? count}) {
    bool isSelected = _selectedCategory == label;
    return InkWell(
      onTap: () {
        setState(() => _selectedCategory = label);
        _recalculateFilters();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: isSelected ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(12), boxShadow: isSelected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))] : null),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? AppColors.accent : Colors.blueGrey.shade300),
            const SizedBox(width: 16),
            Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600, color: isSelected ? AppColors.primary : Colors.blueGrey.shade600))),
            if (count != null) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Text(count, style: const TextStyle(color: AppColors.danger, fontSize: 10, fontWeight: FontWeight.w900))),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryHeader(int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: Colors.blueGrey),
          const SizedBox(width: 12),
          const Text("Use the column headers below to filter and search inventory items.", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.blueGrey)),
          const Spacer(),
          _summaryStat("ACTIVE ITEMS", total.toString(), Colors.blue),
          const SizedBox(width: 32),
          _summaryStat("LOW STOCK", "12", AppColors.danger),
        ],
      ),
    );
  }

  Widget _summaryStat(String label, String value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(label, style: AppStyles.label.copyWith(fontSize: 9)), const SizedBox(height: 2), Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color))]);

  Widget _buildStockGrid(List<Product> products, List<Product> allProducts) {
    double totalWidth = 45 + 80 + _colWidths.values.fold<double>(0.0, (sum, w) => sum + w);
    final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);

    return Scrollbar(
      thumbVisibility: true,
      trackVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: totalWidth,
          child: Column(
            children: [
              Container(
                height: _headerHeight,
                color: const Color(0xFFF5F5F5),
                child: Row(
                  children: [
                    const SizedBox(width: 45, child: Center(child: Text("SL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)))),
                    _hdr("MEDICINE DESCRIPTION", 0, width: _colWidths[0]),
                    _hdr("HSN CODE", 1, width: _colWidths[1]),
                    _hdr("PACK", 2, width: _colWidths[2], columnType: 'numeric'),
                    _hdr("CATEGORY", 3, width: _colWidths[3]),
                    _hdr("SUB CAT", 4, width: _colWidths[4]),
                    _hdr("PATENT", 5, width: _colWidths[5]),
                    _hdr("GST %", 6, width: _colWidths[6], columnType: 'numeric'),
                    _hdr("STOCK QTY", 7, width: _colWidths[7], columnType: 'numeric'),
                    _hdr("PURCHASE RATE", 8, width: _colWidths[8], columnType: 'numeric'),
                    _hdr("SALES PRICE", 9, width: _colWidths[9], columnType: 'numeric'),
                    _hdr("MRP", 10, width: _colWidths[10], columnType: 'numeric'),
                    _hdr("GENERIC NAME", 11, width: _colWidths[11]),
                    _hdr("RACK", 12, width: _colWidths[12]),
                    _hdr("S.DISC %", 13, width: _colWidths[13], columnType: 'numeric'),
                    _hdr("SCHEDULE", 14, width: _colWidths[14]),
                    _hdr("REORDER LEVEL", 15, width: _colWidths[15], columnType: 'numeric'),
                    _hdr("MAX LEVEL", 16, width: _colWidths[16], columnType: 'numeric'),
                    const SizedBox(width: 80, child: Center(child: Text("ACTIONS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)))),
                  ],
                ),
              ),
              Expanded(
                child: Scrollbar(
                  thumbVisibility: true,
                  child: ListView.builder(
                    itemExtent: 40.0,
                    itemCount: products.length,
                    itemBuilder: (context, i) {
                      final p = products[i];
                      final bool lowStock = p.stock < 10;
                      final bool isSelected = _selectedRowIndex == i;
                      return InkWell(
                        onTap: () => setState(() => _selectedRowIndex = i),
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? AppColors.accent.withValues(alpha: 0.1) 
                                : (i % 2 == 0 ? Colors.white : Colors.grey.shade50),
                            border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                          ),
                          child: Row(
                            children: [
                              _Cell("${i + 1}", width: 45, align: TextAlign.center, color: Colors.grey),
                              _Cell(p.name, width: _colWidths[0]!, fontWeight: FontWeight.w800, color: AppColors.primary),
                              _Cell(p.hsnCode, width: _colWidths[1]!),
                              _Cell(p.packSize.toString(), width: _colWidths[2]!, align: TextAlign.center),
                              _Cell(p.category, width: _colWidths[3]!),
                              _Cell(p.subCategory, width: _colWidths[4]!),
                              _Cell(p.patent, width: _colWidths[5]!),
                              _Cell("${p.gstPercent.toStringAsFixed(0)}%", width: _colWidths[6]!, align: TextAlign.right),
                              _Cell("${p.stock} units", width: _colWidths[7]!, align: TextAlign.right, color: lowStock ? AppColors.danger : AppColors.success, fontWeight: FontWeight.w900),
                              _Cell(p.purchaseRate.toStringAsFixed(2), width: _colWidths[8]!, align: TextAlign.right),
                              _Cell(p.salePrice.toStringAsFixed(2), width: _colWidths[9]!, align: TextAlign.right, fontWeight: FontWeight.bold),
                              _Cell(p.mrp.toStringAsFixed(2), width: _colWidths[10]!, align: TextAlign.right, color: AppColors.secondary, fontWeight: FontWeight.w900),
                              _Cell(_getColValue(p, 11, pharmacy), width: _colWidths[11]!),
                              _Cell(p.rack, width: _colWidths[12]!, align: TextAlign.center, fontWeight: FontWeight.bold, color: AppColors.accent),
                              _Cell("${p.sDiscPercent.toStringAsFixed(1)}%", width: _colWidths[13]!, align: TextAlign.right),
                              _Cell(p.schedule, width: _colWidths[14]!, align: TextAlign.center),
                              _Cell(p.reorderLevel.toString(), width: _colWidths[15]!, align: TextAlign.right),
                              _Cell(p.maxLevel.toString(), width: _colWidths[16]!, align: TextAlign.right),
                              _buildActionIcons(p, width: 80),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hdr(String title, int idx, {double? width, int? flex, String columnType = 'text'}) {
    return _Hdr(
      title: title,
      width: width ?? _colWidths[idx]!,
      flex: flex?.toDouble(),
      columnType: columnType,
      onQuickFilter: (c, v) => _applyQuickFilter(idx, c, v),
      onAdvancedTap: (pos) => _openAdvancedFilter(idx, title, pos),
      onResize: (v) => setState(() => _colWidths[idx] = v.clamp(40, 500)),
      onHeightResize: (v) => setState(() => _headerHeight = v.clamp(40, 150)),
    );
  }

  Widget _buildActionIcons(Product p, {required double width}) => SizedBox(
    width: width,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(Icons.edit_outlined, size: 16, color: Colors.blue.shade600),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () {
            Provider.of<AppProvider>(context, listen: false).openProductRegistration();
          },
        ),
        const SizedBox(width: 12),
        IconButton(
          icon: Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red.shade600),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => _confirmDeleteProduct(p),
        ),
      ],
    ),
  );

  void _confirmDeleteProduct(Product p) async {
    final curContext = context;
    final provider = Provider.of<PharmacyProvider>(curContext, listen: false);
    final confirmed = await AppDialogs.showConfirmDialog(
      context: curContext,
      title: "Delete Product",
      content: "Permanently delete '${p.name}' from master data?",
      isDangerous: true,
    );
    if (confirmed == true) {
      await provider.deleteProduct(p.id);
      _recalculateFilters(provider);
    }
  }
}

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
    final bool isNumeric = widget.columnType == 'numeric';

    Widget content = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true), onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        width: widget.width, decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade300, width: 1), bottom: BorderSide(color: Colors.grey.shade400, width: 1))),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: Text(
                          widget.title,
                          textAlign: isNumeric ? TextAlign.right : TextAlign.left,
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
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(2)),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTapDown: _showQuickConditionMenu,
                        child: Container(padding: const EdgeInsets.symmetric(horizontal: 4), color: Colors.grey.shade100, alignment: Alignment.center, child: Text(_getConditionSymbol(), style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold))),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _quickCtrl,
                          style: const TextStyle(fontSize: 10),
                          textAlign: isNumeric ? TextAlign.right : TextAlign.left,
                          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6), border: InputBorder.none),
                          onChanged: (val) { widget.onQuickFilter(_quickCondition, val); setState(() {}); },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(right: 0, top: 0, bottom: 0, child: MouseRegion(cursor: SystemMouseCursors.resizeLeftRight, child: GestureDetector(behavior: HitTestBehavior.opaque, onHorizontalDragUpdate: (details) => widget.onResize(widget.width + details.delta.dx), child: Container(width: 6, decoration: BoxDecoration(border: Border(right: BorderSide(color: _isHovered ? Colors.blue.withValues(alpha: 0.5) : Colors.transparent, width: 2))))))),
            Positioned(left: 0, right: 0, bottom: 0, child: MouseRegion(cursor: SystemMouseCursors.resizeUpDown, child: GestureDetector(behavior: HitTestBehavior.opaque, onVerticalDragUpdate: (details) { final rb = context.findRenderObject() as RenderBox; widget.onHeightResize(rb.size.height + details.delta.dy); }, child: Container(height: 6, decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _isHovered ? Colors.blue.withValues(alpha: 0.5) : Colors.transparent, width: 2))))))),
          ],
        ),
      ),
    );
    if (widget.flex != null) return Expanded(flex: (widget.flex! * 10).toInt(), child: content);
    return content;
  }
}

class _Cell extends StatelessWidget {
  final String text; final double? width; final int? flex; final TextAlign align; final Color? color; final FontWeight fontWeight;
  const _Cell(this.text, {this.width, this.align = TextAlign.left, this.color, this.fontWeight = FontWeight.w600}) : flex = null;
  @override Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cellAlignment = align == TextAlign.left
        ? Alignment.centerLeft
        : (align == TextAlign.center ? Alignment.center : Alignment.centerRight);
    final hPadding = (width != null && width! <= 50) ? 4.0 : 10.0;

    Widget child = ERPTooltip(
      message: text,
      child: Container(
        width: width,
        alignment: cellAlignment,
        padding: EdgeInsets.symmetric(horizontal: hPadding),
        child: Text(
          text,
          textAlign: align,
          style: TextStyle(fontSize: 13, color: color ?? c.primaryText, fontWeight: fontWeight),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
    return flex != null ? Expanded(flex: flex!, child: child) : child;
  }
}

class _AdvancedFilterPopup extends StatefulWidget {
  final String columnName; final List<String> uniqueValues; final Map<String, dynamic>? initialFilter;
  const _AdvancedFilterPopup({required this.columnName, required this.uniqueValues, this.initialFilter});
  @override State<_AdvancedFilterPopup> createState() => _AdvancedFilterPopupState();
}

class _AdvancedFilterPopupState extends State<_AdvancedFilterPopup> {
  final TextEditingController _searchCtrl = TextEditingController(); List<String> _filteredValues = []; Set<String> _selectedValues = {};
  @override void initState() { super.initState(); _filteredValues = List.from(widget.uniqueValues); if (widget.initialFilter != null && widget.initialFilter!['selected'] != null) { _selectedValues = Set<String>.from(widget.initialFilter!['selected']); } }
  @override Widget build(BuildContext context) { return Container(width: 250, height: 350, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4)), child: Column(children: [Container(padding: const EdgeInsets.all(8), color: Colors.blueGrey.shade50, child: Row(children: [Text(widget.columnName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))])), Padding(padding: const EdgeInsets.all(8.0), child: TextField(controller: _searchCtrl, decoration: const InputDecoration(hintText: "Search values...", prefixIcon: Icon(Icons.search, size: 16), isDense: true, border: OutlineInputBorder()), onChanged: (v) => setState(() => _filteredValues = widget.uniqueValues.where((e) => e.toLowerCase().contains(v.toLowerCase())).toList()))), Expanded(child: ListView.builder(itemCount: _filteredValues.length, itemBuilder: (ctx, i) => CheckboxListTile(title: Text(_filteredValues[i], style: const TextStyle(fontSize: 11)), value: _selectedValues.contains(_filteredValues[i]), onChanged: (v) => setState(() => v! ? _selectedValues.add(_filteredValues[i]) : _selectedValues.remove(_filteredValues[i])), dense: true, visualDensity: VisualDensity.compact))), const Divider(height: 1), Padding(padding: const EdgeInsets.all(8.0), child: Row(children: [TextButton(onPressed: () => Navigator.pop(context, {'condition': 'Clear'}), child: const Text("Clear")), const Spacer(), ElevatedButton(onPressed: () => Navigator.pop(context, {'condition': 'Values', 'selected': _selectedValues.toList()}), child: const Text("Apply"))]))])); }
}

Widget _actionBtn(String label, IconData icon, Color color, {VoidCallback? onTap}) { return SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)), style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0))); }