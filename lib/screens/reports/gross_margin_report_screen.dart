import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/pharmacy_provider.dart';

class GrossMarginReportScreen extends StatefulWidget {
  const GrossMarginReportScreen({super.key});

  @override
  State<GrossMarginReportScreen> createState() => _GrossMarginReportScreenState();
}

class _GrossMarginReportScreenState extends State<GrossMarginReportScreen> {

  @override
  Widget build(BuildContext context) {
    final pharma = Provider.of<PharmacyProvider>(context);

    // Dynamic category breakdown from productMaster
    final Map<String, int> categoryCounts = {};
    final Map<String, double> categoryStockValues = {};

    for (var p in pharma.productMaster) {
      final cat = p.category.trim().isEmpty ? "Uncategorized" : p.category.trim().toUpperCase();
      categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
      categoryStockValues[cat] = (categoryStockValues[cat] ?? 0.0) + (p.stock * p.mrp);
    }

    final categories = categoryCounts.keys.toList()..sort();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Gross Margin & Category Profitability Report", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.purple.shade900,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(categories.length),
            const SizedBox(height: 16),
            Expanded(
              child: categories.isEmpty
                  ? const Center(child: Text("No product categories found in inventory.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)))
                  : ListView.builder(
                      itemCount: categories.length,
                      itemBuilder: (ctx, i) {
                        final catName = categories[i];
                        final itemCount = categoryCounts[catName] ?? 0;
                        final stockVal = categoryStockValues[catName] ?? 0.0;
                        final estMargin = catName.contains("GENERIC") ? 45.0 : (catName.contains("SURGICAL") ? 35.0 : 20.0);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _marginCard(
                            catName,
                            "$itemCount Products • Stock Val: ₹ ${stockVal.toStringAsFixed(2)}",
                            "~${estMargin.toStringAsFixed(1)}% Est. Margin",
                            Colors.purple.shade800,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(int totalCats) {
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
      child: Row(
        children: [
          const Icon(Icons.pie_chart_outline_rounded, color: Colors.purple, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Gross Margin % Breakdown by Drug Category", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A))),
              Text("Total Active Categories: $totalCats Categories", style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _marginCard(String category, String subtitle, String margin, Color color) {
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(category, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
            ],
          ),
          Text(margin, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: color)),
        ],
      ),
    );
  }
}
