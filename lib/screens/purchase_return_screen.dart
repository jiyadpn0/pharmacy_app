import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import '../providers/pharmacy_provider.dart';
import '../providers/app_provider.dart';

import 'reports/sales_history_screen.dart';
import 'reports/purchase_history_screen.dart';
import '../windows/window_spawner.dart';
import '../utils/theme_constants.dart';
import '../utils/app_dialogs.dart';
import '../utils/invoice_pdf_generator.dart';
import '../utils/printer_service.dart';
import '../utils/app_formatters.dart';
import '../utils/tax_calculator.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/erp_tooltip.dart';
import '../utils/search_debouncer.dart';
import '../widgets/purchase/purchase_footer.dart';

class PurchaseReturnScreen extends StatefulWidget {
  final String? initialEntryNo;
  final List<Product>? initialExpiredItems;
  const PurchaseReturnScreen({super.key, this.initialEntryNo, this.initialExpiredItems});

  @override
  State<PurchaseReturnScreen> createState() => _PurchaseReturnScreenState();
}

class _PurchaseReturnScreenState extends State<PurchaseReturnScreen> {
  final List<PurchaseReturnItem> _items = [];
  bool _isExistingEntry = false;
  bool _isDeleted = false;

  bool _showSupplierCol = true;
  bool _showInvNoCol = true;
  final bool _showEntryNoCol = false;

  String _entryNo = "";
  PurchaseReturnEntry? _originalLoadedReturn;

  final TextEditingController _supplierCtrl = TextEditingController();
  final TextEditingController _originalInvCtrl = TextEditingController();
  final TextEditingController _remarksCtrl = TextEditingController();
  final TextEditingController _doneByCtrl = TextEditingController();

  DateTime _date = DateTime.now();
  int _gstMode = 1; // 1 = Gst, 2 = Non Gst


  final FocusNode _rootFocus = FocusNode();
  final FocusNode _supplierFocus = FocusNode();
  final FocusNode _originalInvFocus = FocusNode();
  final FocusNode _doneByFocus = FocusNode();

  final FocusNode _remarksFocus = FocusNode();
  final FocusNode _footerDiscPctFocus = FocusNode();
  final FocusNode _footerDiscAmtFocus = FocusNode();
  final FocusNode _otherChargePctFocus = FocusNode();
  final FocusNode _otherChargeAmtFocus = FocusNode();
  final FocusNode _adjustAmtFocus = FocusNode();

  final SearchDebouncer _historyDebouncer = SearchDebouncer(milliseconds: 250);
  final SearchDebouncer _prodSearchDebouncer = SearchDebouncer(milliseconds: 120);
  List<Map<String, dynamic>> _productHistory = [];
  List<Map<String, dynamic>> _salesHistory = [];
  String _historyProductName = "";

  final TextEditingController _subTotalCtrl = TextEditingController(text: "0.00");
  final TextEditingController _footerDiscPctCtrl = TextEditingController(text: "0");
  final TextEditingController _footerDiscAmtCtrl = TextEditingController(text: "0.00");
  final TextEditingController _otherChargePctCtrl = TextEditingController(text: "0");
  final TextEditingController _otherChargeAmtCtrl = TextEditingController(text: "0.00");
  final TextEditingController _roundOffCtrl = TextEditingController(text: "0.00");
  final TextEditingController _adjustAmtCtrl = TextEditingController(text: "0.00");
  final TextEditingController _grandTotalCtrl = TextEditingController(text: "0.00");

  final ValueNotifier<double> _subTotalNotifier = ValueNotifier(0.0);
  final ValueNotifier<double> _grandTotalNotifier = ValueNotifier(0.0);

  final ScrollController _gridScrollCtrl = ScrollController();
  final ScrollController _verticalGridScrollCtrl = ScrollController();
  final ScrollController _dropdownScrollCtrl = ScrollController();

  final Map<int, double> _colWidths = {
    0: 30,   1: 180,  2: 65,   3: 75,   4: 60,   5: 140,  6: 120,  7: 125,
    8: 55,   9: 45,   10: 45,  11: 45,  12: 65,  13: 65,  14: 65,  15: 50,
    16: 65,  17: 65,  18: 50,  19: 75,  20: 80,  21: 30,
  };

  final List<int> _navCols = [1, 3, 8, 9, 10, 11];

  final Map<int, Map<int, TextEditingController>> _gridCtrls = {};
  final Map<int, Map<int, FocusNode>> _gridFocusNodes = {};
  final ValueNotifier<IntPair?> _focusNotifier = ValueNotifier(const IntPair(0, 1));
  int get _focusedRowIndex => _focusNotifier.value?.row ?? -1;
  int get _focusedColIndex => _focusNotifier.value?.col ?? 0;

  final LayerLink _searchLayer = LayerLink();
  final LayerLink _batchLayer = LayerLink();
  final LayerLink _supplierLayer = LayerLink();

  final ValueNotifier<List<Product>> _searchList = ValueNotifier([]);
  final ValueNotifier<List<Product>> _batchList = ValueNotifier([]);
  final ValueNotifier<List<String>> _supplierSearchList = ValueNotifier([]);
  final ValueNotifier<int> _searchIdx = ValueNotifier(0);

  bool _isSelectingBatch = false;
  bool _isSelectingFromDropdown = false;
  bool _isLoading = false;
  bool _isSaving = false;

  final List<List<PurchaseReturnItem>> _undoStack = [];
  final Map<int, Set<int>> _errorCells = {};

  void _markRowError(int row) {
    _errorCells.putIfAbsent(row, () => {});
    for (int c = 0; c <= 21; c++) {
      _errorCells[row]!.add(c);
    }
  }

  bool _isDirty = false;

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

    for (int i = 0; i < _items.length; i++) {
      final it = _items[i];
      final prodName = it.product.name.trim();
      int qty = it.qty;
      final ctrlText = _getGridCtrl(i, 9).text.trim();
      if (ctrlText.isNotEmpty) {
        final parsed = int.tryParse(ctrlText) ?? 0;
        if (parsed > 0) qty = parsed;
      }
      int loose = it.looseQty;
      final looseText = _getGridCtrl(i, 10).text.trim();
      if (looseText.isNotEmpty) {
        final parsedL = int.tryParse(looseText) ?? 0;
        if (parsedL > 0) loose = parsedL;
      }

      if (prodName.isNotEmpty && (qty > 0 || loose > 0 || it.fQty > 0)) {
        return true;
      }
    }

