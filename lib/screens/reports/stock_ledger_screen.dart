import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../providers/pharmacy_provider.dart';
import '../../providers/app_provider.dart';
import '../../services/supabase_sync_service.dart';
import '../../widgets/app_date_picker.dart';
import '../../utils/report_pdf_generator.dart';
import '../../utils/printer_service.dart';
import '../../utils/app_formatters.dart';
import '../consolidate_stock_screen.dart';

enum ColType { text, numeric }

class _ColDef {
  final String key;
  final String label;
  double width;
  final TextAlign align;
  final ColType type;

  _ColDef(this.key, this.label, {this.width = 90.0, this.align = TextAlign.left, this.type = ColType.text});
}

class StockLedgerScreen extends StatefulWidget {
  const StockLedgerScreen({super.key});

  @override
  State<StockLedgerScreen> createState() => _StockLedgerScreenState();
}

class _StockLedgerScreenState extends State<StockLedgerScreen> {
  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();

  bool _isDetailedView = false;
  bool _isLoading = false;

  List<StockLedgerItem> _masterList = [];
  List<StockLedgerItem> _filteredList = [];
  int? _selectedIndex;
  int? _lastTapIndex;
  DateTime? _lastTapTime;

  final Map<String, TextEditingController> _filterCtrls = {};
  final Map<String, String> _filterConditions = {};
  final Map<String, Map<String, dynamic>> _advancedFilters = {};

  String? _sortKey;
  bool _isAscending = true;

  final TextEditingController _productSearchCtrl = TextEditingController();
  final FocusNode _productSearchFocusNode = FocusNode();

  final ScrollController _horizontalScrollCtrl = ScrollController();
  final ScrollController _verticalScrollCtrl = ScrollController();

  final Map<String, double> _colWidths = {};

