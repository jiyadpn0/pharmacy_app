import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/paginated_inventory_notifier.dart';
import '../providers/pharmacy_provider.dart';
import '../widgets/pin_unlock_dialog.dart';
import '../utils/search_debouncer.dart';
import '../utils/theme_constants.dart';

class CurrentStockScreen extends StatefulWidget {
  const CurrentStockScreen({super.key});

  @override
  State<CurrentStockScreen> createState() => _CurrentStockScreenState();
}

class _CurrentStockScreenState extends State<CurrentStockScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SearchDebouncer _searchDebouncer = SearchDebouncer(milliseconds: 200);

  String _filterMode = "Available"; // "All", "Available", "Out of Stock", "Low Stock", "Expired"
  late final PaginatedInventoryNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = PaginatedInventoryNotifier(isMasterList: false);
    _scrollController.addListener(_onScroll);
    _searchCtrl.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = Provider.of<PharmacyProvider>(context, listen: false);
      _notifier.updateProvider(p);
      _notifier.loadInitial(_searchCtrl.text, filterMode: _filterMode);
    });
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _notifier.fetchNextPage();
    }
  }

  void _onSearchChanged() {
    _searchDebouncer.run(() {
      if (mounted) {
        _notifier.loadInitial(_searchCtrl.text, filterMode: _filterMode);
      }
    });
  }

  @override
  void dispose() {
    _searchDebouncer.dispose();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _notifier.dispose();
    super.dispose();
  }

  DateTime _parseExpiry(String exp) {
    if (!exp.contains('/')) return DateTime(2099);
    final parts = exp.split('/');
    int m = int.tryParse(parts[0]) ?? 1;
    int y = int.tryParse(parts[1]) ?? 99;
    if (y < 100) y += 2000;
    return DateTime(y, m + 1, 0); // Last day of the month
  }

  Future<void> _deleteAllStock(BuildContext context) async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    bool isUnlocked = await PinUnlockDialog.show(
      context,
      provider,
      title: "Authorize Stock Deletion",
      message: "Enter Master Security PIN to permanently delete ALL current stock records.",
    );
    if (!isUnlocked) return;

    if (!context.mounted) return;

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 10),
            Text("PERMANENT DELETION WARNING", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: const Text(
          "Are you sure you want to PERMANENTLY DELETE ALL current stock batches?\n\nThis will clear all inventory stock levels from the database. This action CANNOT be undone!",
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("DELETE ALL STOCK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      final res = await provider.deleteInventoryRecords('All Years');
      if (context.mounted) {
        if (res['success'] == true) {
          _notifier.loadInitial(_searchCtrl.text, filterMode: _filterMode);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("All current stock batches permanently deleted!"),
              backgroundColor: Colors.red,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res['message'] ?? "Deletion failed"),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteSingleBatch(BuildContext context, Product p) async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Batch Permanently"),
        content: Text(
          "Are you sure you want to permanently delete batch '${p.batch}' of product '${p.name}' from current stock?",
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("DELETE BATCH", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      final res = await provider.deleteStockBatch(p.id, p.batch);
      if (context.mounted) {
        if (res['success'] == true) {
          _notifier.loadInitial(_searchCtrl.text, filterMode: _filterMode);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Batch '${p.batch}' deleted permanently."),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pharmacyProvider = context.watch<PharmacyProvider>();
    _notifier.updateProvider(pharmacyProvider);

    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      body: Column(
        children: [
          _buildHeader(),
          ListenableBuilder(
            listenable: _notifier,
            builder: (context, _) => _buildFilterBar(),
          ),
          Expanded(child: _buildStockGrid()),
          ListenableBuilder(
            listenable: _notifier,
            builder: (context, _) => _buildFooter(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.inventory_2_rounded, color: Colors.blue.shade800, size: 24),
          ),
          const SizedBox(width: 16),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("LIVE INVENTORY", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.black87, letterSpacing: 0.5)),
              Text("Real-time physical stock and batch locations", style: TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: 350,
            height: 36,
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: "Search Product, Batch, Rack, or Generic...",
                hintStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchCtrl.text.isNotEmpty 
                    ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () { _searchCtrl.clear(); _notifier.loadInitial('', filterMode: _filterMode); }) 
                    : null,
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => _deleteAllStock(context),
            icon: const Icon(Icons.delete_forever_rounded, size: 16, color: Colors.white),
            label: const Text("DELETE ALL STOCK", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          _filterChip("Available", Icons.check_circle, Colors.green),
          _filterChip("All", Icons.list_alt, Colors.blueGrey),
          _filterChip("Low Stock", Icons.warning_amber_rounded, Colors.orange),
          _filterChip("Expired", Icons.dangerous_outlined, Colors.red),
          _filterChip("Negative Stock", Icons.error_outline, Colors.red),
          _filterChip("Out of Stock", Icons.remove_shopping_cart, Colors.grey),
          const Spacer(),
          Text("${_notifier.items.length} Batches Loaded", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        ],
      ),
    );
  }

  Widget _filterChip(String label, IconData icon, Color color) {
    bool isSelected = _filterMode == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () {
          setState(() => _filterMode = label);
          _notifier.loadInitial(_searchCtrl.text, filterMode: label);
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.white,
            border: Border.all(color: isSelected ? color : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(20),
            boxShadow: isSelected ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))] : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: isSelected ? Colors.white : color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStockGrid() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Column(
        children: [
          // GRID HEADER
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade900,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: const Row(
              children: [
                _Hdr("SL", width: 50, align: TextAlign.center),
                _Hdr("PRODUCT NAME", flex: 3),
                _Hdr("GENERIC / CONTENT", flex: 2),
                _Hdr("RACK", width: 70, align: TextAlign.center),
                _Hdr("BATCH", width: 100),
                _Hdr("EXPIRY", width: 80, align: TextAlign.center),
                _Hdr("SUPPLIER", width: 120),
                _Hdr("PACK", width: 50, align: TextAlign.center),
                _Hdr("MRP", width: 70, align: TextAlign.right),
                _Hdr("L.COST", width: 70, align: TextAlign.right),
                _Hdr("STOCK", width: 100, align: TextAlign.right),
                _Hdr("STATUS", width: 90, align: TextAlign.center),
                _Hdr("ACTION", width: 60, align: TextAlign.center),
              ],
            ),
          ),
          
          // GRID BODY
          Expanded(
            child: ListenableBuilder(
              listenable: _notifier,
              builder: (context, _) {
                final items = _notifier.items;
                if (_notifier.isLoading && items.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (items.isEmpty) {
                  return const Center(
                    child: Text("No stock batches found.", style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                  );
                }

                return Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _scrollController,
                    itemExtent: 32.0,
                    itemCount: items.length + (_notifier.isLoading ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == items.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                        );
                      }

                      final p = items[i];
                      final bool isEven = i % 2 == 0;
                      
                      // Status Logic
                      String status = "ACTIVE";
                      Color statusColor = Colors.green;
                      bool isExpired = _parseExpiry(p.expiry).isBefore(DateTime.now());
                      
                      if (p.stock <= 0) {
                        status = "EMPTY";
                        statusColor = Colors.grey.shade600;
                      } else if (isExpired) {
                        status = "EXPIRED";
                        statusColor = Colors.red;
                      } else {
                        final provider = Provider.of<PharmacyProvider>(context, listen: false);
                        final mIdx = provider.productMaster.indexWhere((m) => m.name == p.name);
                        int reorder = mIdx != -1 ? provider.productMaster[mIdx].reorderLevel : p.reorderLevel;
                        if (p.stock <= reorder) {
                          status = "LOW STOCK";
                          statusColor = Colors.orange.shade800;
                        }
                      }

                      // Loose/Strips display
                      int pack = p.packSize > 0 ? p.packSize : 1;
                      int strips = p.stock ~/ pack;
                      int loose = p.stock % pack;

                      return Container(
                        height: 32,
                        decoration: BoxDecoration(
                          color: isEven ? Colors.white : Colors.grey.shade50,
                          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                        ),
                        child: Row(
                          children: [
                            _Cell("${i + 1}", width: 50, align: TextAlign.center, color: Colors.blueGrey),
                            _Cell(p.name, flex: 3, isBold: true, color: isExpired ? Colors.red.shade900 : Colors.black87),
                            _Cell(p.genericName, flex: 2, color: Colors.blue.shade800),
                            Container(
                              width: 70,
                              alignment: Alignment.center,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.teal.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.teal.shade200),
                                ),
                                child: Text(p.rack.isEmpty ? "-" : p.rack, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal.shade900)),
                              ),
                            ),
                            _Cell(p.batch, width: 100, isBold: true),
                            
                            Container(
                              width: 80,
                              alignment: Alignment.center,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isExpired ? Colors.red : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4)
                                ),
                                child: Text(p.expiry, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isExpired ? Colors.white : Colors.black87)),
                              ),
                            ),

                            _Cell(p.supplier, width: 120),
                            _Cell(p.packSize.toString(), width: 50, align: TextAlign.center),
                            _Cell(p.mrp.toStringAsFixed(2), width: 70, align: TextAlign.right),
                            _Cell(p.landingCost.toStringAsFixed(2), width: 70, align: TextAlign.right, color: Colors.blueGrey),
                            
                            Container(
                              width: 100,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: RichText(
                                text: TextSpan(
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Roboto'),
                                  children: [
                                    TextSpan(text: "$strips", style: TextStyle(color: strips > 0 ? Colors.green.shade700 : Colors.blueGrey)),
                                    const TextSpan(text: " / ", style: TextStyle(color: Colors.blueGrey)),
                                    TextSpan(text: "$loose", style: TextStyle(color: loose > 0 ? Colors.red.shade700 : Colors.blueGrey)),
                                  ],
                                ),
                              ),
                            ),

                            Container(
                              width: 90,
                              alignment: Alignment.center,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                ),
                                child: Text(status, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: statusColor)),
                              ),
                            ),

                            Container(
                              width: 60,
                              alignment: Alignment.center,
                              child: IconButton(
                                icon: const Icon(Icons.delete_forever_rounded, size: 16, color: Colors.redAccent),
                                tooltip: "Delete Batch Permanently",
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _deleteSingleBatch(context, p),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  Widget _buildFooter() {
    double totalVal = 0;
    int totalItems = 0;
    
    for (var p in _notifier.items) {
      if (p.stock > 0) {
        totalItems += p.stock;
        double ps = p.packSize > 0 ? p.packSize.toDouble() : 1.0;
        totalVal += (p.stock * (p.mrp / ps));
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Colors.blueGrey),
          const SizedBox(width: 8),
          const Text("Quantities are shown as [Strips / Loose]", style: TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
          const Spacer(),
          _footerStat("Loaded Physical Units", totalItems.toString()),
          const SizedBox(width: 32),
          _footerStat("Loaded MRP Value", "₹ ${totalVal.toStringAsFixed(2)}", isHighlight: true),
        ],
      ),
    );
  }

  Widget _footerStat(String label, String value, {bool isHighlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: isHighlight ? Colors.blue.shade900 : Colors.black87)),
      ],
    );
  }
}

class _Hdr extends StatelessWidget {
  final String title; final double? width; final int? flex; final TextAlign align;
  const _Hdr(this.title, {this.width, this.flex, this.align = TextAlign.left});
  @override Widget build(BuildContext context) {
    Widget child = Container(
      width: width, alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.right ? Alignment.centerRight : Alignment.center),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(title, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
    );
    return flex != null ? Expanded(flex: flex!, child: child) : child;
  }
}

class _Cell extends StatelessWidget {
  final String text; final double? width; final int? flex; final TextAlign align; final Color? color; final bool isBold;
  const _Cell(this.text, {this.width, this.flex, this.align = TextAlign.left, this.color, this.isBold = false});
  @override Widget build(BuildContext context) {
    Widget child = Container(
      width: width, alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.right ? Alignment.centerRight : Alignment.center),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade200))),
      child: Text(text, style: TextStyle(fontSize: 12, color: color ?? Colors.black87, fontWeight: isBold ? FontWeight.bold : FontWeight.w500), overflow: TextOverflow.ellipsis),
    );
    return flex != null ? Expanded(flex: flex!, child: child) : child;
  }
}
