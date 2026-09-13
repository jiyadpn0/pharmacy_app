import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../database/db_helper.dart';
import '../../utils/theme_constants.dart';

class TaxSlab {
  final String id;
  final String name;
  final double igst;
  final double cgst;
  final double sgst;
  final bool isActive;

  TaxSlab({
    required this.id,
    required this.name,
    required this.igst,
    required this.cgst,
    required this.sgst,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'igst': igst,
    'cgst': cgst,
    'sgst': sgst,
    'is_active': isActive ? 1 : 0,
  };

  factory TaxSlab.fromMap(Map<String, dynamic> map) => TaxSlab(
    id: map['id']?.toString() ?? '',
    name: map['name']?.toString() ?? '',
    igst: (map['igst'] as num?)?.toDouble() ?? 0.0,
    cgst: (map['cgst'] as num?)?.toDouble() ?? 0.0,
    sgst: (map['sgst'] as num?)?.toDouble() ?? 0.0,
    isActive: (map['is_active'] as int?) == 1,
  );
}

class TaxRegistrationScreen extends StatefulWidget {
  const TaxRegistrationScreen({super.key});

  @override
  State<TaxRegistrationScreen> createState() => _TaxRegistrationScreenState();
}

class _TaxRegistrationScreenState extends State<TaxRegistrationScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _igstCtrl = TextEditingController(text: "0");
  final TextEditingController _cgstCtrl = TextEditingController(text: "0");
  final TextEditingController _sgstCtrl = TextEditingController(text: "0");
  bool _isActive = true;
  String? _editingId;

