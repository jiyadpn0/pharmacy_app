import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/pharmacy_provider.dart';
import '../utils/app_formatters.dart';


class DamageExpiryScreen extends StatefulWidget {
  const DamageExpiryScreen({super.key});

  @override
  State<DamageExpiryScreen> createState() => _DamageExpiryScreenState();
}

class _DamageExpiryScreenState extends State<DamageExpiryScreen> {
  final List<_WriteOffRow> _selectedItems = [];
  final String _entryNo = "ADJ-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
  final DateTime _date = DateTime.now();

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _qtyCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final FocusNode _qtyFocus = FocusNode();

  List<Product> _filteredProducts = [];
  bool _isEnteringDetails = false;
  String _selectedReason = "Damaged"; // Default reason

  @override
  void initState() {
    super.initState();
    _searchFocus.requestFocus();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _filteredProducts = Provider.of<PharmacyProvider>(context, listen: false).searchProducts(query);
    });
  }

  void _onProductSelected(Product p) {
    setState(() {
      _selectedItems.add(_WriteOffRow(product: p, qty: 1, reason: "Damaged", lossValue: p.purchaseRate));
      _isEnteringDetails = true;
      _qtyCtrl.text = "1";
      _searchCtrl.clear();
      _filteredProducts = [];
    });
    Future.microtask(() => _qtyFocus.requestFocus());
  }

  void _commitRow() {
    if (_selectedItems.isNotEmpty && _isEnteringDetails) {
      final item = _selectedItems.last;
      int enteredQty = int.tryParse(_qtyCtrl.text) ?? 1;

      // Stock Lock: Prevent writing off more than what you have!
      if (enteredQty > item.product.stock) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Cannot write off $enteredQty! Only ${item.product.stock} in stock."), backgroundColor: Colors.red)
        );
        return;
      }

      setState(() {
        item.qty = enteredQty;
        item.reason = _selectedReason;
        item.lossValue = item.product.purchaseRate * item.qty; // Loss is calculated on YOUR cost (purchaseRate)
        _isEnteringDetails = false;
        _qtyCtrl.clear();
      });
      _searchFocus.requestFocus();
    }
  }

  void _saveWriteOffs() async {
    if (_selectedItems.isEmpty) return;
    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      for (var item in _selectedItems) {
        await provider.saveWriteOff(StockWriteOff(
          id: "WO-${DateTime.now().millisecondsSinceEpoch}",
          date: _date,
          product: item.product,
          quantity: item.qty,
          reason: item.reason,
          lossValue: item.lossValue,
        ));
      }

      if (mounted) {
        Navigator.pop(context); // Close loading indicator
        setState(() {
          _selectedItems.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green, 
            content: Text("Stock Write-Off Saved! Inventory Reduced.")
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading indicator
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Write-Off Failed", style: TextStyle(color: Colors.red)),
            content: Text(e.toString()),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK")),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFormPanel(),
                const VerticalDivider(width: 1),
                Expanded(child: _buildGridArea()),
              ],
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))]),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.delete_sweep_outlined, color: Colors.red.shade800, size: 20),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("DAMAGE & EXPIRY", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1, color: Colors.black87)),
              Text("Stock Write-Off Entry", style: TextStyle(fontSize: 11, color: Colors.red.shade800, fontWeight: FontWeight.bold)),
            ],
          ),
          const Spacer(),
          _toolbarButton(Icons.check_circle_outline, "SAVE WRITE-OFF", Colors.red, onTap: _saveWriteOffs),
        ],
      ),
    );
  }

  Widget _toolbarButton(IconData icon, String label, Color color, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildFormPanel() {
    return Container(
      width: 250,
      color: const Color(0xFFF1F5F9),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _formField("Adjustment No", _entryNo),
          const SizedBox(height: 16),
          _formField("Date", DateFormat('dd/MM/yyyy').format(_date)),
        ],
      ),
    );
  }

  Widget _formField(String label, String val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
          child: Text(val, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _buildGridArea() {
    return Column(
      children: [
        Container(
          height: 35, color: const Color(0xFF4A4A4A),
          child: const Row(
            children: [
              _Hdr("PRODUCT NAME", flex: 1),
              _Hdr("BATCH", width: 120),
              _Hdr("REASON", width: 120),
              _Hdr("QTY", width: 80, align: TextAlign.right),
              _Hdr("LOSS VAL", width: 100, align: TextAlign.right),
              _Hdr("ACT", width: 50, align: TextAlign.center),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _selectedItems.length + 1 + _filteredProducts.length,
            itemBuilder: (context, i) {
              if (i < _selectedItems.length) return _buildSavedRow(i);
              if (i == _selectedItems.length) return _buildActiveRow();
              return _buildSearchResultRow(_filteredProducts[i - _selectedItems.length - 1]);
            },
          ),
        )
      ],
    );
  }

  Widget _buildSavedRow(int index) {
    final item = _selectedItems[index];
    return Container(
      height: 38,
      decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
      child: Row(
        children: [
          _Cell(item.product.name, flex: 1, fontWeight: FontWeight.bold),
          _Cell(cleanBatch(item.product.batch), width: 120, color: Colors.blueGrey),
          _Cell(item.reason, width: 120, color: Colors.red.shade700),
          _Cell(item.qty.toString(), width: 80, align: TextAlign.right),
          _Cell(item.lossValue.toStringAsFixed(2), width: 100, align: TextAlign.right, fontWeight: FontWeight.bold),
          SizedBox(width: 50, child: IconButton(icon: const Icon(Icons.close, size: 16, color: Colors.red), onPressed: () => setState(() => _selectedItems.removeAt(index)))),
        ],
      ),
    );
  }

  Widget _buildActiveRow() {
    return Container(
      height: 38,
      decoration: BoxDecoration(color: Colors.blue.shade50, border: const Border(bottom: BorderSide(color: Colors.blue, width: 1))),
      child: Row(
        children: [
          Expanded(
              child: TextField(
                controller: _searchCtrl, focusNode: _searchFocus, onChanged: _onSearchChanged,
                decoration: InputDecoration(hintText: _isEnteringDetails ? "Select Reason & Enter Qty ->" : "Search product to write-off...", border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), isDense: true),
                enabled: !_isEnteringDetails,
              )
          ),
          const SizedBox(width: 120), // Batch filler
          if (_isEnteringDetails)
            SizedBox(
              width: 120,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedReason,
                  isExpanded: true,
                  items: ["Damaged", "Expired", "Lost"].map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (v) => setState(() => _selectedReason = v!),
                ),
              ),
            )
          else const SizedBox(width: 120),
          if (_isEnteringDetails)
            Container(width: 80, color: Colors.blue.shade100, child: TextField(controller: _qtyCtrl, focusNode: _qtyFocus, onSubmitted: (_) => _commitRow(), textAlign: TextAlign.right, keyboardType: TextInputType.number, decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10), isDense: true)))
          else const SizedBox(width: 80),
          const SizedBox(width: 100), // Loss Val filler
          const SizedBox(width: 50), // Act filler
        ],
      ),
    );
  }

  Widget _buildSearchResultRow(Product p) {
    return InkWell(
      onTap: () => _onProductSelected(p),
      child: Container(
        height: 35, decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
        child: Row(
          children: [
            const SizedBox(width: 12),
            const Icon(Icons.subdirectory_arrow_right, size: 14, color: Colors.grey),
            const SizedBox(width: 8),
            _Cell(p.name, flex: 1, color: Colors.blue.shade800),
            _Cell("Batch: ${cleanBatch(p.batch)}", width: 120, color: Colors.grey.shade700),
            _Cell("In Stock: ${p.stock}", width: 120, color: Colors.green, fontWeight: FontWeight.bold),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    double totalLoss = _selectedItems.fold(0.0, (sum, i) => sum + i.lossValue);
    return Container(
      padding: const EdgeInsets.all(24), color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Text("TOTAL FINANCIAL LOSS: ", style: TextStyle(fontWeight: FontWeight.bold)),
          Text("₹${totalLoss.toStringAsFixed(2)}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.red)),
        ],
      ),
    );
  }
}

class _WriteOffRow {
  Product product;
  int qty;
  String reason;
  double lossValue;
  _WriteOffRow({required this.product, required this.qty, required this.reason, required this.lossValue});
}

class _Hdr extends StatelessWidget {
  final String title; final double? width; final int? flex; final TextAlign align;
  const _Hdr(this.title, {this.width, this.flex, this.align = TextAlign.left});
  @override Widget build(BuildContext context) {
    Widget child = Container(width: width, alignment: align == TextAlign.left ? Alignment.centerLeft : Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)));
    return flex != null ? Expanded(flex: flex!, child: child) : child;
  }
}

class _Cell extends StatelessWidget {
  final String text; final double? width; final int? flex; final TextAlign align; final Color? color; final FontWeight fontWeight;
  const _Cell(this.text, {this.width, this.flex, this.align = TextAlign.left, this.color, this.fontWeight = FontWeight.w600});
  @override Widget build(BuildContext context) {
    Widget child = Container(width: width, alignment: align == TextAlign.left ? Alignment.centerLeft : Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(text, style: TextStyle(fontSize: 13, color: color ?? Colors.black87, fontWeight: fontWeight), overflow: TextOverflow.ellipsis));
    return flex != null ? Expanded(flex: flex!, child: child) : child;
  }
}
