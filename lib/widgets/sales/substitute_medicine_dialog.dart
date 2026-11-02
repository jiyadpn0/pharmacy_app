import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/pharmacy_provider.dart';
import '../../utils/theme_constants.dart';

class SubstituteMedicineDialog extends StatefulWidget {
  final String originalProductName;
  final String genericName;

  const SubstituteMedicineDialog({
    super.key,
    required this.originalProductName,
    required this.genericName,
  });

  static Future<Product?> show(
    BuildContext context, {
    required String originalProductName,
    required String genericName,
  }) {
    return showDialog<Product>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => SubstituteMedicineDialog(
        originalProductName: originalProductName,
        genericName: genericName,
      ),
    );
  }

  @override
  State<SubstituteMedicineDialog> createState() => _SubstituteMedicineDialogState();
}

class _SubstituteMedicineDialogState extends State<SubstituteMedicineDialog> {
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollCtrl = ScrollController();
  List<Product> _substitutes = [];
  int _selectedIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSubstitutes();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _loadSubstitutes() {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final targetSalt = widget.genericName.trim().toLowerCase();

    final matches = provider.products.where((p) {
      if (p.stock <= 0) return false;
      if (p.name.trim().toLowerCase() == widget.originalProductName.trim().toLowerCase()) return false;
      final gen = p.genericName.trim().toLowerCase();
      if (targetSalt.isNotEmpty && gen.contains(targetSalt)) return true;
      return false;
    }).toList();

    // Sort by highest stock first, then lowest sale price
    matches.sort((a, b) {
      int stockCmp = b.stock.compareTo(a.stock);
      if (stockCmp != 0) return stockCmp;
      return a.salePrice.compareTo(b.salePrice);
    });

    setState(() {
      _substitutes = matches;
      _isLoading = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _selectProduct(Product product) {
    Navigator.of(context).pop(product);
  }

  void _scrollToSelected() {
    if (!_scrollCtrl.hasClients || _substitutes.isEmpty) return;
    const double itemHeight = 44.0;
    const double viewport = 300.0;
    double target = _selectedIndex * itemHeight;
    double current = _scrollCtrl.offset;

    if (target < current) {
      _scrollCtrl.jumpTo(target);
    } else if (target + itemHeight > current + viewport) {
      _scrollCtrl.jumpTo(target - viewport + itemHeight);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.secondary : AppColors.primary;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          if (_substitutes.isNotEmpty) {
            setState(() {
              _selectedIndex = (_selectedIndex + 1) % _substitutes.length;
            });
            _scrollToSelected();
          }
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          if (_substitutes.isNotEmpty) {
            setState(() {
              _selectedIndex = (_selectedIndex - 1 + _substitutes.length) % _substitutes.length;
            });
            _scrollToSelected();
          }
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          if (_substitutes.isNotEmpty && _selectedIndex < _substitutes.length) {
            _selectProduct(_substitutes[_selectedIndex]);
          }
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop(null);
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          width: 720,
          constraints: const BoxConstraints(maxHeight: 520),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2638) : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Banner
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.swap_horiz_rounded, color: Colors.amber, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              "Out of Stock: ",
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent, fontSize: 13),
                            ),
                            Expanded(
                              child: Text(
                                widget.originalProductName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          "Generic Composition: ${widget.genericName.isEmpty ? 'N/A' : widget.genericName}",
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(null),
                  )
                ],
              ),
              const Divider(height: 20),

              // Subtitle instruction
              Text(
                "Available In-Stock Substitutes (${_substitutes.length} found):",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 8),

              // Content Body
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _substitutes.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.remove_shopping_cart_outlined, size: 48, color: Colors.grey[400]),
                                const SizedBox(height: 12),
                                Text(
                                  "No in-stock substitute found with composition '${widget.genericName}'",
                                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                // Table Header
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  color: isDark ? const Color(0xFF2B364E) : Colors.grey[100],
                                  child: const Row(
                                    children: [
                                      Expanded(flex: 4, child: Text("Brand Name / Mfr", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                      Expanded(flex: 2, child: Text("Rack", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                      Expanded(flex: 2, child: Text("Stock", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                      Expanded(flex: 2, child: Text("MRP", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                      Expanded(flex: 2, child: Text("Sale Rate", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                      SizedBox(width: 60, child: Text("Action", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1),
                                // Table List
                                Expanded(
                                  child: ListView.builder(
                                    controller: _scrollCtrl,
                                    itemCount: _substitutes.length,
                                    itemBuilder: (ctx, idx) {
                                      final item = _substitutes[idx];
                                      final isSelected = idx == _selectedIndex;

                                      return InkWell(
                                        onTap: () => _selectProduct(item),
                                        child: Container(
                                          height: 44,
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          color: isSelected
                                              ? (isDark ? primaryColor.withValues(alpha: 0.35) : primaryColor.withValues(alpha: 0.12))
                                              : (idx % 2 == 0
                                                  ? (isDark ? Colors.transparent : Colors.grey[50])
                                                  : (isDark ? Colors.white.withValues(alpha: 0.02) : Colors.white)),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                flex: 4,
                                                child: Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      item.name,
                                                      style: TextStyle(
                                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                                        fontSize: 12,
                                                        color: isSelected ? primaryColor : null,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    if (item.manufacturer.isNotEmpty)
                                                      Text(
                                                        item.manufacturer,
                                                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  item.rack.isEmpty ? '-' : item.rack,
                                                  style: const TextStyle(fontSize: 11),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    "${item.stock} ${item.packSize > 1 ? 'tabs' : 'units'}",
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.green,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  "₹${item.mrp.toStringAsFixed(2)}",
                                                  style: const TextStyle(fontSize: 11),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  "₹${item.salePrice.toStringAsFixed(2)}",
                                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 60,
                                                child: ElevatedButton(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: primaryColor,
                                                    padding: EdgeInsets.zero,
                                                    minimumSize: const Size(54, 26),
                                                  ),
                                                  onPressed: () => _selectProduct(item),
                                                  child: const Text("Select", style: TextStyle(fontSize: 10, color: Colors.white)),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
              ),

              const SizedBox(height: 12),
              // Footer instructions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.keyboard_arrow_down, size: 16),
                      const Icon(Icons.keyboard_arrow_up, size: 16),
                      const Text(" Navigate   ", style: TextStyle(fontSize: 11, color: Colors.grey)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(3)),
                        child: const Text("Enter", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const Text(" Select Substitute   ", style: TextStyle(fontSize: 11, color: Colors.grey)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(3)),
                        child: const Text("Esc", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const Text(" Cancel", style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text("Cancel"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
