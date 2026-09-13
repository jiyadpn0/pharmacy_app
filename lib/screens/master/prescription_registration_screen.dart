import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/pharmacy_provider.dart';
import '../../utils/theme_constants.dart';

class PrescriptionRegistrationScreen extends StatefulWidget {
  const PrescriptionRegistrationScreen({super.key});

  @override
  State<PrescriptionRegistrationScreen> createState() => _PrescriptionRegistrationScreenState();
}

class _PrescriptionRegistrationScreenState extends State<PrescriptionRegistrationScreen> {
  bool _isDetailView = false;
  Prescription? _activePrescription;
  final Set<String> _selectedIds = {};
  bool _showImportedOnly = false;

  // Form Controllers
  final TextEditingController _entryNoCtrl = TextEditingController();
  final TextEditingController _dateCtrl = TextEditingController();
  final TextEditingController _patientCtrl = TextEditingController();
  final TextEditingController _doctorCtrl = TextEditingController();
  final TextEditingController _diseaseCtrl = TextEditingController();
  final TextEditingController _mobCtrl = TextEditingController();
  final TextEditingController _daysCtrl = TextEditingController();
  bool _isActive = true;

  List<PrescriptionItem> _items = [];
  final List<TextEditingController> _itemNameCtrls = [];
  final List<TextEditingController> _itemQtyCtrls = [];
  final List<FocusNode> _itemNameFocusNodes = [];
  final List<FocusNode> _itemQtyFocusNodes = [];

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _patientFocusNode = FocusNode();
  final FocusNode _doctorFocusNode = FocusNode();

  void _loadPrescription(Prescription p) {
    setState(() {
      _activePrescription = p;
      _isDetailView = true;
      _entryNoCtrl.text = p.prescriptionNo.toString();
      _dateCtrl.text = DateFormat('dd/MM/yyyy').format(p.date);
      _patientCtrl.text = p.patientName;
      _doctorCtrl.text = p.doctorName;
      _diseaseCtrl.text = p.diseaseName;
      _mobCtrl.text = p.mobile;
      _daysCtrl.text = p.days.toString();
      _isActive = p.isActive;
      _items = List.from(p.items);
      _syncItemControllers();
    });
  }

  void _createNew() async {
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final nextNo = await p.getNextPrescriptionNo();
    setState(() {
      _activePrescription = null;
      _isDetailView = true;
      _entryNoCtrl.text = nextNo;
      _dateCtrl.text = DateFormat('dd/MM/yyyy').format(DateTime.now());
      _patientCtrl.clear();
      _doctorCtrl.clear();
      _diseaseCtrl.clear();
      _mobCtrl.clear();
      _daysCtrl.text = "0";
      _isActive = true;
      _items = [PrescriptionItem(name: "")];
      _syncItemControllers();
    });
  }

  void _updateItemsFromControllers() {
    for (int i = 0; i < _items.length; i++) {
      _items[i].name = _itemNameCtrls[i].text;
      _items[i].qty = double.tryParse(_itemQtyCtrls[i].text) ?? 0;
    }
  }

  void _syncItemControllers() {
    _itemNameCtrls.clear();
    _itemQtyCtrls.clear();
    _itemNameFocusNodes.clear();
    _itemQtyFocusNodes.clear();
    for (var item in _items) {
      _itemNameCtrls.add(TextEditingController(text: item.name));
      _itemQtyCtrls.add(TextEditingController(text: item.qty == 0 ? "" : item.qty.toString()));
      _itemNameFocusNodes.add(FocusNode());
      _itemQtyFocusNodes.add(FocusNode());
    }
  }

