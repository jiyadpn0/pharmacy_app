import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/pharmacy_provider.dart';
import '../../utils/theme_constants.dart';
import '../../widgets/pin_unlock_dialog.dart';

class DoctorRegistrationScreen extends StatefulWidget {
  const DoctorRegistrationScreen({super.key});

  @override
  State<DoctorRegistrationScreen> createState() => _DoctorRegistrationScreenState();
}

class _DoctorRegistrationScreenState extends State<DoctorRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _specialCtrl = TextEditingController();
  final _regNoCtrl = TextEditingController();
  
  // Filter controllers for the list
  final _filterNameCtrl = TextEditingController();
  final _filterStatusCtrl = TextEditingController();

  Doctor? _editingDoctor;
  bool _isActive = true;
  String? _focusedDoctorText;

  void _save() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    if (provider.securityToggles['require_pin_edit_master'] == true) {
      bool isUnlocked = await PinUnlockDialog.show(
        context,
        provider,
        title: "Master Data Lock",
        message: "Enter Master PIN to modify doctor master data."
      );
      if (!isUnlocked) return;
    }

    final doctor = Doctor(
      id: _editingDoctor?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameCtrl.text.trim(),
      mobile: _mobileCtrl.text.trim(),
      specialization: _specialCtrl.text.trim(),
      regNo: _regNoCtrl.text.trim(),
      isActive: _isActive,
    );

    if (_editingDoctor == null) {
      await provider.registerDoctor(doctor);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Doctor Registered Successfully"), backgroundColor: Colors.green));
    } else {
      await provider.updateDoctor(doctor);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Doctor Updated Successfully"), backgroundColor: Colors.blue));
    }

    _clear();
  }

  void _clear() {
    setState(() {
      _editingDoctor = null;
      _nameCtrl.clear();
      _mobileCtrl.clear();
      _specialCtrl.clear();
      _regNoCtrl.clear();
      _isActive = true;
    });
  }

  void _edit(Doctor d) {
    setState(() {
      _editingDoctor = d;
      _nameCtrl.text = d.name;
      _mobileCtrl.text = d.mobile;
      _specialCtrl.text = d.specialization;
      _regNoCtrl.text = d.regNo;
      _isActive = d.isActive;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final provider = Provider.of<PharmacyProvider>(context);
    
    // Apply filters from the table row filters
    final filteredDoctors = provider.doctorMaster.where((d) {
      final nameMatch = d.name.toLowerCase().contains(_filterNameCtrl.text.toLowerCase());
      final statusMatch = _filterStatusCtrl.text.isEmpty || 
          (d.isActive ? "active" : "inactive").contains(_filterStatusCtrl.text.toLowerCase());
      return nameMatch && statusMatch;
    }).toList();

    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          _buildToolbar(provider),
          Expanded(
            child: Row(
              children: [
                // LEFT: Registration Form
                Expanded(
                  flex: 2,
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: c.cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border),
                    ),
                    child: Form(
                      key: _formKey,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_editingDoctor == null ? "NEW DOCTOR REGISTRATION" : "EDIT DOCTOR DETAILS", 
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1, color: AppColors.primary)),
                            const SizedBox(height: 24),
                            _buildDoctorAutocomplete(provider),
                            const SizedBox(height: 16),
                            _buildField("Mobile Number", _mobileCtrl, Icons.phone),
                            const SizedBox(height: 16),
                            _buildField("Specialization", _specialCtrl, Icons.medical_services),
                            const SizedBox(height: 16),
                            _buildField("Registration No", _regNoCtrl, Icons.badge),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Checkbox(
                                  value: _isActive, 
                                  onChanged: (v) => setState(() => _isActive = v!),
                                  visualDensity: VisualDensity.compact,
                                ),
                                const Text("Active", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              ],
                            ),
                            const SizedBox(height: 32),
                            const Text("Registered doctors will be linked to Sales Entry.", 
                              style: TextStyle(color: Colors.grey, fontSize: 11, fontStyle: FontStyle.italic)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // RIGHT: Doctor List (GRID STYLE WITH FILTERS)
                Expanded(
                  flex: 3,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        Container(
                          height: 30,
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF1F5F9),
                            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                          ),
                          child: const Text("Drag a column header here to group by that column", 
                            style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic)),
                        ),
                        _buildGridHeader(),
                        _buildFilterRow(),
                        Expanded(
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: filteredDoctors.length,
                            itemBuilder: (ctx, i) {
                              final d = filteredDoctors[i];
                              return _buildDataRow(d, i % 2 == 0);
                            },
                          ),
                        ),
                        if (_filterNameCtrl.text.isNotEmpty)
                          Container(
                            height: 30,
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            color: const Color(0xFFF8FAFC),
                            child: Row(
                              children: [
                                InkWell(
                                  onTap: () => setState(() => _filterNameCtrl.clear()),
                                  child: const Icon(Icons.close, size: 14, color: Colors.black),
                                ),
                                const SizedBox(width: 8),
                                Checkbox(
                                  value: true,
                                  onChanged: (val) {
                                    if (val == false) setState(() => _filterNameCtrl.clear());
                                  },
                                  visualDensity: VisualDensity.compact,
                                ),
                                Text("Contains([name], '${_filterNameCtrl.text}')", style: const TextStyle(fontSize: 11)),
                                const Spacer(),
                                InkWell(
                                  onTap: () => setState(() => _filterNameCtrl.clear()),
                                  child: const Text("Clear Filter", style: TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(PharmacyProvider provider) {
    final c = AppColors.of(context);
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          _toolbarButton(Icons.person_add_alt, "NEW", Colors.blue, onTap: _clear),
          const SizedBox(width: 12),
          _toolbarButton(Icons.save_outlined, "SAVE DOCTOR", Colors.green, onTap: _save),
          const SizedBox(width: 12),
          if (_editingDoctor != null)
            _toolbarButton(Icons.delete_outline, "DELETE", Colors.red, onTap: () => _confirmDelete(_editingDoctor!)),
          const Spacer(),
          const Text("DOCTOR MASTER DATABASE", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.blueGrey, fontSize: 12, letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _toolbarButton(IconData icon, String label, Color color, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, IconData icon, {bool required = false, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          maxLines: maxLines,
          validator: required ? (v) => v!.isEmpty ? "Required" : null : null,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18, color: Colors.blueGrey),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade200)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.blue, width: 2)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            isDense: true,
            fillColor: const Color(0xFFE0FFFF).withValues(alpha: 0.3),
            filled: true,
          ),
        ),
      ],
    );
  }

  // GRID UI COMPONENTS (Similar to provided photos)
  
  Widget _buildGridHeader() {
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          const SizedBox(width: 40), // For row icon
          _headerCell("name", flex: 3),
          _headerCell("status", flex: 1),
          _headerCell("", width: 60), // Edit icon space
          _headerCell("", width: 60), // Delete icon space
        ],
      ),
    );
  }

  Widget _headerCell(String label, {int? flex, double? width}) {
    Widget cell = Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
    );
    return flex != null ? Expanded(flex: flex, child: cell) : cell;
  }

  Widget _buildFilterRow() {
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            alignment: Alignment.center,
            child: const Icon(Icons.filter_alt_outlined, size: 16, color: Colors.grey),
          ),
          Expanded(
            flex: 3,
            child: _filterInp(_filterNameCtrl),
          ),
          Expanded(
            flex: 1,
            child: _filterInp(_filterStatusCtrl),
          ),
          const SizedBox(width: 60), // Space for action buttons
          const SizedBox(width: 60),
        ],
      ),
    );
  }

  Widget _filterInp(TextEditingController ctrl) {
    return Container(
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: TextField(
        controller: ctrl,
        onChanged: (v) => setState(() {}),
        style: const TextStyle(fontSize: 12),
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.abc, size: 18, color: Colors.blueGrey),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 6),
        ),
      ),
    );
  }

  Widget _buildDataRow(Doctor d, bool isEven) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isEven ? Colors.white : const Color(0xFFF1F5F9),
        border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          const SizedBox(width: 40),
          Expanded(flex: 3, child: _dataCell(d.name)),
          Expanded(flex: 1, child: _dataCell(d.isActive ? "Active" : "Inactive")),
          _actionCell(
            onTap: () => _edit(d),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Ab", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF475569))),
                Icon(Icons.edit, size: 14, color: Colors.orange.shade700),
              ],
            ),
          ),
          _actionCell(
            onTap: () => _confirmDelete(d),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: const Icon(Icons.close, color: Colors.red, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B))),
    );
  }

  Widget _actionCell({required Widget child, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 60,
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  Widget _buildDoctorAutocomplete(PharmacyProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Doctor Name *", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        const SizedBox(height: 6),
        Autocomplete<String>(
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) {
              return const Iterable<String>.empty();
            }
            final query = textEditingValue.text.toLowerCase().trim();
            if (_focusedDoctorText != null &&
                textEditingValue.text == _focusedDoctorText &&
                provider.doctorMaster.any((d) => d.name.toLowerCase().trim() == query)) {
              return const Iterable<String>.empty();
            }
            final matches = provider.doctorMaster
                .where((d) => d.name.toLowerCase().contains(query))
                .map((d) => d.name)
                .toList();
            matches.add('ADD NEW NAME: ${textEditingValue.text.toUpperCase()}');
            return matches;
          },
          onSelected: (String selection) async {
            if (selection.startsWith('ADD NEW NAME: ')) {
              final newName = selection.replaceAll('ADD NEW NAME: ', '').trim();
              final newDoctor = Doctor(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: newName,
                mobile: _mobileCtrl.text.trim(),
                specialization: _specialCtrl.text.trim(),
                regNo: _regNoCtrl.text.trim(),
                isActive: true,
              );
              await provider.registerDoctor(newDoctor);
              if (!mounted) return;
              setState(() {
                _nameCtrl.text = newName;
                _editingDoctor = newDoctor;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("DOCTOR NAME CREATED"), backgroundColor: Colors.green),
              );
            } else {
              setState(() {
                _nameCtrl.text = selection;
                final existing = provider.doctorMaster.cast<Doctor?>().firstWhere(
                  (d) => d?.name == selection, orElse: () => null
                );
                if (existing != null) {
                  _edit(existing);
                }
              });
            }
          },
          fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
            if (controller.text != _nameCtrl.text) {
              controller.text = _nameCtrl.text;
            }
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              onTap: () {
                if (focusNode.hasFocus) {
                  _focusedDoctorText = controller.text;
                }
              },
              onEditingComplete: onEditingComplete,
              onChanged: (v) => _nameCtrl.text = v,
              validator: (v) => v!.isEmpty ? "Required" : null,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.person, size: 18, color: Colors.blueGrey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.blue, width: 2)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                isDense: true,
                fillColor: const Color(0xFFE0FFFF).withValues(alpha: 0.3),
                filled: true,
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200, maxWidth: 350),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (BuildContext context, int index) {
                      final option = options.elementAt(index);
                      final isNew = option.startsWith('ADD NEW NAME: ');
                      return InkWell(
                        onTap: () => onSelected(option),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                            color: isNew ? Colors.blue.shade50 : Colors.white,
                          ),
                          child: Text(
                            option,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isNew ? FontWeight.bold : FontWeight.w600,
                              color: isNew ? Colors.blue.shade700 : Colors.black87,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _confirmDelete(Doctor d) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Doctor?"),
        content: Text("Are you sure you want to delete '${d.name}'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () {
              Provider.of<PharmacyProvider>(context, listen: false).deleteDoctor(d.id);
              Navigator.pop(ctx);
              if (_editingDoctor?.id == d.id) _clear();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("DELETE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
