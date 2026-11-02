import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../providers/app_provider.dart';
import '../providers/pharmacy_provider.dart';
import '../services/server_config_service.dart';
import '../services/supabase_sync_service.dart';
import '../utils/theme_constants.dart';
import 'server_settings_screen.dart';

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
              final double screenWidth = constraints.maxWidth;
              // Fluid breakpoints for seamless responsiveness across all monitor scales & resolutions
              final bool isMedium = screenWidth >= 800 && screenWidth < 1280;
              final bool isNarrow = screenWidth < 800;

              final double outerPadding = isNarrow ? 12.0 : (isMedium ? 16.0 : 20.0);

              return SingleChildScrollView(
                padding: EdgeInsets.all(outerPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, c, isNarrow || isMedium),
                    SizedBox(height: isNarrow ? 12 : 18),
                    if (screenWidth >= 1280)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 7,
                            child: _buildLeftColumn(context, c, pharmacy, app, screenWidth),
                          ),
                          const SizedBox(width: 20),
                          SizedBox(
                            width: 330,
                            child: _buildRightColumn(context, c),
                          ),
                        ],
                      )
                    else ...[
                      _buildLeftColumn(context, c, pharmacy, app, screenWidth),
                      const SizedBox(height: 18),
                      _buildRightColumn(context, c),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, AppThemeColors c, bool isCompact) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Welcome back, Administrator",
                style: TextStyle(
                  fontSize: isCompact ? 20 : 24,
                  fontWeight: FontWeight.bold,
                  color: c.primaryText,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                "Here's what's happening with your pharmacy today.",
                style: TextStyle(
                  fontSize: isCompact ? 12 : 14,
                  color: c.secondaryText,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // ORDER BOOK BUTTON (ALWAYS SHOWN ON HOME SCREEN LEFT OF SYSTEM STATUS)
        Builder(
          builder: (context) {
            final pharmacy = Provider.of<PharmacyProvider>(context);
            final int totalCount = pharmacy.specialOrders.length + pharmacy.lowStockItems.length;
            final bool isOpen = pharmacy.isOrderPanelOpen;

            return InkWell(
              onTap: () => pharmacy.openOrderPanel(),
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isOpen
                      ? (c.isDark ? const Color(0xFF0F172A) : const Color(0xFFF0FDF4))
                      : (c.isDark ? const Color(0xFF1E293B) : Colors.white),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isOpen
                        ? Colors.teal.shade600
                        : (totalCount > 0 ? Colors.amber.shade700 : Colors.teal),
                    width: isOpen ? 2.0 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isOpen
                              ? Colors.teal
                              : (totalCount > 0 ? Colors.amber : Colors.black))
                          .withValues(alpha: isOpen ? 0.25 : 0.1),
                      blurRadius: isOpen ? 8 : 6,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.shopping_cart_outlined,
                      size: 18,
                      color: isOpen
                          ? Colors.teal.shade600
                          : (totalCount > 0 ? Colors.amber.shade700 : Colors.teal),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "ORDER BOOK",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: c.isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: totalCount > 0 ? Colors.amber.shade800 : Colors.teal.shade700,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "$totalCount",
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 12),
        _SystemStatusPillWidget(
          isCompact: isCompact,
          c: c,
        ),
      ],
    );
  }

  Widget _buildLeftColumn(BuildContext context, AppThemeColors c, PharmacyProvider pharmacy, AppProvider app, double width) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Responsive Stats Row
        _buildStatCardsRow(context, c, pharmacy, width),
        SizedBox(height: width < 900 ? 16 : 24),
        Container(
          padding: EdgeInsets.all(width < 900 ? 12 : 16),
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.dashboard_customize_outlined, size: 18, color: AppColors.secondary),
                  const SizedBox(width: 8),
                  Text(
                    "CORE WORKFLOWS & SHORTCUTS",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: c.primaryText,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    "Quick Access Station",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: c.secondaryText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: c.border),
              const SizedBox(height: 14),
              _buildQuickActionsGrid(context, c, app, width),
            ],
          ),
        ),
        SizedBox(height: width < 900 ? 16 : 24),
        RevenueTrendCard(
          c: c,
          isCompact: width < 900,
          todayRevenue: pharmacy.todayRevenue,
        ),
      ],
    );
  }

  Widget _buildStatCardsRow(BuildContext context, AppThemeColors c, PharmacyProvider pharmacy, double width) {
    final card1 = _buildStatCard(
      context,
      c,
      "Today's Sales",
      "₹ ${pharmacy.todayRevenue.toStringAsFixed(0)}",
      "${pharmacy.todaySalesCount} Sales",
      "Today",
      Icons.assessment_outlined,
      Colors.blue,
      isCompact: width < 1100,
    );

    final card2 = _buildStatCard(
      context,
      c,
      "Today's Purchases",
      "₹ ${pharmacy.todayPurchase.toStringAsFixed(0)}",
      "${pharmacy.todayPurchasesCount} Orders",
      "Today",
      Icons.shopping_bag_outlined,
      Colors.green,
      isCompact: width < 1100,
    );

    final card3 = _buildStatCard(
      context,
      c,
      "Stock Value",
      pharmacy.totalStockValue > 1000
          ? "${(pharmacy.totalStockValue / 1000).toStringAsFixed(1)}K+"
          : "₹ ${pharmacy.totalStockValue.toStringAsFixed(0)}",
      "${pharmacy.totalStockCount} Items",
      "Across ${pharmacy.racks.length} Racks",
      Icons.inventory_2_outlined,
      Colors.teal,
      isCompact: width < 1100,
    );

    if (width < 700) {
      return Column(
        children: [
          card1,
          const SizedBox(height: 10),
          card2,
          const SizedBox(height: 10),
          card3,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: card1),
        const SizedBox(width: 12),
        Expanded(child: card2),
        const SizedBox(width: 12),
        Expanded(child: card3),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    AppThemeColors c,
    String title,
    String value,
    String subValue,
    String badge,
    IconData icon,
    Color color, {
    bool isCompact = false,
  }) {
    return Container(
      padding: EdgeInsets.all(isCompact ? 12 : 16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // 3px Left Vertical Accent Bar
          Container(
            width: 4,
            height: isCompact ? 56 : 68,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: isCompact ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: EdgeInsets.all(isCompact ? 6 : 8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: color, size: isCompact ? 18 : 20),
                    ),
                    if (badge.isNotEmpty)
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              fontSize: isCompact ? 9 : 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: isCompact ? 8 : 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: isCompact ? 20 : 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: c.primaryText,
                    ),
                  ),
                ),
                if (subValue.isNotEmpty)
                  Text(
                    subValue,
                    style: TextStyle(
                      fontSize: isCompact ? 11 : 12,
                      fontWeight: FontWeight.w600,
                      color: c.secondaryText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 4),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: c.secondaryText,
                    letterSpacing: 0.8,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsGrid(BuildContext context, AppThemeColors c, AppProvider app, double width) {
    final bool isCompact = width < 1100;

    final a1 = _QuickActionTile(context: context, c: c, title: "New Sale", subtext: "Counter POS Billing", icon: Icons.shopping_cart_outlined, color: Colors.blue, onTap: app.openSales, isCompact: isCompact);
    final a2 = _QuickActionTile(context: context, c: c, title: "Purchase Entry", subtext: "Stock Inward Invoice", icon: Icons.local_shipping_outlined, color: Colors.blueGrey, onTap: app.openPurchase, isCompact: isCompact);
    final a3 = _QuickActionTile(context: context, c: c, title: "Add Product", subtext: "Master Catalog", icon: Icons.add_box_outlined, color: Colors.orange, onTap: app.openProductRegistration, isCompact: isCompact);
    final a4 = _QuickActionTile(context: context, c: c, title: "Payments", subtext: "Supplier & Patient", icon: Icons.account_balance_wallet_outlined, color: Colors.teal, onTap: app.openPayment, isCompact: isCompact);
    final a5 = _QuickActionTile(context: context, c: c, title: "Sales Report", subtext: "Sales Analytics", icon: Icons.bar_chart_outlined, color: Colors.indigo, onTap: app.openSalesReport, isCompact: isCompact);
    final a6 = _QuickActionTile(context: context, c: c, title: "GST Filing", subtext: "GST Returns & Tax", icon: Icons.account_balance_outlined, color: Colors.purple, onTap: app.openGstReport, isCompact: isCompact);
    final a7 = _QuickActionTile(context: context, c: c, title: "Stock Ledger", subtext: "Batch Movements", icon: Icons.menu_book_outlined, color: Colors.brown, onTap: app.openStockLedger, isCompact: isCompact);
    final a8 = _QuickActionTile(context: context, c: c, title: "Customer Ledger", subtext: "Party Accounts", icon: Icons.menu_book_rounded, color: Colors.blue, onTap: app.openCustomerLedger, isCompact: isCompact);

    if (width < 650) {
      return Column(
        children: [
          a1, const SizedBox(height: 8),
          a2, const SizedBox(height: 8),
          a3, const SizedBox(height: 8),
          a4, const SizedBox(height: 8),
          a5, const SizedBox(height: 8),
          a6, const SizedBox(height: 8),
          a7, const SizedBox(height: 8),
          a8,
        ],
      );
    }

    if (width < 1100) {
      return Column(
        children: [
          Row(children: [Expanded(child: a1), const SizedBox(width: 10), Expanded(child: a2)]),
          const SizedBox(height: 10),
          Row(children: [Expanded(child: a3), const SizedBox(width: 10), Expanded(child: a4)]),
          const SizedBox(height: 10),
          Row(children: [Expanded(child: a5), const SizedBox(width: 10), Expanded(child: a6)]),
          const SizedBox(height: 10),
          Row(children: [Expanded(child: a7), const SizedBox(width: 10), Expanded(child: a8)]),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: a1), const SizedBox(width: 12),
            Expanded(child: a2), const SizedBox(width: 12),
            Expanded(child: a3), const SizedBox(width: 12),
            Expanded(child: a4),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: a5), const SizedBox(width: 12),
            Expanded(child: a6), const SizedBox(width: 12),
            Expanded(child: a7), const SizedBox(width: 12),
            Expanded(child: a8),
          ],
        ),
      ],
    );
  }





  Widget _buildRightColumn(BuildContext context, AppThemeColors c) {
    final app = Provider.of<AppProvider>(context, listen: false);
    return Consumer<PharmacyProvider>(
      builder: (context, pharmacy, _) {
        final orders = pharmacy.specialOrders.take(6).toList();
        final lowStockItems = pharmacy.lowStockItems.take(6).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // SPECIAL ORDERS
            Container(
              decoration: BoxDecoration(
                color: c.cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
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
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                "SPECIAL ORDERS",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: c.secondaryText,
                                  letterSpacing: 0.5,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
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
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text("No special orders found", style: TextStyle(fontSize: 11, color: c.secondaryText)),
                            ),
                          )
                        else
                          ...orders.map((o) => _specialOrderItem(c, o['name'], o['qty'].toString(), o['customer'])),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // LOW STOCK ALERT
            Container(
              decoration: BoxDecoration(
                color: c.cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
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
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                "LOW STOCK ALERT",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: c.secondaryText,
                                  letterSpacing: 0.5,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text("Order Book", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.orange.shade400)),
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
            ),
          ],
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
            width: 6,
            height: 6,
            decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.primaryText),
                  overflow: TextOverflow.ellipsis,
                ),
                if (customer.isNotEmpty)
                  Text(
                    "Customer: $customer",
                    style: TextStyle(fontSize: 10, color: c.secondaryText),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              "Qty: $qty",
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lowStockItem(AppThemeColors c, String name) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.primaryText),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

}

