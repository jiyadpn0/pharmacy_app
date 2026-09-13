import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/pharmacy_provider.dart';
import '../../widgets/pin_unlock_dialog.dart';
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

class SupplierListScreen extends StatefulWidget {
  const SupplierListScreen({super.key});

  @override
  State<SupplierListScreen> createState() => _SupplierListScreenState();
}

class _SupplierListScreenState extends State<SupplierListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = "";

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final pharmacy = Provider.of<PharmacyProvider>(context);
    final suppliers = pharmacy.supplierMaster.where((s) => 
      s.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
      s.phone.contains(_searchQuery)
    ).toList();

    return Container(
      padding: const EdgeInsets.all(24),
      color: const Color(0xFFF1F5F9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Supplier Registration", 
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                  Text("Manage your wholesale suppliers and their details", 
                    style: TextStyle(fontSize: 14, color: Colors.blueGrey.shade600)),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _showSupplierDialog(context),
                icon: const Icon(Icons.add),
                label: const Text("New Supplier"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: const InputDecoration(
                hintText: "Search by Name or Mobile...",
                border: InputBorder.none,
                icon: Icon(Icons.search, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  children: [
                    Container(
                      color: const Color(0xFF334155),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      child: const Row(
                        children: [
                          Expanded(flex: 3, child: Text("SUPPLIER NAME", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                          Expanded(flex: 2, child: Text("MOBILE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                          Expanded(flex: 2, child: Text("DL NUMBER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                          Expanded(flex: 2, child: Text("GST NUMBER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                          SizedBox(width: 100, child: Text("ACTIONS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: suppliers.length,
                        itemBuilder: (context, index) {
                          final s = suppliers[index];
                          return Container(
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: c.border)),
                              color: index % 2 == 0 ? c.tableRowEvenBg : c.tableRowOddBg,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            child: Row(
                              children: [
                                Expanded(flex: 3, child: Text(s.name.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, color: c.primaryText))),
                                Expanded(flex: 2, child: Text(s.phone.toUpperCase(), style: TextStyle(color: c.primaryText))),
                                Expanded(flex: 2, child: Text(s.dlNumber.toUpperCase(), style: TextStyle(color: c.primaryText))),
                                Expanded(flex: 2, child: Text(s.gstIn.toUpperCase(), style: TextStyle(color: c.primaryText))),
                                SizedBox(
                                  width: 100,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit, color: Colors.blue, size: 18),
                                        onPressed: () => _showSupplierDialog(context, supplier: s),
                                        tooltip: "Edit",
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                                        onPressed: () => _confirmDelete(context, s),
                                        tooltip: "Delete",
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
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSupplierDialog(BuildContext context, {Supplier? supplier}) {
    final nameCtrl = TextEditingController(text: supplier?.name ?? "");
    final phoneCtrl = TextEditingController(text: supplier?.phone ?? "");
    final dlCtrl = TextEditingController(text: supplier?.dlNumber ?? "");
    final gstCtrl = TextEditingController(text: supplier?.gstIn ?? "");
    final addrCtrl = TextEditingController(text: supplier?.address ?? "");

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(supplier == null ? "Add New Supplier" : "Edit Supplier"),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildField("Supplier Name*", nameCtrl),
                _buildField("Mobile Number", phoneCtrl),
                _buildField("DL Number", dlCtrl),
                _buildField("GST Number", gstCtrl),
                _buildField("Address", addrCtrl, maxLines: 2),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isEmpty) return;

              final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);

              if (pharmacy.securityToggles['require_pin_edit_master'] == true) {
                bool isUnlocked = await PinUnlockDialog.show(
                  context,
                  pharmacy,
                  title: "Master Data Lock",
                  message: "Enter Master PIN to ${supplier == null ? "add" : "edit"} supplier details."
                );
                if (!isUnlocked) return;
              }
              
              final newSupplier = Supplier(
                id: supplier?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                name: nameCtrl.text,
                phone: phoneCtrl.text,
                dlNumber: dlCtrl.text,
                gstIn: gstCtrl.text,
                address: addrCtrl.text,
                currentBalance: supplier?.currentBalance ?? 0.0,
              );

              if (supplier == null) {
                await pharmacy.registerSupplier(newSupplier);
              } else {
                await pharmacy.updateSupplier(newSupplier);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
            child: Text(supplier == null ? "Register" : "Update"),
          ),
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [UpperCaseTextFormatter()],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Supplier s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Supplier"),
        content: Text("Are you sure you want to delete '${s.name}'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("No")),
          ElevatedButton(
            onPressed: () async {
              await Provider.of<PharmacyProvider>(context, listen: false).deleteSupplier(s.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("Yes, Delete"),
          ),
        ],
      ),
    );
  }
}
