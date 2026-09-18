import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../providers/pharmacy_provider.dart';
import '../widgets/app_date_picker.dart';
import '../utils/report_pdf_generator.dart';
import '../utils/printer_service.dart';
import '../utils/app_formatters.dart';

class ConsolidateStockScreen extends StatefulWidget {
  const ConsolidateStockScreen({super.key});

  @override
  State<ConsolidateStockScreen> createState() => _ConsolidateStockScreenState();
}

class _ConsolidateStockScreenState extends State<ConsolidateStockScreen> {
  DateTime _fromDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _toDate = DateTime.now();

  String _selectedSupplier = 'ALL';
  final String _selectedCategory = 'ALL';
  bool _isLoading = false;

  List<StockLedgerItem> _masterList = [];
  List<StockLedgerItem> _filteredList = [];

  final Map<String, TextEditingController> _filterCtrls = {};
  final ScrollController _horizontalScrollCtrl = ScrollController();
  final ScrollController _verticalScrollCtrl = ScrollController();

  final List<Map<String, dynamic>> _columns = [
    {'key': 'sl', 'label': 'SL', 'width': 45.0, 'align': TextAlign.center, 'isNumeric': true},
    {'key': 'product', 'label': 'Product', 'width': 210.0, 'align': TextAlign.left, 'isNumeric': false},
    {'key': 'patent', 'label': 'Patent', 'width': 100.0, 'align': TextAlign.left, 'isNumeric': false},
    {'key': 'packing', 'label': 'Packing', 'width': 65.0, 'align': TextAlign.center, 'isNumeric': true},
    {'key': 'batch', 'label': 'Batch', 'width': 95.0, 'align': TextAlign.left, 'isNumeric': false},
    {'key': 'hsn', 'label': 'Hsncode', 'width': 85.0, 'align': TextAlign.left, 'isNumeric': false},
    {'key': 'gst', 'label': 'gst', 'width': 55.0, 'align': TextAlign.right, 'isNumeric': true},
    {'key': 'mrp', 'label': 'Mrp', 'width': 75.0, 'align': TextAlign.right, 'isNumeric': true},
    {'key': 'supplier', 'label': 'Supplier', 'width': 140.0, 'align': TextAlign.left, 'isNumeric': false},
    {'key': 'opening', 'label': 'Opening Stock', 'width': 95.0, 'align': TextAlign.right, 'isNumeric': true},
    {'key': 'op_val', 'label': 'Op.Stock Val', 'width': 95.0, 'align': TextAlign.right, 'isNumeric': true},
    {'key': 'purchase', 'label': 'Purchase', 'width': 75.0, 'align': TextAlign.right, 'isNumeric': true},
    {'key': 'damage', 'label': 'Damage', 'width': 65.0, 'align': TextAlign.right, 'isNumeric': true},
    {'key': 'sreturn', 'label': 'S.Return', 'width': 65.0, 'align': TextAlign.right, 'isNumeric': true},
    {'key': 'sales', 'label': 'Sales', 'width': 70.0, 'align': TextAlign.right, 'isNumeric': true},
    {'key': 'b2bsales', 'label': 'B2BSales', 'width': 75.0, 'align': TextAlign.right, 'isNumeric': true},
    {'key': 'preturn', 'label': 'P.Return', 'width': 65.0, 'align': TextAlign.right, 'isNumeric': true},
    {'key': 'adjustment', 'label': 'Adjustment', 'width': 80.0, 'align': TextAlign.right, 'isNumeric': true},
    {'key': 'closing', 'label': 'Closing Stock', 'width': 95.0, 'align': TextAlign.right, 'isNumeric': true},
    {'key': 'mrp_val', 'label': 'MRP Value', 'width': 95.0, 'align': TextAlign.right, 'isNumeric': true},
    {'key': 'lcost_val', 'label': 'Lcost Value', 'width': 95.0, 'align': TextAlign.right, 'isNumeric': true},
  ];

