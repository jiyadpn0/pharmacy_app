import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/pharmacy_provider.dart';
import '../services/server_config_service.dart';

import '../utils/app_dialogs.dart';
import '../widgets/pin_unlock_dialog.dart';
import '../utils/app_formatters.dart';
import '../utils/search_debouncer.dart';
import '../utils/theme_constants.dart';
import '../utils/report_pdf_generator.dart';
import '../utils/printer_service.dart';
import '../utils/unsaved_handler.dart';
import '../widgets/erp_grid_text_field.dart';
import '../utils/tax_calculator.dart';

class DamageEntryScreen extends StatefulWidget {
  final String? initialReason;
  const DamageEntryScreen({super.key, this.initialReason});

  @override
  State<DamageEntryScreen> createState() => _DamageEntryScreenState();
}

class _StockRow {
  final FocusNode nameFocus = FocusNode();
  final FocusNode qtyFocus = FocusNode();
  final FocusNode expiryFocus = FocusNode();
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController qtyCtrl = TextEditingController();
  final TextEditingController expiryCtrl = ExpiryTextEditingController();
  Product? product;

  void dispose() {
    nameFocus.dispose();
    qtyFocus.dispose();
    expiryFocus.dispose();
    nameCtrl.dispose();
    qtyCtrl.dispose();
    expiryCtrl.dispose();
  }
}

class _DamageEntryScreenState extends State<DamageEntryScreen> implements UnsavedHandler {
  String _originalDoneBy = "";
  String _originalReason = "";
  List<Map<String, dynamic>> _originalItemSnapshots = [];

  bool _hasMeaningfulEdits() {
    if (!_isExistingEntry) return false;

    if (_doneByCtrl.text.trim().toUpperCase() != _originalDoneBy.toUpperCase()) return true;
    if (_reasonCtrl.text.trim().toUpperCase() != _originalReason.toUpperCase()) return true;

    final validRows = _rows
        .where((r) => r.product != null && (int.tryParse(r.qtyCtrl.text.trim()) ?? 0) > 0)
        .toList();

    if (validRows.length != _originalItemSnapshots.length) return true;

    for (int i = 0; i < validRows.length; i++) {
      final r = validRows[i];
      final snap = _originalItemSnapshots[i];

      final pName = r.product!.name.trim().toUpperCase();
      final batch = r.product!.batch.trim().toUpperCase();
      final qty = int.tryParse(r.qtyCtrl.text.trim()) ?? 0;

      if (pName != snap['productName']) return true;
      if (batch != snap['batch']) return true;
      if (qty != snap['qty']) return true;
    }

    return false;
  }

  @override
  bool hasUnsavedChanges() {
    int grandTotalPaise = 0;
    for (var row in _rows) {
      grandTotalPaise += _calculateTotalPaise(row);
    }
    if (grandTotalPaise <= 0) return false;

    if (_isExistingEntry) {
      return _hasMeaningfulEdits();
    } else {
      return _hasValidItems();
    }
  }

  @override
  void showDifferences() {
    _promptDiscardChanges();
  }
  final TextEditingController _entryNoCtrl = TextEditingController();
  final TextEditingController _dateCtrl = TextEditingController();
  final TextEditingController _doneByCtrl = TextEditingController(text: "ADMIN");
  final TextEditingController _reasonCtrl = TextEditingController();
  bool _isDeleted = false;

  final Map<int, String> _columnFilters = {};
  final List<_StockRow> _rows = [];
  final ScrollController _scrollController = ScrollController();

  bool _isExistingEntry = false;
  bool _isLoading = false;
  bool _isDirty = false;
  bool _isSaving = false;

