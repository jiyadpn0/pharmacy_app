import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../providers/pharmacy_provider.dart';
import '../utils/app_dialogs.dart';
import '../utils/theme_constants.dart';

class OrderConfirmationScreen extends StatefulWidget {
  const OrderConfirmationScreen({super.key});

  @override
  State<OrderConfirmationScreen> createState() => _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState extends State<OrderConfirmationScreen> {
  bool _isLoading = true;
  List<OrderConfirmation> _allOrders = [];
  List<OrderConfirmation> _filteredOrders = [];

  String _searchQuery = "";
  String _selectedStatusFilter = "ALL"; // 'ALL', 'PENDING', 'PARTIAL', 'RECEIVED'
  String _selectedDatePreset = "2_MONTHS"; // '2_MONTHS', '30_DAYS', 'THIS_MONTH', 'ALL', 'CUSTOM'

  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 60)); // Default 2 Months
  DateTime _toDate = DateTime.now();

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchOrders();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchOrders() async {
    setState(() => _isLoading = true);
    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    try {
      final orders = await provider.fetchOrderConfirmations(
        fromDate: _fromDate,
        toDate: _toDate.add(const Duration(days: 1)), // inclusive of end date
        statusFilter: _selectedStatusFilter == 'ALL' ? null : _selectedStatusFilter,
        searchQuery: _searchQuery,
      );

      if (mounted) {
        setState(() {
          _allOrders = orders;
          _filteredOrders = orders;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading order confirmations: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyDatePreset(String preset) {
    final now = DateTime.now();
    DateTime start;
    DateTime end = now;

    switch (preset) {
      case '2_MONTHS':
        start = now.subtract(const Duration(days: 60));
        break;
      case '30_DAYS':
        start = now.subtract(const Duration(days: 30));
        break;
      case 'THIS_MONTH':
        start = DateTime(now.year, now.month, 1);
        break;
      case 'ALL':
        start = DateTime(2020, 1, 1);
        break;
      default:
        start = now.subtract(const Duration(days: 60));
    }

    setState(() {
      _selectedDatePreset = preset;
      _fromDate = start;
      _toDate = end;
    });
    _fetchOrders();
  }

  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
    );

    if (picked != null) {
      setState(() {
        _selectedDatePreset = "CUSTOM";
        _fromDate = picked.start;
        _toDate = picked.end;
      });
      _fetchOrders();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final pendingCount = _allOrders.where((o) => o.status == 'PENDING').length;
    final partialCount = _allOrders.where((o) => o.status == 'PARTIAL').length;
    final receivedCount = _allOrders.where((o) => o.status == 'RECEIVED').length;
    final totalAmount = _allOrders.fold<double>(0.0, (sum, o) => sum + o.totalAmount);
    final pendingAmount = _allOrders.where((o) => o.status != 'RECEIVED').fold<double>(0.0, (sum, o) => sum + o.totalAmount);

    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          // Top Header & Action Toolbar
          _buildHeader(),

          // Metrics & Summary Cards
          _buildMetricsBar(
            totalOrders: _allOrders.length,
            pendingOrders: pendingCount,
            receivedOrders: receivedCount,
            totalAmount: totalAmount,
            pendingAmount: pendingAmount,
          ),

          // Filters & Status Tabs Bar
          _buildFilterTabsBar(
            pendingCount: pendingCount,
            partialCount: partialCount,
            receivedCount: receivedCount,
          ),

          // Main Orders List Area
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredOrders.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredOrders.length,
                        itemBuilder: (context, index) {
                          return _buildOrderCard(_filteredOrders[index]);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          const Icon(Icons.assignment_turned_in_rounded, color: Color(0xFF1E3A8A), size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "ORDER CONFIRMATION & RECEIPT TRACKER",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0F172A), letterSpacing: 0.5),
              ),
              Text(
                "Track purchase orders, delivery status & receipt dates up to 2 months",
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
          const Spacer(),

          // Search Box
          SizedBox(
            width: 240,
            height: 36,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (val) {
                _searchQuery = val;
                _fetchOrders();
              },
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: "Search supplier, order ID, product...",
                prefixIcon: const Icon(Icons.search, size: 16),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 14),
                        onPressed: () {
                          _searchCtrl.clear();
                          _searchQuery = "";
                          _fetchOrders();
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Date Range Selector Dropdown
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedDatePreset,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.blueGrey, size: 18),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                items: const [
                  DropdownMenuItem(value: "2_MONTHS", child: Text("Last 2 Months (60 Days)")),
                  DropdownMenuItem(value: "30_DAYS", child: Text("Last 30 Days")),
                  DropdownMenuItem(value: "THIS_MONTH", child: Text("This Month")),
                  DropdownMenuItem(value: "ALL", child: Text("All Orders")),
                  DropdownMenuItem(value: "CUSTOM", child: Text("Custom Range...")),
                ],
                onChanged: (val) {
                  if (val == "CUSTOM") {
                    _pickCustomDateRange();
                  } else if (val != null) {
                    _applyDatePreset(val);
                  }
                },
              ),
            ),
          ),

          const SizedBox(width: 12),

          ElevatedButton.icon(
            onPressed: () => _openCreateOrderDialog(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text("NEW ORDER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),

          const SizedBox(width: 8),

          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blueGrey, size: 20),
            onPressed: _fetchOrders,
            tooltip: "Refresh Data",
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsBar({
    required int totalOrders,
    required int pendingOrders,
    required int receivedOrders,
    required double totalAmount,
    required double pendingAmount,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          Expanded(child: _metricCard("TOTAL ORDERS", "$totalOrders", "Period: ${DateFormat('dd MMM').format(_fromDate)} - ${DateFormat('dd MMM').format(_toDate)}", Icons.shopping_bag_outlined, Colors.blue)),
          const SizedBox(width: 12),
          Expanded(child: _metricCard("PENDING / ORDERED", "$pendingOrders", "Value: ₹${pendingAmount.toStringAsFixed(2)}", Icons.hourglass_top_rounded, Colors.orange.shade800)),
          const SizedBox(width: 12),
          Expanded(child: _metricCard("RECEIVED ORDERS", "$receivedOrders", "Delivered & confirmed", Icons.check_circle_outline, Colors.green.shade700)),
          const SizedBox(width: 12),
          Expanded(child: _metricCard("TOTAL VALUE", "₹${totalAmount.toStringAsFixed(2)}", "All confirmed orders", Icons.account_balance_wallet_outlined, Colors.indigo.shade800)),
        ],
      ),
    );
  }

  Widget _metricCard(String label, String value, String subtext, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
                Text(subtext, style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildFilterTabsBar({
    required int pendingCount,
    required int partialCount,
    required int receivedCount,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          _filterChip("ALL ORDERS", "ALL", _allOrders.length),
          const SizedBox(width: 8),
          _filterChip("PENDING / NOT RECEIVED", "PENDING", pendingCount, color: Colors.orange.shade800),
          const SizedBox(width: 8),
          _filterChip("PARTIALLY RECEIVED", "PARTIAL", partialCount, color: Colors.blue.shade800),
          const SizedBox(width: 8),
          _filterChip("FULLY RECEIVED", "RECEIVED", receivedCount, color: Colors.green.shade700),
          const Spacer(),
          Text(
            "Showing ${_filteredOrders.length} orders",
            style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value, int count, {Color? color}) {
    final isSelected = _selectedStatusFilter == value;
    final chipColor = color ?? const Color(0xFF1E3A8A);

    return InkWell(
      onTap: () {
        setState(() => _selectedStatusFilter = value);
        _fetchOrders();
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? chipColor : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? chipColor : const Color(0xFFCBD5E1)),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : const Color(0xFF475569),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white24 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "$count",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.assignment_late_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text("No order confirmations found", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          const SizedBox(height: 6),
          const Text("Click '+ NEW ORDER' to create and save a new order confirmation.", style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildOrderCard(OrderConfirmation order) {
    final statusColor = _getStatusColor(order.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(_getStatusIcon(order.status), color: statusColor, size: 20),
        ),
        title: Row(
          children: [
            Text(
              order.orderId,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: statusColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                order.status,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
              ),
            ),
            const Spacer(),
            Text(
              "₹${order.totalAmount.toStringAsFixed(2)}",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E3A8A)),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(Icons.business, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(order.supplierName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B))),
              const SizedBox(width: 16),
              Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text("Ordered: ${DateFormat('dd/MM/yyyy HH:mm').format(order.orderDate)}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
              if (order.receivedDate != null && order.receivedDate!.isNotEmpty) ...[
                const SizedBox(width: 16),
                Icon(Icons.event_available, size: 12, color: Colors.green.shade700),
                const SizedBox(width: 4),
                Text("Received Date: ${order.receivedDate}", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
              ] else if (order.expectedDeliveryDate != null && order.expectedDeliveryDate!.isNotEmpty) ...[
                const SizedBox(width: 16),
                Icon(Icons.local_shipping_outlined, size: 12, color: Colors.orange.shade800),
                const SizedBox(width: 4),
                Text("Expected: ${order.expectedDeliveryDate}", style: TextStyle(fontSize: 11, color: Colors.orange.shade900)),
              ],
            ],
          ),
        ),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Items Table
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(1),
                4: FlexColumnWidth(1.2),
                5: FlexColumnWidth(1.2),
                6: FlexColumnWidth(1.5),
              },
              children: [
                TableRow(
                  decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                  children: [
                    _tableHeaderCell("PRODUCT NAME"),
                    _tableHeaderCell("COMPANY"),
                    _tableHeaderCell("ORDERED"),
                    _tableHeaderCell("RECEIVED"),
                    _tableHeaderCell("UNIT RATE"),
                    _tableHeaderCell("TOTAL"),
                    _tableHeaderCell("STATUS"),
                  ],
                ),
                ...order.items.map((item) {
                  final itemStatusColor = _getStatusColor(item.status);
                  return TableRow(
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                    ),
                    children: [
                      _tableBodyCell(item.productName, isBold: true),
                      _tableBodyCell(item.company.isEmpty ? "-" : item.company),
                      _tableBodyCell("${item.orderQty} ${item.packSize > 1 ? '(Pack ${item.packSize})' : ''}"),
                      _tableBodyCell("${item.receivedQty}"),
                      _tableBodyCell("₹${item.unitPrice.toStringAsFixed(2)}"),
                      _tableBodyCell("₹${item.totalPrice.toStringAsFixed(2)}", isBold: true),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: itemStatusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.status,
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: itemStatusColor),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Action Buttons Bar
          Row(
            children: [
              if (order.notes.isNotEmpty) ...[
                const Icon(Icons.note, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text("Notes: ${order.notes}", style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey)),
              ],
              const Spacer(),

              // Quick Action: Mark Received
              if (order.status != 'RECEIVED') ...[
                ElevatedButton.icon(
                  onPressed: () => _openMarkReceivedDialog(order),
                  icon: const Icon(Icons.check_circle, size: 14),
                  label: const Text("MARK RECEIVED / UPDATE STATUS"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(width: 8),
              ],

              OutlinedButton.icon(
                onPressed: () => _printOrderPdf(order),
                icon: const Icon(Icons.print, size: 14),
                label: const Text("PRINT PO / RECEIPT"),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(width: 8),

              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                onPressed: () => _confirmDeleteOrder(order),
                tooltip: "Delete Order Confirmation",
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _tableHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey),
      ),
    );
  }

  Widget _tableBodyCell(String text, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: const Color(0xFF1E293B),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'RECEIVED':
        return Colors.green.shade700;
      case 'PARTIAL':
        return Colors.blue.shade800;
      case 'CANCELLED':
        return Colors.red.shade700;
      case 'PENDING':
      default:
        return Colors.orange.shade800;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'RECEIVED':
        return Icons.check_circle_rounded;
      case 'PARTIAL':
        return Icons.timelapse_rounded;
      case 'CANCELLED':
        return Icons.cancel_rounded;
      case 'PENDING':
      default:
        return Icons.hourglass_top_rounded;
    }
  }

  // --- ACTIONS & DIALOGS ---

  void _openCreateOrderDialog({OrderConfirmation? existingOrder}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CreateOrderConfirmationDialog(
        existingOrder: existingOrder,
        onSaved: () => _fetchOrders(),
      ),
    );
  }

  void _openMarkReceivedDialog(OrderConfirmation order) {
    DateTime pickedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green.shade700),
              const SizedBox(width: 8),
              const Text("Mark Order Received / Status Update", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Order ID: ${order.orderId}", style: const TextStyle(fontWeight: FontWeight.bold)),
              Text("Supplier: ${order.supplierName}", style: const TextStyle(color: Colors.blueGrey)),
              const SizedBox(height: 16),
              const Text("Select Received Date:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: pickedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                  );
                  if (d != null) {
                    setDialogState(() => pickedDate = d);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(DateFormat('dd/MM/yyyy').format(pickedDate), style: const TextStyle(fontWeight: FontWeight.bold)),
                      const Icon(Icons.calendar_month, size: 18, color: Colors.teal),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text("Action:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              const Text("Clicking 'FULL RECEIPT' will set all items as fully received on this date.", style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("CANCEL"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
              onPressed: () async {
                final provider = Provider.of<PharmacyProvider>(context, listen: false);
                final receivedDateStr = DateFormat('dd/MM/yyyy').format(pickedDate);

                await provider.updateOrderConfirmationStatus(
                  order.orderId,
                  'RECEIVED',
                  receivedDate: receivedDateStr,
                );

                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Order ${order.orderId} marked as FULLY RECEIVED on $receivedDateStr"), backgroundColor: Colors.green),
                  );
                  _fetchOrders();
                }
              },
              child: const Text("MARK ALL FULLY RECEIVED"),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteOrder(OrderConfirmation order) async {
    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: "Delete Order Confirmation",
      content: "Are you sure you want to delete order ${order.orderId}? This action cannot be undone.",
      isDangerous: true,
    );

    if (confirmed == true && mounted) {
      final provider = Provider.of<PharmacyProvider>(context, listen: false);
      await provider.deleteOrderConfirmation(order.orderId);
      if (mounted) {
        _fetchOrders();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Order confirmation deleted successfully.")),
        );
      }
    }
  }

  void _printOrderPdf(OrderConfirmation order) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("PURCHASE ORDER CONFIRMATION", style: pw.TextStyle(font: boldFont, fontSize: 18, color: PdfColors.blue900)),
                      pw.Text("Pharma ERP Procurement Receipt", style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text("ORDER ID: ${order.orderId}", style: pw.TextStyle(font: boldFont, fontSize: 12)),
                      pw.Text("Date: ${DateFormat('dd/MM/yyyy').format(order.orderDate)}", style: pw.TextStyle(font: font, fontSize: 10)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Divider(),
              pw.SizedBox(height: 8),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Supplier: ${order.supplierName}", style: pw.TextStyle(font: boldFont, fontSize: 12)),
                  pw.Text("Status: ${order.status}", style: pw.TextStyle(font: boldFont, fontSize: 12, color: PdfColors.green700)),
                ],
              ),
              if (order.receivedDate != null && order.receivedDate!.isNotEmpty)
                pw.Text("Received Date: ${order.receivedDate}", style: pw.TextStyle(font: font, fontSize: 10)),

              pw.SizedBox(height: 16),

              pw.TableHelper.fromTextArray(
                context: context,
                headers: ['Product Name', 'Company', 'Ordered Qty', 'Received Qty', 'Unit Rate (₹)', 'Total (₹)'],
                headerStyle: pw.TextStyle(font: boldFont, fontSize: 10, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
                cellStyle: pw.TextStyle(font: font, fontSize: 9),
                data: order.items.map((i) {
                  return [
                    i.productName,
                    i.company,
                    "${i.orderQty}",
                    "${i.receivedQty}",
                    "₹${i.unitPrice.toStringAsFixed(2)}",
                    "₹${i.totalPrice.toStringAsFixed(2)}",
                  ];
                }).toList(),
              ),

              pw.SizedBox(height: 16),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text("Grand Total: ₹${order.totalAmount.toStringAsFixed(2)}", style: pw.TextStyle(font: boldFont, fontSize: 14)),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Order_${order.orderId}.pdf',
    );
  }
}

// --- DIALOG FOR CREATING / EDITING ORDER CONFIRMATIONS ---

class _CreateOrderConfirmationDialog extends StatefulWidget {
  final OrderConfirmation? existingOrder;
  final VoidCallback onSaved;

  const _CreateOrderConfirmationDialog({this.existingOrder, required this.onSaved});

  @override
  State<_CreateOrderConfirmationDialog> createState() => _CreateOrderConfirmationDialogState();
}

class _CreateOrderConfirmationDialogState extends State<_CreateOrderConfirmationDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _orderId;
  String _selectedSupplier = "";
  DateTime _expectedDate = DateTime.now().add(const Duration(days: 2));
  final TextEditingController _notesCtrl = TextEditingController();
  final TextEditingController _supplierCtrl = TextEditingController();

  final List<OrderConfirmationItem> _items = [];
  List<Product> _availableProducts = [];
  List<Supplier> _availableSuppliers = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _orderId = widget.existingOrder?.orderId ?? "ORD-${DateFormat('yyyyMMdd').format(now)}-${now.millisecondsSinceEpoch.toString().substring(8)}";

    if (widget.existingOrder != null) {
      _selectedSupplier = widget.existingOrder!.supplierName;
      _supplierCtrl.text = _selectedSupplier;
      _notesCtrl.text = widget.existingOrder!.notes;
      _items.addAll(widget.existingOrder!.items);
    } else {
      _items.add(OrderConfirmationItem(orderId: _orderId, productName: "", orderQty: 10, unitPrice: 0.0));
    }

    _loadMasterData();
  }

  Future<void> _loadMasterData() async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final prods = await provider.getProducts();
    final sups = await provider.fetchSuppliers();

    if (mounted) {
      setState(() {
        _availableProducts = prods;
        _availableSuppliers = sups;
      });
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _supplierCtrl.dispose();
    super.dispose();
  }

  void _addItem() {
    setState(() {
      _items.add(OrderConfirmationItem(
        orderId: _orderId,
        productName: "",
        orderQty: 10,
        unitPrice: 0.0,
      ));
    });
  }

  void _removeItem(int index) {
    if (_items.length > 1) {
      setState(() {
        _items.removeAt(index);
      });
    }
  }

  double get _calculatedTotal {
    return _items.fold(0.0, (sum, i) => sum + i.totalPrice);
  }

  void _saveOrder() async {
    if (_formKey.currentState?.validate() != true) return;

    final supplier = _supplierCtrl.text.trim();
    if (supplier.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select or enter a supplier name."), backgroundColor: Colors.redAccent),
      );
      return;
    }

    final validItems = _items.where((i) => i.productName.trim().isNotEmpty && i.orderQty > 0).toList();
    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please add at least one product with order quantity > 0."), backgroundColor: Colors.redAccent),
      );
      return;
    }

    final order = OrderConfirmation(
      orderId: _orderId,
      orderDate: DateTime.now(),
      supplierName: supplier,
      totalItems: validItems.length,
      totalAmount: _calculatedTotal,
      status: 'PENDING',
      expectedDeliveryDate: DateFormat('dd/MM/yyyy').format(_expectedDate),
      notes: _notesCtrl.text.trim(),
      createdAt: DateTime.now(),
      items: validItems,
    );

    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    await provider.saveOrderConfirmation(order);

    if (mounted) {
      Navigator.pop(context);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Order confirmation $_orderId saved successfully! Data stored up to 2 months."), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 900,
        height: 650,
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.note_add_rounded, color: Color(0xFF1E3A8A), size: 24),
                  const SizedBox(width: 8),
                  Text(
                    widget.existingOrder != null ? "Edit Order Confirmation" : "Create Order Confirmation",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
              const Divider(),
              const SizedBox(height: 12),

              // Form fields top row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Order ID", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                          child: Text(_orderId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Supplier / Wholesaler Name *", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                        const SizedBox(height: 4),
                        Autocomplete<String>(
                          optionsBuilder: (TextEditingValue val) {
                            if (val.text.isEmpty) return const Iterable<String>.empty();
                            return _availableSuppliers.map((s) => s.name).where((n) => n.toLowerCase().contains(val.text.toLowerCase()));
                          },
                          onSelected: (String sel) {
                            _supplierCtrl.text = sel;
                            _selectedSupplier = sel;
                          },
                          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                            if (_supplierCtrl.text.isNotEmpty && controller.text.isEmpty) {
                              controller.text = _supplierCtrl.text;
                            }
                            return TextFormField(
                              controller: controller,
                              focusNode: focusNode,
                              onChanged: (v) => _supplierCtrl.text = v,
                              style: const TextStyle(fontSize: 12),
                              decoration: InputDecoration(
                                hintText: "Select or type supplier...",
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Expected Delivery Date", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: _expectedDate,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 180)),
                            );
                            if (d != null) setState(() => _expectedDate = d);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(6)),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(DateFormat('dd/MM/yyyy').format(_expectedDate), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                const Icon(Icons.calendar_month, size: 16, color: Colors.blueGrey),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Items Header Bar
              Row(
                children: [
                  const Text("ORDER ITEMS LIST", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A))),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _addItem,
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text("Add Product", style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  )
                ],
              ),
              const SizedBox(height: 8),

              // Items Table Editor
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, idx) {
                      final item = _items[idx];
                      return Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: idx % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC),
                          border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                        ),
                        child: Row(
                          children: [
                            Text("${idx + 1}.", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.blueGrey)),
                            const SizedBox(width: 8),

                            // Product Autocomplete Field
                            Expanded(
                              flex: 4,
                              child: Autocomplete<String>(
                                optionsBuilder: (TextEditingValue val) {
                                  if (val.text.isEmpty) return const Iterable<String>.empty();
                                  final q = val.text.toLowerCase().trim();
                                  final starts = _availableProducts.where((p) => p.name.toLowerCase().startsWith(q)).toList();
                                  starts.sort((a, b) => b.stock.compareTo(a.stock));
                                  final contains = _availableProducts.where((p) => !p.name.toLowerCase().startsWith(q) && p.name.toLowerCase().contains(q)).toList();
                                  contains.sort((a, b) => b.stock.compareTo(a.stock));
                                  return [...starts, ...contains].map((p) => p.name).take(15);
                                },
                                onSelected: (String sel) {
                                  final match = _availableProducts.firstWhere((p) => p.name == sel, orElse: () => Product(id: '', name: sel, batch: '', rack: ''));
                                  setState(() {
                                    item.productName = sel;
                                    if (match.preferredWholesale.isNotEmpty && _supplierCtrl.text.isEmpty) {
                                      _supplierCtrl.text = match.preferredWholesale;
                                    }
                                  });
                                },
                                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                                  if (item.productName.isNotEmpty && controller.text.isEmpty) {
                                    controller.text = item.productName;
                                  }
                                  return TextFormField(
                                    controller: controller,
                                    focusNode: focusNode,
                                    onChanged: (v) => item.productName = v,
                                    style: const TextStyle(fontSize: 12),
                                    decoration: const InputDecoration(
                                      hintText: "Product Name...",
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      border: OutlineInputBorder(),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Company Field
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                initialValue: item.company,
                                onChanged: (v) => item.company = v,
                                style: const TextStyle(fontSize: 12),
                                decoration: const InputDecoration(
                                  hintText: "Company",
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Qty Field
                            SizedBox(
                              width: 80,
                              child: TextFormField(
                                initialValue: "${item.orderQty}",
                                keyboardType: TextInputType.number,
                                onChanged: (v) {
                                  setState(() {
                                    item.orderQty = int.tryParse(v) ?? 0;
                                  });
                                },
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(
                                  labelText: "Order Qty",
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Unit Price Field
                            SizedBox(
                              width: 90,
                              child: TextFormField(
                                initialValue: "${item.unitPrice}",
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                onChanged: (v) {
                                  setState(() {
                                    item.unitPrice = double.tryParse(v) ?? 0.0;
                                  });
                                },
                                style: const TextStyle(fontSize: 12),
                                decoration: const InputDecoration(
                                  labelText: "Rate (₹)",
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Line Total
                            SizedBox(
                              width: 90,
                              child: Text(
                                "₹${item.totalPrice.toStringAsFixed(2)}",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E3A8A)),
                              ),
                            ),

                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                              onPressed: () => _removeItem(idx),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Bottom Summary & Save Bar
              Row(
                children: [
                  Text("Total Items: ${_items.length}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 24),
                  Text("Total Amount: ₹${_calculatedTotal.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E3A8A))),
                  const Spacer(),

                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("CANCEL"),
                  ),
                  const SizedBox(width: 12),

                  ElevatedButton.icon(
                    onPressed: _saveOrder,
                    icon: const Icon(Icons.save, size: 16),
                    label: const Text("SAVE ORDER CONFIRMATION"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
