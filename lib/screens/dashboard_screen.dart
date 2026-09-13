import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../providers/pharmacy_provider.dart';
import '../utils/theme_constants.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final app = Provider.of<AppProvider>(context, listen: false);

    return Consumer<PharmacyProvider>(
      builder: (context, pharmacy, child) {
        return Scaffold(
          backgroundColor: c.background,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, c),
                const SizedBox(height: 32),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column (Stats + Quick Actions + Revenue Trend)
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Stats Row
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  context,
                                  c,
                                  "Today's Sales",
                                  "₹ ${pharmacy.todayRevenue.toStringAsFixed(0)}",
                                  "${pharmacy.todaySalesCount} Sales Today",
                                  "Today",
                                  Icons.assessment_outlined,
                                  Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: _buildStatCard(
                                  context,
                                  c,
                                  "Today's Purchases",
                                  "₹ ${pharmacy.todayPurchase.toStringAsFixed(0)}",
                                  "${pharmacy.todayPurchasesCount} Orders Today",
                                  "Today",
                                  Icons.shopping_bag_outlined,
                                  Colors.green,
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: _buildStatCard(
                                  context,
                                  c,
                                  "Stock Value",
                                  pharmacy.totalStockValue > 1000
                                      ? "${(pharmacy.totalStockValue / 1000).toStringAsFixed(1)}K+"
                                      : "₹ ${pharmacy.totalStockValue.toStringAsFixed(0)}",
                                  "${pharmacy.totalStockCount} Items",
                                  "Across ${pharmacy.racks.length} Racks",
                                  Icons.inventory_2_outlined,
                                  Colors.orange,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          Text(
                            "QUICK ACTIONS",
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c.secondaryText, letterSpacing: 1),
                          ),
                          const SizedBox(height: 16),
                          // Quick Actions Row 1
                          Row(
                            children: [
                              Expanded(child: _buildQuickAction(context, c, "New Sale", Icons.shopping_cart_outlined, Colors.blue, app.openSales)),
                              const SizedBox(width: 16),
                              Expanded(child: _buildQuickAction(context, c, "Purchase Entry", Icons.local_shipping_outlined, Colors.blueGrey, app.openPurchase)),
                              const SizedBox(width: 16),
                              Expanded(child: _buildQuickAction(context, c, "Add Product", Icons.add_box_outlined, Colors.orange, app.openProductRegistration)),
                              const SizedBox(width: 16),
                              Expanded(child: _buildQuickAction(context, c, "Payments", Icons.account_balance_wallet_outlined, Colors.teal, app.openPayment)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Quick Actions Row 2
                          Row(
                            children: [
                              Expanded(child: _buildQuickAction(context, c, "Sales Report", Icons.bar_chart_outlined, Colors.indigo, app.openSalesReport)),
                              const SizedBox(width: 16),
                              Expanded(child: _buildQuickAction(context, c, "GST Filing", Icons.account_balance_outlined, Colors.purple, app.openGstReport)),
                              const SizedBox(width: 16),
                              Expanded(child: _buildQuickAction(context, c, "Stock Ledger", Icons.menu_book_outlined, Colors.brown, app.openStockLedger)),
                              const SizedBox(width: 16),
                              Expanded(child: _buildQuickAction(context, c, "Customer Ledger", Icons.menu_book_rounded, Colors.blue, app.openCustomerLedger)),
                            ],
                          ),
                          const SizedBox(height: 32),
                          _buildRevenueTrend(context, c),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Right Column (Special Orders + Low Stock Alert)
                    Expanded(
                      child: Column(
                        children: [
                          _buildSpecialOrdersList(context, c),
                          const SizedBox(height: 24),
                          _buildLowStockAlert(context, c),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, AppThemeColors c) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Welcome back, Administrator",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: c.primaryText),
            ),
            const SizedBox(height: 4),
            Text(
              "Here's what's happening with your pharmacy today.",
              style: TextStyle(fontSize: 14, color: c.secondaryText),
            ),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: c.isDark ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shield_outlined, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("System Status", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  Text("Backups up to date", style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
                ],
              ),
              const SizedBox(width: 24),
              Stack(
                children: [
                  Container(width: 100, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(2))),
                  Container(width: 80, height: 4, decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(2))),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(BuildContext context, AppThemeColors c, String title, String value, String subValue, String badge, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 20),
              Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: c.primaryText)),
              if (subValue.isNotEmpty)
                Text(subValue, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.secondaryText)),
              const SizedBox(height: 4),
              Text(title.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.secondaryText, letterSpacing: 1)),
            ],
          ),
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Text(badge, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(BuildContext context, AppThemeColors c, String title, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.02), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c.primaryText),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecialOrdersList(BuildContext context, AppThemeColors c) {
    return Consumer<PharmacyProvider>(
      builder: (context, pharmacy, child) {
        final orders = pharmacy.specialOrders.take(6).toList();

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.02), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shopping_basket_outlined, color: Colors.blue.shade400, size: 18),
                  const SizedBox(width: 8),
                  Text("SPECIAL ORDERS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.secondaryText, letterSpacing: 1)),
                ],
              ),
              const SizedBox(height: 20),
              if (orders.isEmpty)
                Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text("No special orders found", style: TextStyle(fontSize: 12, color: c.secondaryText))))
              else
                ...orders.map((o) => _specialOrderItem(c, o['name'], o['qty'].toString(), o['customer'])),
            ],
          ),
        );
      },
    );
  }

  Widget _specialOrderItem(AppThemeColors c, String name, String qty, String customer) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
            child: Text(qty, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c.primaryText), overflow: TextOverflow.ellipsis),
                Text(customer, style: TextStyle(fontSize: 10, color: c.secondaryText)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLowStockAlert(BuildContext context, AppThemeColors c) {
    return Consumer<PharmacyProvider>(
      builder: (context, pharmacy, _) {
        final lowStockItems = pharmacy.lowStockItems;

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.02), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade400, size: 18),
                  const SizedBox(width: 8),
                  Text("LOW STOCK ALERT", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.secondaryText, letterSpacing: 1)),
                ],
              ),
              const SizedBox(height: 16),
              if (lowStockItems.isEmpty)
                Text("All inventory levels are optimal.", style: TextStyle(color: c.secondaryText, fontSize: 12))
              else
                ...lowStockItems.map((p) => _lowStockItem(c, "${p.name} (Stock: ${p.stock})")),
            ],
          ),
        );
      },
    );
  }

  Widget _lowStockItem(AppThemeColors c, String name) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(child: Text(name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.primaryText), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _buildRevenueTrend(BuildContext context, AppThemeColors c) {
    return Container(
      height: 300,
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("REVENUE TREND", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.secondaryText, letterSpacing: 1)),
              DropdownButton<String>(
                value: 'Last 7 Days',
                underline: const SizedBox(),
                dropdownColor: c.surface,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                items: ['Last 7 Days', 'Last 30 Days'].map((String value) {
                  return DropdownMenuItem<String>(value: value, child: Text(value, style: TextStyle(color: c.primaryText)));
                }).toList(),
                onChanged: (_) {},
              ),
            ],
          ),
          Expanded(child: Center(child: Icon(Icons.show_chart, size: 100, color: c.border))),
        ],
      ),
    );
  }
}
