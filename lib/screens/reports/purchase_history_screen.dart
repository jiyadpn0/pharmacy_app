import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/pharmacy_provider.dart';
import '../../providers/app_provider.dart';
import '../../utils/theme_constants.dart';
import '../../utils/app_formatters.dart';

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

class PurchaseHistoryScreen extends StatefulWidget {
  final String productName;
  final bool hideHeader;
  const PurchaseHistoryScreen({super.key, required this.productName, this.hideHeader = false});

  @override
  State<PurchaseHistoryScreen> createState() => _PurchaseHistoryScreenState();
}

class _PurchaseHistoryScreenState extends State<PurchaseHistoryScreen> {
  int _selectedIndex = 0;
  int _lastTapIndex = -1;
  DateTime? _lastTapTime;
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();
  Future<List<Map<String, dynamic>>>? _historyFuture;

  double _headerHeight = 45.0;
  final Map<String, dynamic> _activeFilters = {};
  final Map<String, AggregationType> _columnAggregations = {
    'qty': AggregationType.sum,
  };
  List<Map<String, dynamic>> _normalizedMaster = [];

  List<_ColInfo> _getColumns() {
    return [
      _ColInfo("entry_no", "Entry No", width: 80, type: ColumnType.numeric),
      _ColInfo("type", "Type", width: 90, type: ColumnType.text),
      _ColInfo("date", "Date", width: 90, type: ColumnType.date),
      _ColInfo("batch", "Batch", width: 110, type: ColumnType.text),
      _ColInfo("expiry", "Expiry", width: 80, type: ColumnType.text),
      _ColInfo("qty", "Qty", width: 60, align: TextAlign.right, type: ColumnType.numeric),
      _ColInfo("mrp", "M.R.P", width: 70, align: TextAlign.right, type: ColumnType.numeric),
      _ColInfo("p_rate", "Rate", width: 70, align: TextAlign.right, type: ColumnType.numeric),
      _ColInfo("disc_percent", "Discp", width: 60, align: TextAlign.right, type: ColumnType.numeric),
      _ColInfo("supplier_name", "Supplier", width: 170, type: ColumnType.text),
      _ColInfo("l_cost", "L.Cost", width: 70, align: TextAlign.right, type: ColumnType.numeric),
      _ColInfo("profit_pct", "Profit%(MRP)", width: 90, align: TextAlign.right, type: ColumnType.numeric),
    ];
  }

  late List<_ColInfo> _columns;

  @override
  void initState() {
    super.initState();
    _columns = _getColumns();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadHistory();
  }

