import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:file_picker/file_picker.dart';

import '../providers/pharmacy_provider.dart';
import '../services/whatsapp_service.dart';
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

class SalesReturnScreen extends StatefulWidget {
  final String? initialReturnNo;
  const SalesReturnScreen({super.key, this.initialReturnNo});

  @override
  State<SalesReturnScreen> createState() => _SalesReturnScreenState();
}

class _SalesReturnScreenState extends State<SalesReturnScreen> {
  final List<SaleItem> _items = [];
  List<SaleItem> _originalInvoiceItems = [];
  bool _isExistingEntry = false;
  bool _isDeleted = false;

  String _entryNo = "";
  SaleReturnInvoice? _originalLoadedReturn;
  final TextEditingController _salesInvCtrl = TextEditingController();
  final TextEditingController _patientCtrl = TextEditingController();
  final TextEditingController _mobileCtrl = TextEditingController();
  final TextEditingController _doctorCtrl = TextEditingController(text: "D1");

  DateTime _date = DateTime.now();
  String _customerAcc = "Cash";

  int _gstMode = 1; // 1 = Gst, 2 = Non Gst


  final FocusNode _rootFocus = FocusNode();
  final FocusNode _salesInvFocus = FocusNode();
  final FocusNode _patientFocus = FocusNode();
  final FocusNode _mobileFocus = FocusNode();
  final FocusNode _doctorFocus = FocusNode();

  final TextEditingController _subTotalCtrl = TextEditingController(text: "0.00");
  final TextEditingController _footerDiscPctCtrl = TextEditingController(text: "0");
  final TextEditingController _footerDiscAmtCtrl = TextEditingController(text: "0.00");
  final TextEditingController _otherChargePctCtrl = TextEditingController(text: "0");
  final TextEditingController _otherChargeAmtCtrl = TextEditingController(text: "0.00");
  final TextEditingController _roundOffCtrl = TextEditingController(text: "0.00");
  final TextEditingController _grandTotalCtrl = TextEditingController(text: "0.00");
  final TextEditingController _narrationCtrl = TextEditingController();

  final ValueNotifier<double> _subTotalNotifier = ValueNotifier(0.0);
  final ValueNotifier<double> _grandTotalNotifier = ValueNotifier(0.0);

  final ValueNotifier<int> _totalQtyNotifier = ValueNotifier(0);
  final ValueNotifier<double> _totalDiscAmtNotifier = ValueNotifier(0.0);
  final ValueNotifier<double> _totalGrossNotifier = ValueNotifier(0.0);
  final ValueNotifier<double> _totalNetNotifier = ValueNotifier(0.0);
  final ValueNotifier<double> _totalGstAmtNotifier = ValueNotifier(0.0);

  final ScrollController _gridScrollCtrl = ScrollController();
  final ScrollController _verticalGridScrollCtrl = ScrollController();
  final ScrollController _dropdownScrollCtrl = ScrollController();

  final Map<int, double> _colWidths = {
    0: 40,   1: 250,  2: 80,   3: 100,  4: 70,   5: 60,   6: 60,   7: 80,
    8: 60,   9: 80,   10: 80,  11: 80,  12: 80,  13: 80,  14: 80,  15: 100, 16: 40,
  };

  final List<int> _editableCols = [1, 2, 3, 4, 6, 8];

  final Map<int, Map<int, TextEditingController>> _gridCtrls = {};
  final Map<int, Map<int, FocusNode>> _gridFocusNodes = {};
  final ValueNotifier<IntPair?> _focusNotifier = ValueNotifier(const IntPair(0, 1));
  int get _focusedRowIndex => _focusNotifier.value?.row ?? -1;
  int get _focusedColIndex => _focusNotifier.value?.col ?? 0;

  final LayerLink _searchLayer = LayerLink();
  final LayerLink _batchLayer = LayerLink();
  final LayerLink _patientLayer = LayerLink();
  final LayerLink _doctorLayer = LayerLink();

  final ValueNotifier<List<Product>> _searchList = ValueNotifier([]);
  final ValueNotifier<List<Product>> _batchList = ValueNotifier([]);
  final ValueNotifier<List<String>> _patientSearchList = ValueNotifier([]);
  final ValueNotifier<List<String>> _doctorSearchList = ValueNotifier([]);
  final ValueNotifier<int> _searchIdx = ValueNotifier(0);

  bool _isSelectingBatch = false;
  bool _isSelectingFromDropdown = false;
  bool _isLoading = false;
  Timer? _scrollTimer;

  final List<List<SaleItem>> _undoStack = [];
  final Map<int, Set<int>> _errorCells = {};

  DateTime _parseExpiry(String exp) {
    if (exp.length != 5 || !exp.contains('/')) return DateTime(2099);
    final parts = exp.split('/');
    int m = int.tryParse(parts[0]) ?? 1;
    int y = int.tryParse(parts[1]) ?? 99;
    return DateTime(2000 + y, m + 1, 0);
  }

  void _markRowError(int row) {
    _errorCells.putIfAbsent(row, () => {});
    for (int c = 0; c <= 16; c++) {
      _errorCells[row]!.add(c);
    }
  }

  bool _isDirty = false;
  bool _isSaving = false;