  @override
  void dispose() {
    _patientFocusNode.dispose();
    _doctorFocusNode.dispose();
    for (var f in _itemNameFocusNodes) {
      f.dispose();
    }
    for (var f in _itemQtyFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _save() async {
    if (_patientCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Patient name required")));
      return;
    }
    if (_doctorCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Doctor name required")));
      return;
    }

    // Update items from controllers
    for (int i = 0; i < _items.length; i++) {
      _items[i].name = _itemNameCtrls[i].text;
      _items[i].qty = double.tryParse(_itemQtyCtrls[i].text) ?? 0;
    }

    final p = Prescription(
      id: _activePrescription?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      prescriptionNo: _activePrescription?.prescriptionNo ?? 0,
      patientName: _patientCtrl.text,
      doctorName: _doctorCtrl.text,
      diseaseName: _diseaseCtrl.text,
      mobile: _mobCtrl.text,
      days: int.tryParse(_daysCtrl.text) ?? 0,
      date: _activePrescription?.date ?? DateTime.now(),
      saleEntryNo: _activePrescription?.saleEntryNo ?? "",
      isActive: _isActive,
      items: _items.where((it) => it.name.isNotEmpty).toList(),
    );

    final assignedNo = await Provider.of<PharmacyProvider>(context, listen: false).addPrescription(p);
    setState(() => _isDetailView = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text("Prescription #$assignedNo Saved!")));
    }
  }

