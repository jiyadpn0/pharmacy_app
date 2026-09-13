import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../providers/pharmacy_provider.dart';
import '../screens/master/product_registration_screen.dart';
import '../database/db_helper.dart';

class ImportFormatSelectionDialog extends StatelessWidget {
  final PharmacyProvider provider;
  final Function(ImportMapping) onFormatSelected;
  final Function(ImportMapping, int) onEdit;
  final Function(bool) onAddNew;
  final Function(ImportMapping?)? closeWindow;

  const ImportFormatSelectionDialog({
    super.key,
    required this.provider,
    required this.onFormatSelected,
    required this.onEdit,
    required this.onAddNew,
    this.closeWindow,
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
                const Spacer(),
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
                          child: const Text("No saved formats yet. Click a green button above to create one.", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
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
                        Navigator.pop(context);
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
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => onFormatSelected(m),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 16, color: color.withValues(alpha: 0.2)),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.edit, color: Colors.blueGrey.shade700, size: 14),
            onPressed: () => onEdit(m, actualIndex),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
            tooltip: "Edit $label Format",
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red, size: 14),
            onPressed: () => prov.deleteImportMapping(actualIndex),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
            tooltip: "Delete $label Format",
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
  final Map<int, Product?> _selectedMatches = {};
  final Map<int, bool> _skipItems = {};
  late List<FocusNode> _focusNodes;
  late List<TextEditingController> _controllers;
  Map<String, int> _productSalesMap = {};

  @override
  void initState() {
    super.initState();
    _focusNodes = List.generate(widget.unknownItems.length, (index) => FocusNode());
    _controllers = List.generate(widget.unknownItems.length, (index) => TextEditingController());
    _initializeMappings();
    _loadSalesVolume();
  }

  void _initializeMappings() {
    for (int i = 0; i < widget.unknownItems.length; i++) {
      final item = widget.unknownItems[i];
      String extName = (item.externalName.isNotEmpty ? item.externalName : item.productName).trim();
      String extCode = item.externalCode.trim();

      // 1. Check if there's an existing saved mapping rule
      final mappedName = widget.provider.getMappedProduct(widget.wholesalerName, extName, extCode);
      Product? match;
      if (mappedName != null && mappedName.isNotEmpty) {
        String cleanMapped = mappedName.trim().toLowerCase();
        match = widget.provider.productMaster.cast<Product?>().firstWhere(
          (p) => p != null && p.name.trim().toLowerCase() == cleanMapped,
          orElse: () => null,
        );
      }

      // 2. Fallback: Check if there's an exact match in Product Master by name or code
      if (match == null) {
        String cleanExt = extName.toLowerCase();
        match = widget.provider.productMaster.cast<Product?>().firstWhere(
          (p) => p != null && (p.name.trim().toLowerCase() == cleanExt || (extCode.isNotEmpty && p.hsnCode.trim() == extCode)),
          orElse: () => null,
        );
      }

      if (match != null) {
        _selectedMatches[i] = match;
        _controllers[i].text = match.name;
      }
    }
  }

  Product? _getValidMatch(int index) {
    if (index < 0 || index >= widget.unknownItems.length) return null;
    final text = _controllers[index].text.trim().toLowerCase();
    if (text.isEmpty) return null;

    final selected = _selectedMatches[index];
    if (selected != null && selected.name.trim().toLowerCase() == text) {
      return selected;
    }

    final exactMatch = widget.provider.productMaster.cast<Product?>().firstWhere(
      (p) => p != null && p.name.trim().toLowerCase() == text,
      orElse: () => null,
    );

    return exactMatch;
  }

  Future<void> _loadSalesVolume() async {
    try {
      final db = await DbHelper.instance.database;
      final res = await db.rawQuery('''
        SELECT product_id, SUM(qty) as total_sold 
        FROM sales_items 
        GROUP BY product_id
      ''');
      if (mounted) {
        setState(() {
          _productSalesMap = {
            for (var r in res)
              (r['product_id']?.toString() ?? ''): ((r['total_sold'] as num?)?.toInt() ?? 0)
          };
        });
      }
    } catch (e) {
      debugPrint("Error loading sales volume: $e");
    }
  }