  // ---> NEW: DIRTY STATE INTERCEPTOR <---
  void _markDirty() {
    if (_isLoading) return;
    if (_isExistingEntry && !_isDirty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _isDirty = true);
      });
    }
  }

  bool _hasValidItems() {
    if (_isExistingEntry) return _hasMeaningfulEdits();

    for (var row in _rows) {
      if (row.product != null) {
        final qty = (int.tryParse(row.qtyCtrl.text.trim()) ?? 0).abs();
        if (qty > 0) return true;
      }
    }
    return false;
  }

  Future<bool?> _promptDiscardChanges() async {
    if (!hasUnsavedChanges()) return true;

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 10),
            Text("Unsaved Edits Detected", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          "You have made changes to this saved damage entry.\nIf you leave now, your edits will be lost.\n\nDo you want to discard your changes?",
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false), // Stay
            child: const Text("STAY ON THIS PAGE", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true), // Discard
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("DISCARD EDITS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    UnsavedChangesRegistry.register("DAMAGE ENTRY", this);
    _reasonCtrl.text = widget.initialReason?.toUpperCase() ?? "DAMAGED";
    _dateCtrl.text = DateFormat('dd/MM/yyyy').format(DateTime.now());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resetPage();
    });
  }

  void _addNewRow() {
    setState(() {
      final row = _StockRow();
      _rows.add(row);
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) row.nameFocus.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    UnsavedChangesRegistry.unregister("DAMAGE ENTRY");
    _entryNoCtrl.dispose();
    _dateCtrl.dispose();
    _doneByCtrl.dispose();
    _reasonCtrl.dispose();
    for (var row in _rows) {
      row.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _resetPage() async {
    // ---> THE FIX: Protect against losing unsaved edits <---
    if (_isExistingEntry && _isDirty) {
      bool? discard = await _promptDiscardChanges();
      if (discard != true) return; // User chose to stay
    }
    if (!mounted) return;

    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final nextNo = await p.getNextAdjustmentNo();
    if (mounted) {
      final oldRows = List<_StockRow>.from(_rows);
      setState(() {
        _isExistingEntry = false;
        _isDeleted = false;
        _isDirty = false;
        _entryNoCtrl.text = nextNo;
        _dateCtrl.text = DateFormat('dd/MM/yyyy').format(DateTime.now());
        _rows.clear();
        _addNewRow();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (var row in oldRows) {
          row.dispose();
        }
      });
    }
  }

  // NAVIGATION LOGIC (Like Sales Screen)
  void _navigateEntry(String dir, {String? searchNo}) async {
    // ---> THE FIX: Protect against losing unsaved edits <---
    if (_isExistingEntry && _isDirty) {
      bool? discard = await _promptDiscardChanges();
      if (discard != true) return; // User chose to stay
    }
    if (!mounted) return;

    final p = Provider.of<PharmacyProvider>(context, listen: false);
    setState(() => _isLoading = true);

    try {
      String targetNo = searchNo ?? _entryNoCtrl.text;
      final nextNo = await p.getNextAdjustmentNo();
      if (targetNo == nextNo && (dir == 'prev' || dir == 'last')) {
        dir = 'last';
      }

      final data = await p.navigateInvoice(targetNo, dir, isAdjustment: true);

      if (data != null) {
        _loadDamageData(data['entry_no'].toString(), data: data);
      } else {
        if (dir == 'next') {
          _isExistingEntry ? await _resetPage() : _showDialog("Navigation", "NO MORE RECORDS TO SHOW");
        } else if (dir == 'prev') {
          _showDialog("Navigation", "FIRST RECORD REACHED");
        } else if (dir == 'find') {
          _showDialog("Not Found", "Entry $targetNo not found.");
          _entryNoCtrl.text = _isExistingEntry ? _entryNoCtrl.text : await p.getNextAdjustmentNo();
        }
      }
    } catch (e) {
      debugPrint("Navigation Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _loadDamageData(String entryNo, {Map<String, dynamic>? data}) async {
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    setState(() => _isLoading = true);

    try {
      final dbData = data ?? await p.navigateInvoice(entryNo, 'find', isAdjustment: true);
      final adj = p.adjustments.cast<StockAdjustment?>().firstWhere(
        (a) => a?.entryNo == entryNo,
        orElse: () => null,
      );

      bool isDel = false;
      if (dbData != null) {
        isDel = (dbData['is_deleted'] == 1 || dbData['is_deleted'] == true || dbData['is_deleted'] == '1');
      } else if (adj != null) {
        isDel = adj.isDeleted;
      }

      setState(() {
        _isExistingEntry = true;
        _isDeleted = isDel;
        _isDirty = false;
        _entryNoCtrl.text = dbData != null ? (dbData['entry_no']?.toString() ?? entryNo) : (adj?.entryNo ?? entryNo);
        if (dbData != null) {
          _dateCtrl.text = DateFormat('dd/MM/yyyy').format(DateTime.tryParse(dbData['date']?.toString() ?? '') ?? DateTime.now());
          _doneByCtrl.text = dbData['done_by']?.toString() ?? '';
          _reasonCtrl.text = dbData['reason']?.toString() ?? '';
        } else if (adj != null) {
          _dateCtrl.text = DateFormat('dd/MM/yyyy').format(adj.date);
          _doneByCtrl.text = adj.doneBy;
          _reasonCtrl.text = adj.reason;
        }

        final oldRows = List<_StockRow>.from(_rows);
        _rows.clear();

        if (adj != null && adj.items.isNotEmpty) {
          for (var item in adj.items) {
            final row = _StockRow();
            row.product = item.product;
            row.nameCtrl.text = item.product.name;
            row.qtyCtrl.text = item.qty.abs().toString();
            row.expiryCtrl.text = item.product.expiry;
            _rows.add(row);
          }
        }
        if (!_isDeleted) {
          _addNewRow(); // Add empty row at bottom
        }

        _originalDoneBy = _doneByCtrl.text.trim();
        _originalReason = _reasonCtrl.text.trim();
        _originalItemSnapshots = _rows
            .where((r) => r.product != null && (int.tryParse(r.qtyCtrl.text.trim()) ?? 0) > 0)
            .map((r) => {
                  'productName': r.product!.name.trim().toUpperCase(),
                  'batch': r.product!.batch.trim().toUpperCase(),
                  'qty': int.tryParse(r.qtyCtrl.text.trim()) ?? 0,
                })
            .toList();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          for (var row in oldRows) {
            row.dispose();
          }
        });
      });
    } catch (e) {
      _showDialog("Error", "Could not load data: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }



  void _save({bool isEdit = false}) async {
    if (_isSaving) return;
    _isSaving = true;
    if (mounted) setState(() {});

    try {
      final provider = Provider.of<PharmacyProvider>(context, listen: false);
      List<StockAdjustmentItem> items = [];
      int grandTotalPaise = 0;

      // Aggregate row quantities by Product ID + Batch across all table rows
      final Map<String, int> aggregateQtyByBatch = {};
      final Map<String, Product> productByBatch = {};

      for (var row in _rows) {
        if (row.product != null && row.qtyCtrl.text.isNotEmpty) {
          int rawQty = int.tryParse(row.qtyCtrl.text.trim()) ?? 0;
          int qty = rawQty.abs();
          if (qty == 0) continue;

          // Strict Expiry Validator Check
          String exp = row.expiryCtrl.text.trim();
          if (exp.isNotEmpty && exp != "--/--") {
            final parts = exp.split(RegExp(r'[-/]'));
            if (parts.length == 2) {
              int? month = int.tryParse(parts[0]);
              int? year = int.tryParse(parts[1]);
              if (month == null || month < 1 || month > 12 || year == null) {
                _showDialog("Invalid Expiry", "Invalid expiry month ($exp) for '${row.product!.name}'. Must be between 01 and 12.");
                row.expiryFocus.requestFocus();
                return;
              }
            } else {
              _showDialog("Invalid Expiry", "Expiry must follow MM/YY format for '${row.product!.name}'.");
              row.expiryFocus.requestFocus();
              return;
            }
          }

          final key = "${row.product!.id}|${row.product!.batch.toLowerCase().trim()}";
          aggregateQtyByBatch[key] = (aggregateQtyByBatch[key] ?? 0) + qty;
          productByBatch[key] = row.product!;
        }
      }

      // Validate aggregated shelf stock limits across all multi-row duplicates
      for (var entry in aggregateQtyByBatch.entries) {
        final prod = productByBatch[entry.key]!;
        int totalQty = entry.value;
        int availableShelfStock = prod.stock;
        if (totalQty > availableShelfStock) {
          _showDialog(
            "Insufficient Stock",
            "Cannot write off $totalQty total units of '${prod.name}' (Batch: '${prod.batch}'). Only $availableShelfStock units available on shelf."
          );
          return;
        }
      }

      // Build adjustment items using exact Integer Paise calculations
      for (var row in _rows) {
        if (row.product != null && row.qtyCtrl.text.isNotEmpty) {
          int rawQty = int.tryParse(row.qtyCtrl.text.trim()) ?? 0;
          int qty = rawQty.abs();
          if (qty == 0) continue;

          int unitCostPaise = _getLooseUnitCostPaise(row.product);
          int totalPaise = unitCostPaise * qty;

          items.add(StockAdjustmentItem(
            product: row.product!,
            qty: -qty, // Strictly negative for stock deduction
            purchaseRate: row.product!.purchaseRate,
            total: totalPaise / 100.0,
          ));
          grandTotalPaise += totalPaise;
        }
      }

      if (items.isEmpty) {
        _showDialog("Empty", "Please add at least one item to save.");
        return;
      }

      if (isEdit || _isExistingEntry) {
        if (mounted) {
          final confirmed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              title: const Row(
                children: [
                  Icon(Icons.save_rounded, color: Colors.blue, size: 28),
                  SizedBox(width: 10),
                  Text("Update Damage Entry", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: Text(
                "Are you sure you want to update Entry #${_entryNoCtrl.text}?\nAll modifications will be saved to your stock.",
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  child: const Text("Update Entry", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
          if (!mounted) return;
          if (confirmed != true) return;
        }
      }

      // 1. SECURITY CHECK: PIN for Damage Entries
      if (provider.securityToggles['require_pin_write_off'] == true) {
        if (!context.mounted) return;
        bool isUnlocked = await PinUnlockDialog.show(
            context,
            provider,
            title: "Auth Required",
            message: "Enter Master Password to authorize this stock write-off."
        );
        if (!mounted) return;
        if (!isUnlocked) return;
      }

      if (ServerConfigService.instance.isPureCloud && !ServerConfigService.instance.isConnected) {
        if (!mounted) return;
        AppDialogs.showFastDialog(
          context: context,
          title: "Pure Cloud Live Disconnected",
          content: "Cannot save damage entry while disconnected from Supabase Cloud Server.\n\nPlease check your internet connection.",
        );
        return;
      }

      String targetEntryNo = isEdit ? _entryNoCtrl.text : "";
      if (!isEdit) {
        final rawNo = cleanEntryNo(_entryNoCtrl.text);
        final resolvedNo = await provider.resolveGuaranteedNextEntryNo('stock_adjustments', rawNo);
        if (resolvedNo != rawNo && rawNo.isNotEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Entry #$rawNo already taken. Automatically saved as Entry #$resolvedNo"),
                backgroundColor: Colors.blueAccent,
                duration: const Duration(seconds: 4),
              ),
            );
            _entryNoCtrl.text = resolvedNo;
          }
        }
        targetEntryNo = resolvedNo;
      }

      final adj = StockAdjustment(
        entryNo: targetEntryNo,
        date: DateFormat('dd/MM/yyyy').parse(_dateCtrl.text),
        doneBy: _doneByCtrl.text,
        reason: _reasonCtrl.text,
        items: items,
        grandTotal: grandTotalPaise / 100.0,
      );

      setState(() => _isLoading = true);
      try {
        final assignedNo = await provider.saveStockAdjustment(adj, isEdit: isEdit);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              backgroundColor: Colors.green,
              content: Text(isEdit ? "Entry #$assignedNo Updated!" : "Damage Entry #$assignedNo Saved!")));
          _isDirty = false;
          await _resetPage(); // Jump to new page after saving
        }
      } catch (e) {
        if (mounted) {
          _showDialog("Error", "Failed to save: $e");
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isLoading = false;
        });
      } else {
        _isSaving = false;
        _isLoading = false;
      }
    }
  }

  void _showDialog(String title, String content) {
    AppDialogs.showFastDialog(context: context, title: title, content: content);
  }

  int _lastFocusedRowIndex = -1;

  int get _focusedRowIndex {
    for (int i = 0; i < _rows.length; i++) {
      if (_rows[i].nameFocus.hasFocus ||
          _rows[i].qtyFocus.hasFocus ||
          _rows[i].expiryFocus.hasFocus) {
        _lastFocusedRowIndex = i;
        return i;
      }
    }
    if (_lastFocusedRowIndex >= 0 && _lastFocusedRowIndex < _rows.length) {
      return _lastFocusedRowIndex;
    }
    return -1;
  }

  void _handleCtrlDelete() {
    int idx = _focusedRowIndex;
    if (idx >= 0 && idx < _rows.length) {
      _deleteRow(idx);
    }
  }

  void _deleteRow(int index) {
    if (index < 0 || index >= _rows.length) return;

    _markDirty();
    final removed = _rows[index];
    setState(() {
      _rows.removeAt(index);

      if (_rows.isEmpty) {
        _addNewRow();
      } else {
        int nextIndex = index >= _rows.length ? _rows.length - 1 : index;
        _lastFocusedRowIndex = nextIndex;
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted && nextIndex >= 0 && nextIndex < _rows.length && _rows[nextIndex].nameFocus.canRequestFocus) {
            _rows[nextIndex].nameFocus.requestFocus();
          }
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      removed.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final isCtrl = HardwareKeyboard.instance.isControlPressed;
          if (event.logicalKey == LogicalKeyboardKey.f2) {
            _save(isEdit: false);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.f3) {
            _resetPage();
            return KeyEventResult.handled;
          } else if (isCtrl && event.logicalKey == LogicalKeyboardKey.delete) {
            _handleCtrlDelete();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
          backgroundColor: AppColors.of(context).background,
          body: Stack(
          children: [
            Column(
              children: [
                _buildToolbar(),
                _buildHeaderFields(),
                Expanded(child: _buildTable()),
                _buildFooter(),
              ],
            ),
            if (_isLoading)
              Container(color: Colors.black12, child: const Center(child: CircularProgressIndicator())),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    bool canSave = !_isExistingEntry && !_isDeleted;
    bool canEdit = _isExistingEntry && !_isDeleted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isDeleted)
          Container(
            width: double.infinity,
            color: Colors.red.shade900,
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            child: Text(
              "🗑️ DELETED ENTRY: Damage Entry #${_entryNoCtrl.text} is marked as DELETED and is Read-Only.",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Row(
            children: [
              const Text("DAMAGE ENTRY", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black87)),
              const Spacer(),
              _actionBtn(Icons.add_circle, "New (F3)", Colors.blue, onTap: _resetPage),
              _actionBtn(
                  Icons.check_circle,
                  "Save (F2)",
                  canSave ? Colors.green : Colors.grey.shade400,
                  textColor: canSave ? Colors.black87 : Colors.grey.shade400,
                  onTap: canSave ? () => _save(isEdit: false) : () {
                    if (_isDeleted) {
                      _showDialog("Read Only", "This entry is deleted and cannot be edited.");
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Add at least one damage/expiry item to save."), duration: Duration(seconds: 2)),
                      );
                    }
                  }
              ),
              _actionBtn(
                  Icons.edit,
                  "Edit",
                  canEdit ? Colors.orange : Colors.grey.shade400,
                  textColor: canEdit ? Colors.black87 : Colors.grey.shade400,
                  onTap: canEdit ? () => _save(isEdit: true) : () {
                    if (_isDeleted) {
                      _showDialog("Read Only", "This entry is deleted and cannot be edited.");
                    } else {
                      _showDialog("Locked", "This is a new entry. Click 'Save' instead.");
                    }
                  }
              ),
              _actionBtn(Icons.print, "Print", Colors.blueGrey, onTap: _printDamageReport),
            ],
          ),
        ),
      ],
    );
  }

  void _printDamageReport() async {
    final validRows = _rows.where((r) => r.product != null && r.qtyCtrl.text.trim().isNotEmpty).toList();
    if (validRows.isEmpty) {
      _showDialog("Print", "No items to print in damage entry voucher.");
      return;
    }
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final company = provider.companyProfile;
    List<List<String>> tableData = [];
    int index = 1;
    for (var r in validRows) {
      final p = r.product!;
      int qty = int.tryParse(r.qtyCtrl.text.trim()) ?? 0;
      int unitCostPaise = _getLooseUnitCostPaise(p);
      int lossValuePaise = unitCostPaise * qty;
      tableData.add([
        "$index",
        p.name,
        p.batch,
        r.expiryCtrl.text.trim().isNotEmpty ? r.expiryCtrl.text.trim() : p.expiry,
        "$qty",
        TaxCalculator.toRupeesString(unitCostPaise),
        TaxCalculator.toRupeesString(lossValuePaise),
      ]);
      index++;
    }

    try {
      final doc = await ReportPdfGenerator.buildReportPdf(
        title: "DAMAGE ENTRY VOUCHER #${_entryNoCtrl.text}",
        subtitle: "Entry Date: ${_dateCtrl.text} | Total Items: ${validRows.length}",
        company: company,
        headers: ["#", "Product Name", "Batch", "Expiry", "Qty", "Unit Cost", "Loss Value"],
        data: tableData,
      );
      if (mounted) {
        PrinterService.showProfessionalPreview(
          context: context,
          doc: doc,
          title: "Damage Entry Voucher Preview",
        );
      }
    } catch (e) {
      if (mounted) _showDialog("Print Error", e.toString());
    }
  }

  Widget _actionBtn(IconData icon, String label, Color color, {Color? textColor, VoidCallback? onTap}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor ?? Colors.black87)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: BorderSide(color: Colors.grey.shade300),
        backgroundColor: Colors.white,
      ),
    ),
  );

  Widget _buildHeaderFields() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFFE8EAF6),
      child: Row(
        children: [
          const Text("Entry No:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Container(
            width: 120, height: 28,
            decoration: BoxDecoration(border: Border.all(color: Colors.blue.shade200), borderRadius: BorderRadius.circular(4), color: Colors.white),
            child: Row(
              children: [
                InkWell(onTap: () => _navigateEntry('prev'), child: Container(width: 24, alignment: Alignment.center, color: Colors.grey.shade200, child: const Icon(Icons.chevron_left, size: 16))),
                Expanded(
                  child: TextField(
                    controller: _entryNoCtrl,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                    onSubmitted: (v) => _navigateEntry('find', searchNo: v),
                  ),
                ),
                InkWell(onTap: () => _navigateEntry('next'), child: Container(width: 24, alignment: Alignment.center, color: Colors.grey.shade200, child: const Icon(Icons.chevron_right, size: 16))),
              ],
            ),
          ),
          const SizedBox(width: 20),
          _field("Date:", _dateCtrl, width: 100),
          const SizedBox(width: 20),
          _field("Done By:", _doneByCtrl, width: 120),
          const Spacer(),
          _field("Reason:", _reasonCtrl, width: 250),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {double? width}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        SizedBox(
          width: width,
          height: 28,
          child: TextField(
            controller: ctrl,
            style: const TextStyle(fontSize: 12, color: Colors.black),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(),
              fillColor: Colors.white,
              filled: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTable() {
    final filteredIndices = <int>[];
    for (int i = 0; i < _rows.length; i++) {
      bool match = true;
      _columnFilters.forEach((colIdx, filter) {
        if (filter.isEmpty) return;
        String val = "";
        final row = _rows[i];
        switch (colIdx) {
          case 0: val = row.nameCtrl.text; break;
          case 1: val = cleanBatch(row.product?.batch ?? ""); break;
          case 5: val = row.product?.supplier ?? ""; break;
        }
        if (!val.toLowerCase().contains(filter.toLowerCase())) {
          match = false;
        }
      });
      if (match) filteredIndices.add(i);
    }

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400)),
      child: Column(
        children: [
          _buildTableHeader(),
          _buildFilterRow(),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemExtent: 30.0,
              itemCount: filteredIndices.length,
              itemBuilder: (ctx, i) => RepaintBoundary(child: _buildTableRow(filteredIndices[i])),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    return Container(
      height: 25,
      decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
      child: Row(
        children: [
          const SizedBox(width: 40), // Slno
          _filterCell(0, flex: 4), // Name
          _filterCell(1, flex: 1.5), // Batch
          const _EmptyFilterCell(flex: 1), // Expiry
          const _EmptyFilterCell(flex: 0.8), // Packing
          const _EmptyFilterCell(flex: 0.8), // Qty
          _filterCell(5, flex: 2), // Supplier
          const _EmptyFilterCell(flex: 1), // L.Cost
          const _EmptyFilterCell(flex: 1), // Total
          const SizedBox(width: 30),
        ],
      ),
    );
  }

  Widget _filterCell(int colIdx, {double? width, double? flex}) {
    Widget child = Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade300))),
      child: Row(
        children: [
          const Icon(Icons.filter_alt, size: 10, color: Colors.grey),
          Expanded(
            child: TextField(
              style: const TextStyle(fontSize: 10),
              decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero, hintText: "Filter...", hintStyle: TextStyle(fontSize: 10, color: Colors.grey)),
              onChanged: (v) { setState(() { _columnFilters[colIdx] = v; }); },
            ),
          ),
        ],
      ),
    );
    if (flex != null) return Expanded(flex: (flex * 10).toInt(), child: child);
    return child;
  }

  Widget _buildTableHeader() {
    return Container(
      height: 30,
      decoration: BoxDecoration(color: Colors.grey.shade200, border: Border(bottom: BorderSide(color: Colors.grey.shade400))),
      child: const Row(
        children: [
          _TableCell("Slno", width: 40, isHeader: true),
          _TableCell("Name", flex: 4, isHeader: true),
          _TableCell("Batch", flex: 1.5, isHeader: true),
          _TableCell("Expiry", flex: 1, isHeader: true),
          _TableCell("Packing", flex: 0.8, isHeader: true),
          _TableCell("Qty", flex: 0.8, isHeader: true),
          _TableCell("Supplier", flex: 2, isHeader: true),
          _TableCell("L.Cost", flex: 1, isHeader: true),
          _TableCell("Total", flex: 1, isHeader: true),
          SizedBox(width: 30),
        ],
      ),
    );
  }

  double _getExpiryMonths(String expStr) {
    if (expStr.isEmpty) return 999.0;
    final parts = expStr.split('/');
    if (parts.length != 2) return 999.0;
    final m = int.tryParse(parts[0]);
    final y = int.tryParse(parts[1]);
    if (m == null || y == null) return 999.0;
    final fullYear = y < 100 ? 2000 + y : y;
    final now = DateTime.now();
    final expDate = DateTime(fullYear, m, 1);
    final diffMonths = (expDate.year - now.year) * 12 + (expDate.month - now.month);
    return diffMonths.toDouble();
  }

  ({Color bg, Color text})? _evalDamageRuleStyle(PharmacyProvider provider, _StockRow row, String field) {
    final rules = provider.getValidationRules("DAMAGE");
    if (rules.isEmpty) return null;

    final p = row.product;
    if (p == null) return null;

    for (var rule in rules) {
      if (!rule.enabled) continue;

      bool appliesToCol = false;
      if (rule.fieldA == "Expiry (Months)" && field == "expiry") appliesToCol = true;
      if (rule.fieldA == "Qty" && field == "qty") appliesToCol = true;
      if (rule.fieldA == "Pack Size" && field == "pack") appliesToCol = true;

      if (!appliesToCol) continue;

      double valA = 0.0;
      switch (rule.fieldA) {
        case "Expiry (Months)":
          valA = _getExpiryMonths(row.expiryCtrl.text.isNotEmpty ? row.expiryCtrl.text : p.expiry);
          break;
        case "Qty":
          valA = double.tryParse(row.qtyCtrl.text) ?? 0.0;
          break;
        case "Pack Size":
          valA = p.packSize.toDouble();
          break;
        default:
          valA = 0.0;
      }

      if (valA <= 0 && rule.fieldA != "Expiry (Months)") continue;

      double valB = double.tryParse(rule.fieldB) ?? 0.0;

      bool isMatch = false;
      switch (rule.operator) {
        case ">=":
          isMatch = valA >= valB;
          break;
        case ">":
          isMatch = valA > valB;
          break;
        case "<=":
          isMatch = valA <= valB && valA > 0;
          break;
        case "<":
          isMatch = valA < valB && valA > 0;
          break;
        case "=":
          isMatch = (valA - valB).abs() < 0.001;
          break;
        case "!=":
          isMatch = (valA - valB).abs() >= 0.001;
          break;
      }

      if (isMatch) {
        return (bg: Color(rule.bgColorHex), text: Color(rule.textColorHex));
      }
    }

    return null;
  }

  Widget _buildTableRow(int index) {
    final row = _rows[index];
    final p = row.product;
    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    final expStyle = _evalDamageRuleStyle(provider, row, "expiry");
    final qtyStyle = _evalDamageRuleStyle(provider, row, "qty");
    final packStyle = _evalDamageRuleStyle(provider, row, "pack");

    return Container(
      height: 30,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
      child: Row(
        children: [
          _TableCell("${index + 1}", width: 40),
          Expanded(
            flex: 40,
            child: Container(
              decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade300))),
              child: _ProductSearchCell(
                controller: row.nameCtrl,
                focusNode: row.nameFocus,
                onSelected: (prod) {
                  setState(() {
                    row.product = prod;
                    row.nameCtrl.text = prod.name;
                    row.expiryCtrl.text = prod.expiry;
                    row.qtyFocus.requestFocus();
                  });
                },
              ),
            ),
          ),
          _TableCell(cleanBatch(p?.batch ?? ""), flex: 1.5),
          Expanded(
            flex: 10,
            child: Container(
              decoration: BoxDecoration(color: expStyle?.bg, border: Border(right: BorderSide(color: Colors.grey.shade300))),
              child: ErpGridTextField(
                controller: row.expiryCtrl,
                focusNode: row.expiryFocus,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: expStyle?.text ?? Colors.black),
                decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                inputFormatters: [ExpiryFormatter()],
                onNavigatePrevious: () => row.nameFocus.requestFocus(),
                onNavigateNext: () => row.qtyFocus.requestFocus(),
                onChanged: (v) {
                   _markDirty(); // <--- ADD THIS LINE
                   if (row.product != null) row.product!.expiry = v;
                },
                onSubmitted: (_) => row.qtyFocus.requestFocus(),
              ),
            ),
          ),
          _TableCell(p?.packSize.toString() ?? "", flex: 0.8, bg: packStyle?.bg, textColor: packStyle?.text),
          Expanded(
            flex: 8,
            child: Container(
              decoration: BoxDecoration(color: qtyStyle?.bg, border: Border(right: BorderSide(color: Colors.grey.shade300))),
              child: ErpGridTextField(
                controller: row.qtyCtrl,
                focusNode: row.qtyFocus,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: qtyStyle?.text ?? Colors.black),
                decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                onNavigatePrevious: () => row.expiryFocus.requestFocus(),
                onNavigateNext: () {
                  if (index < _rows.length - 1) {
                    _rows[index + 1].nameFocus.requestFocus();
                  } else {
                    _addNewRow();
                  }
                },
                onChanged: (_) {
                  _markDirty(); // <--- ADD THIS LINE
                  setState((){});
                },
                onSubmitted: (v) {
                  if (index == _rows.length - 1) {
                    _addNewRow();
                  } else {
                    _rows.last.nameFocus.requestFocus();
                  }
                },
              ),
            ),
          ),
          _TableCell(p?.supplier ?? "", flex: 2),
          _TableCell(_getLooseUnitCost(p).toStringAsFixed(2), flex: 1, textAlign: TextAlign.right),
          _TableCell(_calculateTotal(row).toStringAsFixed(2), flex: 1, textAlign: TextAlign.right),
          SizedBox(
            width: 30,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.red, size: 16),
              padding: EdgeInsets.zero,
              onPressed: () => _deleteRow(index),
            ),
          ),
        ],
      ),
    );
  }

  int _getLooseUnitCostPaise(Product? p) {
    if (p == null) return 0;
    int pSize = p.packSize > 0 ? p.packSize : 1;
    double baseRate = p.landingCost > 0
        ? p.landingCost
        : (p.purchaseRate > 0 ? p.purchaseRate : p.mrp);
    int baseRatePaise = TaxCalculator.toPaise(baseRate);
    // Explicit half-up rounding eliminates decimal paise truncation
    return (baseRatePaise / pSize).round();
  }

  double _getLooseUnitCost(Product? p) {
    return _getLooseUnitCostPaise(p) / 100.0;
  }

  int _calculateTotalPaise(_StockRow row) {
    if (row.product == null) return 0;
    int qty = (int.tryParse(row.qtyCtrl.text.trim()) ?? 0).abs();
    return _getLooseUnitCostPaise(row.product) * qty;
  }

  double _calculateTotal(_StockRow row) {
    return _calculateTotalPaise(row) / 100.0;
  }

  Widget _buildFooter() {
    double totalQty = 0;
    int grandTotalPaise = 0;
    for (var row in _rows) {
      int qty = (int.tryParse(row.qtyCtrl.text.trim()) ?? 0).abs();
      totalQty += qty;
      grandTotalPaise += _calculateTotalPaise(row);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _footerStat("Total Qty", totalQty.toStringAsFixed(0)),
          const SizedBox(width: 40),
          _footerStat("Grand Total", TaxCalculator.toRupeesString(grandTotalPaise), isAmount: true),
        ],
      ),
    );
  }

  Widget _footerStat(String label, String val, {bool isAmount = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
        Text(isAmount ? "₹ $val" : val, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: isAmount ? Colors.blue.shade900 : Colors.black87)),
      ],
    );
  }
}

