import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:math' as math;
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
import '../utils/theme_constants.dart';

class PurchaseReturnReportScreen extends StatefulWidget {
  const PurchaseReturnReportScreen({super.key});

  @override
  State<PurchaseReturnReportScreen> createState() => _PurchaseReturnReportScreenState();
}

enum ReportType { detailed, summary, supplierWise, productWise }
enum AggregationType { sum, min, max, count, average, none }
enum ColumnType { text, numeric, date }

class _ColInfo {
  final String key;
  final String label;
  double width;
  final double flex;
  final TextAlign align;
  final ColumnType type;
  _ColInfo(this.key, this.label, {double? width, this.flex = 1, this.align = TextAlign.left, this.type = ColumnType.text})
      : width = width ?? (flex * 70);
}

class _PurchaseReturnReportScreenState extends State<PurchaseReturnReportScreen> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  ReportType _reportType = ReportType.detailed;
  double _headerHeight = 52.0;

  final Map<String, Map<String, dynamic>> _activeFilters = {};
  final Map<String, AggregationType> _columnAggregations = {};

  List<dynamic> _masterData = [];
  List<dynamic> _displayData = [];
  List<_ColInfo>? _cachedCols;

  int _offset = 0;
  final int _pageSize = 50;
  bool _hasMore = true;
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _cachedCols = _getColumns();
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
    final filteredReturns = await provider.fetchPurchaseReturnsInDateRange(_from, _to, loadItems: true, limit: _pageSize, offset: 0);

    setState(() {
      _masterData = _processData(filteredReturns);
      _displayData = List.from(_masterData);
      _offset = filteredReturns.length;
      _hasMore = filteredReturns.length == _pageSize;
      _isLoading = false;
      _applyFilters();
    });
  }

  void _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);

    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final nextReturns = await provider.fetchPurchaseReturnsInDateRange(_from, _to, loadItems: true, limit: _pageSize, offset: _offset);

    setState(() {
      final processed = _processData(nextReturns);
      _masterData.addAll(processed);
      _displayData = List.from(_masterData);
      _offset += nextReturns.length;
      _hasMore = nextReturns.length == _pageSize;
      _isLoading = false;
      _applyFilters();
    });
  }

  void _applyFilters() {
    if (_activeFilters.isEmpty) {
      setState(() => _displayData = List.from(_masterData));
      return;
    }

    setState(() {
      _displayData = _masterData.where((row) {
        bool match = true;
        _activeFilters.forEach((colKey, filter) {
          if (!match) return;
          if (filter['mode'] == 'values') {
            List<String> allowed = List<String>.from(filter['selected_values']);
            String cellVal = row[colKey]?.toString() ?? "";
            if (!allowed.contains(cellVal)) match = false;
            return;
          }
          String condition = filter['condition'];
          if (condition == 'Clear' || condition == 'None') return;
          final val = row[colKey];
          if (filter['type'] == ColumnType.text) {
            String cellStr = val?.toString().toLowerCase() ?? "";
            String filterStr = filter['value1']?.toString().toLowerCase() ?? "";
            if (condition == 'Equals' && cellStr != filterStr) {
              match = false;
            } else if (condition == 'Does Not Equal' && cellStr == filterStr) match = false;
            else if (condition == 'Contains' && !cellStr.contains(filterStr)) match = false;
            else if (condition == 'Does Not Contain' && cellStr.contains(filterStr)) match = false;
            else if (condition == 'Begins With' && !cellStr.startsWith(filterStr)) match = false;
            else if (condition == 'Ends With' && !cellStr.endsWith(filterStr)) match = false;
          } else if (filter['type'] == ColumnType.numeric) {
            double cellNum = double.tryParse(val?.toString() ?? "0") ?? 0.0;
            double v1 = double.tryParse(filter['value1']?.toString() ?? "0") ?? 0.0;
            if (condition == 'Between') {
              double v2 = double.tryParse(filter['value2']?.toString() ?? "0") ?? 0.0;
              if (cellNum < v1 || cellNum > v2) match = false;
            } else {
              if (condition == 'Equals' && cellNum != v1) {
                match = false;
              } else if (condition == 'Does Not Equal' && cellNum == v1) match = false;
              else if (condition == 'Greater Than' && cellNum <= v1) match = false;
              else if (condition == 'Less Than' && cellNum >= v1) match = false;
            }
          }
        });
        return match;
      }).toList();
    });
  }

  List<dynamic> _processData(List<PurchaseReturnEntry> returns) {
    switch (_reportType) {
      case ReportType.detailed:
        List<Map<String, dynamic>> items = [];
        for (var p in returns) {
          for (var item in p.items) {
            items.add({
              'date': DateFormat('dd/MM/yyyy').format(p.date),
              'entry_no': p.entryNo,
              'supplier': p.supplierName,
              'orig_pur': p.originalPurchaseNo,
              'done_by': p.doneBy,
              'product': item.productName,
              'batch': item.batch,
              'qty': item.qty,
              'rate': item.pRate,
              'total': item.total,
              'reason': item.reason,
            });
          }
        }
        return items;
      case ReportType.summary:
        return returns.map((p) => {
          'date': DateFormat('dd/MM/yyyy').format(p.date),
          'entry_no': p.entryNo,
          'supplier': p.supplierName,
          'orig_pur': p.originalPurchaseNo,
          'done_by': p.doneBy,
          'total': p.grandTotal,
        }).toList();
      case ReportType.supplierWise:
        Map<String, Map<String, dynamic>> grouped = {};
        for (var p in returns) {
          grouped.putIfAbsent(p.supplierName, () => {'supplier': p.supplierName, 'total': 0.0, 'count': 0});
          grouped[p.supplierName]!['total'] += p.grandTotal;
          grouped[p.supplierName]!['count'] += 1;
        }
        return grouped.values.toList()..sort((a,b) => b['total'].compareTo(a['total']));
      case ReportType.productWise:
        Map<String, Map<String, dynamic>> prodGrouped = {};
        for (var p in returns) {
          for (var item in p.items) {
            prodGrouped.putIfAbsent(item.productName, () => {'product': item.productName, 'qty': 0, 'total': 0.0});
            prodGrouped[item.productName]!['qty'] += item.qty;
            prodGrouped[item.productName]!['total'] += item.total;
          }
        }
        return prodGrouped.values.toList()..sort((a,b) => b['total'].compareTo(a['total']));
    }
  }

  List<_ColInfo> _getColumns() {
    switch (_reportType) {
      case ReportType.detailed:
        return [
          _ColInfo("date", "Date", flex: 1.1, type: ColumnType.date),
          _ColInfo("entry_no", "Entry No", flex: 1.0),
          _ColInfo("supplier", "Supplier", flex: 1.5),
          _ColInfo("product", "Product", flex: 2.2),
          _ColInfo("batch", "Batch", flex: 1.1),
          _ColInfo("qty", "Qty", flex: 0.8, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("rate", "Rate", flex: 1.1, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("total", "Total", flex: 1.1, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("reason", "Reason", flex: 1.5),
        ];
      case ReportType.summary:
        return [
          _ColInfo("date", "Date", flex: 1.1, type: ColumnType.date),
          _ColInfo("entry_no", "Entry No", flex: 1.0),
          _ColInfo("supplier", "Supplier", flex: 1.5),
          _ColInfo("orig_pur", "Orig Purchase", flex: 1.2),
          _ColInfo("done_by", "Done By", flex: 1.2),
          _ColInfo("total", "Total", flex: 1.1, align: TextAlign.right, type: ColumnType.numeric),
        ];
      case ReportType.supplierWise:
        return [
          _ColInfo("supplier", "Supplier", flex: 2.0),
          _ColInfo("count", "Count", flex: 1.0, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("total", "Total", flex: 1.3, align: TextAlign.right, type: ColumnType.numeric),
        ];
      case ReportType.productWise:
        return [
          _ColInfo("product", "Product", flex: 3.0),
          _ColInfo("qty", "Qty", flex: 1.0, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("total", "Total", flex: 1.3, align: TextAlign.right, type: ColumnType.numeric),
        ];
    }
  }

  void _openAdvancedFilterDialog(_ColInfo col, Offset position) async {
    List<String> uniqueVals = _masterData.map((row) => row[col.key]?.toString() ?? "").toSet().toList();
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
                columnName: col.label,
                columnType: col.type,
                uniqueValues: uniqueVals,
                initialFilter: _activeFilters[col.key],
              ),
            ),
          )
        ],
      ),
    );

    if (result != null) {
      if (result['condition'] == 'Clear') {
        _activeFilters.remove(col.key);
      } else {
        _activeFilters[col.key] = result;
      }
      _applyFilters();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSidebar(c),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildReportHeader(),
                Expanded(child: Container(color: c.background, child: _buildDataGrid())),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(AppThemeColors c) {
    return Container(
      width: 250, color: c.cardBg, padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _datePicker("From", _from, (d) { setState(() => _from = d); _search(); })),
              const SizedBox(width: 8),
              Expanded(child: _datePicker("To", _to, (d) { setState(() => _to = d); _search(); })),
            ],
          ),
          const SizedBox(height: 15),
          _reportTypeRadio(ReportType.detailed, "Detailed"),
          _reportTypeRadio(ReportType.summary, "Summary"),
          _reportTypeRadio(ReportType.supplierWise, "Supplier Wise"),
          _reportTypeRadio(ReportType.productWise, "Product Wise"),
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

  void _exportExcel() async {
    if (_displayData.isEmpty) return;
    String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Save Return Report Excel',
      fileName: 'Return_Report_${_reportType.name}_${DateFormat('ddMMyyyy').format(_from)}.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (outputFile != null) {
      final excel = ex.Excel.createExcel();
      final sheet = excel['Report'];
      excel.delete('Sheet1');

      final columns = _getColumns();
      sheet.appendRow(columns.map((c) => ex.TextCellValue(c.label)).toList());

      for (var row in _displayData) {
        sheet.appendRow(columns.map((col) {
          final val = row[col.key];
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
            const SnackBar(content: Text("Report Exported to Excel!"), backgroundColor: Colors.green),
          );
        }
      }
    }
  }

  Widget _datePicker(String label, DateTime date, Function(DateTime) onPick) {
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
            height: 25, padding: const EdgeInsets.symmetric(horizontal: 4),
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

  Widget _reportTypeRadio(ReportType type, String label) {
    return SizedBox(
      height: 28,
      child: InkWell(
        onTap: () { setState(() => _reportType = type); _search(); },
        child: Row(
          children: [
            Radio<ReportType>(
              value: type, groupValue: _reportType,
              onChanged: (v) { setState(() => _reportType = v!); _search(); },
              visualDensity: VisualDensity.compact,
            ),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  Widget _sideActionBtn(String label, IconData icon, {required VoidCallback onPressed}) {
    return OutlinedButton.icon(
      onPressed: onPressed, icon: Icon(icon, size: 14), label: Text(label, style: const TextStyle(fontSize: 10)),
      style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
    );
  }

  void _printReport() async {
    if (_displayData.isEmpty) return;
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);
    final columns = _getColumns();
    final headers = columns.map((c) => c.label).toList();
    final data = _displayData.map((row) {
      return columns.map((col) {
        final val = row[col.key];
        if (val == null) return "";
        if (val is double) return val.toStringAsFixed(2);
        return val.toString();
      }).toList();
    }).toList();
    final doc = await ReportPdfGenerator.buildReportPdf(
      title: "Purchase Return Report (${_reportType.name.toUpperCase()})",
      headers: headers, data: data, company: pharma.companyProfile,
      subtitle: "From: ${DateFormat('dd/MM/yyyy').format(_from)} To: ${DateFormat('dd/MM/yyyy').format(_to)}",
    );
    if (!mounted) return;
    PrinterService.showProfessionalPreview(context: context, doc: doc, title: "Purchase Return Report Preview");
  }

  Widget _buildReportHeader() {
    return Container(
      width: double.infinity, color: const Color(0xFFD1D9E1), padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        "Purchase Return Report From: ${DateFormat('dd/MM/yyyy').format(_from)} To: ${DateFormat('dd/MM/yyyy').format(_to)}",
        textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF2C3E50)),
      ),
    );
  }

  Widget _buildDataGrid() {
    _cachedCols ??= _getColumns();
    final columns = _cachedCols!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final double totalWidth = columns.fold<double>(0.0, (sum, col) => sum + col.width);
        final double availableWidth = constraints.maxWidth;
        final double scale = availableWidth > totalWidth ? (availableWidth / totalWidth) : 1.0;

        final double effectiveWidth = math.max(totalWidth, availableWidth);
        final List<double> scaledWidths = columns.map((col) => col.width * scale).toList();
        if (scaledWidths.isNotEmpty) {
          final double sumWidths = scaledWidths.fold<double>(0.0, (sum, w) => sum + w);
          final double diff = effectiveWidth - sumWidths;
          scaledWidths[scaledWidths.length - 1] += diff;
        }

        return Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400)),
          child: Scrollbar(
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
              child: SizedBox(
                width: effectiveWidth,
                child: Column(
                  children: [
                    Container(
                      height: _headerHeight,
                      color: const Color(0xFFF5F5F5),
                      child: Row(
                        children: List.generate(
                          columns.length,
                          (idx) => _GridHeaderCell(
                            col: columns[idx],
                            width: scaledWidths[idx],
                            onAdvancedTap: (pos) => _openAdvancedFilterDialog(columns[idx], pos),
                            onResize: (newWidth) => setState(() => columns[idx].width = newWidth.clamp(40, 500)),
                            onHeightResize: (newHeight) => setState(() => _headerHeight = newHeight.clamp(40, 150)),
                            onQuickFilter: (condition, val) {
                              if (condition == 'Clear' || val.isEmpty) {
                                _activeFilters.remove(columns[idx].key);
                              } else {
                                _activeFilters[columns[idx].key] = {'mode': 'rules', 'type': columns[idx].type, 'condition': condition, 'value1': val};
                              }
                              _applyFilters();
                            },
                          ),
                        ),
                      ),
                    ),
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
                              itemBuilder: (ctx, i) {
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
                                return _buildGridRow(_displayData[i], columns, scaledWidths, i);
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
                    ),
                    _buildGridFooter(columns, scaledWidths),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridRow(Map<String, dynamic> row, List<_ColInfo> columns, List<double> scaledWidths, int index) {
    return InkWell(
      onTap: () {
        if (_reportType == ReportType.detailed || _reportType == ReportType.summary) {
           Provider.of<AppProvider>(context, listen: false).openPurchaseReturn(entryNo: row['entry_no']);
        }
      },
      child: Container(
        height: 25,
        color: index % 2 == 0 ? Colors.white : const Color(0xFFF9F9F9),
        child: ClipRect(
          child: Row(
            children: List.generate(columns.length, (colIdx) {
              final col = columns[colIdx];
              final cellWidth = scaledWidths[colIdx];
              final val = row[col.key];
              String text = val is double ? val.toStringAsFixed(2) : (val?.toString() ?? "");
              return ERPTooltip(
                message: text,
                child: Container(
                  width: cellWidth,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200, width: 0.5)),
                  alignment: col.align == TextAlign.left ? Alignment.centerLeft : Alignment.centerRight,
                  child: Text(text, style: const TextStyle(fontSize: 10, color: Colors.black87), overflow: TextOverflow.ellipsis),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildGridFooter(List<_ColInfo> columns, List<double> scaledWidths) {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EAF6),
        border: Border(top: BorderSide(color: Colors.grey.shade400)),
      ),
      child: Row(
        children: List.generate(columns.length, (colIdx) {
          final col = columns[colIdx];
          final cellWidth = scaledWidths[colIdx];
          final agg = _columnAggregations[col.key] ?? AggregationType.none;
          final result = _calculateAggregation(col.key, agg);

          return GestureDetector(
            onSecondaryTapDown: (details) => _showAggregationMenu(details.globalPosition, col.key),
            child: ERPTooltip(
              message: result,
              child: Container(
                width: cellWidth,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade300, width: 0.5))),
                alignment: col.align == TextAlign.left ? Alignment.centerLeft : Alignment.centerRight,
                child: Text(
                  result,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  String _calculateAggregation(String colKey, AggregationType type) {
    if (type == AggregationType.none || _displayData.isEmpty) return "";

    List<double> values = [];
    for (var row in _displayData) {
      final val = row[colKey];
      if (val is num) {
        values.add(val.toDouble());
      } else if (val is String) {
        final parsed = double.tryParse(val);
        if (parsed != null) values.add(parsed);
      }
    }

    if (type == AggregationType.count) return _displayData.length.toString();
    if (values.isEmpty && type != AggregationType.count) return "";

    switch (type) {
      case AggregationType.sum:
        return values.fold(0.0, (sum, v) => sum + v).toStringAsFixed(2);
      case AggregationType.min:
        return values.reduce((a, b) => a < b ? a : b).toStringAsFixed(2);
      case AggregationType.max:
        return values.reduce((a, b) => a > b ? a : b).toStringAsFixed(2);
      case AggregationType.average:
        return (values.fold(0.0, (sum, v) => sum + v) / values.length).toStringAsFixed(2);
      default:
        return "";
    }
  }

  void _showAggregationMenu(Offset position, String colKey) {
    showMenu<AggregationType>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        _buildPopupItem(AggregationType.sum, "Sum", Icons.functions),
        _buildPopupItem(AggregationType.min, "Min", Icons.bar_chart),
        _buildPopupItem(AggregationType.max, "Max", Icons.bar_chart),
        _buildPopupItem(AggregationType.count, "Count", Icons.numbers),
        _buildPopupItem(AggregationType.average, "Average", Icons.abc),
        const PopupMenuDivider(),
        _buildPopupItem(AggregationType.none, "None", Icons.check),
      ],
    ).then((selected) {
      if (selected != null) {
        setState(() => _columnAggregations[colKey] = selected);
      }
    });
  }

  PopupMenuItem<AggregationType> _buildPopupItem(AggregationType type, String label, IconData icon) {
    return PopupMenuItem(
      value: type,
      height: 35,
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.blueGrey),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _GridHeaderCell extends StatefulWidget {
  final _ColInfo col; final double width; final Function(Offset) onAdvancedTap;
  final Function(String condition, String value) onQuickFilter;
  final Function(double) onResize; final Function(double) onHeightResize;
  const _GridHeaderCell({required this.col, required this.width, required this.onAdvancedTap, required this.onQuickFilter, required this.onResize, required this.onHeightResize});
  @override State<_GridHeaderCell> createState() => _GridHeaderCellState();
}

class _GridHeaderCellState extends State<_GridHeaderCell> {
  late String _quickCondition;
  final TextEditingController _quickCtrl = TextEditingController();
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    if (widget.col.type == ColumnType.text) {
      _quickCondition = 'Contains';
    } else {
      _quickCondition = 'Equals';
    }
  }

  @override
  void dispose() { _quickCtrl.dispose(); super.dispose(); }

  String _getConditionSymbol() {
    switch (_quickCondition) {
      case 'Equals': return '=';
      case 'Does Not Equal': return '!=';
      case 'Contains': return 'inc';
      case 'Does Not Contain': return '!inc';
      case 'Begins With': return 'A..';
      case 'Ends With': return '..Z';
      case 'Greater Than': return '>';
      case 'Less Than': return '<';
      default: return '=';
    }
  }

  void _showConditionMenu(TapDownDetails details) async {
    List<String> items = widget.col.type == ColumnType.text 
      ? ['Equals', 'Does Not Equal', 'Contains', 'Does Not Contain', 'Begins With', 'Ends With']
      : ['Equals', 'Does Not Equal', 'Greater Than', 'Less Than', 'Between'];
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(details.globalPosition.dx, details.globalPosition.dy + 10, details.globalPosition.dx, 0),
      items: items.map((e) => PopupMenuItem(value: e, height: 30, child: Text(e, style: const TextStyle(fontSize: 11)))).toList(),
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
        width: widget.width, decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade300, width: 1), bottom: BorderSide(color: Colors.grey.shade400, width: 1))),
        child: Stack(children: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: Padding(padding: const EdgeInsets.only(left: 6, top: 4, bottom: 2), child: Text(widget.col.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade800), overflow: TextOverflow.ellipsis))),
              Opacity(opacity: showFilter ? 1.0 : 0.0, child: GestureDetector(onTapDown: (details) => widget.onAdvancedTap(details.globalPosition), child: Padding(padding: const EdgeInsets.only(right: 4, top: 4, bottom: 2), child: Icon(Icons.filter_alt_outlined, size: 14, color: Colors.blueGrey.shade600)))),
            ]),
            Container(
              height: 20, margin: const EdgeInsets.fromLTRB(2, 0, 2, 4), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300)),
              child: Row(children: [
                GestureDetector(onTapDown: _showConditionMenu, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4), color: Colors.grey.shade100, alignment: Alignment.center, child: Text(_getConditionSymbol(), style: const TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.bold)))),
                Expanded(child: TextField(controller: _quickCtrl, style: const TextStyle(fontSize: 10), decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6), border: InputBorder.none), onChanged: (val) { if (val.isEmpty) {
                  widget.onQuickFilter('Clear', '');
                } else {
                  widget.onQuickFilter(_quickCondition, val);
                } setState(() {}); })),
              ]),
            ),
          ]),
          Positioned(right: 0, top: 0, bottom: 0, child: MouseRegion(cursor: SystemMouseCursors.resizeLeftRight, child: GestureDetector(behavior: HitTestBehavior.opaque, onHorizontalDragUpdate: (details) => widget.onResize(widget.width + details.delta.dx), child: Container(width: 4)))),
        ]),
      ),
    );
  }
}

