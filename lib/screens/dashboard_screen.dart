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
          body: LayoutBuilder(
            builder: (context, constraints) {
              final bool isNarrow = constraints.maxWidth < 1150;
              final bool isMobile = constraints.maxWidth < 800;
              final double outerPadding = isNarrow ? 16.0 : 24.0;

              return SingleChildScrollView(
                padding: EdgeInsets.all(outerPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, c, isNarrow),
                    SizedBox(height: isNarrow ? 16 : 24),
                    if (isMobile)
                      Column(
                        children: [
                          _buildLeftColumn(context, c, pharmacy, app, isNarrow),
                          const SizedBox(height: 20),
                          _buildRightColumn(context, c),
                        ],
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Column (Stats + Quick Actions + Revenue Trend)
                          Expanded(
                            child: _buildLeftColumn(context, c, pharmacy, app, isNarrow),
                          ),
                          SizedBox(width: isNarrow ? 12 : 20),
                          // Right Column (Special Orders + Low Stock Alert)
                          SizedBox(
                            width: isNarrow ? 260 : 300,
                            child: _buildRightColumn(context, c),
                          ),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, AppThemeColors c, bool isNarrow) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Welcome back, Administrator",
              style: TextStyle(fontSize: isNarrow ? 20 : 24, fontWeight: FontWeight.bold, color: c.primaryText),
            ),
            const SizedBox(height: 4),
            Text(
              "Here's what's happening with your pharmacy today.",
              style: TextStyle(fontSize: isNarrow ? 12 : 14, color: c.secondaryText),
            ),
          ],
        ),
        const Spacer(),
        Container(
          padding: EdgeInsets.symmetric(horizontal: isNarrow ? 12 : 20, vertical: isNarrow ? 8 : 12),
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
              const Icon(Icons.shield_outlined, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("System Status", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  Text("Backups up to date", style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 10)),
                ],
              ),
              if (!isNarrow) ...[
                const SizedBox(width: 16),
                Stack(
                  children: [
                    Container(width: 80, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(2))),
                    Container(width: 65, height: 4, decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(2))),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLeftColumn(BuildContext context, AppThemeColors c, PharmacyProvider pharmacy, AppProvider app, bool isNarrow) {
    return Column(
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
                "${pharmacy.todaySalesCount} Sales",
                "Today",
                Icons.assessment_outlined,
                Colors.blue,
                isNarrow: isNarrow,
              ),
            ),
            SizedBox(width: isNarrow ? 10 : 16),
            Expanded(
              child: _buildStatCard(
                context,
                c,
                "Today's Purchases",
                "₹ ${pharmacy.todayPurchase.toStringAsFixed(0)}",
                "${pharmacy.todayPurchasesCount} Orders",
                "Today",
                Icons.shopping_bag_outlined,
                Colors.green,
                isNarrow: isNarrow,
              ),
            ),
            SizedBox(width: isNarrow ? 10 : 16),
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
                isNarrow: isNarrow,
              ),
            ),
          ],
        ),
        SizedBox(height: isNarrow ? 20 : 28),
        Text(
          "QUICK ACTIONS",
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.secondaryText, letterSpacing: 1),
        ),
        const SizedBox(height: 12),
        _buildQuickActionsGrid(context, c, app, isNarrow),
        SizedBox(height: isNarrow ? 20 : 28),
        _buildRevenueTrend(context, c, isNarrow),
      ],
    );
  }

  Widget _buildRightColumn(BuildContext context, AppThemeColors c) {
    return Column(
      children: [
        _buildSpecialOrdersList(context, c),
        const SizedBox(height: 20),
        _buildLowStockAlert(context, c),
      ],
    );
  }

  Widget _buildStatCard(BuildContext context, AppThemeColors c, String title, String value, String subValue, String badge, IconData icon, Color color, {bool isNarrow = false}) {
    return Container(
      padding: EdgeInsets.all(isNarrow ? 14 : 20),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.02), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(isNarrow ? 6 : 8),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: isNarrow ? 18 : 22),
              ),
              SizedBox(height: isNarrow ? 12 : 16),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value, style: TextStyle(fontSize: isNarrow ? 22 : 26, fontWeight: FontWeight.bold, color: c.primaryText)),
              ),
              if (subValue.isNotEmpty)
                Text(subValue, style: TextStyle(fontSize: isNarrow ? 11 : 13, fontWeight: FontWeight.w600, color: c.secondaryText), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(title.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: c.secondaryText, letterSpacing: 0.8)),
            ],
          ),
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(badge, style: TextStyle(fontSize: isNarrow ? 9 : 10, fontWeight: FontWeight.bold, color: Colors.green)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsGrid(BuildContext context, AppThemeColors c, AppProvider app, bool isNarrow) {
    if (isNarrow) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildQuickAction(context, c, "New Sale", Icons.shopping_cart_outlined, Colors.blue, app.openSales, isNarrow: true)),
              const SizedBox(width: 10),
              Expanded(child: _buildQuickAction(context, c, "Purchase Entry", Icons.local_shipping_outlined, Colors.blueGrey, app.openPurchase, isNarrow: true)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildQuickAction(context, c, "Add Product", Icons.add_box_outlined, Colors.orange, app.openProductRegistration, isNarrow: true)),
              const SizedBox(width: 10),
              Expanded(child: _buildQuickAction(context, c, "Payments", Icons.account_balance_wallet_outlined, Colors.teal, app.openPayment, isNarrow: true)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildQuickAction(context, c, "Sales Report", Icons.bar_chart_outlined, Colors.indigo, app.openSalesReport, isNarrow: true)),
              const SizedBox(width: 10),
              Expanded(child: _buildQuickAction(context, c, "GST Filing", Icons.account_balance_outlined, Colors.purple, app.openGstReport, isNarrow: true)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildQuickAction(context, c, "Stock Ledger", Icons.menu_book_outlined, Colors.brown, app.openStockLedger, isNarrow: true)),
              const SizedBox(width: 10),
              Expanded(child: _buildQuickAction(context, c, "Customer Ledger", Icons.menu_book_rounded, Colors.blue, app.openCustomerLedger, isNarrow: true)),
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildQuickAction(context, c, "New Sale", Icons.shopping_cart_outlined, Colors.blue, app.openSales)),
            const SizedBox(width: 12),
            Expanded(child: _buildQuickAction(context, c, "Purchase Entry", Icons.local_shipping_outlined, Colors.blueGrey, app.openPurchase)),
            const SizedBox(width: 12),
            Expanded(child: _buildQuickAction(context, c, "Add Product", Icons.add_box_outlined, Colors.orange, app.openProductRegistration)),
            const SizedBox(width: 12),
            Expanded(child: _buildQuickAction(context, c, "Payments", Icons.account_balance_wallet_outlined, Colors.teal, app.openPayment)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildQuickAction(context, c, "Sales Report", Icons.bar_chart_outlined, Colors.indigo, app.openSalesReport)),
            const SizedBox(width: 12),
            Expanded(child: _buildQuickAction(context, c, "GST Filing", Icons.account_balance_outlined, Colors.purple, app.openGstReport)),
            const SizedBox(width: 12),
            Expanded(child: _buildQuickAction(context, c, "Stock Ledger", Icons.menu_book_outlined, Colors.brown, app.openStockLedger)),
            const SizedBox(width: 12),
            Expanded(child: _buildQuickAction(context, c, "Customer Ledger", Icons.menu_book_rounded, Colors.blue, app.openCustomerLedger)),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickAction(BuildContext context, AppThemeColors c, String title, IconData icon, Color color, VoidCallback onTap, {bool isNarrow = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: isNarrow ? 10 : 14, vertical: isNarrow ? 8 : 12),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.02), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(isNarrow ? 8 : 10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: isNarrow ? 22 : 26),
            ),
            SizedBox(width: isNarrow ? 8 : 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: isNarrow ? 13 : 15, fontWeight: FontWeight.w800, color: c.primaryText),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecialOrdersList(BuildContext context, AppThemeColors c) {
    final app = Provider.of<AppProvider>(context, listen: false);
    return Consumer<PharmacyProvider>(
      builder: (context, pharmacy, child) {
        final orders = pharmacy.specialOrders.take(6).toList();

        return Container(
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.border),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.02), blurRadius: 8, offset: const Offset(0, 3)),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: () => app.openSpecialOrders(),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shopping_basket_outlined, color: Colors.blue.shade400, size: 16),
                        const SizedBox(width: 8),
                        Text("SPECIAL ORDERS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.secondaryText, letterSpacing: 0.8)),
                        const Spacer(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("View All", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.blue.shade400)),
                            const SizedBox(width: 2),
                            Icon(Icons.chevron_right_rounded, size: 14, color: Colors.blue.shade400),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (orders.isEmpty)
                      Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text("No special orders found", style: TextStyle(fontSize: 11, color: c.secondaryText))))
                    else
                      ...orders.map((o) => _specialOrderItem(c, o['name'], o['qty'].toString(), o['customer'])),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _specialOrderItem(AppThemeColors c, String name, String qty, String customer) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
            child: Text(qty, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.primaryText), overflow: TextOverflow.ellipsis),
                Text(customer, style: TextStyle(fontSize: 10, color: c.secondaryText)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLowStockAlert(BuildContext context, AppThemeColors c) {
    final app = Provider.of<AppProvider>(context, listen: false);
    return Consumer<PharmacyProvider>(
      builder: (context, pharmacy, _) {
        final lowStockItems = pharmacy.lowStockItems;

        return Container(
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.border),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.02), blurRadius: 8, offset: const Offset(0, 3)),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: () => app.openOrderBook(),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.orange.shade400, size: 16),
                        const SizedBox(width: 8),
                        Text("LOW STOCK ALERT", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.secondaryText, letterSpacing: 0.8)),
                        const Spacer(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("Open Order Book", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.orange.shade400)),
                            const SizedBox(width: 2),
                            Icon(Icons.chevron_right_rounded, size: 14, color: Colors.orange.shade400),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (lowStockItems.isEmpty)
                      Text("All inventory levels are optimal.", style: TextStyle(color: c.secondaryText, fontSize: 11))
                    else
                      ...lowStockItems.map((p) => _lowStockItem(c, "${p.name} (Stock: ${p.stock})")),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _lowStockItem(AppThemeColors c, String name) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.primaryText), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _buildRevenueTrend(BuildContext context, AppThemeColors c, bool isNarrow) {
    return Container(
      height: isNarrow ? 240 : 280,
      width: double.infinity,
      padding: EdgeInsets.all(isNarrow ? 16 : 20),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.02), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("REVENUE TREND", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.secondaryText, letterSpacing: 0.8)),
              DropdownButton<String>(
                value: 'Last 7 Days',
                underline: const SizedBox(),
                dropdownColor: c.surface,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue),
                items: ['Last 7 Days', 'Last 30 Days'].map((String value) {
                  return DropdownMenuItem<String>(value: value, child: Text(value, style: TextStyle(color: c.primaryText)));
                }).toList(),
                onChanged: (_) {},
              ),
            ],
          ),
          Expanded(child: Center(child: Icon(Icons.show_chart, size: isNarrow ? 70 : 90, color: c.border))),
        ],
      ),
    );
  }
}
