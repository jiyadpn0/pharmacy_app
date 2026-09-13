import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/pharmacy_provider.dart';
import '../../providers/app_provider.dart';
import '../../widgets/app_date_picker.dart';
import '../../utils/report_pdf_generator.dart';
import '../../utils/printer_service.dart';
import '../../utils/app_formatters.dart';

class StockLedgerScreen extends StatefulWidget {
  const StockLedgerScreen({super.key});

  @override
  State<StockLedgerScreen> createState() => _StockLedgerScreenState();
}

class _StockLedgerScreenState extends State<StockLedgerScreen> {
  DateTime _fromDate = DateTime(DateTime.now().year, DateTime.now().month - 5, 1);
  DateTime _toDate = DateTime.now();

  final List<Product> _selectedProducts = []; // Multi-product comparison list

  bool _isGraphView = true; // Default view: Stock Movement Chart
  bool _isPercentMode = false; // Toggle: Unit Qty vs % Movement Index
  String _selectedInterval = 'Monthly'; // Daily, Weekly, Monthly, Quarterly

  List<Map<String, dynamic>> _ledgerEntries = [];
  Map<String, dynamic>? _multiGraphData;

  int _openingBalance = 0;
  int _closingBalance = 0;
  bool _isLoading = false;

  final List<String> _intervals = ['Daily', 'Weekly', 'Monthly', 'Quarterly'];

  final List<Color> _productColors = [
    const Color(0xFF1D4ED8), // Royal Blue
    const Color(0xFFD97706), // Warm Amber
    const Color(0xFF059669), // Emerald Green
    const Color(0xFF7C3AED), // Deep Purple
    const Color(0xFFE11D48), // Rose Red
    const Color(0xFF0891B2), // Cyan
    const Color(0xFFEA580C), // Vivid Orange
    const Color(0xFF4F46E5), // Indigo
  ];

