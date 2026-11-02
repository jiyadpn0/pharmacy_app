import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../providers/pharmacy_provider.dart';
import '../providers/app_provider.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/erp_tooltip.dart';
import '../utils/report_pdf_generator.dart';
import '../utils/printer_service.dart';
import '../utils/app_formatters.dart';

enum ColType { text, numeric }
enum AggregationType { sum, min, max, count, average, none }

class _ColDef {
  final String key;
  final String label;
  double width;
  final TextAlign align;
  final ColType type;

  _ColDef(this.key, this.label, {this.width = 90.0, this.align = TextAlign.left, this.type = ColType.text});
}

class ConsolidateStockScreen extends StatefulWidget {
  const ConsolidateStockScreen({super.key});

  @override
  State<ConsolidateStockScreen> createState() => _ConsolidateStockScreenState();
}

class _ConsolidateStockScreenState extends State<ConsolidateStockScreen> {
  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();

  final String _selectedSupplier = 'ALL';
  final String _selectedCategory = 'ALL';
  bool _isLoading = false;

  List<StockLedgerItem> _masterList = [];
  List<StockLedgerItem> _filteredList = [];

  final Map<String, TextEditingController> _filterCtrls = {};
  final Map<String, String> _filterConditions = {};
  final Map<String, Map<String, dynamic>> _advancedFilters = {};
  final Map<String, AggregationType> _columnAggregations = {};

  String? _sortKey;
  bool _isAscending = true;

  final ScrollController _horizontalScrollCtrl = ScrollController();
  final ScrollController _verticalScrollCtrl = ScrollController();

  bool _isDetailedView = false;

  final Map<String, double> _colWidths = {};