class _EmptyFilterCell extends StatelessWidget {
  final double? flex;
  const _EmptyFilterCell({this.flex});
  @override Widget build(BuildContext context) {
    Widget child = Container(decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade300))));
    return flex != null ? Expanded(flex: (flex! * 10).toInt(), child: child) : child;
  }
}

class _TableCell extends StatelessWidget {
  final String text; final double? width; final double? flex; final bool isHeader; final TextAlign textAlign; final Color? bg; final Color? textColor;
  const _TableCell(this.text, {this.width, this.flex, this.isHeader = false, this.textAlign = TextAlign.left, this.bg, this.textColor});
  @override Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget child = Container(
      width: width, padding: const EdgeInsets.symmetric(horizontal: 4), alignment: textAlign == TextAlign.left ? Alignment.centerLeft : Alignment.centerRight,
      decoration: BoxDecoration(color: bg, border: Border(right: BorderSide(color: c.border))),
      child: Text(text, style: TextStyle(fontSize: isHeader ? 11 : 12, fontWeight: isHeader ? FontWeight.bold : FontWeight.normal, color: textColor ?? (isHeader ? c.primaryText : c.secondaryText)), overflow: TextOverflow.ellipsis),
    );
    return flex != null ? Expanded(flex: (flex! * 10).toInt(), child: child) : child;
  }
}

