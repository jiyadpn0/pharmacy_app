import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/pharmacy_provider.dart';

import '../utils/app_dialogs.dart';
import '../widgets/pin_unlock_dialog.dart';
import '../utils/app_formatters.dart';
import '../utils/search_debouncer.dart';
import '../utils/theme_constants.dart';

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
  final TextEditingController expiryCtrl = TextEditingController();
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

class _DamageEntryScreenState extends State<DamageEntryScreen> {
  final TextEditingController _entryNoCtrl = TextEditingController();
  final TextEditingController _dateCtrl = TextEditingController();
  final TextEditingController _doneByCtrl = TextEditingController(text: "ADMIN");
  final TextEditingController _reasonCtrl = TextEditingController();

  final Map<int, String> _columnFilters = {};
  final List<_StockRow> _rows = [];
  final ScrollController _scrollController = ScrollController();

  bool _isExistingEntry = false;
  bool _isLoading = false;
  bool _isDirty = false;
  StockAdjustment? _originalLoadedAdj;

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
    if (_isExistingEntry) return _isDirty;

    for (var row in _rows) {
      if (row.product != null) {
        final qty = (int.tryParse(row.qtyCtrl.text.trim()) ?? 0).abs();
        if (qty > 0) return true;
      }
    }
    return false;
  }

  Future<bool?> _promptDiscardChanges() async {
    if (!_isExistingEntry) {
      if (!_hasValidItems()) return true;
    } else if (!_isDirty) {
      return true;
    }

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

  void _resetPage() async {
    // ---> THE FIX: Protect against losing unsaved edits <---
    if (_isExistingEntry && _isDirty) {
      bool? discard = await _promptDiscardChanges();
      if (discard != true) return; // User chose to stay
    }
    if (!mounted) return;

    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final nextNo = await p.getNextAdjustmentNo();
    if (mounted) {
      setState(() {
        _isExistingEntry = false;
        _isDirty = false;
        _entryNoCtrl.text = nextNo;
        _dateCtrl.text = DateFormat('dd/MM/yyyy').format(DateTime.now());
        for (var row in _rows) {
          row.dispose();
        }
        _rows.clear();
        _addNewRow();
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

      // We will add navigateInvoice for Adjustments in the Provider in Part 2
      final data = await p.navigateInvoice(targetNo, dir, isAdjustment: true);

      if (data != null) {
        _loadDamageData(data['entry_no'].toString());
      } else {
        if (dir == 'next') {
          _isExistingEntry ? _resetPage() : _showDialog("Navigation", "NO MORE RECORDS TO SHOW");
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

  void _loadDamageData(String entryNo) async {
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    setState(() => _isLoading = true);

    try {
      final adj = p.adjustments.firstWhere((a) => a.entryNo == entryNo);

      setState(() {
        _isExistingEntry = true;
        _isDirty = false; // <--- ADD THIS LINE
        _entryNoCtrl.text = adj.entryNo;
        _dateCtrl.text = DateFormat('dd/MM/yyyy').format(adj.date);
        _doneByCtrl.text = adj.doneBy;
        _reasonCtrl.text = adj.reason;

        for (var row in _rows) {
          row.dispose();
        }
        _rows.clear();

        for (var item in adj.items) {
          final row = _StockRow();
          row.product = item.product;
          row.nameCtrl.text = item.product.name;
          row.qtyCtrl.text = item.qty.abs().toString();
          row.expiryCtrl.text = item.product.expiry;
          _rows.add(row);
        }
        _addNewRow(); // Add empty row at bottom

        _originalLoadedAdj = StockAdjustment(
          entryNo: adj.entryNo,
          date: adj.date,
          doneBy: adj.doneBy,
          reason: adj.reason,
          items: adj.items.map((item) => StockAdjustmentItem(
            product: item.product.clone(),
            qty: item.qty,
            purchaseRate: item.purchaseRate,
            total: item.total,
          )).toList(),
          grandTotal: adj.grandTotal,
        );
      });
    } catch (e) {
      _showDialog("Error", "Could not load data: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- GENERATE DETAILED EDIT DIFF SPANS FOR RE-WRITE DIALOG ---
  List<InlineSpan> _generateDiffSpans() {
    final List<InlineSpan> diffSpans = [];

    if (!_isExistingEntry || _originalLoadedAdj == null) {
      return diffSpans;
    }

    const redStyle = TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13);
    const normalStyle = TextStyle(color: Colors.black87, fontSize: 13, height: 1.5);

    void addDiffLine(List<InlineSpan> parts) {
      diffSpans.add(const TextSpan(text: "• ", style: normalStyle));
      diffSpans.addAll(parts);
      diffSpans.add(const TextSpan(text: "\n", style: normalStyle));
    }

    // 1. HEADER COMPARISONS
    // Reason
    final currentReason = _reasonCtrl.text.trim();
    final origReason = _originalLoadedAdj!.reason.trim();
    if (currentReason.toUpperCase() != origReason.toUpperCase()) {
      addDiffLine([
        const TextSpan(text: "reason ", style: normalStyle),
        TextSpan(text: origReason.isEmpty ? "(blank)" : origReason, style: redStyle),
        const TextSpan(text: " to ", style: normalStyle),
        TextSpan(text: currentReason.isEmpty ? "(blank)" : currentReason, style: redStyle),
        const TextSpan(text: ".", style: normalStyle),
      ]);
    }

    // Done By
    final currentDoneBy = _doneByCtrl.text.trim();
    final origDoneBy = _originalLoadedAdj!.doneBy.trim();
    if (currentDoneBy.toUpperCase() != origDoneBy.toUpperCase()) {
      addDiffLine([
        const TextSpan(text: "done by ", style: normalStyle),
        TextSpan(text: origDoneBy.isEmpty ? "(blank)" : origDoneBy, style: redStyle),
        const TextSpan(text: " to ", style: normalStyle),
        TextSpan(text: currentDoneBy.isEmpty ? "(blank)" : currentDoneBy, style: redStyle),
        const TextSpan(text: ".", style: normalStyle),
      ]);
    }

    // 2. ITEM COMPARISONS
    final origItems = _originalLoadedAdj!.items;
    final currentValidRows = _rows.where((r) => r.product != null && r.qtyCtrl.text.trim().isNotEmpty).toList();

    int maxLen = origItems.length > currentValidRows.length ? origItems.length : currentValidRows.length;

    for (int i = 0; i < maxLen; i++) {
      if (i < origItems.length && i < currentValidRows.length) {
        final orig = origItems[i];
        final currRow = currentValidRows[i];
        final currProduct = currRow.product!;
        final currQty = (int.tryParse(currRow.qtyCtrl.text.trim()) ?? 0).abs();

        // Product Name
        final origName = orig.product.name.trim();
        final currName = currProduct.name.trim();
        if (origName.toUpperCase() != currName.toUpperCase()) {
          addDiffLine([
            const TextSpan(text: "product name ", style: normalStyle),
            TextSpan(text: origName, style: redStyle),
            const TextSpan(text: " to ", style: normalStyle),
            TextSpan(text: currName, style: redStyle),
            const TextSpan(text: ".", style: normalStyle),
          ]);
        }

        // Batch Number
        final origBatch = orig.product.batch.trim();
        final currBatch = currProduct.batch.trim();
        if (origBatch.toUpperCase() != currBatch.toUpperCase()) {
          addDiffLine([
            TextSpan(text: "batch ($currName) changed from ", style: normalStyle),
            TextSpan(text: '"$origBatch"', style: redStyle),
            const TextSpan(text: " to ", style: normalStyle),
            TextSpan(text: '"$currBatch"', style: redStyle),
            const TextSpan(text: ".", style: normalStyle),
          ]);
        }

        // Quantity
        final origQty = orig.qty.abs();
        if (origQty != currQty) {
          addDiffLine([
            TextSpan(text: "qty ($currName) changed from ", style: normalStyle),
            TextSpan(text: "$origQty", style: redStyle),
            const TextSpan(text: " to ", style: normalStyle),
            TextSpan(text: "$currQty", style: redStyle),
            const TextSpan(text: ".", style: normalStyle),
          ]);
        }
      } else if (i < currentValidRows.length) {
        final currRow = currentValidRows[i];
        final currProduct = currRow.product!;
        final currQty = (int.tryParse(currRow.qtyCtrl.text.trim()) ?? 0).abs();
        addDiffLine([
          const TextSpan(text: "added product ", style: normalStyle),
          TextSpan(text: currProduct.name.trim(), style: redStyle),
          const TextSpan(text: " (qty: ", style: normalStyle),
          TextSpan(text: "$currQty", style: redStyle),
          if (currProduct.batch.isNotEmpty) ...[
            const TextSpan(text: ', batch: "', style: normalStyle),
            TextSpan(text: currProduct.batch.trim(), style: redStyle),
            const TextSpan(text: '"', style: normalStyle),
          ],
          const TextSpan(text: ").", style: normalStyle),
        ]);
      } else if (i < origItems.length) {
        final orig = origItems[i];
        addDiffLine([
          const TextSpan(text: "removed product ", style: normalStyle),
          TextSpan(text: orig.product.name.trim(), style: redStyle),
          const TextSpan(text: " (qty: ", style: normalStyle),
          TextSpan(text: "${orig.qty.abs()}", style: redStyle),
          const TextSpan(text: ").", style: normalStyle),
        ]);
      }
    }

    return diffSpans;
  }

  void _save({bool isEdit = false}) async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    List<StockAdjustmentItem> items = [];
    double grandTotal = 0;

    for (var row in _rows) {
      if (row.product != null && row.qtyCtrl.text.isNotEmpty) {
        int rawQty = int.tryParse(row.qtyCtrl.text.trim()) ?? 0;
        // Enforce positive quantity to prevent stock inversion
        int qty = rawQty.abs();
        if (qty == 0) continue;

        // Verify shelf stock before sending adjustment
        int availableShelfStock = row.product!.stock;
        if (qty > availableShelfStock) {
          _showDialog(
            "Insufficient Stock", 
            "Cannot write off $qty units of '${row.product!.name}'. Only $availableShelfStock units available on shelf."
          );
          row.qtyFocus.requestFocus();
          return;
        }

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

        int pSize = row.product!.packSize > 0 ? row.product!.packSize : 1;
        double unitCost = row.product!.purchaseRate / pSize;
        double total = unitCost * qty;

        items.add(StockAdjustmentItem(
          product: row.product!,
          qty: -qty, // Strictly negative for stock deduction
          purchaseRate: row.product!.purchaseRate,
          total: total,
        ));
        grandTotal += total;
      }
    }

    if (items.isEmpty) {
      _showDialog("Empty", "Please add at least one item to save.");
      return;
    }

    if (isEdit || _isExistingEntry) {
      final diffSpans = _generateDiffSpans();

      if (diffSpans.isEmpty) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.blue, size: 26),
                SizedBox(width: 8),
                Text("No Changes Found", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: Text(
              "No modifications were detected on Entry #${_entryNoCtrl.text}.\nThere are no changes to save.",
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                child: const Text("OK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: Colors.orange, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Re-write Entry #${_entryNoCtrl.text}?",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "The following changes will be applied to this damage entry:",
                  style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText.rich(
                        TextSpan(children: diffSpans),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  "Are you sure you want to overwrite Entry #${_entryNoCtrl.text}? Stock will be updated accordingly.",
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black87),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("NO", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade800,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: const Text("YES, RE-WRITE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    // 1. SECURITY CHECK: PIN for Damage Entries
    if (provider.securityToggles['require_pin_write_off'] == true) {
      bool isUnlocked = await PinUnlockDialog.show(
          context,
          provider,
          title: "Auth Required",
          message: "Enter Master Password to authorize this stock write-off."
      );
      if (!isUnlocked) return;
    }

    // THE RULE: If Save is clicked, pass an empty string to safely auto-generate.
    final String finalEntryNo = isEdit ? _entryNoCtrl.text : "";

    final adj = StockAdjustment(
      entryNo: finalEntryNo,
      date: DateFormat('dd/MM/yyyy').parse(_dateCtrl.text),
      doneBy: _doneByCtrl.text,
      reason: _reasonCtrl.text,
      items: items,
      grandTotal: grandTotal,
    );

    setState(() => _isLoading = true);
    try {
      final assignedNo = await provider.saveStockAdjustment(adj, isEdit: isEdit);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.green,
            content: Text(isEdit ? "Entry #$assignedNo Updated!" : "Damage Entry #$assignedNo Saved!")));
        _isDirty = false; // <--- ADD THIS LINE
        _resetPage(); // Jump to new page after saving
      }
    } catch (e) {
      if (mounted) {
        _showDialog("Error", "Failed to save: $e");
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
    setState(() {
      final removed = _rows.removeAt(index);
      removed.dispose();

      if (_rows.isEmpty) {
        _addNewRow();
      } else {
        int nextIndex = index >= _rows.length ? _rows.length - 1 : index;
        _lastFocusedRowIndex = nextIndex;
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted && nextIndex >= 0 && nextIndex < _rows.length) {
            _rows[nextIndex].nameFocus.requestFocus();
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () => _save(isEdit: false),
        const SingleActivator(LogicalKeyboardKey.f3): _resetPage,
        const SingleActivator(LogicalKeyboardKey.delete, control: true): _handleCtrlDelete,
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            final isCtrl = HardwareKeyboard.instance.isControlPressed;
            if (isCtrl && event.logicalKey == LogicalKeyboardKey.delete) {
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
    ),
  );
}

  Widget _buildToolbar() {
    bool canSave = !_isExistingEntry;
    return Container(
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Add at least one damage/expiry item to save."), duration: Duration(seconds: 2)),
                );
              }
          ),
          _actionBtn(
              Icons.edit,
              "Edit",
              _isExistingEntry ? Colors.orange : Colors.grey.shade400,
              textColor: _isExistingEntry ? Colors.black87 : Colors.grey.shade400,
              onTap: _isExistingEntry ? () => _save(isEdit: true) : () {
                _showDialog("Locked", "This is a new entry. Click 'Save' instead.");
              }
          ),
          _actionBtn(Icons.print, "Print", Colors.blueGrey),
        ],
      ),
    );
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
              itemBuilder: (ctx, i) => _buildTableRow(filteredIndices[i]),
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

  Widget _buildTableRow(int index) {
    final row = _rows[index];
    final p = row.product;

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
              decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade300))),
              child: TextField(
                controller: row.expiryCtrl,
                focusNode: row.expiryFocus,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                inputFormatters: [ExpiryFormatter()],
                onChanged: (v) {
                   _markDirty(); // <--- ADD THIS LINE
                   if (row.product != null) row.product!.expiry = v;
                },
                onSubmitted: (_) => row.qtyFocus.requestFocus(),
              ),
            ),
          ),
          _TableCell(p?.packSize.toString() ?? "", flex: 0.8),
          Expanded(
            flex: 8,
            child: Container(
              decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade300))),
              child: TextField(
                controller: row.qtyCtrl,
                focusNode: row.qtyFocus,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 8)),
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
          _TableCell(p?.purchaseRate.toStringAsFixed(2) ?? "0.00", flex: 1, textAlign: TextAlign.right),
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

  double _calculateTotal(_StockRow row) {
    if (row.product == null) return 0;
    int qty = int.tryParse(row.qtyCtrl.text) ?? 0;
    return row.product!.purchaseRate * qty;
  }

  Widget _buildFooter() {
    double totalQty = 0;
    double grandTotal = 0;
    for (var row in _rows) {
      int qty = int.tryParse(row.qtyCtrl.text) ?? 0;
      totalQty += qty;
      grandTotal += (row.product?.purchaseRate ?? 0) * qty;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _footerStat("Total Qty", totalQty.toStringAsFixed(0)),
          const SizedBox(width: 40),
          _footerStat("Grand Total", grandTotal.toStringAsFixed(2), isAmount: true),
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
  final String text; final double? width; final double? flex; final bool isHeader; final TextAlign textAlign;
  const _TableCell(this.text, {this.width, this.flex, this.isHeader = false, this.textAlign = TextAlign.left});
  @override Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget child = Container(
      width: width, padding: const EdgeInsets.symmetric(horizontal: 4), alignment: textAlign == TextAlign.left ? Alignment.centerLeft : Alignment.centerRight,
      decoration: BoxDecoration(border: Border(right: BorderSide(color: c.border))),
      child: Text(text, style: TextStyle(fontSize: isHeader ? 11 : 12, fontWeight: isHeader ? FontWeight.bold : FontWeight.normal, color: isHeader ? c.primaryText : c.secondaryText), overflow: TextOverflow.ellipsis),
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
    RenderBox renderBox = context.findRenderObject() as RenderBox;
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
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowDown && _overlayEntry != null) {
                setState(() { _selectedIndex = (_selectedIndex + 1) % _results.length; _overlayEntry?.markNeedsBuild(); });
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowUp && _overlayEntry != null) {
                setState(() { _selectedIndex = (_selectedIndex - 1 + _results.length) % _results.length; _overlayEntry?.markNeedsBuild(); });
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            controller: widget.controller, focusNode: widget.focusNode,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
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
                if (!mounted) return;
                final provider = Provider.of<PharmacyProvider>(context, listen: false);
                final matches = _searchProductsAndBatches(provider, v);
                setState(() {
                  _results = matches;
                  _selectedIndex = 0;
                  if (_overlayEntry == null) {
                    _showOverlay();
                  } else {
                    _overlayEntry?.markNeedsBuild();
                  }
                });
              });
            },
            onSubmitted: (v) {
              if (_overlayEntry != null && _results.isNotEmpty) { widget.onSelected(_results[_selectedIndex]); _hideOverlay(); }
              else if (_results.isNotEmpty) { widget.onSelected(_results[0]); }
            },
          ),
        ),
      ),
    );
  }
}