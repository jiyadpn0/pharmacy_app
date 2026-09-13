import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as ex;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../providers/pharmacy_provider.dart';
import '../../utils/theme_constants.dart';

class ReorderAssistantScreen extends StatefulWidget {
  const ReorderAssistantScreen({super.key});

  @override
  State<ReorderAssistantScreen> createState() => _ReorderAssistantScreenState();
}

class _ReorderAssistantScreenState extends State<ReorderAssistantScreen> {
  String _selectedSupplier = "ALL";
  String _selectedCategory = "ALL";
  final TextEditingController _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _reorderItems = [];
  final Map<String, TextEditingController> _qtyControllers = {};
  final Set<String> _selectedItemIds = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchReorderData();
  }

  @override
  void dispose() {
    for (var ctrl in _qtyControllers.values) {
      ctrl.dispose();
    }
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchReorderData() async {
    setState(() => _isLoading = true);
    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    try {
      final res = await provider.getReorderSuggestions(
        supplierFilter: _selectedSupplier,
        categoryFilter: _selectedCategory,
        searchQuery: _searchCtrl.text,
      );

      setState(() {
        _reorderItems = res;
        _selectedItemIds.clear();

        for (var r in res) {
          String id = r['id'].toString();
          _selectedItemIds.add(id);

          int suggested = (r['suggested_qty'] as num?)?.toInt() ?? 10;
          if (!_qtyControllers.containsKey(id)) {
            _qtyControllers[id] = TextEditingController(text: suggested.toString());
          } else {
            _qtyControllers[id]!.text = suggested.toString();
          }
        }
      });
    } catch (e) {
      debugPrint("Error fetching reorder suggestions: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _exportPoExcel() async {
    final activeItems = _reorderItems.where((r) => _selectedItemIds.contains(r['id'].toString())).toList();
    if (activeItems.isEmpty) return;

    try {
      var excel = ex.Excel.createExcel();
      ex.Sheet sheet = excel['Purchase Order'];
      excel.delete('Sheet1');

      sheet.appendRow([
        ex.TextCellValue('Supplier'),
        ex.TextCellValue('Medicine Name'),
        ex.TextCellValue('Category'),
        ex.TextCellValue('Current Stock'),
        ex.TextCellValue('Reorder Level'),
        ex.TextCellValue('Order Qty'),
        ex.TextCellValue('Est. Purchase Rate (₹)'),
        ex.TextCellValue('Est. Amount (₹)'),
      ]);

      for (var r in activeItems) {
        String id = r['id'].toString();
        int orderQty = int.tryParse(_qtyControllers[id]?.text ?? '0') ?? 0;
        double pRate = (r['purchase_rate'] as num?)?.toDouble() ?? 0.0;
        int pack = (r['packin'] as num?)?.toInt() ?? 1;
        if (pack <= 0) pack = 1;

        double lineEstimate = orderQty * pRate;

        sheet.appendRow([
          ex.TextCellValue(r['supplier']?.toString() ?? 'Unassigned'),
          ex.TextCellValue(r['product_name']?.toString() ?? ''),
          ex.TextCellValue(r['category']?.toString() ?? 'General'),
          ex.IntCellValue((r['current_stock'] as num?)?.toInt() ?? 0),
          ex.IntCellValue((r['reorder_level'] as num?)?.toInt() ?? 0),
          ex.IntCellValue(orderQty),
          ex.DoubleCellValue(pRate),
          ex.DoubleCellValue(lineEstimate),
        ]);
      }

      String? filePath = await FilePicker.saveFile(
        dialogTitle: 'Save Purchase Order Excel',
        fileName: 'PO_Reorder_${DateFormat('ddMMyyyy').format(DateTime.now())}.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (filePath != null) {
        final bytes = excel.encode();
        if (bytes != null) {
          final file = File(filePath);
          await file.writeAsBytes(bytes);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("PO Excel Exported Successfully!"), backgroundColor: Colors.green),
            );
          }
        }
      }
    } catch (e) {
      debugPrint("PO Excel Export Error: $e");
    }
  }

  void _printPoPdf() async {
    final activeItems = _reorderItems.where((r) => _selectedItemIds.contains(r['id'].toString())).toList();
    if (activeItems.isEmpty) return;

    final doc = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('PURCHASE REORDER ASSISTANT / PO', style: pw.TextStyle(font: boldFont, fontSize: 16)),
                    pw.Text('Supplier Reorder Indent Sheet', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700)),
                  ],
                ),
                pw.Text('Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}', style: pw.TextStyle(font: boldFont, fontSize: 10)),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            context: context,
            headers: ['Supplier', 'Medicine Name', 'Stock', 'Min', 'Order Qty', 'Est. Rate', 'Total (₹)'],
            headerStyle: pw.TextStyle(font: boldFont, fontSize: 9, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            cellStyle: pw.TextStyle(font: font, fontSize: 8),
            data: activeItems.map((r) {
              String id = r['id'].toString();
              int orderQty = int.tryParse(_qtyControllers[id]?.text ?? '0') ?? 0;
              double pRate = (r['purchase_rate'] as num?)?.toDouble() ?? 0.0;
              int pack = (r['packin'] as num?)?.toInt() ?? 1;
              if (pack <= 0) pack = 1;

              double lineEstimate = orderQty * pRate;

              return [
                r['supplier']?.toString() ?? 'Unassigned',
                r['product_name']?.toString() ?? '',
                (r['current_stock'] as num?)?.toInt().toString() ?? '0',
                (r['reorder_level'] as num?)?.toInt().toString() ?? '0',
                orderQty.toString(),
                "₹${pRate.toStringAsFixed(2)}",
                "₹${lineEstimate.toStringAsFixed(2)}",
              ];
            }).toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Purchase_Order_Reorder.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PharmacyProvider>(context);
    final suppliers = ["ALL", ...provider.suppliers];
    final categories = ["ALL", ...provider.categories];

    final activeItems = _reorderItems.where((r) => _selectedItemIds.contains(r['id'].toString())).toList();
    final double totalEstValue = activeItems.fold(0.0, (sum, r) {
      String id = r['id'].toString();
      int orderQty = int.tryParse(_qtyControllers[id]?.text ?? '0') ?? 0;
      double pRate = (r['purchase_rate'] as num?)?.toDouble() ?? 0.0;
      int pack = (r['packin'] as num?)?.toInt() ?? 1;
      if (pack <= 0) pack = 1;

      return sum + (orderQty * pRate);
    });

    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.shopping_cart_checkout_rounded, color: Colors.white),
            SizedBox(width: 10),
            Text("Reorder Assistant & Purchase PO Generator", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.picture_as_pdf_rounded), tooltip: "Export PO PDF", onPressed: _printPoPdf),
          IconButton(icon: const Icon(Icons.explicit_rounded), tooltip: "Export PO Excel", onPressed: _exportPoExcel),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          // FILTER CONTROLS BAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: Row(
              children: [
                // SUPPLIER FILTER
                const Text("Supplier:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300)),
                  child: Builder(
                    builder: (context) {
                      final uniqueSuppliers = suppliers.toSet().toList();
                      if (!uniqueSuppliers.contains("ALL")) uniqueSuppliers.insert(0, "ALL");
                      final safeSupplier = uniqueSuppliers.contains(_selectedSupplier) ? _selectedSupplier : "ALL";

                      return DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: safeSupplier,
                          isDense: true,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                          items: uniqueSuppliers.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedSupplier = val);
                              _fetchReorderData();
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),

                // CATEGORY FILTER
                const Text("Category:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300)),
                  child: Builder(
                    builder: (context) {
                      final uniqueCategories = categories.toSet().toList();
                      if (!uniqueCategories.contains("ALL")) uniqueCategories.insert(0, "ALL");
                      final safeCategory = uniqueCategories.contains(_selectedCategory) ? _selectedCategory : "ALL";

                      return DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: safeCategory,
                          isDense: true,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                          items: uniqueCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedCategory = val);
                              _fetchReorderData();
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),

                // SEARCH
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => _fetchReorderData(),
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: "Search medicine or generic name...",
                        prefixIcon: const Icon(Icons.search, size: 16),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                ElevatedButton.icon(
                  onPressed: _fetchReorderData,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text("SCAN STOCK"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade900, foregroundColor: Colors.white),
                ),
              ],
            ),
          ),

          // SUMMARY BAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                Text("Low Stock Medicines Found: ${_reorderItems.length}", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900, fontSize: 12)),
                const SizedBox(width: 20),
                Text("Items Selected for PO: ${_selectedItemIds.length}", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900, fontSize: 12)),
                const Spacer(),
                Text("Est. Purchase Order Value: ₹${totalEstValue.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.indigo, fontSize: 14)),
              ],
            ),
          ),

          // REORDER ITEMS LIST
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _reorderItems.isEmpty
                    ? const Center(child: Text("All medicine stock levels are optimal! No reorder items found.", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _reorderItems.length,
                        itemBuilder: (context, idx) {
                          final item = _reorderItems[idx];
                          String id = item['id'].toString();
                          bool isChecked = _selectedItemIds.contains(id);
                          int curStock = (item['current_stock'] as num?)?.toInt() ?? 0;
                          int reorderLvl = (item['reorder_level'] as num?)?.toInt() ?? 0;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: isChecked,
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == true) {
                                          _selectedItemIds.add(id);
                                        } else {
                                          _selectedItemIds.remove(id);
                                        }
                                      });
                                    },
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(item['product_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                        Text("Supplier: ${item['supplier']} | Cat: ${item['category']}", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                                    child: Text("Stock: $curStock / Min: $reorderLvl", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade900, fontSize: 11)),
                                  ),
                                  const SizedBox(width: 16),
                                  const Text("Order Qty:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                  const SizedBox(width: 6),
                                  SizedBox(
                                    width: 70,
                                    height: 32,
                                    child: TextField(
                                      controller: _qtyControllers[id],
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
                                      onChanged: (_) => setState(() {}),
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
    );
  }
}
