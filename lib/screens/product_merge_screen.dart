import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pharmacy_provider.dart';
import '../utils/theme_constants.dart';
import '../widgets/pin_unlock_dialog.dart';

class ProductMergeScreen extends StatefulWidget {
  const ProductMergeScreen({super.key});

  @override
  State<ProductMergeScreen> createState() => _ProductMergeScreenState();
}

class _ProductMergeScreenState extends State<ProductMergeScreen> {
  Product? _duplicateProduct; // The duplicate to be deleted
  Product? _targetProduct;    // The master product to keep

  final TextEditingController _dupCtrl = TextEditingController();
  final TextEditingController _targetCtrl = TextEditingController();

  @override
  void dispose() {
    _dupCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _executeMerge(PharmacyProvider provider) async {
    if (_duplicateProduct == null || _targetProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select both source and target products.")));
      return;
    }

    if (_duplicateProduct!.id == _targetProduct!.id) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cannot merge a product into itself.")));
      return;
    }

    if (provider.securityToggles['require_pin_merge_products'] == true) {
      bool isUnlocked = await PinUnlockDialog.show(
        context, 
        provider, 
        title: "Security Clearance", 
        message: "Enter Master PIN to authorize product consolidation.",
      );
      if (!isUnlocked) return; 
    }

    bool confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Product Merge"),
        content: Text("Are you sure you want to merge '${_duplicateProduct!.name}' into '${_targetProduct!.name}'?\n\nAll historical sales, purchases, and stock batches will transfer to '${_targetProduct!.name}', and '${_duplicateProduct!.name}' will be permanently deleted."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("YES, MERGE NOW", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    await provider.mergeProducts(
      keepProductId: _targetProduct!.id,
      deleteProductId: _duplicateProduct!.id,
    );

    if (provider.errorMessage.isEmpty) {
      provider.logAudit('MERGE_PRODUCTS', 'Merged duplicate [${_duplicateProduct!.name}] into target [${_targetProduct!.name}].');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text("Products successfully merged!")));
        setState(() {
          _duplicateProduct = null;
          _targetProduct = null;
          _dupCtrl.clear();
          _targetCtrl.clear();
        });
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(provider.errorMessage), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final provider = Provider.of<PharmacyProvider>(context);

    return Scaffold(
      backgroundColor: c.background,
      body: Center(
        child: Container(
          width: 720,
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.05), blurRadius: 20, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.call_merge_rounded, color: Colors.white, size: 26),
                    SizedBox(width: 14),
                    Text("Merge Duplicate Products", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(14),
                color: Colors.orange.shade50,
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        "All transaction history and stock batches from the duplicate product will be moved to the target product. The duplicate will be removed.",
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("1. Select Duplicate (To Delete)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent, fontSize: 12)),
                          const SizedBox(height: 8),
                          _buildSearchField(
                            provider: provider,
                            controller: _dupCtrl,
                            hint: "Search duplicate product...",
                            onSelected: (p) => setState(() => _duplicateProduct = p),
                          ),
                          if (_duplicateProduct != null) _buildProductCard(_duplicateProduct!, Colors.red.shade50),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 32),
                      child: Icon(Icons.arrow_forward_rounded, color: Colors.blueGrey, size: 28),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("2. Select Target (To Keep)", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.success, fontSize: 12)),
                          const SizedBox(height: 8),
                          _buildSearchField(
                            provider: provider,
                            controller: _targetCtrl,
                            hint: "Search master target product...",
                            onSelected: (p) => setState(() => _targetProduct = p),
                          ),
                          if (_targetProduct != null) _buildProductCard(_targetProduct!, Colors.green.shade50),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.merge_type_rounded, color: Colors.white, size: 18),
                    label: const Text("EXECUTE DATABASE MERGE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: () => _executeMerge(provider),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField({
    required PharmacyProvider provider,
    required TextEditingController controller,
    required String hint,
    required Function(Product) onSelected,
  }) {
    String? focusedText;
    return Autocomplete<Product>(
      displayStringForOption: (Product p) => p.name,
      optionsBuilder: (TextEditingValue val) {
        if (val.text.isEmpty) return const Iterable<Product>.empty();
        final query = val.text.trim().toLowerCase();
        if (focusedText != null &&
            val.text == focusedText &&
            provider.products.any((p) => p.name.trim().toLowerCase() == query)) {
          return const Iterable<Product>.empty();
        }
        return provider.searchProducts(val.text, includeGenerics: false);
      },
      onSelected: onSelected,
      fieldViewBuilder: (ctx, ctrl, focus, onSubmit) {
        focus.addListener(() {
          if (focus.hasFocus) {
            focusedText = ctrl.text;
          } else {
            focusedText = null;
          }
        });
        return TextField(
          controller: ctrl,
          focusNode: focus,
          onTap: () {
            if (focus.hasFocus) {
              focusedText = ctrl.text;
            }
          },
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.search, size: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            isDense: true,
          ),
        );
      },
    );
  }

  Widget _buildProductCard(Product p, Color bg) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 4),
          Text("Stock: ${p.stock} units | Pack: ${p.packSize}", style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
          Text("ID: ${p.id}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }
}
