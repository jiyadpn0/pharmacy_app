import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pharmacy_provider.dart';
import '../providers/mdi_controller.dart';
import '../screens/master/product_registration_screen.dart';

class ImportFormatSelectionDialog extends StatelessWidget {
  final PharmacyProvider provider;
  final Function(ImportMapping) onFormatSelected;
  final Function(ImportMapping, int) onEdit;
  final Function(bool) onAddNew;
  final Function(ImportMapping?)? closeWindow;
  final bool isGmailSelector;

  const ImportFormatSelectionDialog({
    super.key,
    required this.provider,
    required this.onFormatSelected,
    required this.onEdit,
    required this.onAddNew,
    this.closeWindow,
    this.isGmailSelector = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.grey.shade50,
            child: Row(
              children: [
                const Text("Format Manager", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                if (!isGmailSelector) ...[
                  const Spacer(),
                  const Text(
                    "CREATE NEW : ",
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                    ),
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.table_chart, size: 14),
                    label: const Text("Excel", style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10)),
                    onPressed: () => onAddNew(false),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf, size: 14),
                    label: const Text("PDF", style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10)),
                    onPressed: () => onAddNew(true),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Choose a previously saved format to instantly map columns.", style: TextStyle(fontSize: 13, color: Colors.blueGrey)),
                const SizedBox(height: 15),

                Consumer<PharmacyProvider>(
                    builder: (context, prov, child) {
                      List<ImportMapping> allMappings = prov.importMappings;

                      if (allMappings.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(20),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                          child: const Text("No saved formats yet. Click a format button above or import an invoice to create one.", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                        );
                      }

                      Map<String, Map<String, ImportMapping>> grouped = {};
                      for (var m in allMappings) {
                        String baseName = m.name.replaceAll(' - PDF', '').replaceAll(' - EXCEL', '').trim();
                        if (!grouped.containsKey(baseName)) grouped[baseName] = {};
                        if (m.name.toUpperCase().endsWith('- EXCEL')) {
                          grouped[baseName]!['EXCEL'] = m;
                        } else if (m.name.toUpperCase().endsWith('- PDF')) {
                          grouped[baseName]!['PDF'] = m;
                        }
                      }
                      var supplierNames = grouped.keys.toList()..sort();

                      return SizedBox(
                        height: 300,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: supplierNames.length,
                          itemBuilder: (ctx, i) {
                            final name = supplierNames[i];
                            final formats = grouped[name]!;
                            final excelMap = formats['EXCEL'];
                            final pdfMap = formats['PDF'];

                            return Card(
                              elevation: 1,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (excelMap != null)
                                      _buildCompactAction(ctx, prov, excelMap, Icons.table_chart, Colors.blue.shade800, "EXCEL"),
                                    if (excelMap != null && pdfMap != null)
                                      const SizedBox(width: 10),
                                    if (pdfMap != null)
                                      _buildCompactAction(ctx, prov, pdfMap, Icons.picture_as_pdf, Colors.red.shade800, "PDF"),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    }
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () {
                      if (closeWindow != null) {
                        closeWindow!(null);
                      } else {
                        try {
                          final mdi = Provider.of<MdiController>(context, listen: false);
                          if (mdi.windows.any((w) => w.id == "format_manager_import" || w.id == "format_manager")) {
                            mdi.closeWindow("format_manager_import");
                            mdi.closeWindow("format_manager");
                            return;
                          }
                        } catch (_) {}
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                      }
                    },
                    child: const Text("CLOSE")
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactAction(BuildContext context, PharmacyProvider prov, ImportMapping m, IconData icon, Color color, String label) {
    int actualIndex = prov.importMappings.indexOf(m);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Select Format for Immediate Import
          InkWell(
            onTap: () => onFormatSelected(m),
            child: Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(width: 1, height: 14, color: color.withValues(alpha: 0.3)),
          const SizedBox(width: 4),

          // Edit Format
          Tooltip(
            message: "Edit $label Format Settings",
            child: InkWell(
              onTap: () => onEdit(m, actualIndex),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2.0),
                child: Icon(Icons.edit_note_rounded, color: Colors.blue, size: 18),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Container(width: 1, height: 14, color: color.withValues(alpha: 0.3)),
          const SizedBox(width: 4),

          // Delete Format
          Tooltip(
            message: "Delete $label Format",
            child: InkWell(
              onTap: () => prov.deleteImportMapping(actualIndex),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2.0),
                child: Icon(Icons.delete_forever_rounded, color: Colors.red, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProductMappingDialog extends StatefulWidget {
  final String wholesalerName;
  final List<PurchaseItem> unknownItems;
  final PharmacyProvider provider;
  final Function(List<PurchaseItem>?) onImportRequested;

  const ProductMappingDialog({
    super.key,
    required this.wholesalerName,
    required this.unknownItems,
    required this.provider,
    required this.onImportRequested,
  });

  @override
  State<ProductMappingDialog> createState() => _ProductMappingDialogState();
}

class _ProductMappingDialogState extends State<ProductMappingDialog> {
  final Map<int, Product?> _selectedMappings = {};
  final Map<int, String> _customProductNames = {};
  final Map<int, TextEditingController> _searchControllers = {};
  final Map<int, FocusNode> _focusNodes = {};
  final FocusNode _saveButtonFocusNode = FocusNode();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  FocusNode _getFocusNode(int index) {
    return _focusNodes.putIfAbsent(index, () => FocusNode());
  }

  TextEditingController _getSearchController(int index) {
    return _searchControllers.putIfAbsent(index, () => TextEditingController());
  }

  void _moveToNextBox(int currentIndex) {
    if (currentIndex < widget.unknownItems.length - 1) {
      _getFocusNode(currentIndex + 1).requestFocus();
    } else {
      _saveButtonFocusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    for (var ctrl in _searchControllers.values) {
      ctrl.dispose();
    }
    for (var node in _focusNodes.values) {
      node.dispose();
    }
    _saveButtonFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final prods = widget.provider.productMaster;
    if (mounted) {
      setState(() {
        _isLoading = false;
        for (int i = 0; i < widget.unknownItems.length; i++) {
          final extName = widget.unknownItems[i].externalName.trim().toLowerCase();
          final extCode = widget.unknownItems[i].externalCode.trim().toLowerCase();

          Product? exact;
          if (extCode.isNotEmpty) {
            try {
              exact = prods.firstWhere(
                (p) => p.id.trim().toLowerCase() == extCode,
              );
            } catch (_) {}
          }
          if (exact == null) {
            try {
              exact = prods.firstWhere(
                (p) => p.name.trim().toLowerCase() == extName,
              );
            } catch (_) {}
          }

          if (exact != null) {
            _selectedMappings[i] = exact;
            _getSearchController(i).text = exact.name;
          } else {
            _getSearchController(i).text = "";
          }
        }
      });
    }
  }

  void _createNewProduct(int index) async {
    final extName = widget.unknownItems[index].externalName;

    final result = await showDialog<dynamic>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 600,
          height: 580,
          child: ProductRegistrationScreen(
            initialName: extName,
            isCompact: true,
          ),
        ),
      ),
    );

    final updatedProds = widget.provider.productMaster;
    if (mounted) {
      setState(() {
        Product? newProd;
        if (result is Product) {
          newProd = result;
        } else {
          try {
            newProd = updatedProds.firstWhere(
              (p) => p.name.trim().toLowerCase() == extName.trim().toLowerCase(),
            );
          } catch (_) {}
        }

        if (newProd != null) {
          _selectedMappings[index] = newProd;
          _customProductNames.remove(index);
          _getSearchController(index).text = newProd.name;
        }
      });
    }
  }

  void _saveMappingsAndImport() async {
    for (int i = 0; i < widget.unknownItems.length; i++) {
      if (_selectedMappings[i] == null) {
        final text = _getSearchController(i).text.trim();
        if (text.isNotEmpty) {
          try {
            final match = widget.provider.productMaster.firstWhere(
              (p) => p.name.trim().toLowerCase() == text.toLowerCase(),
            );
            _selectedMappings[i] = match;
          } catch (_) {}
        }
      }

      final extName = widget.unknownItems[i].externalName;
      final extCode = widget.unknownItems[i].externalCode;
      final mappedProd = _selectedMappings[i];

      if (mappedProd != null) {
        await widget.provider.saveProductMapping(
          ProductMapping(
            wholesalerName: widget.wholesalerName,
            externalCode: extCode,
            externalName: extName,
            internalName: mappedProd.name,
            productId: mappedProd.id,
          ),
        );
      }
    }

    List<PurchaseItem> result = [];
    for (int i = 0; i < widget.unknownItems.length; i++) {
      final base = widget.unknownItems[i];
      final mappedProd = _selectedMappings[i];

      if (mappedProd != null) {
        result.add(PurchaseItem(
          id: mappedProd.id,
          productName: mappedProd.name,
          externalName: base.externalName,
          externalCode: base.externalCode,
          batch: base.batch,
          expiry: base.expiry,
          packin: base.packin > 0 ? base.packin : mappedProd.packSize,
          qty: base.qty,
          fQty: base.fQty,
          mrp: base.mrp > 0 ? base.mrp : mappedProd.mrp,
          pRate: base.pRate > 0 ? base.pRate : mappedProd.purchaseRate,
          sRate: base.sRate > 0 ? base.sRate : mappedProd.salePrice,
          discPercent: base.discPercent,
          gstPercent: base.gstPercent > 0 ? base.gstPercent : 12.0,
          hsnCode: base.hsnCode.isNotEmpty ? base.hsnCode : mappedProd.hsnCode,
        ));
      } else {
        String finalName = _customProductNames[i] ?? base.externalName;
        result.add(PurchaseItem(
          id: base.externalCode.isNotEmpty ? base.externalCode : "UNMAPPED_${i + 1}",
          productName: finalName,
          externalName: base.externalName,
          externalCode: base.externalCode,
          batch: base.batch,
          expiry: base.expiry,
          packin: base.packin,
          qty: base.qty,
          fQty: base.fQty,
          mrp: base.mrp,
          pRate: base.pRate,
          sRate: base.sRate,
          discPercent: base.discPercent,
          gstPercent: base.gstPercent,
          hsnCode: base.hsnCode,
        ));
      }
    }

    widget.onImportRequested(result);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 250,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.blue.shade50,
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Map unknown products from '${widget.wholesalerName}' to internal inventory. Mappings are remembered for future imports.",
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: widget.unknownItems.length,
            separatorBuilder: (ctx, i) => const Divider(),
            itemBuilder: (ctx, index) {
              final item = widget.unknownItems[index];
              final bool isMapped = _selectedMappings[index] != null;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.externalName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              color: Colors.black87,
                            ),
                          ),
                          if (item.externalCode.isNotEmpty)
                            Text("Code: ${item.externalCode}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          Text("Batch: ${item.batch} | Exp: ${item.expiry} | Qty: ${item.qty} | MRP: ₹${item.mrp}", style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward, color: Colors.grey, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: RawAutocomplete<Product>(
                        focusNode: _getFocusNode(index),
                        textEditingController: _getSearchController(index),
                        displayStringForOption: (Product p) => p.name,
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          final query = textEditingValue.text.trim();
                          if (query.isEmpty) {
                            return const Iterable<Product>.empty();
                          }
                          return widget.provider.searchProducts(query, includeGenerics: true);
                        },
                        onSelected: (Product selection) {
                          setState(() {
                            _selectedMappings[index] = selection;
                            _customProductNames.remove(index);
                            _getSearchController(index).text = selection.name;
                          });
                          _moveToNextBox(index);
                        },
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          focusNode.addListener(() {
                            if (!focusNode.hasFocus) {
                              final selected = _selectedMappings[index];
                              if (selected == null || controller.text.trim() != selected.name.trim()) {
                                if (selected != null) {
                                  controller.text = selected.name;
                                } else {
                                  controller.clear();
                                }
                              }
                            }
                          });

                          if (_selectedMappings[index] != null && controller.text.isEmpty) {
                            controller.text = _selectedMappings[index]!.name;
                          }

                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            style: TextStyle(
                              color: isMapped ? Colors.green.shade900 : Colors.black87,
                              fontWeight: isMapped ? FontWeight.w600 : FontWeight.normal,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: "Search internal product...",
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: const OutlineInputBorder(),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: isMapped ? Colors.green.shade600 : Colors.grey.shade400,
                                  width: isMapped ? 1.5 : 1.0,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: isMapped ? Colors.green.shade700 : Colors.blue,
                                  width: 2.0,
                                ),
                              ),
                              suffixIcon: isMapped
                                  ? IconButton(
                                      icon: const Icon(Icons.check_circle, color: Colors.green, size: 18),
                                      onPressed: () {
                                        controller.clear();
                                        setState(() {
                                          _selectedMappings.remove(index);
                                          _customProductNames.remove(index);
                                        });
                                      },
                                    )
                                  : (controller.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, size: 16),
                                          onPressed: () {
                                            controller.clear();
                                            setState(() {
                                              _selectedMappings.remove(index);
                                              _customProductNames.remove(index);
                                            });
                                          },
                                        )
                                      : null),
                            ),
                            onSubmitted: (value) {
                              onFieldSubmitted();
                              if (_selectedMappings[index] != null) {
                                _getSearchController(index).text = _selectedMappings[index]!.name;
                                _moveToNextBox(index);
                                return;
                              }
                              final query = value.trim();
                              if (query.isNotEmpty) {
                                final matches = widget.provider.searchProducts(query, includeGenerics: true);
                                if (matches.isNotEmpty) {
                                  final topMatch = matches.first;
                                  setState(() {
                                    _selectedMappings[index] = topMatch;
                                    _customProductNames.remove(index);
                                    _getSearchController(index).text = topMatch.name;
                                  });
                                  _moveToNextBox(index);
                                  return;
                                }
                              }
                              _moveToNextBox(index);
                            },
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 6,
                              borderRadius: BorderRadius.circular(4),
                              color: Colors.white,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 250, maxWidth: 450),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (BuildContext context, int optionIndex) {
                                    final Product option = options.elementAt(optionIndex);
                                    final bool hasStock = option.stock > 0;

                                    return Builder(
                                      builder: (BuildContext context) {
                                        final bool highlight = AutocompleteHighlightedOption.of(context) == optionIndex;

                                        return InkWell(
                                          onTap: () => onSelected(option),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: highlight
                                                  ? (hasStock ? Colors.blue.shade50 : Colors.red.shade50)
                                                  : (hasStock ? Colors.white : Colors.red.shade50.withAlpha(20)),
                                              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        option.name,
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.bold,
                                                          color: highlight ? Colors.blue.shade900 : Colors.black87,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: hasStock ? Colors.green.shade50 : Colors.red.shade50,
                                                        borderRadius: BorderRadius.circular(4),
                                                        border: Border.all(
                                                          color: hasStock ? Colors.green.shade300 : Colors.red.shade300,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        "Stock: ${option.stock}",
                                                        style: TextStyle(
                                                          fontSize: 10.5,
                                                          fontWeight: FontWeight.bold,
                                                          color: hasStock ? Colors.green.shade800 : Colors.red.shade900,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 3),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        [
                                                          if (option.manufacturer.isNotEmpty) option.manufacturer,
                                                          if (option.genericName.isNotEmpty) option.genericName,
                                                        ].join(" • "),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 10.5,
                                                          color: Colors.grey.shade600,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      "MRP: ₹${option.mrp.toStringAsFixed(2)}",
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.black87,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.green),
                      tooltip: "Register New Product in Inventory",
                      onPressed: () => _createNewProduct(index),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            border: Border(top: BorderSide(color: Colors.blue.shade200, width: 1.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "${widget.unknownItems.length} Products to Link",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue.shade900),
              ),
              Row(
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade800,
                      side: BorderSide(color: Colors.grey.shade400),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onPressed: () => widget.onImportRequested(null),
                    child: const Text("CANCEL", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    focusNode: _saveButtonFocusNode,
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: const Text("SAVE MAPPINGS & IMPORT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      elevation: 2,
                    ),
                    onPressed: _saveMappingsAndImport,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