  void _markDirty() {
    if (_isLoading) return;
    if (_isExistingEntry && !_isDirty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _isDirty = true);
      });
    }
  }

  // ---> NEW: DIRTY STATE INTERCEPTOR <---
  bool _hasValidItems() {
    if (_isExistingEntry) return _isDirty;

    for (int i = 0; i < _items.length; i++) {
      final it = _items[i];
      final prodName = it.product.name.trim();
      int qty = it.qty;
      final ctrlText = _getGridCtrl(i, 6).text.trim();
      if (ctrlText.isNotEmpty) {
        final parsed = int.tryParse(ctrlText) ?? 0;
        if (parsed > 0) qty = parsed;
      }

      if (prodName.isNotEmpty && qty > 0) {
        return true;
      }
    }

    final activeProdName = _getGridCtrl(_items.length, 1).text.trim();
    final activeQtyText = _getGridCtrl(_items.length, 6).text.trim();
    final activeQty = int.tryParse(activeQtyText) ?? 0;
    if (activeProdName.isNotEmpty && activeQty > 0) {
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
      if (widget.initialReturnNo != null) {
        _navigateEntry('find', searchNo: widget.initialReturnNo);
      } else {
        final next = await p.getNextSaleReturnEntryNo();
        if (mounted) setState(() => _entryNo = next);
      }
    });
    _resetPage();

    _footerDiscPctCtrl.addListener(_calculateFooter);
    _footerDiscAmtCtrl.addListener(_calculateFooter);
    _otherChargePctCtrl.addListener(_calculateFooter);
    _otherChargeAmtCtrl.addListener(_calculateFooter);

    _salesInvFocus.addListener(() {
      if (_salesInvFocus.hasFocus) {
        _focusNotifier.value = const IntPair(-1, 0);
      } else {
        if (_salesInvCtrl.text.trim().isNotEmpty && _originalInvoiceItems.isEmpty && !_isLoading) {
          _loadOriginalInvoice(_salesInvCtrl.text.trim());
        }
      }
    });
    _patientFocus.addListener(() { if (_patientFocus.hasFocus) _focusNotifier.value = const IntPair(-1, 1); });
    _mobileFocus.addListener(() { if (_mobileFocus.hasFocus) _focusNotifier.value = const IntPair(-1, 2); });
    _doctorFocus.addListener(() { if (_doctorFocus.hasFocus) _focusNotifier.value = const IntPair(-1, 3); });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _salesInvFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _gridScrollCtrl.dispose();
    _verticalGridScrollCtrl.dispose();
    _dropdownScrollCtrl.dispose();
    _rootFocus.dispose();
    _salesInvFocus.dispose();
    _patientFocus.dispose();
    _mobileFocus.dispose();
    _doctorFocus.dispose();

    _salesInvCtrl.dispose();
    _patientCtrl.dispose();
    _mobileCtrl.dispose();
    _doctorCtrl.dispose();
    _subTotalCtrl.dispose();
    _footerDiscPctCtrl.dispose();
    _footerDiscAmtCtrl.dispose();
    _roundOffCtrl.dispose();
    _grandTotalCtrl.dispose();
    _otherChargePctCtrl.dispose();
    _otherChargeAmtCtrl.dispose();
    _narrationCtrl.dispose();
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
    List<SaleItem> lastState = _undoStack.removeLast();
    setState(() {
      _items.clear();
      _errorCells.clear();
      _items.addAll(lastState);
      for (int i = 0; i < _items.length; i++) {
        _calculateItem(i);
      }

    });
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
          _onBlur(row, col, _getGridCtrl(row, col).text);
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
            it.product = Product(id: best.id, name: best.name, hsnCode: best.hsnCode)
              ..packSize = best.packSize
              ..mrp = best.mrp
              ..salePrice = best.salePrice
              ..purchaseRate = best.purchaseRate
              ..gstPercent = best.gstPercent;
            _getGridCtrl(row, 1).text = best.name;
            _getGridCtrl(row, 2).text = best.hsnCode;
          } else {
            it.product.name = value;
          }
        } else {
          it.product.name = value;
        }
      } else if (col == 2) {
        it.product.hsnCode = value;
      } else if (col == 3) {
        if (value.trim().isEmpty && it.product.name.isNotEmpty) {
          final p = Provider.of<PharmacyProvider>(context, listen: false);
          final availableBatches = p.products.where((prod) => prod.name.toLowerCase() == it.product.name.toLowerCase() && prod.stock > 0).toList();

          if (availableBatches.isNotEmpty) {
            availableBatches.sort((a, b) => _parseExpiry(a.expiry).compareTo(_parseExpiry(b.expiry)));
            final bestBatch = availableBatches.first;

            it.product.batch = bestBatch.batch;
            it.product.expiry = bestBatch.expiry;
            it.product.stock = bestBatch.stock;

            double ps = bestBatch.packSize == 0 ? 1 : bestBatch.packSize.toDouble();
            it.mrp = bestBatch.mrp / ps;
            double unitSRate = (bestBatch.salePrice > 0 ? bestBatch.salePrice : bestBatch.mrp) / ps;
            it.sRate = unitSRate;
            it.taxableSP = unitSRate;
            it.gstPercent = bestBatch.gstPercent;
            it.packin = bestBatch.packSize;

            _getGridCtrl(row, 3).text = bestBatch.batch;
            _getGridCtrl(row, 4).text = bestBatch.expiry;
            _calculateItem(row);
          }
        } else {
          it.product.batch = value;
        }
      } else if (col == 4) {
        it.product.expiry = value;
      }

      if ([6, 8].contains(col)) {
        String val = value.trim().isEmpty ? "0" : value;
        if (col == 6) {
          it.qty = int.tryParse(val) ?? 0;
          if (!_getGridFocusNode(row, 6).hasFocus) {
            _getGridCtrl(row, col).text = it.qty.toString();
          }
        } else if (col == 8) {
          it.discPercent = double.tryParse(val) ?? 0.0;
          if (!_getGridFocusNode(row, 8).hasFocus) {
            _getGridCtrl(row, col).text = it.discPercent.toStringAsFixed(2);
          }
        }
        _calculateItem(row);
      }
    }
  }

  void _closeAllDropdowns() {
    _searchList.value = [];
    _batchList.value = [];
    _patientSearchList.value = [];
    _doctorSearchList.value = [];
    _searchIdx.value = 0;
  }

  void _moveFocus(int row, int col, {bool autoOpen = false}) {
    int safeRow = row.clamp(-1, _items.length);
    int safeCol = col;

    if (safeRow >= 0 && _salesInvCtrl.text.trim().isEmpty) {
      _closeAllDropdowns();
      _focusNotifier.value = const IntPair(-1, 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _salesInvFocus.requestFocus();
          _salesInvCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _salesInvCtrl.text.length);
          AppDialogs.showFastDialog(
            context: context,
            title: "Ref Invoice Required",
            content: "Please enter a Reference Invoice Number (Ref Inv No) first before adding or editing items.",
          );
        }
      });
      return;
    }

    if (safeRow >= 0 && !_editableCols.contains(col)) {
      if (col < _editableCols.first) {
        safeCol = _editableCols.first;
      } else if (col > _editableCols.last) safeCol = _editableCols.last;
      else {
        safeCol = _editableCols.reduce((a, b) => (a - col).abs() < (b - col).abs() ? a : b);
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
        FocusNode fn;
        TextEditingController ctrl;
        if (safeCol == 0) { fn = _salesInvFocus; ctrl = _salesInvCtrl; }
        else if (safeCol == 1) { fn = _patientFocus; ctrl = _patientCtrl; }
        else if (safeCol == 2) { fn = _mobileFocus; ctrl = _mobileCtrl; }
        else { fn = _doctorFocus; ctrl = _doctorCtrl; }

        if (!fn.hasFocus) {
          fn.requestFocus();
          ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
        }
      } else {
        final fn = _getGridFocusNode(safeRow, safeCol);
        final ctrl = _getGridCtrl(safeRow, safeCol);
        final initialText = ctrl.text;

        if (!fn.hasFocus) {
          fn.requestFocus();
          if (ctrl.text == initialText) {
            ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
          }
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

    if (key == LogicalKeyboardKey.f10 || key == LogicalKeyboardKey.f6) {
      _saveReturn(isEdit: _isExistingEntry);
      return true;
    }
    if (key == LogicalKeyboardKey.f2) {
      _resetPage();
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
      if (key == LogicalKeyboardKey.keyZ) { _performUndo(); return true; }
      if (key == LogicalKeyboardKey.delete && _focusedRowIndex >= 0 && _focusedRowIndex < _items.length) {
        _saveUndoState();
        setState(() {
          _items.removeAt(_focusedRowIndex);
          _errorCells.clear();
          _gridCtrls.clear();
          _gridFocusNodes.clear();
          _calculateFooter();
        });
        _moveFocus(_focusedRowIndex, 1);
        return true;
      }
    }

    final bool isOverlayOpen = _searchList.value.isNotEmpty || _batchList.value.isNotEmpty || _patientSearchList.value.isNotEmpty || _doctorSearchList.value.isNotEmpty;

    if (isOverlayOpen) {
      final list = _patientSearchList.value.isNotEmpty ? _patientSearchList.value : (_doctorSearchList.value.isNotEmpty ? _doctorSearchList.value : (_isSelectingBatch ? _batchList.value : _searchList.value));
      if (key == LogicalKeyboardKey.arrowDown) {
        _searchIdx.value = (_searchIdx.value + 1) % list.length;
        _scrollToIdx(_searchIdx.value);
        return true;
      } else if (key == LogicalKeyboardKey.arrowUp) {
        _searchIdx.value = (_searchIdx.value - 1 + list.length) % list.length;
        _scrollToIdx(_searchIdx.value);
        return true;
      } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
        if (list.isNotEmpty) {
          if (_patientSearchList.value.isNotEmpty) {
            _onNameSelected(_patientCtrl, _patientSearchList, list[_searchIdx.value] as String, _mobileFocus);
          } else if (_doctorSearchList.value.isNotEmpty) _onNameSelected(_doctorCtrl, _doctorSearchList, list[_searchIdx.value] as String, null);
          else if (_isSelectingBatch) _finalizeBatchSelection(list[_searchIdx.value] as Product);
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
          if (_salesInvCtrl.text.trim().isNotEmpty) {
            _loadOriginalInvoice(_salesInvCtrl.text.trim());
          } else {
            _moveFocus(-1, 1);
          }
        } else if (col < 3) _moveFocus(-1, col + 1);
        else _moveFocus(0, 1, autoOpen: true);
        return true;
      }
      return false;
    }

    final ctrl = _getGridCtrl(row, col);

    if ((key == LogicalKeyboardKey.tab || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) && isShift) {
      int curIdx = _editableCols.indexOf(col);
      if (curIdx > 0) {
        _moveFocus(row, _editableCols[curIdx - 1]);
      } else if (row > 0) _moveFocus(row - 1, _editableCols.last);
      return true;
    }

    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.tab) {
      _onFieldSubmitted(row, col);
      return true;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      int curIdx = _editableCols.indexOf(col);
      if (curIdx > 0) { _moveFocus(row, _editableCols[curIdx - 1]); return true; }
      else if (row > 0) { _moveFocus(row - 1, _editableCols.last); return true; }
    }

    if (key == LogicalKeyboardKey.arrowRight && (!ctrl.selection.isValid || ctrl.selection.baseOffset >= ctrl.text.length)) {
      int curIdx = _editableCols.indexOf(col);
      if (curIdx != -1 && curIdx < _editableCols.length - 1) { _moveFocus(row, _editableCols[curIdx + 1]); return true; }
      else if (row < _items.length) { _moveFocus(_items.length, _editableCols[0]); return true; }
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

  void _scrollToIdx(int index) {
    if (!_dropdownScrollCtrl.hasClients) return;
    const double itemHeight = 24.0;
    const double viewportHeight = 168.0;

    double targetOffset = index * itemHeight;
    double currentOffset = _dropdownScrollCtrl.offset;

    if (targetOffset < currentOffset) {
      _dropdownScrollCtrl.jumpTo(targetOffset);
    } else if (targetOffset + itemHeight > currentOffset + viewportHeight) {
      _dropdownScrollCtrl.jumpTo(targetOffset - viewportHeight + itemHeight);
    }
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
        return;
      }

      final p = Provider.of<PharmacyProvider>(context, listen: false);
      String prodName = row < _items.length ? _items[row].product.name : _getGridCtrl(row, 1).text;

      final availableBatches = p.products.where((b) => b.name.toLowerCase() == prodName.toLowerCase() && b.stock > 0).toList();
      final match = availableBatches.where((b) => b.batch.toUpperCase() == typed).toList();

      if (match.isNotEmpty) {
        _finalizeBatchSelection(match.first);
      } else if (typed.isEmpty) {
        if (availableBatches.isNotEmpty) {
          availableBatches.sort((a, b) => _parseExpiry(a.expiry).compareTo(_parseExpiry(b.expiry)));
          _finalizeBatchSelection(availableBatches.first);
        } else {
          _moveFocus(row, 4);
        }
      } else {
        _moveFocus(row, 4);
      }
    } else {
      int curIdx = _editableCols.indexOf(col);
      if (curIdx != -1 && curIdx < _editableCols.length - 1) {
        _moveFocus(row, _editableCols[curIdx + 1]);
      } else {
        _moveFocus(_items.length, 1, autoOpen: true);
      }
    }
  }

  void _onHeaderSearch(String query, ValueNotifier<List<String>> targetList, List<String> Function(PharmacyProvider) source) {
    if (query.trim().isEmpty) { targetList.value = []; return; }
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final all = source(p);
    final startsWith = all.where((name) => name.toLowerCase().startsWith(query.toLowerCase())).toList();
    final contains = all.where((name) => !name.toLowerCase().startsWith(query.toLowerCase()) && name.toLowerCase().contains(query.toLowerCase())).toList();
    targetList.value = [...startsWith, ...contains].take(15).toList();
    _searchIdx.value = 0;
  }

  void _onNameSelected(TextEditingController ctrl, ValueNotifier<List<String>> list, String name, FocusNode? next) {
    ctrl.text = name;
    list.value = [];
    if (next != null) {
      next.requestFocus();
    } else {
      _moveFocus(0, 1, autoOpen: true);
    }
    setState(() {});
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
    final qTrim = q.trim().toLowerCase();

    // If items exist in original invoice, search within them; otherwise search general master via provider
    if (_originalInvoiceItems.isEmpty) {
      final p = Provider.of<PharmacyProvider>(context, listen: false);
      _searchList.value = p.searchProducts(qTrim, includeGenerics: false);
      _searchIdx.value = 0;
      return;
    }

    final sourceProducts = _originalInvoiceItems.map((it) => it.product).toList();

    final starts = sourceProducts.where((p) => p.name.trim().toLowerCase().startsWith(qTrim)).toList();
    starts.sort((a, b) => b.stock.compareTo(a.stock));

    final contains = sourceProducts.where((p) => !p.name.trim().toLowerCase().startsWith(qTrim) && p.name.trim().toLowerCase().contains(qTrim)).toList();
    contains.sort((a, b) => b.stock.compareTo(a.stock));

    _searchList.value = qTrim.isEmpty ? sourceProducts.take(50).toList() : [...starts, ...contains];
    _searchIdx.value = 0;
  }

  void _startBatchSearch(int row, String q) {
    if (!_isSelectingBatch) {
      setState(() => _isSelectingBatch = true);
    }
    _searchList.value = [];
    String prodName = row < _items.length ? _items[row].product.name : _getGridCtrl(row, 1).text;

    final trimmed = q.trim().toLowerCase();
    if (prodName.isEmpty) { _batchList.value = []; return; }

    List<Product> rawMatches = [];
    if (_originalInvoiceItems.isNotEmpty) {
      final matches = _originalInvoiceItems.where((it) => it.product.name.trim().toLowerCase() == prodName.trim().toLowerCase()).toList();
      for (var m in matches) {
        if (trimmed.isEmpty || m.product.batch.toLowerCase().contains(trimmed)) {
          rawMatches.add(m.product);
        }
      }
    }

    if (rawMatches.isEmpty) {
      final p = Provider.of<PharmacyProvider>(context, listen: false);
      final all = p.products.where((it) => it.name.toLowerCase() == prodName.toLowerCase()).toList();
      rawMatches = trimmed.isEmpty ? all : all.where((b) => b.batch.toLowerCase().contains(trimmed)).toList();
    }

    final Map<String, Product> consolidated = {};
    for (var b in rawMatches) {
      String key = "${b.batch}_${b.expiry}_${b.mrp}_${b.packSize}_${b.salePrice}_${b.gstPercent}";
      if (!consolidated.containsKey(key)) {
        consolidated[key] = Product(
            id: b.id, name: b.name, batch: b.batch, expiry: b.expiry,
            mrp: b.mrp, salePrice: b.salePrice, purchaseRate: b.purchaseRate,
            landingCost: b.landingCost, packSize: b.packSize, gstPercent: b.gstPercent,
            rack: b.rack, category: b.category, manufacturer: b.manufacturer,
            genericName: b.genericName, supplier: b.supplier, hsnCode: b.hsnCode
        )..stock = b.stock;
      }
    }

    List<Product> matches = consolidated.values.toList();
    matches.sort((a, b) {
      int expComp = _parseExpiry(a.expiry).compareTo(_parseExpiry(b.expiry));
      if (expComp != 0) return expComp;
      return b.stock.compareTo(a.stock);
    });

    _batchList.value = matches;
    _searchIdx.value = 0;
  }

  void _onProductSelected(Product p) {
    _saveUndoState();

    SaleItem? matchedInvoiceItem;
    for (var orig in _originalInvoiceItems) {
      if (orig.product.name.trim().toLowerCase() == p.name.trim().toLowerCase()) {
        matchedInvoiceItem = orig;
        break;
      }
    }

    setState(() {
      final row = _focusedRowIndex;
      _getGridCtrl(row, 1, p.name).text = p.name;
      _getGridCtrl(row, 2, p.hsnCode).text = p.hsnCode;

      if (matchedInvoiceItem != null) {
        final newItem = matchedInvoiceItem.clone();
        _getGridCtrl(row, 3, newItem.product.batch).text = newItem.product.batch;
        _getGridCtrl(row, 4, newItem.product.expiry).text = newItem.product.expiry;
        _getGridCtrl(row, 6, newItem.qty.toString()).text = newItem.qty.toString();
        _getGridCtrl(row, 8, newItem.discPercent.toStringAsFixed(2)).text = newItem.discPercent.toStringAsFixed(2);

        if (row == _items.length) {
          _items.add(newItem);
        } else {
          _items[row] = newItem;
        }
      } else {
        _getGridCtrl(row, 3).clear();
        double ps = p.packSize == 0 ? 1 : p.packSize.toDouble();
        double unitMrp = p.mrp / ps;
        double unitSRate = (p.salePrice > 0 ? p.salePrice : p.mrp) / ps;
        if (row == _items.length) {
          _items.add(SaleItem(product: Product(id: p.id, name: p.name)..packSize=p.packSize..mrp=p.mrp..salePrice=p.salePrice..purchaseRate=p.purchaseRate..gstPercent=p.gstPercent..hsnCode=p.hsnCode)
            ..qty = 1 ..packin = p.packSize ..mrp = unitMrp ..sRate = unitSRate ..taxableSP = unitSRate ..gstPercent = p.gstPercent);
        } else {
          final it = _items[row];
          it.product = Product(id: p.id, name: p.name)..packSize=p.packSize..mrp=p.mrp..salePrice=p.salePrice..purchaseRate=p.purchaseRate..gstPercent=p.gstPercent..hsnCode=p.hsnCode;
          it.packin = p.packSize; it.mrp = unitMrp; it.sRate = unitSRate; it.taxableSP = unitSRate; it.gstPercent = p.gstPercent;
        }
      }
      _calculateItem(row);
    });
    _searchList.value = [];
    _moveFocus(_focusedRowIndex, 6, autoOpen: false);
  }

  void _finalizeBatchSelection(Product p) {
    setState(() {
      final row = _focusedRowIndex;
      _getGridCtrl(row, 3, p.batch).text = p.batch;
      _getGridCtrl(row, 4, p.expiry).text = p.expiry;

      if (row < _items.length) {
        final it = _items[row];
        it.product.batch = p.batch;
        it.product.expiry = p.expiry;
        it.product.stock = p.stock;

        if (p.mrp > 0) it.product.mrp = p.mrp;
        if (p.salePrice > 0) it.product.salePrice = p.salePrice;
        double ps = p.packSize == 0 ? 1 : p.packSize.toDouble();
        it.mrp = it.product.mrp / ps;
        double unitSRate = (it.product.salePrice > 0 ? it.product.salePrice : it.product.mrp) / ps;
        it.sRate = unitSRate;
        it.taxableSP = unitSRate;
        it.gstPercent = p.gstPercent;
        _calculateItem(row);
      }
    });
    _isSelectingBatch = false;
    _batchList.value = [];
    _moveFocus(_focusedRowIndex, 6);
  }

  void _calculateItem(int row) {
    if (row >= _items.length) return;
    final it = _items[row];

    double gross = it.sRate * it.qty;
    it.discAmt = TaxCalculator.round(gross * (it.discPercent / 100));
    double netInclusive = gross - it.discAmt;

    it.gstPercent = TaxCalculator.roundGstPercent(it.gstPercent);
    if (_gstMode == 1 && it.gstPercent > 0) {
      final res = TaxCalculator.calculateInclusive(netInclusive, it.gstPercent);
      it.gstAmt = res.gstAmount;
      it.total = res.totalAmount;
    } else {
      it.gstAmt = 0.0;
      it.total = TaxCalculator.round(netInclusive);
    }

    double packMrp = it.product.mrp > 0 ? it.product.mrp : it.mrp * (it.packin > 0 ? it.packin : 1);
    _getGridCtrl(row, 5).text = it.packin.toString();
    _getGridCtrl(row, 7).text = packMrp.toStringAsFixed(2);
    _getGridCtrl(row, 9).text = it.discAmt.toStringAsFixed(2);
    _getGridCtrl(row, 10).text = it.taxableSP.toStringAsFixed(2);
    _getGridCtrl(row, 11).text = it.mrp.toStringAsFixed(2);
    _getGridCtrl(row, 12).text = gross.toStringAsFixed(2);
    _getGridCtrl(row, 13).text = netInclusive.toStringAsFixed(2);
    _getGridCtrl(row, 14).text = it.gstAmt.toStringAsFixed(2);
    _getGridCtrl(row, 15).text = it.total.toStringAsFixed(2);

    _calculateFooter();
  }

  void _calculateFooter() {
    double totalQty = 0;
    double totalDiscAmt = 0;
    double totalGross = 0;
    double totalNet = 0;
    double totalGstAmt = 0;
    double sub = 0;

    for (var it in _items) {
      totalQty += it.qty;
      totalDiscAmt += it.discAmt;
      double gross = it.sRate * it.qty;
      totalGross += gross;
      totalNet += (gross - it.discAmt);
      totalGstAmt += it.gstAmt;
      sub += it.total;
    }

    _totalQtyNotifier.value = totalQty.toInt();
    _totalDiscAmtNotifier.value = totalDiscAmt;
    _totalGrossNotifier.value = totalGross;
    _totalNetNotifier.value = totalNet;
    _totalGstAmtNotifier.value = totalGstAmt;

    double discPct = double.tryParse(_footerDiscPctCtrl.text) ?? 0;
    double discAmt = double.tryParse(_footerDiscAmtCtrl.text) ?? 0;
    double otherPct = double.tryParse(_otherChargePctCtrl.text) ?? 0;
    double otherAmt = double.tryParse(_otherChargeAmtCtrl.text) ?? 0;

    double totalDisc = discAmt + (sub * (discPct / 100));
    double totalOther = otherAmt + (sub * (otherPct / 100));

    double finalVal = sub - totalDisc + totalOther;
    double rounded = finalVal.roundToDouble();
    double roundOff = rounded - finalVal;

    _subTotalNotifier.value = sub;
    _grandTotalNotifier.value = rounded;

    _subTotalCtrl.text = sub.toStringAsFixed(2);
    _roundOffCtrl.text = roundOff.toStringAsFixed(2);
    _grandTotalCtrl.text = rounded.toStringAsFixed(2);
  }

  void _loadOriginalInvoice(String invoiceNo) async {
    if (invoiceNo.trim().isEmpty || _isLoading) return;
    setState(() => _isLoading = true);

    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final originalInvoice = await provider.getSaleInvoiceById(invoiceNo.trim());

    if (originalInvoice != null) {
      setState(() {
        _salesInvCtrl.text = originalInvoice.entryNo;
        _patientCtrl.text = originalInvoice.patient;
        _mobileCtrl.text = originalInvoice.mobile;
        _doctorCtrl.text = originalInvoice.doctor;
        _customerAcc = originalInvoice.customerAcc;
        _gstMode = originalInvoice.taxType == "Gst" ? 1 : 2;

        _items.clear();
        _gridCtrls.clear();
        _gridFocusNodes.clear();

        _originalInvoiceItems = originalInvoice.items.map((e) => e.clone()).toList();

        for (var item in originalInvoice.items) {
          _items.add(item.clone());
        }
        for (int i = 0; i < _items.length; i++) {
          _calculateItem(i);
        }
      });
      if (_items.isNotEmpty) {
        _moveFocus(0, 6);
      } else {
        _moveFocus(0, 1);
      }
    } else {
      if (mounted) {
        setState(() {
          _originalInvoiceItems.clear();
        });
        AppDialogs.showFastDialog(context: context, title: "Invoice Not Found", content: "Original invoice #$invoiceNo could not be found.");
      }
      _moveFocus(-1, 0);
    }

    setState(() => _isLoading = false);
  }

  void _navigateEntry(String dir, {String? searchNo}) async {
    // ---> THE FIX: Protect against losing unsaved edits <---
    if (_isExistingEntry && _isDirty) {
      bool? discard = await _promptDiscardChanges();
      if (discard != true) return; // User chose to stay
    }

    _closeAllDropdowns();
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    setState(() => _isLoading = true);

    try {
      String targetNo = searchNo ?? _entryNo;
      final data = await p.navigateInvoice(targetNo, dir, isSaleReturn: true);

      if (data != null && data['is_deleted'] != 1 && mounted) {
        String actualNo = data['entry_no']?.toString() ?? targetNo;
        final items = await p.getInvoiceItems(actualNo, isSaleReturn: true);

        setState(() {
          _isExistingEntry = true;
          _isDeleted = false;
          _isDirty = false; // Freshly loaded, reset dirty flag
          String cleanNo = actualNo.startsWith("SRET-") ? actualNo.substring(5) : actualNo;
          if (cleanNo.contains('_')) {
            cleanNo = cleanNo.substring(cleanNo.indexOf('_') + 1);
          }
          _entryNo = cleanNo;
          _date = DateTime.tryParse(data['date'].toString()) ?? DateTime.now();
          _customerAcc = data['customer_acc']?.toString() ?? 'Cash';
          _patientCtrl.text = data['patient']?.toString() ?? '';
          _doctorCtrl.text = data['doctor']?.toString() ?? '';
          String origInvNo = data['original_invoice_no']?.toString() ?? '';
          _salesInvCtrl.text = origInvNo;
          if (origInvNo.isNotEmpty) {
            p.getSaleInvoiceById(origInvNo).then((origInv) {
              if (origInv != null && mounted) {
                setState(() {
                  _originalInvoiceItems = origInv.items.map((e) => e.clone()).toList();
                });
              }
            });
          } else {
            _originalInvoiceItems.clear();
          }

          _gstMode = (data['gst_mode'] as int?) ?? 1;
          _subTotalCtrl.text = (data['sub_total'] as num?)?.toDouble().toStringAsFixed(2) ?? "0.00";
          _footerDiscAmtCtrl.text = (data['discount'] as num?)?.toDouble().toStringAsFixed(2) ?? "0.00";
          _roundOffCtrl.text = (data['round_off'] as num?)?.toDouble().toStringAsFixed(2) ?? "0.00";
          _narrationCtrl.text = data['narration']?.toString() ?? '';

          _items.clear();
          _gridCtrls.clear();
          _gridFocusNodes.clear();

          for (var m in items) {
            int qtyVal = (m['qty'] as num?)?.toInt() ?? (m['quantity'] as num?)?.toInt() ?? 0;
            String expiryVal = m['expiry']?.toString() ?? m['expiry_date']?.toString() ?? '';
            double mrpVal = (m['mrp'] as num?)?.toDouble() ?? (m['master_mrp'] as num?)?.toDouble() ?? 0.0;
            double sRateVal = (m['sale_rate'] as num?)?.toDouble() ?? (m['s_rate'] as num?)?.toDouble() ?? (m['master_srate'] as num?)?.toDouble() ?? 0.0;
            double discPctVal = (m['disc_percent'] as num?)?.toDouble() ?? 0.0;
            double discAmtVal = (m['disc_amt'] as num?)?.toDouble() ?? 0.0;
            double gstPctVal = TaxCalculator.roundGstPercent((m['gst_percent'] as num?)?.toDouble() ?? (m['master_gst'] as num?)?.toDouble() ?? 12.0);
            int packVal = (m['packing'] as int?) ?? (m['packin'] as int?) ?? (m['master_packing'] as int?) ?? 1;
            String hsnVal = m['hsn_code']?.toString() ?? m['master_hsn']?.toString() ?? '';

            double ps = packVal > 0 ? packVal.toDouble() : 1.0;
            double unitMrp = mrpVal / ps;
            double unitSRate = (sRateVal > 0 && sRateVal == mrpVal && packVal > 1)
                ? (sRateVal / ps)
                : (sRateVal > 0 ? sRateVal : unitMrp);

            _items.add(SaleItem(
              product: Product(
                id: m['product_id']?.toString() ?? '', 
                name: m['product_name']?.toString() ?? m['master_product_name']?.toString() ?? '', 
                batch: m['batch_number']?.toString() ?? '', 
                expiry: expiryVal,
                hsnCode: hsnVal,
                purchaseRate: (m['purchase_rate'] as num?)?.toDouble() ?? 0.0,
                landingCost: (m['landing_cost'] as num?)?.toDouble() ?? 0.0,
                supplier: m['supplier_name']?.toString() ?? "",
                packSize: packVal,
                gstPercent: gstPctVal,
                mrp: mrpVal,
                salePrice: sRateVal,
              ),
              qty: qtyVal,
              packin: packVal,
              mrp: unitMrp,
              sRate: unitSRate,
              taxableSP: unitSRate,
              discPercent: discPctVal,
              discAmt: discAmtVal,
              gstPercent: gstPctVal,
              total: (m['total'] as num?)?.toDouble() ?? 0.0,
              purchaseRate: (m['purchase_rate'] as num?)?.toDouble() ?? 0.0,
              landingCost: (m['landing_cost'] as num?)?.toDouble() ?? 0.0,
              supplier: m['supplier_name']?.toString() ?? "",
            ));
          }
          for (int i = 0; i < _items.length; i++) {
            _calculateItem(i);
          }
          _calculateFooter();

          _originalLoadedReturn = SaleReturnInvoice(
            entryNo: _entryNo,
            date: _date,
            customerAcc: _customerAcc,
            patient: _patientCtrl.text,
            doctor: _doctorCtrl.text,
            originalInvoiceNo: _salesInvCtrl.text.trim(),
            items: _items.map((it) => it.clone()).toList(),
            subTotal: double.tryParse(_subTotalCtrl.text) ?? 0.0,
            discount: double.tryParse(_footerDiscAmtCtrl.text) ?? 0.0,
            roundOff: double.tryParse(_roundOffCtrl.text) ?? 0.0,
            grandTotal: _grandTotalNotifier.value,
            narration: _narrationCtrl.text.trim(),
            gstMode: _gstMode,
          );
        });
      } else if (data != null && data['is_deleted'] == 1) {
        _resetPage();
        AppDialogs.showFastDialog(context: context, title: "Deleted Return", content: "This sales return record was previously deleted.");
      } else if (dir == 'next') {
        if (_isExistingEntry) {
          _resetPage();
        } else {
          AppDialogs.showFastDialog(context: context, title: "Navigation", content: "End of sales return records.");
        }
      } else if (dir == 'prev') {
        AppDialogs.showFastDialog(context: context, title: "Navigation", content: "First sales return record reached.");
      }
    } catch (e) {
      debugPrint("Sale Return Nav Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
    // Patient
    final currentPatient = _patientCtrl.text.trim();
    final origPatient = _originalLoadedReturn!.patient.trim();
    if (currentPatient.toUpperCase() != origPatient.toUpperCase()) {
      addDiffLine([
        const TextSpan(text: "patient name ", style: normalStyle),
        TextSpan(text: origPatient.isEmpty ? "(blank)" : origPatient, style: redStyle),
        const TextSpan(text: " to ", style: normalStyle),
        TextSpan(text: currentPatient.isEmpty ? "(blank)" : currentPatient, style: redStyle),
        const TextSpan(text: ".", style: normalStyle),
      ]);
    }

    // Doctor
    final currentDoctor = _doctorCtrl.text.trim();
    final origDoctor = _originalLoadedReturn!.doctor.trim();
    if (currentDoctor.toUpperCase() != origDoctor.toUpperCase()) {
      addDiffLine([
        const TextSpan(text: "doctor name ", style: normalStyle),
        TextSpan(text: origDoctor.isEmpty ? "(blank)" : origDoctor, style: redStyle),
        const TextSpan(text: " to ", style: normalStyle),
        TextSpan(text: currentDoctor.isEmpty ? "(blank)" : currentDoctor, style: redStyle),
        const TextSpan(text: ".", style: normalStyle),
      ]);
    }

    // Customer Account
    final currentAcc = _customerAcc.trim();
    final origAcc = _originalLoadedReturn!.customerAcc.trim();
    if (currentAcc.toUpperCase() != origAcc.toUpperCase() && currentAcc.isNotEmpty) {
      addDiffLine([
        const TextSpan(text: "account name ", style: normalStyle),
        TextSpan(text: origAcc.isEmpty ? "(blank)" : origAcc, style: redStyle),
        const TextSpan(text: " to ", style: normalStyle),
        TextSpan(text: currentAcc, style: redStyle),
        const TextSpan(text: ".", style: normalStyle),
      ]);
    }

    // Ref Invoice No
    final currentRefInv = _salesInvCtrl.text.trim();
    final origRefInv = _originalLoadedReturn!.originalInvoiceNo.trim();
    if (currentRefInv.toUpperCase() != origRefInv.toUpperCase()) {
      addDiffLine([
        const TextSpan(text: "ref invoice no ", style: normalStyle),
        TextSpan(text: origRefInv.isEmpty ? "(blank)" : origRefInv, style: redStyle),
        const TextSpan(text: " to ", style: normalStyle),
        TextSpan(text: currentRefInv.isEmpty ? "(blank)" : currentRefInv, style: redStyle),
        const TextSpan(text: ".", style: normalStyle),
      ]);
    }

    // Footer Discount
    final currentDiscAmt = double.tryParse(_footerDiscAmtCtrl.text) ?? 0.0;
    final origDiscAmt = _originalLoadedReturn!.discount;
    if ((currentDiscAmt - origDiscAmt).abs() > 0.01) {
      addDiffLine([
        const TextSpan(text: "footer discount ", style: normalStyle),
        TextSpan(text: "₹${origDiscAmt.toStringAsFixed(2)}", style: redStyle),
        const TextSpan(text: " to ", style: normalStyle),
        TextSpan(text: "₹${currentDiscAmt.toStringAsFixed(2)}", style: redStyle),
        const TextSpan(text: ".", style: normalStyle),
      ]);
    }

    // 2. ITEM COMPARISONS
    final origItems = _originalLoadedReturn!.items;
    final currentValidItems = _items.where((it) => it.product.name.trim().isNotEmpty && it.qty > 0).toList();

    int maxLen = origItems.length > currentValidItems.length ? origItems.length : currentValidItems.length;

    for (int i = 0; i < maxLen; i++) {
      if (i < origItems.length && i < currentValidItems.length) {
        final orig = origItems[i];
        final curr = currentValidItems[i];

        // Product Name
        final origName = orig.product.name.trim();
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
        final origBatch = orig.product.batch.trim();
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

        // Sale Rate
        if ((orig.sRate - curr.sRate).abs() > 0.01) {
          addDiffLine([
            TextSpan(text: "sale rate ($currName) changed from ", style: normalStyle),
            TextSpan(text: "₹${orig.sRate.toStringAsFixed(2)}", style: redStyle),
            const TextSpan(text: " to ", style: normalStyle),
            TextSpan(text: "₹${curr.sRate.toStringAsFixed(2)}", style: redStyle),
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
          TextSpan(text: orig.product.name.trim(), style: redStyle),
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

    try {
      setState(() => _errorCells.clear());
      List<String> errors = [];

      if (_salesInvCtrl.text.trim().isEmpty) {
        AppDialogs.showFastDialog(
          context: context,
          title: "Ref Invoice Required",
          content: "Reference Invoice Number (Ref Inv No) is required to process a Sales Return.",
        );
        _moveFocus(-1, 0);
        return;
      }

      for (int i = 0; i < _items.length; i++) {
        final it = _items[i];
        if (it.product.name.trim().isEmpty) continue;

        if (it.qty <= 0) {
          errors.add("Row ${i + 1}: Quantity must be greater than 0");
          _markRowError(i);
        }
        if (it.product.batch.trim().isEmpty) {
          errors.add("Row ${i + 1}: Batch number is required");
          _markRowError(i);
        }

        if (_originalInvoiceItems.isNotEmpty) {
          final origMatches = _originalInvoiceItems.where(
            (o) => o.product.name.trim().toLowerCase() == it.product.name.trim().toLowerCase()
          ).toList();

          if (origMatches.isEmpty) {
            errors.add("Row ${i + 1} (${it.product.name}): Item was not part of original Invoice #${_salesInvCtrl.text.trim()}.");
            _markRowError(i);
          } else {
            int maxSoldQty = origMatches.fold(0, (sum, o) => sum + o.qty);
            if (it.qty > maxSoldQty) {
              errors.add("Row ${i + 1} (${it.product.name}): Return Qty (${it.qty}) exceeds original sold Qty ($maxSoldQty).");
              _markRowError(i);
            }
          }
        }
      }

      if (errors.isNotEmpty) {
        setState(() {});
        AppDialogs.showFastDialog(context: context, title: "Validation Error", content: errors.join("\n"));
        return;
      }

      final String currentAcc = _customerAcc.trim();
      final String currentPatient = _patientCtrl.text.trim();
      final String currentDoctor = _doctorCtrl.text.trim();

      if (currentAcc.isEmpty) {
        AppDialogs.showFastDialog(context: context, title: "Validation Error", content: "Account Name is mandatory. Please enter Account Name before saving.");
        return;
      }
      if (currentPatient.isEmpty) {
        AppDialogs.showFastDialog(context: context, title: "Validation Error", content: "Patient Name is mandatory. Please enter Patient Name before saving.");
        return;
      }
      if (currentDoctor.isEmpty) {
        AppDialogs.showFastDialog(context: context, title: "Validation Error", content: "Doctor Name is mandatory. Please enter Doctor Name before saving.");
        return;
      }

      final validItems = _items.where((it) => it.product.name.trim().isNotEmpty && it.qty > 0).toList();
      if (validItems.isEmpty) {
        AppDialogs.showFastDialog(context: context, title: "No Items", content: "Please enter at least one valid item to return.");
        return;
      }

      final double totalAmount = _grandTotalNotifier.value;
      if (totalAmount < 1.0) {
        AppDialogs.showFastDialog(context: context, title: "Invalid Total", content: "Sales return grand total must be at least ₹1.00.");
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
                "No modifications were detected on Return $_entryNo.\nThere are no changes to save.",
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
                    "Re-write Return $_entryNo?",
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
                    "The following changes will be applied to this sales return:",
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
                    "Are you sure you want to overwrite Return $_entryNo? Inventory stock will be updated accordingly.",
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

      _isSaving = true;

      setState(() => _isLoading = true);
      final p = Provider.of<PharmacyProvider>(context, listen: false);

      final entry = SaleReturnInvoice(
        entryNo: isEdit ? _entryNo : "",
        date: _date,
        customerAcc: currentAcc,
        patient: currentPatient,
        doctor: currentDoctor,
        originalInvoiceNo: _salesInvCtrl.text.trim(),
        items: validItems,
        subTotal: double.tryParse(_subTotalCtrl.text) ?? 0.0,
        discount: double.tryParse(_footerDiscAmtCtrl.text) ?? 0.0,
        roundOff: double.tryParse(_roundOffCtrl.text) ?? 0.0,
        grandTotal: totalAmount,
        narration: _narrationCtrl.text.trim(),
        gstMode: _gstMode,
      );

      final assignedNo = await p.saveSaleReturn(entry, isEdit: isEdit);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isEdit ? "Return $assignedNo Updated!" : "Return $assignedNo Saved!"),
          backgroundColor: Colors.green.shade800,
        ));
        _isDirty = false; // <--- ADD THIS LINE
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

  void _deleteSale() async {
    if (!_isExistingEntry || _isDeleted) return;

    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: "Delete Sales Return",
      content: "Are you sure you want to delete Sales Return $_entryNo? Stock will be reversed.",
      isDangerous: true,
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      final p = Provider.of<PharmacyProvider>(context, listen: false);
      try {
        await p.deleteSaleReturn(_entryNo);
        p.logAudit('DELETE_SALE_RETURN', 'Sales Return Entry $_entryNo deleted.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Return Deleted"), backgroundColor: Colors.red));
          _resetPage();
        }
      } catch (e) {
        if (mounted) AppDialogs.showFastDialog(context: context, title: "Delete Failed", content: e.toString());
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _resetPage() async {
    // ---> THE FIX: Protect against losing unsaved edits <---
    if (_isExistingEntry && _isDirty) {
      bool? discard = await _promptDiscardChanges();
      if (discard != true) return; // User chose to stay
    }

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

    final nextNo = await p.getNextSaleReturnEntryNo();

    if (mounted) {
      setState(() {
        _isExistingEntry = false;
        _isDeleted = false;
        _isDirty = false; // Reset dirty flag
        _items.clear();
        _originalInvoiceItems.clear();
        _errorCells.clear();
        _entryNo = nextNo;
        _salesInvCtrl.clear();
        _patientCtrl.text = "P1";
        _mobileCtrl.clear();
        _doctorCtrl.text = "D1";
        _gstMode = 1;
        _customerAcc = "Cash";

        _date = DateTime.now();

        _footerDiscPctCtrl.text = "0";
        _footerDiscAmtCtrl.text = "0.00";
        _otherChargePctCtrl.text = "0";
        _otherChargeAmtCtrl.text = "0.00";
        _narrationCtrl.clear();
        _roundOffCtrl.text = "0.00";
        _calculateFooter();
      });
      _moveFocus(-1, 0);
    }
  }

  void _exportToPdf() async {
    if (_items.isEmpty) return;
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final validItems = _items.where((it) => it.product.name.trim().isNotEmpty && it.qty > 0).toList();
    final entry = SaleReturnInvoice(
      entryNo: _entryNo,
      date: _date,
      customerAcc: _customerAcc,
      patient: _patientCtrl.text,
      doctor: _doctorCtrl.text,
      originalInvoiceNo: _salesInvCtrl.text,
      items: validItems,
      grandTotal: _grandTotalNotifier.value,
    );

    final doc = await InvoicePdfGenerator.buildSaleReturnPdf(entry, p.companyProfile);
    if (!mounted) return;
    PrinterService.showProfessionalPreview(context: context, doc: doc, title: "Sales Return Preview");
  }

  void _shareReturnWhatsApp() async {
    final validItems = _items.where((it) => it.product.name.trim().isNotEmpty && it.qty > 0).toList();
    if (validItems.isEmpty) {
      AppDialogs.showFastDialog(
        context: context,
        title: "No Items",
        content: "Please add valid items to the return entry before sharing via WhatsApp.",
      );
      return;
    }

    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final returnEntry = SaleReturnInvoice(
      entryNo: _entryNo.isEmpty ? "DRAFT" : _entryNo,
      date: _date,
      customerAcc: _customerAcc,
      patient: _patientCtrl.text,
      doctor: _doctorCtrl.text,
      originalInvoiceNo: _salesInvCtrl.text,
      items: validItems,
      grandTotal: _grandTotalNotifier.value,
    );

    await WhatsAppService.sendSalesReturnWithPdf(
      context: context,
      returnInvoice: returnEntry,
      customerMobile: _mobileCtrl.text.trim(),
      companyProfile: p.companyProfile,
    );
  }

  void _exportToExcel() async {
    if (_items.isEmpty) return;
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Save Sales Return Excel',
      fileName: 'Sales_Return_${_entryNo.replaceAll('/', '_')}.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (outputFile != null) {
      final validItems = _items.where((it) => it.product.name.trim().isNotEmpty && it.qty > 0).toList();
      final entry = SaleReturnInvoice(
        entryNo: _entryNo,
        date: _date,
        customerAcc: _customerAcc,
        patient: _patientCtrl.text,
        doctor: _doctorCtrl.text,
        originalInvoiceNo: _salesInvCtrl.text,
        items: validItems,
        grandTotal: _grandTotalNotifier.value,
      );
      await p.exportSingleSaleReturnToExcel(entry, outputFile);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text("Excel Exported!")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _rootFocus,
      onKeyEvent: (node, event) => _handleKeyEvent(event) ? KeyEventResult.handled : KeyEventResult.ignored,
      child: GestureDetector(
        onTap: () {
          _closeAllDropdowns();
          if (_focusedRowIndex != -1) {
            _getGridFocusNode(_focusedRowIndex, _focusedColIndex).requestFocus();
          } else {
            _salesInvFocus.requestFocus();
          }
        },
        child: FocusScope(
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
                        _colWidths.forEach((k, v) { if (k != 1) fixedTotal += v; });
                        double productWidth = 250;
                        if (con.maxWidth > (fixedTotal + 250)) {
                          productWidth = con.maxWidth - fixedTotal;
                        }

                        final double finalTw = fixedTotal + productWidth;
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
                                  _buildGridHeader(productWidth),
                                  Expanded(child: _buildGrid(productWidth)),
                                  _buildGridTotals(productWidth),
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
        ),
      ),
    );
  }

  Widget _buildTopToolbar() {
    bool canSave = !_isExistingEntry && !_isDeleted;
    bool canEdit = _isExistingEntry && !_isDeleted;

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey, width: 0.2))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("SALES RETURN ENTRY", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.black87)),
          const SizedBox(width: 30),
          _topActionBtn(Icons.add_box_rounded, "New (F2)", Colors.blue, onTap: _resetPage),
          _topActionBtn(Icons.check_circle_rounded, "Save (F6)", canSave ? Colors.green : Colors.grey.shade400, onTap: canSave ? () => _saveReturn(isEdit: false) : () {}),
          _topActionBtn(Icons.edit_document, "Edit", canEdit ? Colors.orange : Colors.grey.shade400, onTap: canEdit ? () => _saveReturn(isEdit: true) : () {}),
          _topActionBtn(Icons.print_rounded, "Print", Colors.blueGrey, onTap: _exportToPdf),
          _topActionBtn(Icons.picture_as_pdf_rounded, "PDF", const Color(0xFFE53935), onTap: _exportToPdf),
          _topActionBtn(_buildWhatsAppLogo(size: 24), "WhatsApp", const Color(0xFF25D366), onTap: _shareReturnWhatsApp),
          _topActionBtn(Icons.file_download_outlined, "Export", Colors.green.shade800, onTap: _exportToExcel),
          _topActionBtn(Icons.delete_forever_rounded, "Del", canEdit ? Colors.red : Colors.grey.shade400, onTap: canEdit ? _deleteSale : null),
        ],
      ),
    );
  }

  Widget _buildWhatsAppLogo({double size = 24}) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFF25D366),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.call,
        color: Colors.white,
        size: size * 0.58,
      ),
    );
  }

  Widget _topActionBtn(dynamic icon, String label, Color color, {VoidCallback? onTap}) => Padding(
    padding: const EdgeInsets.only(left: 12),
    child: InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon is IconData)
            Icon(icon, size: 24, color: color)
          else if (icon is Widget)
            icon,
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    ),
  );

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFFE9EEF4), border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: Column(
              children: [
                _headerRow("Entry No:", Row(
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
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                          maxLines: 1,
                        ),
                      ),
                    ),
                    _entryNavBtn(">", onTap: () => _navigateEntry('next')),
                  ],
                )),
                const SizedBox(height: 6),
                _headerRow("Date:", InkWell(
                  onTap: _isDeleted ? null : () async {
                    final picked = await showAppDatePicker(context: context, initialDate: _date, firstDate: DateTime(2000), lastDate: DateTime(2100));
                    if (picked != null) setState(() => _date = picked);
                  },
                  child: Container(
                    height: 22, padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400)),
                    child: Row(children: [Text(DateFormat('dd/MM/yyyy').format(_date), style: const TextStyle(fontSize: 11)), const Spacer(), const Icon(Icons.calendar_month, size: 14)]),
                  ),
                )),
                const SizedBox(height: 6),
                _headerRow("Ref Inv No:", Container(
                  height: 22, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400)),
                  child: TextField(
                    controller: _salesInvCtrl,
                    focusNode: _salesInvFocus,
                    onSubmitted: (val) => _loadOriginalInvoice(val.trim()),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8)),
                  ),
                )),
              ],
            ),
          ),
          const SizedBox(width: 20),
          SizedBox(
            width: 320,
            child: Column(
              children: [
                _headerRow("Customer Acc:", Container(
                  height: 22, padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(color: const Color(0xFFCCFFFF), border: Border.all(color: Colors.teal.shade300)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _customerAcc, isDense: true, icon: const Icon(Icons.arrow_drop_down, size: 16, color: Colors.teal),
                      style: const TextStyle(color: Colors.black, fontSize: 11),
                      items: ["Cash", "Credit", "Card", "UPI"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: _isDeleted ? null : (v) => setState(() => _customerAcc = v!),
                    ),
                  ),
                )),
                const SizedBox(height: 6),
                _headerRow("Patient:", CompositedTransformTarget(
                  link: _patientLayer,
                  child: Container(
                    height: 22, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400)),
                    child: TextField(
                      controller: _patientCtrl,
                      focusNode: _patientFocus,
                      onChanged: (v) => _onHeaderSearch(v, _patientSearchList, (p) => p.getRecentPatients()),
                      onSubmitted: (_) => _moveFocus(-1, 2),
                      style: const TextStyle(fontSize: 11),
                      decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8)),
                    ),
                  ),
                )),
                const SizedBox(height: 6),
                _headerRow("Doctor:", CompositedTransformTarget(
                  link: _doctorLayer,
                  child: Container(
                    height: 22, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400)),
                    child: TextField(
                      controller: _doctorCtrl,
                      focusNode: _doctorFocus,
                      onChanged: (v) => _onHeaderSearch(v, _doctorSearchList, (p) => p.getRecentDoctors()),
                      onSubmitted: (_) => _moveFocus(0, 1, autoOpen: true),
                      style: const TextStyle(fontSize: 11),
                      decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8)),
                    ),
                  ),
                )),
              ],
            ),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Tax Schedule:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Radio<int>(
                      value: 1, groupValue: _gstMode,
                      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (v) => setState(() {
                        _gstMode = v!;
                        for (int i = 0; i < _items.length; i++) {
                          _calculateItem(i);
                        }
                      }),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Text("GST Inclusive", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Radio<int>(
                      value: 2, groupValue: _gstMode,
                      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (v) => setState(() {
                        _gstMode = v!;
                        for (int i = 0; i < _items.length; i++) {
                          _calculateItem(i);
                        }
                      }),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Text("Non GST", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerRow(String label, Widget child) => Row(
    children: [
      SizedBox(width: 75, child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.black87))),
      Expanded(child: child),
    ],
  );

  Widget _entryNavBtn(String txt, {VoidCallback? onTap}) => InkWell(
    onTap: onTap,
    child: Container(
      width: 22, height: 26, alignment: Alignment.center,
      decoration: BoxDecoration(color: Colors.grey.shade200, border: Border.all(color: Colors.grey.shade400)),
      child: Text(txt, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    ),
  );

  Widget _buildGridHeader(double dynamicWidth) => Container(
    height: 28, color: const Color(0xFF616161),
    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: List.generate(17, (i) {
      double w = i == 1 ? dynamicWidth : _colWidths[i]!;
      return _ResizableHdr(i, _getColName(i), width: w, tooltip: _getColTooltip(i), onResize: (v) => setState(() => _colWidths[i] = v), align: _getColAlign(i));
    })),
  );

  String _getColName(int i) => ["Sl", "Product Name", "HSN", "Batch", "Expiry", "Pack", "Qty", "MRP", "Disc%", "DiscAmt", "TaxableSP", "1/MRP", "Gross", "Net", "GST", "Total", ""][i];

  String _getColTooltip(int i) => [
        "Serial Number",
        "Product Name",
        "HSN Code",
        "Batch Number",
        "Expiry Date (MM/YY)",
        "Packing Size",
        "Return Quantity",
        "Maximum Retail Price",
        "Discount Percentage",
        "Discount Amount",
        "Taxable Selling Price",
        "Unit Price per Tablet (1 / MRP)",
        "Gross Amount",
        "Net Amount",
        "GST Amount",
        "Total Amount",
        ""
      ][i];
  TextAlign _getColAlign(int i) => [TextAlign.center, TextAlign.left, TextAlign.left, TextAlign.left, TextAlign.center, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.center][i];

  Widget _buildGridTotals(double dynamicWidth) {
    return Container(
      height: 28,
      decoration: const BoxDecoration(
        color: Color(0xFF616161),
        border: Border(top: BorderSide(color: Colors.white24, width: 1)),
      ),
      child: Row(
        children: List.generate(17, (i) {
          double w = i == 1 ? dynamicWidth : _colWidths[i]!;
          if (i == 6) return _totalCell(_totalQtyNotifier, w, isInt: true);
          if (i == 9) return _totalCell(_totalDiscAmtNotifier, w);
          if (i == 12) return _totalCell(_totalGrossNotifier, w);
          if (i == 13) return _totalCell(_totalNetNotifier, w);
          if (i == 14) return _totalCell(_totalGstAmtNotifier, w);
          return Container(width: w, decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.white24, width: 0.5))));
        }),
      ),
    );
  }

  Widget _totalCell(ValueNotifier<num> notifier, double w, {bool isInt = false}) {
    return ValueListenableBuilder<num>(
      valueListenable: notifier,
      builder: (context, val, _) => Container(
        width: w,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.centerRight,
        decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.white24, width: 0.5))),
        child: Text(
          isInt ? val.toString() : (val as double).toStringAsFixed(2),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildGrid(double dynamicWidth) => Scrollbar(
    controller: _verticalGridScrollCtrl,
    child: ListView.builder(
      controller: _verticalGridScrollCtrl,
      itemExtent: 24.0,
      itemCount: _items.length + (_isDeleted ? 0 : 1),
      itemBuilder: (ctx, i) => RepaintBoundary(
        child: i < _items.length ? _buildRow(i, dynamicWidth) : _buildActiveRow(dynamicWidth),
      ),
    ),
  );

  Widget _buildRow(int row, double dynamicWidth) {
    final it = _items[row];
    return ValueListenableBuilder<IntPair?>(
      valueListenable: _focusNotifier,
      builder: (context, focus, _) {
        bool isRowActive = focus?.row == row;
        Color rowBg = isRowActive ? const Color(0xFFF0F7FF) : (row % 2 == 0 ? Colors.white : const Color(0xFFF9FAFB));

        return Container(
          height: 24,
          decoration: BoxDecoration(color: rowBg, border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 0.5))),
          child: Row(
            children: [
              _cell(row, 0, "${row + 1}", _colWidths[0]!, align: TextAlign.center),
              _cell(row, 1, it.product.name.toUpperCase(), dynamicWidth, isInput: true, onChanged: (v) { _saveUndoState(); it.product.name = v; _startProductSearch(v); }),
              _cell(row, 2, it.product.hsnCode.toUpperCase(), _colWidths[2]!, isInput: true, onChanged: (v) { _saveUndoState(); it.product.hsnCode = v; }),
              _cell(row, 3, cleanBatch(it.product.batch).toUpperCase(), _colWidths[3]!, isInput: true, onChanged: (v) { _saveUndoState(); it.product.batch = v; _startBatchSearch(row, v); }),
              _cell(row, 4, it.product.expiry, _colWidths[4]!, isInput: true, align: TextAlign.center, onChanged: (v) { _saveUndoState(); it.product.expiry = v; }),
              _cell(row, 5, it.packin.toString(), _colWidths[5]!, align: TextAlign.right),
              _cell(row, 6, it.qty.toString(), _colWidths[6]!, isInput: true, align: TextAlign.right, onChanged: (v) { _saveUndoState(); it.qty = int.tryParse(v) ?? 0; _calculateItem(row); }),
              _cell(row, 7, (it.product.mrp > 0 ? it.product.mrp : it.mrp * (it.packin > 0 ? it.packin : 1)).toStringAsFixed(2), _colWidths[7]!, align: TextAlign.right),
              _cell(row, 8, it.discPercent.toStringAsFixed(2), _colWidths[8]!, isInput: true, align: TextAlign.right, onChanged: (v) { _saveUndoState(); it.discPercent = double.tryParse(v) ?? 0.0; _calculateItem(row); }),
              _cell(row, 9, it.discAmt.toStringAsFixed(2), _colWidths[9]!, align: TextAlign.right),
              _cell(row, 10, it.taxableSP.toStringAsFixed(2), _colWidths[10]!, align: TextAlign.right),
              _cell(row, 11, it.mrp.toStringAsFixed(2), _colWidths[11]!, align: TextAlign.right),
              _cell(row, 12, (it.sRate * it.qty).toStringAsFixed(2), _colWidths[12]!, align: TextAlign.right),
              _cell(row, 13, ((it.sRate * it.qty) - it.discAmt).toStringAsFixed(2), _colWidths[13]!, align: TextAlign.right),
              _cell(row, 14, it.gstAmt.toStringAsFixed(2), _colWidths[14]!, align: TextAlign.right),
              _cell(row, 15, it.total.toStringAsFixed(2), _colWidths[15]!, align: TextAlign.right, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
              Container(
                width: _colWidths[16]!, alignment: Alignment.center,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.red, size: 14),
                  padding: EdgeInsets.zero,
                  onPressed: () { _saveUndoState(); setState(() { _items.removeAt(row); _calculateFooter(); }); },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveRow(double dynamicWidth) {
    int row = _items.length;
    return ValueListenableBuilder<IntPair?>(
      valueListenable: _focusNotifier,
      builder: (context, focus, _) {
        bool isRowActive = focus?.row == row;
        return Container(
          height: 24,
          decoration: BoxDecoration(color: isRowActive ? const Color(0xFFF0F7FF) : Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
          child: Row(
            children: [
              _cell(row, 0, "${row + 1}", _colWidths[0]!, align: TextAlign.center),
              _cell(row, 1, "", dynamicWidth, isInput: true, hint: "Search Product to return...", onChanged: _startProductSearch),
              _cell(row, 2, "", _colWidths[2]!),
              _cell(row, 3, "", _colWidths[3]!, isInput: true, onChanged: (v) => _startBatchSearch(row, v)),
              _cell(row, 4, "", _colWidths[4]!, align: TextAlign.center),
              _cell(row, 5, "", _colWidths[5]!),
              _cell(row, 6, "", _colWidths[6]!, isInput: true, align: TextAlign.right),
              _cell(row, 7, "", _colWidths[7]!),
              _cell(row, 8, "0", _colWidths[8]!, isInput: true, align: TextAlign.right),
              _cell(row, 9, "", _colWidths[9]!),
              _cell(row, 10, "", _colWidths[10]!),
              _cell(row, 11, "", _colWidths[11]!),
              _cell(row, 12, "", _colWidths[12]!),
              _cell(row, 13, "", _colWidths[13]!),
              _cell(row, 14, "", _colWidths[14]!),
              _cell(row, 15, "", _colWidths[15]!),
              SizedBox(width: _colWidths[16]!),
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
        bool isFocusable = _editableCols.contains(col);
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
                key: ValueKey("sr_tf_${rowId}_$col"),
                controller: ctrl, 
                focusNode: actualFocusNode, 
                textAlign: align,
                keyboardType: (col == 6 || col == 8) ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                inputFormatters: (col == 6 || col == 8) ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : (col == 4 ? [ExpiryFormatter()] : [UpperCaseTextFormatter()]),
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
                style: TextStyle(fontSize: 14, fontWeight: fontWeight ?? FontWeight.bold, color: color ?? Colors.black),
                decoration: InputDecoration(isDense: true, border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4), hintText: hint, hintStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.grey)),
                cursorColor: Colors.blue.shade900, cursorWidth: 2.0,
              )
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: align == TextAlign.center ? Alignment.center : (align == TextAlign.right ? Alignment.centerRight : Alignment.centerLeft),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: align == TextAlign.right ? CrossAxisAlignment.end : (align == TextAlign.center ? CrossAxisAlignment.center : CrossAxisAlignment.start),
                  children: [
                    Text(val.toUpperCase(), style: TextStyle(fontSize: 14, color: color ?? Colors.black, fontWeight: fontWeight ?? FontWeight.normal), overflow: TextOverflow.ellipsis),
                  ],
                )
              );

        Widget content = Container(
            key: ValueKey("sr_cell_${rowId}_$col"),
            decoration: BoxDecoration(color: bg, border: (isFocused && isFocusable) ? Border.all(color: Colors.blue.shade800, width: 2.2) : null),
            child: (col == 1 || col == 3)
                ? CompositedTransformTarget(
                    link: (col == 1 && (isFocused || _focusedRowIndex == row)) ? _searchLayer : ((col == 3 && (isFocused || _focusedRowIndex == row)) ? _batchLayer : LayerLink()),
                    child: cellContent,
                  )
                : cellContent,
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            if (isFocusable && !isFocused) {
              _moveFocus(row, col, autoOpen: col == 1 || col == 3);
            }
          },
          child: Container(width: w, height: 24, decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade300, width: 0.5), bottom: BorderSide(color: Colors.grey.shade200, width: 0.5))), child: content),
        );
      },
    );
  }

  Widget _buildOverlay() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _buildNameOverlay(_patientLayer, _patientSearchList, _patientCtrl, _mobileFocus),
        _buildNameOverlay(_doctorLayer, _doctorSearchList, _doctorCtrl, null),
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
              offset: const Offset(0, 26),
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
                          constraints: const BoxConstraints(maxHeight: 168.0),
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
                                      color: sel ? Colors.blue.shade100 : Colors.white,
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

  Widget _buildNameOverlay(LayerLink link, ValueNotifier<List<String>> listNotifier, TextEditingController ctrl, FocusNode? next) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: listNotifier,
      builder: (ctx, list, _) {
        if (list.isEmpty) return const SizedBox();
        return CompositedTransformFollower(
          link: link, showWhenUnlinked: false, offset: const Offset(0, 26),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => _isSelectingFromDropdown = true,
            child: Material(
              elevation: 8,
              child: Container(
                width: 300,
                  constraints: const BoxConstraints(maxHeight: 250),
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.blue.shade900, width: 2)),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (ctx, i) {
                      final item = list[i];
                      String title = "";
                      String subtitle = "";
                      bool isNew = i == list.length - 1 && item.startsWith("ADD NEW");

                      if (item == "ADD NEW NAME") {
                        title = item;
                        subtitle = "ADD NEW NAME";
                      } else {
                        title = item;
                        subtitle = "DOCTOR/PATIENT"; // Simplified for return screen
                      }

                      return InkWell(
                        onTap: () => _onNameSelected(ctrl, listNotifier, item, next),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                              color: isNew ? Colors.blue.shade50 : null,
                              border: Border(bottom: BorderSide(color: Colors.grey.shade100))
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isNew ? Colors.blue.shade900 : Colors.black87)),
                                    if (subtitle.isNotEmpty)
                                      Text(subtitle, style: TextStyle(fontSize: 10, color: isNew ? Colors.red.shade900 : Colors.grey.shade600, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                              if (isNew)
                                const Icon(Icons.add_circle_outline, size: 16, color: Colors.blue),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFFE9EEF4), border: Border(top: BorderSide(color: Colors.grey.shade400))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Return Narration", style: TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  width: 300,
                  height: 50,
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400)),
                  child: TextField(
                    controller: _narrationCtrl,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 11),
                    decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.all(6), isDense: true),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 300,
            child: Column(
              children: [
                _footerCalcRow("Sub Total", _subTotalCtrl, readOnly: true),
                const SizedBox(height: 4),
                _footerCalcRow("Discount", _footerDiscAmtCtrl, pctCtrl: _footerDiscPctCtrl),
                const SizedBox(height: 4),
                _footerCalcRow("Round Off", _roundOffCtrl, readOnly: true),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text("Refund Grand Total:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    ValueListenableBuilder<double>(
                      valueListenable: _grandTotalNotifier,
                      builder: (context, val, _) => Text("₹ ${val.toStringAsFixed(2)}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.red)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _footerCalcRow(String label, TextEditingController amtCtrl, {TextEditingController? pctCtrl, bool readOnly = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 11), textAlign: TextAlign.right)),
        const SizedBox(width: 8),
        if (pctCtrl != null) ...[
          Container(
            width: 35, height: 22,
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400)),
            child: TextField(controller: pctCtrl, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10), decoration: const InputDecoration(border: InputBorder.none, isDense: true)),
          ),
          const SizedBox(width: 4),
        ],
        Container(
          width: 75, height: 22,
          decoration: BoxDecoration(color: readOnly ? Colors.grey.shade100 : Colors.white, border: Border.all(color: Colors.grey.shade400)),
          child: TextField(controller: amtCtrl, readOnly: readOnly, textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4))),
        ),
      ],
    );
  }

  Widget _buildShortcutLegend() => Container(
    height: 28, padding: const EdgeInsets.symmetric(horizontal: 12),
    color: Colors.grey.shade900,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: const [
        _ShortcutTag("F2", "New"),
        _ShortcutTag("F6/F10", "Save"),
        _ShortcutTag("Enter", "Forward"),
        _ShortcutTag("S+Enter", "Back"),
        _ShortcutTag("C+Z", "Undo"),
        _ShortcutTag("C+Del", "Delete Row"),
      ],
    ),
  );
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