  void _navigate(int direction) {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    if (provider.prescriptions.isEmpty) return;
    
    int index = -1;
    if (_activePrescription != null) {
      index = provider.prescriptions.indexWhere((p) => p.id == _activePrescription!.id);
    }

    int nextIndex = index + direction;
    if (nextIndex >= 0 && nextIndex < provider.prescriptions.length) {
      _loadPrescription(provider.prescriptions[nextIndex]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      body: _isDetailView ? _buildDetailView() : _buildListView(),
    );
  }

  Widget _buildListView() {
    final provider = Provider.of<PharmacyProvider>(context);
    final prescriptions = provider.prescriptions.where((p) {
      final q = _searchCtrl.text.toLowerCase();
      bool match = p.patientName.toLowerCase().contains(q) || p.prescriptionNo.toString().contains(q);
      if (_showImportedOnly && !p.isImported) match = false;
      return match;
    }).toList();

    return Column(
      children: [
        _buildListToolbar(),
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              children: [
                Container(
                  height: 35,
                  color: const Color(0xFFE9EDF2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Checkbox(
                          value: _selectedIds.length == prescriptions.length && prescriptions.isNotEmpty,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedIds.addAll(prescriptions.map((p) => p.id));
                              } else {
                                _selectedIds.clear();
                              }
                            });
                          },
                        ),
                      ),
                      const _Hdr("Entry", width: 80),
                      const _Hdr("Date", width: 120),
                      const _Hdr("Patient", flex: 1),
                      const _Hdr("days", width: 100),
                      const _Hdr("Status", width: 100),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: prescriptions.length,
                    itemBuilder: (ctx, i) {
                      final p = prescriptions[i];
                      bool isSelected = _selectedIds.contains(p.id);
                      return InkWell(
                        onTap: () => _loadPrescription(p),
                        child: Container(
                          height: 35,
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                            color: isSelected ? Colors.blue.shade50 : null,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 40,
                                child: Checkbox(
                                  value: isSelected,
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selectedIds.add(p.id);
                                      } else {
                                        _selectedIds.remove(p.id);
                                      }
                                    });
                                  },
                                ),
                              ),
                              _Cell(p.prescriptionNo.toString(), width: 80),
                              _Cell(DateFormat('dd/MM/yyyy').format(p.date), width: 120),
                              _Cell(p.patientName, flex: 1),
                              _Cell(p.days.toString(), width: 100),
                              Container(
                                width: 100,
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  p.isImported ? "IMPORTED" : "PENDING",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: p.isImported ? Colors.green : Colors.orange,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListToolbar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Colors.white,
      child: Row(
        children: [
          const Text("Prescription Records", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(width: 20),
          Row(
            children: [
              Checkbox(
                value: _showImportedOnly,
                onChanged: (v) => setState(() => _showImportedOnly = v!),
              ),
              const Text("Imported Only", style: TextStyle(fontSize: 12)),
            ],
          ),
          if (_selectedIds.isNotEmpty) ...[
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: () {
                Provider.of<PharmacyProvider>(context, listen: false).deleteMultiplePrescriptions(_selectedIds.toList());
                setState(() => _selectedIds.clear());
              },
              icon: const Icon(Icons.delete_forever, size: 18),
              label: Text("DELETE SELECTED (${_selectedIds.length})"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10)),
            ),
          ],
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () {
              final importedIds = Provider.of<PharmacyProvider>(context, listen: false)
                  .prescriptions.where((p) => p.isImported).map((p) => p.id).toList();
              if (importedIds.isNotEmpty) {
                Provider.of<PharmacyProvider>(context, listen: false).deleteMultiplePrescriptions(importedIds);
              }
            },
            icon: const Icon(Icons.cleaning_services, size: 18),
            label: const Text("DELETE ALL IMPORTED"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10)),
          ),
          const Spacer(),
          SizedBox(
            width: 300,
            height: 32,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() {}),
              decoration: InputDecoration(
                hintText: "Search Patient or Entry...",
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _createNew,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text("NEW PRESCRIPTION", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailView() {
    final pharmacy = Provider.of<PharmacyProvider>(context);
    return Column(
      children: [
        _buildDetailToolbar(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderForm(pharmacy),
                const SizedBox(height: 20),
                _buildItemTable(pharmacy),
                const SizedBox(height: 20),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      child: const Text("SAVE", style: TextStyle(color: Colors.white)),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => setState(() => _isDetailView = false),
                      child: const Text("BACK TO LIST"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailToolbar() {
    return Container(
      height: 50,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _navBtn(Icons.arrow_back_ios_new, () => _navigate(1)), // Reversed because prescriptions are date DESC
          _navBtn(Icons.arrow_forward_ios, () => _navigate(-1)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => setState(() => _isDetailView = false),
            icon: const Icon(Icons.manage_search, size: 18),
            label: const Text("Find"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade200,
              foregroundColor: Colors.black87,
              elevation: 0,
              side: BorderSide(color: Colors.grey.shade400),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback onTap) => Container(
    margin: const EdgeInsets.only(right: 8),
    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4)),
    child: IconButton(icon: Icon(icon, size: 16), onPressed: onTap, constraints: const BoxConstraints(minWidth: 32, minHeight: 32), padding: EdgeInsets.zero),
  );

  Widget _buildHeaderForm(PharmacyProvider pharmacy) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFE8EAF6), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade300)),
      child: Column(
        children: [
          Row(
            children: [
              _formField("EntryNo", _entryNoCtrl, width: 120, readOnly: true),
              const SizedBox(width: 20),
              _formAutocomplete("Patient Name*", _patientCtrl, pharmacy.patients, width: 300, focusNode: _patientFocusNode),
              const SizedBox(width: 20),
              _formField("Mob", _mobCtrl, width: 150),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _formField("Date", _dateCtrl, width: 120, readOnly: true),
              const SizedBox(width: 20),
              _formAutocomplete("Doctors Name", _doctorCtrl, pharmacy.doctors, width: 300, focusNode: _doctorFocusNode),
              const SizedBox(width: 20),
              _formField("Days", _daysCtrl, width: 80),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: 120,
                height: 40,
                child: Row(
                  children: [
                    Checkbox(value: _isActive, onChanged: (v) => setState(() => _isActive = v!)),
                    const Text("Active", style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              _formField("Disease Name", _diseaseCtrl, width: 300),
            ],
          ),
        ],
      ),
    );
  }

  Widget _formField(String label, TextEditingController ctrl, {double? width, bool readOnly = false}) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Container(
            height: 28,
            decoration: BoxDecoration(color: readOnly ? Colors.grey.shade200 : Colors.white, border: Border.all(color: Colors.grey.shade400)),
            child: TextField(
              controller: ctrl,
              readOnly: readOnly,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formAutocomplete(String label, TextEditingController ctrl, List<String> suggestions, {double? width, FocusNode? focusNode}) {
    String? focusedText;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) => RawAutocomplete<String>(
              textEditingController: ctrl,
              focusNode: focusNode,
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
                final query = textEditingValue.text.trim().toLowerCase();
                if (focusedText != null &&
                    textEditingValue.text == focusedText &&
                    suggestions.any((s) => s.trim().toLowerCase() == query)) {
                  return const Iterable<String>.empty();
                }
                return suggestions.where((String option) => option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                focusNode.addListener(() {
                  if (focusNode.hasFocus) {
                    focusedText = controller.text;
                  } else {
                    focusedText = null;
                  }
                });
                return Container(
                  height: 28,
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400)),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onTap: () {
                      if (focusNode.hasFocus) {
                        focusedText = controller.text;
                      }
                    },
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                  ),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4.0,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final option = options.elementAt(index);
                          return ListTile(
                            title: Text(option, style: const TextStyle(fontSize: 12)),
                            dense: true,
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemTable(PharmacyProvider pharmacy) {
    return Container(
      width: 600,
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400)),
      child: Column(
        children: [
          Container(
            height: 25,
            color: const Color(0xFF607D8B),
            child: const Row(
              children: [
                _Hdr("Slno", width: 50),
                _Hdr("name", flex: 1),
                _Hdr("qty", width: 60),
              ],
            ),
          ),
          ...List.generate(_items.length, (i) => _itemRow(i, pharmacy)),
          InkWell(
            onTap: () => setState(() {
              _updateItemsFromControllers();
              _items.add(PrescriptionItem(name: ""));
              _syncItemControllers();
            }),
            child: Container(
              height: 25,
              width: double.infinity,
              color: Colors.grey.shade100,
              alignment: Alignment.center,
              child: const Icon(Icons.add, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(int index, PharmacyProvider pharmacy) {
    return Container(
      height: 25,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
      child: Row(
        children: [
          Container(
            width: 50, 
            alignment: Alignment.center, 
            decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.grey))), 
            child: Text("${index + 1}"),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.grey))), 
              child: RawAutocomplete<Product>(
                textEditingController: _itemNameCtrls[index],
                focusNode: _itemNameFocusNodes[index],
                optionsBuilder: (TextEditingValue textEditingValue) {
                  final q = textEditingValue.text.trim().toLowerCase();
                  if (q.isEmpty) return const Iterable<Product>.empty();

                  // THE RULE: Suppress dropdown if already matches current item
                  if (q == _itemNameCtrls[index].text.trim().toLowerCase()) {
                    return const Iterable<Product>.empty();
                  }

                  return pharmacy.searchProducts(q);
                },
                onSelected: (Product p) {
                  _itemNameCtrls[index].text = p.name;
                  _itemQtyFocusNodes[index].requestFocus();
                },
                displayStringForOption: (Product p) => p.name,
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onSubmitted: (v) {
                      if (v.isNotEmpty) _itemQtyFocusNodes[index].requestFocus();
                    },
                    decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                    style: const TextStyle(fontSize: 12),
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4.0,
                      child: SizedBox(
                        width: 450,
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final p = options.elementAt(index);
                            return ListTile(
                              title: Text(p.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              subtitle: Text("Rack: ${p.rack} | Stock: ${p.stock} | MRP: ${p.mrp}", style: const TextStyle(fontSize: 10)),
                              dense: true,
                              onTap: () => onSelected(p),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          SizedBox(
            width: 60, 
            child: TextField(
              controller: _itemQtyCtrls[index], 
              focusNode: _itemQtyFocusNodes[index],
              textAlign: TextAlign.right, 
              decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)), 
              style: const TextStyle(fontSize: 12),
              onSubmitted: (v) {
                if (index == _items.length - 1) {
                  setState(() {
                    _updateItemsFromControllers();
                    _items.add(PrescriptionItem(name: ""));
                    _syncItemControllers();
                  });
                  Future.delayed(const Duration(milliseconds: 50), () {
                    _itemNameFocusNodes[index + 1].requestFocus();
                  });
                } else {
                  _itemNameFocusNodes[index + 1].requestFocus();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Hdr extends StatelessWidget {
  final String title; final double? width; final int? flex;
  const _Hdr(this.title, {this.width, this.flex});
  @override
  Widget build(BuildContext context) {
    Widget child = Container(
      width: width, padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.grey, width: 0.5))),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
    );
    if (flex != null) return Expanded(flex: flex!, child: child);
    return child;
  }
}

class _Cell extends StatelessWidget {
  final String text; final double? width; final int? flex;
  const _Cell(this.text, {this.width, this.flex});
  @override
  Widget build(BuildContext context) {
    Widget child = Container(
      width: width, padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.grey, width: 0.3))),
      child: Text(text, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
    );
    if (flex != null) return Expanded(flex: flex!, child: child);
    return child;
  }
}
