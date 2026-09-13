import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/pharmacy_provider.dart';
import '../../utils/app_dialogs.dart';
import '../../utils/theme_constants.dart';

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class LedgerRegistrationScreen extends StatefulWidget {
  const LedgerRegistrationScreen({super.key});

  @override
  State<LedgerRegistrationScreen> createState() => _LedgerRegistrationScreenState();
}

class _LedgerRegistrationScreenState extends State<LedgerRegistrationScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _gstCtrl = TextEditingController();
  final _dlCtrl = TextEditingController(); // ADD THIS LINE
  String _type = "Supplier";

  bool _isExistingEntry = false;
  String _editingId = ""; // Stores the ID of the ledger being edited

  void _resetPage() {
    setState(() {
      _nameCtrl.clear();
      _phoneCtrl.clear();
      _addressCtrl.clear();
      _gstCtrl.clear();
      _dlCtrl.clear();
      _isExistingEntry = false;
      _editingId = "";
    });
  }

  void _save({bool isEdit = false}) async {
    if (_nameCtrl.text.trim().isEmpty) {
      AppDialogs.showFastDialog(context: context, title: "Required", content: "Account Name is required.");
      return;
    }

    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    try {
      if (_type == "Supplier") {
        if (isEdit) {
          // Find existing and update
          final existing = provider.supplierMaster.firstWhere((s) => s.id == _editingId);
          final updatedSupplier = Supplier(
            id: existing.id,
            name: _nameCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            address: _addressCtrl.text.trim(),
            gstIn: _gstCtrl.text.trim(),
            dlNumber: _dlCtrl.text.trim(),
            currentBalance: existing.currentBalance,
          );
          await provider.updateSupplier(updatedSupplier);
        } else {
          // Create new
          final newSupplier = Supplier(
            id: "SUP_${DateTime.now().millisecondsSinceEpoch}",
            name: _nameCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            address: _addressCtrl.text.trim(),
            gstIn: _gstCtrl.text.trim(),
            dlNumber: _dlCtrl.text.trim(),
          );
          await provider.registerSupplier(newSupplier);
        }
      } else if (_type == "Patient") {
        if (isEdit) {
          final existing = provider.patientMaster.firstWhere((p) => p.id == _editingId);
          final updated = Patient(
            id: existing.id,
            name: _nameCtrl.text.trim(),
            mobile: _phoneCtrl.text.trim(),
            address: _addressCtrl.text.trim(),
            currentBalance: existing.currentBalance,
          );
          await provider.updatePatient(updated);
        } else {
          final newPatient = Patient(
            id: "PAT_${DateTime.now().millisecondsSinceEpoch}",
            name: _nameCtrl.text.trim(),
            mobile: _phoneCtrl.text.trim(),
            address: _addressCtrl.text.trim(),
          );
          await provider.registerPatient(newPatient);
        }
      } else {
        if (isEdit) {
          final existing = provider.doctorMaster.firstWhere((d) => d.id == _editingId);
          final updated = Doctor(
            id: existing.id,
            name: _nameCtrl.text.trim(),
            mobile: _phoneCtrl.text.trim(),
          );
          await provider.updateDoctor(updated);
        } else {
          final newDoctor = Doctor(
            id: "DOC_${DateTime.now().millisecondsSinceEpoch}",
            name: _nameCtrl.text.trim(),
            mobile: _phoneCtrl.text.trim(),
          );
          await provider.registerDoctor(newDoctor);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.green,
            content: Text(isEdit ? "Ledger Updated!" : "Ledger Registered!"))
        );
        _resetPage();
      }
    } catch (e) {
      if (mounted) {
        AppDialogs.showFastDialog(context: context, title: "Error", content: "Failed to save: $e");
      }
    }
  }

  void _loadForEdit(dynamic item) {
    setState(() {
      _isExistingEntry = true;
      if (_type == "Supplier") {
        final supplier = item as Supplier;
        _editingId = supplier.id;
        _nameCtrl.text = supplier.name;
        _phoneCtrl.text = supplier.phone;
        _addressCtrl.text = supplier.address;
        _gstCtrl.text = supplier.gstIn;
        _dlCtrl.text = supplier.dlNumber;
      } else if (_type == "Patient") {
        final patient = item as Patient;
        _editingId = patient.id;
        _nameCtrl.text = patient.name;
        _phoneCtrl.text = patient.mobile;
        _addressCtrl.text = patient.address;
        _gstCtrl.clear();
        _dlCtrl.clear();
      } else {
        final doctor = item as Doctor;
        _editingId = doctor.id;
        _nameCtrl.text = doctor.name;
        _phoneCtrl.text = doctor.mobile;
        _addressCtrl.clear();
        _gstCtrl.clear();
        _dlCtrl.clear();
      }
    });
  }

  void _deleteEntry(dynamic item) async {
    final res = await AppDialogs.showConfirmDialog(
        context: context,
        title: "Confirm Delete",
        content: "Are you sure you want to delete this ledger account?",
        isDangerous: true
    );

    if (res == true && mounted) {
      final provider = Provider.of<PharmacyProvider>(context, listen: false);
      if (_type == "Supplier") {
        await provider.deleteSupplier((item as Supplier).id);
      } else if (_type == "Patient") {
        await provider.deletePatient((item as Patient).id);
      } else {
        await provider.deleteDoctor((item as Doctor).id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.red, content: Text("Account Deleted")));
        if (_isExistingEntry) _resetPage();
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _gstCtrl.dispose();
    _dlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PharmacyProvider>(context);

    // Dynamically fetch the correct list based on selection
    List<dynamic> currentList = [];
    if (_type == "Supplier") {
      currentList = provider.supplierMaster; // Using the detailed master list
    } else if (_type == "Patient") {
      currentList = provider.patientMaster;
    } else {
      currentList = provider.doctorMaster;
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () => _save(isEdit: false),
        const SingleActivator(LogicalKeyboardKey.f3): _resetPage,
      },
      child: Scaffold(
        backgroundColor: AppColors.of(context).background,
        body: Column(
          children: [
            _buildToolbar(),
            Expanded(
              child: Row(
                children: [
                  _buildFormPanel(),
                  const VerticalDivider(width: 1),
                  Expanded(child: _buildGridArea(currentList)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    bool canSave = !_isExistingEntry;
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
            child: Icon(Icons.people_alt_rounded, color: Colors.purple.shade800, size: 20),
          ),
          const SizedBox(width: 16),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("LEDGER REGISTRATION", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1, color: Colors.black87)),
              Text("Manage Customers & Suppliers", style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
            ],
          ),
          const Spacer(),
          _toolbarButton(Icons.add_circle_outline, "NEW (F3)", Colors.blue, onTap: _resetPage),
          const SizedBox(width: 12),
          _toolbarButton(
              Icons.save_outlined,
              "SAVE (F2)",
              canSave ? Colors.green : Colors.grey,
              isPrimary: canSave,
              onTap: () => _save(isEdit: false) // ALWAYS SAVES AS NEW
          ),
          const SizedBox(width: 12),
          _toolbarButton(
              Icons.edit_outlined,
              "EDIT",
              _isExistingEntry ? Colors.orange : Colors.grey,
              isPrimary: _isExistingEntry,
              onTap: _isExistingEntry ? () => _save(isEdit: true) : () {
                AppDialogs.showFastDialog(context: context, title: "Locked", content: "This is a new entry. Click 'Save' instead.");
              }
          ),
        ],
      ),
    );
  }

  Widget _toolbarButton(IconData icon, String label, Color color, {VoidCallback? onTap, bool isPrimary = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isPrimary ? color : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isPrimary ? color : Colors.grey.shade300),
          boxShadow: isPrimary ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isPrimary ? Colors.white : color, size: 20),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 13, color: isPrimary ? Colors.white : Colors.black87, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildFormPanel() {
    return Container(
      width: 350, padding: const EdgeInsets.all(24), color: const Color(0xFFF1F5F9),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dropdown("Account Type*", _type, ["Supplier", "Patient", "Doctor"], (v) {
              setState(() {
                _type = v!;
                _resetPage(); // Clear form when switching types
              });
            }),
            const SizedBox(height: 20),
            _input("Account Name*", _nameCtrl, isCyan: true),
            const SizedBox(height: 20),
            _input("Phone Number", _phoneCtrl, isNumeric: true),
            const SizedBox(height: 20),
            _input("GSTIN Number", _gstCtrl),
            const SizedBox(height: 20),
            _input("Drug License (DL)", _dlCtrl),
            const SizedBox(height: 20),
            _input("Full Address", _addressCtrl, maxLines: 3),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline, size: 16, color: Colors.orange),
                  SizedBox(width: 12),
                  Expanded(child: Text("Ensure accurate GSTIN for proper taxation in invoices.", style: TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w500))),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _input(String label, TextEditingController ctrl, {bool isCyan = false, bool isNumeric = false, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.blueGrey.shade600, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: isCyan ? const Color(0xFFE0FFFF).withValues(alpha: 0.5) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: TextField(
            controller: ctrl,
            maxLines: maxLines,
            keyboardType: isNumeric ? TextInputType.phone : TextInputType.text,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: isNumeric ? [] : [UpperCaseTextFormatter()],
            decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _dropdown(String label, String val, List<String> items, Function(String?) onChange) {
    final uniqueItems = items.toSet().toList();
    if (!uniqueItems.contains(val)) {
      uniqueItems.insert(0, val);
    }
    final safeVal = uniqueItems.contains(val) ? val : (uniqueItems.isNotEmpty ? uniqueItems.first : val);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.blueGrey.shade600, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: safeVal, isExpanded: true, items: uniqueItems.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)))).toList(),
              onChanged: onChange,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGridArea(List<dynamic> items) {
    return Column(
      children: [
        Container(
          height: 35, color: const Color(0xFF4A4A4A),
          child: Row(
            children: [
              const Expanded(child: _Hdr("NAME / ACCOUNT")),
              if (_type == "Supplier") const _Hdr("GSTIN", width: 150),
              _Hdr(_type.toUpperCase() == "PATIENT" ? "VISITS" : "BALANCE", width: 100, align: TextAlign.right),
              const _Hdr("STATUS", width: 80, align: TextAlign.center),
              const _Hdr("", width: 40),
              const _Hdr("", width: 40),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: Colors.white,
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                String displayName = "";
                String balance = "";
                String gst = "";

                if (_type == "Supplier") {
                  final sup = item as Supplier;
                  displayName = sup.name;
                  balance = "₹ ${sup.currentBalance.toStringAsFixed(2)}";
                  gst = sup.gstIn.isNotEmpty ? sup.gstIn : "N/A";
                } else if (_type == "Patient") {
                  final pat = item as Patient;
                  displayName = pat.name;
                  balance = "₹ ${pat.currentBalance.toStringAsFixed(2)}";
                } else {
                  final doc = item as Doctor;
                  displayName = doc.name;
                  balance = "Active";
                }

                return InkWell(
                  onTap: () => _loadForEdit(item),
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                        color: _isExistingEntry && _nameCtrl.text == displayName ? Colors.blue.shade50 : Colors.white,
                        border: Border(bottom: BorderSide(color: Colors.grey.shade100))
                    ),
                    child: Row(
                      children: [
                        _Cell(displayName, fontWeight: FontWeight.bold),
                        if (_type == "Supplier") _Cell(gst, width: 150, color: Colors.blueGrey),
                        _Cell(balance, width: 100, align: TextAlign.right, color: _type == "Supplier" && (item as Supplier).currentBalance > 0 ? Colors.red : Colors.black87),
                        const _Cell("Active", width: 80, color: Colors.green, fontWeight: FontWeight.bold, align: TextAlign.center),
                        _actionCell(Icons.edit_outlined, Colors.blue, onTap: () => _loadForEdit(item)),
                        _actionCell(Icons.delete_outline, Colors.red, onTap: () => _deleteEntry(item)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _actionCell(IconData icon, Color color, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
          width: 40,
          decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.grey.shade100))),
          child: Center(child: Icon(icon, color: color, size: 18))
      ),
    );
  }
}

class _Hdr extends StatelessWidget {
  final String title; final double? width; final TextAlign align;
  const _Hdr(this.title, {this.width, this.align = TextAlign.left});
  @override Widget build(BuildContext context) {
    Widget child = Container(
      width: width,
      alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.right ? Alignment.centerRight : Alignment.center),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
    );
    return width == null ? Expanded(child: child) : child;
  }
}

class _Cell extends StatelessWidget {
  final String text; final double? width; final int? flex; final Color? color; final FontWeight fontWeight; final TextAlign align;
  const _Cell(this.text, {this.width, this.color, this.fontWeight = FontWeight.w600, this.align = TextAlign.left}) : flex = null;
  @override Widget build(BuildContext context) {
    Widget child = Container(
      width: width,
      alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.right ? Alignment.centerRight : Alignment.center),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(text, style: TextStyle(fontSize: 13, color: color ?? Colors.black87, fontWeight: fontWeight), overflow: TextOverflow.ellipsis),
    );
    return width == null ? Expanded(flex: flex ?? 1, child: child) : child;
  }
}