class _ProductSearchCell extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Function(Product) onSelected;
  const _ProductSearchCell({required this.controller, required this.focusNode, required this.onSelected});
  @override State<_ProductSearchCell> createState() => _ProductSearchCellState();
}

class _ProductSearchCellState extends State<_ProductSearchCell> {
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  List<Product> _results = [];
  int _selectedIndex = 0;
  final SearchDebouncer _debouncer = SearchDebouncer(milliseconds: 120);

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  // CODE MASTER FIX: Kills the ghost touch overlay when the screen is closed!
  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    _debouncer.dispose();
    _hideOverlay();
    super.dispose();
  }

  void _onFocusChange() {
    if (widget.focusNode.hasFocus) {
      if (widget.controller.text.isNotEmpty) {
        widget.controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.controller.text.length,
        );
      }
    } else {
      _hideOverlay();
    }
  }

  List<Product> _searchProductsAndBatches(PharmacyProvider provider, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];

    final allStockBatches = provider.products;
    final List<Product> batchMatches = [];

    for (final b in allStockBatches) {
      final nameLower = b.name.trim().toLowerCase();
      final aliasLower = b.alias.trim().toLowerCase();
      final batchLower = b.batch.trim().toLowerCase();

      if (nameLower.contains(q) ||
          (aliasLower.isNotEmpty && aliasLower.contains(q)) ||
          (batchLower.isNotEmpty && batchLower.contains(q))) {
        batchMatches.add(b);
      }
    }

    if (batchMatches.isNotEmpty) {
      batchMatches.sort((a, b) {
        final aStart = a.name.trim().toLowerCase().startsWith(q);
        final bStart = b.name.trim().toLowerCase().startsWith(q);
        if (aStart != bStart) return aStart ? -1 : 1;

        final aStockPos = a.stock > 0;
        final bStockPos = b.stock > 0;
        if (aStockPos != bStockPos) return aStockPos ? -1 : 1;

        return b.stock.compareTo(a.stock);
      });
      return batchMatches.take(20).toList();
    }

    final masterMatches = provider.searchProducts(q, includeGenerics: false);
    final List<Product> resolvedMatches = [];

    for (final master in masterMatches) {
      final fefoBatch = provider.getAutoFefoBatch(master.name);
      if (fefoBatch != null) {
        resolvedMatches.add(fefoBatch);
      } else {
        final anyBatch = provider.products.where((p) => p.id == master.id).firstOrNull;
        if (anyBatch != null) {
          resolvedMatches.add(anyBatch);
        } else {
          resolvedMatches.add(master);
        }
      }
    }

    return resolvedMatches.take(20).toList();
  }

  void _showOverlay() {
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _selectedIndex = 0;
  }

  OverlayEntry _createOverlayEntry() {
    if (!mounted) return OverlayEntry(builder: (_) => const SizedBox.shrink());
    final renderObj = context.findRenderObject();
    if (renderObj == null || !renderObj.attached || renderObj is! RenderBox || !renderObj.hasSize) {
      return OverlayEntry(builder: (_) => const SizedBox.shrink());
    }
    RenderBox renderBox = renderObj;
    var size = renderBox.size;
    return OverlayEntry(
      builder: (context) => StatefulBuilder(
        builder: (context, setPopupState) => Positioned(
          width: 500,
          child: CompositedTransformFollower(
            link: _layerLink, showWhenUnlinked: false, offset: Offset(0, size.height),
            // ---> THE FIX: TapRegion kills the overlay if you click outside! <---
              child: Listener(
                behavior: HitTestBehavior.opaque,
                child: Material(
                  elevation: 8,
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), color: Colors.white),
                    child: _results.isEmpty
                        ? const Padding(padding: EdgeInsets.all(8), child: Text("No results found"))
                        : ListView.builder(
                      shrinkWrap: true, padding: EdgeInsets.zero, itemCount: _results.length,
                      itemBuilder: (ctx, i) {
                        final p = _results[i];
                        final isSelected = i == _selectedIndex;
                        return InkWell(
                          onTap: () { widget.onSelected(p); _hideOverlay(); },
                          child: Container(
                            color: isSelected ? Colors.blue.shade50 : Colors.transparent,
                            child: ListTile(
                              dense: true,
                              title: Text(p.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 12)),
                              subtitle: Text("Batch: ${cleanBatch(p.batch)} | Exp: ${p.expiry} | Stock: ${p.stock}", style: const TextStyle(fontSize: 10)),
                              trailing: Text("₹${p.purchaseRate}", style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent || event is KeyRepeatEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                if (_overlayEntry == null) {
                  final provider = Provider.of<PharmacyProvider>(context, listen: false);
                  final matches = _searchProductsAndBatches(provider, widget.controller.text);
                  if (matches.isNotEmpty) {
                    setState(() {
                      _results = matches;
                      _selectedIndex = 0;
                      _showOverlay();
                    });
                  }
                  return KeyEventResult.handled;
                } else if (_results.isNotEmpty) {
                  setState(() {
                    _selectedIndex = (_selectedIndex + 1).clamp(0, _results.length - 1);
                    _overlayEntry?.markNeedsBuild();
                  });
                  return KeyEventResult.handled;
                }
              } else if (event.logicalKey == LogicalKeyboardKey.arrowUp && _overlayEntry != null) {
                if (_results.isNotEmpty) {
                  setState(() {
                    _selectedIndex = (_selectedIndex - 1).clamp(0, _results.length - 1);
                    _overlayEntry?.markNeedsBuild();
                  });
                }
                return KeyEventResult.handled;
              } else if ((event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) && _overlayEntry != null) {
                if (_results.isNotEmpty) {
                  widget.onSelected(_results[_selectedIndex]);
                  _hideOverlay();
                  return KeyEventResult.handled;
                }
              }
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onTap: () {
              _hideOverlay();
            },
            onChanged: (v) {
              if (v.isEmpty) {
                setState(() {
                  _results = [];
                  _hideOverlay();
                });
                return;
              }
              _debouncer.run(() {
                if (!mounted || !widget.focusNode.hasFocus) {
                  _hideOverlay();
                  return;
                }
                final provider = Provider.of<PharmacyProvider>(context, listen: false);
                final matches = _searchProductsAndBatches(provider, v);
                setState(() {
                  _results = matches;
                  _selectedIndex = 0;
                  if (matches.isEmpty) {
                    _hideOverlay();
                  } else if (_overlayEntry == null) {
                    _showOverlay();
                  } else {
                    _overlayEntry?.markNeedsBuild();
                  }
                });
              });
            },
            onSubmitted: (v) {
              if (_overlayEntry != null && _results.isNotEmpty) {
                widget.onSelected(_results[_selectedIndex]);
                _hideOverlay();
              } else if (_results.isNotEmpty) {
                widget.onSelected(_results[0]);
              }
            },
          ),
        ),
      ),
    );
  }
}