import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../providers/pharmacy_provider.dart';

class BusinessAnalyticsScreen extends StatefulWidget {
  const BusinessAnalyticsScreen({super.key});

  @override
  State<BusinessAnalyticsScreen> createState() => _BusinessAnalyticsScreenState();
}

class _BusinessAnalyticsScreenState extends State<BusinessAnalyticsScreen> {
  bool _isLoading = true;
  double _monthlySales = 0.0;
  double _monthlyCost = 0.0;
  List<double> _monthlyTrend = [0, 0, 0, 0, 0, 0];
  List<String> _monthLabels = [];

  @override
  void initState() {
    super.initState();
    _fetchAnalyticsData();
  }

  Future<void> _fetchAnalyticsData() async {
    setState(() => _isLoading = true);
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);

    final now = DateTime.now();
    final startOfCurrentMonth = DateTime(now.year, now.month, 1);
    final endOfCurrentMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    final currentMonthSales = await pharma.fetchSalesInDateRange(
      startOfCurrentMonth,
      endOfCurrentMonth,
      loadItems: false,
      limit: 5000,
      offset: 0,
    );

    double totalSales = 0.0;
    for (var s in currentMonthSales) {
      if (!s.isDeleted) {
        totalSales += s.grandTotal;
      }
    }

    // Compute 6-Month Trend
    List<double> trend = [];
    List<String> labels = [];
    for (int i = 5; i >= 0; i--) {
      final mDate = DateTime(now.year, now.month - i, 1);
      final mEnd = DateTime(mDate.year, mDate.month + 1, 0, 23, 59, 59);
      final mSales = await pharma.fetchSalesInDateRange(mDate, mEnd, loadItems: false, limit: 5000, offset: 0);
      double sum = 0.0;
      for (var s in mSales) {
        if (!s.isDeleted) sum += s.grandTotal;
      }
      trend.add(sum);
      labels.add(DateFormat('MMM').format(mDate));
    }

    if (mounted) {
      setState(() {
        _monthlySales = totalSales;
        _monthlyCost = totalSales * 0.78; // Approx cost baseline
        _monthlyTrend = trend;
        _monthLabels = labels;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pharma = Provider.of<PharmacyProvider>(context);
    final activeProducts = pharma.productMaster.length;
    final pendingOrders = pharma.specialOrders.where((o) => (o['status']?.toString().toUpperCase() ?? '') == 'PENDING').length;

    double marginPercent = _monthlySales > 0 ? ((_monthlySales - _monthlyCost) / _monthlySales) * 100 : 22.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Business Intelligence & Financial Analytics", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchAnalyticsData,
            tooltip: "Refresh Analytics",
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildKpiRow(activeProducts, pendingOrders, marginPercent),
                    const SizedBox(height: 20),
                    _buildSalesTrendChartCard(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildKpiRow(int activeProducts, int pendingOrders, double marginPercent) {
    return Row(
      children: [
        Expanded(child: _kpiCard("Monthly Sales", "₹ ${_monthlySales.toStringAsFixed(2)}", Colors.blue.shade900)),
        const SizedBox(width: 12),
        Expanded(child: _kpiCard("Gross Profit Margin", "${marginPercent.toStringAsFixed(1)}%", Colors.green.shade800)),
        const SizedBox(width: 12),
        Expanded(child: _kpiCard("Active Products", "$activeProducts Items", Colors.purple.shade800)),
        const SizedBox(width: 12),
        Expanded(child: _kpiCard("Pending Re-Orders", "$pendingOrders Orders", Colors.orange.shade900)),
      ],
    );
  }

  Widget _kpiCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }

  Widget _buildSalesTrendChartCard() {
    List<FlSpot> spots = [];
    for (int i = 0; i < _monthlyTrend.length; i++) {
      spots.add(FlSpot(i.toDouble(), _monthlyTrend[i]));
    }

    return Container(
      height: 340,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("6-Month Revenue & Sales Trend", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              Text("Total 6M Revenue: ₹ ${_monthlyTrend.fold(0.0, (a, b) => a + b).toStringAsFixed(2)}", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: true),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, meta) {
                        int idx = val.toInt();
                        if (idx >= 0 && idx < _monthLabels.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(_monthLabels[idx], style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade300)),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: Colors.indigo.shade700,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