  @override
  void didUpdateWidget(PurchaseHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productName != widget.productName) {
      _loadHistory();
    }
  }

  void _loadHistory() {
    final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);
    _historyFuture = pharmacy.getProductPurchaseHistory(widget.productName);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToSelected() {
    if (_scrollCtrl.hasClients) {
      double target = _selectedIndex * 24.0;
      if (target < _scrollCtrl.offset) {
        _scrollCtrl.jumpTo(target);
      } else if (target + 24.0 > _scrollCtrl.offset + 400.0) {
        _scrollCtrl.jumpTo(target - 400.0 + 24.0);
      }
    }
  }

  DateTime? _parseFlexibleDate(String dateStr) {
    if (dateStr.isEmpty) return null;
    try {
      if (dateStr.contains('-')) {
        return DateTime.tryParse(dateStr);
      }
      if (dateStr.contains('/') && dateStr.length == 5) {
        final parts = dateStr.split('/');
        int m = int.parse(parts[0]);
        int y = 2000 + int.parse(parts[1]);
        return DateTime(y, m, 1);
      }
      return DateFormat('dd/MM/yyyy').parse(dateStr);
    } catch (_) {
      return null;
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
        } else if (filter['type'] == ColumnType.date) {
          DateTime? cellDate = (colKey == 'date' && row['raw_date'] != null)
              ? row['raw_date']
              : _parseFlexibleDate(val?.toString() ?? "");

          if (cellDate == null) {
            match = false;
            return;
          }

          DateTime? d1 = _parseFlexibleDate(filter['value1']?.toString() ?? "");
          if (d1 == null) return;

          cellDate = DateTime(cellDate.year, cellDate.month, cellDate.day);
          d1 = DateTime(d1.year, d1.month, d1.day);

          if (condition == 'Between') {
            DateTime? d2 = _parseFlexibleDate(filter['value2']?.toString() ?? "");
            if (d2 == null) return;
            d2 = DateTime(d2.year, d2.month, d2.day);
            if (cellDate.isBefore(d1) || cellDate.isAfter(d2)) match = false;
          } else {
            if (condition == 'Equals' && !cellDate.isAtSameMomentAs(d1)) {
              match = false;
            } else if (condition == 'Before' && !cellDate.isBefore(d1)) match = false;
            else if (condition == 'After' && !cellDate.isAfter(d1)) match = false;
          }
        }
      });
      return match;
    }).toList();
  }

  void _openAdvancedFilterDialog(_ColInfo col, Offset tapPosition) async {
    final uniqueVals = _normalizedMaster
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
        _selectedIndex = 0;
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
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: isLast ? Colors.transparent : Colors.grey.shade300, 
                  width: 0.5,
                ),
              ),
            ),
            alignment: col.align == TextAlign.left ? Alignment.centerLeft : Alignment.centerRight,
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
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);
          final rawData = snapshot.data ?? [];
          _normalizedMaster = rawData.map((h) {
            int totalQ = ((h['qty'] as num?)?.toInt() ?? 0) + ((h['f_qty'] as num?)?.toInt() ?? 0);
            double mrp = (h['mrp'] as num?)?.toDouble() ?? 0.0;
            double pRate = (h['p_rate'] as num?)?.toDouble() ?? 0.0;
            double disc = (h['disc_percent'] as num?)?.toDouble() ?? 0.0;
            double lCost = (h['l_cost'] as num?)?.toDouble() ?? 0.0;
            double profitPct = lCost > 0 ? ((mrp - lCost) / lCost) * 100 : 0.0;

            String dateStr = "";
            DateTime? rawDt;
            try {
              rawDt = DateTime.parse(h['date'].toString());
              dateStr = DateFormat('dd/MM/yyyy').format(rawDt);
            } catch (_) {
              dateStr = h['date']?.toString() ?? "";
            }

            String fy = h['financial_year']?.toString() ?? '';
            if (fy.isEmpty && rawDt != null) {
              fy = pharmacy.getCalculatedFY(rawDt);
            }

            return {
              'entry_no': cleanEntryNo(h['entry_no']?.toString() ?? ''),
              'raw_entry_no': h['entry_no']?.toString() ?? '',
              'type': 'Purchase',
              'date': dateStr,
              'raw_date': rawDt,
              'financial_year': fy,
              'batch': h['batch']?.toString() ?? '',
              'expiry': h['expiry']?.toString() ?? '',
              'qty': totalQ,
              'mrp': mrp,
              'p_rate': pRate,
              'disc_percent': disc,
              'supplier_name': h['supplier_name']?.toString() ?? 'N/A',
              'l_cost': lCost,
              'profit_pct': profitPct,
            };
          }).toList();

          final displayData = _applyFilters(_normalizedMaster);

          return Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final double totalWidth = _columns.fold<double>(0.0, (sum, col) => sum + col.width);
                    final double availableWidth = constraints.maxWidth;
                    final double effectiveWidth = availableWidth > totalWidth ? availableWidth : totalWidth;

                    return Scrollbar(
                      controller: _scrollCtrl,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: effectiveWidth,
                          child: Column(
                            children: [
                              // TABLE HEADER WITH EXACT QUICK FILTERS FROM SALES REPORT
                              Container(
                                height: _headerHeight,
                                color: const Color(0xFFF5F5F5),
                                child: Row(
                                  children: List.generate(
                                    _columns.length,
                                    (idx) => _GridHeaderCell(
                                      col: _columns[idx],
                                      width: _columns[idx].width,
                                      onAdvancedTap: (pos) => _openAdvancedFilterDialog(_columns[idx], pos),
                                      onResize: (newWidth) => setState(() => _columns[idx].width = newWidth.clamp(40, 500)),
                                      onHeightResize: (newHeight) => setState(() => _headerHeight = newHeight.clamp(40, 150)),
                                      onQuickFilter: (condition, val) {
                                        setState(() {
                                          if (condition == 'Clear' || val.isEmpty) {
                                            _activeFilters.remove(_columns[idx].key);
                                          } else {
                                            _activeFilters[_columns[idx].key] = {
                                              'mode': 'rules',
                                              'type': _columns[idx].type,
                                              'condition': condition,
                                              'value1': val,
                                            };
                                          }
                                          _selectedIndex = 0;
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
                                    ? const Center(child: Text("No matching records found.", style: TextStyle(color: Colors.grey)))
                                    : Focus(
                                        focusNode: _focusNode,
                                        onKeyEvent: (node, event) {
                                          if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
                                          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                            if (_selectedIndex < displayData.length - 1) {
                                              setState(() => _selectedIndex++);
                                              _scrollToSelected();
                                            }
                                            return KeyEventResult.handled;
                                          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                            if (_selectedIndex > 0) {
                                              setState(() => _selectedIndex--);
                                              _scrollToSelected();
                                            }
                                            return KeyEventResult.handled;
                                          } else if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                                            if (_selectedIndex >= 0 && _selectedIndex < displayData.length) {
                                              _tryOpenEntry(displayData[_selectedIndex]);
                                            }
                                            return KeyEventResult.handled;
                                          }
                                          return KeyEventResult.ignored;
                                        },
                                        child: ListView.builder(
                                          controller: _scrollCtrl,
                                          itemCount: displayData.length,
                                          itemBuilder: (context, index) {
                                            final h = displayData[index];
                                            final isEven = index % 2 == 0;
                                            final isSelected = index == _selectedIndex;

                                            int totalQ = (h['qty'] as num?)?.toInt() ?? 0;
                                            double mrp = (h['mrp'] as num?)?.toDouble() ?? 0.0;
                                            double pRate = (h['p_rate'] as num?)?.toDouble() ?? 0.0;
                                            double disc = (h['disc_percent'] as num?)?.toDouble() ?? 0.0;
                                            double lCost = (h['l_cost'] as num?)?.toDouble() ?? 0.0;
                                            double profitPct = (h['profit_pct'] as num?)?.toDouble() ?? 0.0;

                                            return GestureDetector(
                                              onTap: () {
                                                final now = DateTime.now();
                                                if (_lastTapIndex == index && _lastTapTime != null && now.difference(_lastTapTime!) < const Duration(milliseconds: 350)) {
                                                  _lastTapTime = null;
                                                  _lastTapIndex = -1;
                                                  _tryOpenEntry(displayData[index]);
                                                } else {
                                                  _lastTapIndex = index;
                                                  _lastTapTime = now;
                                                  setState(() => _selectedIndex = index);
                                                }
                                              },
                                              child: Container(
                                                height: 24,
                                                decoration: BoxDecoration(
                                                  color: isSelected ? Colors.blue.shade100 : (isEven ? Colors.white : const Color(0xFFF4F6F9)),
                                                  border: Border(bottom: BorderSide(color: isSelected ? Colors.blue : Colors.grey.shade200))
                                                ),
                                                child: Row(
                                                  children: [
                                                    _histCell(h['entry_no']?.toString() ?? '', _columns[0].width),
                                                    _histCell(h['type']?.toString() ?? 'Purchase', _columns[1].width),
                                                    _histCell(h['date']?.toString() ?? '', _columns[2].width),
                                                    _histCell(h['batch']?.toString() ?? '', _columns[3].width),
                                                    _histCell(h['expiry']?.toString() ?? '', _columns[4].width),
                                                    _histCell(totalQ.toString(), _columns[5].width, align: TextAlign.right),
                                                    _histCell(mrp.toStringAsFixed(2), _columns[6].width, align: TextAlign.right),
                                                    _histCell(pRate.toStringAsFixed(2), _columns[7].width, align: TextAlign.right),
                                                    _histCell(disc.toStringAsFixed(0), _columns[8].width, align: TextAlign.right),
                                                    _histCell(h['supplier_name']?.toString() ?? 'N/A', _columns[9].width),
                                                    _histCell(lCost.toStringAsFixed(2), _columns[10].width, align: TextAlign.right, color: Colors.blue.shade900),
                                                    _histCell(profitPct.toStringAsFixed(2), _columns[11].width, align: TextAlign.right, isLast: true),
                                                  ]
                                                )
                                              ),
                                            );
                                          }
                                        ),
                                      ),
                                ),
                              ),
                              // TABLE GRID FOOTER WITH AGGREGATION OPTIONS (Photo 2 style)
                              _buildGridFooter(_columns, displayData),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _tryOpenEntry(Map<String, dynamic> rowData) {
    final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);
    final activeFY = pharmacy.selectedFinancialYear;
    
    String entryFY = rowData['financial_year']?.toString() ?? '';
    if (entryFY.isEmpty) {
      DateTime? dt = rowData['raw_date'] as DateTime?;
      if (dt != null) {
        entryFY = pharmacy.getCalculatedFY(dt);
      }
    }

    final entryNo = rowData['raw_entry_no']?.toString() ?? rowData['entry_no']?.toString() ?? '';
    if (entryNo.isEmpty) return;

    if (entryFY.isNotEmpty && activeFY.isNotEmpty && entryFY != activeFY) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
              SizedBox(width: 8),
              Text("Another Financial Year", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            "This purchase entry ($entryNo) belongs to Financial Year: $entryFY.\n"
            "Your current active session is set to: $activeFY.\n\n"
            "You cannot open an entry from another financial year.",
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text("OK"),
            ),
          ],
        ),
      );
      return;
    }

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      appProvider.openPurchase(entryNo: entryNo);
    } catch (e) {
      debugPrint("Error opening purchase entry: $e");
    }
  }

  Widget _histCell(String val, double width, {TextAlign align = TextAlign.left, Color color = Colors.black87, bool isLast = false}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: align == TextAlign.right ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(border: Border(right: BorderSide(color: isLast ? Colors.transparent : Colors.grey.shade200))),
      child: Text(val, style: TextStyle(fontSize: 11, color: color), overflow: TextOverflow.ellipsis)
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
