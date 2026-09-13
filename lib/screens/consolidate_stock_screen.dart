import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../providers/pharmacy_provider.dart';
import '../widgets/app_date_picker.dart';
import '../utils/theme_constants.dart';

enum ColumnType { text, numeric, date }
enum AggregationType { sum, min, max, count, average, none }

class _ColInfo {
  final String key;
  final String label;
  double width;
  final double flex;
  final TextAlign align;
  final ColumnType type;

  _ColInfo(
    this.key, 
    this.label, {
    this.width = 100, 
    this.flex = 1, 
    this.align = TextAlign.left, 
    this.type = ColumnType.text
  });
}

class ConsolidateStockScreen extends StatefulWidget {
  const ConsolidateStockScreen({super.key});

  @override
  State<ConsolidateStockScreen> createState() => _ConsolidateStockScreenState();
}

class _ConsolidateStockScreenState extends State<ConsolidateStockScreen> {
  final String _selectedCategory = "ALL";
  bool _hideZeroStock = true;

  DateTime _fromDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _toDate = DateTime.now();
  bool _isLoading = false;
  List<ConsolidatedStockItem> _stockList = [];

  double _headerHeight = 45.0;
  final Map<String, dynamic> _activeFilters = {};
  final Map<String, AggregationType> _columnAggregations = {
    'opening': AggregationType.sum,
    'inward': AggregationType.sum,
    'outward': AggregationType.sum,
    'balance': AggregationType.sum,
    'valuation': AggregationType.sum,
  };

  final ScrollController _horizontalScrollCtrl = ScrollController();

  List<_ColInfo> _getColumns() {
    return [
      _ColInfo("sl", "SL", width: 50, align: TextAlign.center, type: ColumnType.numeric),
      _ColInfo("name", "PRODUCT NAME", width: 220, type: ColumnType.text),
      _ColInfo("rack", "RACK", width: 80, align: TextAlign.center, type: ColumnType.text),
      _ColInfo("category", "CATEGORY", width: 120, type: ColumnType.text),
      _ColInfo("pack", "PACK", width: 70, align: TextAlign.center, type: ColumnType.numeric),
      _ColInfo("opening", "OPENING STOCK", width: 110, align: TextAlign.right, type: ColumnType.numeric),
      _ColInfo("inward", "INWARD (+)", width: 100, align: TextAlign.right, type: ColumnType.numeric),
      _ColInfo("outward", "OUTWARD (-)", width: 100, align: TextAlign.right, type: ColumnType.numeric),
      _ColInfo("balance", "BALANCE STOCK", width: 120, align: TextAlign.right, type: ColumnType.numeric),
      _ColInfo("p_rate", "P.RATE (₹)", width: 90, align: TextAlign.right, type: ColumnType.numeric),
      _ColInfo("mrp", "MRP (₹)", width: 90, align: TextAlign.right, type: ColumnType.numeric),
      _ColInfo("valuation", "STOCK VALUATION", width: 120, align: TextAlign.right, type: ColumnType.numeric),
    ];
  }

  late List<_ColInfo> _columns;

