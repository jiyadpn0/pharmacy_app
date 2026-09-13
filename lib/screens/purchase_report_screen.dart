import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as ex;
import '../providers/pharmacy_provider.dart';
import '../providers/app_provider.dart';
import '../widgets/app_date_picker.dart';
import 'package:intl/intl.dart';
import '../widgets/erp_tooltip.dart';
import '../utils/report_pdf_generator.dart';
import '../utils/printer_service.dart';
import '../utils/app_formatters.dart';
import '../utils/theme_constants.dart';

enum PurchaseReportType { detailed, summary, supplierWise, categoryWise }

class PurchaseReportScreen extends StatefulWidget {
  const PurchaseReportScreen({super.key});

  @override
  State<PurchaseReportScreen> createState() => _PurchaseReportScreenState();
}

class _PurchaseReportScreenState extends State<PurchaseReportScreen> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  PurchaseReportType _reportType = PurchaseReportType.detailed;
  final Map<String, Map<String, dynamic>> _activeFilters = {};
  double _headerHeight = 52.0;

  // CODE MASTER FIX: RAM Cache variables to stop the UI freeze
  List<Map<String, dynamic>> _masterData = [];
  List<Map<String, dynamic>> _displayData = [];
  bool _isLoading = false;

  // Pagination Variables
  int _offset = 0;
  final int _pageSize = 50;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();

  final Map<String, double> _colWidths = {
    'entry_no': 80, 'date': 90, 'supplier': 150, 'supplier_acc': 120, 'inv_no': 100, 'po_no': 80,
    'gross': 80, 'disc': 80, 's_disc': 80, 'net': 80, 'gst': 80, 'cgst': 70, 'sgst': 70, 'igst': 70,
    'subtotal': 100, 'other_disc': 90, 'other_charge': 90, 'credit_note': 90, 'total': 110, 'status': 70, 'tax_type': 80,
    'name': 180, 'rack': 70, 'category': 100, 'sub_category': 100, 'hsn': 80, 'batch': 90, 'expiry': 80,
    'qty': 60, 'packing': 70, 'f_qty': 60, 'p_rate': 80, 'gst_amt': 80, 'l_cost': 80, 's_rate': 80, 'mrp': 80, 'mrp_total': 100,
    'inv_count': 100, 'strip_qty': 80, 'loose_qty': 80
  };

  List<Map<String, String>> _getColumns() {
    switch (_reportType) {
      case PurchaseReportType.summary:
        return [
          {'key': 'entry_no', 'title': 'Entry No'}, {'key': 'date', 'title': 'Date'}, {'key': 'supplier', 'title': 'Supplier'},
          {'key': 'supplier_acc', 'title': 'Supplier Acc'}, {'key': 'inv_no', 'title': 'Sup Inv No'}, {'key': 'po_no', 'title': 'Po.No'},
          {'key': 'gross', 'title': 'Gross', 'type': 'numeric'}, {'key': 'disc', 'title': 'Disc', 'type': 'numeric'},
          {'key': 's_disc', 'title': 'SDisc', 'type': 'numeric'}, {'key': 'net', 'title': 'Net', 'type': 'numeric'},
          {'key': 'gst', 'title': 'gst', 'type': 'numeric'}, {'key': 'cgst', 'title': 'cgst', 'type': 'numeric'},
          {'key': 'sgst', 'title': 'sgst', 'type': 'numeric'}, {'key': 'igst', 'title': 'igst', 'type': 'numeric'},
          {'key': 'subtotal', 'title': 'Sub Total', 'type': 'numeric'}, {'key': 'other_disc', 'title': 'Other Disc', 'type': 'numeric'},
          {'key': 'other_charge', 'title': 'Other Ch...', 'type': 'numeric'}, {'key': 'credit_note', 'title': 'Credit Note', 'type': 'numeric'},
          {'key': 'total', 'title': 'Grand Total', 'type': 'numeric'}, {'key': 'status', 'title': 'status'}, {'key': 'tax_type', 'title': 'Tax Type'},
        ];
      case PurchaseReportType.detailed:
        return [
          {'key': 'entry_no', 'title': 'Entry No'}, {'key': 'date', 'title': 'Date'}, {'key': 'supplier', 'title': 'Supplier'},
          {'key': 'name', 'title': 'Name'}, {'key': 'rack', 'title': 'Rack'}, {'key': 'category', 'title': 'Category'},
          {'key': 'sub_category', 'title': 'Sub Ca...'}, {'key': 'hsn', 'title': 'hsncode'}, {'key': 'batch', 'title': 'Batch'},
          {'key': 'expiry', 'title': 'Expiry'}, {'key': 'qty', 'title': 'Qty', 'type': 'numeric'}, {'key': 'packing', 'title': 'packing', 'type': 'numeric'},
          {'key': 'f_qty', 'title': 'F.Qty', 'type': 'numeric'}, {'key': 'p_rate', 'title': 'P.Rate', 'type': 'numeric'},
          {'key': 'gross', 'title': 'Gross', 'type': 'numeric'}, {'key': 'disc', 'title': 'Disc', 'type': 'numeric'},
          {'key': 's_disc', 'title': 'SDisc', 'type': 'numeric'}, {'key': 'net', 'title': 'Net', 'type': 'numeric'},
          {'key': 'cgst', 'title': 'cgst', 'type': 'numeric'}, {'key': 'igst', 'title': 'igst', 'type': 'numeric'},
          {'key': 'sgst', 'title': 'sgst', 'type': 'numeric'}, {'key': 'gst_amt', 'title': 'gst_amt', 'type': 'numeric'},
          {'key': 'total', 'title': 'Total', 'type': 'numeric'}, {'key': 'l_cost', 'title': 'L.Cost', 'type': 'numeric'},
          {'key': 's_rate', 'title': 'S.Rate', 'type': 'numeric'}, {'key': 'mrp', 'title': 'MRP', 'type': 'numeric'}, {'key': 'mrp_total', 'title': 'Mrp Total', 'type': 'numeric'},
        ];
      case PurchaseReportType.supplierWise:
        return [
          {'key': 'supplier', 'title': 'Supplier'}, {'key': 'total', 'title': 'Grand Total', 'type': 'numeric'}, {'key': 'inv_count', 'title': 'Number Of Invoices', 'type': 'numeric'},
        ];
      case PurchaseReportType.categoryWise:
        return [
          {'key': 'name', 'title': 'Product Name'}, {'key': 'strip_qty', 'title': 'Strip Qty', 'type': 'numeric'}, {'key': 'loose_qty', 'title': 'Loose Qty', 'type': 'numeric'},
        ];
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore && _activeFilters.isEmpty) {
        _loadMore();
      }
    }
  }

  void _search() async {
    setState(() {
      _masterData = [];
      _displayData = [];
      _offset = 0;
      _hasMore = true;
      _isLoading = true;
    });

    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final dateFiltered = await provider.fetchPurchasesInDateRange(_from, _to, loadItems: true, limit: _pageSize, offset: 0);

    setState(() {
      _masterData = _processRawData(dateFiltered, provider);
      _displayData = List.from(_masterData);
      _offset = dateFiltered.length;
      _hasMore = dateFiltered.length == _pageSize;
      _isLoading = false;
      _applyFilters();
    });
  }

  void _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);

    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final nextPurchases = await provider.fetchPurchasesInDateRange(_from, _to, loadItems: true, limit: _pageSize, offset: _offset);

    setState(() {
      final processed = _processRawData(nextPurchases, provider);
      _masterData.addAll(processed);
      _displayData = List.from(_masterData);
      _offset += nextPurchases.length;
      _hasMore = nextPurchases.length == _pageSize;
      _isLoading = false;
      _applyFilters();
    });
  }

  void _processData() {
    _search();
  }

  void _exportExcel() async {
    if (_displayData.isEmpty) return;
    String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Save Purchase Report Excel',
      fileName: 'Purchase_Report_${_reportType.name}_${DateFormat('ddMMyyyy').format(_from)}.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (outputFile != null) {
      final excel = ex.Excel.createExcel();
      final sheet = excel['Purchase Report'];
      excel.delete('Sheet1');

      final columns = _getColumns();
      sheet.appendRow(columns.map((c) => ex.TextCellValue(c['title'] ?? '')).toList());

      for (var row in _displayData) {
        sheet.appendRow(columns.map((col) {
          final val = row[col['key']];
          if (val is double) return ex.DoubleCellValue(val);
          if (val is int) return ex.IntCellValue(val);
          return ex.TextCellValue(val?.toString() ?? '');
        }).toList());
      }

      final bytes = excel.encode();
      if (bytes != null) {
        await File(outputFile).writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Purchase Report Exported to Excel!"), backgroundColor: Colors.green),
          );
        }
      }
    }
  }

  bool checkIfDuplicate(PurchaseEntry current, List<PurchaseEntry> allPurchases) {
    return allPurchases.any((other) =>
      other.entryNo != current.entryNo && // ensure it's not comparing against itself
      other.supplierName.trim().toLowerCase() == current.supplierName.trim().toLowerCase() &&
      other.supInvNo.trim().isNotEmpty &&
      other.supInvNo.trim().toLowerCase() == current.supInvNo.trim().toLowerCase() &&
      other.financialYear == current.financialYear
    );
  }

  List<Map<String, dynamic>> _processRawData(List<PurchaseEntry> dateFiltered, PharmacyProvider provider) {
    List<Map<String, dynamic>> reportData = [];
    switch (_reportType) {
      case PurchaseReportType.summary:
        reportData = dateFiltered.map((p) {
          double totalGst = p.items.fold(0.0, (sum, item) => sum + item.gstAmt);
          bool isDup = checkIfDuplicate(p, provider.purchases);
          return {
            'entry_no': cleanEntryNo(p.entryNo), 'date': DateFormat('dd/MM/yyyy').format(p.date),
            'supplier': p.supplierName, 'supplier_acc': p.supplierName, 'inv_no': cleanInvoiceNo(p.supInvNo),
            'po_no': "", 'gross': p.subTotal, 'disc': p.discount, 's_disc': 0.0,
            'net': p.subTotal - p.discount, 'gst': totalGst, 'cgst': totalGst / 2, 'sgst': totalGst / 2,
            'igst': 0.0, 'subtotal': p.subTotal, 'other_disc': 0.0, 'other_charge': p.otherCharge,
            'credit_note': 0.0, 'total': p.grandTotal, 'status': p.paymentStatus == 1 ? "Paid" : "Saved", 'tax_type': "Normal",
            'is_duplicate': isDup,
          };
        }).toList();
        break;

      case PurchaseReportType.detailed:
        for (var p in dateFiltered) {
          bool isDup = checkIfDuplicate(p, provider.purchases);
          for (var item in p.items) {
            final prod = provider.productMaster.firstWhere((element) => element.id == item.id || element.name == item.productName, orElse: () => Product(id: "", name: item.productName));
            reportData.add({
              'entry_no': cleanEntryNo(p.entryNo), 'date': DateFormat('dd/MM/yyyy').format(p.date), 'supplier': p.supplierName,
              'name': item.productName, 'rack': item.rack.isNotEmpty ? item.rack : prod.rack,
              'category': prod.category, 'sub_category': prod.subCategory, 'hsn': item.hsnCode.isNotEmpty ? item.hsnCode : prod.hsnCode,
              'batch': item.batch, 'expiry': item.expiry, 'qty': item.qty, 'packing': item.packin, 'f_qty': item.fQty,
              'p_rate': item.pRate, 'gross': item.gross, 'disc': item.discAmt, 's_disc': item.sDiscAmt, 'net': item.net,
              'cgst': item.gstAmt / 2, 'igst': 0.0, 'sgst': item.gstAmt / 2, 'gst_amt': item.gstAmt, 'total': item.total,
              'l_cost': item.lCost, 's_rate': item.sRate, 'mrp': item.mrp, 'mrp_total': item.mrp * (item.qty + item.fQty),
              'is_duplicate': isDup,
            });
          }
        }
        break;

      case PurchaseReportType.supplierWise:
        Map<String, Map<String, dynamic>> grouped = {};
        for (var p in dateFiltered) {
          if (!grouped.containsKey(p.supplierName)) {
            grouped[p.supplierName] = {'supplier': p.supplierName, 'total': 0.0, 'inv_count': 0};
          }
          grouped[p.supplierName]!['total'] += p.grandTotal;
          grouped[p.supplierName]!['inv_count'] += 1;
        }
        reportData = grouped.values.toList();
        break;

      case PurchaseReportType.categoryWise:
        Map<String, Map<String, dynamic>> catGrouped = {};
        for (var p in dateFiltered) {
          for (var item in p.items) {
            if (!catGrouped.containsKey(item.productName)) {
              catGrouped[item.productName] = {'name': item.productName, 'strip_qty': 0, 'loose_qty': 0};
            }
            catGrouped[item.productName]!['loose_qty'] += item.qty;
            catGrouped[item.productName]!['strip_qty'] += item.qty ~/ (item.packin > 0 ? item.packin : 1);
          }
        }
        reportData = catGrouped.values.toList();
        break;
    }
    return reportData;
  }

  void _applyFilters() {
    setState(() {
      _displayData = _masterData.where((data) {
        bool matches = true;
        _activeFilters.forEach((key, filter) {
          if (!_matchesFilter(data[key], key)) matches = false;
        });
        return matches;
      }).toList();
      _isLoading = false;
    });
  }

  void _applyQuickFilter(String col, String condition, String value) {
    if (condition == 'Clear' || value.isEmpty) {
      _activeFilters.remove(col);
    } else {
      _activeFilters[col] = {
        'condition': condition,
        'value': value,
      };
    }
    _applyFilters();
  }

  void _openAdvancedFilter(String colKey, String title, Offset position) async {
    List<String> uniqueVals = _masterData.map((d) => d[colKey]?.toString() ?? "").toSet().toList();
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
    final columns = _getColumns();
    double totalWidth = 40 + columns.fold<double>(0.0, (a, b) => a + (_colWidths[b['key']] ?? 100));

    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildReportHeader(),
                Expanded(
                  child: Container(
                    color: const Color(0xFFF5F5F5),
                    child: _isLoading 
                      ? const Center(child: CircularProgressIndicator()) 
                      : Scrollbar(
                          controller: _horizontalScrollController,
                          thumbVisibility: true,
                          trackVisibility: true,
                          interactive: true,
                          thickness: 12.0,
                          radius: const Radius.circular(6),
                          notificationPredicate: (notif) => notif.depth == 1,
                          child: SingleChildScrollView(
                            controller: _horizontalScrollController,
                            scrollDirection: Axis.horizontal,
                            child: Container(
                              color: Colors.white,
                              child: SizedBox(
                                width: totalWidth,
                                child: Column(
                                  children: [
                                    Container(
                                        height: _headerHeight,
                                        color: const Color(0xFFF5F5F5),
                                        child: Row(children: [
                                          const SizedBox(width: 40, child: Center(child: Text("SL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)))),
                                          ...columns.map((col) => _hdr(col['title']!, col['key']!, columnType: col['type'] ?? 'text')),
                                        ])),
                                    Expanded(
                                      child: Stack(
                                        children: [
                                          Scrollbar(
                                            controller: _scrollController,
                                            thumbVisibility: true,
                                            trackVisibility: true,
                                            interactive: true,
                                            thickness: 12.0,
                                            radius: const Radius.circular(6),
                                            child: ListView.builder(
                                              controller: _scrollController,
                                              itemExtent: 25.0,
                                              itemCount: _displayData.length + (_hasMore ? 1 : 0),
                                              itemBuilder: (context, i) {
                                                if (i == _displayData.length) {
                                                  return Container(
                                                    height: 25,
                                                    alignment: Alignment.center,
                                                    child: const SizedBox(
                                                      width: 14,
                                                      height: 14,
                                                      child: CircularProgressIndicator(strokeWidth: 2),
                                                    ),
                                                  );
                                                }
                                                final row = _displayData[i];
                                                final bool isDuplicate = row['is_duplicate'] == true;

                                                return InkWell(
                                                  onTap: () {
                                                    if (row.containsKey('entry_no')) {
                                                      Provider.of<AppProvider>(context, listen: false).openPurchase(entryNo: row['entry_no']);
                                                    }
                                                  },
                                                  child: Container(
                                                    height: 25, 
                                                    decoration: BoxDecoration(
                                                      color: isDuplicate ? Colors.red.shade50 : (i % 2 == 0 ? Colors.white : const Color(0xFFF9F9F9)),
                                                      border: const Border(bottom: BorderSide(color: Colors.grey, width: 0.1))
                                                    ),
                                                    child: Row(children: [
                                                      SizedBox(
                                                        width: 40,
                                                        child: Row(
                                                          mainAxisAlignment: MainAxisAlignment.center,
                                                          children: [
                                                            Text("${i + 1}", style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
                                                            if (isDuplicate)
                                                              Padding(
                                                                padding: const EdgeInsets.only(left: 2),
                                                                child: Tooltip(
                                                                  message: "Duplicate entry detected (Same Financial Year, Wholesaler, and Invoice Number)",
                                                                  child: Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 12),
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                      ...columns.map((col) {
                                                        String val = row[col['key']]?.toString() ?? "";
                                                        if (col['type'] == 'numeric') {
                                                          try {
                                                            double d = double.parse(val);
                                                            val = d.toStringAsFixed(2);
                                                          } catch (_) {}
                                                        }
                                                        return _Cell(val, 
                                                          width: _colWidths[col['key']] ?? 100,
                                                          align: col['type'] == 'numeric' ? TextAlign.right : TextAlign.left,
                                                          fontWeight: col['key'] == 'total' ? FontWeight.bold : FontWeight.normal,
                                                        );
                                                      }),
                                                    ]),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                          Positioned(
                                            right: 20,
                                            bottom: 10,
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Tooltip(
                                                  message: "Scroll to Top",
                                                  child: Material(
                                                    elevation: 4,
                                                    shape: const CircleBorder(),
                                                    color: Colors.blue.shade700,
                                                    child: InkWell(
                                                      customBorder: const CircleBorder(),
                                                      onTap: () {
                                                        if (_scrollController.hasClients) {
                                                          _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                                                        }
                                                      },
                                                      child: const Padding(
                                                        padding: EdgeInsets.all(8.0),
                                                        child: Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white, size: 20),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Tooltip(
                                                  message: "Scroll to Bottom",
                                                  child: Material(
                                                    elevation: 4,
                                                    shape: const CircleBorder(),
                                                    color: Colors.blue.shade700,
                                                    child: InkWell(
                                                      customBorder: const CircleBorder(),
                                                      onTap: () {
                                                        if (_scrollController.hasClients) {
                                                          _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                                                        }
                                                      },
                                                      child: const Padding(
                                                        padding: EdgeInsets.all(8.0),
                                                        child: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 20),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                  ),
                ),
                _buildFooter(_displayData),
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
      color: AppColors.of(context).cardBg,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _datePickerSide("From", _from, (d) { setState(() => _from = d); _processData(); })),
              const SizedBox(width: 8),
              Expanded(child: _datePickerSide("To", _to, (d) { setState(() => _to = d); _processData(); })),
            ],
          ),
          const SizedBox(height: 20),
          _reportTypeRadio(PurchaseReportType.detailed, "Detailed"),
          _reportTypeRadio(PurchaseReportType.summary, "Summary"),
          _reportTypeRadio(PurchaseReportType.supplierWise, "Supplier Wise"),
          _reportTypeRadio(PurchaseReportType.categoryWise, "Category Wise"),
          const Spacer(),
          Row(
            children: [
              Expanded(child: _sideActionBtn("Export", Icons.exit_to_app, onPressed: _exportExcel)),
              const SizedBox(width: 8),
              Expanded(child: _sideActionBtn("Print", Icons.print, onPressed: _printReport)),
            ],
          )
        ],
      ),
    );
  }

  Widget _datePickerSide(String label, DateTime date, Function(DateTime) onPick) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        InkWell(
          onTap: () async {
            final picked = await showAppDatePicker(context: context, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime(2100));
            if (picked != null) {
              if (label == "From") {
                if (picked.isAfter(_to)) {
                  setState(() => _to = picked);
                }
              } else {
                if (picked.isBefore(_from)) {
                  setState(() => _from = picked);
                }
              }
              onPick(picked);
            }
          },
          child: Container(
            height: 25,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey), color: Colors.white),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(DateFormat('dd/MM/yyyy').format(date), style: const TextStyle(fontSize: 10)),
                const Icon(Icons.arrow_drop_down, size: 14),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _reportTypeRadio(PurchaseReportType type, String label) {
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          Radio<PurchaseReportType>(
            value: type,
            groupValue: _reportType,
            onChanged: (v) { setState(() => _reportType = v!); _processData(); },
            visualDensity: VisualDensity.compact,
          ),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _sideActionBtn(String label, IconData icon, {required VoidCallback onPressed}) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 10)),
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.zero,
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }

  void _printReport() async {
    if (_displayData.isEmpty) return;
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);
    final columns = _getColumns();
    
    final headers = columns.map((c) => c['title'] ?? "").toList();
    final data = _displayData.map((row) {
      return columns.map((col) {
        final val = row[col['key']];
        if (val == null) return "";
        if (val is double) return val.toStringAsFixed(2);
        return val.toString();
      }).toList();
    }).toList();

    final doc = await ReportPdfGenerator.buildReportPdf(
      title: "Purchase Report (${_reportType.name.toUpperCase()})",
      headers: headers,
      data: data,
      company: pharma.companyProfile,
      subtitle: "From: ${DateFormat('dd/MM/yyyy').format(_from)} To: ${DateFormat('dd/MM/yyyy').format(_to)}",
    );

    if (!mounted) return;
    PrinterService.showProfessionalPreview(
      context: context,
      doc: doc,
      title: "Purchase Report Preview",
    );
  }

  Widget _buildReportHeader() {
    String title = "Purchase Summary";
    if (_reportType == PurchaseReportType.detailed) title = "Detailed Purchase Report";
    if (_reportType == PurchaseReportType.supplierWise) title = "Supplier Wise Purchase Summary";
    if (_reportType == PurchaseReportType.categoryWise) title = "Product Wise Purchase Summary";

    return Container(
      width: double.infinity,
      color: const Color(0xFFD1D9E1),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        "$title From: ${DateFormat('dd/MM/yyyy').format(_from)} To: ${DateFormat('dd/MM/yyyy').format(_to)}",
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF2C3E50)),
      ),
    );
  }

  Widget _hdr(String title, String key, {String columnType = 'text'}) {
     return _Hdr(
       title: title, 
       width: _colWidths[key] ?? 100, 
       columnType: columnType,
       onQuickFilter: (c, v) => _applyQuickFilter(key, c, v),
       onAdvancedTap: (pos) => _openAdvancedFilter(key, title, pos),
       onResize: (v) => setState(() => _colWidths[key] = v.clamp(40, 500)),
       onHeightResize: (v) => setState(() => _headerHeight = v.clamp(40, 150)),
     );
  }

  Widget _buildFooter(List<Map<String, dynamic>> data) {
    double total = data.fold(0.0, (sum, p) => sum + (p['total'] ?? 0.0));
    return Container(
      height: 30, 
      color: Colors.grey.shade300, 
      padding: const EdgeInsets.symmetric(horizontal: 20), 
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end, 
        children: [
          const Text("TOTAL: ", style: TextStyle(fontWeight: FontWeight.bold)), 
          Text("₹${total.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
        ]
      )
    );
  }
}

class _Hdr extends StatefulWidget {
  final String title;
  final double width;
  final String columnType;
  final Function(String condition, String value) onQuickFilter;
  final Function(Offset position)? onAdvancedTap;
  final Function(double) onResize;
  final Function(double) onHeightResize;

  const _Hdr({required this.title, required this.width, this.columnType = 'text', required this.onQuickFilter, this.onAdvancedTap, required this.onResize, required this.onHeightResize});

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
    return MouseRegion(
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
                    Expanded(child: Padding(padding: const EdgeInsets.only(left: 6, top: 4), child: Text(widget.title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade800), overflow: TextOverflow.ellipsis))),
                    Opacity(
                      opacity: showFilter ? 1.0 : 0.0,
                      child: GestureDetector(
                        onTapDown: (details) => widget.onAdvancedTap?.call(details.globalPosition),
                        child: Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.filter_alt_outlined, size: 14, color: Colors.blueGrey.shade600)),
                      ),
                    ),
                  ],
                ),
                Container(
                  height: 20,
                  margin: const EdgeInsets.fromLTRB(2, 2, 2, 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(onTapDown: _showQuickConditionMenu, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4), color: Colors.grey.shade100, child: Text(_getConditionSymbol(), style: const TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.bold)))),
                      Expanded(child: TextField(controller: _quickCtrl, style: const TextStyle(fontSize: 10), decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6), border: InputBorder.none), onChanged: (v) { widget.onQuickFilter(_quickCondition, v); setState(() {}); })),
                    ],
                  ),
                ),
              ],
            ),
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
  }
}

class _Cell extends StatelessWidget {
  final String text; final double width; final Color? color; final FontWeight? fontWeight; final TextAlign align;
  const _Cell(this.text, {required this.width, this.fontWeight, this.align = TextAlign.left}) : color = null;
  @override Widget build(BuildContext context) => ERPTooltip(
    message: text,
    child: Container(
      width: width, 
      padding: const EdgeInsets.symmetric(horizontal: 4), 
      alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.center ? Alignment.center : Alignment.centerRight),
      decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.grey, width: 0.5))), 
      child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: fontWeight), overflow: TextOverflow.ellipsis)
    ),
  );
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
