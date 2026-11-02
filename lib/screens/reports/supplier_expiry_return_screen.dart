import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../services/expiry_alert_service.dart';
import '../../database/db_helper.dart';

class SupplierExpiryReturnScreen extends StatefulWidget {
  const SupplierExpiryReturnScreen({super.key});

  @override
  State<SupplierExpiryReturnScreen> createState() => _SupplierExpiryReturnScreenState();
}

class _SupplierExpiryReturnScreenState extends State<SupplierExpiryReturnScreen> {
  List<ExpiryBatchItem> _expiringItems = [];
  final Set<String> _selectedKeys = {};
  String _selectedSupplier = "ALL";
  List<String> _suppliers = ["ALL"];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final items = await ExpiryAlertService.instance.getExpiringBatches(daysThreshold: 90);

    final supplierSet = <String>{"ALL"};
    for (var it in items) {
      if (it.supplierName.trim().isNotEmpty) {
        supplierSet.add(it.supplierName.trim());
      }
    }

    setState(() {
      _expiringItems = items;
      _suppliers = supplierSet.toList()..sort();
      _isLoading = false;
    });
  }

  List<ExpiryBatchItem> get _filteredItems {
    if (_selectedSupplier == "ALL") return _expiringItems;
    return _expiringItems.where((i) => i.supplierName.trim() == _selectedSupplier).toList();
  }

  void _toggleSelectAll(bool? checked) {
    setState(() {
      if (checked == true) {
        for (var item in _filteredItems) {
          _selectedKeys.add("${item.productId}|${item.batchNumber}");
        }
      } else {
        _selectedKeys.clear();
      }
    });
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _generateSupplierDebitNote() async {
    final selectedList = _filteredItems.where((i) => _selectedKeys.contains("${i.productId}|${i.batchNumber}")).toList();

    if (selectedList.isEmpty) {
      _showSnackBar("Please select at least one batch to generate a Debit Note.", isError: true);
      return;
    }

    final db = await DbHelper.instance.database;
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    final entryNo = "DN-${now.millisecondsSinceEpoch.toString().substring(5)}";
    final supplierName = selectedList.first.supplierName.isNotEmpty ? selectedList.first.supplierName : "Wholesaler";

    // Insert purchase return entry record
    await db.insert('purchase_return_entries', {
      'entry_no': entryNo,
      'date': dateStr,
      'supplier_name': supplierName,
      'total_amount': 0.0,
      'remarks': 'Near-Expiry Auto Supplier Debit Note',
    });

    double totalAmt = 0.0;
    for (var item in selectedList) {
      double rate = 0.0;
      final res = await db.query(
        'stock_batches',
        columns: ['purchase_rate'],
        where: 'product_id = ? AND batch_number = ?',
        whereArgs: [item.productId, item.batchNumber],
      );
      if (res.isNotEmpty) {
        rate = (res.first['purchase_rate'] as num?)?.toDouble() ?? 0.0;
      }

      double lineTotal = rate * item.currentStock;
      totalAmt += lineTotal;

      await db.insert('purchase_return_items', {
        'entry_no': entryNo,
        'product_id': item.productId,
        'product_name': item.productName,
        'batch_number': item.batchNumber,
        'qty': item.currentStock.toInt(),
        'rate': rate,
        'total': lineTotal,
      });
    }

    await db.update(
      'purchase_return_entries',
      {'total_amount': totalAmt},
      where: 'entry_no = ?',
      whereArgs: [entryNo],
    );

    _showSnackBar("Generated Supplier Debit Note #$entryNo for ₹${totalAmt.toStringAsFixed(2)}");

    _printDebitNotePdf(entryNo, supplierName, dateStr, selectedList, totalAmt);
    if (mounted) _fetchData();
  }

  Future<void> _printDebitNotePdf(String entryNo, String supplier, String date, List<ExpiryBatchItem> items, double total) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text("SUPPLIER EXPIRY DEBIT NOTE / CLAIM", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text("Debit Note Ref #: $entryNo | Date: $date", style: const pw.TextStyle(fontSize: 11)),
              pw.Text("Supplier: $supplier", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.Divider(),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                headers: ["Product Name", "Batch No", "Expiry", "Return Qty", "Est. Claim"],
                data: items.map((i) => [
                  i.productName,
                  i.batchNumber,
                  i.expiryDateStr,
                  "${i.currentStock.toInt()} Packs",
                  "Pending Claim",
                ]).toList(),
              ),
              pw.SizedBox(height: 16),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text("Total Estimated Claim: ₹${total.toStringAsFixed(2)}", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: "Debit_Note_$entryNo.pdf",
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1E2638) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Wholesaler Near-Expiry Return Register (60-90 Days)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.amber.shade900,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 14),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredItems.isEmpty
                      ? const Center(child: Text("No near-expiry items found for return.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)))
                      : _buildList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isAllSelected = _filteredItems.isNotEmpty && _filteredItems.every((i) => _selectedKeys.contains("${i.productId}|${i.batchNumber}"));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Checkbox(
            value: isAllSelected,
            onChanged: _toggleSelectAll,
          ),
          const Text("Select All", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(width: 16),
          const Text("Supplier Filter: ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          DropdownButton<String>(
            value: _selectedSupplier,
            underline: const SizedBox(),
            items: _suppliers.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedSupplier = val);
            },
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _generateSupplierDebitNote,
            icon: const Icon(Icons.note_add_rounded, size: 16),
            label: Text("GENERATE DEBIT NOTE (${_selectedKeys.length})"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade800, foregroundColor: Colors.white),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _fetchData,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text("REFRESH"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade900, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ListView.separated(
        itemCount: _filteredItems.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final item = _filteredItems[i];
          final key = "${item.productId}|${item.batchNumber}";
          final isChecked = _selectedKeys.contains(key);

          return CheckboxListTile(
            value: isChecked,
            onChanged: (val) {
              setState(() {
                if (val == true) {
                  _selectedKeys.add(key);
                } else {
                  _selectedKeys.remove(key);
                }
              });
            },
            dense: true,
            title: Text("${item.productName} (Batch: ${item.batchNumber})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            subtitle: Text("Supplier: ${item.supplierName} | Expiry: ${item.expiryDateStr}", style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
            secondary: Text("Stock: ${item.currentStock.toInt()} Packs", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber)),
          );
        },
      ),
    );
  }
}
