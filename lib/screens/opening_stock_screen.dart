import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as ex;

import '../providers/pharmacy_provider.dart';
import '../services/stock_service.dart';
import '../database/db_helper.dart';

class StagedOpeningStockItem {
  String productName;
  String batchNumber;
  String expiryDate;
  int packSize;
  int packsQty;
  int looseQty;
  double purchaseRate;
  double mrp;
  double saleRate;
  String rack;
  double gstPercent;
  String hsnCode;

  StagedOpeningStockItem({
    required this.productName,
    required this.batchNumber,
    required this.expiryDate,
    this.packSize = 10,
    this.packsQty = 0,
    this.looseQty = 0,
    this.purchaseRate = 0.0,
    this.mrp = 0.0,
    this.saleRate = 0.0,
    this.rack = "A1",
    this.gstPercent = 12.0,
    this.hsnCode = "3004",
  });

  int get totalLooseUnits => (packsQty * (packSize > 0 ? packSize : 1)) + looseQty;
  double get totalPurchaseValue => (totalLooseUnits / (packSize > 0 ? packSize : 1)) * purchaseRate;
  double get totalMrpValue => (totalLooseUnits / (packSize > 0 ? packSize : 1)) * mrp;
}

class OpeningStockScreen extends StatefulWidget {
  const OpeningStockScreen({super.key});

  @override
  State<OpeningStockScreen> createState() => _OpeningStockScreenState();
}

class _OpeningStockScreenState extends State<OpeningStockScreen> {
  final List<StagedOpeningStockItem> _stagedItems = [];
  bool _isCommitting = false;

  // Controllers for Entry Row
  final _prodNameCtrl = TextEditingController();
  final _batchCtrl = TextEditingController(text: "OPN-01");
  final _expiryCtrl = TextEditingController();
  final _packSizeCtrl = TextEditingController(text: "10");
  final _packsQtyCtrl = TextEditingController(text: "1");
  final _looseQtyCtrl = TextEditingController(text: "0");
  final _prCtrl = TextEditingController(text: "0.00");
  final _mrpCtrl = TextEditingController(text: "0.00");
  final _srCtrl = TextEditingController(text: "0.00");
  final _rackCtrl = TextEditingController(text: "A1");
  final _hsnCtrl = TextEditingController(text: "3004");
  final double _selectedGst = 12.0;

  // Focus Nodes for Keyboard-First Fast Entry
  final _nameFocus = FocusNode();
  final _batchFocus = FocusNode();
  final _expiryFocus = FocusNode();
  final _packSizeFocus = FocusNode();
  final _packsQtyFocus = FocusNode();
  final _looseQtyFocus = FocusNode();
  final _prFocus = FocusNode();
  final _mrpFocus = FocusNode();
  final _srFocus = FocusNode();
  final _rackFocus = FocusNode();

  @override
  void dispose() {
    _prodNameCtrl.dispose();
    _batchCtrl.dispose();
    _expiryCtrl.dispose();
    _packSizeCtrl.dispose();
    _packsQtyCtrl.dispose();
    _looseQtyCtrl.dispose();
    _prCtrl.dispose();
    _mrpCtrl.dispose();
    _srCtrl.dispose();
    _rackCtrl.dispose();
    _hsnCtrl.dispose();

    _nameFocus.dispose();
    _batchFocus.dispose();
    _expiryFocus.dispose();
    _packSizeFocus.dispose();
    _packsQtyFocus.dispose();
    _looseQtyFocus.dispose();
    _prFocus.dispose();
    _mrpFocus.dispose();
    _srFocus.dispose();
    _rackFocus.dispose();
    super.dispose();
  }