  @override
  void dispose() {
    for (var node in _focusNodes) {
      node.dispose();
    }
    for (var ctrl in _controllers) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _moveToNext(int currentIndex) {
    if (currentIndex == -1) return;
    int nextIndex = currentIndex + 1;
    while (nextIndex < widget.unknownItems.length) {
      if (_skipItems[nextIndex] != true) {
        _focusNodes[nextIndex].requestFocus();
        break;
      }
      nextIndex++;
    }
  }

  Future<void> _openRegistrationAndAdd(int index, String initialName) async {
    final Product? newProd = await showDialog<Product>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 600,
          height: 680,
          child: ProductRegistrationScreen(
            initialName: initialName,
            isCompact: true,
          ),
        ),
      ),
    );

    if (newProd != null) {
      if (index != -1) {
        setState(() {
          _selectedMatches[index] = newProd;
          _controllers[index].text = newProd.name;
        });
        _moveToNext(index);
      } else {
        // Auto-link new product to any unmapped items matching name
        for (int i = 0; i < widget.unknownItems.length; i++) {
          if (_selectedMatches[i] == null) {
            final unkName = (widget.unknownItems[i].productName.isNotEmpty
                    ? widget.unknownItems[i].productName
                    : widget.unknownItems[i].externalName)
                .trim()
                .toLowerCase();
            final newName = newProd.name.trim().toLowerCase();
            if (unkName == newName || unkName.contains(newName) || newName.contains(unkName)) {
              setState(() {
                _selectedMatches[i] = newProd;
                _controllers[i].text = newProd.name;
              });
              break;
            }
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 950,
      height: 650,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text("Link Unknown Products (${widget.wholesalerName})",
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                      label: const Text("CREATE PRODUCT", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _openRegistrationAndAdd(-1, ""),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  "The following items from Excel don't match your Product Master. Link them to existing products to import them. This will be remembered permanently.",
                  style: TextStyle(fontSize: 14, color: Colors.blueGrey),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: ListView.builder(
                itemCount: widget.unknownItems.length,
                itemBuilder: (ctx, i) {
                  final item = widget.unknownItems[i];
                  final isSkipped = _skipItems[i] ?? false;

                  // --- CORRECTED DISPLAY NAME PRIORITY ---
                  // Force it to use productName first (extracted from your 'itemname' column), 
                  // falling back to externalName only if empty. Never default to code numbers!
                  String displayName = item.productName.trim();
                  if (displayName.isEmpty || RegExp(r'^\d+$').hasMatch(displayName)) {
                    if (item.externalName.trim().isNotEmpty && !RegExp(r'^\d+$').hasMatch(item.externalName.trim())) {
                      displayName = item.externalName.trim();
                    }
                  }

                  String itemCode = item.externalCode.trim();
                  if (itemCode.isEmpty && RegExp(r'^\d+$').hasMatch(item.productName)) {
                    itemCode = item.productName.trim();
                  }

                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: isSkipped ? Colors.grey.shade100 : Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        // 1. MOST LEFT SIDE: Item Code
                        if (itemCode.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text("CODE", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                                Text(
                                  itemCode,
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],

                        // 2. MIDDLE: Item Name (Wholesaler Print)
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Builder(
                                builder: (_) {
                                  double displayMrp = item.mrp;
                                  String displayGen = "";
                                  if (_selectedMatches[i] != null) {
                                    if (displayMrp <= 0) displayMrp = _selectedMatches[i]!.mrp;
                                    displayGen = _selectedMatches[i]!.genericName.trim();
                                  }
                                  String mrpText = displayMrp > 0 ? displayMrp.toStringAsFixed(2) : "0.00";
                                  String genSuffix = displayGen.isNotEmpty ? " | Generic: $displayGen" : "";
                                  return Text(
                                    "MRP: $mrpText | Batch: ${item.batch.isNotEmpty ? item.batch : '-'}$genSuffix",
                                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                                    overflow: TextOverflow.ellipsis,
                                  );
                                },
                              ),
                            ],
                          ),
                        ),

                        const Icon(Icons.arrow_right_alt_rounded, color: Colors.grey, size: 20),
                        const SizedBox(width: 10),

                        // 3. RIGHT SIDE: Our Software Name (Dropdown, editable Autocomplete)
                        Expanded(
                          flex: 4,
                          child: isSkipped
                              ? const Text("SKIPPED", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
                              : Autocomplete<Product>(
                            focusNode: _focusNodes[i],
                            textEditingController: _controllers[i],
                            displayStringForOption: (p) => p.name,
                            optionsBuilder: (TextEditingValue v) {
                              final q = v.text.trim().toLowerCase();
                              if (q.isEmpty) {
                                return const Iterable<Product>.empty();
                              }

                              final matches = widget.provider.searchProducts(q, includeGenerics: false);

                              if (matches.isEmpty) {
                                return [Product(id: "CREATE_NEW", name: v.text.trim())];
                              }

                              return matches.take(30);
                            },
                            onSelected: (p) {
                              if (p.id == "CREATE_NEW") {
                                _openRegistrationAndAdd(i, p.name);
                                return;
                              }
                              setState(() => _selectedMatches[i] = p);
                              _moveToNext(i);
                            },
                            fieldViewBuilder: (ctx, ctrl, fn, onFieldSubmitted) {
                              final Product? validMatch = _getValidMatch(i);
                              final bool hasText = ctrl.text.trim().isNotEmpty;
                              final bool isValid = validMatch != null;
                              final bool isFocused = fn.hasFocus;
                              final bool isInvalid = hasText && !isValid && !isFocused && !isSkipped;

                              Color fillColor = Colors.white;
                              Color borderColor = Colors.grey.shade400;
                              Widget? suffixIcon;

                              if (isSkipped) {
                                fillColor = Colors.grey.shade100;
                              } else if (isValid) {
                                fillColor = Colors.green.shade50;
                                borderColor = Colors.green.shade600;
                                suffixIcon = const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18);
                              } else if (isFocused) {
                                fillColor = Colors.amber.shade50;
                                borderColor = Colors.blue.shade700;
                                suffixIcon = const Icon(Icons.search_rounded, color: Colors.blue, size: 18);
                              } else if (isInvalid) {
                                fillColor = Colors.red.shade50;
                                borderColor = Colors.red.shade500;
                                suffixIcon = const Tooltip(
                                  message: "Invalid product name! Must select from dropdown.",
                                  child: Icon(Icons.cancel_rounded, color: Colors.red, size: 18),
                                );
                              } else {
                                fillColor = Colors.amber.shade50;
                                borderColor = Colors.amber.shade600;
                                suffixIcon = const Icon(Icons.search_rounded, color: Colors.amber, size: 18);
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    controller: ctrl,
                                    focusNode: fn,
                                    onChanged: (v) {
                                      setState(() {
                                        _selectedMatches[i] = _getValidMatch(i);
                                      });
                                    },
                                    decoration: InputDecoration(
                                      hintText: "Search Product...",
                                      border: const OutlineInputBorder(),
                                      enabledBorder: OutlineInputBorder(
                                        borderSide: BorderSide(color: borderColor, width: (isInvalid || isValid) ? 1.5 : 1.0),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderSide: BorderSide(color: Colors.blue.shade700, width: 2.0),
                                      ),
                                      filled: true,
                                      fillColor: fillColor,
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      suffixIcon: suffixIcon,
                                    ),
                                    onSubmitted: (val) {
                                      onFieldSubmitted();
                                      _moveToNext(i);
                                    },
                                  ),
                                  if (isInvalid && !isSkipped)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2, left: 2),
                                      child: Text(
                                        "NOT IN DROPDOWN - Select valid product from list",
                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.red.shade700),
                                      ),
                                    ),
                                ],
                              );
                            },
                            optionsViewBuilder: (context, onSelected, options) {
                              final String typedText = _controllers[i].text;
                              final bool isCreateNew = options.length == 1 && options.first.id == "CREATE_NEW";

                              return Align(
                                alignment: Alignment.topLeft,
                                child: Material(
                                  elevation: 8,
                                  borderRadius: BorderRadius.circular(4),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxHeight: 300, maxWidth: 650),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isCreateNew)
                                          InkWell(
                                            onTap: () {
                                              _openRegistrationAndAdd(i, typedText);
                                            },
                                            child: Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(12),
                                              color: Colors.orange.shade50,
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.add_circle, color: Colors.orange),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text("PRODUCT NOT FOUND. CREATE NEW: '$typedText'?",
                                                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                                                    ),
                                                  ),
                                                  const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.orange),
                                                ],
                                              ),
                                            ),
                                          ),
                                        if (!isCreateNew) ...[
                                          Container(
                                            height: 24,
                                            color: Colors.blue.shade900,
                                            child: const Row(
                                              children: [
                                                SizedBox(width: 8),
                                                Expanded(flex: 6, child: Text("Product Name", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                                                Expanded(flex: 2, child: Text("Generic / Salt", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                                                Expanded(flex: 1, child: Text("Stock", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                                                Expanded(flex: 1, child: Text("MRP", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                                                SizedBox(width: 8),
                                              ],
                                            ),
                                          ),
                                          Flexible(
                                            child: ListView.builder(
                                              padding: EdgeInsets.zero,
                                              shrinkWrap: true,
                                              itemCount: options.length,
                                              itemBuilder: (BuildContext context, int index) {
                                                final Product option = options.elementAt(index);
                                                return InkWell(
                                                  onTap: () => onSelected(option),
                                                  child: Builder(
                                                      builder: (context) {
                                                        final bool highlight = AutocompleteHighlightedOption.of(context) == index;
                                                        if (highlight) {
                                                          SchedulerBinding.instance.addPostFrameCallback((Duration timeStamp) {
                                                            Scrollable.ensureVisible(context, alignment: 0.5);
                                                          });
                                                        }
                                                        return Container(
                                                          color: highlight ? Colors.blue.shade50 : Colors.white,
                                                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                                                          child: Row(
                                                            children: [
                                                              Expanded(
                                                                flex: 6,
                                                                child: Tooltip(
                                                                  message: option.name,
                                                                  child: Text(
                                                                    option.name,
                                                                    style: TextStyle(
                                                                      fontSize: 12,
                                                                      fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
                                                                    ),
                                                                    overflow: TextOverflow.ellipsis,
                                                                  ),
                                                                ),
                                                              ),
                                                              Expanded(
                                                                flex: 2,
                                                                child: Tooltip(
                                                                  message: option.genericName,
                                                                  child: Text(
                                                                    option.genericName,
                                                                    style: const TextStyle(fontSize: 10, color: Colors.blueGrey),
                                                                    overflow: TextOverflow.ellipsis,
                                                                  ),
                                                                ),
                                                              ),
                                                              Expanded(
                                                                flex: 1,
                                                                child: Text(
                                                                  option.stock.toString(),
                                                                  style: const TextStyle(fontSize: 11, color: Colors.blue),
                                                                  textAlign: TextAlign.right,
                                                                ),
                                                              ),
                                                              Expanded(
                                                                flex: 1,
                                                                child: Text(
                                                                  option.mrp.toStringAsFixed(2),
                                                                  style: const TextStyle(fontSize: 11, color: Colors.green),
                                                                  textAlign: TextAlign.right,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        );
                                                      }
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        IconButton(
                          icon: Icon(isSkipped ? Icons.add_circle_outline : Icons.remove_circle_outline, color: isSkipped ? Colors.green : Colors.red),
                          onPressed: () => setState(() => _skipItems[i] = !isSkipped),
                          tooltip: isSkipped ? "Include" : "Skip",
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => widget.onImportRequested(null),
                  child: const Text("CANCEL", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade50,
                    foregroundColor: Colors.blue.shade900,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  onPressed: () async {
                    int mappedCount = 0;
                    int unmappedCount = 0;

                    for (int i = 0; i < widget.unknownItems.length; i++) {
                      if (_skipItems[i] == true) continue;
                      if (_getValidMatch(i) != null) {
                        mappedCount++;
                      } else {
                        unmappedCount++;
                      }
                    }

                    // 1. If unmapped items exist, show confirmation dialog
                    if (unmappedCount > 0) {
                      final bool? proceed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: const Color(0xFF1E293B),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          title: const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 26),
                              SizedBox(width: 10),
                              Text("Unmapped Items Found", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "You haven't mapped all stocks ($unmappedCount unmapped item(s) out of ${mappedCount + unmappedCount}).",
                                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                "Do you want to continue importing? Unmapped items will be imported with blank product names so you can fill them in the purchase table.",
                                style: TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text("Map Items Now", style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                            ),
                            ElevatedButton.icon(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
                              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                              label: const Text("Continue Import"),
                            ),
                          ],
                        ),
                      );

                      if (proceed != true) {
                        return; // User chose to stay and map items
                      }
                    }

                    final List<PurchaseItem> mappedItems = [];
                    String cleanWholesaler = widget.wholesalerName.replaceAll(' - PDF', '').replaceAll(' - EXCEL', '').trim().toUpperCase();

                    for (int i = 0; i < widget.unknownItems.length; i++) {
                      if (_skipItems[i] == true) continue;

                      final match = _getValidMatch(i);
                      final original = widget.unknownItems[i];

                      if (match != null) {
                        // Mapped item: Save DB mapping rule permanently
                        await widget.provider.saveProductMapping(ProductMapping(
                          wholesalerName: cleanWholesaler,
                          externalCode: original.externalCode.trim(),
                          externalName: (original.externalName.isNotEmpty ? original.externalName : original.productName).trim(),
                          internalName: match.name,
                          productId: match.id,
                        ));

                        mappedItems.add(PurchaseItem(
                          id: match.id,
                          productName: match.name,
                          externalName: original.externalName,
                          externalCode: original.externalCode,
                          batch: original.batch,
                          expiry: original.expiry,
                          qty: original.qty,
                          fQty: original.fQty,
                          pRate: original.pRate,
                          mrp: original.mrp == 0 ? match.mrp : original.mrp,
                          gstPercent: original.gstPercent == 0 ? match.gstPercent : original.gstPercent,
                          sRate: original.sRate,
                          packin: original.packin == 0 ? match.packSize : original.packin,
                          rack: original.rack.isEmpty ? match.rack : original.rack,
                          hsnCode: original.hsnCode.isEmpty ? match.hsnCode : original.hsnCode,
                          gross: original.gross,
                          discPercent: original.discPercent,
                          discAmt: 0, net: 0, gstAmt: 0, total: 0,
                          sDiscPercent: match.sDiscPercent,
                        ));
                      } else {
                        // Unmapped item: Keep productName blank, import all other details
                        mappedItems.add(PurchaseItem(
                          id: "UNKNOWN",
                          productName: "", // KEEP BLANK ON PRODUCT NAME AS REQUESTED
                          externalName: original.externalName,
                          externalCode: original.externalCode,
                          batch: original.batch,
                          expiry: original.expiry,
                          qty: original.qty,
                          fQty: original.fQty,
                          pRate: original.pRate,
                          mrp: original.mrp,
                          gstPercent: original.gstPercent,
                          sRate: original.sRate,
                          packin: original.packin,
                          rack: original.rack,
                          hsnCode: original.hsnCode,
                          gross: original.gross,
                          discPercent: original.discPercent,
                          discAmt: 0, net: 0, gstAmt: 0, total: 0,
                          sDiscPercent: original.sDiscPercent,
                        ));
                      }
                    }

                    if (!mounted) return;

                    // 1. Send data back to the purchase screen
                    widget.onImportRequested(mappedItems);

                    // 2. Only pop if this was opened inside showDialog, NEVER pop if hosted in MdiWindow
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop(true);
                    }
                  },
                  child: const Text("IMPORT MAPPED ITEMS", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