class RevenueTrendCard extends StatefulWidget {
  final AppThemeColors c;
  final bool isCompact;
  final double todayRevenue;

  const RevenueTrendCard({
    super.key,
    required this.c,
    required this.isCompact,
    required this.todayRevenue,
  });

  @override
  State<RevenueTrendCard> createState() => _RevenueTrendCardState();
}

class _RevenueTrendCardState extends State<RevenueTrendCard> {
  String _selectedRange = 'Last 7 Days';
  bool _isLoading = true;
  List<double> _dailyRevenues = [];
  List<String> _dayLabels = [];
  List<String> _fullDateLabels = [];
  double _totalRevenue = 0.0;
  double _maxRevenue = 0.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant RevenueTrendCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.todayRevenue != widget.todayRevenue) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);
    final int days = _selectedRange == 'Last 7 Days' ? 7 : 30;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDate = today.subtract(Duration(days: days - 1));
    final endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final sales = await pharmacy.fetchSalesInDateRange(
      startDate,
      endDate,
      loadItems: false,
    );

    final Map<String, double> revenueByDate = {};
    final List<String> dayLabels = [];
    final List<String> fullDateLabels = [];
    final List<String> dateKeys = [];

    final DateFormat keyFormatter = DateFormat('yyyy-MM-dd');
    final DateFormat dayLabelFormatter = days == 7 ? DateFormat('EEE') : DateFormat('d MMM');
    final DateFormat fullDateFormatter = DateFormat('dd MMM yyyy');

    for (int i = 0; i < days; i++) {
      final date = startDate.add(Duration(days: i));
      final key = keyFormatter.format(date);
      dateKeys.add(key);
      revenueByDate[key] = 0.0;
      dayLabels.add(dayLabelFormatter.format(date));
      fullDateLabels.add(fullDateFormatter.format(date));
    }

    for (var sale in sales) {
      if (!sale.isDeleted) {
        final key = keyFormatter.format(sale.date);
        if (revenueByDate.containsKey(key)) {
          revenueByDate[key] = (revenueByDate[key] ?? 0.0) + sale.grandTotal;
        }
      }
    }

    final List<double> dailyRevenues = dateKeys.map((k) => revenueByDate[k] ?? 0.0).toList();
    final double total = dailyRevenues.fold(0.0, (sum, val) => sum + val);
    double maxVal = dailyRevenues.fold(0.0, (max, val) => val > max ? val : max);
    if (maxVal <= 0) maxVal = 1000.0;

    if (mounted) {
      setState(() {
        _dailyRevenues = dailyRevenues;
        _dayLabels = dayLabels;
        _fullDateLabels = fullDateLabels;
        _totalRevenue = total;
        _maxRevenue = maxVal;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final isCompact = widget.isCompact;
    final NumberFormat currencyFormat = NumberFormat.currency(symbol: '₹ ', decimalDigits: 0);

    return Container(
      height: isCompact ? 250 : 280,
      width: double.infinity,
      padding: EdgeInsets.all(isCompact ? 12 : 16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.trending_up_rounded, size: 16, color: Colors.blue.shade600),
                  const SizedBox(width: 6),
                  Text(
                    "REVENUE TREND",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: c.secondaryText,
                      letterSpacing: 0.8,
                    ),
                  ),
                  if (!_isLoading) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: c.isDark ? 0.2 : 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        "Total: ${currencyFormat.format(_totalRevenue)}",
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: c.isDark ? Colors.blue.shade300 : Colors.blue.shade800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, size: 16, color: c.secondaryText),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: "Refresh trend data",
                    onPressed: _loadData,
                  ),
                  const SizedBox(width: 8),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedRange,
                      dropdownColor: c.surface,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: c.isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                      ),
                      items: ['Last 7 Days', 'Last 30 Days'].map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value, style: TextStyle(color: c.primaryText, fontSize: 11)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null && val != _selectedRange) {
                          setState(() {
                            _selectedRange = val;
                          });
                          _loadData();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _isLoading
                ? Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue.shade600),
                    ),
                  )
                : _buildChart(c),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(AppThemeColors c) {
    if (_dailyRevenues.isEmpty) {
      return Center(
        child: Text("No revenue data available", style: TextStyle(color: c.secondaryText, fontSize: 12)),
      );
    }

    final List<FlSpot> spots = [];
    for (int i = 0; i < _dailyRevenues.length; i++) {
      spots.add(FlSpot(i.toDouble(), _dailyRevenues[i]));
    }

    final is7Days = _selectedRange == 'Last 7 Days';
    final int step = is7Days ? 1 : 5;

    final lineColor = c.isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);
    final gradientColors = [
      lineColor.withValues(alpha: c.isDark ? 0.35 : 0.25),
      lineColor.withValues(alpha: 0.0),
    ];

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _maxRevenue > 0 ? _maxRevenue / 3 : 1,
          getDrawingHorizontalLine: (value) => FlLine(
            color: c.border.withValues(alpha: 0.5),
            strokeWidth: 0.8,
            dashArray: [4, 4],
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (value, meta) {
                if (value == meta.max || value == meta.min) {
                  return const SizedBox.shrink();
                }
                String text;
                if (value >= 100000) {
                  text = '${(value / 100000).toStringAsFixed(1)}L';
                } else if (value >= 1000) {
                  text = '${(value / 1000).toStringAsFixed(0)}k';
                } else {
                  text = value.toInt().toString();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    '₹$text',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: c.secondaryText,
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, meta) {
                int index = value.toInt();
                if (index < 0 || index >= _dayLabels.length) {
                  return const SizedBox.shrink();
                }
                if (!is7Days && (index % step != 0) && index != _dayLabels.length - 1) {
                  return const SizedBox.shrink();
                }

                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    _dayLabels[index],
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: c.secondaryText,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minY: 0,
        maxY: _maxRevenue * 1.15,
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => c.isDark ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
            tooltipRoundedRadius: 8,
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                int idx = spot.x.toInt();
                String dateStr = (idx >= 0 && idx < _fullDateLabels.length) ? _fullDateLabels[idx] : '';
                double val = spot.y;
                final formattedVal = NumberFormat.currency(symbol: '₹ ', decimalDigits: 0).format(val);
                return LineTooltipItem(
                  '$dateStr\n',
                  TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  children: [
                    TextSpan(
                      text: formattedVal,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                );
              }).toList();
            },
          ),
          handleBuiltInTouches: true,
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: lineColor,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: is7Days ? 3.5 : 2.0,
                  color: lineColor,
                  strokeWidth: 1.5,
                  strokeColor: c.cardBg,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatefulWidget {
  final BuildContext context;
  final AppThemeColors c;
  final String title;
  final String subtext;
  final String hotkey;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isCompact;

  const _QuickActionTile({
    required this.context,
    required this.c,
    required this.title,
    required this.subtext,
    required this.icon,
    required this.color,
    required this.onTap,
    this.isCompact = false,
  }) : hotkey = '';

  @override
  State<_QuickActionTile> createState() => _QuickActionTileState();
}

class _QuickActionTileState extends State<_QuickActionTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final isDark = c.isDark;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: _isHovered
              ? widget.color.withValues(alpha: isDark ? 0.15 : 0.05)
              : c.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isHovered
                ? widget.color.withValues(alpha: 0.6)
                : c.border,
            width: _isHovered ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: (_isHovered ? widget.color : Colors.black).withValues(alpha: _isHovered ? (isDark ? 0.25 : 0.08) : (isDark ? 0.2 : 0.02)),
              blurRadius: _isHovered ? 12 : 6,
              offset: Offset(0, _isHovered ? 4 : 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.isCompact ? 10 : 14,
                vertical: widget.isCompact ? 10 : 12,
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(widget.isCompact ? 8 : 10),
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: isDark ? 0.2 : 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(widget.icon, color: widget.color, size: widget.isCompact ? 20 : 22),
                  ),
                  SizedBox(width: widget.isCompact ? 8 : 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: widget.isCompact ? 12 : 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.1,
                            color: c.primaryText,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.subtext.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.subtext,
                            style: TextStyle(
                              fontSize: widget.isCompact ? 10 : 11,
                              fontWeight: FontWeight.w600,
                              color: c.secondaryText,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.hotkey.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.border),
                      ),
                      child: Text(
                        widget.hotkey,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: c.secondaryText,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SystemStatusPillWidget extends StatefulWidget {
  final bool isCompact;
  final AppThemeColors c;

  const _SystemStatusPillWidget({
    required this.isCompact,
    required this.c,
  });

  @override
  State<_SystemStatusPillWidget> createState() => _SystemStatusPillWidgetState();
}

class _SystemStatusPillWidgetState extends State<_SystemStatusPillWidget>
    with TickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _animValue;

  late AnimationController _entranceCtrl;
  late Animation<double> _entranceScale;
  late Animation<double> _entranceFade;

  late AnimationController _syncRotateCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _animValue = CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut);

    // Spring entrance animation for the tick on opening
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _entranceScale = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.elasticOut,
    );
    _entranceFade = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
    );
    _entranceCtrl.forward();

    _syncRotateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _entranceCtrl.dispose();
    _syncRotateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final isCompact = widget.isCompact;

    return ListenableBuilder(
      listenable: Listenable.merge([
        ServerConfigService.instance,
        SupabaseSyncService.instance,
        _animCtrl,
        _entranceCtrl,
      ]),
      builder: (context, _) {
        final serverConfig = ServerConfigService.instance;
        final syncService = SupabaseSyncService.instance;

        final bool isServerMode = serverConfig.isServerModeEnabled;
        final bool isConnected = serverConfig.isConnected;
        final bool isSyncing = syncService.isSyncing;

        const Color activeGreen = Color(0xFF00FF88); // Lightning Green
        const Color diamondGreen = Color(0xFF00F5D4); // Diamond Cyan Green
        const Color disconnectedRed = Color(0xFFFF334B); // Vibrant Red
        const Color offlineBlue = Color(0xFF38BDF8); // Standalone Blue

        final Color themeBgColor = c.isDark ? const Color(0xFF0F172A) : const Color(0xFF1E293B);
        Color statusColor;
        String statusTitle = "System Status";
        String statusSubtitle;

        if (!isServerMode) {
          statusColor = offlineBlue;
          statusSubtitle = "Local Standalone Mode";
        } else if (isConnected) {
          statusColor = activeGreen;
          final lastSyncStr = syncService.lastSyncTime != null
              ? DateFormat('hh:mm a').format(syncService.lastSyncTime!)
              : 'Just now';
          statusSubtitle = isSyncing ? "Syncing..." : "Server Active • $lastSyncStr";
        } else {
          statusColor = disconnectedRed;
          statusSubtitle = "Server Disconnected";
        }

        // Dynamic running animation interpolation for connected active mode
        final double t = _animValue.value;
        final double sineVal = (math.sin(t * math.pi)).abs();
        final Color currentShineColor = (isConnected && isServerMode)
            ? Color.lerp(
                Color.lerp(activeGreen, diamondGreen, t)!,
                Colors.white,
                sineVal * 0.45,
              )!
            : statusColor;

        final bool isOK = isConnected || !isServerMode;

        return InkWell(
          onTap: () => Provider.of<AppProvider>(context, listen: false)
              .addTab("SERVER SETTINGS", const ServerSettingsScreen()),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 14 : 20,
              vertical: isCompact ? 10 : 12,
            ),
            decoration: BoxDecoration(
              color: themeBgColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: (isConnected && isServerMode)
                    ? currentShineColor
                    : statusColor.withValues(alpha: 0.7),
                width: 2.5, // Increased thickness for prominent border line shine
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Crisp Metallic Badge with Shield (NO fuzzy glow)
                Builder(
                  builder: (context) {
                    final double scale = _entranceScale.value;
                    final double opacity = _entranceFade.value.clamp(0.0, 1.0);

                    final double badgeSize = isCompact ? 36.0 : 40.0;
                    final double shieldSize = isCompact ? 22.0 : 25.0;
                    final double tickSize = isCompact ? 13.0 : 15.0;

                    return Transform.scale(
                      scale: scale,
                      child: Opacity(
                        opacity: opacity,
                        child: SizedBox(
                          width: badgeSize,
                          height: badgeSize,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // 1. Opening expansion aura ring (sharp line, no blur)
                              if (_entranceCtrl.isAnimating && _entranceCtrl.value < 0.9)
                                Transform.scale(
                                  scale: 1.0 + ((1.0 - _entranceCtrl.value) * 0.9),
                                  child: Container(
                                    width: badgeSize,
                                    height: badgeSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: statusColor.withValues(
                                          alpha: (0.9 - _entranceCtrl.value).clamp(0.0, 0.8),
                                        ),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),

                              // 2. Syncing Orbiting Particle Ring
                              if (isSyncing)
                                AnimatedBuilder(
                                  animation: _syncRotateCtrl,
                                  builder: (context, _) {
                                    return Transform.rotate(
                                      angle: _syncRotateCtrl.value * 2 * math.pi,
                                      child: Container(
                                        width: badgeSize + 2,
                                        height: badgeSize + 2,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: activeGreen.withValues(alpha: 0.35),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Align(
                                          alignment: Alignment.topCenter,
                                          child: Container(
                                            width: 5,
                                            height: 5,
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: diamondGreen,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),

                              // 3. Crisp Inner Shield Surface with Thicker Matching Border Shine
                              Container(
                                width: badgeSize,
                                height: badgeSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF0B1329),
                                  border: Border.all(
                                    color: (isConnected && isServerMode)
                                        ? currentShineColor
                                        : statusColor,
                                    width: 2.0, // Thicker matching border shine
                                  ),
                                ),
                                child: Center(
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Dynamic Metallic Shield Icon with border shine matching gradient
                                      ShaderMask(
                                        shaderCallback: (bounds) => LinearGradient(
                                          colors: [
                                            statusColor,
                                            isOK ? currentShineColor : statusColor,
                                            isOK ? diamondGreen : statusColor,
                                          ],
                                          stops: const [0.0, 0.5, 1.0],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ).createShader(bounds),
                                        child: Icon(
                                          Icons.shield_rounded,
                                          color: Colors.white,
                                          size: shieldSize,
                                        ),
                                      ),

                                      // Crisp High-Contrast Inner Tick / Cross Icon
                                      Padding(
                                        padding: const EdgeInsets.only(top: 1.5),
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            // Drop shadow outline for checkmark clarity
                                            Icon(
                                              isOK ? Icons.check_rounded : Icons.close_rounded,
                                              color: Colors.black.withValues(alpha: 0.9),
                                              size: tickSize + 2.0,
                                            ),
                                            // Crisp checkmark
                                            Icon(
                                              isOK ? Icons.check_rounded : Icons.close_rounded,
                                              color: const Color(0xFF070C18),
                                              size: tickSize,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      statusTitle,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isCompact ? 12 : 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusSubtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: isCompact ? 10 : 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (!isCompact) ...[
                  const SizedBox(width: 18),
                  // Premium Metallic Status Line with matching shine
                  Stack(
                    children: [
                      // Background track
                      Container(
                        width: 80,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                            width: 0.5,
                          ),
                        ),
                      ),
                      // Active bar with matching shine transition
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          width: isOK ? 80 : 30,
                          height: 6,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            gradient: LinearGradient(
                              colors: [
                                statusColor,
                                isOK ? currentShineColor : statusColor,
                                isOK ? diamondGreen : statusColor,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
