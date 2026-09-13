import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/pharmacy_provider.dart';
import '../utils/app_dialogs.dart';
import '../widgets/pin_unlock_dialog.dart';
import '../utils/app_formatters.dart';
import '../utils/theme_constants.dart';

class StockAdjustmentBatchScreen extends StatefulWidget {
  const StockAdjustmentBatchScreen({super.key});

  @override
  State<StockAdjustmentBatchScreen> createState() => _StockAdjustmentBatchScreenState();
}

class _StockAdjustmentBatchScreenState extends State<StockAdjustmentBatchScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _entryNoCtrl = TextEditingController();
  final TextEditingController _dateCtrl = TextEditingController();
  final TextEditingController _doneByCtrl = TextEditingController(text: "ADMIN");
  final TextEditingController _reasonCtrl = TextEditingController();

  final FocusNode _globalFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  final List<_AdjustmentRow> _rows = [];

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
      if (row.selectedBatch != null) {
        if (row.physicalCtrl.text.trim().isNotEmpty) {
          return true;
        }
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
          "You have made changes to this saved adjustment.\nIf you leave now, your edits will be lost.\n\nDo you want to discard your changes?",
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
    _dateCtrl.text = DateFormat('dd/MM/yyyy').format(DateTime.now());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resetPage();
    });
  }

  @override
  void dispose() {
    _entryNoCtrl.dispose();
    _dateCtrl.dispose();
    _doneByCtrl.dispose();
    _reasonCtrl.dispose();
    _globalFocus.dispose();
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

  void _addNewRow() {
    setState(() {
      final row = _AdjustmentRow();
      _rows.add(row);
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) _moveFocus(_rows.length - 1, 0);
      });
    });
  }

  void _moveFocus(int rowIdx, int colIdx) {
    if (rowIdx < 0 || rowIdx >= _rows.length) return;
    final row = _rows[rowIdx];
    if (colIdx == 0) {
      row.productFocus.requestFocus();
    } else if (colIdx == 1) row.batchFocus.requestFocus();
    else if (colIdx == 2) row.physicalFocus.requestFocus();
  }

  void _navigateEntry(String dir, {String? searchNo}) async {
    // ---> THE FIX: Protect against losing unsaved edits <---
    if (_isExistingEntry && _isDirty) {
      bool? discard = await _promptDiscardChanges();
      if (discard != true) return; // User chose to stay
    }

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
        _loadAdjustmentData(data['entry_no'].toString());
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

  void _loadAdjustmentData(String entryNo) {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    try {
      final adj = provider.adjustments.firstWhere((a) => a.entryNo == entryNo);

      setState(() {
        _isExistingEntry = true;
        _isDirty = false;
        _entryNoCtrl.text = adj.entryNo;
        _dateCtrl.text = DateFormat('dd/MM/yyyy').format(adj.date);
        _doneByCtrl.text = adj.doneBy;
        _reasonCtrl.text = adj.reason;

        for (var row in _rows) {
          row.dispose();
        }
        _rows.clear();

        for (var item in adj.items) {
          final row = _AdjustmentRow();
          row.selectedBatch = item.product;
          row.selectedProduct = item.product; 
          row.productCtrl.text = item.product.name;
          row.batchCtrl.text = cleanBatch(item.product.batch);
          row.expiryCtrl.text = item.product.expiry;
          // When loading an existing entry, physical count is (system stock at that time + variance)
          // Since p.stock is the current stock (already includes variance if this was the last adjustment),
          // we can just use p.stock as the physical count, and (p.stock - variance) as the old system stock.
          row.physicalCtrl.text = item.product.stock.toString();
          row.savedVariance = item.qty;
          _rows.add(row);
        }
        _addNewRow();

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
    final currentValidRows = _rows.where((r) => r.selectedBatch != null && r.physicalCtrl.text.trim().isNotEmpty).toList();

    int maxLen = origItems.length > currentValidRows.length ? origItems.length : currentValidRows.length;

    for (int i = 0; i < maxLen; i++) {
      if (i < origItems.length && i < currentValidRows.length) {
        final orig = origItems[i];
        final currRow = currentValidRows[i];
        final currProduct = currRow.selectedBatch!;
        final currPhysical = int.tryParse(currRow.physicalCtrl.text.trim()) ?? currProduct.stock;

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

        // Physical Stock Count / Variance
        int origPhysical = orig.product.stock;
        if (origPhysical != currPhysical) {
          addDiffLine([
            TextSpan(text: "physical stock ($currName) changed from ", style: normalStyle),
            TextSpan(text: "$origPhysical", style: redStyle),
            const TextSpan(text: " to ", style: normalStyle),
            TextSpan(text: "$currPhysical", style: redStyle),
            const TextSpan(text: ".", style: normalStyle),
          ]);
        }
      } else if (i < currentValidRows.length) {
        final currRow = currentValidRows[i];
        final currProduct = currRow.selectedBatch!;
        final currPhysical = int.tryParse(currRow.physicalCtrl.text.trim()) ?? currProduct.stock;
        addDiffLine([
          const TextSpan(text: "added adjustment product ", style: normalStyle),
          TextSpan(text: currProduct.name.trim(), style: redStyle),
          const TextSpan(text: " (physical stock: ", style: normalStyle),
          TextSpan(text: "$currPhysical", style: redStyle),
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
          const TextSpan(text: "removed adjustment product ", style: normalStyle),
          TextSpan(text: orig.product.name.trim(), style: redStyle),
          const TextSpan(text: ").", style: normalStyle),
        ]);
      }
    }

    return diffSpans;
  }

  void _saveAdjustments({bool isEdit = false}) async {
    FocusScope.of(context).unfocus();
    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    if (provider.securityToggles['require_pin_stock_adjustments'] == true) {
      bool isUnlocked = await PinUnlockDialog.show(
          context,
          provider,
          title: "Authorization Required",
          message: "Enter Master PIN to save stock adjustments."
      ) ?? false;
      if (!isUnlocked) return;
    }

    List<StockAdjustmentItem> adjustmentItems = [];

    for (var row in _rows) {
      if (row.selectedBatch != null && row.physicalCtrl.text.isNotEmpty) {
        // Strict Expiry Validator Check
        String exp = row.expiryCtrl.text.trim();
        if (exp.isNotEmpty && exp != "--/--") {
          final parts = exp.split(RegExp(r'[-/]'));
          if (parts.length == 2) {
            int? month = int.tryParse(parts[0]);
            int? year = int.tryParse(parts[1]);
            if (month == null || month < 1 || month > 12 || year == null) {
              _showDialog("Invalid Expiry", "Invalid expiry month ($exp) for '${row.selectedBatch!.name}'. Must be between 01 and 12.");
              row.expiryFocus.requestFocus();
              return;
            }
          } else {
            _showDialog("Invalid Expiry", "Expiry must follow MM/YY format for '${row.selectedBatch!.name}'.");
            row.expiryFocus.requestFocus();
            return;
          }
        }

        int physicalQty = int.tryParse(row.physicalCtrl.text) ?? row.selectedBatch!.stock;
        
        // Calculate variance relative to the stock BEFORE this adjustment
        int systemStock = row.selectedBatch!.stock;
        if (isEdit) {
          systemStock -= row.savedVariance;
        }
        
        int variance = physicalQty - systemStock;

        if (variance != 0) {
          int pSize = row.selectedBatch!.packSize > 0 ? row.selectedBatch!.packSize : 1;
          double unitCost = row.selectedBatch!.landingCost / pSize;
          
          adjustmentItems.add(StockAdjustmentItem(
            product: row.selectedBatch!,
            qty: variance,
            purchaseRate: row.selectedBatch!.landingCost,
            total: variance * unitCost,
          ));
        }
      }
    }

    if (adjustmentItems.isEmpty) {
      _showDialog("Empty", "No variance detected. Physical stock matches system stock exactly.");
      return;
    }

    bool hasError = false;
    for (var row in _rows) {
      row.hasProductError = false;
      row.hasBatchError = false;
      row.hasPhysicalError = false;

      if (row.productCtrl.text.isNotEmpty) {
        if (row.selectedBatch == null || row.batchCtrl.text.isEmpty) {
          row.hasBatchError = true;
          hasError = true;
        }
        if (row.physicalCtrl.text.isEmpty) {
          row.hasPhysicalError = true;
          hasError = true;
        }
      }
    }
    
    if (hasError) {
      setState(() {}); // Trigger red paints
      _showDialog("Validation Error", "Please fill in the missing fields highlighted in red.");
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
              "No modifications were detected on Adjustment #${_entryNoCtrl.text}.\nThere are no changes to save.",
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
                  "Re-write Adjustment #${_entryNoCtrl.text}?",
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
                  "The following changes will be applied to this stock adjustment:",
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
                  "Are you sure you want to overwrite Adjustment #${_entryNoCtrl.text}? Stock will be updated accordingly.",
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

    final String finalEntryNo = isEdit ? _entryNoCtrl.text : "";

    setState(() => _isLoading = true);
    try {
      final assignedNo = await provider.saveStockAdjustment(StockAdjustment(
        entryNo: finalEntryNo,
        date: DateFormat('dd/MM/yyyy').parse(_dateCtrl.text),
        doneBy: _doneByCtrl.text,
        reason: _reasonCtrl.text.isEmpty ? "PHYSICAL STOCK VERIFICATION" : _reasonCtrl.text,
        items: adjustmentItems,
        grandTotal: adjustmentItems.fold(0.0, (sum, item) => sum + item.total),
      ), isEdit: isEdit);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.green,
            content: Text(isEdit ? "Adjustment #$assignedNo Updated!" : "Adjustment #$assignedNo Saved!")));
        _isDirty = false;
        _resetPage();
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      body: Focus(
        focusNode: _globalFocus,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.f10) {
              _saveAdjustments(isEdit: _isExistingEntry);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.f2) {
              _resetPage();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            Column(
              children: [
                _buildToolbar(),
                _buildHeaderFields(),
                Expanded(child: _buildBatchGrid()),
                _buildFooterShortcuts(),
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
    bool canSave = !_isExistingEntry;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
      child: Row(
        children: [
          const Text("PHYSICAL STOCK ADJUSTMENT", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black87)),
          const Spacer(),
          _actionBtn(Icons.add_circle, "New (F2)", Colors.blue, onTap: _resetPage),
          _actionBtn(
              Icons.check_circle,
              "Save (F10)",
              canSave ? Colors.green : Colors.grey.shade400,
              textColor: canSave ? Colors.black87 : Colors.grey.shade400,
              onTap: canSave ? () => _saveAdjustments(isEdit: false) : () {}
          ),
          _actionBtn(
              Icons.edit,
              "Edit",
              _isExistingEntry ? Colors.orange : Colors.grey.shade400,
              textColor: _isExistingEntry ? Colors.black87 : Colors.grey.shade400,
              onTap: _isExistingEntry ? () => _saveAdjustments(isEdit: true) : () {
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

  Widget _buildBatchGrid() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400)),
      child: Column(
        children: [
          Container(
            height: 35,
            color: const Color(0xFF4A4A4A),
            child: const Row(
              children: [
                _Hdr("SL", width: 40, align: TextAlign.center),
                _Hdr("PRODUCT", flex: 40),
                _Hdr("BATCH NO", flex: 20),
                _Hdr("PACK", flex: 8, align: TextAlign.center),
                _Hdr("EXPIRY", flex: 10, align: TextAlign.center),
                _Hdr("MRP", flex: 10, align: TextAlign.right),
                _Hdr("PRATE", flex: 10, align: TextAlign.right),
                _Hdr("SYSTEM STOCK", flex: 10, align: TextAlign.right),
                _Hdr("PHYSICAL COUNT", flex: 10, align: TextAlign.center),
                _Hdr("VARIANCE", flex: 10, align: TextAlign.right),
                _Hdr("L.COST DIFF", flex: 12, align: TextAlign.right),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _rows.length,
              itemBuilder: (context, i) => _buildRow(i, _rows[i]),
            ),
          ),
          _buildGridFooter(),
        ],
      ),
    );
  }

  Widget _buildRow(int index, _AdjustmentRow row) {
    // PART 2 FIX: Wrapped in AnimatedBuilder to stop full screen lag when typing
    return AnimatedBuilder(
      animation: row.physicalCtrl,
      builder: (context, child) {
        final p = row.selectedBatch;
        
        int systemStock = (p?.stock ?? 0);
        if (_isExistingEntry) {
          systemStock -= row.savedVariance;
        }
        
        int physical = int.tryParse(row.physicalCtrl.text) ?? (p?.stock ?? 0);
        int variance = physical - systemStock;

        return Container(
          height: 40,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
          child: Row(
            children: [
              _Cell((index + 1).toString(), width: 40, align: TextAlign.center),
              
              Expanded(
                flex: 40,
                child: Container(
                  decoration: BoxDecoration(
                    color: row.hasProductError ? Colors.red.shade100 : null,
                    border: Border(right: BorderSide(color: Colors.grey.shade300))
                  ),
                  child: _ProductSearchCell(
                    controller: row.productCtrl,
                    focusNode: row.productFocus,
                    onSelected: (prod) {
                      setState(() {
                        row.selectedProduct = prod;
                        row.productCtrl.text = prod.name;
                        row.batchFocus.requestFocus();
                      });
                    },
                  ),
                ),
              ),

              Expanded(
                flex: 20,
                child: Container(
                  decoration: BoxDecoration(
                    color: row.hasBatchError ? Colors.red.shade100 : null,
                    border: Border(right: BorderSide(color: Colors.grey.shade300))
                  ),
                  child: _BatchSearchCell(
                    controller: row.batchCtrl,
                    focusNode: row.batchFocus,
                    productId: row.selectedProduct?.id ?? "",
                    onSelected: (batch) {
                      setState(() {
                        row.selectedBatch = batch;
                        row.batchCtrl.text = cleanBatch(batch.batch);
                        row.expiryCtrl.text = batch.expiry;
                        
                        int pack = batch.packSize > 0 ? batch.packSize : 1;
                        row.physicalStripsCtrl.text = (batch.stock ~/ pack).toString();
                        row.physicalLooseCtrl.text = (batch.stock % pack).toString();
                        row.physicalCtrl.text = batch.stock.toString();
                        
                        row.physicalStripsFocus.requestFocus();
                      });
                    },
                  ),
                ),
              ),

              _Cell(p?.packSize.toString() ?? "0", flex: 8, align: TextAlign.center, color: Colors.blueGrey),
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
                       if (row.selectedBatch != null) row.selectedBatch!.expiry = v;
                    },
                    onSubmitted: (_) => row.physicalFocus.requestFocus(),
                  ),
                ),
              ),
              _Cell(p?.mrp.toStringAsFixed(2) ?? "0.00", flex: 10, align: TextAlign.right),
              _Cell(p?.purchaseRate.toStringAsFixed(2) ?? "0.00", flex: 10, align: TextAlign.right),
              _Cell(systemStock.toString(), flex: 10, align: TextAlign.right, fontWeight: FontWeight.bold, color: Colors.blueGrey),

              Expanded(
                flex: 12,
                child: Row(
                  children: [
                    // STRIPS INPUT
                    Expanded(
                      flex: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                        child: TextField(
                          controller: row.physicalStripsCtrl,
                          focusNode: row.physicalStripsFocus,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: "Strips",
                            hintStyle: const TextStyle(fontSize: 9, color: Colors.grey),
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(vertical: 6),
                            fillColor: row.hasPhysicalError ? Colors.red.shade100 : Colors.yellow.shade50,
                            filled: true,
                          ),
                          onChanged: (_) {
                            _markDirty();
                            int pack = (p?.packSize ?? 1) > 0 ? (p?.packSize ?? 1) : 1;
                            int strips = int.tryParse(row.physicalStripsCtrl.text) ?? 0;
                            int loose = int.tryParse(row.physicalLooseCtrl.text) ?? 0;
                            row.physicalCtrl.text = ((strips * pack) + loose).toString();
                          },
                          onSubmitted: (_) => row.physicalLooseFocus.requestFocus(),
                        ),
                      ),
                    ),
                    const Text("/", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    // LOOSE UNITS INPUT
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                        child: TextField(
                          controller: row.physicalLooseCtrl,
                          focusNode: row.physicalLooseFocus,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: "Loose",
                            hintStyle: const TextStyle(fontSize: 9, color: Colors.grey),
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(vertical: 6),
                            fillColor: row.hasPhysicalError ? Colors.red.shade100 : Colors.yellow.shade50,
                            filled: true,
                          ),
                          onChanged: (_) {
                            _markDirty();
                            int pack = (p?.packSize ?? 1) > 0 ? (p?.packSize ?? 1) : 1;
                            int strips = int.tryParse(row.physicalStripsCtrl.text) ?? 0;
                            int loose = int.tryParse(row.physicalLooseCtrl.text) ?? 0;
                            row.physicalCtrl.text = ((strips * pack) + loose).toString();
                          },
                          onSubmitted: (_) {
                            setState(() {});
                            if (index == _rows.length - 1) {
                              _addNewRow();
                            } else {
                              _moveFocus(_rows.length - 1, 0);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                flex: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.centerRight,
                  child: Text(
                    variance == 0 ? "0" : (variance > 0 ? "+$variance" : "$variance"),
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: variance == 0 ? Colors.grey : (variance > 0 ? Colors.green : Colors.red)),
                  ),
                ),
              ),

              Builder(
                builder: (context) {
                  double lCostImpact = 0;
                  if (p != null) {
                    int pSize = p.packSize <= 0 ? 1 : p.packSize;
                    lCostImpact = (p.landingCost / pSize) * variance;
                  }
                  return _Cell(
                    lCostImpact.toStringAsFixed(2), 
                    flex: 12, 
                    align: TextAlign.right,
                    color: lCostImpact == 0 ? Colors.grey : (lCostImpact > 0 ? Colors.green : Colors.red),
                    fontWeight: FontWeight.bold
                  );
                }
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildGridFooter() {
    int totalVariance = 0;
    for (var row in _rows) {
      if (row.selectedBatch != null) {
        int systemStock = row.selectedBatch!.stock;
        if (_isExistingEntry) {
          systemStock -= row.savedVariance;
        }
        int physical = int.tryParse(row.physicalCtrl.text) ?? row.selectedBatch!.stock;
        totalVariance += (physical - systemStock);
      }
    }

    return Container(
      height: 35,
      color: Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Text("Total Items: ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          Text(_rows.where((r)=>r.selectedBatch != null).length.toString(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          const SizedBox(width: 24),
          const Text("Net Variance: ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          Text(totalVariance.toString(), style: TextStyle(fontWeight: FontWeight.bold, color: totalVariance >= 0 ? Colors.green : Colors.red)),
        ],
      ),
    );
  }

  Widget _buildFooterShortcuts() {
    return Container(
      height: 30,
      color: const Color(0xFF2C3E50),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: const Row(
        children: [
          _Shortcut("F2", "New Entry"),
          _Shortcut("F10", "Save Adjustment"),
          _Shortcut("ESC", "Cancel"),
        ],
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  final String keyName; final String action;
  const _Shortcut(this.keyName, this.action);
  @override Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 24),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3)), child: Text(keyName, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
          const SizedBox(width: 6),
          Text(action, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }
}

class _AdjustmentRow {
  final TextEditingController productCtrl = TextEditingController();
  final FocusNode productFocus = FocusNode();
  final TextEditingController batchCtrl = TextEditingController();
  final FocusNode batchFocus = FocusNode();
  final TextEditingController physicalStripsCtrl = TextEditingController(); // NEW
  final FocusNode physicalStripsFocus = FocusNode();                        // NEW
  final TextEditingController physicalLooseCtrl = TextEditingController();  // NEW
  final FocusNode physicalLooseFocus = FocusNode();                         // NEW
  final TextEditingController physicalCtrl = TextEditingController();
  final FocusNode physicalFocus = FocusNode();
  final TextEditingController expiryCtrl = TextEditingController();
  final FocusNode expiryFocus = FocusNode();
  
  Product? selectedProduct;
  Product? selectedBatch;
  int savedVariance = 0; 
  
  // NEW: Cell error trackers
  bool hasProductError = false;
  bool hasBatchError = false;
  bool hasPhysicalError = false;

  void dispose() {
    productCtrl.dispose();
    productFocus.dispose();
    batchCtrl.dispose();
    batchFocus.dispose();
    physicalStripsCtrl.dispose();
    physicalStripsFocus.dispose();
    physicalLooseCtrl.dispose();
    physicalLooseFocus.dispose();
    physicalCtrl.dispose();
    physicalFocus.dispose();
    expiryCtrl.dispose();
    expiryFocus.dispose();
  }
}

class _Hdr extends StatelessWidget {
  final String title; final double? width; final int? flex; final TextAlign align;
  const _Hdr(this.title, {this.width, this.flex, this.align = TextAlign.left});
  @override Widget build(BuildContext context) {
    Widget child = Container(
      width: width, 
      alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.right ? Alignment.centerRight : Alignment.center), 
      padding: const EdgeInsets.symmetric(horizontal: 8), 
      decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.white12))),
      child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900))
    );
    return flex != null ? Expanded(flex: flex!, child: child) : child;
  }
}

class _Cell extends StatelessWidget {
  final String text; final double? width; final int? flex; final TextAlign align; final Color? color; final FontWeight fontWeight;
  const _Cell(this.text, {this.width, this.flex, this.align = TextAlign.left, this.color, this.fontWeight = FontWeight.w600});
  @override Widget build(BuildContext context) {
    Widget child = Container(
      width: width, 
      padding: const EdgeInsets.symmetric(horizontal: 8), 
      alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.right ? Alignment.centerRight : Alignment.center), 
      decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade200))), 
      child: Text(text, style: TextStyle(fontSize: 11, color: color ?? Colors.black87, fontWeight: fontWeight), overflow: TextOverflow.ellipsis)
    );
    return flex != null ? Expanded(flex: flex!, child: child) : child;
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

  void _showOverlay() {
    if (_overlayEntry == null) {
      _overlayEntry = _createOverlayEntry();
      Overlay.of(context).insert(_overlayEntry!);
    }
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _selectedIndex = 0;
  }

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _hideOverlay(); // <-- This kills the invisible ghost touch layer
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (widget.focusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 10), () {
        if (!mounted) return;
        
        if (widget.controller.text.isNotEmpty) {
          // Select whole text on focus
          widget.controller.selection = TextSelection(
            baseOffset: 0, 
            extentOffset: widget.controller.text.length
          );
          // Do NOT trigger dropdown if there's already a value
        } else {
          // Trigger dropdown only if empty
          _triggerProductSearch();
        }
      });
    } else {
      _hideOverlay();
    }
  }

  void _triggerProductSearch() {
    if (!mounted) return;
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    _results = provider.searchProducts(widget.controller.text, includeGenerics: true);
    _selectedIndex = 0;
    
    // Always show if results exist
    if (_results.isNotEmpty) {
      _showOverlay();
    }
  }

  void _onProductChosen(Product p) {
    widget.onSelected(p);
    _hideOverlay();
  }

  OverlayEntry _createOverlayEntry() {
    RenderBox renderBox = context.findRenderObject() as RenderBox;
    var size = renderBox.size;
    return OverlayEntry(
      builder: (context) => StatefulBuilder(
        builder: (context, setPopupState) => Positioned(
          width: 850,
          child: CompositedTransformFollower(
            link: _layerLink, showWhenUnlinked: false, offset: Offset(0, size.height),
            // ---> THE FIX: TapRegion instantly kills the overlay if you click outside! <---
            child: Listener(
              behavior: HitTestBehavior.opaque,
              child: Material(
                elevation: 8,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  decoration: BoxDecoration(border: Border.all(color: const Color(0xFF0D47A1)), color: Colors.white),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 30,
                        color: const Color(0xFF0D47A1),
                        child: const Row(
                          children: [
                            _HdrSmall("Name", flex: 4),
                            _HdrSmall("Stock", flex: 1, align: TextAlign.right),
                            _HdrSmall("Packin", flex: 1, align: TextAlign.right),
                            _HdrSmall("MRP", flex: 1, align: TextAlign.right),
                            _HdrSmall("PRate", flex: 1, align: TextAlign.right),
                            _HdrSmall("Rack", flex: 1, align: TextAlign.center),
                            _HdrSmall("Cat", flex: 1, align: TextAlign.center),
                            _HdrSmall("Paten", flex: 1, align: TextAlign.center),
                          ],
                        ),
                      ),
                      Flexible(
                        child: _results.isEmpty
                            ? const Padding(padding: EdgeInsets.all(8), child: Text("No results found"))
                            : ListView.builder(
                          shrinkWrap: true, padding: EdgeInsets.zero, itemCount: _results.length,
                          itemBuilder: (ctx, i) {
                            final p = _results[i];
                            final isSelected = i == _selectedIndex;
                            return GestureDetector(
                              onTap: () => _onProductChosen(p),
                              child: Container(
                                height: 30,
                                decoration: BoxDecoration(
                                  color: isSelected ? Colors.blue.shade50 : Colors.white,
                                  border: Border(bottom: BorderSide(color: Colors.grey.shade200))
                                ),
                                child: Row(
                                  children: [
                                    _CellSmall(p.name, flex: 4, fontWeight: FontWeight.bold),
                                    _CellSmall(p.stock.toString(), flex: 1, align: TextAlign.right, color: Colors.blue.shade700, fontWeight: FontWeight.bold),
                                    _CellSmall(p.packSize.toString(), flex: 1, align: TextAlign.right),
                                    _CellSmall(p.mrp.toStringAsFixed(2), flex: 1, align: TextAlign.right),
                                    _CellSmall(p.purchaseRate.toStringAsFixed(2), flex: 1, align: TextAlign.right),
                                    _CellSmall(p.rack, flex: 1, align: TextAlign.center),
                                    _CellSmall(p.category.length > 3 ? p.category.substring(0,3).toUpperCase() : p.category.toUpperCase(), flex: 1, align: TextAlign.center),
                                    _CellSmall(p.patent.length > 3 ? p.patent.substring(0,3).toUpperCase() : p.patent.toUpperCase(), flex: 1, align: TextAlign.center),
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
              } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                _hideOverlay();
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowRight && _overlayEntry == null) {
                final state = context.findAncestorStateOfType<_StockAdjustmentBatchScreenState>();
                final index = state?._rows.indexWhere((r) => r.productFocus == widget.focusNode);
                if (index != null && index != -1) state?._moveFocus(index, 1);
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowDown && _overlayEntry == null) {
                final state = context.findAncestorStateOfType<_StockAdjustmentBatchScreenState>();
                final index = state?._rows.indexWhere((r) => r.productFocus == widget.focusNode);
                if (index != null && index != -1) state?._moveFocus(index + 1, 0);
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowUp && _overlayEntry == null) {
                final state = context.findAncestorStateOfType<_StockAdjustmentBatchScreenState>();
                final index = state?._rows.indexWhere((r) => r.productFocus == widget.focusNode);
                if (index != null && index != -1) state?._moveFocus(index - 1, 0);
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
              if (widget.controller.text.isNotEmpty) {
                widget.controller.selection = TextSelection(baseOffset: 0, extentOffset: widget.controller.text.length);
                _hideOverlay();
              }
            },
            onChanged: (v) {
              final provider = Provider.of<PharmacyProvider>(context, listen: false);
              setState(() {
                if (v.isEmpty) { _results = []; _hideOverlay(); }
                else {
                  _results = provider.searchProducts(v, includeGenerics: true);
                  _selectedIndex = 0;
                  if (_overlayEntry == null) {
                    _showOverlay();
                  } else {
                    _overlayEntry?.markNeedsBuild();
                  }
                }
              });
            },
            onSubmitted: (v) {
              if (_overlayEntry != null && _results.isNotEmpty) { 
                _onProductChosen(_results[_selectedIndex]);
              }
            },
          ),
        ),
      ),
    );
  }
}

class _BatchSearchCell extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String productId;
  final Function(Product) onSelected;
  const _BatchSearchCell({required this.controller, required this.focusNode, required this.productId, required this.onSelected});
  @override State<_BatchSearchCell> createState() => _BatchSearchCellState();
}

class _BatchSearchCellState extends State<_BatchSearchCell> {
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  List<Product> _results = [];
  int _selectedIndex = 0;

  void _showOverlay() {
    if (_overlayEntry == null) {
      _overlayEntry = _createOverlayEntry();
      Overlay.of(context).insert(_overlayEntry!);
    }
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _selectedIndex = 0;
  }

  DateTime? _parseExpiry(String expiry) {
    if (expiry.isEmpty) return null;
    try {
      final parts = expiry.split('/');
      if (parts.length == 2) {
        int m = int.parse(parts[0]);
        int y = int.parse(parts[1]) + 2000;
        return DateTime(y, m, 1);
      }
    } catch (_) {}
    return null;
  }

  OverlayEntry _createOverlayEntry() {
    RenderBox renderBox = context.findRenderObject() as RenderBox;
    var size = renderBox.size;
    return OverlayEntry(
      builder: (context) => StatefulBuilder(
        builder: (context, setPopupState) => Positioned(
          width: 800,
          child: CompositedTransformFollower(
            link: _layerLink, showWhenUnlinked: false, offset: Offset(0, size.height),
            // ---> THE FIX: TapRegion <---
            child: Listener(
              behavior: HitTestBehavior.opaque,
              child: Material(
                elevation: 8,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  decoration: BoxDecoration(border: Border.all(color: Colors.teal.shade300), color: Colors.white),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 30,
                        color: Colors.teal,
                        child: const Row(
                          children: [
                            _HdrSmall("Batch", flex: 3),
                            _HdrSmall("Stock", flex: 2, align: TextAlign.right),
                            _HdrSmall("Packing", flex: 2, align: TextAlign.right),
                            _HdrSmall("Expiry", flex: 2, align: TextAlign.center),
                            _HdrSmall("MRP", flex: 2, align: TextAlign.right),
                            _HdrSmall("S.PRICE", flex: 2, align: TextAlign.right),
                            _HdrSmall("Disc%", flex: 2, align: TextAlign.right),
                          ],
                        ),
                      ),
                      Flexible(
                        child: _results.isEmpty
                            ? const Padding(padding: EdgeInsets.all(8), child: Text("No batches available"))
                            : ListView.builder(
                          shrinkWrap: true, padding: EdgeInsets.zero, itemCount: _results.length,
                          itemBuilder: (ctx, i) {
                            final p = _results[i];
                            final isSelected = i == _selectedIndex;
                            return GestureDetector(
                              onTap: () { widget.onSelected(p); _hideOverlay(); },
                              child: Container(
                                height: 30,
                                decoration: BoxDecoration(
                                  color: isSelected ? Colors.blue.shade50 : Colors.white,
                                  border: Border(bottom: BorderSide(color: Colors.grey.shade200))
                                ),
                                child: Row(
                                  children: [
                                    _CellSmall(cleanBatch(p.batch), flex: 3, fontWeight: FontWeight.bold),
                                    _CellSmall(p.stock.toString(), flex: 2, align: TextAlign.right, fontWeight: FontWeight.bold),
                                    _CellSmall(p.packSize.toString(), flex: 2, align: TextAlign.right),
                                    _CellSmall(p.expiry, flex: 2, align: TextAlign.center, color: Colors.teal.shade700, fontWeight: FontWeight.bold),
                                    _CellSmall(p.mrp.toStringAsFixed(2), flex: 2, align: TextAlign.right),
                                    _CellSmall(p.salePrice.toStringAsFixed(2), flex: 2, align: TextAlign.right),
                                    _CellSmall(p.sDiscPercent.toStringAsFixed(2), flex: 2, align: TextAlign.right),
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
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _hideOverlay(); // <-- This kills the second ghost touch layer
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (widget.focusNode.hasFocus) {
      _tryOpenBatchDropdown();
    } else {
      _hideOverlay();
    }
  }

  void _tryOpenBatchDropdown([int retryCount = 0]) {
    if (!mounted || !widget.focusNode.hasFocus) return;
    
    if (widget.productId.isNotEmpty) {
      if (widget.controller.text.isNotEmpty) {
        // Select whole text on focus
        widget.controller.selection = TextSelection(
          baseOffset: 0, 
          extentOffset: widget.controller.text.length
        );
        // Do NOT open dropdown automatically if a value exists
      } else {
        // It's empty, so trigger the search and show dropdown
        _triggerBatchSearch();
      }
    } else if (retryCount < 10) {
      // If parent ID is not yet propagated, wait a bit and retry
      Future.delayed(const Duration(milliseconds: 30), () => _tryOpenBatchDropdown(retryCount + 1));
    }
  }

  void _triggerBatchSearch() {
    if (!mounted) return;
    if (widget.productId.isNotEmpty) {
      final provider = Provider.of<PharmacyProvider>(context, listen: false);
      // Fetch all batches, filter by current text if any
      final q = widget.controller.text.toLowerCase();
      _results = provider.products.where((it) => 
        it.id == widget.productId && it.stock > 0 &&
        (q.isEmpty || it.batch.toLowerCase().contains(q))
      ).toList();
      
      _results.sort((a, b) {
        final d1 = _parseExpiry(a.expiry) ?? DateTime(2099);
        final d2 = _parseExpiry(b.expiry) ?? DateTime(2099);
        return d1.compareTo(d2);
      });
      
      _selectedIndex = 0;
      if (_overlayEntry == null) {
        _showOverlay();
      } else {
        _overlayEntry?.markNeedsBuild();
      }
    }
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
              } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                _hideOverlay();
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowRight && _overlayEntry == null) {
                final state = context.findAncestorStateOfType<_StockAdjustmentBatchScreenState>();
                final index = state?._rows.indexWhere((r) => r.batchFocus == widget.focusNode);
                if (index != null && index != -1) state?._moveFocus(index, 2);
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft && _overlayEntry == null) {
                final state = context.findAncestorStateOfType<_StockAdjustmentBatchScreenState>();
                final index = state?._rows.indexWhere((r) => r.batchFocus == widget.focusNode);
                if (index != null && index != -1) state?._moveFocus(index, 0);
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowDown && _overlayEntry == null) {
                final state = context.findAncestorStateOfType<_StockAdjustmentBatchScreenState>();
                final index = state?._rows.indexWhere((r) => r.batchFocus == widget.focusNode);
                if (index != null && index != -1) state?._moveFocus(index + 1, 1);
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowUp && _overlayEntry == null) {
                final state = context.findAncestorStateOfType<_StockAdjustmentBatchScreenState>();
                final index = state?._rows.indexWhere((r) => r.batchFocus == widget.focusNode);
                if (index != null && index != -1) state?._moveFocus(index - 1, 1);
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
              if (widget.controller.text.isNotEmpty) {
                widget.controller.selection = TextSelection(baseOffset: 0, extentOffset: widget.controller.text.length);
                _hideOverlay();
              } else {
                _triggerBatchSearch();
              }
            },
            onChanged: (v) {
              if (widget.productId.isNotEmpty) {
                final provider = Provider.of<PharmacyProvider>(context, listen: false);
                final q = v.toLowerCase();
                _results = provider.products.where((it) => 
                  it.id == widget.productId && 
                  it.stock > 0 && 
                  it.batch.toLowerCase().contains(q)
                ).toList();
                _results.sort((a, b) {
                  final d1 = _parseExpiry(a.expiry) ?? DateTime(2099);
                  final d2 = _parseExpiry(b.expiry) ?? DateTime(2099);
                  return d1.compareTo(d2);
                });
                if (_overlayEntry == null) _showOverlay();
                _overlayEntry?.markNeedsBuild();
              }
            },
            onSubmitted: (v) {
              if (_overlayEntry != null && _results.isNotEmpty) { 
                widget.onSelected(_results[_selectedIndex]);
                _hideOverlay();
              }
            },
          ),
        ),
      ),
    );
  }
}

class _HdrSmall extends StatelessWidget {
  final String title; final int flex; final TextAlign align;
  const _HdrSmall(this.title, {required this.flex, this.align = TextAlign.left});
  @override Widget build(BuildContext context) {
    return Expanded(flex: flex, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4), alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.right ? Alignment.centerRight : Alignment.center), child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))));
  }
}

class _CellSmall extends StatelessWidget {
  final String text; final int flex; final TextAlign align; final Color? color; final FontWeight fontWeight;
  const _CellSmall(this.text, {required this.flex, this.align = TextAlign.left, this.color, this.fontWeight = FontWeight.normal});
  @override Widget build(BuildContext context) {
    return Expanded(flex: flex, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4), alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.right ? Alignment.centerRight : Alignment.center), decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade100))), child: Text(text, style: TextStyle(fontSize: 11, color: color ?? Colors.black87, fontWeight: fontWeight), overflow: TextOverflow.ellipsis)));
  }
}