  @override
  void initState() {
    super.initState();
    _columns = _getColumns();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchStockData();
    });
  }

  @override
  void dispose() {
    _horizontalScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchStockData() async {
    setState(() => _isLoading = true);
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    try {
      final items = await provider.getConsolidatedStockForPeriod(_fromDate, _toDate);
      if (mounted) {
        setState(() {
          _stockList = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error fetching stock data: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _exportExcel() async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    String defaultFileName = 'Consolidated_Stock_${DateFormat('ddMMyyyy').format(_fromDate)}_${DateFormat('ddMMyyyy').format(_toDate)}.xlsx';

    String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Save Consolidated Stock Excel',
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (outputFile != null) {
      final bytes = await provider.exportConsolidatedStockToExcelBytes(_stockList, _fromDate, _toDate);

      if (bytes != null) {
        await File(outputFile).writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Consolidated stock exported successfully!"), backgroundColor: Colors.green),
          );
        }
      }
    }
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> data) {
    if (_activeFilters.isEmpty) return data;

    return data.where((row) {
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
  }

  void _openAdvancedFilterDialog(_ColInfo col, Offset tapPosition, List<Map<String, dynamic>> masterData) async {
    final uniqueVals = masterData
        .map((e) => e[col.key]?.toString() ?? "")
        .toSet()
        .toList();
    uniqueVals.sort();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        return Stack(
          children: [
            Positioned(
              left: tapPosition.dx.clamp(10, MediaQuery.of(context).size.width - 260),
              top: tapPosition.dy.clamp(10, MediaQuery.of(context).size.height - 330),
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
            ),
          ],
        );
      },
    );

    if (result != null) {
      setState(() {
        if (result['condition'] == 'Clear') {
          _activeFilters.remove(col.key);
        } else {
          _activeFilters[col.key] = result;
        }
      });
    }
  }

  String _calculateAggregation(String colKey, AggregationType type, List<Map<String, dynamic>> data) {
    if (type == AggregationType.none || data.isEmpty) return "";

    List<double> values = [];
    for (var row in data) {
      final val = row[colKey];
      if (val is num) {
        values.add(val.toDouble());
      } else if (val is String) {
        final parsed = double.tryParse(val);
        if (parsed != null) values.add(parsed);
      }
    }

    if (type == AggregationType.count) return data.length.toString();
    if (values.isEmpty) return "";

    switch (type) {
      case AggregationType.sum:
        double s = values.fold(0.0, (sum, v) => sum + v);
        return s == s.roundToDouble() ? s.toInt().toString() : s.toStringAsFixed(2);
      case AggregationType.min:
        double m = values.reduce((a, b) => a < b ? a : b);
        return m == m.roundToDouble() ? m.toInt().toString() : m.toStringAsFixed(2);
      case AggregationType.max:
        double mx = values.reduce((a, b) => a > b ? a : b);
        return mx == mx.roundToDouble() ? mx.toInt().toString() : mx.toStringAsFixed(2);
      case AggregationType.average:
        double avg = values.fold(0.0, (sum, v) => sum + v) / values.length;
        return avg.toStringAsFixed(2);
      default:
        return "";
    }
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

  Widget _buildGridFooter(List<_ColInfo> columns, List<Map<String, dynamic>> data) {
    List<Widget> cells = [];
    for (int colIdx = 0; colIdx < columns.length; colIdx++) {
      final col = columns[colIdx];
      final cellWidth = col.width;
      final agg = _columnAggregations[col.key] ?? AggregationType.none;
      final result = _calculateAggregation(col.key, agg, data);
      final isLast = colIdx == columns.length - 1;

      cells.add(
        GestureDetector(
          onTapDown: (details) => _showAggregationMenu(details.globalPosition, col.key),
          onSecondaryTapDown: (details) => _showAggregationMenu(details.globalPosition, col.key),
          child: Container(
            width: cellWidth,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: isLast ? Colors.transparent : Colors.grey.shade300, 
                  width: 0.5,
                ),
              ),
            ),
            alignment: col.align == TextAlign.left ? Alignment.centerLeft : (col.align == TextAlign.center ? Alignment.center : Alignment.centerRight),
            child: Text(
              result,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
    }

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EAF6),
        border: Border(top: BorderSide(color: Colors.grey.shade400)),
      ),
      child: Row(
        children: cells,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final toolbarFiltered = _stockList.where((p) {
      if (_selectedCategory != "ALL" && p.category != _selectedCategory) {
        return false;
      }
      if (_hideZeroStock && p.closingStock <= 0) {
        return false;
      }
      return true;
    }).toList();

    final List<Map<String, dynamic>> normalizedMaster = List.generate(toolbarFiltered.length, (i) {
      final item = toolbarFiltered[i];
      final pack = item.packSize > 0 ? item.packSize : 1;
      final double rowValuation = (item.closingStock / pack) * item.purchaseRate;
      final double rowMrpValuation = (item.closingStock / pack) * item.mrp;

      return {
        'sl': i + 1,
        'name': item.productName,
        'rack': item.rack.isNotEmpty ? item.rack : "-",
        'category': item.category,
        'pack': pack,
        'opening': item.openingStock,
        'inward': item.inwardQty,
        'outward': item.outwardQty,
        'balance': item.closingStock,
        'p_rate': item.purchaseRate,
        'mrp': item.mrp,
        'valuation': rowValuation,
        'mrp_valuation': rowMrpValuation,
      };
    });

    final displayData = _applyFilters(normalizedMaster);

    double totalValuation = 0.0;
    double totalMrpValuation = 0.0;
    int totalBalanceUnits = 0;
    int totalOpeningUnits = 0;
    int totalInwardUnits = 0;
    int totalOutwardUnits = 0;

    for (var row in displayData) {
      totalValuation += (row['valuation'] as num?)?.toDouble() ?? 0.0;
      totalMrpValuation += (row['mrp_valuation'] as num?)?.toDouble() ?? 0.0;
      totalBalanceUnits += (row['balance'] as num?)?.toInt() ?? 0;
      totalOpeningUnits += (row['opening'] as num?)?.toInt() ?? 0;
      totalInwardUnits += (row['inward'] as num?)?.toInt() ?? 0;
      totalOutwardUnits += (row['outward'] as num?)?.toInt() ?? 0;
    }

    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      body: Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildGridTable(_columns, normalizedMaster, displayData),
          ),
        ],
      ),
    );
  }

  Widget _buildGridTable(
    List<_ColInfo> columns, 
    List<Map<String, dynamic>> masterData, 
    List<Map<String, dynamic>> displayData
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double totalWidth = columns.fold<double>(0.0, (sum, col) => sum + col.width);
        final double availableWidth = constraints.maxWidth;
        final double effectiveWidth = availableWidth > totalWidth ? availableWidth : totalWidth;

        return Scrollbar(
          controller: _horizontalScrollCtrl,
          child: SingleChildScrollView(
            controller: _horizontalScrollCtrl,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: effectiveWidth,
              child: Column(
                children: [
                  // TABLE HEADER WITH QUICK FILTERS
                  Container(
                    height: _headerHeight,
                    color: const Color(0xFFF5F5F5),
                    child: Row(
                      children: List.generate(
                        columns.length,
                        (idx) => _GridHeaderCell(
                          col: columns[idx],
                          width: columns[idx].width,
                          onAdvancedTap: (pos) => _openAdvancedFilterDialog(columns[idx], pos, masterData),
                          onResize: (newWidth) => setState(() => columns[idx].width = newWidth.clamp(40, 500)),
                          onHeightResize: (newHeight) => setState(() => _headerHeight = newHeight.clamp(40, 150)),
                          onQuickFilter: (condition, val) {
                            setState(() {
                              if (condition == 'Clear' || val.isEmpty) {
                                _activeFilters.remove(columns[idx].key);
                              } else {
                                _activeFilters[columns[idx].key] = {
                                  'mode': 'rules',
                                  'type': columns[idx].type,
                                  'condition': condition,
                                  'value1': val,
                                };
                              }
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                  // DATA BODY
                  Expanded(
                    child: Container(
                      color: Colors.white,
                      child: displayData.isEmpty
                        ? const Center(child: Text("No stock records found.", style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemExtent: 28.0,
                            itemCount: displayData.length,
                            itemBuilder: (ctx, i) {
                              final row = displayData[i];
                              final isEven = i % 2 == 0;
                              final opening = (row['opening'] as num?)?.toInt() ?? 0;
                              final inward = (row['inward'] as num?)?.toInt() ?? 0;
                              final outward = (row['outward'] as num?)?.toInt() ?? 0;
                              final balance = (row['balance'] as num?)?.toInt() ?? 0;
                              final pRate = (row['p_rate'] as num?)?.toDouble() ?? 0.0;
                              final mrp = (row['mrp'] as num?)?.toDouble() ?? 0.0;
                              final valuation = (row['valuation'] as num?)?.toDouble() ?? 0.0;

                              return Container(
                                height: 28,
                                decoration: BoxDecoration(
                                  color: isEven ? Colors.white : const Color(0xFFF8FAFC),
                                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                                ),
                                child: Row(
                                  children: [
                                    _Cell("${row['sl']}", width: columns[0].width, align: TextAlign.center, color: Colors.grey),
                                    _Cell(row['name']?.toString() ?? '', width: columns[1].width, isBold: true),
                                    _Cell(row['rack']?.toString() ?? '-', width: columns[2].width, align: TextAlign.center, color: Colors.blue.shade800),
                                    _Cell(row['category']?.toString() ?? '', width: columns[3].width),
                                    _Cell("${row['pack']}", width: columns[4].width, align: TextAlign.center),
                                    _Cell("$opening", width: columns[5].width, align: TextAlign.right, color: Colors.blueGrey),
                                    _Cell(inward > 0 ? "+$inward" : "-", width: columns[6].width, align: TextAlign.right, color: Colors.green.shade800, isBold: inward > 0),
                                    _Cell(outward > 0 ? "-$outward" : "-", width: columns[7].width, align: TextAlign.right, color: Colors.red.shade800, isBold: outward > 0),
                                    _Cell("$balance", width: columns[8].width, align: TextAlign.right, isBold: true, color: balance > 0 ? Colors.green.shade800 : Colors.red),
                                    _Cell(pRate.toStringAsFixed(2), width: columns[9].width, align: TextAlign.right),
                                    _Cell(mrp.toStringAsFixed(2), width: columns[10].width, align: TextAlign.right),
                                    _Cell(valuation.toStringAsFixed(2), width: columns[11].width, align: TextAlign.right, isBold: true, color: Colors.teal.shade900),
                                  ],
                                ),
                              );
                            },
                          ),
                    ),
                  ),
                  // GRID FOOTER ROW WITH AGGREGATIONS
                  _buildGridFooter(columns, displayData),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildToolbar() {
    final subtitleText = "Period Position: ${DateFormat('dd/MM/yyyy').format(_fromDate)} to ${DateFormat('dd/MM/yyyy').format(_toDate)}";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.inventory_2_rounded, color: Colors.teal.shade800, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("CONSOLIDATE STOCK POSITION", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
              Text(subtitleText, style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
            ],
          ),
          const Spacer(),
          _datePicker("From Date", _fromDate, (d) {
            setState(() => _fromDate = d);
            _fetchStockData();
          }),
          const SizedBox(width: 8),
          _datePicker("To Date", _toDate, (d) {
            setState(() => _toDate = d);
            _fetchStockData();
          }),
          const SizedBox(width: 12),
          Row(
            children: [
              Checkbox(
                value: _hideZeroStock,
                onChanged: (v) => setState(() => _hideZeroStock = v ?? true),
                visualDensity: VisualDensity.compact,
              ),
              const Text("Hide Zero Stock", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            ],
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _exportExcel,
            icon: const Icon(Icons.download, size: 14),
            label: const Text("EXPORT STOCK EXCEL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
        final picked = await showAppDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          onPick(picked);
          _fetchStockData();
        }
      },
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_month, size: 14, color: Colors.teal),
            const SizedBox(width: 6),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold)),
                Text(DateFormat('dd/MM/yyyy').format(date), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildValuationHeader(
    int balanceUnits,
    int openingUnits,
    int inwardUnits,
    int outwardUnits,
    double valuation,
    double mrpValuation,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: Colors.teal.shade50,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text("BALANCE STOCK: $balanceUnits units  ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.teal.shade900)),
              Text("(Opening: $openingUnits | Inward: +$inwardUnits | Outward: -$outwardUnits)", style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w600)),
            ],
          ),
          Text("PURCHASE VALUE: ₹${valuation.toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue.shade900)),
          Text("MRP ASSET VALUE: ₹${mrpValuation.toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.green.shade900)),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String text; 
  final double width; 
  final TextAlign align; 
  final Color? color; 
  final bool isBold;

  const _Cell(this.text, {required this.width, this.align = TextAlign.left, this.color, this.isBold = false});

  @override Widget build(BuildContext context) {
    return Container(
      width: width,
      alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.center ? Alignment.center : Alignment.centerRight),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text, 
        style: TextStyle(fontSize: 11, color: color ?? Colors.black87, fontWeight: isBold ? FontWeight.bold : FontWeight.w500), 
        overflow: TextOverflow.ellipsis
      ),
    );
  }
}

// ============================================================================
// INLINE QUICK FILTER HEADER (The exact component from Sales Report)
// ============================================================================
class _GridHeaderCell extends StatefulWidget {
  final _ColInfo col;
  final double width;
  final Function(Offset) onAdvancedTap;
  final Function(String condition, String value) onQuickFilter;
  final Function(double) onResize;
  final Function(double) onHeightResize;

  const _GridHeaderCell({
    required this.col, 
    required this.width, 
    required this.onAdvancedTap, 
    required this.onQuickFilter, 
    required this.onResize, 
    required this.onHeightResize
  });

  @override
  State<_GridHeaderCell> createState() => _GridHeaderCellState();
}

class _GridHeaderCellState extends State<_GridHeaderCell> {
  late String _quickCondition;
  final TextEditingController _quickCtrl = TextEditingController();
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _setInitialCondition();
  }

  void _setInitialCondition() {
    if (widget.col.type == ColumnType.text) {
      _quickCondition = 'Contains';
    } else if (widget.col.type == ColumnType.numeric) {
      _quickCondition = 'Equals';
    } else {
      _quickCondition = 'Equals';
    }
  }

  @override
  void dispose() {
    _quickCtrl.dispose();
    super.dispose();
  }

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
      case 'Between': return '><';
      case 'Before': return '<';
      case 'After': return '>';
      default: return '=';
    }
  }

  void _showConditionMenu(TapDownDetails details) async {
    List<String> items = [];
    if (widget.col.type == ColumnType.text) {
      items = ['Equals', 'Does Not Equal', 'Contains', 'Does Not Contain', 'Begins With', 'Ends With'];
    } else if (widget.col.type == ColumnType.numeric) {
      items = ['Equals', 'Does Not Equal', 'Greater Than', 'Less Than', 'Between'];
    } else {
      items = ['Equals', 'Before', 'After', 'Between'];
    }

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx, details.globalPosition.dy + 10,
        details.globalPosition.dx, 0,
      ),
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
      child: ClipRect(
        child: Container(
          width: widget.width,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: Colors.grey.shade300, width: 1),
              bottom: BorderSide(color: Colors.grey.shade400, width: 1),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Row 1: Title and Advanced Filter Icon
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6, top: 4, bottom: 2),
                          child: Text(
                            widget.col.label,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ),
                      if (showFilter)
                        GestureDetector(
                          onTapDown: (details) => widget.onAdvancedTap(details.globalPosition),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 4, top: 4, bottom: 2),
                            child: Icon(Icons.filter_alt_outlined, size: 14, color: Colors.blueGrey.shade600),
                          ),
                        ),
                    ],
                  ),
                  // Row 2: Quick Filter Input
                  Container(
                    height: 20,
                    margin: const EdgeInsets.fromLTRB(2, 0, 2, 4),
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300)),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTapDown: _showConditionMenu,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            color: Colors.grey.shade100,
                            alignment: Alignment.center,
                            child: Text(_getConditionSymbol(), style: const TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _quickCtrl,
                            style: const TextStyle(fontSize: 10),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                              border: InputBorder.none,
                              hintText: widget.col.type == ColumnType.date ? "dd/mm/yyyy" : "",
                              hintStyle: const TextStyle(fontSize: 8, color: Colors.grey),
                            ),
                            onChanged: (val) {
                              if (val.isEmpty) {
                                widget.onQuickFilter('Clear', '');
                              } else {
                                widget.onQuickFilter(_quickCondition, val);
                              }
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
                    onHorizontalDragUpdate: (details) => widget.onResize(widget.col.width + details.delta.dx),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ADVANCED POPUP FILTER DIALOG (Values + Rules Tabs)
// ============================================================================
class _AdvancedFilterPopup extends StatefulWidget {
  final String columnName;
  final ColumnType columnType;
  final List<String> uniqueValues;
  final Map<String, dynamic>? initialFilter;

  const _AdvancedFilterPopup({
    required this.columnName,
    required this.columnType,
    required this.uniqueValues,
    this.initialFilter,
  });

  @override
  State<_AdvancedFilterPopup> createState() => _AdvancedFilterPopupState();
}

class _AdvancedFilterPopupState extends State<_AdvancedFilterPopup> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  String _searchQuery = "";
  late List<String> _selectedValues;

  String _ruleCondition = "None";
  final TextEditingController _val1Ctrl = TextEditingController();
  final TextEditingController _val2Ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);

    _selectedValues = List.from(widget.uniqueValues);

    if (widget.initialFilter != null) {
      if (widget.initialFilter!['mode'] == 'values') {
        _tabCtrl.index = 0;
        _selectedValues = List.from(widget.initialFilter!['selected_values']);
      } else {
        _tabCtrl.index = 1;
        _ruleCondition = widget.initialFilter!['condition'];
        _val1Ctrl.text = widget.initialFilter!['value1'] ?? "";
        _val2Ctrl.text = widget.initialFilter!['value2'] ?? "";
      }
    } else {
      _ruleCondition = widget.columnType == ColumnType.text ? 'Contains' : 'Equals';
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _val1Ctrl.dispose();
    _val2Ctrl.dispose();
    super.dispose();
  }

  void _applyValuesFilter() {
    Navigator.pop(context, {
      'mode': 'values',
      'selected_values': _selectedValues,
    });
  }

  void _applyRulesFilter() {
    if (_ruleCondition == 'None' || _ruleCondition == 'Clear') {
      Navigator.pop(context, {'condition': 'Clear'});
      return;
    }
    Navigator.pop(context, {
      'mode': 'rules',
      'type': widget.columnType,
      'condition': _ruleCondition,
      'value1': _val1Ctrl.text,
      'value2': _val2Ctrl.text,
    });
  }

  void _clearFilter() {
    Navigator.pop(context, {'condition': 'Clear'});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      height: 320,
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400)),
      child: Column(
        children: [
          Container(
            height: 30,
            color: Colors.grey.shade200,
            child: TabBar(
              controller: _tabCtrl,
              labelColor: Colors.black,
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              indicatorSize: TabBarIndicatorSize.tab,
              tabs: const [Tab(text: "Values"), Tab(text: "Data Filters")],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildValuesTab(),
                _buildRulesTab(),
              ],
            ),
          ),
          Container(
            height: 40,
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade300))),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(onPressed: _clearFilter, child: const Text("Clear Filter", style: TextStyle(fontSize: 11, color: Colors.red))),
                ElevatedButton(
                  onPressed: () {
                    if (_tabCtrl.index == 0) {
                      _applyValuesFilter();
                    } else {
                      _applyRulesFilter();
                    }
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(60, 25), padding: const EdgeInsets.symmetric(horizontal: 10)),
                  child: const Text("Apply", style: TextStyle(fontSize: 11)),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildValuesTab() {
    final filteredList = widget.uniqueValues.where((v) => v.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    bool allSelected = _selectedValues.length == widget.uniqueValues.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: SizedBox(
            height: 25,
            child: TextField(
              style: const TextStyle(fontSize: 11),
              decoration: const InputDecoration(hintText: "Search values...", prefixIcon: Icon(Icons.search, size: 14), border: OutlineInputBorder(), contentPadding: EdgeInsets.zero),
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
                Icon(allSelected ? Icons.check_box : Icons.check_box_outline_blank, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                const Text("(Select All)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        const Divider(height: 4),
        Expanded(
          child: ListView.builder(
            itemCount: filteredList.length,
            itemBuilder: (ctx, i) {
              final val = filteredList[i];
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Icon(isChecked ? Icons.check_box : Icons.check_box_outline_blank, size: 16, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(child: Text(val.isEmpty ? "(Blanks)" : val, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              );
            },
          ),
        )
      ],
    );
  }

  Widget _buildRulesTab() {
    List<String> conditions = [];
    if (widget.columnType == ColumnType.text) {
      conditions = ['None', 'Equals', 'Does Not Equal', 'Contains', 'Does Not Contain', 'Begins With', 'Ends With'];
    } else if (widget.columnType == ColumnType.numeric) {
      conditions = ['None', 'Equals', 'Does Not Equal', 'Greater Than', 'Less Than', 'Between'];
    } else {
      conditions = ['None', 'Equals', 'Before', 'After', 'Between'];
    }

    if (!conditions.contains(_ruleCondition)) _ruleCondition = conditions.first;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Show rows where ${widget.columnName}:", style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
          const SizedBox(height: 8),
          SizedBox(
            height: 28,
            child: DropdownButtonFormField<String>(
              initialValue: _ruleCondition,
              decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8)),
              style: const TextStyle(fontSize: 11, color: Colors.black),
              items: conditions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => _ruleCondition = v!),
            ),
          ),
          const SizedBox(height: 12),
          if (_ruleCondition != 'None') ...[
            SizedBox(
              height: 28,
              child: TextField(
                controller: _val1Ctrl,
                style: const TextStyle(fontSize: 11),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  hintText: widget.columnType == ColumnType.date ? "dd/mm/yyyy or mm/yy" : "Enter value...",
                ),
              ),
            ),
            if (_ruleCondition == 'Between') ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Center(child: Text("AND", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
              ),
              SizedBox(
                height: 28,
                child: TextField(
                  controller: _val2Ctrl,
                  style: const TextStyle(fontSize: 11),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    hintText: widget.columnType == ColumnType.date ? "dd/mm/yyyy or mm/yy" : "Enter value...",
                  ),
                ),
              ),
            ]
          ]
        ],
      ),
    );
  }
}
