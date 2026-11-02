import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import '../providers/pharmacy_provider.dart';
import '../providers/app_provider.dart';
import '../widgets/app_strict_autocomplete.dart';
import '../utils/app_dialogs.dart';

class SplitOrderDrawer extends StatefulWidget {
  const SplitOrderDrawer({super.key});

  @override
  State<SplitOrderDrawer> createState() => _SplitOrderDrawerState();
}

class _SplitOrderDrawerState extends State<SplitOrderDrawer> {
  final TextEditingController _extraProductCtrl = TextEditingController();
  final TextEditingController _extraQtyCtrl = TextEditingController(text: "1");
  final FocusNode _extraProductFocus = FocusNode();

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = "";
  String _selectedWholesaler = "ALL WHOLESALERS";

  @override
  void dispose() {
    _extraProductCtrl.dispose();
    _extraQtyCtrl.dispose();
    _extraProductFocus.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleAddExtraItem(PharmacyProvider pharmacy) {
    final name = _extraProductCtrl.text.trim();
    final qty = int.tryParse(_extraQtyCtrl.text.trim()) ?? 1;

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select or enter a product name.")),
      );
      return;
    }

    final matches = pharmacy.searchProducts(name, includeGenerics: false);
    Product product;
    if (matches.isNotEmpty) {
      product = matches.first;
    } else {
      product = Product(
        id: "EXTRA_${DateTime.now().millisecondsSinceEpoch}",
        name: name.toUpperCase(),
        supplier: "EXTRA ITEM",
        packSize: 1,
        stock: 0,
        reorderLevel: 10,
        mrp: 0.0,
        purchaseRate: 0.0,
      );
    }

    pharmacy.addCustomExtraOrderItem(product, qty > 0 ? qty : 1);
    _extraProductCtrl.clear();
    _extraQtyCtrl.text = "1";

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Added '${product.name}' (Qty: $qty) to Order Book!"),
        backgroundColor: Colors.teal,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pharmacy = Provider.of<PharmacyProvider>(context);
    final app = Provider.of<AppProvider>(context);
    final isDark = app.isDarkMode;
    final screenSize = MediaQuery.of(context).size;