  List<_ColDef> get _columns {
    List<_ColDef> cols;
    if (_isDetailedView) {
      cols = [
        _ColDef('sl', 'SL', width: 40.0, align: TextAlign.center, type: ColType.numeric),
        _ColDef('product', 'Product', width: 190.0, align: TextAlign.left, type: ColType.text),
        _ColDef('patent', 'Patent', width: 95.0, align: TextAlign.left, type: ColType.text),
        _ColDef('packing', 'Packing', width: 55.0, align: TextAlign.center, type: ColType.numeric),
        _ColDef('batch', 'Batch', width: 85.0, align: TextAlign.left, type: ColType.text),
        _ColDef('hsn', 'Hsncode', width: 80.0, align: TextAlign.left, type: ColType.text),
        _ColDef('gst', 'gst', width: 50.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('mrp', 'Mrp', width: 65.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('supplier', 'Supplier', width: 120.0, align: TextAlign.left, type: ColType.text),
        _ColDef('opening', 'Opening Stock', width: 90.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('op_val', 'Op.Stock Val', width: 90.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('purchase', 'Purchase', width: 70.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('damage', 'Damage', width: 60.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('sreturn', 'S.Return', width: 60.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('sales', 'Sales', width: 65.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('b2bsales', 'B2BSales', width: 70.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('preturn', 'P.Return', width: 60.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('adjustment', 'Adjustment', width: 75.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('closing', 'Closing Stock', width: 90.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('mrp_val', 'MRP Value', width: 90.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('lcost_val', 'Lcost Value', width: 90.0, align: TextAlign.right, type: ColType.numeric),
      ];
    } else {
      cols = [
        _ColDef('sl', 'SL', width: 40.0, align: TextAlign.center, type: ColType.numeric),
        _ColDef('product', 'Product', width: 210.0, align: TextAlign.left, type: ColType.text),
        _ColDef('packing', 'Packing', width: 65.0, align: TextAlign.center, type: ColType.numeric),
        _ColDef('batch', 'Batch', width: 95.0, align: TextAlign.left, type: ColType.text),
        _ColDef('supplier', 'Supplier', width: 140.0, align: TextAlign.left, type: ColType.text),
        _ColDef('inward', 'Inward (+)', width: 85.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('outward', 'Outward (-)', width: 85.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('closing', 'Closing Stock', width: 100.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('mrp_val', 'MRP Value', width: 100.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('lcost_val', 'Lcost Value', width: 100.0, align: TextAlign.right, type: ColType.numeric),
      ];
    }

    for (var c in cols) {
      if (_colWidths.containsKey(c.key)) {
        c.width = _colWidths[c.key]!;
      }
    }
    return cols;
  }

  late final TextEditingController _searchCtrl;
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    for (var col in _columns) {
      final ctrl = TextEditingController();
      ctrl.addListener(_applyHeaderFilters);
      _filterCtrls[col.key] = ctrl;
      _filterConditions[col.key] = col.type == ColType.numeric ? 'Equals' : 'Contains';
    }
    _searchCtrl = _filterCtrls['product']!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchStockData();
    });
  }

  @override
  void dispose() {
    for (var ctrl in _filterCtrls.values) {
      ctrl.dispose();
    }
    _searchFocusNode.dispose();
    _horizontalScrollCtrl.dispose();
    _verticalScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchStockData() async {
    setState(() => _isLoading = true);
    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    try {
      final items = await provider.getStockLedgerReport(
        _fromDate,
        _toDate,
        supplierFilter: _selectedSupplier,
        categoryFilter: _selectedCategory,
      );

      if (mounted) {
        setState(() {
          _masterList = items;
          _isLoading = false;
        });
        _applyHeaderFilters();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading stock report: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _onColumnHeaderTap(String key) {
    setState(() {
      if (_sortKey == key) {
        if (_isAscending) {
          _isAscending = false;
        } else {
          _sortKey = null; // Clear sort on 3rd tap
          _isAscending = true;
        }
      } else {
        _sortKey = key;
        _isAscending = true;
      }
      _applyHeaderFilters();
    });
  }

  void _openAdvancedFilterPopup(_ColDef col, Offset position) async {
    List<String> uniqueVals = _masterList.map((item) => _getCellValueByKey(item, col.key).toString()).toSet().toList();
    uniqueVals.sort();

    double minVal = 0.0;
    double maxVal = 100.0;
    if (col.type == ColType.numeric && _masterList.isNotEmpty) {
      final nums = _masterList.map((item) => double.tryParse(_getCellValueByKey(item, col.key).toString()) ?? 0.0).toList();
      nums.sort();
      minVal = nums.first;
      maxVal = nums.last;
      if (minVal == maxVal) maxVal = minVal + 10.0;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => Stack(
        children: [
          Positioned(
            top: position.dy + 10,
            left: (position.dx - 100).clamp(10.0, MediaQuery.of(context).size.width - 280),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(4),
              child: ERPAdvancedFilterPopup(
                columnName: col.label,
                isNumeric: col.type == ColType.numeric,
                uniqueValues: uniqueVals,
                minVal: minVal,
                maxVal: maxVal,
                initialFilter: _advancedFilters[col.key],
              ),
            ),
          )
        ],
      ),
    );

    if (result != null) {
      if (result['condition'] == 'Clear') {
        _advancedFilters.remove(col.key);
      } else {
        _advancedFilters[col.key] = result;
      }
      _applyHeaderFilters();
    }
  }

  void _applyHeaderFilters() {
    List<StockLedgerItem> list = List.from(_masterList);

    // 1. Advanced Filters Popup (Values checklist / Numeric Range / Rules)
    _advancedFilters.forEach((key, filter) {
      if (filter['mode'] == 'values') {
        List<String> allowed = List<String>.from(filter['selected_values'] ?? []);
        list = list.where((item) {
          String val = _getCellValueByKey(item, key).toString();
          return allowed.contains(val);
        }).toList();
      } else if (filter['mode'] == 'range') {
        double from = filter['from'] ?? double.negativeInfinity;
        double to = filter['to'] ?? double.infinity;
        list = list.where((item) {
          double numVal = double.tryParse(_getCellValueByKey(item, key).toString()) ?? 0.0;
          return numVal >= from && numVal <= to;
        }).toList();
      } else if (filter['mode'] == 'rules') {
        String cond = filter['condition'] ?? 'Equals';
        String val1 = (filter['value1'] ?? '').toString().toLowerCase();
        list = list.where((item) {
          String cellVal = _getCellValueByKey(item, key).toString().toLowerCase();
          if (cond == 'Contains') return cellVal.contains(val1);
          if (cond == 'Equals') return cellVal == val1;
          if (cond == 'Does Not Equal') return cellVal != val1;
          if (cond == 'Begins With') return cellVal.startsWith(val1);
          if (cond == 'Ends With') return cellVal.endsWith(val1);
          if (cond == 'Greater Than') {
            double cNum = double.tryParse(cellVal) ?? 0.0;
            double tNum = double.tryParse(val1) ?? 0.0;
            return cNum > tNum;
          }
          if (cond == 'Less Than') {
            double cNum = double.tryParse(cellVal) ?? 0.0;
            double tNum = double.tryParse(val1) ?? 0.0;
            return cNum < tNum;
          }
          return true;
        }).toList();
      }
    });

    // 2. Header Text Field Filters
    _filterCtrls.forEach((key, ctrl) {
      final query = ctrl.text.trim().toLowerCase();
      if (query.isEmpty) return;

      final cond = _filterConditions[key] ?? 'Contains';

      list = list.where((item) {
        String cellVal = _getCellValueByKey(item, key).toString().toLowerCase();

        if (cond == 'Equals') {
          return cellVal == query;
        } else if (cond == 'Greater Than') {
          final numTarget = double.tryParse(query) ?? 0.0;
          final cellNum = double.tryParse(cellVal) ?? 0.0;
          return cellNum > numTarget;
        } else if (cond == 'Less Than') {
          final numTarget = double.tryParse(query) ?? 0.0;
          final cellNum = double.tryParse(cellVal) ?? 0.0;
          return cellNum < numTarget;
        } else if (cond == 'Does Not Equal') {
          return cellVal != query;
        } else {
          return cellVal.contains(query);
        }
      }).toList();
    });

    // 3. Column Sorting (A to Z / Z to A, 0 to 9 / 9 to 0)
    if (_sortKey != null) {
      final key = _sortKey!;
      final colDef = _columns.firstWhere((c) => c.key == key, orElse: () => _columns.first);
      final isNum = colDef.type == ColType.numeric;

      list.sort((a, b) {
        dynamic valA = _getCellValueByKey(a, key);
        dynamic valB = _getCellValueByKey(b, key);

        int comp = 0;
        if (isNum) {
          double numA = (valA is num) ? valA.toDouble() : (double.tryParse(valA.toString()) ?? 0.0);
          double numB = (valB is num) ? valB.toDouble() : (double.tryParse(valB.toString()) ?? 0.0);
          comp = numA.compareTo(numB);
        } else {
          String strA = valA?.toString().toLowerCase() ?? '';
          String strB = valB?.toString().toLowerCase() ?? '';
          comp = strA.compareTo(strB);
        }

        return _isAscending ? comp : -comp;
      });
    }

    setState(() {
      _filteredList = list;
    });
  }

  dynamic _getCellValueByKey(StockLedgerItem item, String key) {
    switch (key) {
      case 'product': return item.productName;
      case 'patent': return item.patent;
      case 'packing': return item.packin;
      case 'batch': return cleanBatch(item.batch);
      case 'hsn': return item.hsnCode;
      case 'gst': return item.gst;
      case 'mrp': return item.mrp;
      case 'supplier': return item.supplier;
      case 'opening': return item.openingStock;
      case 'op_val': return (item.openingStock * (item.mrp / (item.packin == 0 ? 1 : item.packin)));
      case 'purchase': return item.purchase;
      case 'damage': return item.damage;
      case 'sreturn': return item.saleReturn;
      case 'sales': return item.sales;
      case 'b2bsales': return item.b2bSales;
      case 'preturn': return item.purchaseReturn;
      case 'adjustment': return item.adjustment;
      case 'inward': 
        // Inward includes Purchases, Sales Returns, and Positive Physical Stock Adjustments
        int posAdj = item.adjustment > 0 ? item.adjustment : 0;
        return (item.purchase + item.saleReturn + posAdj);

      case 'outward': 
        // Outward includes Sales, Purchase Returns, Damaged Stock, and Negative Adjustments
        int negAdj = item.adjustment < 0 ? item.adjustment.abs() : 0;
        return (item.sales + item.purchaseReturn + item.damage.abs() + negAdj);
      case 'closing': return item.closingStock;
      case 'mrp_val': return item.mrpValue;
      case 'lcost_val': return item.lCostValue;
      default: return '';
    }
  }

  void _exportExcel() async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final bool? confirmExport = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.file_download_rounded, color: Colors.blue, size: 28),
            SizedBox(width: 10),
            Text("Export Consolidated Stock", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text(
          "Export consolidated stock register for ${_filteredList.length} items to Excel?",
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade800,
              foregroundColor: Colors.white,
            ),
            child: const Text("Export Excel", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmExport != true) return;
    if (!mounted) return;

    String defaultFileName = 'Consolidated_Stock_Ledger_${DateFormat('ddMMyyyy').format(_fromDate)}_${DateFormat('ddMMyyyy').format(_toDate)}.xlsx';

    String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Save Consolidated Stock Excel',
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (outputFile != null) {
      final bytes = await provider.exportStockLedgerReportToExcelBytes(_filteredList, _fromDate, _toDate);

      if (bytes != null) {
        await File(outputFile).writeAsBytes(bytes);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Stock register exported successfully to Excel!"), backgroundColor: Colors.green),
        );
      }
    }
  }

  void _printPdf() async {
    if (_filteredList.isEmpty) return;
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);

    final headers = ["Product", "Batch", "MRP", "Supplier", "Opening", "PUR", "SAL", "S.RET", "P.RET", "Closing", "MRP Val"];
    final data = _filteredList.map((r) => [
      r.productName,
      cleanBatch(r.batch),
      r.mrp.toStringAsFixed(2),
      r.supplier,
      r.openingStock.toString(),
      r.purchase.toString(),
      r.sales.toString(),
      r.saleReturn.toString(),
      r.purchaseReturn.toString(),
      r.closingStock.toString(),
      r.mrpValue.toStringAsFixed(2),
    ]).toList();

    final doc = await ReportPdfGenerator.buildReportPdf(
      title: "Consolidated Stock Position Register",
      headers: headers,
      data: data,
      company: pharma.companyProfile,
      subtitle: "Period: ${DateFormat('dd/MM/yyyy').format(_fromDate)} to ${DateFormat('dd/MM/yyyy').format(_toDate)} | Supplier: $_selectedSupplier",
    );

    if (!mounted) return;
    PrinterService.showProfessionalPreview(context: context, doc: doc, title: "Stock Register Preview");
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);

    // Sync shared state from AppProvider
    if (_fromDate != appProvider.reportFromDate || _toDate != appProvider.reportToDate) {
      _fromDate = appProvider.reportFromDate;
      _toDate = appProvider.reportToDate;
      _fetchStockData();
    }
    _isDetailedView = appProvider.reportDetailedView;
    if (_searchCtrl.text != appProvider.reportSearchQuery) {
      _searchCtrl.text = appProvider.reportSearchQuery;
      _applyHeaderFilters();
    }

    final double totalTableWidth = _columns.fold(0.0, (sum, col) => sum + col.width);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          _buildTopToolbar(appProvider),
          _buildKpiSummaryCards(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                    child: SingleChildScrollView(
                      controller: _horizontalScrollCtrl,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: totalTableWidth,
                        child: Column(
                          children: [
                            // Header Row (Locked with Data & Total Rows)
                            Row(
                              children: _columns.map((col) => _buildHeaderCell(col)).toList(),
                            ),
                            
                            // Main Table Data Rows (Vertical Scrolling Only)
                            Expanded(
                              child: SingleChildScrollView(
                                controller: _verticalScrollCtrl,
                                scrollDirection: Axis.vertical,
                                child: SizedBox(
                                  width: totalTableWidth,
                                  child: _filteredList.isEmpty
                                      ? const SizedBox(
                                          height: 200,
                                          child: Center(child: Text("No matching inventory records found.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
                                        )
                                      : ListView.builder(
                                          shrinkWrap: true,
                                          physics: const NeverScrollableScrollPhysics(),
                                          itemExtent: 25.0,
                                          itemCount: _filteredList.length,
                                          itemBuilder: (ctx, i) {
                                            return _buildTableRow(_filteredList[i], i, totalTableWidth);
                                          },
                                        ),
                                ),
                              ),
                            ),

                            // Fixed Bottom Total Summary Row (Locked with Header & Data Rows)
                            _buildTableTotalRow(totalTableWidth),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopToolbar(AppProvider appProvider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
            child: Icon(Icons.grid_on_rounded, color: Colors.blue.shade800, size: 18),
          ),
          const SizedBox(width: 8),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("CONSOLIDATED STOCK REGISTER", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
              Text("Complete Multi-Product Movement & Stock Asset Valuation", style: TextStyle(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(width: 8),

          // Refresh Button
          Tooltip(
            message: "Refresh Data",
            child: InkWell(
              onTap: _fetchStockData,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Icon(Icons.refresh_rounded, color: Colors.blue.shade800, size: 16),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Scrollable Overflow-Safe Action Bar
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Left Control Group: Search Box + Date Presets + Date Pickers
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Item Search Box with Autocomplete Dropdown
                            SizedBox(
                              width: 200,
                              height: 30,
                              child: RawAutocomplete<String>(
                                textEditingController: _searchCtrl,
                                focusNode: _searchFocusNode,
                                optionsBuilder: (TextEditingValue textEditingValue) {
                                  final query = textEditingValue.text.toLowerCase().trim();
                                  if (query.isEmpty) return const Iterable<String>.empty();
                                  final provider = Provider.of<PharmacyProvider>(context, listen: false);

                                  final startsWith = provider.productMaster
                                      .where((p) => p.name.toLowerCase().startsWith(query))
                                      .map((p) => p.name)
                                      .toSet()
                                      .toList();
                                  final contains = provider.productMaster
                                      .where((p) => !p.name.toLowerCase().startsWith(query) && p.name.toLowerCase().contains(query))
                                      .map((p) => p.name)
                                      .toSet()
                                      .toList();

                                  return [...startsWith, ...contains].take(25);
                                },
                                onSelected: (String selection) {
                                  _searchCtrl.text = selection;
                                  appProvider.setReportSearchQuery(selection);
                                  _applyHeaderFilters();
                                },
                                fieldViewBuilder: (context, textController, fieldFocusNode, onFieldSubmitted) {
                                  return TextField(
                                    controller: textController,
                                    focusNode: fieldFocusNode,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                    onChanged: (v) {
                                      appProvider.setReportSearchQuery(v);
                                      _applyHeaderFilters();
                                    },
                                    decoration: InputDecoration(
                                      hintText: "Search item name...",
                                      hintStyle: const TextStyle(fontSize: 10, color: Colors.grey),
                                      prefixIcon: const Icon(Icons.search_rounded, size: 15, color: Colors.blue),
                                      suffixIcon: textController.text.isNotEmpty
                                          ? InkWell(
                                              onTap: () {
                                                textController.clear();
                                                appProvider.setReportSearchQuery("");
                                                _applyHeaderFilters();
                                              },
                                              child: const Icon(Icons.clear, size: 14, color: Colors.grey),
                                            )
                                          : null,
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                                    ),
                                  );
                                },
                                optionsViewBuilder: (context, onSelected, options) {
                                  return Align(
                                    alignment: Alignment.topLeft,
                                    child: Material(
                                      elevation: 8,
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        width: 280,
                                        constraints: const BoxConstraints(maxHeight: 220),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.blue.shade800, width: 1.2),
                                        ),
                                        child: ListView.builder(
                                          padding: EdgeInsets.zero,
                                          shrinkWrap: true,
                                          itemCount: options.length,
                                          itemBuilder: (BuildContext context, int index) {
                                            final option = options.elementAt(index);
                                            final isHighlighted = AutocompleteHighlightedOption.of(context) == index;

                                            return InkWell(
                                              onTap: () => onSelected(option),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: isHighlighted ? Colors.blue.shade50 : Colors.white,
                                                  border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.5)),
                                                ),
                                                child: Text(
                                                  option,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: isHighlighted ? Colors.blue.shade900 : Colors.black87,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 6),

                            // Quick Date Presets
                            _presetPill("Today", () {
                              appProvider.setReportDateRange(DateTime.now(), DateTime.now());
                              _fetchStockData();
                            }),
                            const SizedBox(width: 3),
                            _presetPill("This Month", () {
                              final now = DateTime.now();
                              appProvider.setReportDateRange(DateTime(now.year, now.month, 1), now);
                              _fetchStockData();
                            }),
                            const SizedBox(width: 3),
                            _presetPill("FY", () {
                              final now = DateTime.now();
                              int startYear = now.month >= 4 ? now.year : now.year - 1;
                              appProvider.setReportDateRange(DateTime(startYear, 4, 1), now);
                              _fetchStockData();
                            }),
                            const SizedBox(width: 6),

                            // Date Pickers
                            _datePicker("From", _fromDate, (d) { appProvider.setReportDateRange(d, _toDate); _fetchStockData(); }),
                            const SizedBox(width: 4),
                            _datePicker("To", _toDate, (d) { appProvider.setReportDateRange(_fromDate, d); _fetchStockData(); }),
                          ],
                        ),

                        // Right Control Group (Most Right Side Area): Detailed View + Switcher + Export Menu
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Detailed View Checkbox
                            InkWell(
                              onTap: () {
                                appProvider.setReportDetailedView(!_isDetailedView);
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Checkbox(
                                    value: _isDetailedView,
                                    activeColor: Colors.blue.shade800,
                                    visualDensity: VisualDensity.compact,
                                    onChanged: (v) {
                                      appProvider.setReportDetailedView(v ?? false);
                                    },
                                  ),
                                  const Text(
                                    "Detailed View",
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),

                            // 1-Click Page Switcher Button to Stock Ledger
                            ElevatedButton.icon(
                              onPressed: () => Provider.of<AppProvider>(context, listen: false).openStockLedger(),
                              icon: const Icon(Icons.swap_horiz_rounded, size: 14),
                              label: const Text("STOCK LEDGER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigo.shade800,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              ),
                            ),
                            const SizedBox(width: 6),

                            // Unified EXPORT & PRINT Menu
                            PopupMenuButton<String>(
                              onSelected: (val) {
                                if (val == 'pdf' || val == 'print') {
                                  _printPdf();
                                } else if (val == 'excel') {
                                  _exportExcel();
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'pdf',
                                  child: Row(
                                    children: [
                                      Icon(Icons.picture_as_pdf_rounded, size: 16, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text("Export PDF (With Preview)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'excel',
                                  child: Row(
                                    children: [
                                      Icon(Icons.table_chart_rounded, size: 16, color: Colors.green),
                                      SizedBox(width: 8),
                                      Text("Export Excel Spreadsheet", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'print',
                                  child: Row(
                                    children: [
                                      Icon(Icons.print_rounded, size: 16, color: Colors.blue),
                                      SizedBox(width: 8),
                                      Text("Print Report (With Page Setup)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ],
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade900,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.ios_share_rounded, size: 14, color: Colors.white),
                                    SizedBox(width: 6),
                                    Text("EXPORT & PRINT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
                                    SizedBox(width: 4),
                                    Icon(Icons.arrow_drop_down, size: 16, color: Colors.white),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetPill(String label, VoidCallback onTap) {
    return InkWell(
      onTap: _isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: _isLoading ? Colors.grey.shade100 : Colors.blue.shade50,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _isLoading ? Colors.grey.shade300 : Colors.blue.shade200),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _isLoading ? Colors.grey : Colors.blue.shade900),
        ),
      ),
    );
  }

  Widget _datePicker(String label, DateTime date, Function(DateTime) onPick) {
    return InkWell(
      onTap: () async {
        final picked = await showAppDatePicker(context: context, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime(2100));
        if (picked != null) onPick(picked);
      },
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade300)),
        child: Row(
          children: [
            const Icon(Icons.calendar_month, size: 13, color: Colors.blueGrey),
            const SizedBox(width: 4),
            Text(DateFormat('dd/MM/yy').format(date), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiSummaryCards() {
    int totalOpen = 0;
    int totalPur = 0;
    int totalSales = 0;
    int totalSRet = 0;
    int totalPRet = 0;
    int totalDmg = 0;
    int totalClosing = 0;
    double totalMrpVal = 0.0;
    double totalLCostVal = 0.0;

    for (var r in _filteredList) {
      totalOpen += r.openingStock;
      totalPur += r.purchase;
      totalSales += r.sales;
      totalSRet += r.saleReturn;
      totalPRet += r.purchaseReturn;
      totalDmg += r.damage.abs();
      totalClosing += r.closingStock;
      totalMrpVal += r.mrpValue;
      totalLCostVal += r.lCostValue;
    }

    String dmgDisplayStr = totalDmg > 0 ? "-$totalDmg" : "0";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: const Color(0xFFF1F5F9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _miniKpiCard("OPENING", "$totalOpen", Colors.blueGrey.shade800),
          const SizedBox(width: 6),
          _miniKpiCard("PURCHASE (+)", "+$totalPur", Colors.green.shade800),
          const SizedBox(width: 6),
          _miniKpiCard("SALES (-)", "-$totalSales", Colors.blue.shade800),
          const SizedBox(width: 6),
          _miniKpiCard("S.RETURNS (+)", "+$totalSRet", Colors.indigo.shade800),
          const SizedBox(width: 6),
          _miniKpiCard("P.RETURNS (-)", "-$totalPRet", Colors.orange.shade800),
          const SizedBox(width: 6),
          _miniKpiCard("DAMAGES (-)", dmgDisplayStr, Colors.red.shade800),
          const SizedBox(width: 6),
          _miniKpiCard("CLOSING STOCK", "$totalClosing", Colors.teal.shade900, isBold: true),
          const SizedBox(width: 6),
          _miniKpiCard("MRP VALUATION", "₹${totalMrpVal.toStringAsFixed(0)}", Colors.indigo.shade900, isBold: true),
          const SizedBox(width: 6),
          _miniKpiCard("COST VALUATION", "₹${totalLCostVal.toStringAsFixed(0)}", Colors.amber.shade900, isBold: true),
        ],
      ),
    );
  }

  Widget _miniKpiCard(String label, String value, Color color, {bool isBold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: isBold ? FontWeight.w900 : FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  // 100% COPY OF SALES REPORT HEADER CELL WITH HOVER FUNNEL FILTER ICON (Photo 3/4) & CLICK-TO-SORT (A-Z / Z-A, 0-9 / 9-0)
  Widget _buildHeaderCell(_ColDef col) {
    final ctrl = _filterCtrls.putIfAbsent(col.key, () {
      final c = TextEditingController();
      c.addListener(_applyHeaderFilters);
      return c;
    });
    final cond = _filterConditions.putIfAbsent(col.key, () => col.type == ColType.numeric ? 'Equals' : 'Contains');
    final isSorted = _sortKey == col.key;
    final hasAdvanced = _advancedFilters.containsKey(col.key);

    String conditionSymbol = '=';
    if (cond == 'Contains') {
      conditionSymbol = 'inc';
    } else if (cond == 'Greater Than') {
      conditionSymbol = '>';
    } else if (cond == 'Less Than') {
      conditionSymbol = '<';
    } else if (cond == 'Does Not Equal') {
      conditionSymbol = '!=';
    }

    return _HoverCellWrapper(
      builder: (context, isHovered) {
        return Stack(
          children: [
            Container(
              width: col.width,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                border: Border(
                  right: BorderSide(color: Colors.grey.shade300, width: 1),
                  bottom: BorderSide(color: Colors.grey.shade400, width: 1),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Row 1: Header Label with Click-to-Sort & Hover-Only Funnel Filter Icon
                  InkWell(
                    onTap: () => _onColumnHeaderTap(col.key),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4, top: 4, bottom: 2, right: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    col.label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isSorted ? Colors.blue.shade900 : Colors.grey.shade800,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                if (isSorted) ...[
                                  const SizedBox(width: 2),
                                  Icon(
                                    _isAscending ? Icons.arrow_upward : Icons.arrow_downward,
                                    size: 11,
                                    color: Colors.blue.shade900,
                                  ),
                                ],
                              ],
                            ),
                          ),

                          // Funnel Filter Icon: Opens Advanced Popup ONLY on Hover or Active Filter
                          if (isHovered || hasAdvanced || ctrl.text.isNotEmpty)
                            GestureDetector(
                              onTapDown: (details) => _openAdvancedFilterPopup(col, details.globalPosition),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: Icon(
                                  Icons.filter_alt_outlined,
                                  size: 13,
                                  color: (hasAdvanced || ctrl.text.isNotEmpty) ? Colors.blue.shade800 : Colors.blueGrey.shade600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Row 2: Quick Filter Input Field
                  Container(
                    height: 22,
                    margin: const EdgeInsets.fromLTRB(2, 0, 2, 3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTapDown: (details) async {
                            List<String> items = col.type == ColType.numeric
                                ? ['Equals', 'Greater Than', 'Less Than', 'Does Not Equal']
                                : ['Contains', 'Equals', 'Does Not Equal'];

                            final result = await showMenu<String>(
                              context: context,
                              position: RelativeRect.fromLTRB(
                                details.globalPosition.dx, details.globalPosition.dy + 10,
                                details.globalPosition.dx, 0,
                              ),
                              items: items.map((e) => PopupMenuItem(value: e, height: 28, child: Text(e, style: const TextStyle(fontSize: 10)))).toList(),
                            );

                            if (result != null) {
                              setState(() => _filterConditions[col.key] = result);
                              _applyHeaderFilters();
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Text(
                              conditionSymbol,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: ctrl,
                            style: const TextStyle(fontSize: 10.5, color: Colors.black87),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 2),
                              hintText: col.type == ColType.numeric ? '0' : '',
                              hintStyle: TextStyle(fontSize: 10.5, color: Colors.grey.shade400),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Right-side Draggable Column Width Resize Handle
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      final cur = _colWidths[col.key] ?? col.width;
                      _colWidths[col.key] = (cur + details.delta.dx).clamp(30.0, 800.0);
                    });
                  },
                  child: Container(
                    width: 10,
                    color: Colors.transparent,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTableRow(StockLedgerItem item, int index, double totalWidth) {
    final bool isEven = index % 2 == 0;
    final Color rowBg = isEven ? Colors.white : const Color(0xFFF9F9F9);

    return Container(
      width: totalWidth,
      height: 30,
      decoration: BoxDecoration(
        color: rowBg,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.5)),
      ),
      child: Row(
        children: _columns.map((col) {
          dynamic rawVal = col.key == 'sl' ? (index + 1) : _getCellValueByKey(item, col.key);

          String textStr = '';
          Color textColor = Colors.black87;
          FontWeight fontWeight = FontWeight.normal;

          if (col.key == 'name') {
            fontWeight = FontWeight.w600;
          }

          if (rawVal is double) {
            textStr = rawVal.toStringAsFixed(2);
            if (col.key == 'closing') {
              fontWeight = FontWeight.bold;
              if (item.closingStock < 0) {
                textColor = Colors.red.shade700;
              } else if (item.closingStock == 0) {
                textColor = Colors.orange.shade800;
              }
            }
          } else if (rawVal is int) {
            textStr = rawVal.toString();
            if ((col.key == 'purchase' || col.key == 'inward') && rawVal > 0) textColor = Colors.green.shade800;
            if ((col.key == 'sales' || col.key == 'outward') && rawVal > 0) textColor = Colors.red.shade800;
            if (col.key == 'damage' && rawVal > 0) textColor = Colors.red.shade800;
            if (col.key == 'closing') {
              fontWeight = FontWeight.bold;
              if (item.closingStock < 0) {
                textColor = Colors.red.shade700;
              } else if (item.closingStock == 0) {
                textColor = Colors.orange.shade800;
              }
            }
          } else {
            textStr = rawVal?.toString() ?? '';
          }

          return Container(
            width: col.width,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: col.align == TextAlign.left
                ? Alignment.centerLeft
                : (col.align == TextAlign.center ? Alignment.center : Alignment.centerRight),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.grey.shade200, width: 0.5)),
            ),
            child: Text(
              textStr,
              style: TextStyle(
                fontSize: 11.5,
                color: textColor,
                fontWeight: fontWeight,
                fontFamily: (col.key == 'batch' || col.key == 'hsn') ? 'monospace' : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
      ),
    );
  }

  String _calculateAggregation(String colKey, AggregationType type) {
    if (type == AggregationType.none || _filteredList.isEmpty) return "";
    if (type == AggregationType.count) return "${_filteredList.length}";

    List<double> values = [];
    for (var item in _filteredList) {
      double? val;
      if (colKey == 'opening') {
        val = item.openingStock.toDouble();
      } else if (colKey == 'purchase') {
        val = item.purchase.toDouble();
      } else if (colKey == 'damage') {
        val = item.damage.toDouble();
      } else if (colKey == 'sreturn') {
        val = item.saleReturn.toDouble();
      } else if (colKey == 'sales') {
        val = item.sales.toDouble();
      } else if (colKey == 'b2bsales') {
        val = item.b2bSales.toDouble();
      } else if (colKey == 'preturn') {
        val = item.purchaseReturn.toDouble();
      } else if (colKey == 'adjustment') {
        val = item.adjustment.toDouble();
      } else if (colKey == 'inward') {
        int posAdj = item.adjustment > 0 ? item.adjustment : 0;
        val = (item.purchase + item.saleReturn + posAdj).toDouble();
      } else if (colKey == 'outward') {
        int negAdj = item.adjustment < 0 ? item.adjustment.abs() : 0;
        val = (item.sales + item.purchaseReturn + item.damage.abs() + negAdj).toDouble();
      } else if (colKey == 'closing') {
        val = item.closingStock.toDouble();
      } else if (colKey == 'mrp_val') {
        val = item.mrpValue;
      } else if (colKey == 'lcost_val') {
        val = item.lCostValue;
      }

      if (val != null) values.add(val);
    }

    if (values.isEmpty) return "";

    bool isCurrency = colKey.contains('_val');
    switch (type) {
      case AggregationType.sum:
        final sumVal = values.fold(0.0, (s, v) => s + v);
        return isCurrency ? "₹${sumVal.toStringAsFixed(0)}" : sumVal.toStringAsFixed(0);
      case AggregationType.min:
        final minVal = values.reduce((a, b) => a < b ? a : b);
        return isCurrency ? "₹${minVal.toStringAsFixed(0)}" : minVal.toStringAsFixed(0);
      case AggregationType.max:
        final maxVal = values.reduce((a, b) => a > b ? a : b);
        return isCurrency ? "₹${maxVal.toStringAsFixed(0)}" : maxVal.toStringAsFixed(0);
      case AggregationType.average:
        final avgVal = values.fold(0.0, (s, v) => s + v) / values.length;
        return isCurrency ? "₹${avgVal.toStringAsFixed(1)}" : avgVal.toStringAsFixed(1);
      default:
        return "";
    }
  }

  void _showAggregationMenu(Offset position, String colKey) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final currentAgg = _columnAggregations[colKey] ?? AggregationType.none;
    final resultStr = _calculateAggregation(colKey, currentAgg);

    final List<PopupMenuEntry<dynamic>> items = [
      _buildPopupItem(AggregationType.sum, "Sum", Icons.functions),
      _buildPopupItem(AggregationType.min, "Min", Icons.bar_chart),
      _buildPopupItem(AggregationType.max, "Max", Icons.bar_chart),
      _buildPopupItem(AggregationType.count, "Count", Icons.numbers),
      _buildPopupItem(AggregationType.average, "Average", Icons.abc),
      const PopupMenuDivider(),
      _buildPopupItem(AggregationType.none, "None", Icons.check),
    ];

    if (resultStr.isNotEmpty) {
      items.addAll([
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: "COPY_VALUE",
          height: 32,
          child: Row(
            children: [
              const Icon(Icons.copy, size: 14, color: Colors.blue),
              const SizedBox(width: 8),
              Text("Copy ($resultStr)", style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ]);
    }

    showMenu<dynamic>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: items,
    ).then((selected) {
      if (selected is AggregationType) {
        setState(() => _columnAggregations[colKey] = selected);
      } else if (selected == "COPY_VALUE") {
        Clipboard.setData(ClipboardData(text: resultStr));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Copied $resultStr to clipboard"), duration: const Duration(seconds: 1)),
          );
        }
      }
    });
  }

  PopupMenuItem<AggregationType> _buildPopupItem(AggregationType type, String label, IconData icon) {
    return PopupMenuItem<AggregationType>(
      value: type,
      height: 32,
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.blueGrey),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildTableTotalRow(double totalWidth) {
    int sumOpen = 0;
    int sumPur = 0;
    int sumDmg = 0;
    int sumSRet = 0;
    int sumSal = 0;
    int sumB2B = 0;
    int sumPRet = 0;
    int sumAdj = 0;
    int sumClosing = 0;
    double sumMrpVal = 0.0;
    double sumLCostVal = 0.0;

    for (var item in _filteredList) {
      sumOpen += item.openingStock;
      sumPur += item.purchase;
      sumDmg += item.damage;
      sumSRet += item.saleReturn;
      sumSal += item.sales;
      sumB2B += item.b2bSales;
      sumPRet += item.purchaseReturn;
      sumAdj += item.adjustment;
      sumClosing += item.closingStock;
      sumMrpVal += item.mrpValue;
      sumLCostVal += item.lCostValue;
    }

    return Container(
      width: totalWidth,
      height: 28,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EAF6),
        border: Border(top: BorderSide(color: Colors.grey.shade400, width: 1)),
      ),
      child: Row(
        children: _columns.map((col) {
          final selectedAgg = _columnAggregations[col.key];
          String valStr = '';
          if (selectedAgg != null && selectedAgg != AggregationType.none) {
            valStr = _calculateAggregation(col.key, selectedAgg);
          } else {
            if (col.key == 'sl') {
              valStr = 'TOTAL';
            } else if (col.key == 'product') {
              valStr = '${_filteredList.length} Items';
            } else if (col.key == 'opening') {
              valStr = '$sumOpen';
            } else if (col.key == 'purchase') {
              valStr = '$sumPur';
            } else if (col.key == 'damage') {
              valStr = '$sumDmg';
            } else if (col.key == 'sreturn') {
              valStr = '$sumSRet';
            } else if (col.key == 'sales') {
              valStr = '$sumSal';
            } else if (col.key == 'b2bsales') {
              valStr = '$sumB2B';
            } else if (col.key == 'preturn') {
              valStr = '$sumPRet';
            } else if (col.key == 'adjustment') {
              valStr = '$sumAdj';
            } else if (col.key == 'inward') {
              int sumInward = 0;
              for (var item in _filteredList) {
                int posAdj = item.adjustment > 0 ? item.adjustment : 0;
                sumInward += (item.purchase + item.saleReturn + posAdj);
              }
              valStr = '$sumInward';
            } else if (col.key == 'outward') {
              int sumOutward = 0;
              for (var item in _filteredList) {
                int negAdj = item.adjustment < 0 ? item.adjustment.abs() : 0;
                sumOutward += (item.sales + item.purchaseReturn + item.damage.abs() + negAdj);
              }
              valStr = '$sumOutward';
            } else if (col.key == 'closing') {
              valStr = '$sumClosing';
            } else if (col.key == 'mrp_val') {
              valStr = '₹${sumMrpVal.toStringAsFixed(0)}';
            } else if (col.key == 'lcost_val') {
              valStr = '₹${sumLCostVal.toStringAsFixed(0)}';
            }
          }

          return GestureDetector(
            onTapDown: (details) => _showAggregationMenu(details.globalPosition, col.key),
            onSecondaryTapDown: (details) => _showAggregationMenu(details.globalPosition, col.key),
            child: ERPTooltip(
              message: valStr,
              child: Container(
                width: col.width,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: col.align == TextAlign.left
                    ? Alignment.centerLeft
                    : (col.align == TextAlign.center ? Alignment.center : Alignment.centerRight),
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: Colors.grey.shade300, width: 0.5)),
                ),
                child: Text(
                  valStr,
                  style: const TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Isolated Hover Wrapper Widget (Prevents recursive parent rebuilds & screen blinking)
class _HoverCellWrapper extends StatefulWidget {
  final Widget Function(BuildContext context, bool isHovered) builder;

  const _HoverCellWrapper({required this.builder});

  @override
  State<_HoverCellWrapper> createState() => _HoverCellWrapperState();
}

class _HoverCellWrapperState extends State<_HoverCellWrapper> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: widget.builder(context, _isHovered),
    );
  }
}

/// ERP ADVANCED FILTER POPUP (Photo 1: Values Tab Checklist, Photo 2: Numeric Range / Filters, Photo 4: Hierarchical Values)
class ERPAdvancedFilterPopup extends StatefulWidget {
  final String columnName;
  final bool isNumeric;
  final List<String> uniqueValues;
  final double minVal;
  final double maxVal;
  final Map<String, dynamic>? initialFilter;

  const ERPAdvancedFilterPopup({
    super.key,
    required this.columnName,
    required this.isNumeric,
    required this.uniqueValues,
    required this.minVal,
    required this.maxVal,
    this.initialFilter,
  });

  @override
  State<ERPAdvancedFilterPopup> createState() => _ERPAdvancedFilterPopupState();
}

class _ERPAdvancedFilterPopupState extends State<ERPAdvancedFilterPopup> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  String _searchQuery = "";
  late List<String> _selectedValues;

  late double _fromNum;
  late double _toNum;
  String _ruleCondition = "Contains";
  final TextEditingController _val1Ctrl = TextEditingController();
  late final TextEditingController _fromCtrl;
  late final TextEditingController _toCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _selectedValues = List.from(widget.uniqueValues);

    _fromNum = widget.minVal;
    _toNum = widget.maxVal;

    if (widget.initialFilter != null) {
      if (widget.initialFilter!['mode'] == 'values') {
        _tabCtrl.index = 0;
        _selectedValues = List<String>.from(widget.initialFilter!['selected_values'] ?? widget.uniqueValues);
      } else if (widget.initialFilter!['mode'] == 'range') {
        _tabCtrl.index = 1;
        _fromNum = widget.initialFilter!['from'] ?? widget.minVal;
        _toNum = widget.initialFilter!['to'] ?? widget.maxVal;
      } else if (widget.initialFilter!['mode'] == 'rules') {
        _tabCtrl.index = 1;
        _ruleCondition = widget.initialFilter!['condition'] ?? 'Equals';
        _val1Ctrl.text = widget.initialFilter!['value1'] ?? '';
      }
    }

    _fromCtrl = TextEditingController(text: _fromNum.toStringAsFixed(2));
    _toCtrl = TextEditingController(text: _toNum.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _val1Ctrl.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  void _applyValuesFilter() {
    Navigator.pop(context, {
      'mode': 'values',
      'selected_values': _selectedValues,
    });
  }

  void _applyRangeFilter() {
    Navigator.pop(context, {
      'mode': 'range',
      'from': _fromNum,
      'to': _toNum,
    });
  }

  void _applyRulesFilter() {
    if (_ruleCondition == 'Clear') {
      Navigator.pop(context, {'condition': 'Clear'});
      return;
    }
    Navigator.pop(context, {
      'mode': 'rules',
      'condition': _ruleCondition,
      'value1': _val1Ctrl.text,
    });
  }

  void _clearFilter() {
    Navigator.pop(context, {'condition': 'Clear'});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      height: 330,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Column(
        children: [
          // Header Tabs (Photo 1 & Photo 2: "Values" vs "Numeric Filters" / "Data Filters")
          Container(
            height: 32,
            color: const Color(0xFFE2E8F0),
            child: TabBar(
              controller: _tabCtrl,
              labelColor: const Color(0xFF0F172A),
              unselectedLabelColor: Colors.blueGrey,
              labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              indicatorColor: Colors.blue.shade800,
              indicatorWeight: 2.5,
              tabs: [
                const Tab(text: "Values"),
                Tab(text: widget.isNumeric ? "Numeric Filters" : "Data Filters"),
              ],
            ),
          ),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildValuesTab(),
                widget.isNumeric ? _buildNumericFiltersTab() : _buildDataFiltersTab(),
              ],
            ),
          ),

          // Bottom Action Bar (Clear Filter & Apply / Close)
          Container(
            height: 36,
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade300))),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _clearFilter,
                  child: const Text("Clear Filter", style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (_tabCtrl.index == 0) {
                      _applyValuesFilter();
                    } else {
                      if (widget.isNumeric) {
                        _applyRangeFilter();
                      } else {
                        _applyRulesFilter();
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade800,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(60, 24),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                  child: const Text("Apply", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // TAB 1: VALUES CHECKLIST (Photo 1 & Photo 4 with Search & Select All)
  Widget _buildValuesTab() {
    final filteredList = widget.uniqueValues.where((v) => v.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    bool allSelected = _selectedValues.length == widget.uniqueValues.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(6.0),
          child: SizedBox(
            height: 26,
            child: TextField(
              style: const TextStyle(fontSize: 10),
              decoration: InputDecoration(
                hintText: "Search values...",
                prefixIcon: const Icon(Icons.search, size: 14, color: Colors.blueGrey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        ),
        InkWell(
          onTap: () {
            setState(() {
              if (allSelected) {
                _selectedValues.clear();
              } else {
                _selectedValues = List.from(widget.uniqueValues);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Icon(allSelected ? Icons.check_box : Icons.check_box_outline_blank, size: 15, color: Colors.blue.shade800),
                const SizedBox(width: 8),
                const Text("(Select All)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: filteredList.length,
            itemBuilder: (ctx, idx) {
              final val = filteredList[idx];
              final isChecked = _selectedValues.contains(val);

              return InkWell(
                onTap: () {
                  setState(() {
                    if (isChecked) {
                      _selectedValues.remove(val);
                    } else {
                      _selectedValues.add(val);
                    }
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  child: Row(
                    children: [
                      Icon(isChecked ? Icons.check_box : Icons.check_box_outline_blank, size: 14, color: isChecked ? Colors.blue.shade800 : Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          val.isEmpty ? "(Blank)" : val,
                          style: const TextStyle(fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // TAB 2: NUMERIC FILTERS (Photo 2: From/To Inputs + Range Slider)
  Widget _buildNumericFiltersTab() {
    double minRange = widget.minVal;
    double maxRange = widget.maxVal <= widget.minVal ? widget.minVal + 100.0 : widget.maxVal;

    double currentFrom = _fromNum.clamp(minRange, maxRange);
    double currentTo = _toNum.clamp(currentFrom, maxRange);

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("From", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: 26,
                      child: TextField(
                        controller: _fromCtrl,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (v) {
                          double? p = double.tryParse(v);
                          if (p != null) {
                            _fromNum = p;
                            setState(() {});
                          }
                        },
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("To", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: 26,
                      child: TextField(
                        controller: _toCtrl,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (v) {
                          double? p = double.tryParse(v);
                          if (p != null) {
                            _toNum = p;
                            setState(() {});
                          }
                        },
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          RangeSlider(
            values: RangeValues(currentFrom, currentTo),
            min: minRange,
            max: maxRange,
            activeColor: Colors.blue.shade800,
            inactiveColor: Colors.grey.shade300,
            onChanged: (RangeValues vals) {
              setState(() {
                _fromNum = vals.start;
                _toNum = vals.end;
                _fromCtrl.text = _fromNum.toStringAsFixed(2);
                _toCtrl.text = _toNum.toStringAsFixed(2);
              });
            },
          ),
          const Spacer(),
        ],
      ),
    );
  }

  // TAB 2 (TEXT): DATA FILTERS RULES
  Widget _buildDataFiltersTab() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Select Rule Condition:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          const SizedBox(height: 6),
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _ruleCondition,
                isExpanded: true,
                style: const TextStyle(fontSize: 10, color: Colors.black87, fontWeight: FontWeight.bold),
                items: ["Contains", "Equals", "Does Not Equal", "Begins With", "Ends With"].map((cond) {
                  return DropdownMenuItem(value: cond, child: Text(cond));
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _ruleCondition = v);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),

          SizedBox(
            height: 28,
            child: TextField(
              controller: _val1Ctrl,
              style: const TextStyle(fontSize: 10),
              decoration: InputDecoration(
                hintText: "Enter value...",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
