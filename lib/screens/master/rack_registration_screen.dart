import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../../providers/pharmacy_provider.dart';
import '../../utils/app_dialogs.dart';
import '../../utils/rack_label_generator.dart';
import '../../utils/theme_constants.dart';

class RackRegistrationScreen extends StatefulWidget {
  const RackRegistrationScreen({super.key});

  @override
  State<RackRegistrationScreen> createState() => _RackRegistrationScreenState();
}

class _RackRegistrationScreenState extends State<RackRegistrationScreen> {
  // Rack Registration State
  final TextEditingController _nameCtrl = TextEditingController();
  bool _isActive = true;
  bool _isHeatmapEnabled = false;

  String? _selectedRack;
  int _mode = 0; // 0: Reg, 1: Items, 2: History, 3: Inactive
  final TextEditingController _itemSearchCtrl = TextEditingController();
  final TextEditingController _historySearchCtrl = TextEditingController();
  final TextEditingController _inactiveFilterCtrl = TextEditingController(text: "30");
  final TextEditingController _inactiveSearchCtrl = TextEditingController();
  List<Product> _filteredItems = [];
  final Set<String> _selectedInactiveRacks = {};


  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _verticalScroll = ScrollController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _itemSearchCtrl.dispose();
    _historySearchCtrl.dispose();
    _inactiveFilterCtrl.dispose();
    _inactiveSearchCtrl.dispose();
    _horizontalScroll.dispose();
    _verticalScroll.dispose();
    super.dispose();
  }

  void _save() {
    final newRack = _nameCtrl.text.trim().toUpperCase();
    if (newRack.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Rack name required")));
      return;
    }
    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    if (_selectedRack != null && provider.racks.contains(_selectedRack)) {
      provider.updateRack(_selectedRack!, newRack, isActive: _isActive);
      setState(() => _selectedRack = newRack);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.blue, content: Text("Rack Updated!")));
    } else {
      if (provider.racks.contains(newRack)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Rack already exists")));
        return;
      }
      provider.addRack(newRack, isActive: _isActive);
      _nameCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text("Rack Saved!")));
    }
  }

  void _export() async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Select where to save Rack Excel:',
      fileName: 'racks_export.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (outputFile != null) {
      try {
        await provider.exportRacksToExcel(outputFile);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text("Racks exported successfully!")));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text("Export failed: $e")));
        }
      }
    }
  }

  void _import() async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (result != null && result.files.single.path != null) {
      try {
        final res = await provider.importRacksFromExcel(result.files.single.path!);
        if (mounted) {
          if (res['success'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.green, content: Text("Imported ${res['count']} racks!")));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text("Import failed: ${res['message']}")));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text("Import error: $e")));
        }
      }
    }
  }

  void _handlePdfLabelsExport() async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final activeRacks = provider.racks.where((r) => provider.isRackActive(r)).toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("PDF Labels Options"),
        content: const Text("Choose how you want to export or print the PDF labels:"),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              String? outputFile = await FilePicker.saveFile(
                dialogTitle: 'Save Rack Labels PDF:',
                fileName: 'rack_labels.pdf',
                type: FileType.custom,
                allowedExtensions: ['pdf'],
              );
              if (outputFile != null) {
                try {
                  await RackLabelGenerator.savePdfLabelsToFile(
                    racks: activeRacks,
                    productMaster: provider.productMaster,
                    pharmacyName: provider.companyProfile.name,
                    savePath: outputFile,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(backgroundColor: Colors.green, content: Text("Rack Labels PDF saved successfully!")),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(backgroundColor: Colors.red, content: Text("PDF Export failed: $e")),
                    );
                  }
                }
              }
            },
            child: const Text("SAVE FILE..."),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.print, size: 16),
            label: const Text("PREVIEW & PRINT"),
            onPressed: () async {
              Navigator.pop(ctx);
              await RackLabelGenerator.printPdfLabels(
                racks: activeRacks,
                productMaster: provider.productMaster,
                pharmacyName: provider.companyProfile.name,
              );
            },
          ),
        ],
      ),
    );
  }

  void _handleExcelLabelsExport() async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final activeRacks = provider.racks.where((r) => provider.isRackActive(r)).toList();

    String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Save Rack Box Labels Excel:',
      fileName: 'rack_box_labels.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (outputFile != null) {
      try {
        final success = await RackLabelGenerator.exportExcelLabelsToFile(
          racks: activeRacks,
          productMaster: provider.productMaster,
          savePath: outputFile,
        );
        if (mounted && success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(backgroundColor: Colors.green, content: Text("Rack Box Labels exported to Excel successfully!")),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.red, content: Text("Excel Labels export failed: $e")),
          );
        }
      }
    }
  }

  void _showRackLabelsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.label, color: Colors.teal),
            SizedBox(width: 8),
            Text("Export Physical Rack Labels", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Generate printable rack box labels (with item lists & rack ID in bottom-right corner). "
              "Cut along borders and paste onto physical boxes.",
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 28),
              title: const Text("Export / Print PDF Labels", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: const Text("Opens print preview dialog or saves printable PDF", style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(ctx);
                _handlePdfLabelsExport();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.table_chart, color: Colors.green, size: 28),
              title: const Text("Export to Excel Cards", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: const Text("Saves .xlsx workbook formatted as box cards", style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(ctx);
                _handleExcelLabelsExport();
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final provider = Provider.of<PharmacyProvider>(context);
    final racks = provider.racks;

    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLeftPanel(provider),
                const VerticalDivider(width: 1),
                Expanded(child: _buildPeriodicGrid(racks, provider)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          // Left side: Heatmap
          _toolbarButton(
            _isHeatmapEnabled ? Icons.local_fire_department : Icons.local_fire_department_outlined,
            "Heatmap",
            _isHeatmapEnabled ? Colors.red.shade700 : Colors.indigo.shade700,
            isActive: _isHeatmapEnabled,
            onTap: () => setState(() => _isHeatmapEnabled = !_isHeatmapEnabled),
          ),
          const Spacer(),
          // Right side: New Rack, Import, Export, Exchange, Export Labels
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _toolbarButton(Icons.add_circle_outline, "New Rack", Colors.blue, onTap: () {
                  setState(() => _selectedRack = null);
                  _nameCtrl.clear();
                }),
                const SizedBox(width: 8),
                _toolbarButton(Icons.upload_file_outlined, "Import", Colors.orange.shade800, onTap: _import),
                const SizedBox(width: 8),
                _toolbarButton(Icons.download_outlined, "Export", Colors.grey.shade700, onTap: _export),
                const SizedBox(width: 8),
                _toolbarButton(Icons.swap_horiz, "Exchange", Colors.purple.shade700, onTap: _showExchangeDialog),
                const SizedBox(width: 8),
                _toolbarButton(Icons.label_outlined, "Export Labels", Colors.teal.shade700, onTap: () => _showRackLabelsDialog()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbarButton(IconData icon, String label, Color color, {bool isActive = false, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? color : Colors.grey.shade300, width: isActive ? 1.5 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, color: isActive ? color : Colors.black87, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftPanel(PharmacyProvider provider) {
    return Container(
      width: 320,
      color: const Color(0xFFF1F5F9),
      child: Column(
        children: [
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                _modeTab(0, "REG", Icons.app_registration),
                _modeTab(1, "ITEMS", Icons.list),
                _modeTab(2, "HIST", Icons.history),
                _modeTab(3, "INACT", Icons.timer_off),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _mode == 0
                  ? _buildRegistrationForm(provider)
                  : _mode == 1
                      ? _buildItemsManagement(provider)
                      : _mode == 2
                          ? _buildRackHistory(provider)
                          : _buildInactiveRackList(provider),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeTab(int index, String label, IconData icon) {
    bool isSelected = _mode == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _mode = index),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.shade700 : Colors.white,
            border: Border(
              bottom: BorderSide(color: isSelected ? Colors.orange : Colors.grey.shade300, width: 2),
            ),
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: isSelected ? Colors.white : Colors.blue.shade800),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.blue.shade800, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRegistrationForm(PharmacyProvider provider) {
    bool isEdit = _selectedRack != null && provider.racks.contains(_selectedRack);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formField("Sl No", isEdit ? "Editing" : "Auto", enabled: false),
        const SizedBox(height: 12),
        _formField("Rack Identifier*", "", controller: _nameCtrl, isCyan: true),
        const SizedBox(height: 12),
        Row(
          children: [
            Checkbox(
              value: _isActive,
              onChanged: (v) {
                setState(() => _isActive = v ?? true);
                if (isEdit) _save();
              },
              visualDensity: VisualDensity.compact,
            ),
            const Text("Active Status", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ],
        ),
        const SizedBox(height: 24),
        if (isEdit) ...[
          _actionBtn(_isActive ? "MARK INACTIVE" : "MARK ACTIVE", Colors.orange.shade800, _isActive ? Icons.block : Icons.check, onTap: () {
            provider.toggleRackStatus(_selectedRack!);
            setState(() => _isActive = provider.isRackActive(_selectedRack!));
          }),
          const SizedBox(height: 10),
          _actionBtn("DELETE RACK", Colors.red, Icons.delete, onTap: () {
            provider.deleteRack(_selectedRack!);
            _nameCtrl.clear();
            setState(() => _selectedRack = null);
          }),
        ] else ...[
          _actionBtn("SAVE NEW RACK", Colors.blue.shade700, Icons.add_circle, onTap: _save),
        ],
      ],
    );
  }

  Widget _actionBtn(String label, Color color, IconData icon, {VoidCallback? onTap}) => SizedBox(
    width: double.infinity,
    height: 40,
    child: ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
      style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
    ),
  );

  Widget _buildItemsManagement(PharmacyProvider provider) {
    if (_selectedRack == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.only(top: 50),
          child: Text("Select a rack from the grid\nto manage its items.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
        ),
      );
    }

    final itemsInRack = provider.productMaster.where((p) => p.rack == _selectedRack).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("RACK: $_selectedRack", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
        const Divider(),
        TextField(
          controller: _itemSearchCtrl,
          decoration: InputDecoration(
            hintText: "Search & assign item...",
            prefixIcon: const Icon(Icons.search, size: 18),
            border: const OutlineInputBorder(),
            isDense: true,
            fillColor: Colors.white,
            filled: true,
            suffixIcon: _itemSearchCtrl.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () { _itemSearchCtrl.clear(); setState(() => _filteredItems = []); })
                : null,
          ),
          style: const TextStyle(fontSize: 12),
          onChanged: (v) {
            setState(() {
              _filteredItems = v.isEmpty ? [] : provider.searchProducts(v);
            });
          },
        ),
        if (_filteredItems.isNotEmpty)
          Container(
            height: 150,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), color: Colors.white),
            child: ListView.builder(
              itemCount: _filteredItems.length,
              itemBuilder: (ctx, i) {
                final p = _filteredItems[i];
                return ListTile(
                  title: Text(p.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  subtitle: Text("Current: ${p.rack.isEmpty ? 'None' : p.rack} | Stock: ${p.stock}", style: const TextStyle(fontSize: 10)),
                  trailing: const Icon(Icons.add_circle, color: Colors.green, size: 18),
                  dense: true,
                  onTap: () {
                    p.rack = _selectedRack!;
                    provider.updateProduct(p);
                    _itemSearchCtrl.clear();
                    setState(() => _filteredItems = []);
                  },
                );
              },
            ),
          ),
        const SizedBox(height: 15),
        Text("ITEMS IN RACK (${itemsInRack.length}):", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54)),
        const SizedBox(height: 6),
        ...itemsInRack.map((p) => Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(4)),
          child: Row(
            children: [
              Expanded(child: Text(p.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
              Text("Qty: ${p.stock}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  p.rack = "";
                  provider.updateProduct(p);
                  setState(() {});
                },
              ),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildRackHistory(PharmacyProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("RACK CHANGE AUDIT", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 12)),
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 18),
              tooltip: "Purge history older than 90 days",
              onPressed: _showClearHistoryDialog,
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _historySearchCtrl,
          decoration: const InputDecoration(
            hintText: "Search movement history...",
            prefixIcon: Icon(Icons.search, size: 18),
            border: OutlineInputBorder(),
            isDense: true,
            fillColor: Colors.white,
            filled: true,
          ),

          style: const TextStyle(fontSize: 11),
          onChanged: (_) => setState(() {}),
        ),
        const Divider(),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: provider.getAllRackHistory(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text("No movement audit records.", style: TextStyle(fontSize: 11, color: Colors.grey)));
            }

            final query = _historySearchCtrl.text.toLowerCase().trim();
            final history = snapshot.data!.where((h) {
              final name = (h['product_name'] ?? "").toString().toLowerCase();
              return name.contains(query);
            }).toList();

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: history.length,
              itemBuilder: (ctx, i) {
                final h = history[i];
                final date = DateTime.tryParse(h['change_date'] ?? "") ?? DateTime.now();
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(h['product_name'] ?? "Unknown", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          Text("${h['old_rack']} ➔ ${h['new_rack']}", style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          Text(DateFormat('dd/MM/yy HH:mm').format(date), style: const TextStyle(fontSize: 9, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildInactiveRackList(PharmacyProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("UNUSED RACKS", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 12)),
            if (_selectedInactiveRacks.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_forever, color: Colors.red, size: 20),
                onPressed: () => _deleteInactiveRacks(provider, _selectedInactiveRacks.toList()),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _inactiveSearchCtrl,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: "Filter unused racks...",
            prefixIcon: Icon(Icons.filter_list, size: 16),
            isDense: true,
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(fontSize: 11),
        ),
        const Divider(),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: provider.getInactiveRacksInfo(minDays: int.tryParse(_inactiveFilterCtrl.text) ?? 30),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text("All racks currently have active stock.", style: TextStyle(fontSize: 11, color: Colors.grey)));
            }

            final query = _inactiveSearchCtrl.text.toLowerCase().trim();
            final list = snapshot.data!.where((r) => (r['name'] ?? "").toString().toLowerCase().contains(query)).toList();

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: list.length,
              itemBuilder: (ctx, i) {
                final r = list[i];
                final name = r['name'] ?? "";
                final isSelected = _selectedInactiveRacks.contains(name);
                return CheckboxListTile(
                  value: isSelected,
                  title: Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  subtitle: Text("Last Active: ${r['last_entry_date'] ?? 'Never'}", style: const TextStyle(fontSize: 9)),
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedInactiveRacks.add(name);
                      } else {
                        _selectedInactiveRacks.remove(name);
                      }
                    });

                  },
                );
              },
            );
          },
        ),
      ],
    );
  }

  int _getRackStockCount(String rackName, PharmacyProvider provider) {
    final items = provider.productMaster.where((p) => p.rack == rackName);
    int sum = 0;
    for (var p in items) {
      if (p.stock > 0) sum += p.stock;
    }
    return sum;
  }

  Color _getHeatmapColor(double ratio) {
    if (ratio <= 0.0) {
      return const Color(0xFF4CAF50); // Green (0% / Least stock)
    } else if (ratio >= 1.0) {
      return const Color(0xFFD32F2F); // Bright Maximum Red (100% / Most stock)
    } else if (ratio <= 0.5) {
      return Color.lerp(const Color(0xFF4CAF50), const Color(0xFFFFC107), ratio * 2)!;
    } else {
      return Color.lerp(const Color(0xFFFFC107), const Color(0xFFD32F2F), (ratio - 0.5) * 2)!;
    }
  }

  Widget _buildPeriodicGrid(List<String> racks, PharmacyProvider provider) {
    Set<String> rowLabels = {};
    int maxCol = 15;
    for (var r in racks) {
      final match = RegExp(r'^([A-Z]*)(\d+)$').firstMatch(r);
      if (match != null) {
        String row = match.group(1) ?? "";
        if (row.isEmpty) row = "#";
        rowLabels.add(row);
        int col = int.tryParse(match.group(2)!) ?? 0;
        if (col > maxCol) maxCol = col;
      }
    }
    if (rowLabels.isEmpty) rowLabels.addAll(["#", "A", "B", "C", "D", "E", "F", "G"]);
    List<String> sortedRows = rowLabels.toList()..sort();
    maxCol = (maxCol + 1).clamp(15, 30);

    int globalMaxStock = 0;
    int globalMinStock = 999999;
    int totalStoreStock = 0;
    final Map<String, int> rackStockMap = {};

    if (_isHeatmapEnabled) {
      for (var r in racks) {
        int cnt = _getRackStockCount(r, provider);
        rackStockMap[r] = cnt;
        totalStoreStock += cnt;
        if (cnt > globalMaxStock) globalMaxStock = cnt;
        if (cnt < globalMinStock) globalMinStock = cnt;
      }
      if (globalMinStock == 999999) globalMinStock = 0;
    }

    return Container(
      color: const Color(0xFFE9EDF0),
      child: Column(
        children: [
          if (_isHeatmapEnabled)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF263238),
              child: Row(
                children: [
                  const Icon(Icons.local_fire_department, color: Colors.orangeAccent, size: 18),
                  const SizedBox(width: 8),
                  const Text("HEATMAP MODE ACTIVE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                  const Spacer(),
                  _heatmapLegendItem("Least (0%)", const Color(0xFF4CAF50)),
                  const SizedBox(width: 12),
                  _heatmapLegendItem("Medium (50%)", const Color(0xFFFFC107)),
                  const SizedBox(width: 12),
                  _heatmapLegendItem("Max (100% Red)", const Color(0xFFD32F2F)),
                  const SizedBox(width: 16),
                  Text(
                    "Total: $totalStoreStock pcs | Max Rack: $globalMaxStock pcs",
                    style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Scrollbar(
              controller: _verticalScroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _verticalScroll,
                scrollDirection: Axis.vertical,
                child: Scrollbar(
                  controller: _horizontalScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _horizontalScroll,
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(width: 45, height: 35, color: const Color(0xFF424242), alignment: Alignment.center, child: const Text("R/C", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                              ...List.generate(maxCol, (i) => Container(
                                width: 70, height: 35,
                                decoration: const BoxDecoration(color: Color(0xFF424242), border: Border(left: BorderSide(color: Colors.white24, width: 0.5))),
                                child: Center(child: Text("${i + 1}", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                              )),
                            ],
                          ),
                          ...sortedRows.map((rowLabel) {
                            return Row(
                              children: [
                                Container(
                                  width: 45, height: 45,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(color: Colors.grey.shade200, border: Border.all(color: Colors.grey.shade300, width: 0.5)),
                                  child: Text(rowLabel, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 13)),
                                ),
                                ...List.generate(maxCol, (colIndex) {
                                  String rackName = (rowLabel == "#" ? "" : rowLabel) + (colIndex + 1).toString();
                                  bool exists = racks.contains(rackName);
                                  bool isActive = provider.isRackActive(rackName);
                                  bool isSelected = _selectedRack == rackName;

                                  int stockVal = _isHeatmapEnabled ? (rackStockMap[rackName] ?? 0) : 0;
                                  double stockPct = totalStoreStock > 0 ? (stockVal / totalStoreStock) * 100 : 0.0;

                                  Color cellBgColor;
                                  if (_isHeatmapEnabled) {
                                    if (!exists) {
                                      cellBgColor = Colors.white;
                                    } else {
                                      double ratio = globalMaxStock > 0 ? (stockVal / globalMaxStock).clamp(0.0, 1.0) : 0.0;
                                      cellBgColor = _getHeatmapColor(ratio);
                                    }
                                  } else {
                                    cellBgColor = exists ? (isActive ? const Color(0xFF4CAF50) : Colors.red.shade400) : Colors.white;
                                  }

                                  Color textColor;
                                  if (exists) {
                                    textColor = _isHeatmapEnabled
                                        ? (cellBgColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white)
                                        : Colors.white;
                                  } else {
                                    textColor = Colors.blueGrey.shade300;
                                  }

                                  return InkWell(
                                    onTap: () {
                                      setState(() {
                                        _selectedRack = rackName;
                                        _nameCtrl.text = rackName;
                                        _isActive = provider.isRackActive(rackName);
                                      });
                                    },
                                    child: Container(
                                      width: 68, height: 42,
                                      margin: const EdgeInsets.all(1),
                                      decoration: BoxDecoration(
                                        color: cellBgColor,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: isSelected ? Colors.yellow.shade700 : (exists ? Colors.black26 : Colors.grey.shade300),
                                          width: isSelected ? 2.5 : 0.5,
                                        ),
                                      ),
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              rackName,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: textColor,
                                              ),
                                            ),
                                            if (_isHeatmapEnabled && exists)
                                              Text(
                                                stockVal > 0
                                                    ? "$stockVal (${stockPct.toStringAsFixed(0)}%)"
                                                    : "0 pcs",
                                                style: TextStyle(
                                                  fontSize: 8.5,
                                                  fontWeight: FontWeight.w900,
                                                  color: textColor.withValues(alpha: 0.95),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heatmapLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 10)),
      ],
    );
  }

  Widget _formField(String label, String initialVal, {TextEditingController? controller, bool enabled = true, bool isCyan = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.blueGrey.shade600, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Container(
          height: 38,
          decoration: BoxDecoration(
            color: isCyan ? const Color(0xFFE0FFFF).withValues(alpha: 0.5) : (enabled ? Colors.white : Colors.grey.shade100),

            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: controller != null
              ? TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(initialVal, style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade400, fontWeight: FontWeight.w600)),
                ),
        ),
      ],
    );
  }

  void _showExchangeDialog() {
    List<TextEditingController> fromCtrls = List.generate(3, (i) => TextEditingController(text: i == 0 ? _selectedRack : ""));
    List<TextEditingController> toCtrls = List.generate(3, (_) => TextEditingController());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Exchange Racks (Max 3 Pairs)"),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Specify rack pairs to swap. Products will move between them atomically.", style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 15),
              ...List.generate(3, (i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(child: TextField(controller: fromCtrls[i], decoration: InputDecoration(labelText: "Pair ${i+1}: From", border: const OutlineInputBorder(), isDense: true), textCapitalization: TextCapitalization.characters)),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.swap_horiz)),
                    Expanded(child: TextField(controller: toCtrls[i], decoration: const InputDecoration(labelText: "To", border: OutlineInputBorder(), isDense: true), textCapitalization: TextCapitalization.characters)),
                  ],
                ),
              )),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () async {
              final provider = Provider.of<PharmacyProvider>(context, listen: false);
              for (int i = 0; i < 3; i++) {
                String f = fromCtrls[i].text.trim().toUpperCase();
                String t = toCtrls[i].text.trim().toUpperCase();
                if (f.isNotEmpty && t.isNotEmpty && f != t) {
                  await provider.exchangeRacks(f, t);
                }
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text("SWAP ALL"),
          ),
        ],
      ),
    );
  }

  void _showClearHistoryDialog() {
    DateTime selectedDate = DateTime.now().subtract(const Duration(days: 90));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Purge Old Movement History"),
        content: Text("Delete all rack change logs older than ${DateFormat('dd/MM/yyyy').format(selectedDate)}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () async {
              await Provider.of<PharmacyProvider>(context, listen: false).clearRackHistory(selectedDate);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("PURGE LOGS", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _deleteInactiveRacks(PharmacyProvider provider, List<String> names) async {
    final confirm = await AppDialogs.showConfirmDialog(
      context: context,
      title: "Confirm Delete",
      content: "Permanently delete ${names.length} unused racks?",
      isDangerous: true,
    );
    if (confirm == true) {
      await provider.deleteMultipleRacks(names);
      setState(() => _selectedInactiveRacks.clear());
    }
  }
}