  List<_ColDef> get _columns {
    List<_ColDef> cols;
    if (_isDetailedView) {
      cols = [
        _ColDef('date', 'DATE', width: 85.0, align: TextAlign.left, type: ColType.text),
        _ColDef('time', 'TIME', width: 65.0, align: TextAlign.left, type: ColType.text),
        _ColDef('sl', 'SL', width: 40.0, align: TextAlign.center, type: ColType.numeric),
        _ColDef('product', 'Product', width: 180.0, align: TextAlign.left, type: ColType.text),
        _ColDef('patent', 'Patent', width: 90.0, align: TextAlign.left, type: ColType.text),
        _ColDef('packing', 'Packing', width: 55.0, align: TextAlign.center, type: ColType.numeric),
        _ColDef('batch', 'Batch', width: 85.0, align: TextAlign.left, type: ColType.text),
        _ColDef('hsn', 'Hsncode', width: 75.0, align: TextAlign.left, type: ColType.text),
        _ColDef('gst', 'GST %', width: 50.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('mrp', 'MRP', width: 65.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('p_rate', 'P.Rate', width: 65.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('l_cost', 'L.Cost', width: 65.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('supplier', 'Supplier', width: 120.0, align: TextAlign.left, type: ColType.text),
        _ColDef('opening', 'Opening Stock', width: 85.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('purchase', 'Purchase', width: 65.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('preturn', 'P.Return', width: 60.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('sales', 'Sales', width: 65.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('sreturn', 'S.Return', width: 60.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('damage', 'Damage', width: 60.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('adjustment', 'Adjustment', width: 70.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('closing', 'Closing Stock', width: 85.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('mrp_val', 'MRP Value', width: 85.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('lcost_val', 'Lcost Value', width: 85.0, align: TextAlign.right, type: ColType.numeric),
      ];
    } else {
      cols = [
        _ColDef('date', 'DATE', width: 85.0, align: TextAlign.left, type: ColType.text),
        _ColDef('sl', 'SL', width: 40.0, align: TextAlign.center, type: ColType.numeric),
        _ColDef('product', 'Product', width: 200.0, align: TextAlign.left, type: ColType.text),
        _ColDef('packing', 'Packing', width: 60.0, align: TextAlign.center, type: ColType.numeric),
        _ColDef('batch', 'Batch', width: 90.0, align: TextAlign.left, type: ColType.text),
        _ColDef('supplier', 'Supplier', width: 130.0, align: TextAlign.left, type: ColType.text),
        _ColDef('opening', 'Opening', width: 75.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('inward', 'Inward (+)', width: 80.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('outward', 'Outward (-)', width: 80.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('closing', 'Closing Stock', width: 90.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('mrp_val', 'MRP Value', width: 90.0, align: TextAlign.right, type: ColType.numeric),
        _ColDef('lcost_val', 'Lcost Value', width: 90.0, align: TextAlign.right, type: ColType.numeric),
      ];
    }

    for (var c in cols) {
      if (_colWidths.containsKey(c.key)) {
        c.width = _colWidths[c.key]!;
      }
    }
    return cols;
  }

  @override
  void initState() {
    super.initState();
    _initFilterCtrls();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchData();
    });
  }

  void _initFilterCtrls() {
    for (var col in _columns) {
      if (!_filterCtrls.containsKey(col.key)) {
        final ctrl = TextEditingController();
        ctrl.addListener(_applyHeaderFilters);
        _filterCtrls[col.key] = ctrl;
        _filterConditions[col.key] = col.type == ColType.numeric ? 'Equals' : 'Contains';
      }
    }
  }

  @override
  void dispose() {
    for (var ctrl in _filterCtrls.values) {
      ctrl.dispose();
    }
    _productSearchCtrl.dispose();
    _productSearchFocusNode.dispose();
    _horizontalScrollCtrl.dispose();
    _verticalScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    _fromDate = appProvider.reportFromDate;
    _toDate = appProvider.reportToDate;

    try {
      await SupabaseSyncService.instance.refreshDateRangeTransactionsCloudDirect(_fromDate, _toDate);
      final items = await provider.getStockLedgerReport(
        _fromDate,
        _toDate,
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
      }
    }
  }

  void _onColumnHeaderTap(String key) {
    setState(() {
      if (_sortKey == key) {
        if (_isAscending) {
          _isAscending = false;
        } else {
          _sortKey = null;
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

    // 0. Main Search Box Query Filter
    final mainSearchQuery = _productSearchCtrl.text.trim().toLowerCase();
    if (mainSearchQuery.isNotEmpty) {
      list = list.where((item) {
        String name = item.productName.toLowerCase();
        String batch = item.batch.toLowerCase();
        String supp = item.supplier.toLowerCase();
        return name.contains(mainSearchQuery) || batch.contains(mainSearchQuery) || supp.contains(mainSearchQuery);
      }).toList();
    }

    // 1. Advanced Filters
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
      }
    });

    // 2. Quick Column Header Filters
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

    // 3. Sorting
    if (_sortKey != null) {
      final key = _sortKey!;
      final colDef = _columns.firstWhere((c) => c.key == key, orElse: () => _columns.first);
      final isNum = colDef.type == ColType.numeric;

      list.sort((a, b) {
        dynamic valA = _getCellValueByKey(a, key);
        dynamic valB = _getCellValueByKey(b, key);

        int comp = 0;
        if (isNum) {
          double numA = (valA is num) ? valA.toDouble() : (double.tryParse(valA?.toString() ?? '0') ?? 0.0);
          double numB = (valB is num) ? valB.toDouble() : (double.tryParse(valB?.toString() ?? '0') ?? 0.0);
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
      case 'date':
        return DateFormat('dd/MM/yyyy').format(_fromDate);
      case 'time':
        return DateFormat('hh:mm a').format(DateTime.now());
      case 'product':
      case 'product_name':
        return item.productName;
      case 'patent':
        return item.patent;
      case 'packing':
        return item.packin;
      case 'batch':
        return cleanBatch(item.batch);
      case 'hsn':
        return item.hsnCode;
      case 'gst':
        return item.gst;
      case 'mrp':
        return item.mrp;
      case 'p_rate':
        return item.lCost;
      case 'l_cost':
        return item.lCost;
      case 'supplier':
        return item.supplier;
      case 'opening':
        return item.openingStock;
      case 'purchase':
      case 'purchase_qty':
        return item.purchase;
      case 'preturn':
      case 'preturn_qty':
        return item.purchaseReturn;
      case 'sales':
      case 'sales_qty':
        return item.sales;
      case 'sreturn':
      case 'sreturn_qty':
        return item.saleReturn;
      case 'damage':
      case 'damage_qty':
        return item.damage;
      case 'adjustment':
      case 'adjustment_qty':
        return item.adjustment;
      case 'inward':
      case 'in_qty':
        return (item.purchase + item.saleReturn);
      case 'outward':
      case 'out_qty':
        return (item.sales + item.purchaseReturn + item.damage.abs());
      case 'closing':
      case 'balance':
        return item.closingStock;
      case 'mrp_val':
        return item.mrpValue;
      case 'lcost_val':
        return item.lCostValue;
      default:
        return '';
    }
  }

  void _printLedger() async {
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
      title: "Historical Stock Movement Register",
      headers: headers,
      data: data,
      company: pharma.companyProfile,
      subtitle: "Period: ${DateFormat('dd/MM/yyyy').format(_fromDate)} to ${DateFormat('dd/MM/yyyy').format(_toDate)} | Total Items: ${_filteredList.length}",
    );

    if (!mounted) return;
    PrinterService.showProfessionalPreview(context: context, doc: doc, title: "Stock Ledger Preview");
  }

  void _exportExcel() async {
    if (_filteredList.isEmpty) return;
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);
    final String defaultFileName = "Stock_Ledger_Register_${DateFormat('ddMMyyyy').format(_fromDate)}_${DateFormat('ddMMyyyy').format(_toDate)}.xlsx";

    String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Save Excel Report',
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (outputFile != null) {
      final bytes = await pharma.exportStockLedgerReportToExcelBytes(_filteredList, _fromDate, _toDate);
      if (bytes != null && bytes.isNotEmpty) {
        await File(outputFile).writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Stock ledger exported successfully to Excel!"), backgroundColor: Colors.green),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);

    // Sync shared state from AppProvider
    if (_fromDate != appProvider.reportFromDate || _toDate != appProvider.reportToDate) {
      _fromDate = appProvider.reportFromDate;
      _toDate = appProvider.reportToDate;
      _fetchData();
    }
    _isDetailedView = appProvider.reportDetailedView;
    if (_productSearchCtrl.text != appProvider.reportSearchQuery) {
      _productSearchCtrl.text = appProvider.reportSearchQuery;
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
                            // Header Row (ALWAYS RENDERED)
                            Row(
                              children: _columns.map((col) => _buildHeaderCell(col)).toList(),
                            ),

                            // Main Table Data Rows
                            Expanded(
                              child: SingleChildScrollView(
                                controller: _verticalScrollCtrl,
                                scrollDirection: Axis.vertical,
                                child: SizedBox(
                                  width: totalTableWidth,
                                  child: _filteredList.isEmpty
                                      ? const SizedBox(
                                          height: 200,
                                          child: Center(child: Text("No matching stock movement records found.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
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

                            // Bottom Totals Summary Row
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
            child: Icon(Icons.history_rounded, color: Colors.blue.shade800, size: 18),
          ),
          const SizedBox(width: 8),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("HISTORICAL STOCK MOVEMENT REGISTER", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
              Text("Audit Movement History & Detailed Quantity Breakdown", style: TextStyle(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(width: 8),

          // Refresh Button
          Tooltip(
            message: "Refresh Data",
            child: InkWell(
              onTap: _fetchData,
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
                                textEditingController: _productSearchCtrl,
                                focusNode: _productSearchFocusNode,
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
                                  _productSearchCtrl.text = selection;
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
                              _fetchData();
                            }),
                            const SizedBox(width: 3),
                            _presetPill("This Month", () {
                              final now = DateTime.now();
                              appProvider.setReportDateRange(DateTime(now.year, now.month, 1), now);
                              _fetchData();
                            }),
                            const SizedBox(width: 3),
                            _presetPill("FY", () {
                              final now = DateTime.now();
                              int startYear = now.month >= 4 ? now.year : now.year - 1;
                              appProvider.setReportDateRange(DateTime(startYear, 4, 1), now);
                              _fetchData();
                            }),
                            const SizedBox(width: 6),

                            // Date Pickers
                            _datePicker("From", _fromDate, (d) { appProvider.setReportDateRange(d, _toDate); _fetchData(); }),
                            const SizedBox(width: 4),
                            _datePicker("To", _toDate, (d) { appProvider.setReportDateRange(_fromDate, d); _fetchData(); }),
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
                                _initFilterCtrls();
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
                                      _initFilterCtrls();
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

                            // 1-Click Page Switcher Button to Consolidate Stock Position
                            ElevatedButton.icon(
                              onPressed: () => Provider.of<AppProvider>(context, listen: false).openConsolidateStock(),
                              icon: const Icon(Icons.swap_horiz_rounded, size: 14),
                              label: const Text("CONSOLIDATE STOCK POSITION", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
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
                                  _printLedger();
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
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
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
    } else if (cond == 'Greater Than') conditionSymbol = '>';
    else if (cond == 'Less Than') conditionSymbol = '<';
    else if (cond == 'Does Not Equal') conditionSymbol = '!=';

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
    final bool isSelected = (index == _selectedIndex);

    return InkWell(
      onTap: () {
        final now = DateTime.now();
        setState(() => _selectedIndex = index);
        if (_lastTapIndex == index && _lastTapTime != null && now.difference(_lastTapTime!) < const Duration(milliseconds: 350)) {
          _lastTapTime = null;
          _lastTapIndex = null;
          if (item.productName.isNotEmpty) {
            Provider.of<AppProvider>(context, listen: false).openStockEnquiries(initialQuery: item.productName);
          }
        } else {
          _lastTapIndex = index;
          _lastTapTime = now;
        }
      },
      child: Container(
        width: totalWidth,
        height: 30,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFBAE6FD) : (isEven ? Colors.white : const Color(0xFFF9F9F9)),
          border: Border(bottom: BorderSide(color: isSelected ? Colors.blue.shade300 : Colors.grey.shade200, width: 0.5)),
        ),
        child: Row(
          children: _columns.map((col) {
            dynamic rawVal = col.key == 'sl' ? (index + 1) : _getCellValueByKey(item, col.key);

            String textStr = '';
            Color textColor = Colors.black87;
            FontWeight fontWeight = FontWeight.normal;

            if (col.key == 'name' || col.key == 'product_name') {
              fontWeight = FontWeight.w600;
            }

            if (rawVal is double) {
              textStr = rawVal.toStringAsFixed(2);
              if (col.key == 'closing' || col.key == 'balance') {
                fontWeight = FontWeight.bold;
                if (item.closingStock < 0) {
                  textColor = Colors.red.shade700;
                } else if (item.closingStock == 0) {
                  textColor = Colors.orange.shade800;
                }
              }
            } else if (rawVal is int) {
              textStr = rawVal.toString();
              if ((col.key == 'purchase' || col.key == 'purchase_qty' || col.key == 'inward' || col.key == 'in_qty') && rawVal > 0) {
                textColor = Colors.green.shade800;
              }
              if ((col.key == 'sales' || col.key == 'sales_qty' || col.key == 'outward' || col.key == 'out_qty') && rawVal > 0) {
                textColor = Colors.red.shade800;
              }
              if ((col.key == 'damage' || col.key == 'damage_qty') && rawVal > 0) {
                textColor = Colors.red.shade800;
              }
              if (col.key == 'closing' || col.key == 'balance') {
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
      ),
    );
  }

  Widget _buildTableTotalRow(double totalWidth) {
    int sumOpen = 0;
    int sumPur = 0;
    int sumDmg = 0;
    int sumSRet = 0;
    int sumSal = 0;
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
          String valStr = '';
          if (col.key == 'sl') {
            valStr = 'TOTAL';
          } else if (col.key == 'product' || col.key == 'product_name') valStr = '${_filteredList.length} Items';
          else if (col.key == 'opening') valStr = '$sumOpen';
          else if (col.key == 'purchase' || col.key == 'purchase_qty') valStr = '+$sumPur';
          else if (col.key == 'damage' || col.key == 'damage_qty') valStr = '-$sumDmg';
          else if (col.key == 'sreturn' || col.key == 'sreturn_qty') valStr = '+$sumSRet';
          else if (col.key == 'sales' || col.key == 'sales_qty') valStr = '-$sumSal';
          else if (col.key == 'preturn' || col.key == 'preturn_qty') valStr = '-$sumPRet';
          else if (col.key == 'adjustment' || col.key == 'adjustment_qty') valStr = '$sumAdj';
          else if (col.key == 'inward' || col.key == 'in_qty') valStr = '+${sumPur + sumSRet}';
          else if (col.key == 'outward' || col.key == 'out_qty') valStr = '-${sumSal + sumPRet + sumDmg.abs()}';
          else if (col.key == 'closing' || col.key == 'balance') valStr = '$sumClosing';
          else if (col.key == 'mrp_val') valStr = '₹${sumMrpVal.toStringAsFixed(0)}';
          else if (col.key == 'lcost_val') valStr = '₹${sumLCostVal.toStringAsFixed(0)}';

          return Container(
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
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF1A237E)),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
      ),
    );
  }
}

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
