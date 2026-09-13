import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/pharmacy_provider.dart';
import '../../database/db_helper.dart';
import '../../utils/theme_constants.dart';

class ManufacturerRegistrationScreen extends StatefulWidget {
  const ManufacturerRegistrationScreen({super.key});

  @override
  State<ManufacturerRegistrationScreen> createState() => _ManufacturerRegistrationScreenState();
}

class _ManufacturerRegistrationScreenState extends State<ManufacturerRegistrationScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  
  bool _isActive = true;
  String? _editingManufacturer;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _clear() {
    setState(() {
      _nameCtrl.clear();
      _codeCtrl.clear();
      _addressCtrl.clear();
      _phoneCtrl.clear();
      _emailCtrl.clear();
      _editingManufacturer = null;
      _isActive = true;
    });
  }

  void _edit(String name) {
    setState(() {
      _nameCtrl.text = name;
      _editingManufacturer = name;
      _isActive = true;
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim().toUpperCase();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Manufacturer Name is required")));
      return;
    }
    
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final db = await DbHelper.instance.database;
    
    if (_editingManufacturer != null) {
      await db.update('manufacturers', {'name': name}, where: 'name = ?', whereArgs: [_editingManufacturer]);
      await db.update('product_master', {'manufacturer_id': name}, where: 'manufacturer_id = ?', whereArgs: [_editingManufacturer]);
      await provider.loadFromDatabase();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.blue, content: Text("Manufacturer Updated!")));
    } else {
      provider.addManufacturer(name);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text("Manufacturer Saved!")));
    }
    
    _clear();
  }

  Future<void> _delete(String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Manufacturer"),
        content: Text("Permanently delete '$name'? Existing products will retain their records."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("DELETE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final db = await DbHelper.instance.database;
      await db.delete('manufacturers', where: 'name = ?', whereArgs: [name]);
      if (!mounted) return;
      await Provider.of<PharmacyProvider>(context, listen: false).loadFromDatabase();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.red, content: Text("Manufacturer Deleted")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final allManufacturers = Provider.of<PharmacyProvider>(context).manufacturers;
    final filtered = allManufacturers.where((m) => m.toLowerCase().contains(_searchCtrl.text.toLowerCase().trim())).toList();

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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2)),
        ],

      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.factory_rounded, color: Colors.teal.shade800, size: 20),
          ),
          const SizedBox(width: 16),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("MANUFACTURER MASTER", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1, color: Colors.black87)),
              Text("Manage Pharmaceutical Companies", style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
            ],
          ),
          const Spacer(),
          _toolbarButton(Icons.add_circle_outline, "NEW", Colors.blue, onTap: _clear),
          const SizedBox(width: 12),
          _toolbarButton(Icons.save_outlined, "SAVE", Colors.green, onTap: _save),
        ],
      ),
    );
  }

  Widget _toolbarButton(IconData icon, String label, Color color, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(24),
      color: const Color(0xFFF1F5F9),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _formField("Sl No", _editingManufacturer ?? "Auto", enabled: false),
            const SizedBox(height: 16),
            _formField("Manufacturer Name*", "", controller: _nameCtrl, isCyan: true),
            const SizedBox(height: 16),
            _formField("Company Code", "", controller: _codeCtrl),
            const SizedBox(height: 16),
            _formField("Contact Number", "", controller: _phoneCtrl, isNumeric: true),
            const SizedBox(height: 16),
            _formField("Official Email", "", controller: _emailCtrl),
            const SizedBox(height: 16),
            _formField("Corporate Address", "", controller: _addressCtrl, maxLines: 2),
            const SizedBox(height: 16),
            Row(
              children: [
                Checkbox(
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v ?? true),
                  visualDensity: VisualDensity.compact,
                ),
                const Text("Active Status", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blueGrey)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _formField(
    String label,
    String initialVal, {
    TextEditingController? controller,
    bool enabled = true,
    bool isCyan = false,
    int maxLines = 1,
    bool isNumeric = false,
  }) {
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
                keyboardType: isNumeric ? TextInputType.phone : TextInputType.text,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: isNumeric ? [FilteringTextInputFormatter.digitsOnly] : null,
                decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(initialVal, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blueGrey.shade400)),
              ),
        ),
      ],
    );
  }

  Widget _buildGrid(List<String> manufacturers) {
    return Column(
      children: [
        Container(
          height: 35,
          color: const Color(0xFF4A4A4A),
          child: const Row(
            children: [
              _Hdr("MANUFACTURER NAME", flex: 3),
              _Hdr("STATUS", width: 80, align: TextAlign.center),
              _Hdr("", width: 80),
            ],
          ),
        ),
        Container(
          height: 35,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: Colors.grey.shade100,
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              hintText: "Search manufacturer...",
              prefixIcon: Icon(Icons.search, size: 16),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: manufacturers.length,
            itemBuilder: (context, i) {
              final m = manufacturers[i];
              return Container(
                height: 38,
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                child: Row(
                  children: [
                    _Cell(m, flex: 3, fontWeight: FontWeight.bold),
                    const _Cell("Active", width: 80, color: Colors.green, fontWeight: FontWeight.bold, align: TextAlign.center),
                    SizedBox(
                      width: 80,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(icon: const Icon(Icons.edit, size: 16, color: Colors.blue), onPressed: () => _edit(m)),
                          IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red), onPressed: () => _delete(m)),
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
  const _Cell(this.text, {this.width, this.flex, this.color, this.fontWeight = FontWeight.normal, this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    Widget child = Container(
      width: width,
      alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.right ? Alignment.centerRight : Alignment.center),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(text, style: TextStyle(fontSize: 12, color: color ?? Colors.black87, fontWeight: fontWeight)),
    );
    return width == null ? Expanded(flex: flex ?? 1, child: child) : child;
  }
}