    final activeProdName = _getGridCtrl(_items.length, 1).text.trim();
    final activeQtyText = _getGridCtrl(_items.length, 9).text.trim();
    final activeQty = int.tryParse(activeQtyText) ?? 0;
    final activeLooseText = _getGridCtrl(_items.length, 10).text.trim();
    final activeLoose = int.tryParse(activeLooseText) ?? 0;
    if (activeProdName.isNotEmpty && (activeQty > 0 || activeLoose > 0)) {
      return true;
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
          "You have made changes to this saved return entry.\nIf you leave now, your edits will be lost.\n\nDo you want to discard your changes?",
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
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    Future.microtask(() async {
      final next = await p.getNextPurchaseReturnEntryNo();
      if (mounted) setState(() => _entryNo = next);
    });
    _resetPage();

    if (widget.initialExpiredItems != null && widget.initialExpiredItems!.isNotEmpty) {
      for (var p in widget.initialExpiredItems!) {
        double rate = p.purchaseRate > 0 ? p.purchaseRate : p.salePrice;
        final item = PurchaseReturnItem(product: p)
          ..qty = p.stock
          ..pRate = rate
          ..mrp = p.mrp
          ..sRate = p.salePrice
          ..gstPercent = p.gstPercent
          ..total = p.stock * rate
          ..reason = "EXPIRED STOCK DUMP";
        _items.add(item);
      }
      _remarksCtrl.text = "Batch return draft auto-generated from Expired Stock Track.";
    }

    _footerDiscPctCtrl.addListener(_calculateFooter);
    _footerDiscAmtCtrl.addListener(_calculateFooter);
    _otherChargePctCtrl.addListener(_calculateFooter);
    _otherChargeAmtCtrl.addListener(_calculateFooter);
    _adjustAmtCtrl.addListener(_calculateFooter);

    _footerDiscPctFocus.addListener(_calculateFooter);
    _footerDiscAmtFocus.addListener(_calculateFooter);
    _otherChargePctFocus.addListener(_calculateFooter);
    _otherChargeAmtFocus.addListener(_calculateFooter);
    _adjustAmtFocus.addListener(_calculateFooter);

    _supplierFocus.addListener(() { if (_supplierFocus.hasFocus) _focusNotifier.value = const IntPair(-1, 0); });
    _originalInvFocus.addListener(() { if (_originalInvFocus.hasFocus) _focusNotifier.value = const IntPair(-1, 1); });

    _supplierCtrl.addListener(() {
      final text = _supplierCtrl.text.trim();
      if (text.isNotEmpty) {
        setState(() {
          for (int i = 0; i < _items.length; i++) {
            if (_items[i].supplier.isEmpty) {
              _items[i].supplier = text;
              _getGridCtrl(i, 5, text).text = text;
            }
          }
        });
      }
    });

    _originalInvCtrl.addListener(() {
      final text = _originalInvCtrl.text.trim();
      if (text.isNotEmpty) {
        setState(() {
          for (int i = 0; i < _items.length; i++) {
            if (_items[i].supInvNo.isEmpty) {
              _items[i].supInvNo = cleanInvoiceNo(text);
              _getGridCtrl(i, 6, text).text = cleanInvoiceNo(text);
            }
          }
        });
      }
    });

    _focusNotifier.addListener(() {
      final pair = _focusNotifier.value;
      if (pair != null && pair.row >= 0) {
        String pName = "";
        if (pair.row < _items.length) {
          pName = _items[pair.row].product.name;
        } else {
          pName = _getGridCtrl(pair.row, 1).text;
        }
        if (pName.isNotEmpty) {
          _updateHistory(pName);
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialEntryNo != null) {
        // ---> FIXED: Replaced _loadReturnData with the new _navigateEntry <---
        _navigateEntry('find', searchNo: widget.initialEntryNo);
      } else {
        _supplierFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _gridScrollCtrl.dispose();
    _verticalGridScrollCtrl.dispose();
    _dropdownScrollCtrl.dispose();
    _rootFocus.dispose();
    _supplierFocus.dispose();
    _originalInvFocus.dispose();
    _remarksFocus.dispose();
    _footerDiscPctFocus.dispose();
    _footerDiscAmtFocus.dispose();
    _otherChargePctFocus.dispose();
    _otherChargeAmtFocus.dispose();
    _adjustAmtFocus.dispose();
    _historyDebouncer.dispose();
    _prodSearchDebouncer.dispose();
    _supplierCtrl.dispose();
    _originalInvCtrl.dispose();
    _remarksCtrl.dispose();
    _doneByCtrl.dispose();
    _subTotalCtrl.dispose();
    _footerDiscPctCtrl.dispose();
    _footerDiscAmtCtrl.dispose();
    _otherChargePctCtrl.dispose();
    _otherChargeAmtCtrl.dispose();
    _roundOffCtrl.dispose();
    _adjustAmtCtrl.dispose();
    _grandTotalCtrl.dispose();
    _gridCtrls.forEach((_, m) => m.forEach((_, c) => c.dispose()));
    _gridFocusNodes.forEach((_, m) => m.forEach((_, f) => f.dispose()));
    super.dispose();
  }

  void _saveUndoState() {
    if (!mounted) return;
    _undoStack.add(_items.map((it) => it.clone()).toList());
    if (_undoStack.length > 5) _undoStack.removeAt(0);
  }

  void _performUndo() {
    if (_undoStack.isEmpty) return;
    List<PurchaseReturnItem> lastState = _undoStack.removeLast();
    setState(() {
      _items.clear();
      _errorCells.clear();
      _items.addAll(lastState);
      for (int i = 0; i < _items.length; i++) {
        _calculateItem(i);
      }
    });
  }

  void _deleteRow(int row) {
    if (row < 0 || row >= _items.length) return;
    _saveUndoState();
    setState(() {
      _items.removeAt(row);
      _gridCtrls.clear();
      _gridFocusNodes.clear();
      _errorCells.clear();
      _calculateFooter();
    });
    if (_items.isNotEmpty) {
      int nextRow = row >= _items.length ? _items.length - 1 : row;
      _moveFocus(nextRow, _focusedColIndex > 0 ? _focusedColIndex : 1);
    } else {
      _moveFocus(-1, 0);
    }
  }

  TextEditingController _getGridCtrl(int row, int col, [String init = ""]) {
    _gridCtrls.putIfAbsent(row, () => {});
    if (!_gridCtrls[row]!.containsKey(col)) {
      _gridCtrls[row]![col] = TextEditingController(text: init);
    }
    else if (init.isNotEmpty && _gridCtrls[row]![col]!.text.isEmpty) {
      if (!_getGridFocusNode(row, col).hasFocus) {
        _gridCtrls[row]![col]!.text = init;
      }
    }

    return _gridCtrls[row]![col]!;
  }

  FocusNode _getGridFocusNode(int row, int col) {
    _gridFocusNodes.putIfAbsent(row, () => {});
    if (!_gridFocusNodes[row]!.containsKey(col)) {
      final fn = FocusNode();
      fn.addListener(() {
        if (fn.hasFocus) {
          if (_focusNotifier.value?.row != row || _focusNotifier.value?.col != col) {
            _focusNotifier.value = IntPair(row, col);
            final ctrl = _getGridCtrl(row, col);
            ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
          }
        } else {
          _onBlur(row, col, _getGridFocusNode(row, col).hasFocus ? _getGridCtrl(row, col).text : _getGridCtrl(row, col).text);
        }
      });
      _gridFocusNodes[row]![col] = fn;
    }
    return _gridFocusNodes[row]![col]!;
  }

  void _onBlur(int row, int col, String value) {
    if (row < _items.length) {
      final it = _items[row];

      if (col == 1) {
        if (value.trim().isNotEmpty && it.product.id.isEmpty) {
          final p = Provider.of<PharmacyProvider>(context, listen: false);
          final matches = p.searchProducts(value.trim(), includeGenerics: false);
          if (matches.isNotEmpty) {
            final best = matches.first;
            it.product = Product(id: best.id, name: best.name, batch: best.batch, expiry: best.expiry, packSize: best.packSize, mrp: best.mrp, purchaseRate: best.purchaseRate, salePrice: best.salePrice, gstPercent: best.gstPercent, rack: best.rack, category: best.category, manufacturer: best.manufacturer, supplier: best.supplier, genericName: best.genericName, hsnCode: best.hsnCode)..stock = best.stock;
            it.hsncode = best.hsnCode;
            _getGridCtrl(row, 1).text = best.name;
            _getGridCtrl(row, 2).text = best.hsnCode;
          }
        }
      }

      if (col == 3) {
        it.product.batch = value.trim();
        _fetchBatchPurchaseDetails(row, it.product.name, it.product.id, it.product.batch);
      } else if (col == 5) {
        it.supplier = value.trim();
      } else if (col == 6) {
        it.supInvNo = cleanInvoiceNo(value);
      }

      if ([8, 9, 10, 11, 12, 13, 15, 18].contains(col)) {
        String val = value.trim().isEmpty ? "0" : value;
        if (col == 8) {
          it.packin = double.tryParse(val)?.toInt() ?? 1;
        } else if (col == 9) {
          it.qty = double.tryParse(val)?.toInt() ?? 0;
        } else if (col == 10) {
          it.looseQty = double.tryParse(val)?.toInt() ?? 0;
        } else if (col == 11) {
          it.fQty = double.tryParse(val)?.toInt() ?? 0;
        } else if (col == 12) {
          it.pRate = double.tryParse(val) ?? 0.0;
        } else if (col == 13) {
          it.mrp = double.tryParse(val) ?? 0.0;
        } else if (col == 15) {
          it.discPercent = double.tryParse(val) ?? 0.0;
        } else if (col == 18) {
          it.gstPercent = TaxCalculator.roundGstPercent(double.tryParse(val) ?? 0.0);
        }

        _calculateItem(row);
      }
    }
  }

  void _closeAllDropdowns() {
    _searchList.value = [];
    _batchList.value = [];
    _supplierSearchList.value = [];
  }

  void _moveFocus(int row, int col, {bool autoOpen = false}) {
    int safeRow = row.clamp(-1, _items.length);
    int safeCol = col;
    if (safeRow >= 0 && !_navCols.contains(col)) {
      if (col < _navCols.first) {
        safeCol = _navCols.first;
      } else if (col > _navCols.last) safeCol = _navCols.last;
      else {
        safeCol = _navCols.reduce((a, b) => (a - col).abs() < (b - col).abs() ? a : b);
      }
    }

    if (safeCol != 1 && safeCol != 3) {
      _closeAllDropdowns();
    }

    setState(() {
      _isSelectingBatch = (safeCol == 3);
    });

    _focusNotifier.value = IntPair(safeRow, safeCol);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (safeRow == -1) {
        final fn = safeCol == 0 ? _supplierFocus : (safeCol == 1 ? _originalInvFocus : _doneByFocus);
        final ctrl = safeCol == 0 ? _supplierCtrl : (safeCol == 1 ? _originalInvCtrl : _doneByCtrl);
        if (!fn.hasFocus) {
          fn.requestFocus();
          ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
        }
      } else {
        final fn = _getGridFocusNode(safeRow, safeCol);
        final ctrl = _getGridCtrl(safeRow, safeCol);
        final initialText = ctrl.text;

        fn.requestFocus();
        if (initialText.isNotEmpty) {
          ctrl.selection = TextSelection(baseOffset: 0, extentOffset: initialText.length);
        }

        if (autoOpen || safeCol == 3) {
          if (safeCol == 1 && initialText.trim().isEmpty) {
            _startProductSearch("");
          } else if (safeCol == 3) {
            _startBatchSearch(safeRow, "");
          }
        }
      }
    });
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyUpEvent) return false;
    final key = event.logicalKey;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;

    if (key == LogicalKeyboardKey.f6) {
      if (!_isDeleted) _saveReturn(isEdit: _isExistingEntry);
      return true;
    }
    if (key == LogicalKeyboardKey.f2) {
      _navigateEntry('next');
      return true;
    }

    if (isCtrl) {
      if (key == LogicalKeyboardKey.digit1) {
        String pName = _getActiveProductName();
        if (pName.trim().isNotEmpty) _openHistoryWindow(pName.trim(), false);
        return true;
      }
      if (key == LogicalKeyboardKey.digit2) {
        String pName = _getActiveProductName();
        if (pName.trim().isNotEmpty) _openHistoryWindow(pName.trim(), true);
        return true;
      }
      if (key == LogicalKeyboardKey.keyZ) {
        _performUndo();
        return true;
      }
      if (key == LogicalKeyboardKey.delete && _focusedRowIndex >= 0 && _focusedRowIndex < _items.length) {
        _deleteRow(_focusedRowIndex);
        return true;
      }
    }

    final isOverlayOpen = _searchList.value.isNotEmpty || _batchList.value.isNotEmpty || _supplierSearchList.value.isNotEmpty;
    if (isOverlayOpen) {
      final list = _supplierSearchList.value.isNotEmpty ? _supplierSearchList.value : (_isSelectingBatch ? _batchList.value : _searchList.value);
      if (key == LogicalKeyboardKey.arrowDown) {
        _searchIdx.value = (_searchIdx.value + 1) % list.length;
        return true;
      } else if (key == LogicalKeyboardKey.arrowUp) {
        _searchIdx.value = (_searchIdx.value - 1 + list.length) % list.length;
        return true;
      } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
        if (list.isNotEmpty) {
          if (_supplierSearchList.value.isNotEmpty) {
            _onSupplierSelected(_supplierSearchList.value[_searchIdx.value]);
          } else if (_isSelectingBatch) _finalizeBatchSelection(list[_searchIdx.value] as Product);
          else _onProductSelected(list[_searchIdx.value] as Product);
          return true;
        }
      }
    }

    int row = _focusedRowIndex;
    int col = _focusedColIndex;

    if (row == -1) {
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.tab) {
        if (col == 0) {
          _moveFocus(-1, 2);
        } else {
          _moveFocus(_items.length, 1, autoOpen: true);
        }
        return true;
      }
      return false;
    }

    final ctrl = _getGridCtrl(row, col);

