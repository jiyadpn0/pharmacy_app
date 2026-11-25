import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/app_provider.dart';
import '../../providers/pharmacy_provider.dart';
import '../../services/expiry_alert_service.dart';
import '../../services/stock_outbox_service.dart';
import '../../services/server_config_service.dart';
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
    final entryNo = "PRET-DN-${now.millisecondsSinceEpoch.toString().substring(5)}";
    final supplierName = selectedList.first.supplierName.isNotEmpty ? selectedList.first.supplierName : "Wholesaler";

    double totalAmt = 0.0;
    List<Map<String, dynamic>> itemsToInsert = [];

    for (var item in selectedList) {
      double rate = 0.0;
      double mrp = 0.0;
      int packing = 1;
      final res = await db.query(
        'stock_batches',
        columns: ['purchase_rate', 'mrp', 'packing'],
        where: 'product_id = ? AND batch_number = ?',
        whereArgs: [item.productId, item.batchNumber],
      );
      if (res.isNotEmpty) {
        rate = (res.first['purchase_rate'] as num?)?.toDouble() ?? 0.0;
        mrp = (res.first['mrp'] as num?)?.toDouble() ?? 0.0;
        packing = (res.first['packing'] as num?)?.toInt() ?? 1;
      }

      double lineTotal = rate * item.currentStock;
      totalAmt += lineTotal;

      itemsToInsert.add({
        'entry_no': entryNo,
        'product_name': item.productName,
        'batch': item.batchNumber,
        'expiry': item.expiryDateStr,
        'qty': item.currentStock.toInt(),
        'loose_qty': 0,
        'f_qty': 0,
        'unit': 'Strip',
        'packin': packing,
        'mrp': mrp,
        'p_rate': rate,
        's_rate': mrp,
        'disc_percent': 0.0,
        'gst_percent': 12.0,
        'total': lineTotal,
        'reason': 'Near Expiry Return',
        'supplier': supplierName,
        'productId': item.productId,
      });
    }

    await db.transaction((txn) async {
      await txn.insert('purchase_return_entries', {
        'entry_no': entryNo,
        'date': now.toIso8601String(),
        'supplier_name': supplierName,
        'original_purchase_no': '',
        'done_by': 'Admin',
        'grand_total': totalAmt,
        'gst_mode': 1,
        'financial_year': '',
      });

      for (var it in itemsToInsert) {
        final pId = it['productId'] as String;
        final batch = it['batch'] as String;
        final qty = it['qty'] as int;
        final pRate = (it['p_rate'] as num?)?.toDouble() ?? 0.0;
        final pMrp = (it['mrp'] as num?)?.toDouble() ?? 0.0;

        await txn.insert('purchase_return_items', {
          'entry_no': it['entry_no'],
          'product_name': it['product_name'],
          'batch': batch,
          'expiry': it['expiry'],
          'qty': qty,
          'loose_qty': 0,
          'f_qty': 0,
          'unit': it['unit'],
          'packin': it['packin'],
          'mrp': pMrp,
          'p_rate': pRate,
          's_rate': it['s_rate'],
          'disc_percent': it['disc_percent'],
          'gst_percent': it['gst_percent'],
          'total': it['total'],
          'reason': it['reason'],
          'supplier': it['supplier'],
        });

        // Deduct returned stock from stock_batches
        await txn.rawUpdate(
          'UPDATE stock_batches SET current_stock = MAX(0, current_stock - ?), is_synced = 0, updated_at = ? WHERE product_id = ? AND batch_number = ? COLLATE NOCASE',
          [qty, DateTime.now().toUtc().toIso8601String(), pId, batch],
        );

        // Record immutable audit movement in stock_ledger
        final idempKey = StockOutboxService.generateIdempotencyKey(
          branchId: ServerConfigService.instance.storeBranchId,
          terminalId: ServerConfigService.instance.terminalId,
          operationType: 'PURCHASE_RETURN',
          referenceNo: "$entryNo-$pId-$batch",
        );
        await DbHelper.instance.recordStockLedgerEntryInTxn(
          txn,
          entryType: 'PURCHASE_RETURN',
          referenceNo: entryNo,
          productId: pId,
          batchNumber: batch,
          quantityDelta: -qty,
          qtyIn: 0,
          qtyOut: qty,
          purchaseRate: pRate,
          mrp: pMrp,
          supplierName: supplierName,
          remarks: 'Near-Expiry Wholesaler Debit Note / Claim',
          branchId: ServerConfigService.instance.storeBranchId,
          terminalId: ServerConfigService.instance.terminalId,
          idempotencyKey: idempKey,
        );
      }

      // Reduce supplier payable balance
      if (supplierName.isNotEmpty && totalAmt > 0) {
        final updated = await txn.rawUpdate(
          'UPDATE suppliers SET current_balance = current_balance - ? WHERE name = ? COLLATE NOCASE',
          [totalAmt, supplierName],
        );
        if (updated == 0) {
          await txn.insert('suppliers', {
            'id': "SUP_${DateTime.now().millisecondsSinceEpoch}",
            'name': supplierName,
            'current_balance': -totalAmt,
            'phone': '', 'address': '', 'gst_in': '', 'dl_number': '',
          });
        }
      }
    });

    // Queue operation in durable outbox for server / multi-counter sync
    final outboxIdempKey = StockOutboxService.generateIdempotencyKey(
      branchId: ServerConfigService.instance.storeBranchId,
      terminalId: ServerConfigService.instance.terminalId,
      operationType: 'PURCHASE_RETURN',
      referenceNo: entryNo,
    );
    unawaited(StockOutboxService.instance.queueOperation(
      operationType: 'PURCHASE_RETURN',
      referenceNo: entryNo,
      payload: {
        'entry_no': entryNo,
        'date': now.toIso8601String(),
        'supplier_name': supplierName,
        'grand_total': totalAmt,
        'items': itemsToInsert,
        'branch_id': ServerConfigService.instance.storeBranchId,
        'terminal_id': ServerConfigService.instance.terminalId,
      },
      idempotencyKey: outboxIdempKey,
    ));

    // Refresh provider state if mounted
    if (mounted) {
      try {
        final pharmacyProv = Provider.of<PharmacyProvider>(context, listen: false);
        unawaited(pharmacyProv.syncInventoryFromDb());
        unawaited(pharmacyProv.fetchAccounts());
      } catch (_) {}
    }

    _showSnackBar("Generated Supplier Debit Note #$entryNo for ₹${totalAmt.toStringAsFixed(2)}");

    _printDebitNotePdf(entryNo, supplierName, dateStr, itemsToInsert, totalAmt);
    if (mounted) _fetchData();
  }

  void _openInPurchaseReturn() {
    final selectedList = _filteredItems.where((i) => _selectedKeys.contains("${i.productId}|${i.batchNumber}")).toList();
    if (selectedList.isEmpty) {
      _showSnackBar("Please select at least one batch to return.", isError: true);
      return;
    }
    final products = selectedList.map((item) => Product(
      id: item.productId,
      name: item.productName,
      batch: item.batchNumber,
      expiry: item.expiryDateStr,
      stock: item.currentStock.toInt(),
      supplier: item.supplierName,
    )).toList();
    Provider.of<AppProvider>(context, listen: false).openPurchaseReturn(initialExpiredItems: products);
  }

  Future<void> _printDebitNotePdf(
    String entryNo,
    String supplier,
    String date,
    List<Map<String, dynamic>> items,
    double total,
  ) async {
    final profile = Provider.of<PharmacyProvider>(context, listen: false).companyProfile;
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context ctx) {
          int totalPacks = 0;
          for (var it in items) {
            totalPacks += (it['qty'] as num?)?.toInt() ?? 0;
          }

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Store Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          profile.name.toUpperCase(),
                          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900),
                        ),
                        if (profile.tagline.isNotEmpty)
                          pw.Text(profile.tagline, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                        pw.SizedBox(height: 2),
                        pw.Text(profile.address, style: const pw.TextStyle(fontSize: 8)),
                        pw.Text("Phone: ${profile.phone}  |  Email: ${profile.email}", style: const pw.TextStyle(fontSize: 8)),
                        pw.Text("GSTIN: ${profile.gstIn}  |  D.L. No: ${profile.dlNumber}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.teal900, width: 1.5),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text("DEBIT NOTE / CLAIM", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900)),
                        pw.Text("Ref: $entryNo", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                        pw.Text("Date: $date", style: const pw.TextStyle(fontSize: 8)),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 1, color: PdfColors.teal900),
              pw.SizedBox(height: 6),

              // Wholesaler Metadata Bar
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Supplier / Wholesaler: $supplier", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.Text("Reason: Near-Expiry / Expired Stock Credit Claim", style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800)),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),

              // Itemized Table
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.teal900),
                cellStyle: const pw.TextStyle(fontSize: 8),
                cellAlignment: pw.Alignment.centerLeft,
                headers: ["#", "Product Description", "Batch No", "Expiry", "Return Qty", "Pur. Rate", "MRP", "Line Claim (Rs.)"],
                columnWidths: {
                  0: const pw.FixedColumnWidth(20),
                  1: const pw.FlexColumnWidth(3),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(1.2),
                  4: const pw.FlexColumnWidth(1.2),
                  5: const pw.FlexColumnWidth(1.2),
                  6: const pw.FlexColumnWidth(1.2),
                  7: const pw.FlexColumnWidth(1.5),
                },
                data: List.generate(items.length, (idx) {
                  final it = items[idx];
                  final qty = (it['qty'] as num?)?.toInt() ?? 0;
                  final pRate = (it['p_rate'] as num?)?.toDouble() ?? 0.0;
                  final mrp = (it['mrp'] as num?)?.toDouble() ?? 0.0;
                  final lineTot = (it['total'] as num?)?.toDouble() ?? 0.0;
                  return [
                    "${idx + 1}",
                    it['product_name']?.toString() ?? '',
                    it['batch']?.toString() ?? '',
                    it['expiry']?.toString() ?? '',
                    "$qty Packs",
                    pRate.toStringAsFixed(2),
                    mrp.toStringAsFixed(2),
                    lineTot.toStringAsFixed(2),
                  ];
                }),
              ),
              pw.SizedBox(height: 10),

              // Summary Box
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Total Returned Items: ${items.length} ($totalPacks Packs)", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.teal50,
                      border: pw.Border.all(color: PdfColors.teal800, width: 1),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Text(
                      "TOTAL ESTIMATED CLAIM: Rs. ${total.toStringAsFixed(2)}",
                      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 14),

              // Statutory Certification
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                ),
                child: pw.Text(
                  "Statutory Declaration: The above pharmaceutical stocks have been segregated and returned due to near-expiry/expiry under Drugs & Cosmetics Rules and GST Table 12 compliance. Please credit our account / adjust against outstanding ledger.",
                  style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
                ),
              ),
              pw.Spacer(),

              // Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(width: 120, height: 0.5, color: PdfColors.black),
                      pw.SizedBox(height: 2),
                      pw.Text("Prepared By (Pharmacist)", style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(width: 130, height: 0.5, color: PdfColors.black),
                      pw.SizedBox(height: 2),
                      pw.Text("For ${profile.name}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      pw.Text("Authorized Signatory", style: const pw.TextStyle(fontSize: 7)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(width: 130, height: 0.5, color: PdfColors.black),
                      pw.SizedBox(height: 2),
                      pw.Text("Wholesaler Verification", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      pw.Text("Stamp & Receiver Signature", style: const pw.TextStyle(fontSize: 7)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.Text("--- SYSTEM GENERATED SUPPLIER DEBIT NOTE / CLAIM STATEMENT ---", style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
              ),
            ],
          );
        },
      ),
    );

    Printer? targetPrinter;
    try {
      final prefs = await SharedPreferences.getInstance();
      final preferredPrinterName = prefs.getString('preferred_printer_name');
      if (preferredPrinterName != null && preferredPrinterName.isNotEmpty) {
        final printers = await Printing.listPrinters();
        targetPrinter = printers.firstWhere(
          (p) => p.name.toLowerCase() == preferredPrinterName.toLowerCase(),
          orElse: () => printers.firstWhere((p) => p.isDefault, orElse: () => printers.first),
        );
      }
    } catch (_) {}

    if (targetPrinter != null) {
      await Printing.directPrintPdf(
        printer: targetPrinter,
        onLayout: (format) async => pdf.save(),
        name: "Debit_Note_$entryNo.pdf",
      );
    } else {
      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: "Debit_Note_$entryNo.pdf",
      );
    }
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
            onPressed: _openInPurchaseReturn,
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text("OPEN RETURN VOUCHER"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade800, foregroundColor: Colors.white),
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
