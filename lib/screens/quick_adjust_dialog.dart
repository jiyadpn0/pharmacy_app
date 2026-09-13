import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/pharmacy_provider.dart';
import '../utils/app_formatters.dart';
import '../utils/theme_constants.dart';

class QuickAdjustDialog extends StatefulWidget {
  const QuickAdjustDialog({super.key});

  @override
  State<QuickAdjustDialog> createState() => _QuickAdjustDialogState();
}

class _QuickAdjustDialogState extends State<QuickAdjustDialog> {
  final TextEditingController _productCtrl = TextEditingController();
  final TextEditingController _batchCtrl = TextEditingController();
  final TextEditingController _actualStockCtrl = TextEditingController();

  Product? _selectedProduct;
  Product? _selectedBatch;
  Key _batchDropdownKey = UniqueKey();
  String _reason = "Packing Correction";
  int _systemStock = 0;
  bool _isLoading = false;
  String? _focusedProductText;

  @override
  void dispose() {
    _productCtrl.dispose();
    _batchCtrl.dispose();
    _actualStockCtrl.dispose();
    super.dispose();
  }

  void _onProductSelected(Product p) {
    setState(() {
      _selectedProduct = p;
      _productCtrl.text = p.name;
      _selectedBatch = null;
      _batchCtrl.clear();
      _systemStock = 0;
      _actualStockCtrl.clear();
      _batchDropdownKey = UniqueKey(); // Forces dropdown rebuild with clean state
    });
  }

  void _onBatchSelected(Product b) {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    // Re-fetch the live instance from the provider to avoid stale cache
    final liveBatch = provider.products.firstWhere(
      (p) => p.id == b.id && p.batch == b.batch,
      orElse: () => b,
    );

    setState(() {
      _selectedBatch = liveBatch;
      _batchCtrl.text = cleanBatch(liveBatch.batch);
      _systemStock = liveBatch.stock;
      _actualStockCtrl.text = liveBatch.stock.toString();
    });
  }

  Future<void> _saveAdjustment() async {
    if (_selectedBatch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a valid product and batch")),
      );
      return;
    }

    final int physicalStock = int.tryParse(_actualStockCtrl.text) ?? _systemStock;
    final int variance = physicalStock - _systemStock;

    if (variance == 0) {
      Navigator.of(context).pop();
      return;
    }

    // Prevent deducting more stock than physically exists
    if (variance < 0 && physicalStock < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Physical count cannot be negative!"), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);
    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    try {
      final int pack = _selectedBatch!.packSize > 0 ? _selectedBatch!.packSize : 1;
      // Landing cost per single loose tablet/capsule
      final double unitLandingCost = _selectedBatch!.landingCost > 0 
          ? (_selectedBatch!.landingCost / pack) 
          : (_selectedBatch!.purchaseRate / pack);

      final adjustmentItem = StockAdjustmentItem(
        product: _selectedBatch!,
        qty: variance, // Negative for deduction, positive for addition
        purchaseRate: _selectedBatch!.purchaseRate,
        total: variance * unitLandingCost,
      );

      final nextNo = await provider.getNextAdjustmentNo();
      final adjustment = StockAdjustment(
        entryNo: nextNo,
        date: DateTime.now(),
        doneBy: "ADMIN (QUICK ADJUST)",
        reason: _reason.toUpperCase(),
        items: [adjustmentItem],
        grandTotal: variance * unitLandingCost,
      );

      await provider.saveStockAdjustment(adjustment);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Stock adjusted (${variance > 0 ? '+$variance' : '$variance'} units) successfully!"),
            backgroundColor: Colors.green.shade800,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Adjustment failed: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final provider = Provider.of<PharmacyProvider>(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.build_circle_rounded, color: Colors.blue.shade400, size: 24),
                const SizedBox(width: 8),
                Text(
                  "Quick Stock Adjustment",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: c.primaryText),
                ),
              ],
            ),
            const Divider(height: 24, thickness: 1),

            const Text("Product Name", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Autocomplete<Product>(
              displayStringForOption: (Product p) => p.name,
              optionsBuilder: (TextEditingValue value) {
                if (value.text.trim().isEmpty) return const Iterable<Product>.empty();
                final query = value.text.trim().toLowerCase();
                if (_focusedProductText != null &&
                    value.text == _focusedProductText &&
                    provider.products.any((p) => p.name.trim().toLowerCase() == query)) {
                  return const Iterable<Product>.empty();
                }
                return provider.searchProducts(value.text.trim(), includeGenerics: false);
              },
              onSelected: _onProductSelected,
              fieldViewBuilder: (ctx, ctrl, focus, onSubmitted) {
                focus.addListener(() {
                  if (focus.hasFocus) {
                    _focusedProductText = ctrl.text;
                  } else {
                    _focusedProductText = null;
                  }
                });
                return TextField(
                  controller: ctrl,
                  focusNode: focus,
                  onTap: () {
                    if (focus.hasFocus) {
                      _focusedProductText = ctrl.text;
                    }
                  },
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: "Search Product...",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Batch", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Builder(
                        builder: (context) {
                          final batchList = _selectedProduct == null
                              ? <Product>[]
                              : provider.products
                              .where((p) => p.name.toLowerCase() == _selectedProduct!.name.toLowerCase() && p.stock > 0)
                              .toSet()
                              .toList();
                          final safeBatch = batchList.contains(_selectedBatch) ? _selectedBatch : null;

                          return DropdownButtonFormField<Product>(
                            key: _batchDropdownKey, // Add key here
                            initialValue: safeBatch,  // Use safe value
                            isExpanded: true,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            hint: const Text("Select Batch", style: TextStyle(fontSize: 11)),
                            items: batchList
                                .map((b) => DropdownMenuItem(
                              value: b,
                              child: Text("${cleanBatch(b.batch)} (Qty: ${b.stock})", style: const TextStyle(fontSize: 11)),
                            ))
                                .toList(),
                            onChanged: (Product? b) {
                              if (b != null) _onBatchSelected(b);
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("System Stock", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                      const SizedBox(height: 4),
                      Container(
                        height: 38,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.shade50,
                          border: Border.all(color: Colors.blueGrey.shade200),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "$_systemStock",
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Actual Count", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _actualStockCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Reason", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Builder(
                        builder: (context) {
                          final reasons = {"Packing Correction", "Damage", "Expiry", "Physical Verification"}.toList();
                          final safeReason = reasons.contains(_reason) ? _reason : reasons.first;

                          return DropdownButtonFormField<String>(
                            initialValue: safeReason,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            items: reasons
                                .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 11))))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _reason = v);
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CANCEL", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _saveAdjustment,
                  icon: const Icon(Icons.check, size: 16, color: Colors.white),
                  label: const Text("SAVE ADJUSTMENT", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}