    final double panelWidth = (screenSize.width * 0.50).clamp(520.0, 950.0);
    final bool isOpen = pharmacy.isOrderPanelOpen;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      curve: Curves.fastOutSlowIn,
      top: 0,
      bottom: 0,
      right: isOpen ? 0 : -panelWidth - 20,
      width: panelWidth,
      child: Material(
        elevation: 16,
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            border: Border(
              left: BorderSide(
                color: isDark ? Colors.teal.shade800 : Colors.teal.shade200,
                width: 2.0,
              ),
            ),
          ),
          child: Column(
            children: [
              _buildHeader(context, pharmacy, isDark),
              _buildAddExtraItemBar(pharmacy, isDark),
              _buildTabBar(pharmacy, isDark),
              _buildFilterAndSearchBar(pharmacy, isDark),
              Expanded(
                child: pharmacy.orderPanelActiveTab == 0
                    ? _buildSpecialOrdersTableView(pharmacy, isDark)
                    : _buildReorderTableView(pharmacy, isDark),
              ),
              _buildFooter(context, pharmacy, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, PharmacyProvider pharmacy, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: isDark ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
      child: Row(
        children: [
          const Icon(Icons.style_rounded, color: Colors.tealAccent, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "ORDER BOOK WORKSPACE",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  "50% Split Panel • Formula Auto-Qty & Manual Override",
                  style: TextStyle(color: Colors.white60, fontSize: 10),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_rounded, color: Colors.white70, size: 22),
            onPressed: () => pharmacy.minimizeOrderPanel(),
            tooltip: "Minimize to Floating Dock (F8)",
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 20),
            onPressed: () => pharmacy.closeOrderPanelCompletely(),
            tooltip: "Close & Hide Dock Completely",
          ),
        ],
      ),
    );
  }

  Widget _buildAddExtraItemBar(PharmacyProvider pharmacy, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: isDark ? const Color(0xFF131C2E) : Colors.teal.shade50.withValues(alpha: 0.5),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: AppStrictAutocomplete(
              label: "Add Extra Medicine",
              controller: _extraProductCtrl,
              focusNode: _extraProductFocus,
              getItems: () => pharmacy.productMaster.map((p) => p.name).toList(),
              defaultOption: "",
              isStrict: false,
              height: 32,
              onValueChanged: (_) {},
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: TextField(
              controller: _extraQtyCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: "Qty",
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onPressed: () => _handleAddExtraItem(pharmacy),
            icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
            label: const Text("Add", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(PharmacyProvider pharmacy, bool isDark) {
    final activeTab = pharmacy.orderPanelActiveTab;

    return Container(
      color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => pharmacy.setOrderPanelActiveTab(0),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: activeTab == 0
                      ? (isDark ? Colors.teal.shade900 : Colors.teal.shade50)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: activeTab == 0 ? Colors.teal : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_pin_rounded,
                        size: 15, color: activeTab == 0 ? Colors.teal : Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      "Patient Special Orders (${pharmacy.specialOrders.length})",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: activeTab == 0
                            ? (isDark ? Colors.tealAccent : Colors.teal.shade900)
                            : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: InkWell(
              onTap: () => pharmacy.setOrderPanelActiveTab(1),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: activeTab == 1
                      ? (isDark ? Colors.amber.shade900.withValues(alpha: 0.3) : Colors.amber.shade50)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: activeTab == 1 ? Colors.amber.shade700 : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 15, color: activeTab == 1 ? Colors.amber.shade700 : Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      "Supplier Reorder List",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: activeTab == 1
                            ? (isDark ? Colors.amberAccent : Colors.amber.shade900)
                            : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterAndSearchBar(PharmacyProvider pharmacy, bool isDark) {
    final List<String> wholesalers = [
      "ALL WHOLESALERS",
      ...pharmacy.productMaster
          .map((p) => (p.supplier.isNotEmpty ? p.supplier : p.manufacturer).trim().toUpperCase())
          .where((c) => c.isNotEmpty)
          .toSet()
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: isDark ? const Color(0xFF0F172A) : Colors.white,
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: wholesalers.contains(_selectedWholesaler) ? _selectedWholesaler : "ALL WHOLESALERS",
              style: TextStyle(fontSize: 11, color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              ),
              items: wholesalers
                  .map<DropdownMenuItem<String>>((String w) => DropdownMenuItem<String>(
                        value: w,
                        child: Text(w, overflow: TextOverflow.ellipsis, maxLines: 1),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedWholesaler = val);
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
              style: const TextStyle(fontSize: 11),
              decoration: InputDecoration(
                hintText: "Search medicine name...",
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
      child: const Row(
        children: [
          SizedBox(width: 40, child: Text("Sl No", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          Expanded(flex: 5, child: Text("Product / Wholesaler", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          SizedBox(width: 80, child: Text("Pack", textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
          SizedBox(width: 90, child: Text("Order Qty", textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildReorderTableView(PharmacyProvider pharmacy, bool isDark) {
    // 1. Gather custom extra items + low stock products matching threshold
    final List<Map<String, dynamic>> rows = [];

    // Custom extra items
    for (var extra in pharmacy.customExtraOrderItems) {
      rows.add({
        'key': extra['key'],
        'name': extra['productName'],
        'company': extra['company'],
        'packStr': "1x${extra['packSize']}",
        'autoQty': extra['qty'],
        'isExtra': true,
      });
    }

    // Low stock items matching System Stock / Pack Size <= Reorder Rank
    for (var p in pharmacy.productMaster) {
      double packSize = p.packSize > 0 ? p.packSize.toDouble() : 1.0;
      double systemPacks = p.stock / packSize;
      double reorderRank = p.reorderLevel > 0 ? p.reorderLevel.toDouble() : 5.0;

      if (systemPacks <= reorderRank) {
        double targetRank = reorderRank * 2; // Target Rank
        int autoQty = math.max(1, (targetRank - systemPacks).ceil());

        String key = "LOW_${p.id}";
        rows.add({
          'key': key,
          'id': p.id,
          'name': p.name,
          'company': p.supplier.isNotEmpty ? p.supplier : p.manufacturer,
          'packStr': "1x${p.packSize > 0 ? p.packSize : 1}",
          'autoQty': autoQty,
          'isExtra': false,
        });
      }
    }

    // Apply Wholesaler & Search Filters
    final filtered = rows.where((r) {
      final nameMatches = r['name'].toString().toLowerCase().contains(_searchQuery);
      final compMatches = _selectedWholesaler == "ALL WHOLESALERS" ||
          r['company'].toString().toUpperCase() == _selectedWholesaler;
      return nameMatches && compMatches;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 48, color: Colors.green.shade300),
            const SizedBox(height: 12),
            const Text(
              "No Reorder Items Matched",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildTableHeader(isDark),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final r = filtered[index];
              final String key = r['key'];
              final int defaultQty = r['autoQty'];
              final int currentQty = pharmacy.orderOverrideQtys[key] ?? defaultQty;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text("${index + 1}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r['name'],
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          Text(
                            r['company'].toString().isNotEmpty ? r['company'] : "GENERAL",
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      child: Text(
                        r['packStr'],
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11, color: Colors.teal, fontWeight: FontWeight.bold),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: SizedBox(
                        height: 32,
                        child: TextField(
                          key: ValueKey("QTY_$key"),
                          controller: TextEditingController(text: "$currentQty"),
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onChanged: (val) {
                            int parsed = int.tryParse(val.trim()) ?? 0;
                            pharmacy.setOrderOverrideQty(key, parsed);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSpecialOrdersTableView(PharmacyProvider pharmacy, bool isDark) {
    final filtered = pharmacy.specialOrders.where((s) {
      final name = (s['productName'] ?? s['product_name'] ?? "").toString().toLowerCase();
      final patient = (s['patientName'] ?? s['customer_name'] ?? "").toString().toLowerCase();
      return name.contains(_searchQuery) || patient.contains(_searchQuery);
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_turned_in_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              "No Patient Special Orders Found",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildTableHeader(isDark),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final s = filtered[index];
              final String name = s['productName'] ?? s['product_name'] ?? 'Product';
              final String key = "SPEC_${s['entryNo']}_$name";

              int defaultQty = int.tryParse(s['qty']?.toString() ?? "1") ?? 1;
              int currentQty = pharmacy.orderOverrideQtys[key] ?? defaultQty;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text("${index + 1}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          Text(
                            "Patient: ${s['patientName'] ?? s['customer_name'] ?? 'Walk-in'}",
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(
                      width: 80,
                      child: Text(
                        "1x10",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: Colors.teal, fontWeight: FontWeight.bold),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: SizedBox(
                        height: 32,
                        child: TextField(
                          key: ValueKey("QTY_$key"),
                          controller: TextEditingController(text: "$currentQty"),
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onChanged: (val) {
                            int parsed = int.tryParse(val.trim()) ?? 0;
                            pharmacy.setOrderOverrideQty(key, parsed);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context, PharmacyProvider pharmacy, bool isDark) {
    int totalOrderedPacks = 0;
    pharmacy.orderOverrideQtys.forEach((_, q) => totalOrderedPacks += q.toInt());

    return Container(
      padding: const EdgeInsets.all(12),
      color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                "Active Wholesaler: $_selectedWholesaler",
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const Spacer(),
              Text(
                "Total Packs: $totalOrderedPacks",
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    AppDialogs.showFastDialog(
                      context: context,
                      title: "WhatsApp Order Sent",
                      content: "Dispatched order draft ($totalOrderedPacks packs) to $_selectedWholesaler!",
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                  label: const Text("WhatsApp", style: TextStyle(fontSize: 11)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    AppDialogs.showFastDialog(
                      context: context,
                      title: "Converted to Purchase Entry",
                      content: "Transferred $totalOrderedPacks packs into Purchase Entry screen!",
                    );
                  },
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
                  label: const Text("Purchase Entry", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
