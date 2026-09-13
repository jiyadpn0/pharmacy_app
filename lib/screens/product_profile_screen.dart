import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/pharmacy_provider.dart';
import '../utils/app_formatters.dart';
import '../utils/theme_constants.dart';

class ProductProfileScreen extends StatefulWidget {
  final String? initialProductName;
  const ProductProfileScreen({super.key, this.initialProductName});

  @override
  State<ProductProfileScreen> createState() => _ProductProfileScreenState();
}

class _ProductProfileScreenState extends State<ProductProfileScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  
  Product? _selectedProduct;
  late TabController _tabController;

  // Data Lists
  List<Product> _activeBatches = [];
  List<Map<String, dynamic>> _allTrans = [];
  final List<Map<String, dynamic>> _sales = [];
  final List<Map<String, dynamic>> _purchases = [];
  final List<Map<String, dynamic>> _salesReturns = [];
  final List<Map<String, dynamic>> _purchaseReturns = [];
  final List<Map<String, dynamic>> _damages = [];

  // Dropdown Overlays
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  List<Product> _searchResults = [];
  int _searchIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    
    if (widget.initialProductName != null && widget.initialProductName!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchCtrl.text = widget.initialProductName!;
        final p = Provider.of<PharmacyProvider>(context, listen: false);
        final matches = p.searchProducts(widget.initialProductName!);
        if (matches.isNotEmpty) {
          _loadProductData(matches.first);
        }
      });
    } else {
      _searchFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    _hideOverlay();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // =========================================================================
  // LIGHTNING FAST RAM DATA LOADER
  // =========================================================================
  void _loadProductData(Product selected) {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    
    // Get the absolute master record
    final master = provider.productMaster.firstWhere((p) => p.id == selected.id, orElse: () => selected);

    setState(() {
      _selectedProduct = master;
      
      // 1. Live Batches
      _activeBatches = provider.products.where((b) => b.id == master.id).toList();
      _activeBatches.sort((a, b) => a.expiry.compareTo(b.expiry));

      // 2. Clear ledgers
      _sales.clear();
      _purchases.clear();
      _salesReturns.clear();
      _purchaseReturns.clear();
      _damages.clear();
      _allTrans.clear();

      // 3. Extract Sales
      for (var sale in provider.sales) {
        if (sale.isDeleted) continue;
        for (var item in sale.items) {
          if (item.product.id == master.id || item.product.name == master.name) {
            _sales.add(_buildRowMap(sale.date, sale.entryNo, "SALES", sale.patient, item.product.batch, item.product.expiry, item.qty, item.packin, item.mrp, item.sRate, item.product.landingCost));
          }
        }
      }

      // 4. Extract Purchases
      for (var pur in provider.purchases) {
        for (var item in pur.items) {
          if (item.id == master.id || item.productName == master.name) {
            _purchases.add(_buildRowMap(pur.date, pur.entryNo, "PURCHASE", pur.supplierName, item.batch, item.expiry, item.qty + item.fQty, item.packin, item.mrp, item.pRate, item.lCost));
          }
        }
      }

      // 5. Extract Sales Returns
      for (var ret in provider.saleReturns) {
        for (var item in ret.items) {
          if (item.product.id == master.id || item.product.name == master.name) {
            _salesReturns.add(_buildRowMap(ret.date, ret.entryNo, "SALE RTN", ret.patient, item.product.batch, item.product.expiry, item.qty, item.packin, item.mrp, item.sRate, 0.0));
          }
        }
      }

      // 6. Extract Purchase Returns
      for (var ret in provider.purchaseReturns) {
        for (var item in ret.items) {
          if (item.productName == master.name) {
            _purchaseReturns.add(_buildRowMap(ret.date, ret.entryNo, "PUR RTN", ret.supplierName, item.batch, item.expiry, item.qty, item.packin, item.mrp, item.pRate, 0.0));
          }
        }
      }

      // 7. Extract Damages & Adjustments
      for (var dmg in provider.writeOffs) {
        if (dmg.product.id == master.id || dmg.product.name == master.name) {
          _damages.add(_buildRowMap(dmg.date, dmg.id, "DAMAGE", dmg.reason, dmg.product.batch, dmg.product.expiry, dmg.quantity, dmg.product.packSize, dmg.product.mrp, dmg.lossValue, 0.0));
        }
      }
      for (var adj in provider.adjustments) {
        for (var item in adj.items) {
          if (item.product.id == master.id || item.product.name == master.name) {
            _damages.add(_buildRowMap(adj.date, adj.entryNo, item.qty < 0 ? "STOCK MINUS" : "STOCK ADD", adj.reason, item.product.batch, item.product.expiry, item.qty, item.product.packSize, item.product.mrp, item.purchaseRate, item.purchaseRate));
          }
        }
      }

      // Combine and sort ALL
      _allTrans = [..._sales, ..._purchases, ..._salesReturns, ..._purchaseReturns, ..._damages];
      _allTrans.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
    });
  }

  Map<String, dynamic> _buildRowMap(DateTime date, String billNo, String type, String party, String batch, String expiry, int qty, int pack, double mrp, double rate, double lCost) {
    return {
      'date': date, 'billNo': billNo, 'type': type, 'party': party,
      'batch': batch, 'expiry': expiry, 'qty': qty, 'pack': pack,
      'mrp': mrp, 'rate': rate, 'lCost': lCost,
    };
  }

  // =========================================================================
  // AUTOCOMPLETE OVERLAY LOGIC
  // =========================================================================
  void _showOverlay() {
    if (_overlayEntry != null) return;
    context.findRenderObject() as RenderBox;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 600,
        child: CompositedTransformFollower(
          link: _layerLink, showWhenUnlinked: false, offset: const Offset(0, 35),
          child: Material(
            elevation: 8,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 300),
              decoration: BoxDecoration(border: Border.all(color: Colors.blue.shade900), color: Colors.white),
              child: ListView.builder(
                shrinkWrap: true, padding: EdgeInsets.zero, itemCount: _searchResults.length,
                itemBuilder: (ctx, i) {
                  final p = _searchResults[i];
                  final isSelected = i == _searchIndex;
                  return InkWell(
                    onTap: () {
                      _searchCtrl.text = p.name;
                      _loadProductData(p);
                      _hideOverlay();
                    },
                    child: Container(
                      color: isSelected ? Colors.blue.shade50 : Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(flex: 3, child: Text(p.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 13))),
                          Expanded(flex: 2, child: Text("Patent: ${p.patent}", style: const TextStyle(fontSize: 11, color: Colors.blueGrey))),
                          Text("Stock: ${p.stock}", style: TextStyle(fontWeight: FontWeight.bold, color: p.stock > 0 ? Colors.green : Colors.red, fontSize: 12)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onSearchChanged(String query) {
    if (query.trim().isEmpty) {
      _hideOverlay();
      return;
    }
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    setState(() {
      _searchResults = provider.searchProducts(query, includeGenerics: true);
      _searchIndex = 0;
    });
    if (_searchResults.isNotEmpty) {
      _showOverlay();
      _overlayEntry?.markNeedsBuild();
    } else {
      _hideOverlay();
    }
  }

  // =========================================================================
  // UI BUILDERS
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      body: Column(
        children: [
          _buildTopSearchPanel(),
          _buildProductDetailsPanel(),
          Expanded(child: _buildTabBarSection()),
        ],
      ),
    );
  }

  Widget _buildTopSearchPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
      child: Row(
        children: [
          const Icon(Icons.manage_search_rounded, color: Colors.blueGrey),
          const SizedBox(width: 8),
          const Text("PRODUCT PROFILE", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black87)),
          const SizedBox(width: 32),
          const Text("Product / Barcode:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(width: 8),
          CompositedTransformTarget(
            link: _layerLink,
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent && _overlayEntry != null) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    setState(() { _searchIndex = (_searchIndex + 1) % _searchResults.length; });
                    _overlayEntry?.markNeedsBuild();
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    setState(() { _searchIndex = (_searchIndex - 1 + _searchResults.length) % _searchResults.length; });
                    _overlayEntry?.markNeedsBuild();
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: SizedBox(
                width: 400, height: 32,
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  onChanged: _onSearchChanged,
                  onSubmitted: (v) {
                    if (_searchResults.isNotEmpty) {
                      _searchCtrl.text = _searchResults[_searchIndex].name;
                      _loadProductData(_searchResults[_searchIndex]);
                      _hideOverlay();
                    }
                  },
                  decoration: InputDecoration(
                    hintText: "Scan barcode or type name...",
                    filled: true, fillColor: Colors.blue.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    suffixIcon: const Icon(Icons.search, size: 18),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductDetailsPanel() {
    final p = _selectedProduct;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 2))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // COLUMN 1: Codes
          Expanded(flex: 2, child: Column(children: [
            _infoRow("HSN Code", p == null ? "---" : (p.hsnCode.isEmpty ? "N/A" : p.hsnCode)),
            _infoRow("Patent", p == null ? "---" : (p.patent.isEmpty ? p.manufacturer : p.patent)),
            _infoRow("Reorder Level", p?.reorderLevel.toString() ?? "0"),
          ])),
          
          // COLUMN 2: Core Identity
          Expanded(flex: 4, child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text(p?.name ?? "SELECT PRODUCT", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: p == null ? Colors.grey : Colors.blue.shade900)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _pillTag("Controlled", p != null && p.schedule.isNotEmpty, color: Colors.orange),
              const SizedBox(width: 8),
              _pillTag("Active", p != null, color: Colors.green),
            ]),
          ])),

          // COLUMN 3: Financials & Stock
          Expanded(flex: 3, child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_miniLabel("Stock:"), _miniVal(p?.stock.toString() ?? "0", color: (p != null && p.stock > 0) ? Colors.green.shade700 : Colors.red, isBold: true)]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_miniLabel("Packing:"), _miniVal(p?.packSize.toString() ?? "0")]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_miniLabel("MRP:"), _miniVal("₹${p?.mrp.toStringAsFixed(2) ?? "0.00"}")]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_miniLabel("P.Rate:"), _miniVal("₹${p?.purchaseRate.toStringAsFixed(2) ?? "0.00"}")]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_miniLabel("Rack:"), _miniVal(p?.rack ?? "---", isBold: true)]),
            ]),
          )),

          const SizedBox(width: 12),

          // COLUMN 4: Taxonomy
          Expanded(flex: 3, child: Column(children: [
            _infoRow("Category", p?.category ?? "---"),
            _infoRow("Generic Name", p?.genericName ?? "---"),
            _infoRow("Tax Schedule", p != null ? "GST ${p.gstPercent.toStringAsFixed(0)}%" : "---"),
            _infoRow("Discount %", p != null ? "${p.sDiscPercent}%" : "0.0%"),
          ])),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey))),
          const Text(":", style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
          const SizedBox(width: 8),
          Expanded(child: Text(val, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87))),
        ],
      ),
    );
  }

  Widget _miniLabel(String l) => Text(l, style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold));
  Widget _miniVal(String v, {Color color = Colors.black87, bool isBold = false}) => Text(v, style: TextStyle(fontSize: 12, color: color, fontWeight: isBold ? FontWeight.bold : FontWeight.w500));

  Widget _pillTag(String label, bool isActive, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: isActive ? color.withValues(alpha: 0.1) : Colors.grey.shade100, border: Border.all(color: isActive ? color : Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isActive ? Icons.check_box : Icons.check_box_outline_blank, size: 12, color: isActive ? color : Colors.grey),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isActive ? color : Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildTabBarSection() {
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: Colors.blue.shade900,
            unselectedLabelColor: Colors.blueGrey,
            indicatorColor: Colors.blue.shade900,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
            tabs: [
              const Tab(text: "LIVE STOCK (BATCHES)"),
              const Tab(text: "ALL TRANSACTIONS"),
              Tab(text: "SALES (${_sales.length})"),
              Tab(text: "PURCHASES (${_purchases.length})"),
              Tab(text: "SALES RETURN (${_salesReturns.length})"),
              Tab(text: "PURCHASE RETURN (${_purchaseReturns.length})"),
              Tab(text: "DAMAGES/ADJ (${_damages.length})"),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildBatchGrid(),
              _buildTransactionGrid(_allTrans, true),
              _buildTransactionGrid(_sales, false),
              _buildTransactionGrid(_purchases, false),
              _buildTransactionGrid(_salesReturns, false),
              _buildTransactionGrid(_purchaseReturns, false),
              _buildTransactionGrid(_damages, false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBatchGrid() {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300)),
      child: Column(
        children: [
          Container(
            height: 30, color: const Color(0xFF37474F),
            child: const Row(children: [
              _Hdr("BATCH NO", flex: 2), _Hdr("EXPIRY", flex: 1, align: TextAlign.center), _Hdr("MRP", flex: 1, align: TextAlign.right), _Hdr("P.RATE", flex: 1, align: TextAlign.right), _Hdr("L.COST", flex: 1, align: TextAlign.right), _Hdr("S.RATE", flex: 1, align: TextAlign.right), _Hdr("STRIPS / LOOSE", flex: 2, align: TextAlign.center), _Hdr("SUPPLIER", flex: 3),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _activeBatches.length,
              itemBuilder: (ctx, i) {
                final b = _activeBatches[i];
                int pack = b.packSize > 0 ? b.packSize : 1;
                int strips = b.stock ~/ pack;
                int loose = b.stock % pack;
                bool isEven = i % 2 == 0;

                return Container(
                  height: 30, decoration: BoxDecoration(color: isEven ? Colors.white : Colors.grey.shade50, border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                  child: Row(children: [
                    _Cell(cleanBatch(b.batch), flex: 2, isBold: true),
                    _Cell(b.expiry, flex: 1, align: TextAlign.center, color: Colors.red.shade800, isBold: true),
                    _Cell(b.mrp.toStringAsFixed(2), flex: 1, align: TextAlign.right),
                    _Cell(b.purchaseRate.toStringAsFixed(2), flex: 1, align: TextAlign.right),
                    _Cell(b.landingCost.toStringAsFixed(2), flex: 1, align: TextAlign.right, color: Colors.blue.shade900, isBold: true),
                    _Cell(b.salePrice.toStringAsFixed(2), flex: 1, align: TextAlign.right),
                    Expanded(flex: 2, child: Container(alignment: Alignment.center, decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade200))), child: RichText(text: TextSpan(style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Roboto'), children: [TextSpan(text: "$strips", style: TextStyle(color: strips > 0 ? Colors.green.shade700 : Colors.blueGrey)), const TextSpan(text: " / ", style: TextStyle(color: Colors.blueGrey)), TextSpan(text: "$loose", style: TextStyle(color: loose > 0 ? Colors.red.shade700 : Colors.blueGrey))])))),
                    _Cell(b.supplier.isEmpty ? "Unknown" : b.supplier, flex: 3),
                  ]),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTransactionGrid(List<Map<String, dynamic>> data, bool isAllTab) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300)),
      child: Column(
        children: [
          Container(
            height: 30, color: const Color(0xFF37474F),
            child: Row(children: [
              const _Hdr("DATE", width: 80),
              const _Hdr("BILL NO", width: 80),
              if (isAllTab) const _Hdr("TYPE", width: 90),
              const _Hdr("PARTY / REASON", flex: 3),
              const _Hdr("BATCH", width: 100),
              const _Hdr("EXP", width: 60, align: TextAlign.center),
              const _Hdr("QTY", width: 50, align: TextAlign.right),
              const _Hdr("PK", width: 40, align: TextAlign.center),
              const _Hdr("MRP", width: 70, align: TextAlign.right),
              const _Hdr("RATE", width: 70, align: TextAlign.right),
              const _Hdr("L.COST", width: 70, align: TextAlign.right),
            ]),
          ),
          Expanded(
            child: data.isEmpty 
              ? const Center(child: Text("No transactions found.", style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: data.length,
                  itemBuilder: (ctx, i) {
                    final d = data[i];
                    bool isEven = i % 2 == 0;
                    
                    // Color coding for 'All Transactions' tab
                    Color typeColor = Colors.black87;
                    if (d['type'] == "SALES") typeColor = Colors.blue.shade700;
                    if (d['type'] == "PURCHASE") typeColor = Colors.green.shade700;
                    if (d['type'].toString().contains("RTN") || d['type'].toString().contains("MINUS")) typeColor = Colors.red.shade700;

                    DateTime parsedDate;
                    if (d['date'] is DateTime) {
                      parsedDate = d['date'] as DateTime;
                    } else {
                      parsedDate = DateTime.tryParse(d['date']?.toString() ?? '') ?? DateTime.now();
                    }

                    return Container(
                      height: 28, decoration: BoxDecoration(color: isEven ? Colors.white : Colors.grey.shade50, border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                      child: Row(children: [
                        _Cell(DateFormat('dd/MM/yy').format(parsedDate), width: 80, color: Colors.blueGrey),
                        _Cell(d['billNo'].toString(), width: 80, isBold: true),
                        if (isAllTab) _Cell(d['type'], width: 90, color: typeColor, isBold: true),
                        _Cell(d['party'].toString(), flex: 3),
                        _Cell(cleanBatch(d['batch'].toString()), width: 100),
                        _Cell(d['expiry'].toString(), width: 60, align: TextAlign.center),
                        _Cell(d['qty'].toString(), width: 50, align: TextAlign.right, isBold: true),
                        _Cell(d['pack'].toString(), width: 40, align: TextAlign.center),
                        _Cell((d['mrp'] as double).toStringAsFixed(2), width: 70, align: TextAlign.right),
                        _Cell((d['rate'] as double).toStringAsFixed(2), width: 70, align: TextAlign.right, color: Colors.blue.shade900),
                        _Cell((d['lCost'] as double).toStringAsFixed(2), width: 70, align: TextAlign.right, color: Colors.green.shade900),
                      ]),
                    );
                  },
                ),
          )
        ],
      ),
    );
  }
}

class _Hdr extends StatelessWidget {
  final String title; final double? width; final int? flex; final TextAlign align;
  const _Hdr(this.title, {this.width, this.flex, this.align = TextAlign.left});
  @override Widget build(BuildContext context) { Widget child = Container(width: width, alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.center ? Alignment.center : Alignment.centerRight), padding: const EdgeInsets.symmetric(horizontal: 8), decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.white24, width: 0.5))), child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))); return flex != null ? Expanded(flex: flex!, child: child) : child; }
}

class _Cell extends StatelessWidget {
  final String text; final double? width; final int? flex; final TextAlign align; final Color? color; final bool isBold;
  const _Cell(this.text, {this.width, this.flex, this.align = TextAlign.left, this.color, this.isBold = false});
  @override Widget build(BuildContext context) { Widget child = Container(width: width, alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.center ? Alignment.center : Alignment.centerRight), padding: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade300, width: 0.5))), child: Text(text, style: TextStyle(fontSize: 11, color: color ?? Colors.black87, fontWeight: isBold ? FontWeight.bold : FontWeight.normal), overflow: TextOverflow.ellipsis)); return flex != null ? Expanded(flex: flex!, child: child) : child; }
}