    if ((key == LogicalKeyboardKey.tab || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) && isShift) {
      int curIdx = _navCols.indexOf(col);
      if (curIdx > 0) {
        _moveFocus(row, _navCols[curIdx - 1]);
      } else if (row > 0) _moveFocus(row - 1, _navCols.last);
      return true;
    }

    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.tab) {
      _onFieldSubmitted(row, col);
      return true;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      int curIdx = _navCols.indexOf(col);
      if (curIdx > 0) { _moveFocus(row, _navCols[curIdx - 1]); return true; }
      else if (row > 0) { _moveFocus(row - 1, _navCols.last); return true; }
    }

    if (key == LogicalKeyboardKey.arrowRight && (!ctrl.selection.isValid || ctrl.selection.baseOffset >= ctrl.text.length)) {
      int curIdx = _navCols.indexOf(col);
      if (curIdx != -1 && curIdx < _navCols.length - 1) { _moveFocus(row, _navCols[curIdx + 1]); return true; }
      else if (row < _items.length) { _moveFocus(_items.length, _navCols[0]); return true; }
    }

    if (key == LogicalKeyboardKey.arrowDown && row < _items.length) { _moveFocus(row + 1, col); return true; }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (row > 0) {
        _moveFocus(row - 1, col);
      } else {
        _moveFocus(-1, 0);
      }
      return true;
    }

    return false;
  }

  void _onFieldSubmitted(int row, int col) {
    if (col == 1) {
      String typedText = _getGridCtrl(row, 1).text.trim();
      if (_searchList.value.isNotEmpty) {
        _onProductSelected(_searchList.value[_searchIdx.value]);
      } else if (typedText.isNotEmpty) {
        final p = Provider.of<PharmacyProvider>(context, listen: false);
        final matches = p.searchProducts(typedText, includeGenerics: false);
        if (matches.isNotEmpty) {
          _onProductSelected(matches.first);
        } else {
          _moveFocus(row, 3, autoOpen: true);
        }
      }
    } else if (col == 3) {
      String typed = _getGridCtrl(row, 3).text.trim().toUpperCase();
      if (_batchList.value.isNotEmpty) {
        final exactIdx = _batchList.value.indexWhere((b) => b.batch.toUpperCase() == typed);
        _finalizeBatchSelection(_batchList.value[exactIdx != -1 ? exactIdx : _searchIdx.value]);
      } else {
        _moveFocus(row, 8);
      }
    } else {
      int curIdx = _navCols.indexOf(col);
      if (curIdx != -1 && curIdx < _navCols.length - 1) {
        _moveFocus(row, _navCols[curIdx + 1]);
      } else {
        _moveFocus(_items.length, 1, autoOpen: true);
      }
    }
  }

  void _startSupplierSearch(String q) {
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final query = q.trim().toLowerCase();
    if (query.isEmpty) { _supplierSearchList.value = []; }
    else {
      final all = p.suppliers.where((s) => s.toLowerCase().contains(query)).toList()..sort();
      _supplierSearchList.value = all.take(20).toList();
    }
    _searchIdx.value = 0;
  }

  void _onSupplierSelected(String name) {
    setState(() { _supplierCtrl.text = name; _supplierSearchList.value = []; });
    _originalInvFocus.requestFocus();
  }

  bool _isExactProductMatch(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return false;
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    return p.products.any((prod) => prod.name.trim().toLowerCase() == q);
  }

  bool _isExactBatchMatch(int row, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return false;
    if (row < 0 || row >= _items.length) return false;
    final it = _items[row];
    return it.product.batch.trim().toLowerCase() == q;
  }

  void _startProductSearch(String q) {
    setState(() => _isSelectingBatch = false);
    final trimmed = q.trim().toLowerCase();

    if (trimmed.isEmpty) {
      _searchList.value = [];
      _searchIdx.value = 0;
      return;
    }

    _prodSearchDebouncer.run(() {
      if (!mounted) return;
      final p = Provider.of<PharmacyProvider>(context, listen: false);
      final results = p.searchProducts(trimmed, includeGenerics: false);

      _searchList.value = results.take(50).toList();
      _searchIdx.value = 0;
    });
  }

  DateTime _parseExpiry(String exp) {
    if (!exp.contains('/')) return DateTime(2099);
    final parts = exp.split('/');
    int m = int.tryParse(parts[0]) ?? 1;
    int y = int.tryParse(parts[1]) ?? 99;
    if (y < 100) y += 2000;
    return DateTime(y, m + 1, 0);
  }

  void _startBatchSearch(int row, String q) {
    if (!_isSelectingBatch) setState(() => _isSelectingBatch = true);
    _searchList.value = [];
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    String prodName = row < _items.length ? _items[row].product.name : _getGridCtrl(row, 1).text;

    final trimmed = q.trim().toLowerCase();
    if (prodName.isEmpty) { _batchList.value = []; return; }

    final all = p.products.where((it) => it.name.toLowerCase() == prodName.toLowerCase()).toList();
    final rawMatches = trimmed.isEmpty ? all : all.where((b) => b.batch.toLowerCase().contains(trimmed)).toList();

    rawMatches.sort((a, b) {
      int expComp = _parseExpiry(a.expiry).compareTo(_parseExpiry(b.expiry));
      if (expComp != 0) return expComp;
      return b.stock.compareTo(a.stock);
    });
    _batchList.value = rawMatches;
    _searchIdx.value = 0;
  }

  Future<void> _fetchBatchPurchaseDetails(int row, String productName, String productId, String batch) async {
    if (productName.trim().isEmpty) return;
    
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final info = await p.getBatchPurchaseMetadata(productName, productId: productId, batch: batch);
    
    if (!mounted || row >= _items.length) return;
    
    final it = _items[row];
    
    String foundSupplier = info['supplier'] ?? '';
    if (foundSupplier.isEmpty && _supplierCtrl.text.isNotEmpty) {
      foundSupplier = _supplierCtrl.text.trim();
    }
    if (foundSupplier.isEmpty && it.supplier.isNotEmpty) {
      foundSupplier = it.supplier;
    }
    
    String foundInvNo = info['inv_no'] ?? '';
    if (foundInvNo.isEmpty && _originalInvCtrl.text.isNotEmpty) {
      foundInvNo = _originalInvCtrl.text.trim();
    }
    if (foundInvNo.isEmpty && it.supInvNo.isNotEmpty) {
      foundInvNo = it.supInvNo;
    }
    
    double foundPRate = (info['p_rate'] as num?)?.toDouble() ?? 0.0;
    double foundMrp = (info['mrp'] as num?)?.toDouble() ?? 0.0;
    double foundGst = (info['gst_percent'] as num?)?.toDouble() ?? 0.0;
    double foundDisc = (info['disc_percent'] as num?)?.toDouble() ?? 0.0;

    setState(() {
      if (foundSupplier.isNotEmpty) {
        it.supplier = foundSupplier;
        _getGridCtrl(row, 5, foundSupplier).text = foundSupplier;
      }
      if (foundInvNo.isNotEmpty) {
        it.supInvNo = foundInvNo;
        _getGridCtrl(row, 6, foundInvNo).text = foundInvNo;
      }
      if (foundPRate > 0) {
        it.pRate = foundPRate;
        _getGridCtrl(row, 12, foundPRate.toStringAsFixed(2)).text = foundPRate.toStringAsFixed(2);
      }
      if (it.mrp <= 0 && foundMrp > 0) {
        it.mrp = foundMrp;
        _getGridCtrl(row, 13, foundMrp.toStringAsFixed(2)).text = foundMrp.toStringAsFixed(2);
      }
      if (foundDisc > 0) {
        it.discPercent = foundDisc;
        _getGridCtrl(row, 15, foundDisc.toStringAsFixed(2)).text = foundDisc.toStringAsFixed(2);
      }
      if (it.gstPercent <= 0 && foundGst > 0) {
        it.gstPercent = TaxCalculator.roundGstPercent(foundGst);
        double g = it.gstPercent;
        String gStr = g % 1 == 0 ? g.toInt().toString() : g.toStringAsFixed(1);
        _getGridCtrl(row, 18, gStr).text = gStr;
      }
      _calculateItem(row);
    });
  }

  void _onProductSelected(Product p) {
    _saveUndoState();
    final row = _focusedRowIndex;
    setState(() {
      _getGridCtrl(row, 1, p.name).text = p.name;
      _getGridCtrl(row, 2, p.hsnCode).text = p.hsnCode;

      String sup = p.supplier.isNotEmpty ? p.supplier : _supplierCtrl.text.trim();
      String inv = _originalInvCtrl.text.trim();

      if (row == _items.length) {
        _items.add(PurchaseReturnItem(product: Product(id: p.id, name: p.name)..packSize = p.packSize..hsnCode = p.hsnCode)
          ..hsncode = p.hsnCode
          ..supplier = sup
          ..supInvNo = cleanInvoiceNo(inv)
          ..qty = 0
          ..packin = p.packSize > 0 ? p.packSize : 1
          ..mrp = p.mrp
          ..pRate = p.purchaseRate
          ..gstPercent = p.gstPercent
        );
      } else {
        final it = _items[row];
        it.product = Product(id: p.id, name: p.name)..packSize = p.packSize..hsnCode = p.hsnCode;
        it.hsncode = p.hsnCode;
        if (sup.isNotEmpty) it.supplier = sup;
        if (inv.isNotEmpty) it.supInvNo = cleanInvoiceNo(inv);
        it.packin = p.packSize > 0 ? p.packSize : 1;
        if (p.mrp > 0) it.mrp = p.mrp;
        if (p.purchaseRate > 0) it.pRate = p.purchaseRate;
        if (p.gstPercent > 0) it.gstPercent = p.gstPercent;
      }
      _getGridCtrl(row, 5, sup).text = sup;
      _getGridCtrl(row, 6, inv).text = inv;
    });
    _searchList.value = [];
    _fetchBatchPurchaseDetails(row, p.name, p.id, p.batch);
    _moveFocus(_focusedRowIndex, 3, autoOpen: true);
  }

  void _finalizeBatchSelection(Product p) {
    final row = _focusedRowIndex;
    setState(() {
      _getGridCtrl(row, 3, cleanBatch(p.batch)).text = cleanBatch(p.batch);
      _getGridCtrl(row, 4, p.expiry).text = p.expiry;

      if (row < _items.length) {
        final it = _items[row];
        it.product.batch = p.batch;
        it.product.expiry = p.expiry;
        if (p.supplier.isNotEmpty) it.supplier = p.supplier;
        if (it.supplier.isEmpty && _supplierCtrl.text.isNotEmpty) it.supplier = _supplierCtrl.text.trim();
        if (it.supInvNo.isEmpty && _originalInvCtrl.text.isNotEmpty) it.supInvNo = cleanInvoiceNo(_originalInvCtrl.text);
        it.product.stock = p.stock;
        it.packin = p.packSize > 0 ? p.packSize : 1;
        if (p.mrp > 0) it.mrp = p.mrp;
        if (p.purchaseRate > 0) it.pRate = p.purchaseRate;
        if (p.gstPercent > 0) it.gstPercent = p.gstPercent;

        _getGridCtrl(row, 5, it.supplier).text = it.supplier;
        _getGridCtrl(row, 6, it.supInvNo).text = it.supInvNo;
        _getGridCtrl(row, 8).text = it.packin.toString();
        _getGridCtrl(row, 12).text = it.pRate.toStringAsFixed(2);
        _getGridCtrl(row, 13).text = it.mrp.toStringAsFixed(2);
        _calculateItem(row);
      }
    });
    _batchList.value = [];
    if (row < _items.length) {
      _fetchBatchPurchaseDetails(row, _items[row].product.name, _items[row].product.id, p.batch);
    }
    _moveFocus(_focusedRowIndex, 8);
  }

  void _calculateItem(int row) {
    if (row >= _items.length) return;
    final it = _items[row];
    
    double ps = it.packin > 0 ? it.packin.toDouble() : 1.0;
    double stripValue = it.pRate * it.qty;
    double looseValue = (it.pRate / ps) * it.looseQty;
    
    it.gross = double.parse((stripValue + looseValue).toStringAsFixed(2));
    it.discAmt = double.parse((it.gross * (it.discPercent / 100.0)).toStringAsFixed(2));
    it.net = double.parse((it.gross - it.discAmt).toStringAsFixed(2));

    it.gstPercent = TaxCalculator.roundGstPercent(it.gstPercent);
    if (_gstMode == 1 && it.gstPercent > 0) {
      it.gstAmt = double.parse((it.net * (it.gstPercent / 100.0)).toStringAsFixed(2));
      it.total = double.parse((it.net + it.gstAmt).toStringAsFixed(2));
    } else {
      it.gstAmt = 0.0;
      it.total = double.parse(it.net.toStringAsFixed(2));
    }

    _getGridCtrl(row, 14, it.gross.toStringAsFixed(2)).text = it.gross.toStringAsFixed(2);
    _getGridCtrl(row, 15, it.discPercent.toStringAsFixed(2)).text = it.discPercent.toStringAsFixed(2);
    _getGridCtrl(row, 16, it.net.toStringAsFixed(2)).text = it.net.toStringAsFixed(2);
    _getGridCtrl(row, 17, it.gstAmt.toStringAsFixed(2)).text = it.gstAmt.toStringAsFixed(2);
    _getGridCtrl(row, 19, it.total.toStringAsFixed(2)).text = it.total.toStringAsFixed(2);
    _calculateFooter();
  }

  void _calculateFooter() {
    double sub = _items.fold(0, (s, i) => s + i.total);

    if (_footerDiscPctFocus.hasFocus) {
      double pct = double.tryParse(_footerDiscPctCtrl.text) ?? 0;
      String amtStr = _fmt(sub * (pct / 100));
      if (_footerDiscAmtCtrl.text != amtStr) _footerDiscAmtCtrl.text = amtStr;
    } else if (_footerDiscAmtFocus.hasFocus) {
      double amt = double.tryParse(_footerDiscAmtCtrl.text) ?? 0;
      if (sub > 0) {
        String pctStr = _fmt((amt / sub) * 100);
        if (_footerDiscPctCtrl.text != pctStr) _footerDiscPctCtrl.text = pctStr;
      }
    } else {
      double pct = double.tryParse(_footerDiscPctCtrl.text) ?? 0;
      String amtStr = _fmt(sub * (pct / 100));
      if (_footerDiscAmtCtrl.text != amtStr) _footerDiscAmtCtrl.text = amtStr;
    }

    if (_otherChargeAmtFocus.hasFocus) {
      double amt = double.tryParse(_otherChargeAmtCtrl.text) ?? 0;
      if (sub > 0) {
        String pctStr = _fmt((amt / sub) * 100);
        if (_otherChargePctCtrl.text != pctStr) _otherChargePctCtrl.text = pctStr;
      }
    } else {
      double pct = double.tryParse(_otherChargePctCtrl.text) ?? 0;
      String amtStr = _fmt(sub * (pct / 100));
      if (_otherChargeAmtCtrl.text != amtStr) _otherChargeAmtCtrl.text = amtStr;
    }

    double discAmt = double.tryParse(_footerDiscAmtCtrl.text) ?? 0;
    double otherAmt = double.tryParse(_otherChargeAmtCtrl.text) ?? 0;
    double adjust = double.tryParse(_adjustAmtCtrl.text) ?? 0;

    double finalVal = sub - discAmt + otherAmt + adjust;
    double rounded = finalVal.roundToDouble();
    double roundOff = rounded - finalVal;

    _subTotalNotifier.value = sub;
    _grandTotalNotifier.value = rounded;

    _subTotalCtrl.text = _fmt(sub);
    _roundOffCtrl.text = _fmt(roundOff);
    _grandTotalCtrl.text = _fmt(rounded);
  }

  // --- GENERATE DETAILED EDIT DIFF SPANS FOR RE-WRITE DIALOG ---
  List<InlineSpan> _generateDiffSpans() {
    final List<InlineSpan> diffSpans = [];

    if (!_isExistingEntry || _originalLoadedReturn == null) {
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
    // Supplier Name
    final currentSupplier = _supplierCtrl.text.trim();
    final origSupplier = _originalLoadedReturn!.supplierName.trim();
    if (currentSupplier.toUpperCase() != origSupplier.toUpperCase()) {
      addDiffLine([
        const TextSpan(text: "supplier name ", style: normalStyle),
        TextSpan(text: origSupplier.isEmpty ? "(blank)" : origSupplier, style: redStyle),
        const TextSpan(text: " to ", style: normalStyle),
        TextSpan(text: currentSupplier.isEmpty ? "(blank)" : currentSupplier, style: redStyle),
        const TextSpan(text: ".", style: normalStyle),
      ]);
    }

    // Ref Purchase Inv No
    final currentRefNo = _originalInvCtrl.text.trim();
    final origRefNo = _originalLoadedReturn!.originalPurchaseNo.trim();
    if (currentRefNo.toUpperCase() != origRefNo.toUpperCase()) {
      addDiffLine([
        const TextSpan(text: "ref purchase no ", style: normalStyle),
        TextSpan(text: origRefNo.isEmpty ? "(blank)" : origRefNo, style: redStyle),
        const TextSpan(text: " to ", style: normalStyle),
        TextSpan(text: currentRefNo.isEmpty ? "(blank)" : currentRefNo, style: redStyle),
        const TextSpan(text: ".", style: normalStyle),
      ]);
    }

    // Done By
    final currentDoneBy = _doneByCtrl.text.trim();
    final origDoneBy = _originalLoadedReturn!.doneBy.trim();
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
    final origItems = _originalLoadedReturn!.items;
    final currentValidItems = _items.where((it) => it.product.name.trim().isNotEmpty && (it.qty > 0 || it.looseQty > 0)).toList();

    int maxLen = origItems.length > currentValidItems.length ? origItems.length : currentValidItems.length;

    for (int i = 0; i < maxLen; i++) {
      if (i < origItems.length && i < currentValidItems.length) {
        final orig = origItems[i];
        final curr = currentValidItems[i];

        // Product Name
        final origName = orig.productName.trim();
        final currName = curr.product.name.trim();
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
        final origBatch = orig.batch.trim();
        final currBatch = curr.product.batch.trim();
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
        if (orig.qty != curr.qty) {
          addDiffLine([
            TextSpan(text: "qty ($currName) changed from ", style: normalStyle),
            TextSpan(text: "${orig.qty}", style: redStyle),
            const TextSpan(text: " to ", style: normalStyle),
            TextSpan(text: "${curr.qty}", style: redStyle),
            const TextSpan(text: ".", style: normalStyle),
          ]);
        }

        // Purchase Rate
        if ((orig.pRate - curr.pRate).abs() > 0.01) {
          addDiffLine([
            TextSpan(text: "purchase rate ($currName) changed from ", style: normalStyle),
            TextSpan(text: "₹${orig.pRate.toStringAsFixed(2)}", style: redStyle),
            const TextSpan(text: " to ", style: normalStyle),
            TextSpan(text: "₹${curr.pRate.toStringAsFixed(2)}", style: redStyle),
            const TextSpan(text: ".", style: normalStyle),
          ]);
        }

        // Discount %
        if ((orig.discPercent - curr.discPercent).abs() > 0.01) {
          addDiffLine([
            TextSpan(text: "discount ($currName) changed from ", style: normalStyle),
            TextSpan(text: "${orig.discPercent.toStringAsFixed(1)}%", style: redStyle),
            const TextSpan(text: " to ", style: normalStyle),
            TextSpan(text: "${curr.discPercent.toStringAsFixed(1)}%", style: redStyle),
            const TextSpan(text: ".", style: normalStyle),
          ]);
        }
      } else if (i < currentValidItems.length) {
        final curr = currentValidItems[i];
        addDiffLine([
          const TextSpan(text: "added product ", style: normalStyle),
          TextSpan(text: curr.product.name.trim(), style: redStyle),
          const TextSpan(text: " (qty: ", style: normalStyle),
          TextSpan(text: "${curr.qty}", style: redStyle),
          if (curr.product.batch.isNotEmpty) ...[
            const TextSpan(text: ', batch: "', style: normalStyle),
            TextSpan(text: curr.product.batch.trim(), style: redStyle),
            const TextSpan(text: '"', style: normalStyle),
          ],
          const TextSpan(text: ").", style: normalStyle),
        ]);
      } else if (i < origItems.length) {
        final orig = origItems[i];
        addDiffLine([
          const TextSpan(text: "removed product ", style: normalStyle),
          TextSpan(text: orig.productName.trim(), style: redStyle),
          const TextSpan(text: " (qty: ", style: normalStyle),
          TextSpan(text: "${orig.qty}", style: redStyle),
          const TextSpan(text: ").", style: normalStyle),
        ]);
      }
    }

    return diffSpans;
  }

  void _saveReturn({bool isEdit = false}) async {
    if (_isSaving || _isLoading) return;
    _isSaving = true;

    try {
      final p = Provider.of<PharmacyProvider>(context, listen: false);

      final supplierInput = _supplierCtrl.text.trim();
      if (supplierInput.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Please select a proper Wholesaler / Supplier from the dropdown list."),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
        AppDialogs.showFastDialog(
          context: context,
          title: "Wholesaler Required",
          content: "Please select a proper Wholesaler / Supplier from the dropdown list before saving.",
        );
        _supplierFocus.requestFocus();
        return;
      }

      final validSupplier = p.suppliers.firstWhere(
        (s) => s.trim().toLowerCase() == supplierInput.toLowerCase(),
        orElse: () => "",
      );

      if (validSupplier.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("'$supplierInput' is not a valid Wholesaler. Please select a registered Wholesaler from the dropdown list."),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
        AppDialogs.showFastDialog(
          context: context,
          title: "Invalid Wholesaler",
          content: "The Wholesaler / Supplier '$supplierInput' is not selected from the dropdown list. Please select a valid Wholesaler from the dropdown before saving.",
        );
        _supplierFocus.requestFocus();
        return;
      }

      setState(() => _errorCells.clear());
      List<String> errors = [];

      for (int i = 0; i < _items.length; i++) {
        final it = _items[i];
        if (it.product.name.trim().isEmpty) continue;

        if (it.product.batch.trim().isEmpty) {
          errors.add("Row ${i + 1}: Batch required");
          _markRowError(i);
        }
        if (it.qty <= 0 && it.looseQty <= 0) {
          errors.add("Row ${i + 1}: Return quantity must be greater than 0");
          _markRowError(i);
        }
      }

      if (errors.isNotEmpty) {
        setState(() {});
        AppDialogs.showFastDialog(context: context, title: "Validation Error", content: errors.join("\n"));
        return;
      }

      final validItems = _items.where((it) => it.product.name.trim().isNotEmpty && (it.qty > 0 || it.looseQty > 0)).toList();
      if (validItems.isEmpty) {
        AppDialogs.showFastDialog(context: context, title: "No Items", content: "Please enter at least one valid item to return.");
        return;
      }

      final double totalAmount = _grandTotalNotifier.value;
      if (totalAmount < 1.0) {
        AppDialogs.showFastDialog(context: context, title: "Invalid Total", content: "Grand total must be at least ₹1.00.");
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
                "No modifications were detected on Return PRET-$_entryNo.\nThere are no changes to save.",
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
                    "Re-write Return PRET-$_entryNo?",
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
                    "The following changes will be applied to this purchase return:",
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
                    "Are you sure you want to overwrite Return PRET-$_entryNo? Stock will be updated accordingly.",
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

      setState(() => _isLoading = true);

      final entry = PurchaseReturnEntry(
        entryNo: isEdit ? _entryNo : "",
        date: _date,
        supplierName: validSupplier,
        originalPurchaseNo: _originalInvCtrl.text.trim(),
        doneBy: _doneByCtrl.text.trim().isEmpty ? "Admin" : _doneByCtrl.text.trim(),
        gstMode: _gstMode,
        items: validItems.map((it) => PurchaseItem(
          productName: it.product.name, batch: it.product.batch, expiry: it.product.expiry,
          packin: it.packin, qty: it.qty, looseQty: it.looseQty, fQty: it.fQty,
          pRate: it.pRate, mrp: it.mrp,
          gross: it.gross, discPercent: it.discPercent, discAmt: it.discAmt,
          net: it.net, gstPercent: it.gstPercent, gstAmt: it.gstAmt, total: it.total,
          reason: it.reason, supplier: it.supplier, supInvNo: it.supInvNo, hsnCode: it.hsncode,
        )).toList(),
        grandTotal: totalAmount,
      );

      final assignedNo = await p.savePurchaseReturn(entry, isEdit: isEdit);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isEdit ? "Return $assignedNo Updated!" : "Return $assignedNo Saved!"),
          backgroundColor: Colors.green.shade800,
        ));
        _isDirty = false;
        _resetPage();
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) {
        AppDialogs.showFastDialog(context: context, title: "Save Blocked", content: e.toString());
      }
    } finally {
      _isSaving = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateEntry(String dir, {String? searchNo}) async {
    // ---> THE FIX: Protect against losing unsaved edits <---
    if (_isExistingEntry && _isDirty) {
      bool? discard = await _promptDiscardChanges();
      if (discard != true) return; // User chose to stay
    }

    _closeAllDropdowns();
    if (!mounted) return;
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    setState(() => _isLoading = true);

    try {
      String targetNo = searchNo ?? _entryNo;
      final data = await p.navigateInvoice(targetNo, dir, isPurchaseReturn: true);
      
      if (data != null && data['is_deleted'] != 1 && mounted) {
        String actualNo = data['entry_no']?.toString() ?? targetNo;
        final items = await p.getInvoiceItems(actualNo, isPurchaseReturn: true);

        setState(() {
          _isExistingEntry = true;
          _isDeleted = false;
          _isDirty = false; // Freshly loaded, reset dirty flag
          String cleanNo = actualNo.startsWith("PRET-") ? actualNo.substring(5) : actualNo;
          if (cleanNo.contains('_')) {
            cleanNo = cleanNo.substring(cleanNo.indexOf('_') + 1);
          }
          _entryNo = cleanNo;
          _date = DateTime.tryParse(data['date'].toString()) ?? DateTime.now();
          _supplierCtrl.text = data['supplier_name']?.toString() ?? '';
          _originalInvCtrl.text = data['original_purchase_no']?.toString() ?? '';
          _doneByCtrl.text = data['done_by']?.toString() ?? '';
          _gstMode = (data['gst_mode'] as num?)?.toInt() ?? 1;

          _items.clear();
          _gridCtrls.clear();
          _gridFocusNodes.clear();

          for (var m in items) {
            _items.add(PurchaseReturnItem(product: Product(id: '', name: m['product_name'] ?? '', batch: m['batch'] ?? ''))
              ..hsncode = m['hsn_code'] ?? ''
              ..qty = m['qty'] ?? 0
              ..looseQty = m['loose_qty'] ?? 0
              ..packin = m['packin'] ?? 1
              ..pRate = (m['p_rate'] ?? 0).toDouble()
              ..mrp = (m['mrp'] ?? 0).toDouble()
              ..discPercent = (m['disc_percent'] ?? 0).toDouble()
              ..gstPercent = (m['gst_percent'] ?? 0).toDouble()
              ..reason = m['reason'] ?? ''
              ..supplier = m['supplier'] ?? ''
              ..supInvNo = cleanInvoiceNo(m['sup_inv_no'])
              ..total = (m['total'] ?? 0).toDouble()
            );
          }
          for (int i = 0; i < _items.length; i++) {
            _calculateItem(i);
          }

          _calculateFooter();

          _originalLoadedReturn = PurchaseReturnEntry(
            entryNo: _entryNo,
            date: _date,
            supplierName: _supplierCtrl.text.trim(),
            originalPurchaseNo: _originalInvCtrl.text.trim(),
            doneBy: _doneByCtrl.text.trim().isEmpty ? "Admin" : _doneByCtrl.text.trim(),
            gstMode: _gstMode,
            items: _items.where((it) => it.product.name.trim().isNotEmpty).map((it) => PurchaseItem(
              productName: it.product.name,
              batch: it.product.batch,
              expiry: it.product.expiry,
              packin: it.packin,
              qty: it.qty,
              looseQty: it.looseQty,
              pRate: it.pRate,
              mrp: it.mrp,
              discPercent: it.discPercent,
              discAmt: it.discAmt,
              total: it.total,
            )).toList(),
            grandTotal: _grandTotalNotifier.value,
          );
        });
      } else if (dir == 'next') {
        if (_isExistingEntry) _resetPage();
      }
    } catch (e) {
      debugPrint("Load Purchase Return Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _resetPage() async {
    // ---> THE FIX: Protect against losing unsaved edits <---
    if (_isExistingEntry && _isDirty) {
      bool? discard = await _promptDiscardChanges();
      if (!mounted) return;
      if (discard != true) return; // User chose to stay
    }

    if (!mounted) return;
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    _closeAllDropdowns();
    FocusScope.of(context).unfocus();

    for (var m in _gridCtrls.values) {
      for (var c in m.values) { c.dispose(); }
    }
    for (var m in _gridFocusNodes.values) {
      for (var f in m.values) { f.dispose(); }
    }
    _gridCtrls.clear();
    _gridFocusNodes.clear();

    final nextNo = await p.getNextPurchaseReturnEntryNo();

    if (mounted) {
      setState(() {
        _isExistingEntry = false;
        _isDeleted = false;
        _isDirty = false; // Reset dirty flag
        _items.clear();
        _errorCells.clear();
        _entryNo = nextNo;
        _supplierCtrl.clear();
        _originalInvCtrl.clear();
        _remarksCtrl.clear();
        _doneByCtrl.clear();
        _date = DateTime.now();

        _footerDiscPctCtrl.text = "0";
        _footerDiscAmtCtrl.text = "0.00";
        _otherChargePctCtrl.text = "0";
        _otherChargeAmtCtrl.text = "0.00";
        _roundOffCtrl.text = "0.00";
        _adjustAmtCtrl.text = "0.00";
        _productHistory = [];
        _salesHistory = [];
        _historyProductName = "";
        _calculateFooter();
      });
      _moveFocus(-1, 0);
    }
  }

  void _exportToExcel() async {
    if (_items.isEmpty) return;
    try {
      final p = Provider.of<PharmacyProvider>(context, listen: false);
      String? result = await FilePicker.saveFile(
        dialogTitle: 'Save Purchase Return Excel',
        fileName: 'purchase_return_${_entryNo.replaceAll('/', '_')}.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (result != null) {
        await p.exportPurchaseReturnToExcel(result, _items, showSupplier: _showSupplierCol, showInvNo: _showInvNoCol, showEntryNo: _showEntryNoCol);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Exported successfully!")));
      }
    } catch (e) {
      if (mounted) AppDialogs.showFastDialog(context: context, title: "Export Error", content: e.toString());
    }
  }

  void _exportToPdf() async {
    if (_items.isEmpty) return;
    try {
      final p = Provider.of<PharmacyProvider>(context, listen: false);
      final doc = await InvoicePdfGenerator.buildPurchaseReturnPdf(
        _items, _entryNo, _date, _supplierCtrl.text, _originalInvCtrl.text, p.companyProfile,
        showSupplierCol: _showSupplierCol,
        showInvNoCol: _showInvNoCol,
        showEntryNoCol: _showEntryNoCol,
      );
      if (!mounted) return;
      PrinterService.showProfessionalPreview(context: context, doc: doc, title: "Purchase Return Preview");
    } catch (e) {
      if (mounted) AppDialogs.showFastDialog(context: context, title: "PDF Error", content: e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _rootFocus,
      onKeyEvent: (node, event) => _handleKeyEvent(event) ? KeyEventResult.handled : KeyEventResult.ignored,
      child: Scaffold(
        backgroundColor: const Color(0xFFE9EDF0),
        body: Stack(
          children: [
            Column(
              children: [
                _buildTopToolbar(),
                _buildHeader(),
                Expanded(
                  child: LayoutBuilder(builder: (ctx, con) {
                    double fixedTotal = 0;
                    _colWidths.forEach((k, v) {
                      if (k == 1) return;
                      if (k == 5 && !_showSupplierCol) return;
                      if (k == 6 && !_showInvNoCol) return;
                      if (k == 7 && !_showEntryNoCol) return;
                      fixedTotal += v;
                    });
                    double productWidth = 180;
                    if (con.maxWidth > (fixedTotal + 180)) {
                      productWidth = con.maxWidth - fixedTotal;
                    }
                    _colWidths[1] = productWidth;
                    final double finalTw = fixedTotal + _colWidths[1]!;

                    return Scrollbar(
                      controller: _gridScrollCtrl,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        controller: _gridScrollCtrl,
                        child: SizedBox(
                          width: finalTw,
                          height: con.maxHeight,
                          child: Column(
                            children: [
                              _buildGridHeader(),
                              Expanded(child: _buildGrid()),
                              _buildTotalsRow(finalTw),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                _buildFooter(),
                _buildShortcutLegend(),
              ],
            ),
            _buildOverlay(),
            if (_isLoading) Container(color: Colors.black12, child: const Center(child: CircularProgressIndicator())),
          ],
        ),
      ),
    );
  }

  Widget _buildTopToolbar() {
    bool canSave = !_isExistingEntry && !_isDeleted;
    bool canEdit = _isExistingEntry && !_isDeleted;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey, width: 0.2))),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text("PURCHASE RETURN ENTRY", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black87)),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _topActionBtn(Icons.add_box_rounded, "New (F2)", Colors.blue, onTap: _resetPage),
              _topActionBtn(Icons.check_circle_rounded, "Save (F6)", canSave ? Colors.green : Colors.grey.shade400, onTap: canSave ? () => _saveReturn(isEdit: false) : () {}),
              _topActionBtn(Icons.edit_document, "Edit", canEdit ? Colors.orange : Colors.grey.shade400, onTap: canEdit ? () => _saveReturn(isEdit: true) : () {}),
              _topActionBtn(Icons.print_rounded, "Print", Colors.blueGrey, onTap: _exportToPdf),
              _topActionBtn(Icons.file_download_outlined, "Export", Colors.green.shade800, onTap: _exportToExcel),
            ],
          ),
        ],
      ),
    );
  }

  Widget _topActionBtn(IconData icon, String label, Color color, {VoidCallback? onTap}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 28, color: color),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    ),
  );

  Widget _headerColumn(String label, Widget child, {CrossAxisAlignment align = CrossAxisAlignment.start}) => Column(
    crossAxisAlignment: align,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
      const SizedBox(height: 2),
      child,
    ],
  );

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LEFT BLOCK: Entry No on Row 1, Date & Time on Row 2
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ROW 1: ENTRY NO
              _headerColumn("Entry No:", Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _entryNavBtn("<", onTap: () => _navigateEntry('prev')),
                  Container(
                    width: 70, height: 26,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400)),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _entryNo.contains('_') ? _entryNo.substring(_entryNo.indexOf('_') + 1) : _entryNo,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        maxLines: 1,
                      ),
                    ),
                  ),
                  _entryNavBtn(">", onTap: () => _navigateEntry('next')),
                ],
              )),
              const SizedBox(height: 4),
              // ROW 2: DATE & TIME SIDE BY SIDE BELOW ENTRY NO
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _headerColumn("Date", InkWell(
                    onTap: _isDeleted ? null : () async {
                      final picked = await showAppDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime(2100));
                      if (picked != null) {
                        setState(() => _date = DateTime(picked.year, picked.month, picked.day, _date.hour, _date.minute));
                      }
                    },
                    child: Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(DateFormat('d/M/yy').format(_date), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                          const SizedBox(width: 4),
                          Icon(Icons.calendar_month, size: 13, color: Colors.orange.shade800),
                        ],
                      ),
                    ),
                  )),
                  const SizedBox(width: 6),
                  _headerColumn("Time", InkWell(
                    onTap: _isDeleted ? null : () async {
                      final tod = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_date));
                      if (tod != null) {
                        setState(() => _date = DateTime(_date.year, _date.month, _date.day, tod.hour, tod.minute));
                      }
                    },
                    child: Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Center(
                        child: Text(DateFormat('hh:mm a').format(_date), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                      ),
                    ),
                  )),
                ],
              ),
            ],
          ),
          const SizedBox(width: 14),

          // MIDDLE BLOCK: Supplier, Pur Inv No, Done By (Row 1), Box 4 Toggles (Row 2 under Pur Inv No/Done By)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // SUPPLIER
                  _headerColumn("Supplier:", Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _headerField(
                        _supplierCtrl,
                        _supplierFocus,
                        width: 260,
                        height: 28,
                        link: _supplierLayer,
                        hint: "",
                        onChanged: _startSupplierSearch,
                      ),
                      InkWell(
                        onTap: () {
                          Provider.of<AppProvider>(context, listen: false).openSupplierRegistration();
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4, right: 6),
                          child: Text("+", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                        ),
                      ),
                    ],
                  )),
                  const SizedBox(width: 10),

                  // PUR INV NO
                  _headerColumn("Pur Inv No:", _headerField(
                    _originalInvCtrl,
                    _originalInvFocus,
                    width: 120,
                    height: 28,
                    hint: "",
                  )),
                  const SizedBox(width: 10),

                  // DONE BY
                  _headerColumn("Done By:", _headerField(
                    _doneByCtrl,
                    _doneByFocus,
                    width: 80,
                    height: 28,
                    hint: "",
                  )),
                  const SizedBox(width: 10),

                  // TAX TYPE (GST / NON GST)
                  _headerColumn("TAX TYPE", Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () {
                          if (_gstMode != 1) {
                            setState(() {
                              _gstMode = 1;
                              for (int i = 0; i < _items.length; i++) {
                                _calculateItem(i);
                              }
                            });
                          }
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Radio<int>(
                              value: 1,
                              groupValue: _gstMode,
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() {
                                    _gstMode = v;
                                    for (int i = 0; i < _items.length; i++) {
                                      _calculateItem(i);
                                    }
                                  });
                                }
                              },
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            const Text("Gst", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () {
                          if (_gstMode != 2) {
                            setState(() {
                              _gstMode = 2;
                              for (int i = 0; i < _items.length; i++) {
                                _calculateItem(i);
                              }
                            });
                          }
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Radio<int>(
                              value: 2,
                              groupValue: _gstMode,
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() {
                                    _gstMode = v;
                                    for (int i = 0; i < _items.length; i++) {
                                      _calculateItem(i);
                                    }
                                  });
                                }
                              },
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            const Text("Non Gst", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  )),
                ],
              ),
              const SizedBox(height: 6),
              // BOX 4: WHOLESALER & SHOW INV NO OPTIONS DIRECTLY UNDER PUR INV NO / DONE BY
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => setState(() => _showSupplierCol = !_showSupplierCol),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18, height: 18,
                          child: Checkbox(
                            value: _showSupplierCol,
                            onChanged: (v) => setState(() => _showSupplierCol = v ?? true),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Text("Show Wholesaler", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  InkWell(
                    onTap: () => setState(() => _showInvNoCol = !_showInvNoCol),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18, height: 18,
                          child: Checkbox(
                            value: _showInvNoCol,
                            onChanged: (v) => setState(() => _showInvNoCol = v ?? true),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Text("Show Inv No", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 14),

          // BOX M: REMARK COLUMN (Fills the entire right area)
          Expanded(
            child: _headerColumn("Remarks:", SizedBox(
              height: 56,
              child: TextField(
                controller: _remarksCtrl,
                focusNode: _remarksFocus,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                textCapitalization: TextCapitalization.characters,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: "",
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  fillColor: Colors.grey.shade50,
                  filled: true,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
                ),
              ),
            )),
          ),
        ],
      ),
    );
  }

  Widget _headerField(
    TextEditingController ctrl,
    FocusNode fn, {
    double width = 150,
    double height = 28,
    LayerLink? link,
    Color? bgColor,
    bool isNumeric = false,
    String? hint,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) {
    Widget field = SizedBox(
      height: height,
      child: TextField(
        controller: ctrl,
        focusNode: fn,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        keyboardType: isNumeric ? const TextInputType.numberWithOptions(decimal: true) : null,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          fillColor: bgColor ?? Colors.grey.shade50,
          filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: Colors.grey.shade300)),
        ),
      ),
    );

    if (link != null) {
      field = CompositedTransformTarget(link: link, child: field);
    }

    return SizedBox(width: width, child: field);
  }

  Widget _entryNavBtn(String txt, {VoidCallback? onTap}) => InkWell(
    onTap: onTap,
    child: Container(
      width: 22, height: 26, alignment: Alignment.center,
      decoration: BoxDecoration(color: Colors.grey.shade200, border: Border.all(color: Colors.grey.shade400)),
      child: Text(txt, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    ),
  );

  Widget _buildGridHeader() => Container(
    height: 32, color: const Color(0xFF37474F),
    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: List.generate(22, (i) {
      if (i == 5 && !_showSupplierCol) return const SizedBox();
      if (i == 6 && !_showInvNoCol) return const SizedBox();
      if (i == 7 && !_showEntryNoCol) return const SizedBox();
      return _ResizableHdr(i, _getColName(i), width: _colWidths[i]!, tooltip: _getColTooltip(i), onResize: (v) => setState(() => _colWidths[i] = v), align: _getColAlign(i));
    })),
  );

  String _getColName(int i) => ["Sl", "Product Name", "HSN", "Batch", "Expiry", "Supplier", "Inv No", "Entry No", "Pack", "Qty", "Loose", "F.Qty", "P.Rate", "MRP", "Gross", "Disc%", "Net", "GST", "GST%", "Total", "Reason", ""][i];

  String _getColTooltip(int i) => [
        "Serial Number",
        "Product Name",
        "HSN Code",
        "Batch Number",
        "Expiry Date (MM/YY)",
        "Supplier / Wholesaler Name",
        "Ref Supplier Invoice Number",
        "Return Entry Number",
        "Packing Size",
        "Return Quantity",
        "Loose Quantity",
        "Free Quantity",
        "Purchase Rate",
        "Maximum Retail Price",
        "Gross Amount",
        "Discount Percentage",
        "Net Amount",
        "GST Amount",
        "GST Percentage",
        "Total Amount",
        "Return Reason",
        ""
      ][i];
  TextAlign _getColAlign(int i) => [TextAlign.center, TextAlign.left, TextAlign.left, TextAlign.left, TextAlign.center, TextAlign.left, TextAlign.left, TextAlign.center, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.left, TextAlign.center][i];

  Widget _buildGrid() => ListView.builder(
    controller: _verticalGridScrollCtrl,
    itemExtent: 30.0,
    itemCount: _items.length + (_isDeleted ? 0 : 1),
    itemBuilder: (ctx, i) => RepaintBoundary(
      child: i < _items.length ? _buildRow(i) : _buildActiveRow(),
    ),
  );

  Widget _buildRow(int row) {
    final it = _items[row];
    return ValueListenableBuilder<IntPair?>(
      valueListenable: _focusNotifier,
      builder: (context, focus, _) {
        bool isRowActive = focus?.row == row;
        Color rowBg = isRowActive ? const Color(0xFFF0F7FF) : (row % 2 == 0 ? Colors.white : const Color(0xFFF9FAFB));

        return Container(
          height: 30,
          decoration: BoxDecoration(color: rowBg, border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.5))),
          child: Row(
            children: [
              _cell(row, 0, "${row + 1}", _colWidths[0]!, align: TextAlign.center),
              _cell(row, 1, it.product.name.toUpperCase(), _colWidths[1]!, isInput: true, fontWeight: FontWeight.bold, onChanged: (v) { _saveUndoState(); it.product.name = v; _startProductSearch(v); }),
              _cell(row, 2, it.hsncode.toUpperCase(), _colWidths[2]!),
              _cell(row, 3, cleanBatch(it.product.batch).toUpperCase(), _colWidths[3]!, isInput: true, onChanged: (v) { _saveUndoState(); it.product.batch = v; _startBatchSearch(row, v); }),
              _cell(row, 4, it.product.expiry, _colWidths[4]!, align: TextAlign.center),
              if (_showSupplierCol) _cell(row, 5, it.supplier.toUpperCase(), _colWidths[5]!, isInput: true, onChanged: (v) { _saveUndoState(); it.supplier = v; }),
              if (_showInvNoCol) _cell(row, 6, it.supInvNo.toUpperCase(), _colWidths[6]!, isInput: true, onChanged: (v) { _saveUndoState(); it.supInvNo = v; }),
              if (_showEntryNoCol) _cell(row, 7, _entryNo, _colWidths[7]!, align: TextAlign.center),
              _cell(row, 8, it.packin.toString(), _colWidths[8]!, isInput: true, align: TextAlign.right, onChanged: (v) { _saveUndoState(); it.packin = int.tryParse(v) ?? 1; _calculateItem(row); }),
              _cell(row, 9, it.qty.toString(), _colWidths[9]!, isInput: true, align: TextAlign.right, onChanged: (v) { _saveUndoState(); it.qty = int.tryParse(v) ?? 0; _calculateItem(row); }),
              _cell(row, 10, it.looseQty.toString(), _colWidths[10]!, isInput: true, align: TextAlign.right, onChanged: (v) { _saveUndoState(); it.looseQty = int.tryParse(v) ?? 0; _calculateItem(row); }),
              _cell(row, 11, it.fQty.toString(), _colWidths[11]!, isInput: true, align: TextAlign.right),
              _cell(row, 12, it.pRate.toStringAsFixed(2), _colWidths[12]!, align: TextAlign.right),
              _cell(row, 13, it.mrp.toStringAsFixed(2), _colWidths[13]!, align: TextAlign.right),
              _cell(row, 14, it.gross.toStringAsFixed(2), _colWidths[14]!, align: TextAlign.right),
              _cell(row, 15, it.discPercent.toStringAsFixed(2), _colWidths[15]!, isInput: true, align: TextAlign.right, onChanged: (v) { _saveUndoState(); it.discPercent = double.tryParse(v) ?? 0.0; _calculateItem(row); }),
              _cell(row, 16, it.net.toStringAsFixed(2), _colWidths[16]!, align: TextAlign.right),
              _cell(row, 17, it.gstAmt.toStringAsFixed(2), _colWidths[17]!, align: TextAlign.right),
              _cell(row, 18, (TaxCalculator.roundGstPercent(it.gstPercent) % 1 == 0 ? TaxCalculator.roundGstPercent(it.gstPercent).toInt().toString() : TaxCalculator.roundGstPercent(it.gstPercent).toStringAsFixed(1)), _colWidths[18]!, isInput: true, align: TextAlign.right, onChanged: (v) { _saveUndoState(); it.gstPercent = TaxCalculator.roundGstPercent(double.tryParse(v) ?? 0.0); _calculateItem(row); }),
              _cell(row, 19, it.total.toStringAsFixed(2), _colWidths[19]!, align: TextAlign.right, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
              _cell(row, 20, it.reason, _colWidths[20]!, isInput: true, onChanged: (v) { _saveUndoState(); it.reason = v; }),
              Container(width: _colWidths[21]!, alignment: Alignment.center, child: IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 16), padding: EdgeInsets.zero, onPressed: () => _deleteRow(row))),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveRow() {
    int row = _items.length;
    return ValueListenableBuilder<IntPair?>(
      valueListenable: _focusNotifier,
      builder: (context, focus, _) {
        bool isRowActive = focus?.row == row;
        return Container(
          height: 32,
          decoration: BoxDecoration(color: isRowActive ? const Color(0xFFF0F7FF) : const Color(0xFFFFFFF0), border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
          child: Row(
            children: [
              _cell(row, 0, "${row + 1}", _colWidths[0]!, align: TextAlign.center),
              _cell(row, 1, "", _colWidths[1]!, isInput: true, onChanged: _startProductSearch),
              _cell(row, 2, "", _colWidths[2]!),
              _cell(row, 3, "", _colWidths[3]!, isInput: true, onChanged: (v) => _startBatchSearch(row, v)),
              _cell(row, 4, "", _colWidths[4]!, align: TextAlign.center),
              if (_showSupplierCol) _cell(row, 5, "", _colWidths[5]!),
              if (_showInvNoCol) _cell(row, 6, "", _colWidths[6]!),
              if (_showEntryNoCol) _cell(row, 7, "", _colWidths[7]!, align: TextAlign.center),
              _cell(row, 8, "", _colWidths[8]!, isInput: true, align: TextAlign.right),
              _cell(row, 9, "", _colWidths[9]!, isInput: true, align: TextAlign.right),
              _cell(row, 10, "", _colWidths[10]!, isInput: true, align: TextAlign.right),
              _cell(row, 11, "", _colWidths[11]!, align: TextAlign.right),
              _cell(row, 12, "", _colWidths[12]!, align: TextAlign.right),
              _cell(row, 13, "", _colWidths[13]!, align: TextAlign.right),
              _cell(row, 14, "", _colWidths[14]!, align: TextAlign.right),
              _cell(row, 15, "", _colWidths[15]!, isInput: true, align: TextAlign.right),
              _cell(row, 16, "", _colWidths[16]!, align: TextAlign.right),
              _cell(row, 17, "", _colWidths[17]!, align: TextAlign.right),
              _cell(row, 18, "", _colWidths[18]!, isInput: true, align: TextAlign.right),
              _cell(row, 19, "", _colWidths[19]!, align: TextAlign.right),
              _cell(row, 20, "", _colWidths[20]!, isInput: true),
              SizedBox(width: _colWidths[21]!),
            ],
          ),
        );
      },
    );
  }

  Widget _cell(int row, int col, String val, double w, {bool isInput = false, TextAlign align = TextAlign.left, Color? color, FontWeight? fontWeight, String hint = "", Function(String)? onChanged}) {
    final actualFocusNode = _getGridFocusNode(row, col);
    String rowId = row < _items.length ? _items[row].uuid : "new_row";

    return ListenableBuilder(
      listenable: actualFocusNode,
      builder: (context, _) {
        // ---> THE DEADLOCK FIX <---
        bool isFocused = (_focusNotifier.value?.row == row && _focusNotifier.value?.col == col) || actualFocusNode.hasFocus;
        bool isFocusable = _navCols.contains(col);
        final ctrl = _getGridCtrl(row, col, val);
        
        if (!isFocused && ctrl.text != val) {
          ctrl.text = val;
        }

        const bool isEntryLocked = false;
        bool isActuallyInput = isInput && !_isDeleted && !isEntryLocked;
        bool renderAsTextField = isActuallyInput && isFocused;

        Color? bg;
        if (_errorCells[row]?.contains(col) == true) {
          bg = Colors.red.shade100;
        } else {
          bg = (isActuallyInput)
            ? (isFocused ? null : const Color(0xFFFFFDE7).withValues(alpha: 0.5))
            : const Color(0xFFCFD8DC).withValues(alpha: 0.5);
        }

        Widget cellContent = renderAsTextField
            ? TextField(
                key: ValueKey("pret_tf_${rowId}_$col"),
                controller: ctrl, 
                focusNode: actualFocusNode, 
                textAlign: align,
                keyboardType: (col >= 8 && col <= 19) ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                inputFormatters: (col >= 8 && col <= 19) ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : (col == 4 ? [ExpiryFormatter()] : [UpperCaseTextFormatter()]),
                onChanged: (v) {
                  if (_errorCells[row]?.contains(col) == true) {
                     setState(() {
                       _errorCells[row]?.remove(col);
                     });
                  }
                  _markDirty();
                  if (col == 1) {
                    _startProductSearch(v);
                  } else if (col == 3) {
                    _startBatchSearch(row, v);
                  } else {
                    if (onChanged != null) onChanged(v);
                  }
                },
                onTap: () {
                  final bool isAlreadyFocused = (_focusNotifier.value?.row == row && _focusNotifier.value?.col == col);

                  if (!isAlreadyFocused) {
                    _moveFocus(row, col, autoOpen: false);
                    if (ctrl.text.isNotEmpty) {
                      ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
                      _closeAllDropdowns();
                    } else {
                      if (col == 1) {
                        _startProductSearch("");
                      }
                    }
                  } else {
                    if (col == 1) {
                      if (!_isExactProductMatch(ctrl.text)) {
                        _startProductSearch(ctrl.text);
                      }
                    } else if (col == 3) {
                      if (!_isExactBatchMatch(row, ctrl.text)) {
                        _startBatchSearch(row, ctrl.text);
                      }
                    }
                  }
                },
                textCapitalization: (col == 4 || col == 5 || col == 10) ? TextCapitalization.none : TextCapitalization.characters,
                textAlignVertical: TextAlignVertical.center,
                style: TextStyle(fontSize: 12, fontWeight: fontWeight ?? FontWeight.bold, color: color ?? Colors.black),
                decoration: InputDecoration(isDense: true, border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8), hintText: hint, hintStyle: const TextStyle(fontSize: 10, color: Colors.grey)),
                cursorColor: Colors.blue.shade900, cursorWidth: 2.0,
              )
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: align == TextAlign.center ? Alignment.center : (align == TextAlign.right ? Alignment.centerRight : Alignment.centerLeft),
                child: Text(val.toUpperCase(), style: TextStyle(fontSize: 12, color: color ?? Colors.black, fontWeight: fontWeight ?? FontWeight.normal), overflow: TextOverflow.ellipsis),
              );

        Widget content = Container(
          key: ValueKey("pret_cell_${rowId}_$col"),
          decoration: BoxDecoration(color: bg, border: (isFocused && isFocusable) ? Border.all(color: Colors.blue.shade800, width: 2) : null),
          child: (col == 1 || col == 3)
              ? CompositedTransformTarget(link: (col == 1 && (isFocused || _focusedRowIndex == row)) ? _searchLayer : ((col == 3 && (isFocused || _focusedRowIndex == row)) ? _batchLayer : LayerLink()), child: cellContent)
              : cellContent,
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            if (!isFocused) {
              _moveFocus(row, col, autoOpen: false);
            }
          },
          child: Container(width: w, height: 30, decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade300, width: 0.5))), child: content),
        );
      },
    );
  }

  Widget _buildTotalsRow(double width) {
    int sumQty = _items.fold(0, (sum, it) => sum + it.qty);
    int sumLoose = _items.fold(0, (sum, it) => sum + it.looseQty);
    double sumGross = _items.fold(0.0, (sum, it) => sum + it.gross);
    double sumNet = _items.fold(0.0, (sum, it) => sum + it.net);
    double sumGst = _items.fold(0.0, (sum, it) => sum + it.gstAmt);
    double sumTotal = _items.fold(0.0, (sum, it) => sum + it.total);

    return Container(
      height: 28, width: width, color: const Color(0xFF37474F),
      child: Row(
        children: [
          SizedBox(width: _colWidths[0]! + _colWidths[1]! + _colWidths[2]! + _colWidths[3]! + _colWidths[4]! + (_showSupplierCol ? _colWidths[5]! : 0) + (_showInvNoCol ? _colWidths[6]! : 0) + (_showEntryNoCol ? _colWidths[7]! : 0) + _colWidths[8]!),
          _Hdr(sumQty.toString(), width: _colWidths[9], align: TextAlign.right),
          _Hdr(sumLoose.toString(), width: _colWidths[10], align: TextAlign.right),
          SizedBox(width: _colWidths[11]! + _colWidths[12]! + _colWidths[13]!),
          _Hdr(sumGross.toStringAsFixed(2), width: _colWidths[14], align: TextAlign.right),
          SizedBox(width: _colWidths[15]!),
          _Hdr(sumNet.toStringAsFixed(2), width: _colWidths[16], align: TextAlign.right),
          _Hdr(sumGst.toStringAsFixed(2), width: _colWidths[17], align: TextAlign.right),
          SizedBox(width: _colWidths[18]!),
          _Hdr(sumTotal.toStringAsFixed(2), width: _colWidths[19], align: TextAlign.right),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    return Stack(
      children: [
        ValueListenableBuilder<List<String>>(
          valueListenable: _supplierSearchList,
          builder: (ctx, list, _) {
            if (list.isEmpty) return const SizedBox();
            return CompositedTransformFollower(
              link: _supplierLayer,
              showWhenUnlinked: false,
              offset: const Offset(0, 28),
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _isSelectingFromDropdown = true,
                child: Material(
                  elevation: 8,
                  child: Container(
                    width: 250, constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.blue.shade900)),
                    child: ListView.builder(
                      padding: EdgeInsets.zero, shrinkWrap: true, itemCount: list.length,
                      itemBuilder: (ctx, i) => InkWell(
                        onTap: () => _onSupplierSelected(list[i]),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
                          child: Text(list[i], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        ListenableBuilder(
          listenable: Listenable.merge([_searchList, _batchList]),
          builder: (ctx, _) {
            final bool isBatch = _isSelectingBatch && _batchList.value.isNotEmpty;
            final list = isBatch ? _batchList.value : _searchList.value;
            if (list.isEmpty) return const SizedBox();

            final link = isBatch ? _batchLayer : _searchLayer;
            const double dropWidth = 1100.0;
            const headerColor = Color(0xFF334155);

            return CompositedTransformFollower(
              link: link,
              showWhenUnlinked: false,
              offset: const Offset(0, 30),
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _isSelectingFromDropdown = true,
                child: Material(
                  elevation: 16,
                  shadowColor: Colors.black54,
                  child: Container(
                    width: dropWidth,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: headerColor, width: 2.0),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          height: 26,
                          color: headerColor,
                          child: Row(
                            children: isBatch
                                ? const [
                                    _Hdr("Batch", width: 150),
                                    _Hdr("Stock", width: 80, align: TextAlign.right),
                                    _Hdr("Packing", width: 80, align: TextAlign.right),
                                    _Hdr("Strips/L", width: 80, align: TextAlign.center),
                                    _Hdr("Expiry", width: 90, align: TextAlign.center),
                                    _Hdr("MRP", width: 90, align: TextAlign.right),
                                    _Hdr("S.PRICE", width: 100, align: TextAlign.right),
                                    _Hdr("Disc%", width: 70, align: TextAlign.right),
                                    _Hdr("1 /MRP", width: 80, align: TextAlign.right),
                                    _Hdr("1 /S.PRICE", width: 90, align: TextAlign.right),
                                    _Hdr("LCWT", width: 90, align: TextAlign.right),
                                    _Hdr("Profit%", flex: 1, align: TextAlign.right),
                                  ]
                                : const [
                                    _Hdr("Name", width: 300),
                                    _Hdr("Stock", width: 70, align: TextAlign.right),
                                    _Hdr("Packin", width: 60, align: TextAlign.right),
                                    _Hdr("Strips/L", width: 80, align: TextAlign.center),
                                    _Hdr("MRP", width: 80, align: TextAlign.right),
                                    _Hdr("PRate", width: 80, align: TextAlign.right),
                                    _Hdr("Rack", width: 60),
                                    _Hdr("Cat", width: 50),
                                    _Hdr("Patent", width: 120),
                                    _Hdr("Generic Name", width: 150),
                                    _Hdr("Use", flex: 1),
                                  ],
                          ),
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 270.0),
                          child: ValueListenableBuilder<int>(
                            valueListenable: _searchIdx,
                            builder: (ctx, idx, _) => ListView.builder(
                              controller: _dropdownScrollCtrl,
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemExtent: 24.0,
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: list.length,
                              itemBuilder: (ctx, i) {
                                final p = list[i];
                                bool sel = i == idx;
                                double ps = p.packSize == 0 ? 1 : p.packSize.toDouble();
                                int strips = p.stock ~/ ps;
                                int loose = p.stock % ps.toInt();
                                String stripsStr = "$strips / $loose";

                                return InkWell(
                                  onTap: () => isBatch ? _finalizeBatchSelection(p) : _onProductSelected(p),
                                  child: Container(
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: sel ? Colors.teal.shade50 : Colors.white,
                                      border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 0.5)),
                                    ),
                                    child: Row(
                                      children: isBatch
                                          ? [
                                              _GridCell(cleanBatch(p.batch), width: 150, fontWeight: FontWeight.bold),
                                              _GridCell("${p.stock}", width: 80, align: TextAlign.right),
                                              _GridCell("${p.packSize}", width: 80, align: TextAlign.right),
                                              _GridCell(stripsStr, width: 80, align: TextAlign.center),
                                              _GridCell(p.expiry, width: 90, align: TextAlign.center),
                                              _GridCell(p.mrp.toStringAsFixed(2), width: 90, align: TextAlign.right),
                                              _GridCell(p.salePrice.toStringAsFixed(2), width: 100, align: TextAlign.right),
                                              const _GridCell("0.00", width: 70, align: TextAlign.right),
                                              _GridCell((p.mrp / ps).toStringAsFixed(2), width: 80, align: TextAlign.right),
                                              _GridCell((p.salePrice / ps).toStringAsFixed(2), width: 90, align: TextAlign.right),
                                              _GridCell(p.landingCost.toStringAsFixed(2), width: 90, align: TextAlign.right),
                                              _GridCell(
                                                p.purchaseRate > 0 ? "${(((p.mrp - p.purchaseRate) / p.purchaseRate) * 100).toStringAsFixed(1)}%" : "0.0%",
                                                flex: 1,
                                                align: TextAlign.right,
                                              ),
                                            ]
                                          : [
                                              _GridCell(p.name, width: 300, fontWeight: FontWeight.bold),
                                              _GridCell("${p.stock}", width: 70, align: TextAlign.right, color: Colors.blue.shade900, fontWeight: FontWeight.bold),
                                              _GridCell("${p.packSize}", width: 60, align: TextAlign.right),
                                              _GridCell(stripsStr, width: 80, align: TextAlign.center, color: Colors.blue.shade800),
                                              _GridCell(p.mrp.toStringAsFixed(2), width: 80, align: TextAlign.right),
                                              _GridCell(p.purchaseRate.toStringAsFixed(2), width: 80, align: TextAlign.right),
                                              _GridCell(p.rack, width: 60),
                                              _GridCell(p.category, width: 50),
                                              _GridCell(p.manufacturer, width: 120),
                                              _GridCell(p.genericName.isNotEmpty ? p.genericName : (Provider.of<PharmacyProvider>(context, listen: false).productMaster.firstWhere((m) => m.id == p.id || m.name.toLowerCase().trim() == p.name.toLowerCase().trim(), orElse: () => Product(id: "", name: p.name)).genericName), width: 150),
                                              const _GridCell("", flex: 1),
                                            ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  String _fmt(double v) => v.toStringAsFixed(2);

  void _updateHistory(String productName) {
    if (productName.trim().isEmpty) {
      if (_historyProductName.isNotEmpty || _productHistory.isNotEmpty || _salesHistory.isNotEmpty) {
        setState(() {
          _productHistory = [];
          _salesHistory = [];
          _historyProductName = "";
        });
      }
      return;
    }
    _historyDebouncer.run(() async {
      final p = Provider.of<PharmacyProvider>(context, listen: false);
      final purHistory = await p.getProductPurchaseHistory(productName);
      final saleHistory = await p.getProductSaleHistory(productName);
      if (mounted) {
        setState(() {
          _productHistory = purHistory;
          _salesHistory = saleHistory;
          _historyProductName = productName;
        });
      }
    });
  }

  Widget _purchaseHistoryList() {
    return ListView.builder(
      itemCount: _productHistory.length,
      itemBuilder: (ctx, i) {
        final h = _productHistory[i];
        double mrp = (h['mrp'] as num?)?.toDouble() ?? 0.0;
        double pRate = (h['p_rate'] as num?)?.toDouble() ?? 0.0;
        double lCost = (h['l_cost'] as num?)?.toDouble() ?? 0.0;
        double cost = lCost > 0 ? lCost : pRate;
        double profitPct = cost > 0 ? ((mrp - cost) / cost) * 100 : 0.0;
        String batch = h['batch']?.toString() ?? '';

        return Container(
          height: 22,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
          child: Row(children: [
            SizedBox(width: 65, child: Text(DateFormat('dd/MM/yy').format(DateTime.parse(h['date'])), style: const TextStyle(fontSize: 10))),
            SizedBox(width: 60, child: Text(h['entry_no']?.toString() ?? '', style: const TextStyle(fontSize: 10))),
            Expanded(flex: 2, child: Text(h['supplier_name']?.toString() ?? '', style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis)),
            SizedBox(width: 65, child: Text(batch, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis)),
            SizedBox(width: 55, child: Text(_fmt(mrp), textAlign: TextAlign.right, style: const TextStyle(fontSize: 10))),
            SizedBox(width: 55, child: Text(_fmt(pRate), textAlign: TextAlign.right, style: const TextStyle(fontSize: 10))),
            SizedBox(width: 55, child: Text("${profitPct.toStringAsFixed(1)}%", textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade800))),
          ]),
        );
      },
    );
  }

  Widget _salesHistoryList() {
    return ListView.builder(
      itemCount: _salesHistory.length,
      itemBuilder: (ctx, i) {
        final h = _salesHistory[i];
        double mrp = (h['mrp'] as num?)?.toDouble() ?? 0.0;
        double sRate = (h['s_rate'] as num?)?.toDouble() ?? 0.0;
        double disc = (h['disc_percent'] as num?)?.toDouble() ?? 0.0;
        int qty = (h['qty'] as num?)?.toInt() ?? 0;

        String party = (h['patient'] as String?)?.isNotEmpty == true 
            ? h['patient']! 
            : ((h['doctor'] as String?)?.isNotEmpty == true ? h['doctor']! : (h['supplier_name']?.toString() ?? ''));

        return Container(
          height: 22,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
          child: Row(children: [
            SizedBox(width: 65, child: Text(DateFormat('dd/MM/yy').format(DateTime.parse(h['date'])), style: const TextStyle(fontSize: 10))),
            SizedBox(width: 60, child: Text(h['entry_no']?.toString() ?? '', style: const TextStyle(fontSize: 10))),
            Expanded(flex: 2, child: Text(party, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis)),
            SizedBox(width: 55, child: Text(_fmt(mrp), textAlign: TextAlign.right, style: const TextStyle(fontSize: 10))),
            SizedBox(width: 55, child: Text(_fmt(sRate), textAlign: TextAlign.right, style: const TextStyle(fontSize: 10))),
            SizedBox(width: 40, child: Text("$qty", textAlign: TextAlign.right, style: const TextStyle(fontSize: 10))),
            SizedBox(width: 45, child: Text("${_fmt(disc)}%", textAlign: TextAlign.right, style: const TextStyle(fontSize: 10))),
          ]),
        );
      },
    );
  }

  Widget _calcRow(String label, TextEditingController ctrl, {TextEditingController? pct, FocusNode? pctFocus, FocusNode? amtFocus, bool readOnly = false, VoidCallback? onSubmitted}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Row(children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        const Spacer(),
        if (pct != null) ...[
          SizedBox(
              width: 45, height: 21,
              child: TextField(
                  controller: pct, focusNode: pctFocus, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11),
                  onSubmitted: (_) => onSubmitted?.call(),
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2), suffixText: "%")
              )
          ),
          const SizedBox(width: 6)
        ],
        SizedBox(
            width: 100, height: 21,
            child: TextField(
                controller: ctrl, focusNode: amtFocus, readOnly: readOnly, textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                onSubmitted: (_) => onSubmitted?.call(),
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 2))
            )
        ),
      ]),
    );
  }

  Widget _totalCalculationSection() {
    return ValueListenableBuilder<double>(
      valueListenable: _grandTotalNotifier,
      builder: (context, total, _) {
        return SizedBox(
          width: 250,
          child: Column(children: [
            _calcRow("Sub Total:", _subTotalCtrl, readOnly: true),
            _calcRow("Discount:", _footerDiscAmtCtrl, pct: _footerDiscPctCtrl, pctFocus: _footerDiscPctFocus, amtFocus: _footerDiscAmtFocus),
            _calcRow("Other Chg:", _otherChargeAmtCtrl, pct: _otherChargePctCtrl, pctFocus: _otherChargePctFocus, amtFocus: _otherChargeAmtFocus),
            _calcRow("Less CrNote:", _adjustAmtCtrl, amtFocus: _adjustAmtFocus),
            _calcRow("Round Off:", _roundOffCtrl, readOnly: true),
            const Divider(height: 4, thickness: 1, color: Colors.black26),
            Row(children: [
              const Text("GRAND TOTAL:", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.blue)),
              const Spacer(),
              Text("₹ ${_fmt(total)}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.blue)),
            ]),
          ]),
        );
      },
    );
  }

  String _getActiveProductName() {
    final p = Provider.of<PharmacyProvider>(context, listen: false);

    if (_searchList.value.isNotEmpty) {
      final idx = _searchIdx.value.clamp(0, _searchList.value.length - 1);
      return _searchList.value[idx].name;
    }

    int row = _focusedRowIndex;
    String name = "";
    if (row >= 0 && row < _items.length) {
      name = _items[row].product.name;
      if (name.isEmpty) name = _getGridCtrl(row, 1).text;
    } else if (row == _items.length) {
      name = _getGridCtrl(row, 1).text;
    }

    if (name.trim().isEmpty) {
      name = _historyProductName;
    }

    if (name.trim().isNotEmpty) {
      final matches = p.searchProducts(name.trim(), includeGenerics: false);
      if (matches.isNotEmpty) {
        return matches.first.name;
      }
    }

    return name;
  }

  void _openHistoryWindow(String productName, bool isSales) {
    if (productName.trim().isEmpty) return;

    Offset dialogOffset = Offset.zero;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: isSales ? "Sales History" : "Purchase History",
      barrierColor: Colors.black26,
      transitionDuration: Duration.zero,
      pageBuilder: (ctx, anim1, anim2) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Transform.translate(
              offset: dialogOffset,
              child: Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
                    Navigator.of(ctx).pop();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Dialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  clipBehavior: Clip.antiAlias,
                  elevation: 12,
                  child: SizedBox(
                    width: 1080,
                    height: 540,
                    child: Column(
                      children: [
                        GestureDetector(
                          onPanUpdate: (details) {
                            setStateDialog(() {
                              dialogOffset += details.delta;
                            });
                          },
                          child: Container(
                            height: 38,
                            color: AppColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                Icon(
                                  isSales ? Icons.shopping_cart_rounded : Icons.local_shipping_rounded,
                                  color: Colors.amber,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isSales ? "Sales History: ${productName.toUpperCase()}" : "Purchase History: ${productName.toUpperCase()}",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    "Press ESC to Close | Drag header to move",
                                    style: TextStyle(color: Colors.white70, fontSize: 10, fontStyle: FontStyle.italic),
                                  ),
                                ),
                                const Spacer(),
                                Tooltip(
                                  message: "Pop out to separate OS Window",
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.of(ctx).pop();
                                      spawnOSWindow(isSales ? "sales_history" : "purchase_history", productName.trim());
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                      child: Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 16),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () => Navigator.of(ctx).pop(),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    child: Icon(Icons.close, color: Colors.white, size: 18),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: isSales
                              ? SalesHistoryScreen(productName: productName)
                              : PurchaseHistoryScreen(productName: productName),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFooter() {
    return PurchaseFooter(
      recentPurchasesList: _purchaseHistoryList(),
      purchaseHistoryList: _salesHistoryList(),
      historyProductName: _historyProductName,
      remarksCtrl: _remarksCtrl,
      remarksFocus: _remarksFocus,
      totalCalculationSection: _totalCalculationSection(),
      showRemarks: false,
      section1Title: _historyProductName.isEmpty ? "Purchase History" : "Purchase History of $_historyProductName",
      section1Headers: const [
        {'title': 'Date', 'width': 65.0},
        {'title': 'Entry No', 'width': 60.0},
        {'title': 'Supplier', 'flex': 2},
        {'title': 'Batch', 'width': 65.0},
        {'title': 'MRP', 'width': 55.0, 'align': Alignment.centerRight},
        {'title': 'P.Rate', 'width': 55.0, 'align': Alignment.centerRight},
        {'title': 'Profit %', 'width': 55.0, 'align': Alignment.centerRight},
      ],
      section1Flex: 5,
      section2Title: _historyProductName.isEmpty ? "Sales History" : "Sales History of $_historyProductName",
      section2Headers: const [
        {'title': 'Date', 'width': 65.0},
        {'title': 'Inv No', 'width': 60.0},
        {'title': 'Patient / Doctor', 'flex': 2},
        {'title': 'MRP', 'width': 55.0, 'align': Alignment.centerRight},
        {'title': 'S.Rate', 'width': 55.0, 'align': Alignment.centerRight},
        {'title': 'Qty', 'width': 40.0, 'align': Alignment.centerRight},
        {'title': 'Disc%', 'width': 45.0, 'align': Alignment.centerRight},
      ],
      section2Flex: 5,
    );
  }

  Widget _buildShortcutLegend() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Colors.grey.shade900,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: const [
          _ShortcutTag("F2", "New"),
          _ShortcutTag("F6", "Save"),
          _ShortcutTag("Enter", "Next"),
          _ShortcutTag("S+Enter", "Prev"),
          _ShortcutTag("C+Z", "Undo"),
        ],
      ),
    );
  }
}

class _ShortcutTag extends StatelessWidget {
  final String keyName;
  final String label;
  const _ShortcutTag(this.keyName, this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        children: [
          Text(keyName, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 10)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 10)),
        ],
      ),
    );
  }
}

class _ResizableHdr extends StatelessWidget {
  final int index;
  final String title;
  final String? tooltip;
  final double width;
  final Function(double) onResize;
  final TextAlign align;
  const _ResizableHdr(this.index, this.title, {this.tooltip, required this.width, required this.onResize, this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    final String msg = tooltip ?? title;
    Widget child = Container(
      width: width,
      decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.white24, width: 0.5))),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.center ? Alignment.center : Alignment.centerRight),
              child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
    );
    if (msg.isNotEmpty) {
      child = ERPTooltip(message: msg, child: child);
    }
    return child;
  }
}

class _Hdr extends StatelessWidget {
  final String title;
  final String? tooltip;
  final double? width;
  final int? flex;
  final TextAlign align;

  const _Hdr(this.title, {this.tooltip, this.width, this.flex, this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    final String msg = tooltip ?? title;
    Widget child = Container(
      width: width,
      alignment: align == TextAlign.left
          ? Alignment.centerLeft
          : (align == TextAlign.center ? Alignment.center : Alignment.centerRight),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Colors.white24, width: 0.5)),
      ),
      child: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
    if (msg.isNotEmpty) {
      child = ERPTooltip(message: msg, child: child);
    }
    return flex != null ? Expanded(flex: flex!, child: child) : child;
  }
}

class _GridCell extends StatelessWidget {
  final String text;
  final double? width;
  final int? flex;
  final TextAlign align;
  final Color? color;
  final FontWeight? fontWeight;
  final Color? bgColor;

  const _GridCell(
    this.text, {
    this.width,
    this.flex,
    this.align = TextAlign.left,
    this.color,
    this.fontWeight,
  }) : bgColor = null;

  @override
  Widget build(BuildContext context) {
    Widget child = Container(
      width: width,
      alignment: align == TextAlign.left
          ? Alignment.centerLeft
          : (align == TextAlign.center ? Alignment.center : Alignment.centerRight),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(right: BorderSide(color: Colors.grey.shade300, width: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color ?? Colors.black,
          fontWeight: fontWeight ?? FontWeight.normal,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
    return flex != null ? Expanded(flex: flex!, child: child) : child;
  }
}