  List<TaxSlab> _taxSlabs = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadTaxSlabs();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _igstCtrl.dispose();
    _cgstCtrl.dispose();
    _sgstCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTaxSlabs() async {
    setState(() => _isLoading = true);
    try {
      final db = await DbHelper.instance.database;
      await db.execute('''
        CREATE TABLE IF NOT EXISTS tax_slabs (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          igst REAL DEFAULT 0.0,
          cgst REAL DEFAULT 0.0,
          sgst REAL DEFAULT 0.0,
          is_active INTEGER DEFAULT 1
        )
      ''');

      final List<Map<String, dynamic>> maps = await db.query('tax_slabs', orderBy: 'igst ASC');
      
      if (maps.isEmpty) {
        final defaultSlabs = [
          TaxSlab(id: 'GST_0', name: 'GST 0%', igst: 0.0, cgst: 0.0, sgst: 0.0),
          TaxSlab(id: 'GST_5', name: 'GST 5%', igst: 5.0, cgst: 2.5, sgst: 2.5),
          TaxSlab(id: 'GST_12', name: 'GST 12%', igst: 12.0, cgst: 6.0, sgst: 6.0),
          TaxSlab(id: 'GST_18', name: 'GST 18%', igst: 18.0, cgst: 9.0, sgst: 9.0),
          TaxSlab(id: 'GST_28', name: 'GST 28%', igst: 28.0, cgst: 14.0, sgst: 14.0),
        ];
        for (var slab in defaultSlabs) {
          await db.insert('tax_slabs', slab.toMap());
        }
        _taxSlabs = defaultSlabs;
      } else {
        _taxSlabs = maps.map((m) => TaxSlab.fromMap(m)).toList();
      }
    } catch (e) {
      debugPrint("Tax Slabs Load Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onIgstChanged(String val) {
    double totalGst = double.tryParse(val) ?? 0.0;
    double half = totalGst / 2.0;
    _cgstCtrl.text = half.toStringAsFixed(2);
    _sgstCtrl.text = half.toStringAsFixed(2);
  }

  void _clear() {
    setState(() {
      _editingId = null;
      _nameCtrl.clear();
      _igstCtrl.text = "0";
      _cgstCtrl.text = "0";
      _sgstCtrl.text = "0";
      _isActive = true;
    });
  }

  void _edit(TaxSlab slab) {
    setState(() {
      _editingId = slab.id;
      _nameCtrl.text = slab.name;
      _igstCtrl.text = slab.igst.toString();
      _cgstCtrl.text = slab.cgst.toString();
      _sgstCtrl.text = slab.sgst.toString();
      _isActive = slab.isActive;
    });
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tax Name is required")));
      return;
    }

    final db = await DbHelper.instance.database;
    final double igst = double.tryParse(_igstCtrl.text) ?? 0.0;
    final double cgst = double.tryParse(_cgstCtrl.text) ?? (igst / 2);
    final double sgst = double.tryParse(_sgstCtrl.text) ?? (igst / 2);

    final slab = TaxSlab(
      id: _editingId ?? "TAX_${DateTime.now().millisecondsSinceEpoch}",
      name: _nameCtrl.text.trim(),
      igst: igst,
      cgst: cgst,
      sgst: sgst,
      isActive: _isActive,
    );

    if (_editingId != null) {
      await db.update('tax_slabs', slab.toMap(), where: 'id = ?', whereArgs: [_editingId]);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.blue, content: Text("Tax Slab Updated!")));
    } else {
      await db.insert('tax_slabs', slab.toMap());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text("Tax Slab Saved!")));
    }

    _clear();
    _loadTaxSlabs();
  }

  Future<void> _delete(String id) async {
    final db = await DbHelper.instance.database;
    await db.delete('tax_slabs', where: 'id = ?', whereArgs: [id]);
    _loadTaxSlabs();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.red, content: Text("Tax Slab Deleted")));
  }

  @override
  Widget build(BuildContext context) {
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
                Expanded(child: _buildGrid()),
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
            decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.percent_rounded, color: Colors.purple.shade800, size: 20),
          ),
          const SizedBox(width: 16),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("TAX SLAB REGISTRATION", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1, color: Colors.black87)),
              Text("GST & Rate Slabs for Invoicing", style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _formField("Sl No", _editingId ?? "Auto", enabled: false),
          const SizedBox(height: 16),
          _formField("Tax Name*", "", controller: _nameCtrl, isCyan: true),
          const SizedBox(height: 16),
          _formField("Total IGST %*", "0", controller: _igstCtrl, isNumeric: true, onChanged: _onIgstChanged),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _formField("CGST %", "0", controller: _cgstCtrl, isNumeric: true)),
              const SizedBox(width: 12),
              Expanded(child: _formField("SGST %", "0", controller: _sgstCtrl, isNumeric: true)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Checkbox(
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v ?? true),
                visualDensity: VisualDensity.compact,
              ),
              const Text("Active Slab", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _formField(
    String label,
    String initialVal, {
    TextEditingController? controller,
    bool enabled = true,
    bool isCyan = false,
    bool isNumeric = false,
    Function(String)? onChanged,
  }) {
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
                  enabled: enabled,
                  keyboardType: isNumeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                  inputFormatters: isNumeric ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
                  onChanged: onChanged,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(initialVal, style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade400, fontWeight: FontWeight.w600)),
                ),
        ),
      ],
    );
  }

  Widget _buildGrid() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        Container(
          height: 35,
          color: const Color(0xFF4A4A4A),
          child: const Row(
            children: [
              _Hdr("TAX SLAB NAME", flex: 3),
              _Hdr("IGST %", width: 70, align: TextAlign.right),
              _Hdr("CGST %", width: 70, align: TextAlign.right),
              _Hdr("SGST %", width: 70, align: TextAlign.right),
              _Hdr("STATUS", width: 80, align: TextAlign.center),
              _Hdr("", width: 80),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _taxSlabs.length,
            itemBuilder: (context, i) {
              final s = _taxSlabs[i];
              return Container(
                height: 38,
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                child: Row(
                  children: [
                    _Cell(s.name, flex: 3, fontWeight: FontWeight.bold),
                    _Cell("${s.igst.toStringAsFixed(1)}%", width: 70, align: TextAlign.right),
                    _Cell("${s.cgst.toStringAsFixed(1)}%", width: 70, align: TextAlign.right),
                    _Cell("${s.sgst.toStringAsFixed(1)}%", width: 70, align: TextAlign.right),
                    _Cell(s.isActive ? "Active" : "Inactive", width: 80, align: TextAlign.center, color: s.isActive ? Colors.green : Colors.red, fontWeight: FontWeight.bold),
                    SizedBox(
                      width: 80,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 16, color: Colors.blue),
                            onPressed: () => _edit(s),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                            onPressed: () => _delete(s.id),
                          ),
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