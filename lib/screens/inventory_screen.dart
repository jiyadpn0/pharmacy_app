import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pharmacy_provider.dart';
import '../utils/theme_constants.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _currentFilterMode = 'ALL'; // 'ALL', 'LOW', 'EXPIRED', 'NEGATIVE'
  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedCategory = "All";

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _isExpired(String expiry) {
    if (expiry.isEmpty || expiry == "--/--") return false;
    try {
      final parts = expiry.split('/');
      if (parts.length == 2) {
        int month = int.parse(parts[0]);
        int year = int.parse(parts[1]);
        if (year < 100) year += 2000;
        final expDate = DateTime(year, month + 1, 0);
        return expDate.isBefore(DateTime.now());
      }
    } catch (_) {}
    return false;
  }

  Widget _sidebarFilterTile({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? color : Colors.blueGrey.shade300),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                  color: isSelected ? AppColors.primary : Colors.blueGrey.shade600,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pharmacy = Provider.of<PharmacyProvider>(context);
    final allProducts = pharmacy.productMaster;

    int allCount = allProducts.length;
    int lowStockCount = allProducts.where((p) => p.stock < 10 && p.stock >= 0).length;
    int expiredCount = allProducts.where((p) => _isExpired(p.expiry)).length;

    List<Product> allOtherFilteredProducts = allProducts.where((item) {
      if (_currentFilterMode == 'LOW') return item.stock <= item.reorderLevel && item.stock > 0;
      if (_currentFilterMode == 'EXPIRED') return _isExpired(item.expiry);

      if (_selectedCategory != "All" && item.category != _selectedCategory) return false;

      if (_searchCtrl.text.isNotEmpty) {
        final q = _searchCtrl.text.toLowerCase().trim();
        return item.name.toLowerCase().contains(q) ||
            item.genericName.toLowerCase().contains(q) ||
            item.rack.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    final displayedProducts = _currentFilterMode == 'NEGATIVE'
        ? pharmacy.negativeStockProducts
        : allOtherFilteredProducts;

    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 280,
            decoration: BoxDecoration(
              color: c.sidebarBg,
              border: Border(right: BorderSide(color: c.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.inventory_2_rounded, color: AppColors.accent, size: 24),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        "INVENTORY",
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("FILTER BY STATUS", style: AppStyles.label),
                        const SizedBox(height: 16),
                        _sidebarFilterTile(
                          icon: Icons.grid_view_rounded,
                          label: "All Inventory",
                          count: allCount,
                          color: AppColors.primary,
                          isSelected: _currentFilterMode == 'ALL',
                          onTap: () => setState(() => _currentFilterMode = 'ALL'),
                        ),
                        _sidebarFilterTile(
                          icon: Icons.warning_amber_rounded,
                          label: "Low Stock Items",
                          count: lowStockCount,
                          color: Colors.orange,
                          isSelected: _currentFilterMode == 'LOW',
                          onTap: () => setState(() => _currentFilterMode = 'LOW'),
                        ),
                        _sidebarFilterTile(
                          icon: Icons.event_busy_rounded,
                          label: "Expired Products",
                          count: expiredCount,
                          color: Colors.red,
                          isSelected: _currentFilterMode == 'EXPIRED',
                          onTap: () => setState(() => _currentFilterMode = 'EXPIRED'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.remove_circle_outline, color: Colors.red),
                          title: const Text("Negative Stock", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                          trailing: Consumer<PharmacyProvider>(
                            builder: (context, provider, _) {
                              int count = provider.negativeStockProducts.length;
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(10)),
                                child: Text("$count", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                              );
                            },
                          ),
                          onTap: () {
                            setState(() {
                              _currentFilterMode = 'NEGATIVE';
                            });
                          },
                        ),
                        const SizedBox(height: 30),
                        Text("CATEGORIES", style: AppStyles.label),
                        const SizedBox(height: 16),
                        ...pharmacy.categories
                            .where((c) => c != "General")
                            .map((cat) => InkWell(
                                  onTap: () => setState(() => _selectedCategory = cat),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    margin: const EdgeInsets.only(bottom: 4),
                                    decoration: BoxDecoration(
                                      color: _selectedCategory == cat ? Colors.white : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.medication_rounded, size: 16, color: Colors.blueGrey),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            cat,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: _selectedCategory == cat ? FontWeight.bold : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Main Content
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  color: Colors.white,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 350,
                        height: 38,
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: "Search by Product Name, Generic, Rack...",
                            prefixIcon: const Icon(Icons.search, size: 18),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(vertical: 0),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "${displayedProducts.length} Items Found",
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: displayedProducts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = displayedProducts[index];
                      final isNegative = item.stock < 0;
                      return Container(
                        color: isNegative ? Colors.red.shade50 : Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text("${item.genericName} • Rack: ${item.rack}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                "${item.stock} Units",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isNegative ? Colors.red : (item.stock < 10 ? Colors.orange : Colors.green),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text("₹${item.salePrice.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
