import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../providers/pharmacy_provider.dart';
import '../../utils/theme_constants.dart';


class GenericRegistrationScreen extends StatefulWidget {
  const GenericRegistrationScreen({super.key});

  @override
  State<GenericRegistrationScreen> createState() => _GenericRegistrationScreenState();
}

class _GenericRegistrationScreenState extends State<GenericRegistrationScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _useCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  bool _isActive = true;
  String? _editingName;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _useCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _clear() {
    setState(() {
      _nameCtrl.clear();
      _useCtrl.clear();
      _editingName = null;
      _isActive = true;
    });
  }

  void _edit(Generic gen) {
    setState(() {
      _nameCtrl.text = gen.name;
      _useCtrl.text = gen.use;
      _editingName = gen.name;
      _isActive = gen.isActive;
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim().toUpperCase();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Generic composition name is required")));
      return;
    }

    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    if (_editingName != null) {
      provider.updateGeneric(_editingName!, name, use: _useCtrl.text.trim(), isActive: _isActive);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.blue, content: Text("Generic Updated!")));
    } else {
      provider.addGeneric(name, use: _useCtrl.text.trim(), isActive: _isActive);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text("Generic Saved!")));
    }

    _clear();
  }

  void _delete(String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Generic?"),
        content: Text("Are you sure you want to delete composition '$name'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () {
              Provider.of<PharmacyProvider>(context, listen: false).deleteGeneric(name);
              Navigator.pop(ctx);
              _clear();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("DELETE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _clearAll() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Remove Product Names / Clear Generics?"),
        content: const Text(
          "This will clear out all invalid product names from Generic Master.\n\nYou can then add new generic compositions manually, import via Excel, or extract genuine generic names from medicines.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final provider = Provider.of<PharmacyProvider>(context, listen: false);
              await provider.clearAllGenerics();
              _clear();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(backgroundColor: Colors.orange, content: Text("Generic Master cleared successfully!")),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("CLEAR ALL", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _extractFromProducts() async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final added = await provider.autoExtractAndRegisterGenerics();
    if (mounted) {
      if (added > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.green, content: Text("Extracted $added unique generic compositions from medicines!")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Colors.blueGrey, content: Text("No new generic compositions found in Product Master.")),
        );
      }
    }
  }

  void _export() async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Select where to save Generic Excel:',
      fileName: 'generics_export.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (outputFile != null) {
      try {
        await provider.exportGenericsToExcel(outputFile);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text("Generics exported successfully!")));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text("Export failed: $e")));
        }
      }
    }
  }

  void _import() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );

    if (result != null && result.files.single.path != null) {
      if (!mounted) return;
      final provider = Provider.of<PharmacyProvider>(context, listen: false);

      final res = await provider.importGenericsFromExcel(result.files.single.path!);
      if (mounted) {
        if (res['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.green, content: Text("Imported: ${res['imported']}, Updated: ${res['updated']}")));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text("Import failed: ${res['message']}")));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PharmacyProvider>(context);
    final allGenerics = provider.genericMaster;
    final filtered = allGenerics.where((g) =>
      g.name.toLowerCase().contains(_searchCtrl.text.toLowerCase().trim()) ||
      g.use.toLowerCase().contains(_searchCtrl.text.toLowerCase().trim())
    ).toList();

    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      body: Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildForm(),
                const VerticalDivider(width: 1),
                Expanded(child: _buildGrid(filtered)),
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
          _toolbarButton(Icons.add_circle_outline, "New", Colors.blue, onTap: _clear),
          const SizedBox(width: 8),
          _toolbarButton(Icons.save_outlined, "Save", Colors.green, onTap: _save),
          const SizedBox(width: 8),
          _toolbarButton(Icons.auto_fix_high_outlined, "Extract from Products", Colors.teal, onTap: _extractFromProducts),
          const SizedBox(width: 8),
          _toolbarButton(Icons.upload_file_outlined, "Bulk Import", Colors.deepPurple, onTap: _import),
          const SizedBox(width: 8),
          _toolbarButton(Icons.download_outlined, "Export", Colors.blueGrey, onTap: _export),
          const SizedBox(width: 8),
          _toolbarButton(Icons.delete_sweep_outlined, "Clear All", Colors.red, onTap: _clearAll),
        ],
      ),
    );
  }

  Widget _toolbarButton(IconData icon, String label, Color color, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(20),
      color: const Color(0xFFF1F5F9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _formField("Sl No", _editingName ?? "Auto", enabled: false),
          const SizedBox(height: 16),
          _formField("Generic Composition*", "", controller: _nameCtrl, isCyan: true, maxLines: 2),
          const SizedBox(height: 16),
          _formField("Primary Medical Use", "", controller: _useCtrl, maxLines: 2),
          const SizedBox(height: 16),
          Row(
            children: [
              Checkbox(
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v ?? true),
                visualDensity: VisualDensity.compact,
              ),
              const Text("Active Status", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _formField(String label, String initialVal, {TextEditingController? controller, bool enabled = true, bool isCyan = false, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.blueGrey.shade600, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: isCyan ? const Color(0xFFE0FFFF).withValues(alpha: 0.5) : (enabled ? Colors.white : Colors.grey.shade100),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: controller != null
              ? TextField(
                  controller: controller,
                  maxLines: maxLines,
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

  Widget _buildGrid(List<Generic> items) {
    return Column(
      children: [
        Container(
          height: 35,
          color: const Color(0xFF4A4A4A),
          child: const Row(
            children: [
              _Hdr("GENERIC NAME", flex: 5),
              _Hdr("MEDICAL USE", flex: 2),
              _Hdr("STATUS", width: 80, align: TextAlign.center),
              _Hdr("", width: 80),
            ],
          ),
        ),
        Container(
          height: 35,
          color: Colors.grey.shade100,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              hintText: "Search generic compositions...",
              prefixIcon: Icon(Icons.search, size: 16),
              border: InputBorder.none,
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return Container(
                      constraints: const BoxConstraints(minHeight: 40),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                      child: Row(
                        children: [
                          _Cell(item.name, flex: 5, fontWeight: FontWeight.bold, maxLines: 3),
                          _Cell(item.use, flex: 2, maxLines: 3),
                          _Cell(item.isActive ? "Active" : "Inactive", width: 80, align: TextAlign.center, color: item.isActive ? Colors.green : Colors.red, fontWeight: FontWeight.bold),
                          SizedBox(
                            width: 80,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(icon: const Icon(Icons.edit, size: 16, color: Colors.blue), onPressed: () => _edit(item)),
                                IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red), onPressed: () => _delete(item.name)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.science_outlined, size: 60, color: Colors.blueGrey.shade200),
          const SizedBox(height: 12),
          const Text(
            "No Generic Compositions Found",
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey),
          ),
          const SizedBox(height: 6),
          const Text(
            "Product names have been removed. Add new generic compositions on the left,\nimport an Excel sheet, or click 'Extract from Products'.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _Hdr extends StatelessWidget {
  final String title;
  final double? width;
  final int? flex;
  final TextAlign align;
  const _Hdr(this.title, {this.width, this.flex, this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    Widget child = Container(
      width: width,
      alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.right ? Alignment.centerRight : Alignment.center),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
    return flex != null ? Expanded(flex: flex!, child: child) : child;
  }
}

class _Cell extends StatelessWidget {
  final String text;
  final double? width;
  final int? flex;
  final Color? color;
  final FontWeight fontWeight;
  final TextAlign align;
  final int maxLines;

  const _Cell(
    this.text, {
    this.width,
    this.flex,
    this.color,
    this.fontWeight = FontWeight.normal,
    this.align = TextAlign.left,
    this.maxLines = 3,
  });

  @override
  Widget build(BuildContext context) {
    Widget child = Container(
      width: width,
      alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.right ? Alignment.centerRight : Alignment.center),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Tooltip(
        message: text,
        waitDuration: const Duration(milliseconds: 150),
        child: Text(
          text,
          style: TextStyle(fontSize: 11, color: color ?? Colors.black87, fontWeight: fontWeight, height: 1.2),
          overflow: TextOverflow.ellipsis,
          maxLines: maxLines,
        ),
      ),
    );
    return width == null ? Expanded(flex: flex ?? 1, child: child) : child;
  }
}
