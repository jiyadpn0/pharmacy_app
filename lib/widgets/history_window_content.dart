import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import '../providers/pharmacy_provider.dart';
import '../utils/app_formatters.dart';
import '../utils/theme_constants.dart';

class HistoryWindowContent extends StatefulWidget {
  final String productName;
  final bool isSales;

  const HistoryWindowContent({super.key, required this.productName, this.isSales = true});

  @override
  State<HistoryWindowContent> createState() => _HistoryWindowContentState();
}

class _HistoryWindowContentState extends State<HistoryWindowContent> {
  late Future<List<Map<String, dynamic>>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _fetchHistory();
  }

  Future<List<Map<String, dynamic>>> _fetchHistory() async {
    try {
      final method = widget.isSales ? 'query_sales_history' : 'query_purchase_history';
      final res = await DesktopMultiWindow.invokeMethod(
        0,
        method,
        {'productName': widget.productName},
      );
      if (res is List) {
        return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {
      if (mounted) {
        final provider = Provider.of<PharmacyProvider>(context, listen: false);
        if (widget.isSales) {
          return await provider.getProductSaleHistory(widget.productName);
        } else {
          return await provider.getProductPurchaseHistory(widget.productName);
        }
      }
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(child: Text("No records found.", style: TextStyle(color: c.secondaryText)));
          }

          final history = snapshot.data!;
          return ListView.builder(
            itemCount: history.length + 1,
            itemBuilder: (ctx, i) {
              if (i == 0) {
                return Container(
                  height: 35,
                  color: c.tableHeaderBg,
                  child: _buildRow(
                    context,
                    "Entry No", "Date", "Batch", "Expiry", "Qty", "MRP", 
                    "Rate", widget.isSales ? "Doctor" : "Supplier", 
                    widget.isSales ? "Patient" : "L.Cost", 
                    isHeader: true
                  ),
                );
              }
              
              final item = history[i - 1];
              String dateStr = "";
              try { dateStr = DateFormat('dd/MM/yyyy').format(DateTime.parse(item['date'].toString())); } catch (_) {}
              
              double mrp = double.tryParse(item['mrp']?.toString() ?? "0") ?? 0.0;
              double rate = double.tryParse(item['s_rate']?.toString() ?? item['p_rate']?.toString() ?? "0") ?? 0.0;
              double lCost = double.tryParse(item['l_cost']?.toString() ?? "0") ?? 0.0;

              return Container(
                height: 35,
                decoration: BoxDecoration(
                  color: i % 2 == 0 ? c.tableRowEvenBg : c.tableRowOddBg,
                  border: Border(bottom: BorderSide(color: c.border)),
                ),
                child: _buildRow(
                  context,
                  item['entry_no']?.toString() ?? "",
                  dateStr,
                  cleanBatch(item['batch']?.toString() ?? ""),
                  item['expiry']?.toString() ?? "",
                  item['qty']?.toString() ?? "0",
                  mrp.toStringAsFixed(2),
                  rate.toStringAsFixed(2),
                  widget.isSales ? (item['doctor']?.toString() ?? "N/A") : (item['supplier_name']?.toString() ?? "N/A"),
                  widget.isSales ? (item['patient']?.toString() ?? "N/A") : lCost.toStringAsFixed(2),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildRow(BuildContext context, String c1, String c2, String c3, String c4, String c5, String c6, String c7, String c8, String c9, {bool isHeader = false}) {
    final c = AppColors.of(context);
    final style = TextStyle(fontSize: 12, fontWeight: isHeader ? FontWeight.bold : FontWeight.normal, color: isHeader ? c.primaryText : c.primaryText.withValues(alpha: 0.9));
    return Row(
      children: [
        Expanded(flex: 2, child: Padding(padding: const EdgeInsets.only(left: 12), child: Text(c1, style: style))),
        Expanded(flex: 3, child: Text(c2, style: style)),
        Expanded(flex: 3, child: Text(c3, style: style)),
        Expanded(flex: 2, child: Text(c4, style: style)),
        Expanded(flex: 1, child: Text(c5, style: style, textAlign: TextAlign.right)),
        Expanded(flex: 2, child: Text(c6, style: style, textAlign: TextAlign.right)),
        Expanded(flex: 2, child: Text(c7, style: style, textAlign: TextAlign.right)),
        Expanded(flex: 4, child: Padding(padding: const EdgeInsets.only(left: 16), child: Text(c8, style: style, overflow: TextOverflow.ellipsis))),
        Expanded(flex: 3, child: Text(c9, style: style, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
