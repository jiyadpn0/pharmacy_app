import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/pharmacy_provider.dart';
import '../../database/db_helper.dart';
import '../../utils/theme_constants.dart';

class CategoryRegistrationScreen extends StatefulWidget {
  const CategoryRegistrationScreen({super.key});

  @override
  State<CategoryRegistrationScreen> createState() => _CategoryRegistrationScreenState();
}

class _CategoryRegistrationScreenState extends State<CategoryRegistrationScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isActive = true;
  String? _editingCategory;

  void _clear() {
    setState(() {
      _nameCtrl.clear();
      _editingCategory = null;
      _isActive = true;
    });
  }

  void _edit(String cat) {
    setState(() {
      _editingCategory = cat;
      _nameCtrl.text = cat;
      _isActive = true;
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter category name")));
      return;
    }

    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final db = await DbHelper.instance.database;

    if (_editingCategory != null) {
      await db.update('categories', {'name': name}, where: 'name = ?', whereArgs: [_editingCategory]);
      await db.update('product_master', {'category_id': name}, where: 'category_id = ?', whereArgs: [_editingCategory]);
      await provider.loadFromDatabase();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.blue, content: Text("Category Updated!")));
    } else {
      provider.addCategory(name);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text("Category Saved!")));
    }

    _clear();
  }

  Future<void> _delete(String cat) async {
    final c = AppColors.of(context);
    if (cat == "General") {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Default 'General' category cannot be deleted.")));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text("Delete Category", style: TextStyle(color: c.primaryText)),
        content: Text("Delete category '$cat'? Existing medicines will be reassigned to 'General'.", style: TextStyle(color: c.secondaryText)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("CANCEL", style: TextStyle(color: c.secondaryText))),
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
      await db.delete('categories', where: 'name = ?', whereArgs: [cat]);
      await db.update('product_master', {'category_id': 'General'}, where: 'category_id = ?', whereArgs: [cat]);
      if (!mounted) return;
      await Provider.of<PharmacyProvider>(context, listen: false).loadFromDatabase();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.red, content: Text("Category Deleted")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final categories = Provider.of<PharmacyProvider>(context).categories;
    final filtered = categories.where((cat) => cat.toLowerCase().contains(_searchCtrl.text.toLowerCase().trim())).toList();

    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          _buildToolbar(c),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildForm(c),
                VerticalDivider(width: 1, color: c.border),
                Expanded(child: _buildGrid(c, filtered)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(AppThemeColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(bottom: BorderSide(color: c.border, width: 1)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.05), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.indigo.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.category_rounded, color: Colors.indigoAccent, size: 20),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("CATEGORY MASTER", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1, color: c.primaryText)),
              Text("Product Classification", style: TextStyle(fontSize: 11, color: c.secondaryText, fontWeight: FontWeight.bold)),
            ],
          ),
          const Spacer(),
          _toolbarButton(c, Icons.add_circle_outline, "NEW", Colors.blue, onTap: _clear),
          const SizedBox(width: 12),
          _toolbarButton(c, Icons.save_outlined, "SAVE", Colors.green, onTap: _save),
        ],
      ),
    );
  }

  Widget _toolbarButton(AppThemeColors c, IconData icon, String label, Color color, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 13, color: c.primaryText, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(AppThemeColors c) {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(24),
      color: c.cardBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _formField(c, "Sl No", _editingCategory ?? "Auto", enabled: false),
          const SizedBox(height: 24),
          _formField(c, "Category Name*", "", controller: _nameCtrl, isCyan: true),
          const SizedBox(height: 24),
          Row(
            children: [
              Checkbox(
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v ?? true),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              Text("Active Status", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.secondaryText)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _formField(AppThemeColors c, String label, String initialVal, {TextEditingController? controller, bool enabled = true, bool isCyan = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: c.secondaryText, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: isCyan 
                ? (c.isDark ? Colors.teal.shade900.withValues(alpha: 0.3) : const Color(0xFFE0FFFF).withValues(alpha: 0.5)) 
                : c.inputBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.border),
          ),
          child: controller != null
              ? TextField(
                  controller: controller,
                  decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: c.primaryText),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(initialVal, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.secondaryText)),
                ),
        ),
      ],
    );
  }

  Widget _buildGrid(AppThemeColors c, List<String> categories) {
    return Column(
      children: [
        Container(
          height: 35,
          color: const Color(0xFF334155),
          child: const Row(
            children: [
              _Hdr("CATEGORY NAME", flex: 3),
              _Hdr("STATUS", width: 80, align: TextAlign.center),
              _Hdr("", width: 80),
            ],
          ),
        ),
        Container(
          height: 35,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: c.inputBg,
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            style: TextStyle(fontSize: 12, color: c.primaryText),
            decoration: InputDecoration(
              hintText: "Search categories...",
              hintStyle: TextStyle(fontSize: 12, color: c.secondaryText),
              prefixIcon: Icon(Icons.search, size: 16, color: c.secondaryText),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: categories.length,
            itemBuilder: (context, i) {
              final cat = categories[i];
              return Container(
                height: 38,
                decoration: BoxDecoration(color: c.cardBg, border: Border(bottom: BorderSide(color: c.border))),
                child: Row(
                  children: [
                    _Cell(cat, flex: 3, fontWeight: FontWeight.bold),
                    const _Cell("Active", width: 80, color: Colors.green, fontWeight: FontWeight.bold, align: TextAlign.center),
                    SizedBox(
                      width: 80,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(icon: const Icon(Icons.edit, size: 16, color: Colors.blue), onPressed: () => _edit(cat)),
                          IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red), onPressed: () => _delete(cat)),
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
    final c = AppColors.of(context);
    Widget child = Container(
      width: width,
      alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.right ? Alignment.centerRight : Alignment.center),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(text, style: TextStyle(fontSize: 12, color: color ?? c.primaryText, fontWeight: fontWeight)),
    );
    return width == null ? Expanded(flex: flex ?? 1, child: child) : child;
  }
}
