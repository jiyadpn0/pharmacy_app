import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/pharmacy_provider.dart';
import '../utils/app_formatters.dart';
import '../utils/theme_constants.dart';
import '../widgets/app_strict_autocomplete.dart';

class QuickAdjustDialog extends StatefulWidget {
  const QuickAdjustDialog({super.key});

  @override
  State<QuickAdjustDialog> createState() => _QuickAdjustDialogState();
}

class _QuickAdjustDialogState extends State<QuickAdjustDialog> {
  final TextEditingController _productCtrl = TextEditingController();
  final TextEditingController _batchCtrl = TextEditingController();
  final TextEditingController _actualStockCtrl = TextEditingController();
  final TextEditingController _reasonCtrl = TextEditingController(text: "Physical Verification");
  final TextEditingController _doneByCtrl = TextEditingController(text: "ADMIN");

  final FocusNode _reasonFocus = FocusNode();
  final FocusNode _doneByFocus = FocusNode();

  Product? _selectedProduct;
  Product? _selectedBatch;
  Key _batchDropdownKey = UniqueKey();
  String _reason = "Physical Verification";
  String _doneBy = "ADMIN";
  int _systemStock = 0;
  bool _isLoading = false;
  String? _focusedProductText;

  @override
  void dispose() {
    _productCtrl.dispose();
    _batchCtrl.dispose();
    _actualStockCtrl.dispose();
    _reasonCtrl.dispose();
    _doneByCtrl.dispose();
    _reasonFocus.dispose();
    _doneByFocus.dispose();
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

      final finalDoneBy = _doneByCtrl.text.trim().isEmpty ? "ADMIN" : _doneByCtrl.text.trim();
      final finalReason = _reasonCtrl.text.trim().isEmpty ? "PHYSICAL VERIFICATION" : _reasonCtrl.text.trim();

      final nextNo = await provider.getNextAdjustmentNo();
      final adjustment = StockAdjustment(
        entryNo: nextNo,
        date: DateTime.now(),
        doneBy: finalDoneBy.toUpperCase(),
        reason: finalReason.toUpperCase(),
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

    final int totalStock = _selectedProduct == null
        ? 0
        : provider.products
            .where((p) => p.name.trim().toLowerCase() == _selectedProduct!.name.trim().toLowerCase())
            .fold<int>(0, (sum, p) => sum + p.stock);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 480,
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
              optionsViewBuilder: (context, onSelected, options) {
                final highlightedIndex = AutocompleteHighlightedOption.of(context);
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 6.0,
                    borderRadius: BorderRadius.circular(6),
                    color: Colors.white,
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 250),
                      width: 400,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
                        itemBuilder: (context, index) {
                          final option = options.elementAt(index);
                          final isHighlighted = (highlightedIndex == index) || (highlightedIndex == -1 && index == 0);
                          return InkWell(
                            onTap: () => onSelected(option),
                            child: Container(
                              color: isHighlighted ? Colors.grey.shade300 : Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Text(
                                option.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w500,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
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
                  onSubmitted: (_) {
                    onSubmitted();
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
                  flex: 5,
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
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Batch Stock", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
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
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Total Stock", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal)),
                      const SizedBox(height: 4),
                      Container(
                        height: 38,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          border: Border.all(color: Colors.teal.shade200),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "$totalStock",
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade800),
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
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Actual Count", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green)),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 32,
                        child: TextField(
                          controller: _actualStockCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          ),
                          onChanged: (_) {
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: Builder(
                    builder: (context) {
                      final int physicalStock = int.tryParse(_actualStockCtrl.text) ?? _systemStock;
                      final int variance = physicalStock - _systemStock;
                      final String diffText = variance == 0 ? "0" : (variance > 0 ? "+$variance" : "$variance");
                      final Color textColor = variance == 0 ? Colors.grey : (variance > 0 ? Colors.green : Colors.red);
                      final Color bgColor = variance == 0 ? Colors.grey.shade50 : (variance > 0 ? Colors.green.shade50 : Colors.red.shade50);
                      final Color borderColor = variance == 0 ? Colors.grey.shade300 : (variance > 0 ? Colors.green.shade300 : Colors.red.shade300);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Diff", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
                          const SizedBox(height: 4),
                          Container(
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: bgColor,
                              border: Border.all(color: borderColor),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              diffText,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: AppStrictAutocomplete(
                    label: "Reason",
                    controller: _reasonCtrl,
                    focusNode: _reasonFocus,
                    items: const ["Physical Verification", "Packing Correction", "Damage", "Expiry"],
                    defaultOption: "Physical Verification",
                    isStrict: true,
                    height: 32,
                    onValueChanged: (val) {
                      setState(() {
                        _reason = val.isEmpty ? "Physical Verification" : val;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: AppStrictAutocomplete(
                    label: "Done By",
                    controller: _doneByCtrl,
                    focusNode: _doneByFocus,
                    getItems: () => provider.doneByNames,
                    defaultOption: "ADMIN",
                    isStrict: false,
                    height: 32,
                    onValueChanged: (val) {
                      setState(() {
                        _doneBy = val.isEmpty ? "ADMIN" : val;
                      });
                    },
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