class _AdvancedFilterPopup extends StatefulWidget {
  final String columnName; final ColumnType columnType; final List<String> uniqueValues; final Map<String, dynamic>? initialFilter;
  const _AdvancedFilterPopup({required this.columnName, required this.columnType, required this.uniqueValues, this.initialFilter});
  @override State<_AdvancedFilterPopup> createState() => _AdvancedFilterPopupState();
}

class _AdvancedFilterPopupState extends State<_AdvancedFilterPopup> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl; String _searchQuery = ""; late List<String> _selectedValues;
  String _ruleCondition = "None"; final TextEditingController _val1Ctrl = TextEditingController(); final TextEditingController _val2Ctrl = TextEditingController();
  @override void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _selectedValues = List.from(widget.uniqueValues);
    if (widget.initialFilter != null) {
      if (widget.initialFilter!['mode'] == 'values') { _tabCtrl.index = 0; _selectedValues = List.from(widget.initialFilter!['selected_values']); }
      else { _tabCtrl.index = 1; _ruleCondition = widget.initialFilter!['condition']; _val1Ctrl.text = widget.initialFilter!['value1'] ?? ""; _val2Ctrl.text = widget.initialFilter!['value2'] ?? ""; }
    } else { _ruleCondition = widget.columnType == ColumnType.text ? 'Contains' : 'Equals'; }
  }
  @override void dispose() { _tabCtrl.dispose(); _val1Ctrl.dispose(); _val2Ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return Container(
      width: 250, height: 320, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400)),
      child: Column(children: [
        Container(height: 30, color: Colors.grey.shade200, child: TabBar(controller: _tabCtrl, labelColor: Colors.black, unselectedLabelColor: Colors.grey, labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), indicatorSize: TabBarIndicatorSize.tab, tabs: const [Tab(text: "Values"), Tab(text: "Data Filters")])),
        Expanded(child: TabBarView(controller: _tabCtrl, children: [_buildValuesTab(), _buildRulesTab()])),
        Container(height: 40, decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade300))), padding: const EdgeInsets.symmetric(horizontal: 8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          TextButton(onPressed: () => Navigator.pop(context, {'condition': 'Clear'}), child: const Text("Clear Filter", style: TextStyle(fontSize: 11, color: Colors.red))),
          ElevatedButton(onPressed: () {
            if (_tabCtrl.index == 0) {
              Navigator.pop(context, {'mode': 'values', 'selected_values': _selectedValues});
            } else {
              Navigator.pop(context, {'mode': 'rules', 'type': widget.columnType, 'condition': _ruleCondition, 'value1': _val1Ctrl.text, 'value2': _val2Ctrl.text});
            }
          }, style: ElevatedButton.styleFrom(minimumSize: const Size(60, 25), padding: const EdgeInsets.symmetric(horizontal: 10)), child: const Text("Apply", style: TextStyle(fontSize: 11)))
        ])),
      ]),
    );
  }

  Widget _buildValuesTab() {
    final filteredList = widget.uniqueValues.where((v) => v.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    bool allSelected = _selectedValues.length == widget.uniqueValues.length;
    return Column(children: [
      Padding(padding: const EdgeInsets.all(8.0), child: SizedBox(height: 25, child: TextField(style: const TextStyle(fontSize: 11), decoration: const InputDecoration(hintText: "Search values...", prefixIcon: Icon(Icons.search, size: 14), border: OutlineInputBorder(), contentPadding: EdgeInsets.zero), onChanged: (v) => setState(() => _searchQuery = v)))),
      InkWell(onTap: () { setState(() { if (allSelected) {
        _selectedValues.clear();
      } else {
        _selectedValues = List.from(widget.uniqueValues);
      } }); }, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Row(children: [Icon(allSelected ? Icons.check_box : Icons.check_box_outline_blank, size: 16, color: Colors.blue), const SizedBox(width: 8), const Text("(Select All)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))]))),
      const Divider(height: 4),
      Expanded(child: ListView.builder(itemCount: filteredList.length, itemBuilder: (ctx, i) {
        final val = filteredList[i]; final isChecked = _selectedValues.contains(val);
        return InkWell(onTap: () { setState(() { if (isChecked) {
          _selectedValues.remove(val);
        } else {
          _selectedValues.add(val);
        } }); }, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Row(children: [Icon(isChecked ? Icons.check_box : Icons.check_box_outline_blank, size: 16, color: Colors.blue), const SizedBox(width: 8), Expanded(child: Text(val.isEmpty ? "(Blanks)" : val, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis))])));
      }))
    ]);
  }

  Widget _buildRulesTab() {
    List<String> conditions = widget.columnType == ColumnType.text ? ['None', 'Equals', 'Does Not Equal', 'Contains', 'Does Not Contain', 'Begins With', 'Ends With'] : ['None', 'Equals', 'Does Not Equal', 'Greater Than', 'Less Than', 'Between'];
    return Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("Show rows where ${widget.columnName}:", style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
      const SizedBox(height: 8),
      SizedBox(height: 28, child: DropdownButtonFormField<String>(initialValue: _ruleCondition, decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8)), style: const TextStyle(fontSize: 11, color: Colors.black), items: conditions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: (v) => setState(() => _ruleCondition = v!))),
      const SizedBox(height: 12),
      if (_ruleCondition != 'None') ...[
        SizedBox(height: 28, child: TextField(controller: _val1Ctrl, style: const TextStyle(fontSize: 11), decoration: InputDecoration(border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(horizontal: 8), hintText: widget.columnType == ColumnType.date ? "dd/mm/yyyy or mm/yy" : "Enter value..."))),
        if (_ruleCondition == 'Between') ...[const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Center(child: Text("AND", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))), SizedBox(height: 28, child: TextField(controller: _val2Ctrl, style: const TextStyle(fontSize: 11), decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8), hintText: "Enter value...")))]
      ]
    ]));
  }
}
