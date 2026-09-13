import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/pharmacy_provider.dart';
import '../../providers/mdi_controller.dart';
import '../../utils/app_dialogs.dart';
import '../../widgets/pin_unlock_dialog.dart';
import '../../widgets/import_widgets.dart';
import '../../utils/theme_constants.dart';

class StockManagementScreen extends StatefulWidget {
  const StockManagementScreen({super.key});

  @override
  State<StockManagementScreen> createState() => _StockManagementScreenState();
}

class _StockManagementScreenState extends State<StockManagementScreen> {
  bool _isImporting = false;
  double _importProgress = 0.0;
  String _importStatus = "";
  String? _selectedFile;
  int _activeOption = 0; // 0: Master, 1: Inventory, 2: Clean Junk, 3: Wipe Names, 4: Wipe Inventory
  Map<String, dynamic>? _result;

  final List<FocusNode> _focusNodes = List.generate(5, (_) => FocusNode());
  final FocusNode _keyboardFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Default focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _showHeadingsHint(int type) {
    List<String> headings = [];
    String title = "";

    if (type == 0) {
      title = "Product Master Excel Headings";
      headings = [
        "Product ID", "Name", "Packing", "Rack", "HSNCode", "MRP", "P.Rate",
        "Category", "SubCategory", "Patent", "Generic Name", "GST", "SDisc",
        "Schedule", "Reorder Level", "Max Level"
      ];
    } else {
      title = "Inventory Stock Excel Headings";
      headings = [
        "Name", "Stock", "Batch", "Expiry", "MRP", "L Cost", "Packing",
        "Supplier", "GST", "Category", "SubCategory", "Patent", "Manufacturer"
      ];
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.blue),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Your Excel file can have columns in any order. The system detects these names:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: headings.map((h) => Chip(
                  label: Text(h, style: const TextStyle(fontSize: 11)),
                  backgroundColor: Colors.blue.shade50,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                )).toList(),
              ),
              const SizedBox(height: 15),
              const Text("Note: 'Name' is essential. Other fields will use defaults if missing.", style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: headings.join("\t")));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Headings copied to clipboard!"), duration: Duration(seconds: 1)));
            },
            child: const Text("COPY ALL"),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK")),
        ],
      ),
    );
  }

  Future<void> _handleAction(int option) async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    if (provider.securityToggles['require_pin_db_reset_imports'] == true) {
      bool isUnlocked = await PinUnlockDialog.show(
          context,
          provider,
          title: "High-Security Lock",
          message: "Enter Master PIN to perform database wipes or bulk imports."
      );
      if (!isUnlocked) return;
    }

    setState(() {
      _activeOption = option;
      _result = null;
    });
    if (option == 0 || option == 1) {
      await _pickAndImport(option);
    } else if (option == 2) {
      final res = await AppDialogs.showConfirmDialog(
        context: context,
        title: "CLEAN JUNK / NUMERIC NAMES?",
        content: "This will remove automatically created numeric or invalid product names (e.g. '115', '120', '45', '7S') and their associated stock batches created during past bad imports. Valid medicine names will NOT be affected.",
        yesLabel: "CLEAN NOW",
        noLabel: "CANCEL",
        isDangerous: false,
      );
      if (res == true) {
        setState(() => _isImporting = true);
        final cleanRes = await provider.cleanupInvalidProductsAndStock();
        if (!mounted) return;
        setState(() {
          _isImporting = false;
          _result = {
            'success': cleanRes['success'],
            'imported': cleanRes['deleted'] ?? 0,
            'message': cleanRes['success'] == true 
                ? "Removed ${cleanRes['deleted']} invalid/numeric products and batches." 
                : cleanRes['message']
          };
        });
      }
    } else if (option == 3) {
      _confirmWipe("PRODUCT MASTER", () async {
        setState(() => _isImporting = true);
        await Provider.of<PharmacyProvider>(context, listen: false).clearProductMaster();
        setState(() => _isImporting = false);
      });
    } else if (option == 4) {
      _confirmWipe("INVENTORY / BATCHES", () async {
        setState(() => _isImporting = true);
        await Provider.of<PharmacyProvider>(context, listen: false).clearInventoryOnly();
        setState(() => _isImporting = false);
      });
    }
  }

  Future<void> _pickAndImport(int type) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
    );

    if (result != null && result.files.single.path != null) {
      if (!mounted) return;
      setState(() {
        _selectedFile = result.files.single.path;
        _isImporting = true;
        _importProgress = 0.0;
        _importStatus = "";
      });

      try {
        final provider = Provider.of<PharmacyProvider>(context, listen: false);
        Map<String, dynamic> importResult;

        if (type == 0) {
          importResult = await provider.importProductMasterFromExcel(
              _selectedFile!,
              onProgress: (p, s) => setState(() {
                _importProgress = p;
                _importStatus = s;
              })
          );
        } else {
          importResult = await provider.importInventoryFromExcel(
              _selectedFile!,
              onProgress: (p, s) => setState(() {
                _importProgress = p;
                _importStatus = s;
              })
          );
        }

        setState(() {
          _isImporting = false;
          _result = importResult;
        });

        if (type == 1 && importResult['requiresMapping'] == true && importResult['unmappedItems'] != null) {
          final List<PurchaseItem> unmapped = List<PurchaseItem>.from(importResult['unmappedItems']);
          if (unmapped.isNotEmpty && mounted) {
            Provider.of<MdiController>(context, listen: false).openWindow(
              MdiWindow(
                id: "mapping_unknown_inventory",
                title: "Link Unknown Products (Stock Import)",
                width: 950,
                height: 650,
                content: ProductMappingDialog(
                  wholesalerName: "Stock Excel Import",
                  unknownItems: unmapped,
                  provider: provider,
                  onImportRequested: (mappedItems) async {
                    Provider.of<MdiController>(context, listen: false).closeWindow("mapping_unknown_inventory");
                    if (mappedItems != null && mappedItems.isNotEmpty) {
                      await provider.commitMappedStockImport(mappedItems);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("Successfully mapped and imported ${mappedItems.length} items into inventory!"),
                            backgroundColor: Colors.green,
                          )
                        );
                      }
                    }
                  },
                ),
              ),
            );
          }
        }
      } catch (e) {
        setState(() {
          _isImporting = false;
          _result = {'success': false, 'message': e.toString()};
        });
      }
    }
  }

  void _confirmWipe(String target, Future<void> Function() wipeFn) async {
    final res = await AppDialogs.showConfirmDialog(
      context: context,
      title: "WIPE $target?",
      content: "This will PERMANENTLY delete all $target data. This cannot be undone.",
      yesLabel: "WIPE NOW",
      noLabel: "CANCEL",
      isDangerous: true,
    );

    if (res == true) {
      await wipeFn();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$target data wiped."), backgroundColor: Colors.black));
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          int current = -1;
          for (int i = 0; i < 5; i++) { if (_focusNodes[i].hasFocus) current = i; }

          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Provider.of<PharmacyProvider>(context, listen: false).cancelImport();
            if (_isImporting) {
              setState(() => _isImporting = false);
            }
            return;
          }

          if (event.logicalKey == LogicalKeyboardKey.arrowDown || event.logicalKey == LogicalKeyboardKey.arrowRight) {
            if (current != -1) _focusNodes[(current + 1) % 5].requestFocus();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp || event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            if (current != -1) _focusNodes[(current - 1 + 5) % 5].requestFocus();
          }
        }
      },
      child: Stack(
        children: [
          Container(
            color: AppColors.of(context).background,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Stock & Inventory Management", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF003366))),
                const SizedBox(height: 20),

                Expanded(
                  child: GridView.count(
                    crossAxisCount: 3,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 2.2,
                    children: [
                      _optionCard(0, "Add Product Names (Master)", "Import medicines details for drop-downs. (Visible on 'All Stock Details')", Icons.library_add, Colors.blue),
                      _optionCard(1, "Add Inventory Stock", "Import real stock levels in shop. (Visible on 'Inventory')", Icons.inventory, Colors.green),
                      _optionCard(2, "Clean Junk/Numeric Names", "Remove auto-created number names ('115', '120', '7S') from bad imports.", Icons.cleaning_services_rounded, Colors.purple),
                      _optionCard(3, "Remove Stock Names", "Delete all medicine names and history.", Icons.delete_sweep, Colors.orange),
                      _optionCard(4, "Clear Inventory", "Clear shop stock levels and batches only.", Icons.layers_clear, Colors.red),
                    ],
                  ),
                ),

                if (_result != null)
                  _buildResultSummary(),
                
                const Spacer(),
                Consumer<PharmacyProvider>(
                  builder: (context, prov, child) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade900,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Wrap(
                        spacing: 20,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.storage_rounded, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                "NAMES: ${prov.productMaster.length}",
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const SizedBox(width: 12),
                              InkWell(
                                onTap: () => _handleAction(3),
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_sweep, color: Colors.orange.shade300, size: 18),
                                    const SizedBox(width: 4),
                                    const Text(
                                      "WIPE ALL NAMES",
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, decoration: TextDecoration.underline),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Container(height: 20, width: 1, color: Colors.white30),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.inventory_2_rounded, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                "INVENTORY BATCHES: ${prov.products.length}",
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const SizedBox(width: 12),
                              InkWell(
                                onTap: () => _handleAction(4),
                                child: Row(
                                  children: [
                                    Icon(Icons.layers_clear, color: Colors.red.shade300, size: 18),
                                    const SizedBox(width: 4),
                                    const Text(
                                      "CLEAR INVENTORY",
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, decoration: TextDecoration.underline),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }
                ),
              ],
            ),
          ),
          if (_isImporting)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: Center(
                child: Card(
                  elevation: 10,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(value: _importProgress > 0 ? _importProgress : null, strokeWidth: 5),
                        const SizedBox(height: 25),
                        Text(
                          _activeOption < 2
                              ? "Processing Excel File ${_importStatus.isNotEmpty ? '($_importStatus)' : ''}"
                              : "Cleaning Database...",
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        if (_importStatus.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          LinearProgressIndicator(value: _importProgress),
                          const SizedBox(height: 5),
                          Text("${(_importProgress * 100).toStringAsFixed(0)}% of this part finished", style: const TextStyle(fontSize: 12, color: Colors.blue)),
                        ],
                        const SizedBox(height: 10),
                        const Text(
                          "Please wait, this may take a moment.",
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 25),
                        OutlinedButton.icon(
                          onPressed: () {
                            Provider.of<PharmacyProvider>(context, listen: false).cancelImport();
                          },
                          icon: const Icon(Icons.cancel_rounded, color: Colors.red),
                          label: const Text("CANCEL IMPORT", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _optionCard(int index, String title, String desc, IconData icon, Color color) {
    return Focus(
      focusNode: _focusNodes[index],
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          _handleAction(index);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
          builder: (context) {
            final bool hasFocus = Focus.of(context).hasFocus;
            return InkWell(
              onTap: () => _handleAction(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: hasFocus ? color : Colors.transparent, width: 3),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))
                  ],
                ),
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 60, height: 60,
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                      child: Icon(icon, color: color, size: 30),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              if (index < 2) ...[
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () {
                                    _showHeadingsHint(index);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle),
                                    child: Icon(Icons.priority_high, size: 14, color: color),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(desc, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                          if (hasFocus)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text("Press ENTER to select", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
                            ),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            );
          }
      ),
    );
  }

  Widget _buildResultSummary() {
    bool success = _result!['success'] ?? false;
    if (!success) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade200)),
        child: Text("Error: ${_result!['message']}", style: const TextStyle(color: Colors.red)),
      );
    }

    int imported = _result!['imported'] ?? 0;
    int errors = _result!['errors'] ?? 0;
    List<String> logs = List<String>.from(_result!['logs'] ?? []);

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade200)),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 40),
                const SizedBox(width: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Import Completed Successfully", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                    Text("Total Products Registered: $imported", style: const TextStyle(fontSize: 16)),
                    if (errors > 0)
                      Text("Skipped Rows (Errors): $errors", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ],
                )
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (logs.isNotEmpty) ...[
            const Text("Error Logs:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: logs.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text("• ${logs[i]}", style: const TextStyle(color: Colors.red, fontSize: 13)),
                ),
              ),
            )
          ]
        ],
      ),
    );
  }
}