  @override
  void initState() {
    super.initState();
    for (var col in _columns) {
      final ctrl = TextEditingController();
      ctrl.addListener(_applyHeaderFilters);
      _filterCtrls[col['key']] = ctrl;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchStockData();
    });
  }

  @override
  void dispose() {
    for (var ctrl in _filterCtrls.values) {
      ctrl.dispose();
    }
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

  void _applyHeaderFilters() {
    List<StockLedgerItem> list = List.from(_masterList);

    _filterCtrls.forEach((key, ctrl) {
      final query = ctrl.text.trim().toLowerCase();
      if (query.isEmpty) return;

      list = list.where((item) {
        String cellVal = _getCellValueByKey(item, key).toString().toLowerCase();

        if (query.startsWith('=')) {
          final target = query.substring(1).trim();
          return cellVal == target;
        } else if (query.startsWith('>')) {
          final numTarget = double.tryParse(query.substring(1).trim()) ?? 0.0;
          final cellNum = double.tryParse(cellVal) ?? 0.0;
          return cellNum > numTarget;
        } else if (query.startsWith('<')) {
          final numTarget = double.tryParse(query.substring(1).trim()) ?? 0.0;
          final cellNum = double.tryParse(cellVal) ?? 0.0;
          return cellNum < numTarget;
        } else if (query.startsWith('inc ')) {
          final target = query.substring(4).trim();
          return cellVal.contains(target);
        } else {
          return cellVal.contains(query);
        }
      }).toList();
    });

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
      case 'closing': return item.closingStock;
      case 'mrp_val': return item.mrpValue;
      case 'lcost_val': return item.lCostValue;
      default: return '';
    }
  }

  void _exportExcel() async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Stock register exported successfully to Excel!"), backgroundColor: Colors.green),
          );
        }
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
    final double totalTableWidth = _columns.fold(0.0, (sum, col) => sum + (col['width'] as double));

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          _buildTopToolbar(),
          _buildKpiSummaryCards(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade300),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4)],
                    ),
                    child: Column(
                      children: [
                        // Scrollable Header & Filter Section
                        SingleChildScrollView(
                          controller: _horizontalScrollCtrl,
                          scrollDirection: Axis.horizontal,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTableHeaderRow(totalTableWidth),
                              _buildHeaderFilterRow(totalTableWidth),
                            ],
                          ),
                        ),
                        const Divider(height: 1, thickness: 1, color: Color(0xFFCBD5E1)),
                        
                        // Main Table Data Rows
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _verticalScrollCtrl,
                            scrollDirection: Axis.vertical,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
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
                                        itemCount: _filteredList.length,
                                        itemBuilder: (ctx, i) {
                                          return _buildTableRow(_filteredList[i], i);
                                        },
                                      ),
                              ),
                            ),
                          ),
                        ),

                        // Fixed Bottom Total Summary Row
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: _buildTableTotalRow(totalTableWidth),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopToolbar() {
    final pharma = Provider.of<PharmacyProvider>(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.grid_on_rounded, color: Colors.blue.shade800, size: 20),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("CONSOLIDATED STOCK REGISTER", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
              Text("Complete Multi-Product Movement, Stock Balances & Asset Valuation", style: TextStyle(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
            ],
          ),
          const Spacer(),

          // Supplier Filter Dropdown Box ("Supplier Box Extra")
          FutureBuilder<List<Map<String, dynamic>>>(
            future: pharma.getWholesalerNamesWithCounts(),
            builder: (context, snapshot) {
              List<String> suppliers = ['ALL'];
              if (snapshot.hasData && snapshot.data != null) {
                for (var r in snapshot.data!) {
                  if (r['name'] != null && r['name'].toString().isNotEmpty) {
                    suppliers.add(r['name'].toString());
                  }
                }
              }

              return Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: suppliers.contains(_selectedSupplier) ? _selectedSupplier : 'ALL',
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.blueGrey, size: 18),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedSupplier = val);
                        _fetchStockData();
                      }
                    },
                    items: suppliers.map((s) {
                      return DropdownMenuItem(
                        value: s,
                        child: Text(s == 'ALL' ? "🏬 ALL SUPPLIERS" : "🏬 $s", overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 10),

          // Date Pickers
          _datePicker("From", _fromDate, (d) { setState(() => _fromDate = d); _fetchStockData(); }),
          const SizedBox(width: 6),
          _datePicker("To", _toDate, (d) { setState(() => _toDate = d); _fetchStockData(); }),
          const SizedBox(width: 12),

          // Export Excel Button
          ElevatedButton.icon(
            onPressed: _exportExcel,
            icon: const Icon(Icons.file_download, size: 15),
            label: const Text("EXCEL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
          const SizedBox(width: 6),

          // Print PDF Button
          ElevatedButton.icon(
            onPressed: _printPdf,
            icon: const Icon(Icons.print, size: 15),
            label: const Text("PRINT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ],
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
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300)),
        child: Row(
          children: [
            const Icon(Icons.calendar_month, size: 14, color: Colors.blueGrey),
            const SizedBox(width: 4),
            Text(DateFormat('dd/MM/yy').format(date), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
      totalDmg += r.damage;
      totalClosing += r.closingStock;
      totalMrpVal += r.mrpValue;
      totalLCostVal += r.lCostValue;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: const Color(0xFFF1F5F9),
      child: Row(
        children: [
          _miniKpiCard("OPENING", "$totalOpen", Colors.blueGrey.shade800),
          const SizedBox(width: 8),
          _miniKpiCard("PURCHASE (+)", "+$totalPur", Colors.green.shade800),
          const SizedBox(width: 8),
          _miniKpiCard("SALES (-)", "-$totalSales", Colors.blue.shade800),
          const SizedBox(width: 8),
          _miniKpiCard("S.RETURNS (+)", "+$totalSRet", Colors.indigo.shade800),
          const SizedBox(width: 8),
          _miniKpiCard("P.RETURNS (-)", "-$totalPRet", Colors.orange.shade800),
          const SizedBox(width: 8),
          _miniKpiCard("DAMAGES (-)", "-$totalDmg", Colors.red.shade800),
          const SizedBox(width: 8),
          _miniKpiCard("CLOSING STOCK", "$totalClosing", Colors.teal.shade900, isBold: true),
          const Spacer(),
          _miniKpiCard("MRP VALUATION", "₹${totalMrpVal.toStringAsFixed(0)}", Colors.indigo.shade900, isBold: true),
          const SizedBox(width: 8),
          _miniKpiCard("COST VALUATION", "₹${totalLCostVal.toStringAsFixed(0)}", Colors.amber.shade900, isBold: true),
        ],
      ),
    );
  }

  Widget _miniKpiCard(String label, String value, Color color, {bool isBold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          Text(value, style: TextStyle(fontSize: 11, fontWeight: isBold ? FontWeight.w900 : FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildTableHeaderRow(double totalWidth) {
    return Container(
      width: totalWidth,
      height: 30,
      color: const Color(0xFF1E293B),
      child: Row(
        children: _columns.map((col) {
          final double w = col['width'];
          final TextAlign align = col['align'];
          return Container(
            width: w,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: align == TextAlign.left
                ? Alignment.centerLeft
                : (align == TextAlign.center ? Alignment.center : Alignment.centerRight),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.blueGrey.shade800, width: 0.8)),
            ),
            child: Text(
              col['label'].toString(),
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHeaderFilterRow(double totalWidth) {
    return Container(
      width: totalWidth,
      height: 26,
      color: const Color(0xFFE2E8F0),
      child: Row(
        children: _columns.map((col) {
          final String key = col['key'];
          final double w = col['width'];
          final bool isNum = col['isNumeric'];
          final ctrl = _filterCtrls[key]!;

          return Container(
            width: w,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.grey.shade300, width: 0.8)),
            ),
            child: TextField(
              controller: ctrl,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              decoration: InputDecoration(
                hintText: isNum ? "= / > / <" : "inc...",
                hintStyle: const TextStyle(fontSize: 8, color: Colors.blueGrey),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(3), borderSide: BorderSide(color: Colors.grey.shade300)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTableRow(StockLedgerItem item, int index) {
    final double totalWidth = _columns.fold(0.0, (sum, col) => sum + (col['width'] as double));
    final bool isEven = index % 2 == 0;

    return Container(
      width: totalWidth,
      height: 28,
      decoration: BoxDecoration(
        color: isEven ? Colors.white : const Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.8)),
      ),
      child: Row(
        children: _columns.map((col) {
          final String key = col['key'];
          final double w = col['width'];
          final TextAlign align = col['align'];

          dynamic rawVal;
          if (key == 'sl') {
            rawVal = index + 1;
          } else {
            rawVal = _getCellValueByKey(item, key);
          }

          String textStr = '';
          Color textColor = Colors.black87;
          bool isBold = false;

          if (rawVal is double) {
            textStr = rawVal.toStringAsFixed(2);
          } else if (rawVal is int) {
            textStr = rawVal.toString();
            if (key == 'purchase' && rawVal > 0) textColor = Colors.green.shade800;
            if (key == 'sales' && rawVal > 0) textColor = Colors.blue.shade800;
            if (key == 'damage' && rawVal > 0) textColor = Colors.red.shade800;
            if (key == 'closing') isBold = true;
          } else {
            textStr = rawVal?.toString() ?? '';
          }

          return Container(
            width: w,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: align == TextAlign.left
                ? Alignment.centerLeft
                : (align == TextAlign.center ? Alignment.center : Alignment.centerRight),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.grey.shade200, width: 0.8)),
            ),
            child: Text(
              textStr,
              style: TextStyle(
                fontSize: 10,
                color: textColor,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                fontFamily: (key == 'batch' || key == 'hsn') ? 'monospace' : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
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
      height: 30,
      color: const Color(0xFF0F172A),
      child: Row(
        children: _columns.map((col) {
          final String key = col['key'];
          final double w = col['width'];
          final TextAlign align = col['align'];

          String valStr = '';
          if (key == 'sl') {
            valStr = 'TOTAL';
          } else if (key == 'product') {
            valStr = '${_filteredList.length} Items';
          } else if (key == 'opening') {
            valStr = '$sumOpen';
          } else if (key == 'purchase') {
            valStr = '$sumPur';
          } else if (key == 'damage') {
            valStr = '$sumDmg';
          } else if (key == 'sreturn') {
            valStr = '$sumSRet';
          } else if (key == 'sales') {
            valStr = '$sumSal';
          } else if (key == 'b2bsales') {
            valStr = '$sumB2B';
          } else if (key == 'preturn') {
            valStr = '$sumPRet';
          } else if (key == 'adjustment') {
            valStr = '$sumAdj';
          } else if (key == 'closing') {
            valStr = '$sumClosing';
          } else if (key == 'mrp_val') {
            valStr = '₹${sumMrpVal.toStringAsFixed(0)}';
          } else if (key == 'lcost_val') {
            valStr = '₹${sumLCostVal.toStringAsFixed(0)}';
          }

          return Container(
            width: w,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: align == TextAlign.left
                ? Alignment.centerLeft
                : (align == TextAlign.center ? Alignment.center : Alignment.centerRight),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.blueGrey.shade800, width: 0.8)),
            ),
            child: Text(
              valStr,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
      ),
    );
  }
}