  Future<void> _fetchData() async {
    if (_selectedProducts.isEmpty) return;

    setState(() => _isLoading = true);
    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    try {
      final primary = _selectedProducts.first;

      final ledgerFuture = provider.generateStockLedger(
        primary.name,
        _fromDate,
        _toDate,
      );

      final multiGraphFuture = provider.generateMultiProductMovementGraphData(
        productNames: _selectedProducts.map((p) => p.name).toList(),
        fromDate: _fromDate,
        toDate: _toDate,
        interval: _selectedInterval,
      );

      final results = await Future.wait([ledgerFuture, multiGraphFuture]);

      if (mounted) {
        final [data, gData] = results;

        setState(() {
          _openingBalance = data['opening'] ?? 0;
          _closingBalance = data['closing'] ?? 0;
          _ledgerEntries = List<Map<String, dynamic>>.from(data['entries'] ?? []);
          _multiGraphData = gData;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addProductToComparison(Product p) {
    if (!_selectedProducts.any((item) => item.id == p.id || item.name.toLowerCase() == p.name.toLowerCase())) {
      setState(() {
        _selectedProducts.add(p);
      });
      _fetchData();
    }
  }

  void _removeProductFromComparison(int index) {
    setState(() {
      _selectedProducts.removeAt(index);
      if (_selectedProducts.isEmpty) {
        _ledgerEntries = [];
        _multiGraphData = null;
        _openingBalance = 0;
        _closingBalance = 0;
      }
    });
    if (_selectedProducts.isNotEmpty) {
      _fetchData();
    }
  }

  void _openMovementScreenerDialog(String sortField) {
    showDialog(
      context: context,
      builder: (ctx) => _MovementScreenerDialog(
        fromDate: _fromDate,
        toDate: _toDate,
        initialSortField: sortField,
        onSelectProduct: (pName) {
          final p = Product(id: pName, name: pName);
          _addProductToComparison(p);
        },
      ),
    );
  }

  void _printLedger() async {
    if (_ledgerEntries.isEmpty || _selectedProducts.isEmpty) return;
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);
    final primary = _selectedProducts.first;

    final headers = ["Date", "Type", "Ref / Bill No", "Batch", "In Qty", "Out Qty", "Balance"];
    final data = _ledgerEntries.map((r) => [
      r['date'].toString(),
      r['type'].toString(),
      r['ref_no'].toString(),
      r['batch'].toString(),
      r['in_qty'] > 0 ? r['in_qty'].toString() : "-",
      r['out_qty'] > 0 ? r['out_qty'].toString() : "-",
      r['balance'].toString(),
    ]).toList();

    final doc = await ReportPdfGenerator.buildReportPdf(
      title: "Stock Movement Ledger: ${primary.name}",
      headers: headers,
      data: data,
      company: pharma.companyProfile,
      subtitle: "Period: ${DateFormat('dd/MM/yyyy').format(_fromDate)} to ${DateFormat('dd/MM/yyyy').format(_toDate)} | Opening: $_openingBalance | Closing: $_closingBalance",
    );

    if (!mounted) return;
    PrinterService.showProfessionalPreview(context: context, doc: doc, title: "Stock Ledger Preview");
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PharmacyProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          _buildToolbar(),
          _buildFilterHeader(provider),
          if (_selectedProducts.isNotEmpty) _buildProductChipsBar(),
          if (_selectedProducts.isNotEmpty && _isGraphView) _buildKpiCards(),
          if (!_isGraphView) _buildBalanceSummary(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : (_selectedProducts.isEmpty
                    ? _buildRecentStockChangesView(provider)
                    : (_isGraphView ? _buildMultiGraphView() : _buildLedgerGrid())),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.show_chart_rounded, color: Colors.blue.shade800, size: 22),
          ),
          const SizedBox(width: 14),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("STOCK MOVEMENT ANALYTICS & LEDGER", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
              Text("Multi-Item Movement Comparison, % Growth Indexing & Movement Screener", style: TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
            ],
          ),
          const Spacer(),

          // Unit Qty vs % Movement Mode Toggle
          if (_isGraphView) ...[
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
              child: Row(
                children: [
                  _modeToggleButton(
                    label: "UNIT QTY",
                    isActive: !_isPercentMode,
                    onTap: () => setState(() => _isPercentMode = false),
                  ),
                  _modeToggleButton(
                    label: "% MOVEMENT",
                    isActive: _isPercentMode,
                    onTap: () => setState(() => _isPercentMode = true),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Movement Screener Open Button
            ElevatedButton.icon(
              onPressed: () => _openMovementScreenerDialog('qty'),
              icon: const Icon(Icons.analytics_rounded, size: 16),
              label: const Text("MOVEMENT SCREENER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(width: 12),
          ],

          // View Switcher Segmented Control
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                _viewToggleButton(
                  icon: Icons.show_chart_rounded,
                  label: "GRAPH ANALYTICS",
                  isActive: _isGraphView,
                  onTap: () => setState(() => _isGraphView = true),
                ),
                _viewToggleButton(
                  icon: Icons.table_chart_rounded,
                  label: "AUDIT LEDGER",
                  isActive: !_isGraphView,
                  onTap: () => setState(() => _isGraphView = false),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: _printLedger,
            icon: const Icon(Icons.print_rounded, size: 16),
            label: const Text("PRINT LEDGER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeToggleButton({required String label, required bool isActive, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? Colors.indigo.shade800 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: isActive ? Colors.white : const Color(0xFF475569)),
        ),
      ),
    );
  }

  Widget _viewToggleButton({required IconData icon, required String label, required bool isActive, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue.shade800 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isActive ? Colors.white : const Color(0xFF64748B)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: isActive ? Colors.white : const Color(0xFF64748B))),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterHeader(PharmacyProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: Colors.white,
      child: Row(
        children: [
          // Search & Add Medicines Input
          Expanded(
            flex: 6,
            child: Autocomplete<Product>(
              displayStringForOption: (p) => p.name,
              optionsBuilder: (textEditingValue) {
                if (textEditingValue.text.isEmpty) return const Iterable<Product>.empty();
                return provider.searchProducts(textEditingValue.text, includeGenerics: false).take(20);
              },
              onSelected: (p) {
                _addProductToComparison(p);
              },
              optionsViewBuilder: (context, onSelectedOption, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 6,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 450,
                      constraints: const BoxConstraints(maxHeight: 280),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (BuildContext context, int index) {
                          final Product option = options.elementAt(index);
                          return ListTile(
                            dense: true,
                            horizontalTitleGap: 8,
                            leading: const Icon(Icons.medication_rounded, size: 18, color: Colors.blue),
                            title: Text(
                              option.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                            ),
                            onTap: () {
                              onSelectedOption(option);
                            },
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
              fieldViewBuilder: (ctx, ctrl, focus, onSubmitted) {
                void handleAddProduct() {
                  final text = ctrl.text.trim();
                  if (text.isEmpty) return;
                  final matches = provider.searchProducts(text, includeGenerics: false);
                  if (matches.isNotEmpty) {
                    _addProductToComparison(matches.first);
                    ctrl.clear();
                    focus.unfocus();
                  }
                }

                return TextField(
                  controller: ctrl,
                  focusNode: focus,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  onSubmitted: (_) {
                    onSubmitted();
                    handleAddProduct();
                  },
                  decoration: InputDecoration(
                    hintText: "Type & select medicine to add to chart comparison...",
                    prefixIcon: const Icon(Icons.add_chart_rounded, size: 18, color: Colors.blue),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search_rounded, color: Colors.blue),
                      tooltip: "Search & Add Product",
                      onPressed: () {
                        onSubmitted();
                        handleAddProduct();
                      },
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 12),

          // Interval Control (Daily, Weekly, Monthly, Quarterly)
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedInterval,
                icon: const Icon(Icons.arrow_drop_down, size: 20, color: Colors.blueGrey),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedInterval = val);
                    _fetchData();
                  }
                },
                items: _intervals.map((i) => DropdownMenuItem(value: i, child: Text("$i Interval"))).toList(),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Date Pickers
          _datePicker("From", _fromDate, (d) { setState(() => _fromDate = d); _fetchData(); }),
          const SizedBox(width: 8),
          _datePicker("To", _toDate, (d) { setState(() => _toDate = d); _fetchData(); }),
        ],
      ),
    );
  }

  Widget _buildProductChipsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          const Text("ACTIVE CHART ITEMS:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.blueGrey)),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: List.generate(_selectedProducts.length, (index) {
                final prod = _selectedProducts[index];
                final color = _productColors[index % _productColors.length];
                final isPrimary = index == 0;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    border: Border.all(color: color, width: 1.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(
                        prod.name,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
                      ),
                      if (isPrimary) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                          child: const Text("MAIN", style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ],
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => _removeProductFromComparison(index),
                        child: Icon(Icons.cancel, size: 14, color: color),
                      ),
                    ],
                  ),
                );
              }),
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
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300)),
        child: Row(
          children: [
            const Icon(Icons.calendar_month, size: 14, color: Colors.blueGrey),
            const SizedBox(width: 6),
            Text(DateFormat('dd/MM/yy').format(date), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCards() {
    if (_multiGraphData == null) return const SizedBox.shrink();
    final summaries = _multiGraphData!['summaries'] as Map<String, dynamic>?;

    if (summaries == null || summaries.isEmpty) return const SizedBox.shrink();

    final mainProduct = _selectedProducts.first;
    final mainSum = summaries[mainProduct.name] as Map<String, dynamic>? ?? {};

    int primaryQty = ((mainSum['totalQty'] as num?) ?? 0).toInt();
    int primaryBills = ((mainSum['totalBills'] as num?) ?? 0).toInt();
    int peakQty = ((mainSum['peakQty'] as num?) ?? 0).toInt();
    String peakLabel = (mainSum['peakLabel'] ?? 'N/A').toString();

    String compareTitle = "MOVEMENT SCREENER";
    String compareValue = "${summaries.length} Items";
    String compareSub = "Click to inspect all products list 📊";

    if (_selectedProducts.length > 1) {
      final compProduct = _selectedProducts[1];
      final compSum = summaries[compProduct.name] as Map<String, dynamic>? ?? {};
      compareTitle = "COMPARE VOLUME";
      compareValue = "${compSum['totalQty'] ?? 0} units";
      compareSub = "Product: ${compProduct.name}";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: const Color(0xFFF1F5F9),
      child: Row(
        children: [
          Expanded(
            child: _clickableKpiCard(
              title: "PRIMARY VOLUME",
              mainValue: "$primaryQty units",
              subText: "Peak: $peakQty ($peakLabel)",
              color: Colors.blue.shade900,
              icon: Icons.inventory_2_rounded,
              onTap: () => _openMovementScreenerDialog('qty'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _clickableKpiCard(
              title: "SALES BILLS",
              mainValue: "$primaryBills Invoices",
              subText: "Click to rank by transaction frequency 🧾",
              color: Colors.teal.shade800,
              icon: Icons.receipt_long_rounded,
              onTap: () => _openMovementScreenerDialog('bills'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _clickableKpiCard(
              title: "DEMAND TREND",
              mainValue: "${((mainSum['growthTrend'] as num?) ?? 0.0).toStringAsFixed(1)}%",
              subText: "Click to view top gainers / losers 📈",
              color: Colors.indigo.shade800,
              icon: Icons.trending_up_rounded,
              onTap: () => _openMovementScreenerDialog('growth'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _clickableKpiCard(
              title: compareTitle,
              mainValue: compareValue,
              subText: compareSub,
              color: Colors.amber.shade900,
              icon: Icons.compare_arrows_rounded,
              onTap: () => _openMovementScreenerDialog('qty'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _clickableKpiCard({
    required String title,
    required String mainValue,
    required String subText,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      mouseCursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                      const Spacer(),
                      const Icon(Icons.open_in_new_rounded, size: 12, color: Colors.blueGrey),
                    ],
                  ),
                  Text(mainValue, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color)),
                  Text(subText, style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMultiGraphView() {
    if (_multiGraphData == null) return const SizedBox.shrink();
    final buckets = List<Map<String, dynamic>>.from(_multiGraphData!['buckets'] ?? []);
    final activeNames = List<String>.from(_multiGraphData!['productNames'] ?? []);
    final summaries = _multiGraphData!['summaries'] as Map<String, dynamic>? ?? {};

    if (buckets.isEmpty || activeNames.isEmpty) {
      return const Center(child: Text("No stock movement recorded in the selected date range.", style: TextStyle(color: Colors.grey)));
    }

    double maxVal = 10.0;
    double minVal = 0.0;

    if (_isPercentMode) {
      minVal = -100.0;
      maxVal = 100.0;

      for (var b in buckets) {
        final qMap = b['qty'] as Map<String, dynamic>;
        for (var pName in activeNames) {
          int q = ((qMap[pName] as num?) ?? 0).toInt();
          int baseQ = ((summaries[pName]?['firstNonZeroQty'] as num?) ?? 1).toInt();
          if (baseQ <= 0) baseQ = 1;

          double pct = ((q - baseQ) / baseQ) * 100.0;
          if (pct > maxVal) maxVal = pct;
          if (pct < minVal) minVal = pct;
        }
      }
      maxVal = (maxVal * 1.2).clamp(100.0, 10000.0);
      minVal = (minVal * 1.2).clamp(-100.0, 0.0);
    } else {
      for (var b in buckets) {
        final qMap = b['qty'] as Map<String, dynamic>;
        for (var pName in activeNames) {
          double q = ((qMap[pName] as num?) ?? 0).toDouble();
          if (q > maxVal) maxVal = q;
        }
      }
      maxVal = (maxVal * 1.25).clamp(10.0, 100000.0);
    }

    List<LineChartBarData> lineBarsData = [];

    for (int pIdx = 0; pIdx < activeNames.length; pIdx++) {
      final pName = activeNames[pIdx];
      final color = _productColors[pIdx % _productColors.length];
      final baseQ = ((summaries[pName]?['firstNonZeroQty'] as num?) ?? 1).toInt();

      List<FlSpot> spots = [];

      for (int i = 0; i < buckets.length; i++) {
        final b = buckets[i];
        final qMap = b['qty'] as Map<String, dynamic>;
        int q = ((qMap[pName] as num?) ?? 0).toInt();

        double yVal;
        if (_isPercentMode) {
          int bQ = baseQ <= 0 ? 1 : baseQ;
          yVal = ((q - bQ) / bQ) * 100.0;
        } else {
          yVal = q.toDouble();
        }

        spots.add(FlSpot(i.toDouble(), yVal));
      }

      lineBarsData.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: color,
          barWidth: 3.2,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) {
              String label;
              if (_isPercentMode) {
                label = "${spot.y >= 0 ? '+' : ''}${spot.y.toStringAsFixed(0)}%";
              } else {
                label = spot.y.toInt().toString();
              }
              return _DataLabelDotPainter(
                color: color,
                text: label,
              );
            },
          ),
          belowBarData: BarAreaData(
            show: pIdx == 0,
            color: color.withValues(alpha: 0.10),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _isPercentMode
                    ? "RELATIVE % MOVEMENT / GROWTH INDEX"
                    : "MULTI-ITEM STOCK MOVEMENT COMPARISON",
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF1E293B)),
              ),
              const Spacer(),
              Wrap(
                spacing: 12,
                children: List.generate(activeNames.length, (i) {
                  final color = _productColors[i % _productColors.length];
                  return _legendItem(activeNames[i], color);
                }),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: ((maxVal - minVal) / 5).clamp(1.0, 10000.0),
                  getDrawingHorizontalLine: (val) => FlLine(color: val == 0 ? Colors.blueGrey.shade300 : Colors.grey.shade200, strokeWidth: val == 0 ? 1.5 : 1),
                  getDrawingVerticalLine: (val) => FlLine(color: Colors.grey.shade100, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: (buckets.length / 8).ceilToDouble().clamp(1.0, 100.0),
                      getTitlesWidget: (val, meta) {
                        int idx = val.toInt();
                        if (idx >= 0 && idx < buckets.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              buckets[idx]['label'].toString(),
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 55,
                      getTitlesWidget: (val, meta) {
                        if (_isPercentMode) {
                          String prefix = val > 0 ? "+" : "";
                          return Text(
                            "$prefix${val.toInt()}%",
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: val >= 0 ? Colors.blueGrey : Colors.red),
                          );
                        } else {
                          return Text(
                            val.toInt().toString(),
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                          );
                        }
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade200)),
                minX: 0,
                maxX: (buckets.length - 1).toDouble().clamp(0.0, 1000.0),
                minY: minVal,
                maxY: maxVal,
                lineTouchData: LineTouchData(
                  enabled: true,
                  handleBuiltInTouches: true,
                  getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
                    return spotIndexes.map((index) {
                      return TouchedSpotIndicatorData(
                        FlLine(
                          color: barData.color ?? Colors.blue.shade700,
                          strokeWidth: 2,
                          dashArray: [4, 4], // Crosshair vertical line
                        ),
                        FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, bar, idx) => FlDotCirclePainter(
                            radius: 7,
                            color: Colors.white,
                            strokeWidth: 3,
                            strokeColor: bar.color ?? Colors.blue.shade800,
                          ),
                        ),
                      );
                    }).toList();
                  },
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (spot) => const Color(0xFF0F172A),
                    tooltipPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    tooltipMargin: 12,
                    tooltipRoundedRadius: 8,
                    tooltipBorder: BorderSide(color: Colors.blue.shade400, width: 1.5),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        int idx = spot.x.toInt();
                        if (idx >= 0 && idx < buckets.length) {
                          final b = buckets[idx];
                          final label = b['label'].toString();
                          int barIdx = spot.barIndex;

                          if (barIdx >= 0 && barIdx < activeNames.length) {
                            String pName = activeNames[barIdx];
                            final qMap = b['qty'] as Map<String, dynamic>;
                            final bMap = b['bills'] as Map<String, dynamic>;

                            int currQ = ((qMap[pName] as num?) ?? 0).toInt();
                            int bills = ((bMap[pName] as num?) ?? 0).toInt();

                            int prevQ = idx > 0 ? (((buckets[idx - 1]['qty'] as Map<String, dynamic>)[pName] as num?) ?? currQ).toInt() : currQ;
                            int diff = currQ - prevQ;
                            String arrow = diff > 0 ? " ▲ (+$diff)" : (diff < 0 ? " ▼ ($diff)" : " ➔ (0)");

                            if (_isPercentMode) {
                              String pctStr = "${spot.y.toStringAsFixed(1)}%";
                              if (spot.y > 0) pctStr = "+$pctStr";

                              return LineTooltipItem(
                                "📅 $label\n📦 $pName: $currQ units ($pctStr Index)\n🧾 Bills: $bills Invoices",
                                TextStyle(color: _productColors[barIdx % _productColors.length], fontWeight: FontWeight.bold, fontSize: 11, height: 1.4),
                              );
                            } else {
                              return LineTooltipItem(
                                "📅 $label\n📦 $pName: $currQ units$arrow\n🧾 Bills: $bills Invoices",
                                TextStyle(color: _productColors[barIdx % _productColors.length], fontWeight: FontWeight.bold, fontSize: 11, height: 1.4),
                              );
                            }
                          }
                        }
                        return LineTooltipItem('', const TextStyle());
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: lineBarsData,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }

  Widget _buildBalanceSummary() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: Colors.blueGrey.shade50,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("OPENING BALANCE: $_openingBalance units", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
          Text("CLOSING BALANCE: $_closingBalance units", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: _closingBalance > 0 ? Colors.green.shade800 : Colors.red.shade800)),
        ],
      ),
    );
  }

  Widget _buildLedgerGrid() {
    if (_ledgerEntries.isEmpty) {
      return const Center(child: Text("No transactions recorded for this medicine in the selected period.", style: TextStyle(color: Colors.grey)));
    }

    return Column(
      children: [
        Container(
          height: 34,
          color: const Color(0xFF334155),
          child: const Row(
            children: [
              _Hdr("DATE", flex: 2),
              _Hdr("TYPE", flex: 2),
              _Hdr("REF / BILL NO", flex: 3),
              _Hdr("BATCH", flex: 2),
              _Hdr("IN (+)", flex: 2, align: TextAlign.right),
              _Hdr("OUT (-)", flex: 2, align: TextAlign.right),
              _Hdr("BALANCE", flex: 2, align: TextAlign.right),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _ledgerEntries.length,
            itemBuilder: (ctx, i) {
              final r = _ledgerEntries[i];
              return Container(
                height: 32,
                decoration: BoxDecoration(
                  color: i % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC),
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    _Cell(r['date'].toString(), flex: 2),
                    _Cell(r['type'].toString(), flex: 2, isBold: true, color: _getTypeColor(r['type'].toString())),
                    _Cell(r['ref_no'].toString(), flex: 3),
                    _Cell(cleanBatch(r['batch'].toString()), flex: 2),
                    _Cell(r['in_qty'] > 0 ? "+${r['in_qty']}" : "-", flex: 2, align: TextAlign.right, color: Colors.green.shade800, isBold: true),
                    _Cell(r['out_qty'] > 0 ? "-${r['out_qty']}" : "-", flex: 2, align: TextAlign.right, color: Colors.red.shade800, isBold: true),
                    _Cell(r['balance'].toString(), flex: 2, align: TextAlign.right, isBold: true),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecentStockChangesView(PharmacyProvider provider) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: provider.get20RecentStockChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final changes = snapshot.data ?? [];
        if (changes.isEmpty) {
          return const Center(
            child: Text(
              "No recent stock changes found.",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.history_rounded, size: 18, color: Colors.blue),
                    const SizedBox(width: 8),
                    const Text(
                      "20 HISTORY OF LAST STOCK CHANGED",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)),
                    ),
                    const Spacer(),
                    Text(
                      "Showing latest 20 stock changes",
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowHeight: 36,
                      dataRowHeight: 38,
                      headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                      columns: const [
                        DataColumn(label: Text("DATE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900))),
                        DataColumn(label: Text("TYPE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900))),
                        DataColumn(label: Text("REF NO", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900))),
                        DataColumn(label: Text("PRODUCT NAME", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900))),
                        DataColumn(label: Text("BATCH", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900))),
                        DataColumn(label: Text("IN QTY", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900))),
                        DataColumn(label: Text("OUT QTY", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900))),
                      ],
                      rows: changes.map((r) {
                        final inQty = (r['in_qty'] as num?)?.toInt() ?? 0;
                        final outQty = (r['out_qty'] as num?)?.toInt() ?? 0;
                        final typeStr = r['type']?.toString() ?? '';

                        return DataRow(
                          cells: [
                            DataCell(Text(r['date']?.toString() ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: inQty > 0 ? Colors.green.shade50 : Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: inQty > 0 ? Colors.green.shade200 : Colors.orange.shade200),
                                ),
                                child: Text(
                                  typeStr,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: inQty > 0 ? Colors.green.shade800 : Colors.orange.shade900,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(Text(r['ref_no']?.toString() ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                            DataCell(Text(r['product_name']?.toString() ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                            DataCell(Text(r['batch']?.toString() ?? '', style: const TextStyle(fontSize: 11, fontFamily: 'monospace'))),
                            DataCell(Text(inQty > 0 ? "+$inQty" : "-", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade700))),
                            DataCell(Text(outQty > 0 ? "-$outQty" : "-", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade700))),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getTypeColor(String type) {
    if (type.contains("PURCHASE")) return Colors.green.shade800;
    if (type.contains("SALE")) return Colors.blue.shade800;
    if (type.contains("RETURN")) return Colors.orange.shade800;
    if (type.contains("WRITE-OFF") || type.contains("DAMAGE")) return Colors.red.shade800;
    return Colors.black87;
  }
}

/// Movement Screener & Product Breakdown Dialog with Default White Theme & Dark Mode Toggle
class _MovementScreenerDialog extends StatefulWidget {
  final DateTime fromDate;
  final DateTime toDate;
  final String initialSortField;
  final Function(String) onSelectProduct;

  const _MovementScreenerDialog({
    required this.fromDate,
    required this.toDate,
    required this.initialSortField,
    required this.onSelectProduct,
  });

  @override
  State<_MovementScreenerDialog> createState() => _MovementScreenerDialogState();
}

class _MovementScreenerDialogState extends State<_MovementScreenerDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _screenerData = [];
  bool _isLoading = true;

  bool get _isDarkMode => Provider.of<AppProvider>(context, listen: false).isDarkMode;

  late String _sortField; // 'qty', 'bills', 'growth'
  bool _isAscending = false;
  String _activePreset = 'ALL'; // 'ALL', 'GAINERS', 'LOSERS'

  @override
  void initState() {
    super.initState();
    _sortField = widget.initialSortField;
    _loadScreenerData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadScreenerData() async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final data = await provider.getInventoryMovementScreenerData(
      fromDateA: widget.fromDate,
      toDateA: widget.toDate,
      fromDateB: widget.fromDate.subtract(const Duration(days: 30)),
      toDateB: widget.fromDate.subtract(const Duration(days: 1)),
    );

    if (mounted) {
      setState(() {
        _screenerData = data;
        _isLoading = false;
        _applySortingAndFilter();
      });
    }
  }

  void _applySortingAndFilter() {
    _screenerData.sort((a, b) {
      num valA = 0;
      num valB = 0;

      if (_sortField == 'qty') {
        valA = a['totalQty'] as num;
        valB = b['totalQty'] as num;
      } else if (_sortField == 'bills') {
        valA = a['totalBills'] as num;
        valB = b['totalBills'] as num;
      } else if (_sortField == 'growth') {
        valA = a['growthTrend'] as num;
        valB = b['growthTrend'] as num;
      }

      return _isAscending ? valA.compareTo(valB) : valB.compareTo(valA);
    });
  }

  void _toggleSort(String field) {
    setState(() {
      if (_sortField == field) {
        _isAscending = !_isAscending;
      } else {
        _sortField = field;
        _isAscending = false;
      }
      _applySortingAndFilter();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = Provider.of<AppProvider>(context);
    final isDarkMode = app.isDarkMode;
    String query = _searchCtrl.text.trim().toLowerCase();

    List<Map<String, dynamic>> filteredList = _screenerData.where((item) {
      final name = item['productName'].toString().toLowerCase();
      if (query.isNotEmpty && !name.contains(query)) return false;

      double growth = (item['growthTrend'] as num).toDouble();
      if (_activePreset == 'GAINERS') return growth > 0;
      if (_activePreset == 'LOSERS') return growth < 0;

      return true;
    }).toList();

    // Theme Palette Definitions
    final dialogBg = isDarkMode ? const Color(0xFF0F172A) : Colors.white;
    final headerBg = isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final borderColor = isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textPrimary = isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final rowEvenBg = isDarkMode ? const Color(0xFF0F172A) : Colors.white;
    final rowOddBg = isDarkMode ? const Color(0xFF1E293B).withValues(alpha: 0.4) : const Color(0xFFF8FAFC);
    final tableHeaderBg = isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 1000,
        height: 680,
        decoration: BoxDecoration(
          color: dialogBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Column(
          children: [
            // Header Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: headerBg,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  Icon(Icons.analytics_rounded, color: Colors.blue.shade800, size: 22),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("PRODUCT MOVEMENT SCREENER", style: TextStyle(color: textPrimary, fontWeight: FontWeight.w900, fontSize: 15)),
                      Text("Ranked Product Demand & Stock Quantity Movement Breakdown", style: TextStyle(color: textSub, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Spacer(),

                  IconButton(
                    icon: Icon(Icons.close, color: textSub),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Controls & Filters Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              color: headerBg.withValues(alpha: 0.6),
              child: Row(
                children: [
                  // Search Input
                  SizedBox(
                    width: 280,
                    height: 36,
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(color: textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: "Search product name...",
                        hintStyle: TextStyle(color: textSub, fontSize: 12),
                        prefixIcon: const Icon(Icons.search, size: 16, color: Colors.blue),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(icon: Icon(Icons.clear, size: 14, color: textSub), onPressed: () => setState(() => _searchCtrl.clear()))
                            : null,
                        filled: true,
                        fillColor: dialogBg,
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: borderColor)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Preset Filter Chips
                  _presetChip("All Items", 'ALL', isDark: _isDarkMode),
                  const SizedBox(width: 8),
                  _presetChip("📈 Top Gainers", 'GAINERS', color: Colors.green, isDark: _isDarkMode),
                  const SizedBox(width: 8),
                  _presetChip("📉 Top Losers", 'LOSERS', color: Colors.red, isDark: _isDarkMode),
                  const Spacer(),

                  Text("Total ${filteredList.length} Items", style: TextStyle(color: textSub, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),

            // Table Body
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: Colors.blue.shade800))
                  : (filteredList.isEmpty
                      ? Center(child: Text("No items found matching criteria.", style: TextStyle(color: textSub)))
                      : Column(
                          children: [
                            // Table Header Row
                            Container(
                              height: 36,
                              color: tableHeaderBg,
                              child: Row(
                                children: [
                                  _ScreenerHdr("#", flex: 1, textColor: textSub),
                                  _ScreenerHdr("PRODUCT NAME", flex: 6, textColor: textSub),
                                  _ScreenerSortHdr("VOLUME (UNITS)", 'qty', currentField: _sortField, isAsc: _isAscending, onTap: () => _toggleSort('qty'), flex: 3, textColor: textSub),
                                  _ScreenerSortHdr("INVOICES", 'bills', currentField: _sortField, isAsc: _isAscending, onTap: () => _toggleSort('bills'), flex: 3, textColor: textSub),
                                  _ScreenerSortHdr("MOVEMENT TREND (%)", 'growth', currentField: _sortField, isAsc: _isAscending, onTap: () => _toggleSort('growth'), flex: 3, textColor: textSub),
                                  _ScreenerHdr("ACTION", flex: 2, align: TextAlign.center, textColor: textSub),
                                ],
                              ),
                            ),

                            // List Rows
                            Expanded(
                              child: ListView.builder(
                                itemCount: filteredList.length,
                                itemBuilder: (ctx, i) {
                                  final r = filteredList[i];
                                  final pName = r['productName'].toString();
                                  final qty = r['totalQty'] as int;
                                  final bills = r['totalBills'] as int;
                                  final growth = r['growthTrend'] as double;
                                  final isEven = i % 2 == 0;

                                  Color growthColor = growth > 0
                                      ? (_isDarkMode ? const Color(0xFF4ADE80) : Colors.green.shade800)
                                      : (growth < 0 ? (_isDarkMode ? const Color(0xFFF87171) : Colors.red.shade800) : textSub);

                                  String growthStr = growth > 0 ? "▲ +${growth.toStringAsFixed(1)}%" : (growth < 0 ? "▼ ${growth.toStringAsFixed(1)}%" : "➔ 0.0%");

                                  return Container(
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: isEven ? rowEvenBg : rowOddBg,
                                      border: Border(bottom: BorderSide(color: borderColor)),
                                    ),
                                    child: Row(
                                      children: [
                                        _ScreenerCell("${i + 1}", flex: 1, color: textSub),
                                        _ScreenerCell(pName, flex: 6, isBold: true, color: textPrimary),
                                        _ScreenerCell("$qty units", flex: 3, align: TextAlign.right, color: Colors.blue.shade800, isBold: true),
                                        _ScreenerCell("$bills Bills", flex: 3, align: TextAlign.right, color: textPrimary),
                                        _ScreenerCell(growthStr, flex: 3, align: TextAlign.right, color: growthColor, isBold: true),
                                        Expanded(
                                          flex: 2,
                                          child: Center(
                                            child: ElevatedButton(
                                              onPressed: () {
                                                widget.onSelectProduct(pName);
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text("Added $pName to Stock Movement Chart comparison!"),
                                                    duration: const Duration(seconds: 2),
                                                    backgroundColor: Colors.blue.shade900,
                                                  ),
                                                );
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.blue.shade800,
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                minimumSize: Size.zero,
                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                              ),
                                              child: const Text("+ CHART", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _themeToggleButton({required IconData icon, required String label, required bool isActive, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? (_isDarkMode ? Colors.blue.shade800 : Colors.white) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          boxShadow: isActive && !_isDarkMode ? [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 2)] : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 12, color: isActive ? (_isDarkMode ? Colors.white : Colors.blue.shade800) : (_isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: isActive ? (_isDarkMode ? Colors.white : Colors.blue.shade800) : (_isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetChip(String label, String key, {Color? color, required bool isDark}) {
    final isActive = _activePreset == key;
    final activeColor = color ?? Colors.blue.shade800;

    return InkWell(
      onTap: () => setState(() => _activePreset = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withValues(alpha: 0.15) : Colors.transparent,
          border: Border.all(color: isActive ? activeColor : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1))),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isActive ? activeColor : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
        ),
      ),
    );
  }
}

class _ScreenerHdr extends StatelessWidget {
  final String title; final int flex; final TextAlign align; final Color textColor;
  const _ScreenerHdr(this.title, {required this.flex, this.align = TextAlign.left, required this.textColor});
  @override Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.center ? Alignment.center : Alignment.centerRight),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(title, style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _ScreenerSortHdr extends StatelessWidget {
  final String title; final String field; final String currentField; final bool isAsc; final VoidCallback onTap; final int flex; final Color textColor;
  const _ScreenerSortHdr(this.title, this.field, {required this.currentField, required this.isAsc, required this.onTap, required this.flex, required this.textColor});

  @override Widget build(BuildContext context) {
    final isSelected = currentField == field;

    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: onTap,
        child: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.blue.shade800 : textColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                isSelected ? (isAsc ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more,
                size: 12,
                color: isSelected ? Colors.blue.shade800 : textColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScreenerCell extends StatelessWidget {
  final String text; final int flex; final TextAlign align; final Color? color; final bool isBold;
  const _ScreenerCell(this.text, {required this.flex, this.align = TextAlign.left, this.color, this.isBold = false});
  @override Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.center ? Alignment.center : Alignment.centerRight),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(
          text,
          style: TextStyle(fontSize: 11, color: color ?? Colors.black87, fontWeight: isBold ? FontWeight.bold : FontWeight.w500),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _Hdr extends StatelessWidget {
  final String title; final int flex; final TextAlign align;
  const _Hdr(this.title, {required this.flex, this.align = TextAlign.left});
  @override Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        alignment: align == TextAlign.left ? Alignment.centerLeft : Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String text; final int flex; final TextAlign align; final Color? color; final bool isBold;
  const _Cell(this.text, {required this.flex, this.align = TextAlign.left, this.color, this.isBold = false});
  @override Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        alignment: align == TextAlign.left ? Alignment.centerLeft : Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(text, style: TextStyle(fontSize: 11, color: color ?? Colors.black87, fontWeight: isBold ? FontWeight.bold : FontWeight.w500), overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _DataLabelDotPainter extends FlDotPainter {
  final Color color;
  final String text;
  final FlDotCirclePainter circlePainter;

  _DataLabelDotPainter({required this.color, required this.text})
      : circlePainter = FlDotCirclePainter(
          radius: 4.5,
          color: Colors.white,
          strokeWidth: 2.5,
          strokeColor: color,
        );

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    circlePainter.draw(canvas, spot, offsetInCanvas);

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();

    final double textWidth = textPainter.width;
    final double textHeight = textPainter.height;
    final Rect bgRect = Rect.fromLTWH(
      offsetInCanvas.dx - textWidth / 2 - 3,
      offsetInCanvas.dy - 18 - 1,
      textWidth + 6,
      textHeight + 2,
    );
    final RRect bgRRect = RRect.fromRectAndRadius(bgRect, const Radius.circular(4));

    final Paint bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    final Paint borderPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawRRect(bgRRect, bgPaint);
    canvas.drawRRect(bgRRect, borderPaint);

    textPainter.paint(
      canvas,
      Offset(offsetInCanvas.dx - textWidth / 2, offsetInCanvas.dy - 18),
    );
  }

  @override
  Size getSize(FlSpot spot) => const Size(24, 24);

  @override
  Color get mainColor => color;

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) => this;

  @override
  List<Object?> get props => [color, text];
}