  void _addItemToStaging() {
    final name = _prodNameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter Product Name"), backgroundColor: Colors.orange),
      );
      _nameFocus.requestFocus();
      return;
    }

    final batch = _batchCtrl.text.trim().isNotEmpty ? _batchCtrl.text.trim().toUpperCase() : "OPN-01";
    String expiry = _expiryCtrl.text.trim();
    if (expiry.isEmpty) {
      expiry = "12/28"; // Default safe fallback
    }

    final packSize = int.tryParse(_packSizeCtrl.text.trim()) ?? 10;
    final packsQty = int.tryParse(_packsQtyCtrl.text.trim()) ?? 0;
    final looseQty = int.tryParse(_looseQtyCtrl.text.trim()) ?? 0;

    if (packsQty <= 0 && looseQty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Quantity must be greater than 0"), backgroundColor: Colors.orange),
      );
      _packsQtyFocus.requestFocus();
      return;
    }

    final pr = double.tryParse(_prCtrl.text.trim()) ?? 0.0;
    final mrp = double.tryParse(_mrpCtrl.text.trim()) ?? 0.0;
    final sr = double.tryParse(_srCtrl.text.trim()) ?? (mrp > 0 ? mrp : pr);
    final rack = _rackCtrl.text.trim().isNotEmpty ? _rackCtrl.text.trim() : "A1";
    final hsn = _hsnCtrl.text.trim().isNotEmpty ? _hsnCtrl.text.trim() : "3004";

    setState(() {
      _stagedItems.insert(
        0,
        StagedOpeningStockItem(
          productName: name,
          batchNumber: batch,
          expiryDate: expiry,
          packSize: packSize > 0 ? packSize : 1,
          packsQty: packsQty,
          looseQty: looseQty,
          purchaseRate: pr,
          mrp: mrp,
          saleRate: sr,
          rack: rack,
          gstPercent: _selectedGst,
          hsnCode: hsn,
        ),
      );

      // Reset form fields for next entry
      _prodNameCtrl.clear();
      _batchCtrl.text = "OPN-01";
      _expiryCtrl.clear();
      _packsQtyCtrl.text = "1";
      _looseQtyCtrl.text = "0";
      _prCtrl.text = "0.00";
      _mrpCtrl.text = "0.00";
      _srCtrl.text = "0.00";
    });

    _nameFocus.requestFocus();
  }

  Future<void> _commitAllStock() async {
    if (_stagedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No items staged. Add medicines to the table first."), backgroundColor: Colors.orange),
      );
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text("Commit Opening Stock", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          "Are you sure you want to commit ${_stagedItems.length} products to active inventory?\n\nThis will atomically register master products, create stock batches, and record ledger entries.",
          style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Cancel", style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
            child: const Text("Confirm & Commit"),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isCommitting = true);
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);
    final db = await DbHelper.instance.database;

    try {
      int successCount = 0;
      await db.transaction((txn) async {
        for (var item in _stagedItems) {
          // 1. Find or create in product_master
          String prodId = "";
          final existing = await txn.rawQuery(
            'SELECT id FROM product_master WHERE LOWER(TRIM(name)) = LOWER(TRIM(?)) LIMIT 1',
            [item.productName],
          );

          if (existing.isNotEmpty) {
            prodId = existing.first['id'].toString();
            // Update rates and details
            await txn.rawUpdate('''
              UPDATE product_master 
              SET mrp = ?, purchase_rate = ?, sale_rate = ?, rack_id = ?, packing = ?, gst_percent = ?, hsn_code = ?
              WHERE id = ?
            ''', [item.mrp, item.purchaseRate, item.saleRate, item.rack, item.packSize, item.gstPercent, item.hsnCode, prodId]);
          } else {
            prodId = "PROD_${DateTime.now().microsecondsSinceEpoch}_$successCount";
            await txn.insert('product_master', {
              'id': prodId,
              'name': item.productName,
              'mrp': item.mrp,
              'purchase_rate': item.purchaseRate,
              'sale_rate': item.saleRate,
              'rack_id': item.rack,
              'packing': item.packSize,
              'gst_percent': item.gstPercent,
              'hsn_code': item.hsnCode,
              'category_id': 'General',
              'is_active': 1,
            });
          }

          // 2. Process stock in using StockService
          await StockService.instance.processStockIn(
            productId: prodId,
            batchNumber: item.batchNumber,
            expiryDate: item.expiryDate,
            totalLooseQty: item.totalLooseUnits,
            voucherType: 'OPENING_STOCK',
            voucherNo: 'OPN_${DateTime.now().millisecondsSinceEpoch}',
            packing: item.packSize,
            purchaseRate: item.purchaseRate,
            landingCost: item.purchaseRate,
            mrp: item.mrp,
            saleRate: item.saleRate,
            gstPercent: item.gstPercent,
            rack: item.rack,
            remarks: 'Opening Stock Inward Entry',
            txn: txn,
          );

          // 3. Ensure stock_batches has immediate direct row for quick querying
          await txn.rawInsert('''
            INSERT INTO stock_batches (
              product_id, batch_number, expiry_date, current_stock, purchase_rate, landing_cost, mrp, sale_rate, packing, gst_percent, rack, supplier_name, is_active
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '', 1)
            ON CONFLICT(product_id, batch_number, expiry_date, purchase_rate, landing_cost, mrp, sale_rate, packing, supplier_name, gst_percent)
            DO UPDATE SET current_stock = current_stock + excluded.current_stock
          ''', [
            prodId,
            item.batchNumber,
            item.expiryDate,
            item.totalLooseUnits,
            item.purchaseRate,
            item.purchaseRate,
            item.mrp,
            item.saleRate,
            item.packSize,
            item.gstPercent,
            item.rack,
          ]);

          successCount++;
        }
      });

      await pharma.loadFromDatabase();

      if (mounted) {
        setState(() {
          _stagedItems.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Success! $successCount products committed to live inventory."),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error committing stock: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isCommitting = false);
    }
  }

  Future<void> _importSpreadsheet() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
      );

      if (result == null || result.files.single.path == null) return;
      final file = File(result.files.single.path!);
      final ext = result.files.single.extension?.toLowerCase() ?? '';

      List<List<dynamic>> rows = [];
      if (ext == 'csv') {
        final input = await file.readAsString();
        final lines = input.split(RegExp(r'\r?\n'));
        for (var line in lines) {
          if (line.trim().isEmpty) continue;
          rows.add(line.split(',').map((s) => s.replaceAll('"', '').trim()).toList());
        }
      } else if (ext == 'xlsx' || ext == 'xls') {
        final bytes = await file.readAsBytes();
        final excel = ex.Excel.decodeBytes(bytes);
        for (var table in excel.tables.keys) {
          rows = excel.tables[table]!.rows.map((row) => row.map((cell) => cell?.value?.toString() ?? '').toList()).toList();
          break; // Read first sheet
        }
      }

      if (rows.length <= 1) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("File contains no data or only headers"), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      // Expected columns: Name, Batch, Expiry, Pack, PacksQty, LooseQty, PurchaseRate, MRP, SaleRate, Rack
      int imported = 0;
      for (int i = 1; i < rows.length; i++) {
        final r = rows[i];
        if (r.isEmpty) continue;
        final name = r[0]?.toString().trim() ?? '';
        if (name.isEmpty) continue;

        final batch = r.length > 1 && r[1].toString().trim().isNotEmpty ? r[1].toString().trim().toUpperCase() : 'OPN-01';
        final expiry = r.length > 2 && r[2].toString().trim().isNotEmpty ? r[2].toString().trim() : '12/28';
        final pack = r.length > 3 ? (int.tryParse(r[3].toString().trim()) ?? 10) : 10;
        final packsQty = r.length > 4 ? (int.tryParse(r[4].toString().trim()) ?? 1) : 1;
        final looseQty = r.length > 5 ? (int.tryParse(r[5].toString().trim()) ?? 0) : 0;
        final pr = r.length > 6 ? (double.tryParse(r[6].toString().trim()) ?? 0.0) : 0.0;
        final mrp = r.length > 7 ? (double.tryParse(r[7].toString().trim()) ?? 0.0) : 0.0;
        final sr = r.length > 8 ? (double.tryParse(r[8].toString().trim()) ?? mrp) : mrp;
        final rack = r.length > 9 && r[9].toString().trim().isNotEmpty ? r[9].toString().trim() : 'A1';

        _stagedItems.add(StagedOpeningStockItem(
          productName: name,
          batchNumber: batch,
          expiryDate: expiry,
          packSize: pack,
          packsQty: packsQty,
          looseQty: looseQty,
          purchaseRate: pr,
          mrp: mrp,
          saleRate: sr,
          rack: rack,
        ));
        imported++;
      }

      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Successfully loaded $imported items from file!"), backgroundColor: const Color(0xFF10B981)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Import error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _downloadTemplate() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final String? selectedDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: "Select Folder to Save Opening Stock Template",
      );

      if (selectedDirectory == null || selectedDirectory.isEmpty) return;

      final filePath = "$selectedDirectory${Platform.pathSeparator}Opening_Stock_Sample_Template.csv";
      final file = File(filePath);

      const csvContent = """Product Name,Batch Number,Expiry (MM/YY),Pack Size,Packs Qty,Loose Qty,Purchase Rate,MRP,Sale Rate,Rack,GST %,HSN Code
PARACETAMOL 650MG,PCM-101,12/28,10,25,0,18.50,25.00,22.00,A1,12,3004
AMOXICILLIN 500 CAP,AMX-202,06/27,10,10,4,85.00,120.00,110.00,B3,12,3004
PAN-D CAPSULE,PND-303,09/28,15,15,0,140.00,195.00,185.00,C2,12,3004
CETIRIZINE 10MG TAB,CTZ-404,03/28,10,20,5,15.00,35.00,30.00,A2,12,3004
AZITHROMYCIN 500MG,AZM-505,11/27,3,30,0,72.00,115.00,105.00,C1,12,3004
""";

      await file.writeAsString(csvContent, flush: true);

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text("Template saved successfully to: $filePath"),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text("Error generating template: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pharma = Provider.of<PharmacyProvider>(context);
    final int totalItems = _stagedItems.length;
    final int totalUnits = _stagedItems.fold(0, (acc, it) => acc + it.totalLooseUnits);
    final double totalPurVal = _stagedItems.fold(0.0, (acc, it) => acc + it.totalPurchaseValue);
    final double totalMrpVal = _stagedItems.fold(0.0, (acc, it) => acc + it.totalMrpValue);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Column(
        children: [
          // 1. TOP STATS BAR & ACTIONS
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              border: Border(bottom: BorderSide(color: Color(0xFF334155), width: 1)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.inventory_2_rounded, color: Color(0xFF3B82F6), size: 20),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "OPENING STOCK ENTRY",
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    Text(
                      "Rapid Inward of Initial Shop Inventory & Stock Valuation",
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    ),
                  ],
                ),
                const Spacer(),
                // Summary Pills
                _buildSummaryPill("Items Staged", "$totalItems", Colors.cyanAccent),
                const SizedBox(width: 10),
                _buildSummaryPill("Total Loose Units", "$totalUnits", Colors.amberAccent),
                const SizedBox(width: 10),
                _buildSummaryPill("Purchase Valuation", "₹ ${totalPurVal.toStringAsFixed(2)}", Colors.lightGreenAccent),
                const SizedBox(width: 10),
                _buildSummaryPill("MRP Valuation", "₹ ${totalMrpVal.toStringAsFixed(2)}", Colors.white),
                const SizedBox(width: 10),
                _buildSummaryPill(
                  "Est. Margin",
                  "${totalMrpVal > 0 ? (((totalMrpVal - totalPurVal) / totalMrpVal) * 100).toStringAsFixed(1) : '0.0'}%",
                  Colors.purpleAccent,
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: _downloadTemplate,
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text("Sample Template", style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE2E8F0),
                    side: const BorderSide(color: Color(0xFF64748B)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _importSpreadsheet,
                  icon: const Icon(Icons.file_upload_outlined, size: 16),
                  label: const Text("Import Excel/CSV", style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF93C5FD),
                    side: const BorderSide(color: Color(0xFF3B82F6)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _isCommitting ? null : _commitAllStock,
                  icon: _isCommitting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded, size: 16),
                  label: Text(
                    _isCommitting ? "Committing..." : "Commit Stock to Inventory",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  ),
                ),
              ],
            ),
          ),

          // 2. FAST ENTRY ROW (KEYBOARD-FIRST)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(bottom: BorderSide(color: Color(0xFF334155), width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Product Name Autocomplete
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Medicine / Product Name *", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Autocomplete<String>(
                            optionsBuilder: (textEditingValue) {
                              if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
                              final q = textEditingValue.text.toLowerCase();
                              return pharma.productMaster
                                  .where((p) => p.name.toLowerCase().contains(q))
                                  .map((p) => p.name)
                                  .take(8);
                            },
                            onSelected: (selection) {
                              _prodNameCtrl.text = selection;
                              final match = pharma.getProductMasterByName(selection);
                              if (match != null) {
                                _packSizeCtrl.text = "${match.packSize}";
                                _mrpCtrl.text = match.mrp.toStringAsFixed(2);
                                _prCtrl.text = match.purchaseRate.toStringAsFixed(2);
                                _srCtrl.text = match.salePrice.toStringAsFixed(2);
                                if (match.rack.isNotEmpty) _rackCtrl.text = match.rack;
                                if (match.hsnCode.isNotEmpty) _hsnCtrl.text = match.hsnCode;
                              }
                              _batchFocus.requestFocus();
                            },
                            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                              _prodNameCtrl.text = controller.text;
                              controller.addListener(() {
                                _prodNameCtrl.text = controller.text;
                              });
                              return TextField(
                                controller: controller,
                                focusNode: focusNode,
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                decoration: _cellInputDecoration("Type Medicine Name..."),
                                onSubmitted: (_) => _batchFocus.requestFocus(),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Batch No
                    Expanded(
                      flex: 1,
                      child: _buildInputCol("Batch No", _batchCtrl, _batchFocus, nextFocus: _expiryFocus, hint: "OPN-01"),
                    ),
                    const SizedBox(width: 8),

                    // Expiry Date MM/YY
                    Expanded(
                      flex: 1,
                      child: _buildInputCol("Expiry (MM/YY)", _expiryCtrl, _expiryFocus, nextFocus: _packSizeFocus, hint: "12/28"),
                    ),
                    const SizedBox(width: 8),

                    // Pack Size
                    Expanded(
                      flex: 1,
                      child: _buildInputCol("Packing", _packSizeCtrl, _packSizeFocus, nextFocus: _packsQtyFocus, hint: "10", isNumber: true),
                    ),
                    const SizedBox(width: 8),

                    // Packs Qty
                    Expanded(
                      flex: 1,
                      child: _buildInputCol("Packs Qty", _packsQtyCtrl, _packsQtyFocus, nextFocus: _looseQtyFocus, hint: "1", isNumber: true),
                    ),
                    const SizedBox(width: 8),

                    // Loose Qty
                    Expanded(
                      flex: 1,
                      child: _buildInputCol("Loose Qty", _looseQtyCtrl, _looseQtyFocus, nextFocus: _prFocus, hint: "0", isNumber: true),
                    ),
                    const SizedBox(width: 8),

                    // Purchase Rate
                    Expanded(
                      flex: 1,
                      child: _buildInputCol("P.Rate", _prCtrl, _prFocus, nextFocus: _mrpFocus, hint: "0.00", isNumber: true),
                    ),
                    const SizedBox(width: 8),

                    // MRP
                    Expanded(
                      flex: 1,
                      child: _buildInputCol("MRP", _mrpCtrl, _mrpFocus, nextFocus: _srFocus, hint: "0.00", isNumber: true),
                    ),
                    const SizedBox(width: 8),

                    // Sale Rate
                    Expanded(
                      flex: 1,
                      child: _buildInputCol("S.Rate", _srCtrl, _srFocus, nextFocus: _rackFocus, hint: "0.00", isNumber: true),
                    ),
                    const SizedBox(width: 8),

                    // Rack
                    Expanded(
                      flex: 1,
                      child: _buildInputCol("Rack", _rackCtrl, _rackFocus, hint: "A1", onSubmitted: (_) => _addItemToStaging()),
                    ),
                    const SizedBox(width: 8),

                    // Add Button
                    ElevatedButton.icon(
                      onPressed: _addItemToStaging,
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text("Add", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 3. TABLE OF STAGED OPENING STOCK ITEMS
          Expanded(
            child: _stagedItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.post_add_rounded, size: 48, color: Colors.white.withValues(alpha: 0.2)),
                        const SizedBox(height: 12),
                        const Text(
                          "No opening stock items entered yet.",
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Type medicine names in the top row and press Enter, or click 'Import Excel/CSV' to upload your shop's stock list.",
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _stagedItems.length,
                    itemBuilder: (context, index) {
                      final item = _stagedItems[index];
                      final isEven = index % 2 == 0;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isEven ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
                          border: const Border(bottom: BorderSide(color: Color(0xFF334155), width: 0.5)),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 30,
                              child: Text(
                                "${index + 1}",
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName,
                                    style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    "Rack: ${item.rack} | HSN: ${item.hsnCode} | GST: ${item.gstPercent.toInt()}%",
                                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                item.batchNumber,
                                style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11.5, fontFamily: 'monospace'),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                item.expiryDate,
                                style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 11.5),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                "1 x ${item.packSize}",
                                style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                "${item.packsQty} packs + ${item.looseQty}",
                                style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                "${item.totalLooseUnits} units",
                                style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 11.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                "₹ ${item.purchaseRate.toStringAsFixed(2)}",
                                style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                "₹ ${item.mrp.toStringAsFixed(2)}",
                                style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                "₹ ${item.totalPurchaseValue.toStringAsFixed(2)}",
                                style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 11.5, fontWeight: FontWeight.w600),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                              onPressed: () => setState(() => _stagedItems.removeAt(index)),
                              tooltip: "Remove Item",
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9.5)),
          const SizedBox(height: 1),
          Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildInputCol(
    String label,
    TextEditingController ctrl,
    FocusNode focus, {
    FocusNode? nextFocus,
    String hint = "",
    bool isNumber = false,
    ValueChanged<String>? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          focusNode: focus,
          keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: _cellInputDecoration(hint),
          onSubmitted: (val) {
            if (nextFocus != null) {
              nextFocus.requestFocus();
            } else if (onSubmitted != null) {
              onSubmitted(val);
            }
          },
        ),
      ],
    );
  }

  InputDecoration _cellInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
      filled: true,
      fillColor: const Color(0xFF1E293B),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFF334155)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
      ),
    );
  }
}
