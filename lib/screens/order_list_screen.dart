import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/pharmacy_provider.dart';
import '../providers/app_provider.dart';

class OrderListScreen extends StatefulWidget {
  final String initialTab;
  const OrderListScreen({super.key, this.initialTab = 'ORDER'});

  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _orderItems = [];
  DateTimeRange? _selectedDateRange;

  @override
  void initState() {
    super.initState();
    _fetchOrderList();
  }

  Future<void> _fetchOrderList() async {
    setState(() => _isLoading = true);
    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    try {
      final items = await provider.loadActiveOrderProducts(
        startDate: _selectedDateRange?.start,
        endDate: _selectedDateRange?.end ?? DateTime.now(),
      );

      if (mounted) {
        setState(() {
          _orderItems = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading order list: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = Provider.of<AppProvider>(context);
    final isDarkMode = app.isDarkMode;

    // Dynamic Colors based on Mode
    final bgColor = isDarkMode ? const Color(0xFF0F172A) : Colors.white;
    final appBarColor = isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final textColor = isDarkMode ? Colors.white : const Color(0xFF1E293B);
    final subTextColor = isDarkMode ? Colors.white70 : Colors.blueGrey;
    final rowBgEven = isDarkMode ? const Color(0xFF1E293B) : Colors.white;
    final rowBgOdd = isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF9FAFB);
    final borderColor = isDarkMode ? Colors.blueGrey.shade900 : Colors.grey.shade200;

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          // Header / Controls Bar
          _buildTopBar(appBarColor, textColor, bgColor, borderColor, isDarkMode),

          // Table / List Area
          Expanded(
            child: _isLoading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.teal),
                        const SizedBox(height: 16),
                        Text(
                          "Loading purchased items...",
                          style: TextStyle(color: subTextColor, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : _orderItems.isEmpty
                    ? Center(
                        child: Text(
                          "No purchased or used items found for the selected range.",
                          style: TextStyle(color: subTextColor, fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _orderItems.length,
                        itemExtent: 44.0, 
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemBuilder: (context, index) {
                          final item = _orderItems[index];
                          final stock = item['current_stock'] as num? ?? 0;
                          final sales = item['sales_qty'] as num? ?? 0;
                          final reorder = item['reorder_level'] as num? ?? 0;
                          final suggestedQty = (reorder > stock) ? (reorder - stock) : (sales > 0 ? sales : 10);

                          return Container(
                            decoration: BoxDecoration(
                              color: index % 2 == 0 ? rowBgEven : rowBgOdd,
                              border: Border(bottom: BorderSide(color: borderColor)),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    item['name'] ?? '',
                                    style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    item['supplier_name'] ?? 'Direct',
                                    style: TextStyle(color: subTextColor, fontSize: 11),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    "$stock",
                                    style: TextStyle(
                                      color: stock <= reorder ? Colors.redAccent : Colors.teal.shade700,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    "$sales",
                                    style: TextStyle(color: subTextColor, fontSize: 12),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    "₹${(item['purchase_rate'] as num? ?? 0).toStringAsFixed(2)}",
                                    style: TextStyle(color: isDarkMode ? Colors.amberAccent : Colors.orange.shade800, fontSize: 12),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.teal.shade300),
                                  ),
                                  child: Text(
                                    "Order: $suggestedQty",
                                    style: TextStyle(color: Colors.teal.shade800, fontWeight: FontWeight.bold, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(Color barColor, Color textColor, Color bgColor, Color borderColor, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: barColor,
      child: Row(
        children: [
          Text(
            "ORDER BOOK",
            style: TextStyle(color: isDarkMode ? Colors.tealAccent : const Color(0xFF0D9488), fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                initialDateRange: _selectedDateRange ?? DateTimeRange(
                  start: DateTime.now().subtract(const Duration(days: 30)),
                  end: DateTime.now(),
                ),
              );
              if (picked != null) {
                setState(() => _selectedDateRange = picked);
                _fetchOrderList();
              }
            },
            icon: const Icon(Icons.calendar_today_rounded, size: 14),
            label: Text(
              _selectedDateRange == null
                  ? "Filter Date Range"
                  : "${DateFormat('dd/MM').format(_selectedDateRange!.start)} - ${DateFormat('dd/MM').format(_selectedDateRange!.end)}",
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: bgColor,
              foregroundColor: textColor,
              side: BorderSide(color: borderColor),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: Icon(Icons.refresh, color: isDarkMode ? Colors.tealAccent : const Color(0xFF0D9488)),
            tooltip: "Refresh List",
            onPressed: _fetchOrderList,
          ),
        ],
      ),
    );
  }
}
