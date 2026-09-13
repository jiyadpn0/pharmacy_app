import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/pharmacy_provider.dart';
import '../utils/app_formatters.dart';
import '../utils/theme_constants.dart';

class StockAdjustmentBatchReportScreen extends StatefulWidget {
  const StockAdjustmentBatchReportScreen({super.key});

  @override
  State<StockAdjustmentBatchReportScreen> createState() => _StockAdjustmentBatchReportScreenState();
}

enum AggregationType { sum, min, max, count, average, none }

class _StockAdjustmentBatchReportScreenState extends State<StockAdjustmentBatchReportScreen> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  final Map<String, String> _columnFilters = {};
  final Map<String, AggregationType> _columnAggregations = {
    'grandTotal': AggregationType.sum,
    'entryNo': AggregationType.count,
  };

  List<StockAdjustment> _allAdjustments = [];
  List<StockAdjustment> _displayData = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchData());
  }

  void _fetchData() {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    setState(() {
      _allAdjustments = provider.adjustments.where((adj) {
        final dateOnly = DateTime(adj.date.year, adj.date.month, adj.date.day);
        final startOnly = DateTime(_startDate.year, _startDate.month, _startDate.day);
        final endOnly = DateTime(_endDate.year, _endDate.month, _endDate.day);
        return !dateOnly.isBefore(startOnly) && !dateOnly.isAfter(endOnly);
      }).toList();
      _applyFilters();
    });
  }

  void _applyFilters() {
    setState(() {
      _displayData = _allAdjustments.where((adj) {
        bool match = true;
        _columnFilters.forEach((key, value) {
          if (value.isEmpty) return;
          String fieldVal = "";
          switch (key) {
            case 'date': fieldVal = DateFormat('dd/MM/yy').format(adj.date); break;
            case 'entryNo': fieldVal = adj.entryNo; break;
            case 'product': fieldVal = adj.items.map((i) => i.product.name).join(", "); break;
            case 'reason': fieldVal = adj.reason; break;
            case 'doneBy': fieldVal = adj.doneBy; break;
          }
          if (!fieldVal.toLowerCase().contains(value.toLowerCase())) match = false;
        });
        return match;
      }).toList();
    });
  }

  int _calculateNetQty(StockAdjustment adj) {
    return adj.items.fold(0, (sum, item) => sum + item.qty);
  }

  void _exportCSV() async {
    if (_displayData.isEmpty) return;
    String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Save Stock Adjustment Report CSV',
      fileName: 'Stock_Adjustment_Report_${DateFormat('ddMMyyyy').format(_startDate)}.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (outputFile != null) {
      final buffer = StringBuffer();
      buffer.writeln("Date,Entry No,Products,Reason,Done By,Net Qty,L.Cost Diff");

      for (var adj in _displayData) {
        String prods = adj.items.map((i) => "${i.product.name} (${cleanBatch(i.product.batch)})").join("; ");
        buffer.writeln('"${DateFormat('dd/MM/yyyy').format(adj.date)}","${adj.entryNo}","$prods","${adj.reason}","${adj.doneBy}",${_calculateNetQty(adj)},${adj.grandTotal.toStringAsFixed(2)}');
      }

      final file = File(outputFile);
      await file.writeAsString(buffer.toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Adjustment Report Exported to CSV!"), backgroundColor: Colors.green),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.cardBg,
        elevation: 0,
        title: Text("STOCK ADJUSTMENT REPORT", style: TextStyle(color: c.primaryText, fontWeight: FontWeight.w900, fontSize: 16)),
        leading: IconButton(icon: Icon(Icons.arrow_back, color: c.secondaryText), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          _buildReportHeader(),
          Expanded(child: _buildDataGrid()),
          _buildGridFooter(),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
      child: Row(
        children: [
          _dateRangePicker(),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _exportCSV,
            icon: const Icon(Icons.download, size: 16),
            label: const Text("EXPORT CSV", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey.shade800, foregroundColor: Colors.white),
          )
        ],
      ),
    );
  }

  Widget _dateRangePicker() {
    return InkWell(
      onTap: () async {
        final picked = await showDateRangePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDateRange: DateTimeRange(start: _startDate, end: _endDate));
        if (picked != null) {
          setState(() { _startDate = picked.start; _endDate = picked.end; });
          _fetchData();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            const Icon(Icons.calendar_month, size: 16, color: Colors.blue),
            const SizedBox(width: 8),
            Text("${DateFormat('dd/MM/yyyy').format(_startDate)} - ${DateFormat('dd/MM/yyyy').format(_endDate)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          ],
        ),
      ),
    );
  }

  Widget _buildReportHeader() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFD1D9E1),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        "Report Summary From: ${DateFormat('dd/MM/yyyy').format(_startDate)} To: ${DateFormat('dd/MM/yyyy').format(_endDate)}",
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF2C3E50)),
      ),
    );
  }

  Widget _buildDataGrid() {
    final columns = [
      _ColInfo("date", "Date", flex: 1.2),
      _ColInfo("entryNo", "Entry No", flex: 1.2),
      _ColInfo("product", "Product", flex: 3),
      _ColInfo("reason", "Reason", flex: 2),
      _ColInfo("doneBy", "Done By", flex: 1.2),
      _ColInfo("netQty", "Net Qty", flex: 1, align: TextAlign.center),
      _ColInfo("grandTotal", "L.Cost Diff", flex: 1.5, align: TextAlign.right),
      _ColInfo("action", "Act", flex: 0.5, align: TextAlign.center),
    ];

    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400)),
      child: Column(
        children: [
          _buildGridHeader(columns),
          _buildFilterRow(columns),
          Expanded(
            child: ListView.builder(
              itemCount: _displayData.length,
              itemBuilder: (ctx, i) => _buildGridRow(_displayData[i], columns, i),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridHeader(List<_ColInfo> columns) {
    return Container(
      height: 30,
      color: const Color(0xFFF5F5F5),
      child: Row(
        children: columns.map((col) => Expanded(
          flex: (col.flex * 10).toInt(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300, width: 0.5)),
            alignment: Alignment.centerLeft,
            child: Text(col.label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildFilterRow(List<_ColInfo> columns) {
    return Container(
      height: 25,
      color: Colors.white,
      child: Row(
        children: columns.map((col) => Expanded(
          flex: (col.flex * 10).toInt(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300, width: 0.5)),
            child: TextField(
              style: const TextStyle(fontSize: 10),
              decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
              onChanged: (v) {
                _columnFilters[col.key] = v;
                _applyFilters();
              },
            ),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildGridRow(StockAdjustment adj, List<_ColInfo> columns, int index) {
    return Container(
      height: 30,
      color: index % 2 == 0 ? Colors.white : const Color(0xFFF9F9F9),
      child: Row(
        children: columns.map((col) {
          String text = "";
          Color textColor = Colors.black87;
          switch (col.key) {
            case 'date': text = DateFormat('dd/MM/yy').format(adj.date); break;
            case 'entryNo': text = adj.entryNo; break;
            case 'reason': text = adj.reason; break;
            case 'doneBy': text = adj.doneBy; break;
            case 'netQty':
              int qty = _calculateNetQty(adj);
              text = qty > 0 ? "+$qty" : qty.toString();
              textColor = qty == 0 ? Colors.grey : (qty > 0 ? Colors.green.shade700 : Colors.red.shade700);
              break;
            case 'grandTotal':
              text = adj.grandTotal.toStringAsFixed(2);
              textColor = adj.grandTotal >= 0 ? Colors.green.shade700 : Colors.red.shade700;
              break;
            case 'product':
              text = adj.items.map((i) => "${i.product.name} (${cleanBatch(i.product.batch)})").join(", ");
              break;
          }

          if (col.key == 'action') {
            return Expanded(
              flex: (col.flex * 10).toInt(),
              child: Container(
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade100, width: 0.5)),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.red, size: 14),
                  padding: EdgeInsets.zero,
                  onPressed: () => _confirmDelete(adj),
                ),
              ),
            );
          }

          return Expanded(
            flex: (col.flex * 10).toInt(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade100, width: 0.5)),
              alignment: col.align == TextAlign.left ? Alignment.centerLeft : Alignment.centerRight,
              child: Text(text, style: TextStyle(fontSize: 11, fontWeight: col.key == 'entryNo' ? FontWeight.bold : FontWeight.normal, color: textColor), overflow: TextOverflow.ellipsis),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGridFooter() {
    final columns = [
      _ColInfo("date", "Date", flex: 1.2),
      _ColInfo("entryNo", "Entry No", flex: 1.2),
      _ColInfo("product", "Product", flex: 3),
      _ColInfo("reason", "Reason", flex: 2),
      _ColInfo("doneBy", "Done By", flex: 1.2),
      _ColInfo("netQty", "Net Qty", flex: 1, align: TextAlign.center),
      _ColInfo("grandTotal", "L.Cost Diff", flex: 1.5, align: TextAlign.right),
      _ColInfo("action", "", flex: 0.5),
    ];

    return Container(
      height: 30,
      decoration: BoxDecoration(color: const Color(0xFFE8EAF6), border: Border.all(color: Colors.grey.shade400)),
      child: Row(
        children: columns.map((col) {
          final agg = _columnAggregations[col.key] ?? AggregationType.none;
          final result = _calculateAggregation(col.key, agg);

          return Expanded(
            flex: (col.flex * 10).toInt(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300, width: 0.5)),
              alignment: col.align == TextAlign.left ? Alignment.centerLeft : Alignment.centerRight,
              child: Text(result, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue)),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _calculateAggregation(String colKey, AggregationType type) {
    if (type == AggregationType.none || _displayData.isEmpty) return "";
    if (type == AggregationType.count) return "${_displayData.length} records";

    List<double> values = [];
    for (var adj in _displayData) {
      if (colKey == 'grandTotal') values.add(adj.grandTotal);
      if (colKey == 'netQty') values.add(_calculateNetQty(adj).toDouble());
    }
    if (values.isEmpty) return "";

    switch (type) {
      case AggregationType.sum: return values.fold(0.0, (sum, v) => sum + v).toStringAsFixed(2);
      default: return "";
    }
  }

  void _confirmDelete(StockAdjustment adj) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Delete"),
        content: Text("Are you sure you want to delete stock adjustment #${adj.entryNo}? This will revert the physical stock changes."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await Provider.of<PharmacyProvider>(context, listen: false).deleteStockAdjustment(adj.entryNo);
                _fetchData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Adjustment deleted and inventory stock restored!")));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error deleting: $e"), backgroundColor: Colors.red));
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("DELETE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _ColInfo {
  final String key; final String label; final double flex; final TextAlign align;
  _ColInfo(this.key, this.label, {this.flex = 1, this.align = TextAlign.left});
}
