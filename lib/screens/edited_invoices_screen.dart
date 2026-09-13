import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/pharmacy_provider.dart';
import '../providers/app_provider.dart';
import '../utils/theme_constants.dart';
import '../widgets/pin_unlock_dialog.dart';
import '../widgets/edit_history_dialog.dart';
import '../widgets/app_date_picker.dart';
import '../utils/invoice_pdf_generator.dart';
import '../utils/printer_service.dart';

class EditedInvoicesScreen extends StatefulWidget {
  final bool headless;
  const EditedInvoicesScreen({super.key, this.headless = false});

  @override
  State<EditedInvoicesScreen> createState() => _EditedInvoicesScreenState();
}

class _EditedInvoicesScreenState extends State<EditedInvoicesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 180)); // 6 Months
  DateTime _toDate = DateTime.now();
  String _selectedType = 'Sales';
  bool _editedOnly = false;

  List<Map<String, dynamic>> _editedData = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final data = await provider.getEditedInvoices(_selectedType, _fromDate, _toDate, editedOnly: _editedOnly);
    
    List<Map<String, dynamic>> processedData = [];
    for (var rawItem in data) {
      final item = Map<String, dynamic>.from(rawItem);
      final entryNo = item['entry_no']?.toString() ?? "";

      List<dynamic> oldItems = [];
      try {
        if (item['previous_items_json'] != null) {
          oldItems = jsonDecode(item['previous_items_json']);
        }
      } catch (_) {}

      List<dynamic> newItems = [];
      if (item['new_items_json'] != null && item['new_items_json'].toString().trim().isNotEmpty) {
        try {
          newItems = jsonDecode(item['new_items_json']);
        } catch (_) {}
      } else if (entryNo.isNotEmpty) {
        newItems = await provider.getCurrentInvoiceItems(entryNo);
      }

      final diffs = EditHistoryDialog.generateDiffSummary(oldItems, newItems);
      if (diffs.isNotEmpty) {
        item['_edit_summary'] = diffs.join(" | ");
      } else if (oldItems.isNotEmpty) {
        item['_edit_summary'] = item['reason_for_edit'] ?? "Manual Edit";
      } else {
        item['_edit_summary'] = "No Edits";
      }

      processedData.add(item);
    }

    if (mounted) {
      setState(() {
        _editedData = processedData;
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredData {
    final query = _searchCtrl.text.toLowerCase();
    if (query.isEmpty) return _editedData;
    
    return _editedData.where((item) {
      final entryNo = item['entry_no']?.toString().toLowerCase() ?? "";
      final party = (item['patient'] ?? item['supplier_name'] ?? "").toString().toLowerCase();
      final summary = (item['_edit_summary'] ?? "").toString().toLowerCase();
      return entryNo.contains(query) || party.contains(query) || summary.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = Column(
      children: [
        if (!widget.headless) _buildToolbar(),
        _buildFilters(),
        Expanded(
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : _buildDataTable(_filteredData),
        ),
        _buildFooter(_filteredData.length),
      ],
    );

    if (widget.headless) return content;

    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      body: content,
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.history_rounded, color: Colors.orange, size: 24),
          ),
          const SizedBox(width: 16),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("EDITED INVOICES", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.5)),
              Text("Showing edited transaction history for the previous 6 months", style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: 300,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: "Search Invoice or Party...",
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      color: Colors.grey.shade50,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildDateField("From Date", _fromDate, (d) { _fromDate = d; _fetchData(); }),
            const SizedBox(width: 16),
            _buildDateField("To Date", _toDate, (d) { _toDate = d; _fetchData(); }),
            const SizedBox(width: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Sales', label: Text('Sales', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                ButtonSegment(value: 'Purchase', label: Text('Purchase', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                ButtonSegment(value: 'Sale Return', label: Text('Sales Ret', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                ButtonSegment(value: 'Purchase Return', label: Text('Pur Ret', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
              ],
              selected: {_selectedType},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() {
                  _selectedType = newSelection.first;
                });
                _fetchData();
              },
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                backgroundColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
                  if (states.contains(WidgetState.selected)) return AppColors.primary;
                  return Colors.white;
                }),
                foregroundColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) {
                  if (states.contains(WidgetState.selected)) return Colors.white;
                  return AppColors.primary;
                }),
              ),
            ),
            const SizedBox(width: 16),
            _buildToggle("Edited Only", _editedOnly, (v) {
              setState(() => _editedOnly = v);
              _fetchData();
            }),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: () {
                _fromDate = DateTime.now().subtract(const Duration(days: 180));
                _toDate = DateTime.now();
                _searchCtrl.clear();
                _fetchData();
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text("Reset Filters"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggle(String label, bool value, Function(bool) onChanged) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.orange,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }

  Widget _buildDateField(String label, DateTime date, Function(DateTime) onPick) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        const SizedBox(width: 8),
        InkWell(
          onTap: () async {
            final picked = await showAppDatePicker(context: context, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime(2100));
            if (picked != null) {
              if (label == "From Date") {
                if (picked.isAfter(_toDate)) {
                  setState(() => _toDate = picked);
                }
              } else {
                if (picked.isBefore(_fromDate)) {
                  setState(() => _fromDate = picked);
                }
              }
              onPick(picked);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade300)),
            child: Row(
              children: [
                Text(DateFormat('dd/MM/yyyy').format(date), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                const Icon(Icons.calendar_today, size: 14, color: Colors.blue),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDataTable(List<Map<String, dynamic>> data) {
    return Container(
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          children: [
            Container(
              height: 40,
              color: AppColors.primary,
              child: Row(
                children: [
                  const _Hdr("SL", width: 40, textAlign: TextAlign.center),
                  const _Hdr("DATE", width: 80),
                  const _Hdr("TIME", width: 60),
                  const _Hdr("INV NO", width: 90),
                  _Hdr(_selectedType.contains('Purchase') ? "SUPPLIER NAME" : "PATIENT NAME", flex: 2),
                  const _Hdr("EDIT DETAILS", flex: 3),
                  const _Hdr("OLD TOTAL", width: 100, textAlign: TextAlign.right),
                  const _Hdr("NEW TOTAL", width: 100, textAlign: TextAlign.right),
                  const _Hdr("ACTION", width: 90, textAlign: TextAlign.center),
                ],
              ),
            ),
            Expanded(
              child: data.isEmpty 
                ? const Center(child: Text("No edited invoices found for the selected period.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)))
                : ListView.builder(
                itemCount: data.length,
                itemBuilder: (context, i) {
                  final item = data[i];
                  DateTime dt = DateTime.tryParse(item['date']?.toString() ?? "") ?? DateTime.now();
                  final entryNo = item['entry_no']?.toString() ?? "";
                  final party = (item['patient'] ?? item['supplier_name'] ?? "").toString();
                  final editSummary = item['_edit_summary']?.toString() ?? "N/A";
                  final oldTotal = (item['previous_grand_total'] as num?)?.toDouble() ?? 0.0;
                  final newTotal = (item['grand_total'] as num?)?.toDouble() ?? 0.0;

                  return InkWell(
                    onTap: () => _openInvoiceInEditor(item),
                    child: Container(
                      height: 45,
                      decoration: BoxDecoration(
                        color: i % 2 == 0 ? Colors.white : Colors.grey.shade50,
                        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                      ),
                      child: Row(
                        children: [
                          _Cell("${i + 1}", width: 40, textAlign: TextAlign.center),
                          _Cell(DateFormat('dd/MM/yy').format(dt), width: 80),
                          _Cell(DateFormat('HH:mm').format(dt), width: 60),
                          _Cell(entryNo.toUpperCase(), width: 90, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                          _Cell(party.toUpperCase(), flex: 2, fontWeight: FontWeight.bold),
                          _Cell(editSummary, flex: 3, color: Colors.blueGrey.shade800, fontWeight: FontWeight.w600),
                          _Cell(oldTotal.toStringAsFixed(2), width: 100, textAlign: TextAlign.right, color: Colors.red.shade700),
                          _Cell(newTotal.toStringAsFixed(2), width: 100, textAlign: TextAlign.right, fontWeight: FontWeight.bold, color: AppColors.secondary),
                          Container(
                            width: 90,
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_document, color: Colors.orange, size: 18),
                                  tooltip: "Edit Invoice",
                                  onPressed: () => _openInvoiceInEditor(item),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.print, color: Colors.blueGrey, size: 18),
                                  tooltip: "Print Preview",
                                  onPressed: () async {
                                    final p = Provider.of<PharmacyProvider>(context, listen: false);
                                    if (_selectedType == 'Sales') {
                                      final inv = await p.getSaleInvoiceById(entryNo);
                                      if (inv != null && mounted) {
                                        final doc = await InvoicePdfGenerator.buildPdfDocument(inv, p.companyProfile);
                                        if (!mounted) return;
                                        PrinterService.showProfessionalPreview(context: context, doc: doc, title: "Invoice $entryNo Preview");
                                      }
                                    } else if (_selectedType == 'Purchase') {
                                      final purList = await p.fetchPurchasesInDateRange(_fromDate, _toDate, loadItems: true);
                                      final entry = purList.cast<PurchaseEntry?>().firstWhere((e) => e?.entryNo == entryNo, orElse: () => null);
                                      if (entry != null && mounted) {
                                        final doc = await InvoicePdfGenerator.buildPurchasePdf(entry, p.companyProfile);
                                        if (!mounted) return;
                                        PrinterService.showProfessionalPreview(context: context, doc: doc, title: "Purchase $entryNo Preview");
                                      }
                                    }
                                  },
                                ),
                              ],
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
    );
  }

  void _openInvoiceInEditor(Map<String, dynamic> item) async {
    final entryNo = item['entry_no']?.toString() ?? "";
    DateTime dt = DateTime.tryParse(item['date']?.toString() ?? "") ?? DateTime.now();

    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final appProvider = Provider.of<AppProvider>(context, listen: false);

    bool isLocked = provider.isEditLocked(dt);

    if (isLocked) {
      bool isUnlocked = await PinUnlockDialog.show(
          context,
          provider,
          title: "Locked Entry",
          message: "Enter Master Password to modify Invoice $entryNo."
      );

      if (!mounted) return;
      if (!isUnlocked) return;
    }

    if (_selectedType == 'Sales') {
      appProvider.openSales(invoiceNo: entryNo);
    } else if (_selectedType == 'Purchase') {
      appProvider.openPurchase(entryNo: entryNo);
    } else if (_selectedType == 'Sale Return') {
      appProvider.openSalesReturn(entryNo: entryNo);
    } else if (_selectedType == 'Purchase Return') {
      appProvider.openPurchaseReturn(entryNo: entryNo);
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("Editing $_selectedType #$entryNo"),
      backgroundColor: Colors.orange,
      duration: const Duration(seconds: 2),
    ));
  }

  Widget _buildFooter(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade200))),
      child: Row(
        children: [
          Text("TOTAL EDITED ENTRIES: $count", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
          const Spacer(),
          const Text("Double click an entry to open in its respective editor", style: TextStyle(fontStyle: FontStyle.italic, fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _Hdr extends StatelessWidget {
  final String title; final double? width; final int? flex; final TextAlign textAlign;
  const _Hdr(this.title, {this.width, this.flex, this.textAlign = TextAlign.left});
  @override Widget build(BuildContext context) {
    Widget child = Container(
      width: width, padding: const EdgeInsets.symmetric(horizontal: 12), alignment: textAlign == TextAlign.left ? Alignment.centerLeft : (textAlign == TextAlign.right ? Alignment.centerRight : Alignment.center),
      child: Text(title, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
    );
    return flex != null ? Expanded(flex: flex!, child: child) : child;
  }
}

class _Cell extends StatelessWidget {
  final String text; final double? width; final int? flex; final TextAlign textAlign; final Color? color; final FontWeight fontWeight;
  const _Cell(this.text, {this.width, this.flex, this.textAlign = TextAlign.left, this.color, this.fontWeight = FontWeight.normal});
  @override Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget child = Container(
      width: width, padding: const EdgeInsets.symmetric(horizontal: 12), alignment: textAlign == TextAlign.left ? Alignment.centerLeft : (textAlign == TextAlign.right ? Alignment.centerRight : Alignment.center),
      child: Tooltip(
        message: text,
        waitDuration: const Duration(milliseconds: 300),
        child: Text(text, style: TextStyle(fontSize: 13, color: color ?? c.primaryText, fontWeight: fontWeight), overflow: TextOverflow.ellipsis),
      ),
    );
    return flex != null ? Expanded(flex: flex!, child: child) : child;
  }
}
