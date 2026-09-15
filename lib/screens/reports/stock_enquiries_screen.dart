import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/pharmacy_provider.dart';
import '../../providers/app_provider.dart';

class StockEnquiriesScreen extends StatefulWidget {
  const StockEnquiriesScreen({Key? key}) : super(key: key);

  @override
  State<StockEnquiriesScreen> createState() => _StockEnquiriesScreenState();
}

class _StockEnquiriesScreenState extends State<StockEnquiriesScreen> {
  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();
  String _selectedPreset = "Today"; // 'Today', 'Yesterday', 'This Week', 'This Month', 'Custom'
  
  String _searchQuery = "";
  String _sortBy = "most"; // 'most', 'lowest', 'latest', 'name'
  bool _isLoading = false;

  List<Map<String, dynamic>> _enquiries = [];

  @override
  void initState() {
    super.initState();
    _applyPreset("Today");
  }

  void _applyPreset(String preset) {
    final now = DateTime.now();
    setState(() {
      _selectedPreset = preset;
      if (preset == "Today") {
        _fromDate = now;
        _toDate = now;
      } else if (preset == "Yesterday") {
        final yest = now.subtract(const Duration(days: 1));
        _fromDate = yest;
        _toDate = yest;
      } else if (preset == "This Week") {
        _fromDate = now.subtract(Duration(days: now.weekday - 1));
        _toDate = now;
      } else if (preset == "This Month") {
        _fromDate = DateTime(now.year, now.month, 1);
        _toDate = now;
      }
    });
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final pharma = Provider.of<PharmacyProvider>(context, listen: false);
      final list = await pharma.getStockEnquiries(
        fromDate: _fromDate,
        toDate: _toDate,
      );
      if (mounted) {
        setState(() {
          _enquiries = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredAndSortedData {
    final query = _searchQuery.trim().toLowerCase();
    List<Map<String, dynamic>> list = _enquiries.where((e) {
      if (query.isEmpty) return true;
      final name = (e['product_name'] ?? '').toString().toLowerCase();
      return name.contains(query);
    }).toList();

    list.sort((a, b) {
      if (_sortBy == "most") {
        int cA = (a['times_enquired'] as num?)?.toInt() ?? 0;
        int cB = (b['times_enquired'] as num?)?.toInt() ?? 0;
        return cB.compareTo(cA); // Descending
      } else if (_sortBy == "lowest") {
        int cA = (a['times_enquired'] as num?)?.toInt() ?? 0;
        int cB = (b['times_enquired'] as num?)?.toInt() ?? 0;
        return cA.compareTo(cB); // Ascending
      } else if (_sortBy == "latest") {
        String dA = a['last_enquiry_date'] ?? '';
        String dB = b['last_enquiry_date'] ?? '';
        return dB.compareTo(dA); // Descending date
      } else if (_sortBy == "name") {
        String nA = (a['product_name'] ?? '').toString().toLowerCase();
        String nB = (b['product_name'] ?? '').toString().toLowerCase();
        return nA.compareTo(nB);
      }
      return 0;
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredAndSortedData;
    
    // Aggregated metrics
    int totalEnquiries = filtered.fold(0, (sum, e) => sum + ((e['times_enquired'] as num?)?.toInt() ?? 0));
    int uniqueMedicines = filtered.length;
    int totalShortQty = filtered.fold(0, (sum, e) => sum + ((e['total_short_qty'] as num?)?.toInt() ?? 0));
    
    String topDemanded = "None";
    if (filtered.isNotEmpty) {
      topDemanded = "${filtered.first['product_name']} (${filtered.first['times_enquired']}x)";
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: Column(
        children: [
          // === TOP TOOLBAR ===
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2))
              ]
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.analytics_rounded, color: Colors.blue, size: 22),
                    const SizedBox(width: 8),
                    const Text("Stock Enquiries & Lost Demand Analysis", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const Spacer(),
                    
                    // PRESET PILLS
                    _presetChip("Today"),
                    const SizedBox(width: 4),
                    _presetChip("Yesterday"),
                    const SizedBox(width: 4),
                    _presetChip("This Week"),
                    const SizedBox(width: 4),
                    _presetChip("This Month"),
                    const SizedBox(width: 12),

                    // DATE RANGE PICKERS
                    _datePickerButton("From: ", _fromDate, (d) {
                      setState(() {
                        _fromDate = d;
                        _selectedPreset = "Custom";
                      });
                      _loadData();
                    }),
                    const SizedBox(width: 8),
                    _datePickerButton("To: ", _toDate, (d) {
                      setState(() {
                        _toDate = d;
                        _selectedPreset = "Custom";
                      });
                      _loadData();
                    }),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: Colors.blue),
                      tooltip: "Refresh Data",
                      onPressed: _loadData,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    // SEARCH BAR
                    SizedBox(
                      width: 300,
                      height: 34,
                      child: TextField(
                        onChanged: (v) => setState(() => _searchQuery = v),
                        decoration: InputDecoration(
                          hintText: "Search medicine name...",
                          hintStyle: const TextStyle(fontSize: 12),
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // SORT BY DROPDOWN
                    const Text("Sort By: ", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade300)
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _sortBy,
                          style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w600),
                          items: const [
                            DropdownMenuItem(value: "most", child: Text("Most Enquired (Highest Demand)")),
                            DropdownMenuItem(value: "lowest", child: Text("Lowest Enquired")),
                            DropdownMenuItem(value: "latest", child: Text("Latest First")),
                            DropdownMenuItem(value: "name", child: Text("Product Name (A-Z)")),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _sortBy = v);
                          },
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),

          // === METRICS CARDS ===
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _metricCard("TOTAL ENQUIRIES", totalEnquiries.toString(), Icons.shopping_bag_outlined, Colors.blue),
                const SizedBox(width: 12),
                _metricCard("UNIQUE MEDICINES", uniqueMedicines.toString(), Icons.medication_outlined, Colors.purple),
                const SizedBox(width: 12),
                _metricCard("TOTAL SHORT QTY", totalShortQty.toString(), Icons.inventory_2_outlined, Colors.orange.shade800),
                const SizedBox(width: 12),
                Expanded(child: _metricCard("TOP DEMANDED OUT-OF-STOCK", topDemanded, Icons.star_rounded, Colors.green.shade800)),
              ],
            ),
          ),

          // === MAIN TABLE ===
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_rounded, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text("No Stock Enquiries found for the selected filter.", style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      )
                    : Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4)
                          ]
                        ),
                        child: Column(
                          children: [
                            // Table Header
                            Container(
                              height: 36,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2C3E50),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                              ),
                              child: Row(
                                children: const [
                                  SizedBox(width: 40, child: Text("SLR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                                  Expanded(flex: 3, child: Text("PRODUCT NAME", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                                  SizedBox(width: 120, child: Text("TIMES ENQUIRED", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                                  SizedBox(width: 120, child: Text("TOTAL SHORT QTY", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                                  SizedBox(width: 160, child: Text("LAST ENQUIRY DATE", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                                  SizedBox(width: 130, child: Text("CURRENT STOCK", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                                  SizedBox(width: 160, child: Text("ACTION", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                                ],
                              ),
                            ),
                            // Table Body
                            Expanded(
                              child: ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                                itemBuilder: (ctx, idx) {
                                  final item = filtered[idx];
                                  final prodName = (item['product_name'] ?? '').toString();
                                  final timesEnquired = (item['times_enquired'] as num?)?.toInt() ?? 0;
                                  final shortQty = (item['total_short_qty'] as num?)?.toInt() ?? 0;
                                  final rawDate = (item['last_enquiry_date'] ?? '').toString();
                                  
                                  String dateStr = rawDate;
                                  try {
                                    if (rawDate.isNotEmpty) {
                                      final dt = DateTime.parse(rawDate);
                                      dateStr = DateFormat('dd/MM/yyyy hh:mm a').format(dt);
                                    }
                                  } catch (_) {}

                                  final pharma = Provider.of<PharmacyProvider>(context, listen: false);
                                  final liveStock = pharma.getTotalStockForProduct(prodName);

                                  return Container(
                                    height: 38,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    color: idx % 2 == 0 ? Colors.white : const Color(0xFFF9FAFB),
                                    child: Row(
                                      children: [
                                        SizedBox(width: 40, child: Text("${idx + 1}", style: const TextStyle(fontSize: 12, color: Colors.black54))),
                                        Expanded(
                                          flex: 3, 
                                          child: Text(prodName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87))
                                        ),
                                        SizedBox(
                                          width: 120, 
                                          child: Container(
                                            alignment: Alignment.center,
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
                                            child: Text("$timesEnquired times", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                                          )
                                        ),
                                        SizedBox(
                                          width: 120, 
                                          child: Text("$shortQty units", textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87))
                                        ),
                                        SizedBox(
                                          width: 160, 
                                          child: Text(dateStr, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.black87))
                                        ),
                                        SizedBox(
                                          width: 130, 
                                          child: Container(
                                            alignment: Alignment.center,
                                            child: Text(
                                              liveStock > 0 ? "$liveStock units" : "OUT OF STOCK",
                                              style: TextStyle(
                                                fontSize: 11, 
                                                fontWeight: FontWeight.bold, 
                                                color: liveStock > 0 ? Colors.green.shade800 : Colors.red.shade700
                                              ),
                                            ),
                                          )
                                        ),
                                        SizedBox(
                                          width: 160, 
                                          child: Center(
                                            child: ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.blue.shade700,
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                              ),
                                              icon: const Icon(Icons.add_shopping_cart_rounded, size: 14),
                                              label: const Text("Add Special Order", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                              onPressed: () {
                                                final app = Provider.of<AppProvider>(context, listen: false);
                                                app.openSpecialOrders();
                                              },
                                            ),
                                          )
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            )
                          ],
                        ),
                      ),
          )
        ],
      ),
    );
  }

  Widget _presetChip(String label) {
    bool isSelected = _selectedPreset == label;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.white : Colors.black87)),
      selected: isSelected,
      selectedColor: Colors.blue.shade700,
      backgroundColor: Colors.grey.shade100,
      onSelected: (_) => _applyPreset(label),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _datePickerButton(String label, DateTime date, Function(DateTime) onSelect) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (d != null) onSelect(d);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade300)
        ),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
            Text(DateFormat('dd/MM/yyyy').format(date), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue)),
            const SizedBox(width: 4),
            const Icon(Icons.calendar_today_rounded, size: 12, color: Colors.blue),
          ],
        ),
      ),
    );
  }

  Widget _metricCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))
          ]
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54)),
                  const SizedBox(height: 2),
                  Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
