import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import '../services/pdf_worker_service.dart';
import '../services/print_spooler_service.dart';
import '../services/whatsapp_service.dart';

// Providers & Controllers
import '../providers/pharmacy_provider.dart';
import '../providers/app_provider.dart';

// Models & Utils
import '../utils/tax_calculator.dart';
import '../utils/theme_constants.dart';
import '../utils/app_dialogs.dart';
import '../utils/app_formatters.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/erp_tooltip.dart';
import '../utils/app_sounds.dart';
import '../utils/printer_service.dart';
import '../utils/invoice_pdf_generator.dart';
import '../utils/search_debouncer.dart';

// Widgets & Sub-components
import '../widgets/pin_unlock_dialog.dart';
import '../widgets/schedule_h1_compliance_dialog.dart';
import '../widgets/window_controls_bar.dart';
import 'reports/order_book_screen.dart';
import 'reports/sales_history_screen.dart';
import 'reports/purchase_history_screen.dart';
import '../windows/window_spawner.dart';







class SalesScreen extends StatefulWidget {
  final String? initialInvoiceNo;
  final bool isDialog;
  const SalesScreen({super.key, this.initialInvoiceNo, this.isDialog = false});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  // Variables for Headless Barcode Scanning
  String _barcodeBuffer = "";
  DateTime _lastKeyPress = DateTime.now();

  // Focus nodes to jump around with Hotkeys
  final FocusNode _itemSearchFocusNode = FocusNode();

  final List<SaleItem> _items = [];
  String _entryNo = "";
  Timer? _draftTimer;
  String _customerAcc = "Cash";
  String _selectedAgent = "";
  int _lastSyncedSessionIdx = -1;
  String _lastYear = "";
  String _activeNotificationTab = "none";
  String _orderFilter = "PENDING";
  int _alertPage = 1;
  final List<String> _agents = ["Suresh", "Ramesh", "Admin", "Staff 1", "Staff 2"];

  final TextEditingController _customerAccCtrl = TextEditingController(text: "Cash");
  final TextEditingController _agentCtrl = TextEditingController();
  final FocusNode _agentFocus = FocusNode();
  final FocusNode _customerAccFocus = FocusNode();
  int _gstType = 2;
  int _orderType = 0; // 0 = Normal, 1 = Special Order, 2 = One Time Order
  bool _showSpecialOrderSidebar = false;
  bool _isSpecialOrderMinimized = false;
  DateTime _date = DateTime.now();
  bool _isExistingEntry = false; // Tracks if we are viewing a saved record or a new one
  bool _isDirty = false; // NEW: Tracks if any changes were made to an existing entry
  bool _isDeleted = false; // NEW: Tracks if the loaded entry is marked as deleted
  bool _isResetting = false; // Prevents recursive re-entrant reset loops
  bool _hasNewMobileOrder = false;
  bool _showProfitColumn = false; 
  SaleInvoice? _originalLoadedInvoice; 
  final Map<SaleItem, Map<String, dynamic>> _originalItemSnapshots = {};
  bool _highlightEdits = false;

  // ---> 3D Red Box Theme (Matching Photo 2 Date Box Style) <---
  static const Color _editHighlightBg = Color(0xFFFFF0F0); // Soft pastel red fill
  static const Color _editHighlightBorder = Color(0xFFE57373); // Crisp 3D border outline

  // Agent Watermark Variables
  bool _showAgentWatermark = false;
  String _watermarkAgent = "";
  Timer? _watermarkTimer;

  final List<List<SaleItem>> _undoStack = [];
  final Map<int, Set<int>> _errorCells = {}; // Maps Row Index -> Set of Column Indexes with errors
  final Set<int> _discountInteractedRows = {};

  bool _isDialogOpen = false;
  final TextEditingController _patientCtrl = TextEditingController(text: "P1");
  final TextEditingController _mobileCtrl = TextEditingController();
  final TextEditingController _doctorCtrl = TextEditingController(text: "D1");
  final TextEditingController _doctorRegNoCtrl = TextEditingController();
  final TextEditingController _daysCtrl = TextEditingController(text: "0");
  final TextEditingController _specialMainCtrl = TextEditingController();
  final TextEditingController _specialCustomerNameCtrl = TextEditingController();
  final TextEditingController _specialCustomerPhoneCtrl = TextEditingController();
  final TextEditingController _expectingDateCtrl = TextEditingController();
  final Map<String, int> _specialOrderQtys = {};
  List<Map<String, dynamic>> _urgentOrders = [];
  List<Map<String, dynamic>> _lowStockOrders = [];
  List<Map<String, dynamic>> _specialOrdersList = [];
  bool _isLoadingNotifications = false;
  final List<String> _extraSpecialItems = [];
  bool _isSpecialSyncEnabled = true;
  bool _isProductSyncEnabled = false;
  final Map<String, TextEditingController> _specialOrderCtrls = {};
  final Map<String, FocusNode> _specialOrderFocusNodes = {};

  final TextEditingController _subTotalCtrl = TextEditingController(text: "0.00");
  final TextEditingController _footerDiscPctCtrl = TextEditingController(text: "0");
  final TextEditingController _footerDiscAmtCtrl = TextEditingController(text: "0.00");
  final TextEditingController _roundOffCtrl = TextEditingController(text: "0.00");
  final TextEditingController _rcvdAmtCtrl = TextEditingController(text: "0");
  final TextEditingController _salesReturnCtrl = TextEditingController(text: "0.00");
  final TextEditingController _balanceCtrl = TextEditingController(text: "0.00");
  final TextEditingController _netTotalCtrl = TextEditingController(text: "0.00");

  final ScrollController _gridScrollCtrl = ScrollController();
  final ScrollController _verticalGridScrollCtrl = ScrollController();
  final ScrollController _dropdownScrollCtrl = ScrollController();
  final ScrollController _topScrollCtrl = ScrollController();

  final Map<int, double> _colWidths = {
    0: 35, 1: 75, 2: 280, 3: 90, 4: 140, 5: 60, 6: 60, 7: 60, 8: 60,
    9: 80, 10: 80, 11: 60, 12: 80, 13: 50, 14: 100, 15: 80, 16: 48,
  };

  // --- PART 5: OBJECT-MAPPED CONTROLLERS (FIXES MEMORY LEAKS) ---
  final Map<SaleItem, Map<int, TextEditingController>> _gridCtrls = {};
  final Map<SaleItem, Map<int, FocusNode>> _gridFocusNodes = {};
  final Map<int, TextEditingController> _nextRowCtrls = {};
  final Map<int, FocusNode> _nextRowNodes = {};
  final ValueNotifier<IntPair?> _focusNotifier = ValueNotifier(const IntPair(0, 2));
  final List<int> _navCols = [2, 4, 5, 7, 11];
  List<int> get _editableCols => _navCols;

  String _lastSyncedProdName = "";
  List<Product> _footerAlts = [];
  String _activeGenericName = "";
  List<Map<String, dynamic>> _productHistory = [];

  final FocusNode _rootFocus = FocusNode();
  final FocusNode _patientFocus = FocusNode();
  final FocusNode _mobileFocus = FocusNode();
  final FocusNode _doctorFocus = FocusNode();
  final FocusNode _doctorRegNoFocus = FocusNode();
  final FocusNode _daysFocus = FocusNode();
  final FocusNode _specialSearchFocus = FocusNode();
  final FocusNode _specialCustomerNameFocus = FocusNode();
  final FocusNode _specialCustomerPhoneFocus = FocusNode();
  final FocusNode _expectingDateFocus = FocusNode();
  final FocusNode _saveSpecialOrderFocus = FocusNode();
  final FocusNode _rcvdAmtFocus = FocusNode();
  final FocusNode _footerDiscAmtFocus = FocusNode();
  final FocusNode _otherChargeAmtFocus = FocusNode();
  final TextEditingController _otherChargePctCtrl = TextEditingController(text: "0");
  final TextEditingController _otherChargeAmtCtrl = TextEditingController(text: "0.00");

  final Map<String, int> _originalInvoiceBatchQtys = {}; // batch -> qty

  final ValueNotifier<double> _subTotalNotifier = ValueNotifier(0.0);
  final ValueNotifier<double> _netTotalNotifier = ValueNotifier(0.0);
  ValueNotifier<double> get _grandTotalNotifier => _netTotalNotifier;
  final ValueNotifier<double> _roundOffNotifier = ValueNotifier(0.0);
  final ValueNotifier<double> _balanceNotifier = ValueNotifier(0.0);
  final ValueNotifier<int> _summaryNotifier = ValueNotifier(0);

  String _fmt(double val) => val.toStringAsFixed(2);

  int get _focusedRowIndex => _focusNotifier.value?.row ?? -1;
  int get _focusedColIndex => _focusNotifier.value?.col ?? 0;

  final LayerLink _searchLayer = LayerLink();
  final LayerLink _batchLayer = LayerLink();
  final LayerLink _specialSearchLayer = LayerLink();
  final LayerLink _patientLayer = LayerLink();
  final LayerLink _doctorLayer = LayerLink();
  final LayerLink _specialCustomerLayer = LayerLink();

  final ValueNotifier<List<Product>> _searchList = ValueNotifier([]);
  final ValueNotifier<List<Product>> _batchList = ValueNotifier([]);
  final ValueNotifier<List<Product>> _specialSearchList = ValueNotifier([]);
  final ValueNotifier<List<dynamic>> _patientSearchList = ValueNotifier([]);
  final ValueNotifier<List<dynamic>> _doctorSearchList = ValueNotifier([]);
  String? _focusedPatientText;
  String? _focusedDoctorText;
  final ValueNotifier<int> _searchIdx = ValueNotifier(0);

  Timer? _scrollTimer;
  Timer? _timeTimer;
  final SearchDebouncer _productSearchDebouncer = SearchDebouncer(milliseconds: 100);
  final SearchDebouncer _historyDebouncer = SearchDebouncer(milliseconds: 200);
  final SearchDebouncer _footerDebouncer = SearchDebouncer(milliseconds: 50);
  final SearchDebouncer _barcodeDebouncer = SearchDebouncer(milliseconds: 80);
  String _timeString = "";

  bool _isLoading = false;
  bool _isSaving = false; // ---> Hard guard against rapid double-clicks & hotkey spam
  bool _isSelectingBatch = false;
  bool _isSelectingFromDropdown = false;

  DateTime _parseExpiry(String exp) {
    String clean = exp.replaceAll('-', '/');
    if (!clean.contains('/')) return DateTime(2099);
    final parts = clean.split('/');
    if (parts.length != 2) return DateTime(2099);
    int m = int.tryParse(parts[0]) ?? 1;
    int y = int.tryParse(parts[1]) ?? 99;
    if (y < 100) y += 2000;
    return DateTime(y, m + 1, 0);
  }

  String _cleanBatch(String batch) {
    return cleanBatch(batch);
  }

  Color _getBatchBgColor(String expiryStr) {
    DateTime expDate = _parseExpiry(expiryStr);
    int days = expDate.difference(DateTime.now()).inDays;
    if (days <= 30) return Colors.black87;
    if (days <= 90) return Colors.red.shade900.withValues(alpha: 0.9);
    if (days <= 180) return Colors.orange.withValues(alpha: 0.9);
    if (days <= 365) return Colors.yellow.shade700.withValues(alpha: 0.9);
    if (days <= 730) return Colors.lightGreen.withValues(alpha: 0.9);
    return Colors.green.shade800.withValues(alpha: 0.9);
  }

  Color _getBatchTextColor(String expiryStr) {
    DateTime expDate = _parseExpiry(expiryStr);
    int days = expDate.difference(DateTime.now()).inDays;
    return (days <= 90 || days > 730) ? Colors.white : Colors.black;
  }


  // ---> NEW: Instantly unlocks the Edit button when a change happens <---
  void _markDirty() {
    if (_isLoading) return; // Don't trigger while the invoice is still loading!
    if (_isExistingEntry && !_isDirty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _isDirty = true);
      });
    }
  }

  void _saveUndoState() {
    if (!mounted) return;
    _markDirty(); // <--- THE FIX: Any grid changes instantly trigger the Edit button!
    _undoStack.add(_items.map((it) => it.clone()).toList());
    if (_undoStack.length > 3) _undoStack.removeAt(0);
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


  @override
  void initState() {
    super.initState();

    final p = Provider.of<PharmacyProvider>(context, listen: false);
    _lastYear = p.selectedFinancialYear;
    _isExistingEntry = widget.initialInvoiceNo != null;

    // ASYNC INITIALIZATION
    Future.microtask(() async {
      final next = await p.getNextSaleEntryNo();
      if (mounted) setState(() => _entryNo = next);
      _loadNotificationData();
    });

    // ---> START AUTO-SAVE TIMER (Every 5 seconds) <---
    _draftTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) _triggerAutoSaveDraft();
    });

    _timeString = DateFormat('hh:mm a').format(DateTime.now());
    _timeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _timeString = DateFormat('hh:mm a').format(DateTime.now());
        });
      }
    });

    p.addListener(_onProviderChanged);
    _lastSyncedSessionIdx = p.activeSessionIdx;

    // --- THE FIX: ADD FOCUS LISTENER ---
    _focusNotifier.addListener(() {
      if (!mounted) return;
    });
    _itemSearchFocusNode.addListener(() {
      if (_itemSearchFocusNode.hasFocus) {
        if (_focusNotifier.value?.row != _items.length || _focusNotifier.value?.col != 2) {
          _focusNotifier.value = IntPair(_items.length, 2);
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialInvoiceNo != null) {
        _loadSaleData(widget.initialInvoiceNo!);
      } else {
        _moveFocus(0, 1);
      }
    });
  }

  @override
  void dispose() {
    _draftTimer?.cancel(); // Clean up timer
    _scrollTimer?.cancel();
    _timeTimer?.cancel();
    _productSearchDebouncer.dispose();
    _historyDebouncer.dispose();
    _footerDebouncer.dispose();
    _barcodeDebouncer.dispose();
    _gridScrollCtrl.dispose();
    _verticalGridScrollCtrl.dispose();
    _dropdownScrollCtrl.dispose();
    _topScrollCtrl.dispose();
    _rootFocus.dispose();
    _patientFocus.dispose();
    _itemSearchFocusNode.dispose();
    _mobileFocus.dispose();
    _doctorFocus.dispose();
    _doctorRegNoFocus.dispose();
    _daysFocus.dispose();
    _specialSearchFocus.dispose();
    _agentFocus.dispose();
    _specialCustomerNameFocus.dispose();
    _specialCustomerPhoneFocus.dispose();
    _expectingDateFocus.dispose();
    _saveSpecialOrderFocus.dispose();
    _rcvdAmtFocus.dispose();
    _focusNotifier.dispose();
    _searchList.dispose();
    _batchList.dispose();
    _searchIdx.dispose();
    _specialOrderCtrls.forEach((k, v) => v.dispose());
    _gridCtrls.forEach((k, v) => v.forEach((k2, v2) => v2.dispose()));
    _gridFocusNodes.forEach((k, v) => v.forEach((k2, v2) => v2.dispose()));
    for (final c in _nextRowCtrls.values) {
      c.dispose();
    }
    for (final f in _nextRowNodes.values) {
      f.dispose();
    }

    // Remove listener from provider
    try {
      Provider.of<PharmacyProvider>(context, listen: false).removeListener(_onProviderChanged);
    } catch (_) {}

    super.dispose();
  }

  TextEditingController _getHeaderCtrl(int col) {
    if (col == 0) return _patientCtrl;
    if (col == 1) return _mobileCtrl;
    if (col == 2) return _doctorCtrl;
    return _daysCtrl;
  }

  FocusNode _getHeaderFocus(int col) {
    if (col == 0) return _patientFocus;
    if (col == 1) return _mobileFocus;
    if (col == 2) return _doctorFocus;
    return _daysFocus;
  }

  TextEditingController _getGridCtrl(int row, int col, [String init = ""]) {
    // Handle the empty "Search Product" row
    if (row == _items.length) {
      if (!_nextRowCtrls.containsKey(col)) {
        _nextRowCtrls[col] = TextEditingController(text: init);
      } else if (init.isNotEmpty && _nextRowCtrls[col]!.text.isEmpty) {
        _nextRowCtrls[col]!.text = init;
      }
      return _nextRowCtrls[col]!;
    }

    if (row < 0 || row > _items.length) return TextEditingController();

    // Bind strictly to the memory address of the SaleItem
    final it = _items[row];
    _gridCtrls.putIfAbsent(it, () => {});
    if (!_gridCtrls[it]!.containsKey(col)) {
      _gridCtrls[it]![col] = TextEditingController(text: init);
    } else if (init.isNotEmpty && _gridCtrls[it]![col]!.text.isEmpty) {
      if (!_getGridFocusNode(row, col).hasFocus) {
        _gridCtrls[it]![col]!.text = init;
      }
    }
    return _gridCtrls[it]![col]!;
  }

  FocusNode _getGridFocusNode(int row, int col) {
    if (row == _items.length && (col == 1 || col == 2)) return _itemSearchFocusNode;

    // Handle the empty "Search Product" row
    if (row == _items.length) {
      if (!_nextRowNodes.containsKey(col)) {
        final fn = FocusNode();
        fn.addListener(() {
          // ---> THE GHOST FIX: Find true row if node was transferred <---
          int liveRow = _items.length;
          for (int i = 0; i < _items.length; i++) {
            if (_gridFocusNodes[_items[i]]?.containsValue(fn) == true) {
              liveRow = i;
              break;
            }
          }

          if (fn.hasFocus) {
            final ctrl = _getGridCtrl(liveRow, col);
            if (_focusNotifier.value?.row != liveRow || _focusNotifier.value?.col != col) {
              _focusNotifier.value = IntPair(liveRow, col);
            }
            Timer.run(() {
              if (fn.hasFocus && ctrl.text.isNotEmpty) {
                ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
              }
            });
          } else {
            // Safely grab text based on whether it's a committed row or the empty row
            String val = "";
            if (liveRow < _items.length) {
              val = _gridCtrls[_items[liveRow]]?[col]?.text ?? "";
            } else {
              val = _nextRowCtrls[col]?.text ?? "";
            }
            _onBlur(liveRow, col, val);
          }
        });
        _nextRowNodes[col] = fn;
      }
      return _nextRowNodes[col]!;
    }

    if (row < 0 || row > _items.length) return FocusNode();

    // Bind strictly to the memory address of the SaleItem
    final it = _items[row];
    _gridFocusNodes.putIfAbsent(it, () => {});
    if (!_gridFocusNodes[it]!.containsKey(col)) {
      final fn = FocusNode();
      fn.addListener(() {
        int liveRow = _items.indexOf(it);
        if (liveRow == -1) return; // Item was securely deleted, abort listener

        if (fn.hasFocus) {
          final ctrl = _getGridCtrl(liveRow, col);
          if (_focusNotifier.value?.row != liveRow || _focusNotifier.value?.col != col) {
            _focusNotifier.value = IntPair(liveRow, col);
          }

          // ---> THE FIX: Update footer when row gains focus <---
          if (liveRow < _items.length) {
            _updateFooter(_items[liveRow].product);
          } else {
            _updateFooter(Product(id: "", name: ""));
          }

          Timer.run(() {
            if (fn.hasFocus && ctrl.text.isNotEmpty) {
              ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
            }
          });
        } else {
          _onBlur(liveRow, col, _getGridCtrl(liveRow, col).text);
        }
      });
      _gridFocusNodes[it]![col] = fn;
    }
    return _gridFocusNodes[it]![col]!;
  }

  void _saveAndPrintBill() {
    _promptSave();
  }

  void _processBarcode(String barcode) async {
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final cleanCode = barcode.trim().toUpperCase();
    Product? found;

    // 1. PRIORITY: Check if barcode identifies a specific active batch
    try {
      found = p.products.firstWhere(
        (it) => it.batch.trim().toUpperCase() == cleanCode && it.stock > 0,
      );
    } catch (_) {}

    // 2. Fallback: Check if barcode matches a Product Master ID
    if (found == null) {
      final master = p.productMaster.cast<Product?>().firstWhere(
        (pm) => pm != null && (pm.id.trim().toUpperCase() == cleanCode || pm.batch.trim().toUpperCase() == cleanCode),
        orElse: () => null,
      );

      if (master != null) {
        // Only trigger FEFO search when scanning the product generally (not a specific batch)
        final fefoBatch = p.getAutoFefoBatch(master.name);
        found = fefoBatch ?? master;
      }
    }

    if (found != null) {
      // Check if this exact product and batch is already in the grid
      int existingRowIndex = _items.indexWhere((it) => 
          it.product.id == found!.id && it.product.batch == found.batch);

      if (existingRowIndex != -1) {
        setState(() {
          _items[existingRowIndex].qty += 1;
          _getGridCtrl(existingRowIndex, 7).text = _items[existingRowIndex].qty.toString();
          _calculateItem(existingRowIndex);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("UPDATED: ${found.name} (Qty: ${_items[existingRowIndex].qty})"),
            backgroundColor: Colors.blue.shade800,
            duration: const Duration(milliseconds: 700),
          ),
        );
      } else {
        int row = _focusedRowIndex;
        if (row < 0 || (row < _items.length && _items[row].product.name.isNotEmpty && _focusedColIndex != 3)) {
          row = _items.length;
        }

        _handleBatchSelection(row: row, product: found);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("SCANNED: ${found.name}"),
            backgroundColor: Colors.green,
            duration: const Duration(milliseconds: 700),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Barcode Not Found: $barcode"), backgroundColor: Colors.red),
      );
    }
  }

  void _onBlur(int row, int col, String value) {
    if (_isSelectingFromDropdown) return; // PREVENTS DROPDOWN FREEZE ON MOUSE CLICK

    if (row < _items.length) {
      final it = _items[row];
      if (col == 11) {
        _discountInteractedRows.add(row);
      }

      // Auto-fill Product on blur
      if (col == 2) {
        if (value.trim().isNotEmpty && it.product.id.isEmpty) {
          final p = Provider.of<PharmacyProvider>(context, listen: false);
          final matches = p.searchProducts(value.trim(), includeGenerics: false);
          if (matches.length == 1 && Product.cleanProductName(matches.first.name).toLowerCase() == Product.cleanProductName(value).toLowerCase()) {
            final best = matches.first;
            int pack = best.packSize > 0 ? best.packSize : 1;
            it.product = Product(
              id: best.id, name: best.name, hsnCode: best.hsnCode, packSize: pack,
              mrp: best.mrp, salePrice: best.salePrice > 0 ? best.salePrice : best.mrp,
              purchaseRate: best.purchaseRate, gstPercent: best.gstPercent,
              genericName: best.genericName, rack: best.rack, batch: best.batch, expiry: best.expiry,
            );
            it.packin = pack;
            it.mrp = best.mrp / pack.toDouble();
            it.sRate = (best.salePrice > 0 ? best.salePrice : best.mrp) / pack.toDouble();
            _getGridCtrl(row, 2).text = best.name;
            _getGridCtrl(row, 3).text = best.rack;
            _getGridCtrl(row, 4).text = _cleanBatch(best.batch);
            _getGridCtrl(row, 5).text = best.expiry;
            _updateFooter(it.product);
          } else {
            it.product.name = value;
            _updateFooter(it.product);
          }
        } else {
          it.product.name = value;
          _updateFooter(it.product);
        }
      }

      // Auto-fill Batch on blur
      if (col == 4) {
        if (value.trim().isEmpty && it.product.name.isNotEmpty) {
          final p = Provider.of<PharmacyProvider>(context, listen: false);
          final now = DateTime.now();

          // Only auto-fill unexpired batches with stock
          final availableBatches = p.products.where((prod) =>
              prod.name.toLowerCase().trim() == it.product.name.toLowerCase().trim() &&
              prod.stock > 0 &&
              !_parseExpiry(prod.expiry).isBefore(now)
          ).toList();

          if (availableBatches.isNotEmpty) {
            availableBatches.sort((a, b) => _parseExpiry(a.expiry).compareTo(_parseExpiry(b.expiry)));
            final bestBatch = availableBatches.first;

            int pack = bestBatch.packSize > 0 ? bestBatch.packSize : 1;
            it.product.batch = bestBatch.batch;
            it.product.expiry = bestBatch.expiry;
            it.product.stock = bestBatch.stock;
            it.product.landingCost = bestBatch.landingCost;
            it.product.purchaseRate = bestBatch.purchaseRate;
            it.product.mrp = bestBatch.mrp;
            it.product.salePrice = bestBatch.salePrice > 0 ? bestBatch.salePrice : bestBatch.mrp;
            it.product.rack = bestBatch.rack;
            it.packin = pack;
            it.mrp = bestBatch.mrp / pack.toDouble();
            it.sRate = (bestBatch.salePrice > 0 ? bestBatch.salePrice : bestBatch.mrp) / pack.toDouble();
            it.gstPercent = bestBatch.gstPercent;

            _getGridCtrl(row, 3).text = bestBatch.rack;
            _getGridCtrl(row, 4).text = _cleanBatch(bestBatch.batch);
            _getGridCtrl(row, 5).text = bestBatch.expiry;
            _calculateItem(row);
          }
        }
      }

      if (col == 5) it.product.expiry = value;

      // Qty, Disc%, DiscAmt Sync
      if (col == 7 || col == 11 || col == 12) {
        String val = value.trim().isEmpty ? "0" : value;
        if (col == 7) {
          it.qty = int.tryParse(val) ?? 0;
          if (!_getGridFocusNode(row, 7).hasFocus) {
            _getGridCtrl(row, 7).text = it.qty.toString();
          }
        } else if (col == 11) {
          it.discPercent = double.tryParse(val) ?? 0.0;
          if (!_getGridFocusNode(row, 11).hasFocus) {
            _getGridCtrl(row, 11).text = it.discPercent.toStringAsFixed(2);
          }
        } else if (col == 12) {
          double amt = double.tryParse(val) ?? 0.0;
          it.discAmt = amt;
          double gross = it.sRate * it.qty;
          it.discPercent = gross > 0 ? ((amt / gross) * 100.0) : 0.0;
          if (!_getGridFocusNode(row, 10).hasFocus) {
            _getGridCtrl(row, 10).text = it.discPercent.toStringAsFixed(2);
          }
        }
        _calculateItem(row);
      }
    }
  }

  // ---> NEW: Master function to instantly kill all dropdowns <---
  void _closeAllDropdowns() {
    _searchList.value = [];
    _batchList.value = [];
    _specialSearchList.value = [];
    _patientSearchList.value = [];
    _doctorSearchList.value = [];
  }

  void _moveFocus(int row, int col, {bool autoOpen = false}) {
    int safeRow = row.clamp(-1, _items.length);

    int safeCol = col;
    if (safeRow >= 0 && !_navCols.contains(col) && col != 15) {
      if (col < 2) {
        safeCol = 2;
      } else if (col > 11) {
        safeCol = 11;
      } else {
        safeCol = _navCols.reduce((a, b) => (a - col).abs() < (b - col).abs() ? a : b);
      }
    }

    // Capture undo snapshot once upon entering an editable cell
    if (_editableCols.contains(safeCol) && (_focusNotifier.value?.row != safeRow || _focusNotifier.value?.col != safeCol)) {
      _saveUndoState();
    }

    // Only close dropdowns if switching away from search columns
    if (safeCol != 2 && safeCol != 4) {
      _closeAllDropdowns();
    }
    
    _searchIdx.value = 0;
    _isSelectingBatch = (safeCol == 4);
    _focusNotifier.value = IntPair(safeRow, safeCol);

    // ---> SYNC FOOTER IMMEDIATELY ON ROW FOCUS MOVE <---
    if (safeRow >= 0 && safeRow < _items.length) {
      _updateFooter(_items[safeRow].product);
    } else {
      _updateFooter(Product(id: "", name: ""));
    }

    if (safeRow != -1) {
      _getGridFocusNode(safeRow, safeCol).requestFocus();
    }

    if (safeRow >= 0 && _showSpecialOrderSidebar && !_isSpecialOrderMinimized) {
      setState(() => _isSpecialOrderMinimized = true);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (safeRow == -1) {
        final fn = _getHeaderFocus(safeCol < 4 ? safeCol : 3);
        final ctrl = _getHeaderCtrl(safeCol < 4 ? safeCol : 3);

        bool wasFocused = fn.hasFocus;
        if (!wasFocused) {
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

        // Open the dropdown table upon focus if autoOpen is true
        if (autoOpen || safeCol == 4) {
          if (safeCol == 2 && initialText.trim().isEmpty) {
            _startProductSearch("");
          } else if (safeCol == 4) {
            _startBatchSearch(safeRow, "");
          }
        }
      }
    });
  }

  Product _cloneProduct(Product p) {
    return Product(
      id: p.id,
      name: p.name,
      batch: p.batch,
      expiry: p.expiry,
      packSize: p.packSize > 0 ? p.packSize : 1,
      mrp: p.mrp,
      salePrice: p.salePrice > 0 ? p.salePrice : p.mrp,
      purchaseRate: p.purchaseRate,
      landingCost: p.landingCost,
      gstPercent: p.gstPercent,
      rack: p.rack,
      category: p.category,
      manufacturer: p.manufacturer,
      genericName: p.genericName,
      stock: p.stock,
      schedule: p.schedule,
      hsnCode: p.hsnCode,
      patent: p.patent,
      use: p.use,
    );
  }

  void _updateFooter(Product p) {
    if (!mounted) return;
    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    // 1. Resolve Generic Name
    String genName = p.genericName.trim();
    if (genName.isEmpty && p.name.trim().isNotEmpty) {
      final pNameLower = p.name.trim().toLowerCase();
      for (var m in provider.productMaster) {
        if ((m.id == p.id || m.name.trim().toLowerCase() == pNameLower) && m.genericName.trim().isNotEmpty) {
          genName = m.genericName.trim();
          break;
        }
      }
      // If still empty, check if product name matches any registered generic in provider.generics
      if (genName.isEmpty) {
        final pNameUpper = p.name.toUpperCase();
        for (var g in provider.generics) {
          if (g.isNotEmpty && g.length >= 3 && pNameUpper.contains(g.toUpperCase())) {
            genName = g;
            break;
          }
        }
      }
      if (genName.isNotEmpty) {
        p.genericName = genName;
      }
    }

    _activeGenericName = genName;

    // 2. Sync Previous Sales History (already debounced)
    if (p.name.trim().isNotEmpty && p.name != _lastSyncedProdName) {
      _lastSyncedProdName = p.name;
      _updateHistory(p.name);
    } else if (p.name.trim().isEmpty) {
      _lastSyncedProdName = "";
      setState(() => _productHistory = []);
    }

    // 3. Fast Generic Substitutes Lookup (Early exit if blank)
    if (p.name.trim().isEmpty || genName.isEmpty) {
      if (_footerAlts.isNotEmpty) {
        setState(() => _footerAlts = []);
      }
      return;
    }

    final String searchGen = genName.toLowerCase();
    final String currentCleanName = Product.cleanProductName(p.name).toLowerCase();

    final Set<String> existingNamesInBill = _items
        .map((it) => Product.cleanProductName(it.product.name).toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();

    final Map<String, Product> subMap = {};

    // Check active inventory batches first (what is actually on the shelf right now)
    for (int i = 0; i < provider.products.length; i++) {
      final bp = provider.products[i];
      if (bp.stock <= 0) continue;

      final bpCleanName = Product.cleanProductName(bp.name).toLowerCase();
      if (bpCleanName == currentCleanName || existingNamesInBill.contains(bpCleanName)) continue;

      String bpGen = bp.genericName.trim().toLowerCase();
      if (bpGen.isEmpty) {
        final mMatch = provider.productMaster.firstWhere(
          (m) => m.id == bp.id || m.name.trim().toLowerCase() == bpCleanName,
          orElse: () => Product(id: "", name: bp.name),
        );
        bpGen = mMatch.genericName.trim().toLowerCase();
      }

      if (bpGen.isNotEmpty && (bpGen == searchGen || bpGen.contains(searchGen) || searchGen.contains(bpGen))) {
        if (!subMap.containsKey(bpCleanName)) {
          subMap[bpCleanName] = Product(
            id: bp.id,
            name: bp.name,
            genericName: bp.genericName.isNotEmpty ? bp.genericName : (bpGen.isNotEmpty ? bpGen.toUpperCase() : genName),
            stock: bp.stock,
            mrp: bp.mrp,
            salePrice: bp.salePrice,
            packSize: bp.packSize,
            category: bp.category,
            rack: bp.rack,
            manufacturer: bp.manufacturer,
          );
        } else {
          subMap[bpCleanName]!.stock += bp.stock;
        }
      }

      if (subMap.length >= 20) break; // Cap at top 20 shelf alternatives
    }

    final substitutes = subMap.values.toList()
      ..sort((a, b) => b.stock.compareTo(a.stock));

    setState(() {
      _footerAlts = substitutes;
    });
  }

  void _updateHistory(String productName) {
    _historyDebouncer.run(() async {
      final p = Provider.of<PharmacyProvider>(context, listen: false);
      final history = await p.getProductSaleHistory(productName);
      if (mounted) {
        setState(() {
          _productHistory = history;
        });
      }
    });
  }

  void _onHeaderSearch(String query, ValueNotifier<List<dynamic>> targetList, List<dynamic> Function(PharmacyProvider) source) {
    if (query.trim().isEmpty) {
      targetList.value = [];
      return;
    }

    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final String cleanQuery = query.trim().toUpperCase();

    final all = source(p);

    // CODE MASTER FIX: Use startsWith to only match starting letters
    final matches = all.where((item) {
      String name = "";
      if (item is Patient) {
        name = item.name;
      } else if (item is Doctor) {
        name = item.name;
      } else if (item is String) {
        name = item;
      }
      return name.toLowerCase().startsWith(query.toLowerCase().trim());
    }).take(5).toList();

    List<dynamic> results = List.from(matches);

    // CODE MASTER FIX: Put "Add New" option at the VERY END, and hide if exact match exists
    bool exactMatchExists = matches.any((item) {
      String name = "";
      if (item is Patient) {
        name = item.name;
      } else if (item is Doctor) {
        name = item.name;
      } else if (item is String) {
        name = item;
      }
      return name.toUpperCase() == cleanQuery;
    });

    if (!exactMatchExists) {
      results.add(cleanQuery); // This acts as the "ADD NEW NAME" at the bottom of the list
    }

    targetList.value = results;
    _searchIdx.value = 0;
  }

  void _onNameSelected(TextEditingController ctrl, ValueNotifier<List<dynamic>> list, dynamic item, FocusNode? next) {
    if (item is Patient) {
      ctrl.text = item.name.toUpperCase();
      _mobileCtrl.text = item.mobile;
    } else if (item is Doctor) {
      ctrl.text = item.name.toUpperCase();
    } else if (item is String) {
      ctrl.text = item.toUpperCase();
    }

    list.value = [];
    if (next != null) next.requestFocus();
    setState(() {});
  }



  bool _handleGlobalKeys(KeyEvent event) {
    if (_isDialogOpen) return false;

    // ---> CRITICAL: If focus is inside ANY field of Special Order window, DO NOT intercept Enter or Tab! <---
    final bool isSpecialOrderFocused = _specialCustomerNameFocus.hasFocus ||
        _specialCustomerPhoneFocus.hasFocus ||
        _agentFocus.hasFocus ||
        _expectingDateFocus.hasFocus ||
        _saveSpecialOrderFocus.hasFocus ||
        _specialSearchFocus.hasFocus ||
        _specialOrderFocusNodes.values.any((f) => f.hasFocus);

    if (isSpecialOrderFocused) {
      return false;
    }

    if (event is KeyUpEvent) return false;

    final key = event.logicalKey;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final bool isCtrl = HardwareKeyboard.instance.isControlPressed;

    // ---> NEW FIX: Handle Dropdown Overlays FIRST <---
    final bool isOverlayOpen = _searchList.value.isNotEmpty ||
        _batchList.value.isNotEmpty ||
        _specialSearchList.value.isNotEmpty ||
        _patientSearchList.value.isNotEmpty ||
        _doctorSearchList.value.isNotEmpty;

    if (isOverlayOpen && event is KeyDownEvent) {
      final list = _patientSearchList.value.isNotEmpty ? _patientSearchList.value
          : _doctorSearchList.value.isNotEmpty ? _doctorSearchList.value
          : _specialSearchList.value.isNotEmpty ? _specialSearchList.value
          : (_batchList.value.isNotEmpty ? _batchList.value : _searchList.value);

      // Allow vertical arrows to navigate the list properly even if focus is inside the TextField
      if (key == LogicalKeyboardKey.arrowDown) {
        if (list.isEmpty) return true;
        _searchIdx.value = (_searchIdx.value + 1) % list.length;
        _scrollToIdx(_searchIdx.value);
        return true;
      } else if (key == LogicalKeyboardKey.arrowUp) {
        if (list.isEmpty) return true;
        _searchIdx.value = (_searchIdx.value - 1 + list.length) % list.length;
        _scrollToIdx(_searchIdx.value);
        return true;
      }
      else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
        if (list.isNotEmpty) {
          if (_patientSearchList.value.isNotEmpty) {
            final ctrl = _specialCustomerNameFocus.hasFocus ? _specialCustomerNameCtrl : _patientCtrl;
            final next = ctrl == _patientCtrl ? _mobileFocus : _specialCustomerPhoneFocus;
            _onNameSelected(ctrl, _patientSearchList, list[_searchIdx.value] as String, next);
          } else if (_doctorSearchList.value.isNotEmpty) {
            _onNameSelected(_doctorCtrl, _doctorSearchList, list[_searchIdx.value] as String, null);
          } else if (_specialSearchList.value.isNotEmpty) {
            _onSpecialProductSelected(list[_searchIdx.value] as Product);
          } else {
            // ---> FIX: Explicitly commit the selected batch and jump to Qty (Col 6) <---
            final selectedProduct = list[_searchIdx.value] as Product;
            _handleBatchSelection(row: _focusedRowIndex, product: selectedProduct);
          }
          return true;
        }
      }
    }

    // Headless Barcode Scanner & Global Hotkeys logic
    if (event is KeyDownEvent) {
      // FIX: Only handle global keys if THIS instance of SalesScreen has focus (prevents double-triggering across multiple tabs)
      if (!_rootFocus.hasFocus && !_rootFocus.hasPrimaryFocus) return false;

      final now = DateTime.now();
      if (now.difference(_lastKeyPress).inMilliseconds > 50) {
        _barcodeBuffer = "";
      }
      _lastKeyPress = now;

      if (event.logicalKey == LogicalKeyboardKey.enter && _barcodeBuffer.length >= 5) {
        final codeToProcess = _barcodeBuffer;
        _barcodeBuffer = "";
        _barcodeDebouncer.run(() {
          _processBarcode(codeToProcess);
        });
        return true;
      }

      if (event.logicalKey == LogicalKeyboardKey.f1) {
        _resetPage();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.f2) {
        _resetPage();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.f3) {
        _openGenericSearchDialog();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.f5) {
        _saveAndPrintBill();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.f7) {
        _patientFocus.requestFocus();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.f8) {
        _rcvdAmtFocus.requestFocus();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.f9) {
        _exportToPdf(); // F9 Preview / PDF
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.f10) {
        _isExistingEntry && !_isDeleted ? _editSale() : _saveSale(isEdit: false); // F10 Save/Invoice
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.f11) {
        // F11: Hold current billing session and switch to next
        if (_isExistingEntry && _isDirty) {
          _showFastDialog(title: "Workspace Locked", content: "You have unsaved edits. Please save or press F2 to clear before switching workspaces.");
          return true;
        }
        final pharma = Provider.of<PharmacyProvider>(context, listen: false);
        _syncToGlobalSession(notify: true);
        int nextSession = (pharma.activeSessionIdx + 1) % 3;
        pharma.setSalesSession(nextSession);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Session Held! Switched to Workspace ${nextSession + 1}"), duration: const Duration(seconds: 1)),
        );
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.f12) {
        _saveAndPrintBill();
        return true;
      }

      if (event.character != null) {
        _barcodeBuffer += event.character!;
      }
    }

    if (event is KeyUpEvent) return false;

    if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) {
      if (_showSpecialOrderSidebar) {
        setState(() => _isSpecialOrderMinimized = !_isSpecialOrderMinimized);
        return true;
      }
    }

    // --- UPDATED: F6 SHORTCUT ROUTES TO SAVE OR EDIT AUTOMATICALLY ---
    if (key == LogicalKeyboardKey.f6) {
      _isExistingEntry && !_isDeleted ? _editSale() : _saveSale(isEdit: false);
      return true;
    }


    // --- SMART CONTEXT READER FOR SHORTCUTS ---
    String getActiveProductName() {
      final p = Provider.of<PharmacyProvider>(context, listen: false);

      // 1. If dropdown is open, grab the highlighted item!
      if (_searchList.value.isNotEmpty) {
        return _searchList.value[_searchIdx.value].name;
      }
      // 2. Otherwise, grab the text from the current row
      int row = _focusedRowIndex;
      String name = "";
      if (row >= 0 && row < _items.length) {
        name = _items[row].product.name;
        if (name.isEmpty) name = _getGridCtrl(row, 1).text;
      } else if (row == _items.length) {
        name = _getGridCtrl(row, 1).text;
      }

      if (name.trim().isNotEmpty) {
        // Resolve to master name if it's a partial match
        final matches = p.searchProducts(name.trim(), includeGenerics: false);
        if (matches.isNotEmpty) {
          return matches.first.name;
        }
      }

      return name;
    }


    // === NEW: Ctrl + 1 FOR PURCHASE HISTORY ===
    if (isCtrl && key == LogicalKeyboardKey.digit1) {
      String pName = getActiveProductName();
      if (pName.trim().isNotEmpty) {
        _openHistoryWindow(pName.trim(), false);
      }
      return true;
    }

    // === NEW: Ctrl + 2 FOR SALES HISTORY ===
    if (isCtrl && key == LogicalKeyboardKey.digit2) {
      String pName = getActiveProductName();
      if (pName.trim().isNotEmpty) {
        _openHistoryWindow(pName.trim(), true);
      }
      return true;
    }

    // === NEW: Ctrl + L FOR STOCK MOVEMENT LEDGER ===
    if (isCtrl && key == LogicalKeyboardKey.keyL) {
      String pName = getActiveProductName();
      if (pName.trim().isNotEmpty) {
        _openStockMovementDrawer(pName.trim());
      }
      return true;
    }

    // === NEW: F2 RESTORED FOR NEW PAGE ===
    if (key == LogicalKeyboardKey.f2) {
      _resetPage();
      return true;
    }


    if (HardwareKeyboard.instance.isControlPressed) {
      if (key == LogicalKeyboardKey.keyZ) {
        _performUndo();
        return true;
      }
      if (key == LogicalKeyboardKey.delete && _focusedRowIndex >= 0 && _focusedRowIndex < _items.length) {
        _safeDeleteRow(_focusedRowIndex); // CODE MASTER FIX
        _moveFocus(_focusedRowIndex, 1);
        return true;
      }
    }

    // if (isOverlayOpen) return true; // Handled at top now

    int row = _focusedRowIndex;
    int col = _focusedColIndex;
    if (row == -1) return false;

    // Check if the current focus is actually on a grid cell
    final currentFocus = FocusManager.instance.primaryFocus;
    if (currentFocus != null && row >= 0) {
      final gridNode = _getGridFocusNode(row, col);
      if (currentFocus != gridNode && currentFocus.parent != gridNode) {
        // Focus is likely in the Special Order panel or header, don't run grid keyboard logic
        return false;
      }
    }

    final ctrl = _getGridCtrl(row, col);

    // FAST BACKWARD OPTION: Shift + Tab or Shift + Enter
    if ((key == LogicalKeyboardKey.tab || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) && isShift) {
      int curIdx = _navCols.indexOf(col);
      if (curIdx > 0) {
        _moveFocus(row, _navCols[curIdx - 1], autoOpen: _navCols[curIdx - 1] == 4);
      } else if (curIdx == 0 && row > 0) {
        _moveFocus(row - 1, _navCols.last);
      }
      return true;
    }

    // FORWARD NAVIGATION
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.tab) {
      _onFieldSubmitted(row, col);
      return true;
    }

    // BOUNDARY CHECK: Left Arrow (Universal Undo behavior)
    if (key == LogicalKeyboardKey.arrowLeft) {
      int curIdx = _navCols.indexOf(col);
      if (curIdx > 0) {
        _moveFocus(row, _navCols[curIdx - 1], autoOpen: _navCols[curIdx - 1] == 4);
        return true;
      } else if (curIdx == 0 && row > 0) {
        _moveFocus(row - 1, _navCols.last);
        return true;
      }
      return false;
    }

    // BOUNDARY CHECK: Right Arrow
    if (key == LogicalKeyboardKey.arrowRight) {
      if (!ctrl.selection.isValid || ctrl.selection.baseOffset >= ctrl.text.length) {

        // ---> THE FIX: Right arrow on empty row jumps to Rcvd Amt <---
        if (row == _items.length && _getGridCtrl(row, 2).text.trim().isEmpty) {
          _closeAllDropdowns();
          _focusNotifier.value = null;
          _rcvdAmtFocus.requestFocus();
          _rcvdAmtCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _rcvdAmtCtrl.text.length);
          return true;
        }

        int curIdx = _navCols.indexOf(col);
        if (curIdx != -1 && curIdx < _navCols.length - 1) {
          _moveFocus(row, _navCols[curIdx + 1], autoOpen: _navCols[curIdx + 1] == 4);
          return true;
        } else if (curIdx == _navCols.length - 1 && row < _items.length) {
          _moveFocus(_items.length, _navCols.first, autoOpen: true);
          return true;
        }
      }
      return false; // Let the cursor move through the text normally
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (row < _items.length) {
        int nextCol = _navCols.contains(col) ? col : 1;
        _moveFocus(row + 1, nextCol);
      }
      return true;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (row > 0) {
        int nextCol = _navCols.contains(col) ? col : 1;
        _moveFocus(row - 1, nextCol);
      } else {
        _moveFocus(-1, 0);
      }
      return true;
    }

    return false;
  }

  void _scrollToIdx(int index) {
    if (!_dropdownScrollCtrl.hasClients) return;
    const double itemHeight = 24.0; // <--- CHANGED FROM 30 TO 24
    const double viewportHeight = 168.0; // <--- 7 items * 24 height
    double targetOffset = index * itemHeight;
    double currentOffset = _dropdownScrollCtrl.offset;

    if (targetOffset < currentOffset) {
      _dropdownScrollCtrl.jumpTo(targetOffset);
    } else if (targetOffset + itemHeight > currentOffset + viewportHeight) {
      _dropdownScrollCtrl.jumpTo(targetOffset - viewportHeight + itemHeight);
    }
  }

  void _startFastScroll(bool upward) {
    _scrollTimer?.cancel();
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!_dropdownScrollCtrl.hasClients) {
        timer.cancel();
        return;
      }
      final list = _isSelectingBatch ? _batchList.value : _searchList.value;
      if (list.isEmpty) {
        timer.cancel();
        return;
      }

      int newIdx;
      if (upward) {
        newIdx = _searchIdx.value - 1;
        if (newIdx < 0) newIdx = list.length - 1;
      } else {
        newIdx = _searchIdx.value + 1;
        if (newIdx >= list.length) newIdx = 0;
      }

      _searchIdx.value = newIdx;
      _scrollToIdx(newIdx);
    });
  }

  void _stopFastScroll() {
    _scrollTimer?.cancel();
  }



  String _getBatchUniqueKey(dynamic item) {
    if (item is SaleItem) {
      return "${item.product.id}_${item.product.batch}_${item.product.expiry}_${item.mrp}_${item.packin}_${item.landingCost}_${item.gstPercent}_${item.purchaseRate}_${item.supplier}";
    } else if (item is Product) {
      return "${item.id}_${item.batch}_${item.expiry}_${item.mrp}_${item.packSize}_${item.landingCost}_${item.gstPercent}_${item.purchaseRate}_${item.supplier}";
    }
    return "";
  }

  int _getCrossRowStockUsed(dynamic target, int excludeRow) {
    int used = 0;
    String targetKey = _getBatchUniqueKey(target);
    for (int i = 0; i < _items.length; i++) {
      if (i != excludeRow && _getBatchUniqueKey(_items[i]) == targetKey) {
        used += _items[i].qty + _items[i].fQty;
      }
    }
    return used;
  }

  // FORCEFUL HARDWARE ENTER KEY LISTENER

  Future<dynamic> _showFastDialog({required String title, required String content, Widget? contentWidget, bool isYesNo = false, bool isSuccess = false, bool showSpecialOrder = false, int initialFocusIdx = 1}) {
    if (!isSuccess) AppSounds.playError();
    _isDialogOpen = true;
    int focusedIdx = initialFocusIdx; // 0: Special Order, 1: OK/Yes, 2: No

    return showDialog<dynamic>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black12, // Light transparent background
        builder: (ctx) {
          Offset offset = Offset.zero; // Tracks window position
          return StatefulBuilder(
              builder: (context, setStateDialog) {
                return Transform.translate(
                  offset: offset,
                  child: Focus(
                      autofocus: true,
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent) {
                          if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                            if (focusedIdx == 0) {
                              Navigator.of(ctx).pop("special");
                            } else if (focusedIdx == 1) {
                              Navigator.of(ctx).pop(true);
                            } else {
                              Navigator.of(ctx).pop(false);
                            }
                            return KeyEventResult.handled;
                          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                            Navigator.of(ctx).pop(false);
                            return KeyEventResult.handled;
                          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                            if (showSpecialOrder && focusedIdx == 1) {
                              setStateDialog(() => focusedIdx = 0);
                              return KeyEventResult.handled;
                            } else if (isYesNo && focusedIdx == 1) {
                              setStateDialog(() => focusedIdx = 2);
                              return KeyEventResult.handled;
                            }
                          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                            if (showSpecialOrder && focusedIdx == 0) {
                              setStateDialog(() => focusedIdx = 1);
                              return KeyEventResult.handled;
                            } else if (isYesNo && focusedIdx == 2) {
                              setStateDialog(() => focusedIdx = 1);
                              return KeyEventResult.handled;
                            }
                          }
                        }
                        return KeyEventResult.ignored;
                      },
                      child: Dialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        backgroundColor: const Color(0xFFF5F5F7),
                        elevation: 10,
                        child: SizedBox(
                          width: 400,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // === DRAGGABLE HEADER ===
                              GestureDetector(
                                onPanUpdate: (details) => setStateDialog(() => offset += details.delta),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: isSuccess ? Colors.green.shade100 : (isYesNo ? Colors.blue.shade100 : Colors.red.shade100),
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                      border: Border(bottom: BorderSide(color: Colors.grey.shade300))
                                  ),
                                  child: Row(children: [
                                    Icon(
                                        isSuccess ? Icons.check_circle : (isYesNo ? Icons.help_rounded : Icons.warning_rounded),
                                        color: isSuccess ? Colors.green.shade800 : (isYesNo ? Colors.blue.shade800 : Colors.red.shade800),
                                        size: 22
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text(title, style: TextStyle(color: isSuccess ? Colors.green.shade900 : (isYesNo ? Colors.blue.shade900 : Colors.red.shade900), fontWeight: FontWeight.bold, fontSize: 15))),
                                  ]),
                                ),
                              ),
                              // CONTENT
                              Flexible(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(16),
                                  child: contentWidget ?? Text(content, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                                ),
                              ),
                              // ACTIONS
                              Padding(
                                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                                child: Row(
                                    children: [
                                      if (showSpecialOrder)
                                        ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: focusedIdx == 0 ? Colors.green : Colors.blue.shade50,
                                              foregroundColor: focusedIdx == 0 ? Colors.white : Colors.blue.shade900,
                                              side: focusedIdx == 0 ? BorderSide(color: Colors.green.shade900, width: 2) : null,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                            ),
                                            onPressed: () => Navigator.pop(ctx, "special"),
                                            child: const Text("ADD SPECIAL ORDER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))
                                        ),
                                      const Spacer(),
                                      if (isYesNo) ...[
                                        ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: focusedIdx == 2 ? Colors.blue : Colors.grey.shade100,
                                              foregroundColor: focusedIdx == 2 ? Colors.white : Colors.black87,
                                              side: focusedIdx == 2 ? const BorderSide(color: Colors.black26, width: 2) : null,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                            ),
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: const Text("No", style: TextStyle(fontWeight: FontWeight.bold))
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: focusedIdx == 1 ? Colors.blue : Colors.grey.shade300,
                                            foregroundColor: focusedIdx == 1 ? Colors.white : Colors.black87,
                                            side: focusedIdx == 1 ? const BorderSide(color: Colors.black26, width: 2) : null,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                          ),
                                          onPressed: () => Navigator.pop(ctx, isYesNo ? true : true),
                                          child: Text(isYesNo ? "Yes" : "OK", style: const TextStyle(fontWeight: FontWeight.bold))
                                      )
                                    ]),
                              )
                            ],
                          ),
                        ),
                      )
                  ),
                );
              }
          );
        }
    ).then((val) {
      if (mounted) setState(() => _isDialogOpen = false);
      return val;
    });
  }

  void _onFieldSubmitted(int row, int col) async {
    // ---> THE FIX: Master Catch for Empty Row <---
    // If on the blank row and Product is empty, ANY 'Enter' or 'Tab' jumps to Rcvd Amt
    if (row == _items.length && _getGridCtrl(row, 2).text.trim().isEmpty) {
      _closeAllDropdowns();
      _focusNotifier.value = null;
      _rcvdAmtFocus.requestFocus();
      _rcvdAmtCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _rcvdAmtCtrl.text.length);
      return;
    }

    if (col == 2) {
      String typedText = _getGridCtrl(row, 2).text.trim();
      final p = Provider.of<PharmacyProvider>(context, listen: false);

      if (_searchList.value.isNotEmpty) {
        final selected = _searchList.value[_searchIdx.value];
        if (selected.id == "NEW") {
          _promptCreateNewProduct(selected.name);
          return;
        }

        final bool isExactMatch = Product.cleanProductName(selected.name).toLowerCase() == Product.cleanProductName(typedText).toLowerCase();
        if (isExactMatch || _searchIdx.value > 0) {
          _onProductSelected(selected);
        } else {
          final matches = p.searchProducts(typedText, includeGenerics: false);
          if (matches.isNotEmpty) {
            _onProductSelected(matches.first);
          } else {
            _promptCreateNewProduct(typedText);
          }
        }
      } else if (typedText.isNotEmpty) {
        final matches = p.searchProducts(typedText, includeGenerics: false);
        if (matches.isNotEmpty) {
          _onProductSelected(matches.first);
        } else {
          _promptCreateNewProduct(typedText);
        }
      } else {
        _moveFocus(row, 4, autoOpen: true);
      }
    }
    else if (col == 4) {
      String typed = _getGridCtrl(row, 4).text.trim().toUpperCase();

      if (_batchList.value.isNotEmpty) {
        final selected = _batchList.value[_searchIdx.value];
        final exactIdx = _batchList.value.indexWhere((b) => _cleanBatch(b.batch).toUpperCase() == typed);
        _handleBatchSelection(row: row, product: exactIdx != -1 ? _batchList.value[exactIdx] : selected);
      } else {
        final p = Provider.of<PharmacyProvider>(context, listen: false);
        String prodName = row < _items.length ? _items[row].product.name : _getGridCtrl(row, 2).text;
        final availableBatches = p.products.where((it) => it.name.toLowerCase() == prodName.toLowerCase() && it.stock > 0).toList();
        final match = availableBatches.where((b) => _cleanBatch(b.batch).toUpperCase() == typed).toList();

        if (match.isNotEmpty) {
          _handleBatchSelection(row: row, product: match.first);
        } else if (availableBatches.isNotEmpty) {
          // ---> THE FIX: AUTO-SELECT BEST BATCH IF SKIPPED OR MISMATCHED <---
          availableBatches.sort((a, b) => _parseExpiry(a.expiry).compareTo(_parseExpiry(b.expiry)));
          _commitSelection(row, availableBatches.first, stayOnProduct: false);
        } else {
          _moveFocus(row, 7);
        }
      }
    } else if (col == 7) {
      if (_getGridCtrl(row, 7).text.isEmpty) _getGridCtrl(row, 7).text = "0";

      int requestedQty = int.tryParse(_getGridCtrl(row, 7).text) ?? 0;
      final currentItem = _items[row];
      int stockAlreadyUsed = _getCrossRowStockUsed(currentItem, row);
      int originalQtyInThisInvoice = _originalInvoiceBatchQtys["${currentItem.product.id}|${currentItem.product.batch.trim().toUpperCase()}"] ?? 0;
      int actualAvailableForThisRow = currentItem.product.stock + originalQtyInThisInvoice - stockAlreadyUsed;

      if (requestedQty > actualAvailableForThisRow) {
        final String currentBatchKey = _getBatchUniqueKey(currentItem.product);
        final otherBatches = Provider.of<PharmacyProvider>(context, listen: false).products.where((it) =>
        it.name.toLowerCase() == currentItem.product.name.toLowerCase() &&
            it.stock > 0 && _getBatchUniqueKey(it) != currentBatchKey &&
            !_parseExpiry(it.expiry).isBefore(DateTime.now())
        ).toList();

        if (otherBatches.isEmpty) {
          int safeQty = actualAvailableForThisRow < 0 ? 0 : actualAvailableForThisRow;
          int shortage = requestedQty - safeQty;
          bool? addToSpecial = await _showFastDialog(
            title: "Stock Shortage",
            content: "",
            contentWidget: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black, fontFamily: 'Roboto'),
                children: [
                  TextSpan(text: "Only $safeQty available. Add $shortage to "),
                  const TextSpan(text: "Special Orders", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  const TextSpan(text: "?"),
                ]
              )
            ),
            isYesNo: true,
            initialFocusIdx: 2
          );
          setState(() {
            _items[row].qty = safeQty;
            _getGridCtrl(row, 7, safeQty.toString()).text = safeQty.toString();
            _calculateItem(row);
          });
          if (addToSpecial == true) {
            _triggerSpecialOrderFocus(currentItem.product.name, shortage);
          } else {
            _moveFocus(row, 11);
          }
        } else {
          bool? wantsSplit = await _showFastDialog(title: "Split Batch?", content: "Only $actualAvailableForThisRow available. Add another batch?", isYesNo: true, initialFocusIdx: 1);
          if (wantsSplit == true) {
            _handleAutoSplit(row, requestedQty, actualAvailableForThisRow);
          } else {
            setState(() {
              int safeQty = actualAvailableForThisRow < 0 ? 0 : actualAvailableForThisRow;
              _items[row].qty = safeQty;
              _getGridCtrl(row, 7, safeQty.toString()).text = safeQty.toString();
              _calculateItem(row);
            });
            _moveFocus(row, 11);
          }
        }
      } else {
        _moveFocus(row, 11);
      }
    } else if (col == 11) {
      if (_getGridCtrl(row, 11).text.isEmpty) _getGridCtrl(row, 11).text = "0";
      _moveFocus(_items.length, 2, autoOpen: true);
    } else {
      int curIdx = _navCols.indexOf(col);
      if (curIdx != -1 && curIdx < _navCols.length - 1) {
        _moveFocus(row, _navCols[curIdx + 1], autoOpen: _navCols[curIdx + 1] == 3);
      } else {
        _moveFocus(_items.length, 2, autoOpen: true);
      }
    }
  }

  void _handleAutoSplit(int startRow, int totalRequested, int availableInCurrent) async {
    _saveUndoState();

    int startingQty = availableInCurrent < 0 ? 0 : availableInCurrent;
    int remaining = totalRequested - startingQty;

    _items[startRow].qty = startingQty;
    _getGridCtrl(startRow, 7, startingQty.toString()).text = startingQty.toString();

    final p = Provider.of<PharmacyProvider>(context, listen: false);
    String prodName = _items[startRow].product.name;
    final String currentBatchKey = _getBatchUniqueKey(_items[startRow].product);
    final otherBatches = p.products.where((it) =>
    it.name.toLowerCase() == prodName.toLowerCase() &&
        it.stock > 0 && _getBatchUniqueKey(it) != currentBatchKey &&
        !_parseExpiry(it.expiry).isBefore(DateTime.now())
    ).toList();

    otherBatches.sort((a, b) => _parseExpiry(a.expiry).compareTo(_parseExpiry(b.expiry)));

    int addedRows = 0;

    setState(() {
      for (var batch in otherBatches) {
        if (remaining <= 0) break;

        int bLoose = batch.stock;

        int stockAlreadyUsed = _getCrossRowStockUsed(batch, -1);
        int originalQtyInThisInvoice = _originalInvoiceBatchQtys["${batch.id}|${batch.batch.trim().toUpperCase()}"] ?? 0;
        int trueAvailable = bLoose + originalQtyInThisInvoice - stockAlreadyUsed;

        if (trueAvailable <= 0) continue;

        int qtyToTake = remaining > trueAvailable ? trueAvailable : remaining;
        remaining -= qtyToTake;
        addedRows++;

        double ps = batch.packSize == 0 ? 1 : batch.packSize.toDouble();
        double unitMrp = batch.mrp / ps;
        // Respect the batch's actual salePrice if defined; otherwise fallback to MRP
        double unitSRate = (batch.salePrice > 0 ? batch.salePrice : batch.mrp) / ps;

        _items.insert(startRow + addedRows, SaleItem(
            product: Product(
                id: batch.id, name: batch.name, batch: batch.batch, expiry: batch.expiry,
                packSize: batch.packSize, mrp: batch.mrp, salePrice: batch.salePrice,
                purchaseRate: batch.purchaseRate, gstPercent: batch.gstPercent,
                rack: batch.rack, category: batch.category, manufacturer: batch.manufacturer,
                genericName: batch.genericName
            )..stock = bLoose,
            qty: qtyToTake, packin: batch.packSize,
            mrp: unitMrp, 
            sRate: unitSRate, 
            taxableSP: unitSRate,
            discPercent: _items[startRow].discPercent,
            discAmt: 0, gstPercent: batch.gstPercent, total: 0
        ));
      }

      for(int i = 0; i <= addedRows; i++) {
        _calculateItem(startRow + i);
      }
    });

    if (remaining > 0) {
      // THE DEEP SHORTAGE FIX
      bool? addToSpecial = await _showFastDialog(
          title: "Stock Shortage",
          content: "",
          contentWidget: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black, fontFamily: 'Roboto'),
              children: [
                TextSpan(text: "$remaining Qty is short across all valid batches. Add this $remaining to "),
                const TextSpan(text: "Special Orders", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                const TextSpan(text: "?"),
              ]
            )
          ),
          isYesNo: true,
          initialFocusIdx: 2
      );

      if (addToSpecial == true && mounted) {
        // ROUTE DIRECTLY TO THE SIDEBAR
        _triggerSpecialOrderFocus(_items[startRow].product.name, remaining);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _moveFocus(_items.length, 2, autoOpen: true);
        });
      }
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _moveFocus(_items.length, 2, autoOpen: true);
      });
    }
  }

  void _triggerSpecialOrderFocus(String pName, int qty) {
    setState(() {
      _orderType = 1;
      _showSpecialOrderSidebar = true;
      _isSpecialOrderMinimized = false;
      _activeNotificationTab = "special";
      _isProductSyncEnabled = false; // Turn off sync so it acts as an independent order
      _isSpecialSyncEnabled = false;

      if (!_extraSpecialItems.contains(pName)) {
        _extraSpecialItems.add(pName);
      }
      _specialOrderQtys[pName] = (_specialOrderQtys[pName] ?? 0) + qty;

      if (_specialOrderCtrls.containsKey(pName)) {
        _specialOrderCtrls[pName]!.text = _specialOrderQtys[pName].toString();
      }
    });

    _loadNotificationData();

    // 1. Unfocus the grid so it doesn't fight for the cursor
    _focusNotifier.value = null;

    // 2. Force focus into the Special Order sidebar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final node = _getSpecialFocusNode(pName);
      node.requestFocus();

      // Select all text so you can instantly overwrite the number
      final ctrl = _getSpecialCtrl(pName, qty);
      ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
    });
  }

  void _startProductSearch(String q) {
    if (_isSelectingBatch) {
      setState(() => _isSelectingBatch = false);
    }
    _batchList.value = [];
    final String query = q.trim();

    if (query.isEmpty) {
      _searchList.value = [];
      _searchIdx.value = 0;
      return;
    }

    _productSearchDebouncer.run(() {
      if (!mounted) return;
      final provider = Provider.of<PharmacyProvider>(context, listen: false);
      final results = provider.searchProducts(query, isSalesWindow: true);

      List<Product> list = List.from(results.take(50));
      final bool hasExact = results.any((p) => p.name.trim().toLowerCase() == query.toLowerCase());
      if (!hasExact && query.length >= 2) {
        list.add(Product(id: "NEW", name: query));
      }

      _searchList.value = list;
      _searchIdx.value = 0;
    });
  }

  void _startBatchSearch(int row, String q) {
    setState(() => _isSelectingBatch = true);
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    String prodName = row < _items.length ? _items[row].product.name : _getGridCtrl(row, 1).text;
    String prodId = row < _items.length ? _items[row].product.id : "";
    if (prodName.trim().isEmpty && prodId.trim().isEmpty) {
      _batchList.value = [];
      return;
    }

    final String query = q.trim().toUpperCase();

    // Find all stock batches for this product
    final rawMatches = p.products.where((prod) {
      bool isSameProduct = (prodId.isNotEmpty && prod.id == prodId) ||
          prod.name.trim().toLowerCase() == prodName.trim().toLowerCase();
      
      if (!isSameProduct) return false;

      if (query.isNotEmpty && !_cleanBatch(prod.batch).toUpperCase().contains(query)) {
        return false;
      }

      bool isCurrentRowBatch = row < _items.length &&
          prod.batch.trim().toLowerCase() == _items[row].product.batch.trim().toLowerCase();

      return prod.stock > 0 || isCurrentRowBatch;
    }).toList();

    // Consolidate identical batch rows into 1 row with combined stock
    final matches = p.consolidateBatches(rawMatches);

    matches.sort((a, b) {
      int expComp = _parseExpiry(a.expiry).compareTo(_parseExpiry(b.expiry));
      if (expComp != 0) return expComp;
      return b.stock.compareTo(a.stock);
    });
    _batchList.value = matches;
  }

  void _startSpecialProductSearch(String q) {
    if (q.trim().isEmpty) {
      _specialSearchList.value = [];
      return;
    }
    final results = Provider.of<PharmacyProvider>(context, listen: false).searchProducts(q.trim(), isSalesWindow: true);
    _specialSearchList.value = results.take(10).toList();
    _searchIdx.value = 0;
  }

  void _onSpecialProductSelected(Product p) {
    setState(() {
      _extraSpecialItems.add(p.name);
      _specialOrderQtys[p.name] = 1;
      _specialMainCtrl.clear();
      _specialSearchList.value = [];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getSpecialFocusNode(p.name).requestFocus();
    });
  }

  Future<void> _promptCreateNewProduct(String productName) async {
    _closeAllDropdowns();
    final String cleanName = productName.trim();
    if (cleanName.isEmpty) return;

    final bool? create = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Row(
          children: const [
            Icon(Icons.add_circle_outline, color: Colors.blue, size: 24),
            SizedBox(width: 8),
            Text("Create New Product?", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          "Product '$cleanName' was not found in Product Master.\n\nWould you like to register this as a new product?",
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("NO", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("YES, CREATE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (create == true && mounted) {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      appProvider.openProductRegistration(initialName: cleanName);
    }
  }

  void _onProductSelected(Product p) {
    if (p.id == "NEW") {
      _promptCreateNewProduct(p.name);
      return;
    }

    _isSelectingFromDropdown = true;
    int row = _focusedRowIndex;

    // If focused on the new row line or index is out of bounds, target the new line
    if (row < 0 || row > _items.length) {
      row = _items.length;
    }

    // Use the verified _commitSelection which correctly creates SaleItem and updates controllers
    _commitSelection(row, p);

    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _isSelectingFromDropdown = false;
    });
  }

  void _handleBatchSelection({required int row, required Product product}) async {
    _batchList.value = [];
    _searchList.value = [];

    if (product.stock <= 0) {
      final res = await _showFastDialog(
        title: "Zero Stock",
        content: "This item currently has no available stock.",
        showSpecialOrder: true,
        initialFocusIdx: 1, 
      );

      if (res == "special") {
        setState(() {
          _getGridCtrl(row, 1).clear();
          if (row < _items.length) {
            _items.removeAt(row);
          }
          _orderType = 1;
          _showSpecialOrderSidebar = true;
          _isSpecialOrderMinimized = false;
          _activeNotificationTab = "special";
        });
        _triggerSpecialOrderFocus(product.name, 1);
      } else if (res == true) {
        _commitSelection(row, product, stayOnProduct: true);
      }
      return;
    }

    _checkExpiryAndCommit(row, product);
  }

  void _checkExpiryAndCommit(int row, Product product) async {
    if (_isSelectingBatch && _parseExpiry(product.expiry).isBefore(DateTime.now())) {
      bool? proceed = await _showFastDialog(
          title: "Stock Is Expired",
          content: "This batch has passed its expiry date. Proceed anyway?",
          isYesNo: true,
          initialFocusIdx: 2
      );
      if (proceed == true) _commitSelection(row, product);
    } else {
      _commitSelection(row, product);
    }
  }

  void _finalizeBatchSelection(Product p) {
    _isSelectingFromDropdown = true; // LOCKS FOCUS
    
    setState(() {
      final row = _focusedRowIndex;
      _getGridCtrl(row, 3, p.rack).text = p.rack;
      _getGridCtrl(row, 4, p.batch).text = _cleanBatch(p.batch);
      _getGridCtrl(row, 5, p.expiry).text = p.expiry;

      if (row < _items.length) {
        final it = _items[row];
        it.product.rack = p.rack;
        it.product.batch = p.batch;
        it.product.expiry = p.expiry;
        it.product.stock = p.stock;

        if (p.mrp > 0) it.product.mrp = p.mrp;
        if (p.salePrice > 0) it.product.salePrice = p.salePrice;
        double ps = p.packSize == 0 ? 1 : p.packSize.toDouble();
        it.mrp = it.product.mrp/ps;
        it.sRate = it.product.mrp/ps;
        it.taxableSP = it.product.mrp/ps;
        it.gstPercent = p.gstPercent;
        _calculateItem(row);
      }
    });
    
    _isSelectingBatch = false;
    _batchList.value = [];
    _moveFocus(_focusedRowIndex, 7);
    
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _isSelectingFromDropdown = false;
    });
  }

  void _commitSelection(int row, Product p, {bool stayOnProduct = false}) {
    if (p.id == "NEW") {
      _promptCreateNewProduct(p.name);
      return;
    }
    _isSelectingFromDropdown = true; // LOCKS FOCUS
    _saveUndoState();

    if (p.schedule.toUpperCase().contains('H1') || p.schedule.toUpperCase() == 'H') {
      _showH1DrugWarningDialog(p.name, p.schedule);
    }

    int trueLooseStock = p.stock;
    int packSize = p.packSize > 0 ? p.packSize : 1;
    double pack = packSize.toDouble();
    double unitMrp = p.mrp > 0 ? (p.mrp / pack) : 0.0;
    double unitSRate = p.salePrice > 0 ? (p.salePrice / pack) : unitMrp;
    double unitLCost = p.landingCost > 0 ? (p.landingCost / pack) : (p.purchaseRate / pack);

    if (_isSelectingBatch) {
      // THE FIX: Removed Proactive Merging. It strictly populates the current row only.
      setState(() {
        if (row < _items.length) {
          final it = _items[row];
          it.product.batch = p.batch;
          it.product.expiry = p.expiry;
          it.product.rack = p.rack;
          it.product.mrp = p.mrp;
          it.product.salePrice = p.salePrice > 0 ? p.salePrice : p.mrp;
          it.product.purchaseRate = p.purchaseRate;
          it.product.landingCost = p.landingCost > 0 ? p.landingCost : p.purchaseRate;
          it.product.stock = trueLooseStock;
          it.product.gstPercent = p.gstPercent;
          it.product.supplier = p.supplier;
          if (p.genericName.trim().isNotEmpty) {
            it.product.genericName = p.genericName.trim();
          }
          it.packin = packSize;
          it.mrp = unitMrp;
          it.sRate = unitSRate;
          it.purchaseRate = p.purchaseRate / pack;
          it.landingCost = unitLCost;
          it.gstPercent = p.gstPercent;
          it.supplier = p.supplier;

          if (it.qty <= 0) it.qty = 1;

          _getGridCtrl(row, 3).text = p.rack;
          _getGridCtrl(row, 4).text = _cleanBatch(p.batch);
          _getGridCtrl(row, 5).text = p.expiry;
          
          // Only populate Qty if it's currently blank, so we don't erase user input
          if (_getGridCtrl(row, 7).text.isEmpty) {
            _getGridCtrl(row, 7).text = it.qty.toString();
          }
          _calculateItem(row);
        }
      });
      _updateFooter(p);
      _isSelectingBatch = false;
      _batchList.value = [];
      
      if (stayOnProduct) {
        _moveFocus(row, 2);
      } else {
        _moveFocus(row, 7); // Move smoothly to Qty column
      }
    } else {
      setState(() {
        _getGridCtrl(row, 2, p.name).text = p.name;
        _getGridCtrl(row, 3).text = p.rack;
        _getGridCtrl(row, 4).text = _cleanBatch(p.batch);
        _getGridCtrl(row, 5).text = p.expiry;

        if (row == _items.length) {
          final newItem = SaleItem(
            product: Product(
              id: p.id,
              name: p.name,
              batch: p.batch,
              expiry: p.expiry,
              packSize: p.packSize > 0 ? p.packSize : 1,
              mrp: p.mrp,
              salePrice: p.salePrice > 0 ? p.salePrice : p.mrp,
              purchaseRate: p.purchaseRate,
              landingCost: p.landingCost,
              gstPercent: p.gstPercent,
              rack: p.rack,
              category: p.category,
              manufacturer: p.manufacturer,
              genericName: p.genericName,
              stock: p.stock,
            ),
            qty: 1, packin: packSize, mrp: unitMrp, sRate: unitSRate, taxableSP: unitSRate,
            discPercent: 0, discAmt: 0, gstPercent: p.gstPercent, total: unitSRate,
            landingCost: unitLCost, purchaseRate: p.purchaseRate / pack,
          );
          _items.add(newItem);

          _gridCtrls[newItem] = Map.from(_nextRowCtrls);
          _gridFocusNodes[newItem] = Map.from(_nextRowNodes);
          _nextRowCtrls.clear();
          _nextRowNodes.clear();

          _getGridCtrl(row, 7).text = "1";
          _calculateItem(row);
          _updateFooter(newItem.product);
        } else {
          final it = _items[row];
          it.product = Product(
            id: p.id,
            name: p.name,
            batch: p.batch,
            expiry: p.expiry,
            packSize: p.packSize > 0 ? p.packSize : 1,
            mrp: p.mrp,
            salePrice: p.salePrice > 0 ? p.salePrice : p.mrp,
            purchaseRate: p.purchaseRate,
            landingCost: p.landingCost,
            gstPercent: p.gstPercent,
            rack: p.rack,
            category: p.category,
            manufacturer: p.manufacturer,
            genericName: p.genericName,
            stock: p.stock,
          );
          it.packin = packSize; it.mrp = unitMrp; it.sRate = unitSRate;
          it.taxableSP = unitSRate; it.landingCost = unitLCost;
          it.purchaseRate = p.purchaseRate / pack; it.gstPercent = p.gstPercent;
          if (it.qty <= 0) it.qty = 1;

          if (_getGridCtrl(row, 7).text.isEmpty) {
            _getGridCtrl(row, 7).text = it.qty.toString();
          }
          _calculateItem(row);
          _updateFooter(it.product);
        }
      });
      _searchList.value = [];
      if (stayOnProduct) {
        _moveFocus(row, 2);
      } else {
        _moveFocus(row, 4, autoOpen: true);
      }
    }

    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _isSelectingFromDropdown = false;
    });
  }

  // Pure math calculation: zero text controller touches, zero UI overhead
  void _recalculateItemSilent(SaleItem it, {required bool isGstMode}) {
    _recalculateItem(it, isGstMode: isGstMode);
  }

  // UI-facing calculation: used only when a single row changes via user input
  void _calculateItem(int row) {
    if (row >= _items.length) return;
    final it = _items[row];

    _recalculateItemSilent(it, isGstMode: _gstType == 1);

    _getGridCtrl(row, 9).text = it.product.mrp.toStringAsFixed(2);
    _getGridCtrl(row, 10).text = it.mrp.toStringAsFixed(2);
    _getGridCtrl(row, 12).text = it.discAmt.toStringAsFixed(2);
    double gVal = TaxCalculator.roundGstPercent(it.gstPercent);
    _getGridCtrl(row, 13).text = gVal % 1 == 0 ? gVal.toInt().toString() : gVal.toStringAsFixed(1);
    _getGridCtrl(row, 14).text = it.total.toStringAsFixed(2);

    _calculateFooter();
  }

  void _recalculateItem(SaleItem item, {bool isGstMode = false}) {
    double pack = (item.packin > 0) ? item.packin.toDouble() : 1.0;

    // Set Pack MRP and Unit MRP
    if (item.product.mrp <= 0 && item.mrp > 0) {
      item.product.mrp = item.mrp * pack;
    }
    item.mrp = item.product.mrp > 0 ? (item.product.mrp / pack) : item.mrp;

    // Unit Selling Rate in Paise
    if (item.sRate <= 0) {
      if (item.product.salePrice > 0) {
        item.sRate = item.product.salePrice / pack;
      } else {
        item.sRate = item.mrp;
      }
    }

    int sRatePaise = TaxCalculator.toPaise(item.sRate);
    int grossPaise = sRatePaise * item.qty;

    // Discount Calculation in Paise
    if (item.discPercent > 0) {
      int discAmtPaise = ((grossPaise * item.discPercent) / 100.0).round();
      item.discAmt = discAmtPaise / 100.0;
    } else {
      item.discAmt = 0.0;
    }
    int discAmtPaise = TaxCalculator.toPaise(item.discAmt);
    int netTaxablePaise = grossPaise - discAmtPaise;
    if (netTaxablePaise < 0) netTaxablePaise = 0;

    // GST Calculation (Retail sales are inclusive of GST - Integer Paise Model)
    item.gstPercent = TaxCalculator.roundGstPercent(item.gstPercent);
    if (isGstMode && item.gstPercent > 0) {
      final res = TaxCalculator.calculateInclusivePaise(netTaxablePaise, item.gstPercent);
      item.gstAmt = res.gstAmount;
      item.cgstAmt = res.cgstPaise / 100.0;
      item.sgstAmt = res.sgstPaise / 100.0;
      item.total = res.totalAmount;
      item.taxableSP = item.qty > 0 ? (res.taxablePaise / (item.qty * 100.0)) : res.taxableAmount;
    } else {
      item.gstAmt = 0.0;
      item.cgstAmt = 0.0;
      item.sgstAmt = 0.0;
      item.total = netTaxablePaise / 100.0;
      item.taxableSP = item.qty > 0 ? (netTaxablePaise / (item.qty * 100.0)) : (netTaxablePaise / 100.0);
    }

    // Unit Landing Cost & Profit in Paise
    double effectivePackLCost = item.product.landingCost > 0
        ? item.product.landingCost
        : (item.product.purchaseRate > 0 ? item.product.purchaseRate : item.purchaseRate);

    int landingCostPaise = effectivePackLCost > 0 ? ((effectivePackLCost / pack) * 100).round() : 0;
    item.landingCost = landingCostPaise / 100.0;
    int totalCostPaise = landingCostPaise * (item.qty + item.fQty);
    int totalPaise = TaxCalculator.toPaise(item.total);

    item.profit = (totalPaise - totalCostPaise) / 100.0;
  }

  void _saveSpecialOrderOnly() async {
    final String currentPatient = _patientCtrl.text.trim();
    final String currentDoctor = _doctorCtrl.text.trim();

    if (currentPatient.isEmpty) {
      _patientFocus.requestFocus();
      _showFastDialog(title: "Validation Error", content: "Patient Name is mandatory before saving.");
      return;
    }
    if (currentDoctor.isEmpty) {
      _doctorFocus.requestFocus();
      _showFastDialog(title: "Validation Error", content: "Doctor Name is mandatory before saving.");
      return;
    }

    final List<Map<String, dynamic>> specialItems = _buildSpecialOrderList();
    if (specialItems.isEmpty) {
      _showFastDialog(title: "No Items", content: "Please add at least one special order item.");
      return;
    }

    final p = Provider.of<PharmacyProvider>(context, listen: false);
    setState(() => _isLoading = true);

    try {
      // Use a special prefix for orders that are NOT full invoices yet
      final String entryNo = "ORD-${DateTime.now().millisecondsSinceEpoch}";

      final sale = SaleInvoice(
        entryNo: entryNo,
        date: _date,
        customerAcc: "Special Order",
        patient: _patientCtrl.text,
        mobile: _mobileCtrl.text,
        doctor: _doctorCtrl.text,
        specialOrderJson: jsonEncode(specialItems),
        items: [], // Empty items because it's just an order
        grandTotal: 0,
        agent: _agentCtrl.text,
        expectingDate: _expectingDateCtrl.text,
        specialCustomerName: _specialCustomerNameCtrl.text,
        specialCustomerPhone: _specialCustomerPhoneCtrl.text,
        isPaid: false,
      );

      await p.saveSale(sale);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Special Order Saved to Book"), backgroundColor: Colors.green),
        );
        setState(() {
          _specialOrderQtys.clear();
          _extraSpecialItems.clear();
          _specialOrderCtrls.clear();
          _showSpecialOrderSidebar = false;
        });
      }
    } catch (e) {
      _showFastDialog(title: "Save Failed", content: "Error: $e");
    } finally {
      _isSaving = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openSpecialOrdersList() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.9,
            child: const SpecialOrdersScreen(isDialog: true),

          ),
        ),
      ),
    );
  }


  Future<bool> _loadSaleData(String invNo) async {
    // ---> THE FIX: Strictly discard draft when navigating <---
    if (!_isExistingEntry) {
      final p = Provider.of<PharmacyProvider>(context, listen: false);
      p.clearSaleDraft();
    }

    setState(() => _isLoading = true);

    // Kill dropdowns before loading
    _closeAllDropdowns();

    final p = Provider.of<PharmacyProvider>(context, listen: false);
    try {
      final data = await p.navigateInvoice(invNo, 'find', isPurchase: false);

      // 1. If data is found AND it is NOT marked as deleted, load it normally
      if (data != null && data['is_deleted'] != 1 && mounted) {
        // --- SAFE FOCUS TRANSITION ---
        FocusScope.of(context).unfocus();
        await Future.delayed(Duration.zero);

        final items = await p.getInvoiceItems(invNo, isPurchase: false);
        if (!mounted) return false;

        // Pre-build O(1) maps for fast batch & master product lookup
        final productBatchMap = <String, Product>{};
        for (final pItem in p.products) {
          productBatchMap["${pItem.id}|${pItem.batch.trim().toUpperCase()}"] = pItem;
        }

        final masterIdMap = <String, Product>{};
        final masterNameMap = <String, Product>{};
        for (final pm in p.productMaster) {
          if (pm.id.isNotEmpty) masterIdMap[pm.id] = pm;
          final upper = pm.name.trim().toUpperCase();
          if (upper.isNotEmpty && !masterNameMap.containsKey(upper)) {
            masterNameMap[upper] = pm;
          }
        }

        setState(() {
          // RESET TO DEFAULTS FIRST to avoid data bleeding
          _gridCtrls.clear();
          _gridFocusNodes.clear();
          _isExistingEntry = true;
          _isDirty = false; // Reset dirty flag on load
          _isDeleted = (data['is_deleted'] == 1 || data['is_deleted'] == true || data['is_deleted'] == '1'); // Check if deleted
          _orderType = 0;
          _showSpecialOrderSidebar = false;
          _isSpecialOrderMinimized = false;
          _items.clear();
          _errorCells.clear();
          _specialOrderQtys.clear();
          _extraSpecialItems.clear();
          _specialOrderCtrls.clear();
          _originalItemSnapshots.clear();
          _highlightEdits = false;
          _originalInvoiceBatchQtys.clear();

          // LOAD ACTUAL HEADER DATA
          String rawEntry = data['entry_no']?.toString() ?? "";
          if (rawEntry.contains('_')) {
            rawEntry = rawEntry.substring(rawEntry.indexOf('_') + 1);
          }
          _entryNo = rawEntry.isNotEmpty ? rawEntry : invNo;
          _date = DateTime.tryParse(data['date'].toString()) ?? DateTime.now();
          _customerAcc = data['customer_acc']?.toString() ?? 'Cash';
          _customerAccCtrl.text = _customerAcc;
          _gstType = (data['tax_type'] == "Gst") ? 1 : 2;

          _patientCtrl.text = data['patient']?.toString() ?? 'P1';
          _mobileCtrl.text = data['mobile']?.toString() ?? '';
          _doctorCtrl.text = data['doctor']?.toString() ?? 'D1';
          _doctorRegNoCtrl.text = data['doctor_reg_no']?.toString() ?? '';
          _daysCtrl.text = data['days']?.toString() ?? "0";

          _agentCtrl.text = data['agent'] ?? "Admin";
          _expectingDateCtrl.text = data['expecting_date'] ?? "";
          _specialCustomerNameCtrl.text = data['special_customer_name'] ?? "";
          _specialCustomerPhoneCtrl.text = data['special_customer_phone'] ?? "";
          _salesReturnCtrl.text = (data['sales_return_amt'] ?? 0.0).toStringAsFixed(2);

          // RESTORE FOOTER AMOUNTS, DISCOUNTS & RECEIVED PAYMENTS
          double savedDiscount = (data['discount'] as num?)?.toDouble() ?? 0.0;
          double savedDiscPct = (data['discount_percent'] as num?)?.toDouble() ?? 0.0;
          double savedRcvd = (data['rcvd_amt'] as num?)?.toDouble() ?? 0.0;

          _footerDiscAmtCtrl.text = savedDiscount.toStringAsFixed(2);
          _footerDiscPctCtrl.text = savedDiscPct.toStringAsFixed(0);
          _rcvdAmtCtrl.text = savedRcvd > 0 ? savedRcvd.toStringAsFixed(2) : "0";

          String jsonStr = data['special_order_json'] ?? "[]";
          try {
            List<dynamic> list = jsonDecode(jsonStr);
            if (list.isNotEmpty) {
              _orderType = 1; // Special Order mode
              for (var item in list) {
                String name = item['name'] ?? "";
                int q = item['qty'] ?? 0;
                if (name.isNotEmpty) {
                  _specialOrderQtys[name] = q;
                  bool inBill = items.any((m) => (m['product_name']?.toString().trim().toUpperCase() == name.trim().toUpperCase()));
                  if (!inBill) _extraSpecialItems.add(name);
                }
              }
            }
          } catch (e) {
            debugPrint("Error recovering special order: $e");
          }

          for (var m in items) {
            int packin = (m['packin'] as num?)?.toInt() ?? (m['packing'] as num?)?.toInt() ?? 1;
            if (packin <= 0) packin = 1;
            double pack = packin.toDouble();

            double packMrp = (m['mrp'] as num?)?.toDouble() ?? 0.0;
            double sRateVal = (m['s_rate'] as num?)?.toDouble() ?? (m['sale_rate'] as num?)?.toDouble() ?? 0.0;

            // If sRateVal is equal to packMrp, it's a pack price -> convert to unit price
            double unitSRate = (sRateVal > 0 && sRateVal == packMrp && packin > 1)
                ? (sRateVal / pack)
                : (sRateVal > 0 ? sRateVal : (packMrp / pack));

            double pRateVal = (m['purchase_rate'] as num?)?.toDouble() ?? 0.0;
            double lCostVal = (m['landing_cost'] as num?)?.toDouble() ?? 0.0;

            String pId = m['product_id']?.toString() ?? "";
            String pBatch = m['batch_number']?.toString().trim().toUpperCase() ?? "";
            String key = "$pId|$pBatch";

            final prod = productBatchMap[key] ?? Product(
              id: pId,
              name: m['product_name']?.toString() ?? "",
              batch: m['batch_number']?.toString() ?? "",
              expiry: m['expiry_date']?.toString() ?? "",
              mrp: packMrp,
              salePrice: packMrp,
              packSize: packin,
              purchaseRate: pRateVal,
              landingCost: lCostVal,
              gstPercent: (m['gst_percent'] as num?)?.toDouble() ?? 12.0,
              supplier: m['supplier_name']?.toString() ?? "",
            );

            // Attach master generic name if batch product lacks it
            if (prod.genericName.isEmpty) {
              final masterMatch = masterIdMap[pId] ?? masterNameMap[prod.name.trim().toUpperCase()];
              if (masterMatch != null) prod.genericName = masterMatch.genericName;
            }

            // Ensure prod has pack-level MRP stored
            prod.mrp = packMrp;
            prod.packSize = packin;
            if (prod.expiry.isEmpty && m['expiry_date'] != null) {
              prod.expiry = m['expiry_date'].toString();
            }

            // CRITICAL: Clone product so each row owns an isolated copy in memory
            final isolatedProd = _cloneProduct(prod);

            // Track original stock reserved by this invoice
            _originalInvoiceBatchQtys[key] = (_originalInvoiceBatchQtys[key] ?? 0) + ((m['qty'] as num?)?.toInt() ?? 0);

            _items.add(SaleItem(
              product: isolatedProd, // <--- Use the isolated copy
              qty: (m['qty'] as num?)?.toInt() ?? (m['quantity'] as num?)?.toInt() ?? 0,
              packin: packin,
              mrp: packMrp / pack, // Unit MRP (e.g. 2.68)
              sRate: unitSRate,     // Unit Selling Rate (e.g. 2.42)
              taxableSP: unitSRate,
              discPercent: (m['disc_percent'] as num?)?.toDouble() ?? 0.0,
              discAmt: (m['disc_amt'] as num?)?.toDouble() ?? 0.0,
              gstPercent: TaxCalculator.roundGstPercent((m['gst_percent'] as num?)?.toDouble() ?? (m['tax_percent'] as num?)?.toDouble() ?? 0.0),
              gstAmt: (m['gst_amt'] as num?)?.toDouble() ?? 0.0,
              cgstAmt: (m['cgst_amt'] as num?)?.toDouble() ?? 0.0,
              sgstAmt: (m['sgst_amt'] as num?)?.toDouble() ?? 0.0,
              total: (m['total'] as num?)?.toDouble() ?? 0.0,
              purchaseRate: pRateVal / pack,
              landingCost: lCostVal > 0 ? (lCostVal / pack) : (pRateVal / pack),
              supplier: m['supplier_name']?.toString() ?? "",
            ));
          }

          for (int i = 0; i < _items.length; i++) {
            _calculateItem(i);
            _getGridCtrl(i, 7).text = _items[i].qty.toString();
            // Store by item reference with independent attributes
            _originalItemSnapshots[_items[i]] = {
              'id': _items[i].product.id,
              'name': _items[i].product.name.trim().toUpperCase(),
              'batch': _items[i].product.batch.trim().toUpperCase(),
              'qty': _items[i].qty,
              'discPercent': _items[i].discPercent,
            };
          }
          _calculateFooter();

          // Snapshot the complete original invoice for auditing and edit diffing
          _originalLoadedInvoice = SaleInvoice(
            entryNo: _entryNo,
            date: _date,
            customerAcc: _customerAcc,
            patient: _patientCtrl.text,
            mobile: _mobileCtrl.text,
            doctor: _doctorCtrl.text,
            doctorRegNo: _doctorRegNoCtrl.text,
            specialOrderJson: data['special_order_json'] ?? "[]",
            taxType: _gstType == 1 ? "Gst" : "Non Gst",
            days: int.tryParse(_daysCtrl.text) ?? 0,
            items: _items.map((it) => it.clone()).toList(),
            subTotal: double.tryParse(_subTotalCtrl.text) ?? 0,
            discount: savedDiscount,
            discountPercent: savedDiscPct,
            grandTotal: double.tryParse(_netTotalCtrl.text) ?? 0,
            rcvdAmt: savedRcvd,
            secondaryAcc: data['secondary_acc'] ?? "",
            secondaryAmt: (data['secondary_amt'] as num?)?.toDouble() ?? 0.0,
            paymentRemarks: data['payment_remarks'] ?? "",
            isPaid: (data['is_paid'] as int?) == 1,
          );
        });

        if (_isDeleted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("🗑️ DELETED ENTRY: Sales Invoice #$_entryNo is marked as DELETED."),
              backgroundColor: Colors.red.shade900,
              duration: const Duration(seconds: 4),
            ),
          );
        }

        // Remove focus so nothing is highlighted when viewing history
        _focusNotifier.value = null;
        return true;
      }
      // 2. ---> THE FIX: HANDLE DELETED OR MISSING ENTRIES VISUALLY <---
      else if (mounted) {
        FocusScope.of(context).unfocus();
        await Future.delayed(Duration.zero);

        if (data == null) {
          setState(() {
            _isExistingEntry = true;
            _isDeleted = true; // Lock UI because it doesn't exist
            _entryNo = invNo;
            _items.clear();
            _gridCtrls.clear();
            _gridFocusNodes.clear();
            _patientCtrl.clear();
            _mobileCtrl.clear();
            _doctorCtrl.clear();
          });
          _showFastDialog(title: "Invoice Not Found", content: "Entry #$invNo does not exist.");
          return false;
        } else {
          // ---> THE FIX: DELETED ENTRY DETECTED! LET THEM REUSE THE NUMBER! <---
          setState(() {
            _isExistingEntry = true; // Force overwrite on save
            _isDeleted = false; // UNLOCK UI!
            _isDirty = false;
            _entryNo = invNo;

            _items.clear();
            _gridCtrls.clear();
            _gridFocusNodes.clear();
            _originalInvoiceBatchQtys.clear();
            _specialOrderQtys.clear();
            _extraSpecialItems.clear();

            _patientCtrl.text = "P1"; // Reset to defaults
            _mobileCtrl.clear();
            _doctorCtrl.text = "D1";
            _daysCtrl.text = "0";

            _rcvdAmtCtrl.text = "0";
            _footerDiscPctCtrl.text = "0";
            _footerDiscAmtCtrl.text = "0.00";
            _calculateFooter();
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("Reusing Deleted Entry #$invNo"),
              backgroundColor: Colors.blue.shade800,
              duration: const Duration(seconds: 2),
            ));
          }

          _moveFocus(-1, 0); // Start cursor at Patient field
          return true;
        }
      }
      return false;
    } catch (e) {
      if (mounted) {
        _showFastDialog(
            title: "Error Loading Data",
            content: "Failed to load entry #$invNo: $e"
        );
      }
      return false;
    } finally {
      _isSaving = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _promptSave() async {
    // PRE-COMMIT HOOK: Validate mandatory fields before prompting for payment
    final String currentAcc = _customerAccCtrl.text.trim().isNotEmpty ? _customerAccCtrl.text.trim() : _customerAcc.trim();
    final String currentPatient = _patientCtrl.text.trim();
    final String currentDoctor = _doctorCtrl.text.trim();

    if (currentAcc.isEmpty) {
      _customerAccFocus.requestFocus();
      _showFastDialog(
        title: "Validation Error",
        content: "Account Name is mandatory. Please enter Account Name before saving.",
      );
      return;
    }
    if (currentPatient.isEmpty) {
      _patientFocus.requestFocus();
      _showFastDialog(
        title: "Validation Error",
        content: "Patient Name is mandatory. Please enter Patient Name before saving.",
      );
      return;
    }
    if (currentDoctor.isEmpty) {
      _doctorFocus.requestFocus();
      _showFastDialog(
        title: "Validation Error",
        content: "Doctor Name is mandatory. Please enter Doctor Name before saving.",
      );
      return;
    }

    // PRE-COMMIT HOOK: Force calculation of everything before asking for payment (Silent to avoid UI churn)
    for (var it in _items) {
      _recalculateItemSilent(it, isGstMode: _gstType == 1);
    }
    _calculateFooter();

    final double grandTotal = _netTotalNotifier.value;
    String acc1 = _customerAcc; // Defaults to what is selected in the footer
    String acc2 = "Bank";

    // If account is Credit, received amount must default to 0.00
    final bool isCredit = acc1.toUpperCase() == "CREDIT";
    final TextEditingController amt1Ctrl = TextEditingController(
      text: isCredit ? "0.00" : grandTotal.toStringAsFixed(2)
    );
    final TextEditingController amt2Ctrl = TextEditingController(text: "0.00");

    final res = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          int focusedIdx = 1; // 1: Save, 2: Cancel
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                      Navigator.of(ctx).pop(focusedIdx == 1);
                      return KeyEventResult.handled;
                    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                      Navigator.of(ctx).pop(false);
                      return KeyEventResult.handled;
                    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft || event.logicalKey == LogicalKeyboardKey.arrowRight) {
                      setDialogState(() => focusedIdx = (focusedIdx == 1 ? 2 : 1));
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: AlertDialog(
                  backgroundColor: const Color(0xFFF1F5F9), // Light grayish-blue background
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  title: Row(
                    children: [
                      const Icon(Icons.save, color: Colors.blue),
                      const SizedBox(width: 10),
                      Text(_isExistingEntry ? "Update Sale?" : "Save Sale?", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    ],
                  ),
                  content: SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _isExistingEntry
                              ? "Do you want to update this existing Sales Entry?"
                              : "Do you want to save this new Sales Entry?",
                          style: const TextStyle(fontSize: 14, color: Colors.black87),
                        ),
                        const SizedBox(height: 24),

                        // --- ROW 1 (Auto-filled with Grand Total) ---
                        Row(
                          children: [
                            const SizedBox(width: 80, child: Text("Customer", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                            Expanded(
                              child: Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(color: Colors.grey.shade200, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
                                child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: acc1,
                                      isExpanded: true,
                                      isDense: true,
                                      style: const TextStyle(fontSize: 12, color: Colors.black, fontWeight: FontWeight.bold),
                                      items: ["Cash", "Credit", "Card", "UPI"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                      onChanged: (v) {
                                        setDialogState(() {
                                          acc1 = v!;
                                          if (acc1.toUpperCase() == "CREDIT") {
                                            amt1Ctrl.text = "0.00";
                                            amt2Ctrl.text = "0.00";
                                          } else {
                                            amt1Ctrl.text = grandTotal.toStringAsFixed(2);
                                          }
                                        });
                                      },
                                    )
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              width: 90,
                              height: 32,
                              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.blue.shade400, width: 1.5), borderRadius: BorderRadius.circular(4)),
                              child: TextField(
                                controller: amt1Ctrl,
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black),
                                decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
                                onChanged: (v) {
                                  // Optional Magic: If they type a smaller amount in Box 1, Box 2 auto-calculates the rest!
                                  double entered = double.tryParse(v) ?? 0.0;
                                  if (entered <= grandTotal) {
                                    amt2Ctrl.text = (grandTotal - entered).toStringAsFixed(2);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // --- ROW 2 (Bank / Secondary Payment) ---
                        Row(
                          children: [
                            const SizedBox(width: 80, child: Text("Bank", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                            Expanded(
                              child: Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(color: Colors.grey.shade200, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
                                child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: acc2,
                                      isExpanded: true,
                                      isDense: true,
                                      style: const TextStyle(fontSize: 12, color: Colors.black, fontWeight: FontWeight.bold),
                                      items: ["Bank", "Card", "UPI", "Cash"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                      onChanged: (v) => setDialogState(() => acc2 = v!),
                                    )
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              width: 90,
                              height: 32,
                              decoration: BoxDecoration(color: Colors.grey.shade100, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
                              child: TextField(
                                controller: amt2Ctrl,
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black),
                                decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  actionsPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  actions: [
                    TextButton.icon(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(
                        backgroundColor: focusedIdx == 2 ? Colors.red.shade50 : null,
                        side: focusedIdx == 2 ? BorderSide(color: Colors.red.shade200, width: 2) : null,
                      ),
                      icon: const Icon(Icons.close, color: Colors.red, size: 16),
                      label: const Text("CANCEL (ESC)", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: focusedIdx == 1 ? Colors.blue.shade700 : Colors.grey.shade300,
                          foregroundColor: focusedIdx == 1 ? Colors.white : Colors.black54,
                          side: focusedIdx == 1 ? const BorderSide(color: Colors.black26, width: 2) : null,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))
                      ),
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text("SAVE (ENTER)", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                    ),
                  ],
                ),
              );
            },
          );
        }
    );

    if (res == true) {
      final double p1Amt = double.tryParse(amt1Ctrl.text) ?? 0.0;
      final double p2Amt = double.tryParse(amt2Ctrl.text) ?? 0.0;

      _saveSale(
        isEdit: _isExistingEntry,
        primaryAcc: acc1,
        primaryAmt: p1Amt,
        secondaryAcc: p2Amt > 0 ? acc2 : "",
        secondaryAmt: p2Amt,
      );
    } else {
      _rcvdAmtFocus.requestFocus();
    }
  }

  void _navigateEntry(String dir) async {
    // ---> THE FIX: Protect against losing unsaved edits <---
    if (_isExistingEntry && _isDirty) {
      bool? discard = await _promptDiscardChanges();
      if (discard != true) return; // User chose to stay
    }
    if (!mounted) return;

    // ---> THE FIX: Kill dropdowns before navigating <---
    _closeAllDropdowns();

    final p = Provider.of<PharmacyProvider>(context, listen: false);

    final data = await p.navigateInvoice(_entryNo, dir, isPurchase: false);
    if (data != null) {
      _loadSaleData(data['entry_no'].toString());
    } else if (dir == 'next') {
      if (_isExistingEntry) {
        _resetPage();
      } else {
        _showFastDialog(title: "Navigation", content: "NO MORE RECORDS TO SHOW");
      }
    } else if (dir == 'prev') {
      _showFastDialog(title: "Navigation", content: "FIRST RECORD REACHED");
    }
  }

  // --- GENERATE DETAILED EDIT DIFF SPANS FOR RE-WRITE DIALOG ---
  List<InlineSpan> _generateDiffSpans() {
    final List<InlineSpan> diffSpans = [];

    if (!_isExistingEntry || _originalLoadedInvoice == null) {
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
    // Patient Name
    final currentPatient = _patientCtrl.text.trim();
    final origPatient = _originalLoadedInvoice!.patient.trim();
    if (currentPatient.toUpperCase() != origPatient.toUpperCase()) {
      addDiffLine([
        const TextSpan(text: "patient name ", style: normalStyle),
        TextSpan(text: origPatient.isEmpty ? "(blank)" : origPatient, style: redStyle),
        const TextSpan(text: " to ", style: normalStyle),
        TextSpan(text: currentPatient.isEmpty ? "(blank)" : currentPatient, style: redStyle),
        const TextSpan(text: ".", style: normalStyle),
      ]);
    }

    // Doctor Name
    final currentDoctor = _doctorCtrl.text.trim();
    final origDoctor = _originalLoadedInvoice!.doctor.trim();
    if (currentDoctor.toUpperCase() != origDoctor.toUpperCase()) {
      addDiffLine([
        const TextSpan(text: "doctor name ", style: normalStyle),
        TextSpan(text: origDoctor.isEmpty ? "(blank)" : origDoctor, style: redStyle),
        const TextSpan(text: " to ", style: normalStyle),
        TextSpan(text: currentDoctor.isEmpty ? "(blank)" : currentDoctor, style: redStyle),
        const TextSpan(text: ".", style: normalStyle),
      ]);
    }

    // Customer Account / Payment Mode
    final currentAcc = _customerAccCtrl.text.trim();
    final origAcc = _originalLoadedInvoice!.customerAcc.trim();
    if (currentAcc.toUpperCase() != origAcc.toUpperCase() && currentAcc.isNotEmpty) {
      addDiffLine([
        const TextSpan(text: "payment account ", style: normalStyle),
        TextSpan(text: origAcc.isEmpty ? "(blank)" : origAcc, style: redStyle),
        const TextSpan(text: " to ", style: normalStyle),
        TextSpan(text: currentAcc, style: redStyle),
        const TextSpan(text: ".", style: normalStyle),
      ]);
    }

    // Footer Discount
    final currentDiscAmt = double.tryParse(_footerDiscAmtCtrl.text) ?? 0.0;
    final origDiscAmt = _originalLoadedInvoice!.discount;
    if ((currentDiscAmt - origDiscAmt).abs() > 0.01) {
      addDiffLine([
        const TextSpan(text: "footer discount ", style: normalStyle),
        TextSpan(text: "₹${origDiscAmt.toStringAsFixed(2)}", style: redStyle),
        const TextSpan(text: " to ", style: normalStyle),
        TextSpan(text: "₹${currentDiscAmt.toStringAsFixed(2)}", style: redStyle),
        const TextSpan(text: ".", style: normalStyle),
      ]);
    }

    // 2. ITEM LEVEL COMPARISONS
    final origItems = _originalLoadedInvoice!.items;
    final currentValidItems = _items.where((it) => it.product.name.trim().isNotEmpty).toList();

    int maxLen = origItems.length > currentValidItems.length ? origItems.length : currentValidItems.length;

    for (int i = 0; i < maxLen; i++) {
      if (i < origItems.length && i < currentValidItems.length) {
        final orig = origItems[i];
        final curr = currentValidItems[i];

        // Check Product Name
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

        // Check Batch Number
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

        // Check Quantity
        if (orig.qty != curr.qty) {
          addDiffLine([
            TextSpan(text: "qty ($currName) changed from ", style: normalStyle),
            TextSpan(text: "${orig.qty}", style: redStyle),
            const TextSpan(text: " to ", style: normalStyle),
            TextSpan(text: "${curr.qty}", style: redStyle),
            const TextSpan(text: ".", style: normalStyle),
          ]);
        }

        // Check Discount %
        if ((orig.discPercent - curr.discPercent).abs() > 0.01) {
          addDiffLine([
            TextSpan(text: "discount ($currName) changed from ", style: normalStyle),
            TextSpan(text: "${orig.discPercent.toStringAsFixed(1)}%", style: redStyle),
            const TextSpan(text: " to ", style: normalStyle),
            TextSpan(text: "${curr.discPercent.toStringAsFixed(1)}%", style: redStyle),
            const TextSpan(text: ".", style: normalStyle),
          ]);
        }

        // Check Sale Price / Rate
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
        // Item added
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
        // Item removed
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

  // --- NEW: EDIT CONFIRMATION METHOD ---
  void _editSale() async {
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
            "No modifications were detected on Entry #$_entryNo.\nThere are no changes to save.",
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
                "Re-write Entry #$_entryNo?",
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
                "The following changes will be applied to this entry:",
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
                "Are you sure you want to overwrite Entry #$_entryNo? Stock and ledger will be updated accordingly.",
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

    if (confirmed == true) {
      _saveSale(isEdit: true);
    }
  }

  void _printSale() async {
    if (_items.isEmpty) return;
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);
    final invoice = SaleInvoice(
      entryNo: _entryNo,
      date: _date,
      customerAcc: _customerAcc,
      patient: _patientCtrl.text,
      mobile: _mobileCtrl.text,
      doctor: _doctorCtrl.text,
      items: _items.where((it) => it.product.name.isNotEmpty).toList(),
      subTotal: _subTotalNotifier.value,
      discount: double.tryParse(_footerDiscAmtCtrl.text) ?? 0,
      grandTotal: _netTotalNotifier.value,
      taxType: _gstType == 1 ? "Gst" : "Non Gst",
    );

    await printWithCurrentProfile(
      context: context,
      invoice: invoice,
      companyProfile: pharma.companyProfile,
      a4PdfBuilder: () async => await InvoicePdfGenerator.buildPdfDocument(invoice, pharma.companyProfile),
    );
  }

  void handleAsyncPdfExport(SaleInvoice invoice, CompanyProfile company) async {
    final pdfBytes = await PdfWorkerService.generateInvoicePdfInBackground(
      invoice: invoice, 
      company: company,
    );
    
    await Printing.layoutPdf(onLayout: (format) async => pdfBytes);
  }

  void handleBackgroundPrint(SaleInvoice invoice, CompanyProfile company) {
    PrintSpoolerService.enqueuePrintTask(() async {
      // Offload formatting and raw socket dispatch completely to background queue
      await PrinterService.printPdfInvoice(invoice: invoice, companyProfile: company, directPrint: true);
    });
    
    // Cashier is instantly freed to begin the next bill without waiting for physical printing
  }

  void _exportToPdf() async {
    final validItems = _items.where((it) => it.product.name.trim().isNotEmpty && it.qty > 0).toList();
    if (validItems.isEmpty) {
      AppDialogs.showFastDialog(
        context: context,
        title: "No Items",
        content: "Please add valid items to the sales entry before exporting PDF.",
      );
      return;
    }

    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final invoice = SaleInvoice(
      entryNo: _entryNo.isEmpty ? "DRAFT" : _entryNo,
      date: _date,
      customerAcc: _customerAcc,
      patient: _patientCtrl.text,
      mobile: _mobileCtrl.text,
      doctor: _doctorCtrl.text,
      items: validItems,
      subTotal: _subTotalNotifier.value,
      discount: double.tryParse(_footerDiscAmtCtrl.text) ?? 0,
      grandTotal: _netTotalNotifier.value,
      taxType: _gstType == 1 ? "Gst" : "Non Gst",
    );

    final doc = await InvoicePdfGenerator.buildPdfDocument(invoice, p.companyProfile);
    if (!mounted) return;
    PrinterService.showProfessionalPreview(
      context: context,
      doc: doc,
      title: "Invoice PDF - ${_entryNo.isEmpty ? "DRAFT" : _entryNo}",
    );
  }

  void _shareInvoiceWhatsApp() async {
    final validItems = _items.where((it) => it.product.name.trim().isNotEmpty && it.qty > 0).toList();
    if (validItems.isEmpty) {
      AppDialogs.showFastDialog(
        context: context,
        title: "No Items",
        content: "Please add valid items to the sales entry before sharing via WhatsApp.",
      );
      return;
    }

    final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);
    final invoice = SaleInvoice(
      entryNo: _entryNo.isEmpty ? "DRAFT" : _entryNo,
      date: _date,
      customerAcc: _customerAcc,
      patient: _patientCtrl.text,
      mobile: _mobileCtrl.text,
      doctor: _doctorCtrl.text,
      items: validItems,
      subTotal: _subTotalNotifier.value,
      discount: double.tryParse(_footerDiscAmtCtrl.text) ?? 0,
      grandTotal: _netTotalNotifier.value,
      taxType: _gstType == 1 ? "Gst" : "Non Gst",
    );

    if (!mounted) return;
    await WhatsAppService.sendSalesInvoiceWithPdf(
      context: context,
      invoice: invoice,
      companyProfile: pharmacy.companyProfile,
    );
  }

  void _exportToExcel() async {
    if (_items.isEmpty) return;
    try {
      final p = Provider.of<PharmacyProvider>(context, listen: false);
      String? result = await FilePicker.saveFile( // v2
        dialogTitle: 'Save Sales Excel',
        fileName: 'sales_${_entryNo.replaceAll('/', '_')}.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (result != null) {
        // We'll use a generic export or just show a message for now if single export isn't ready
        // But let's try to use the provider's export if it supports filtering
        await p.exportSalesToExcel(result);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Exported successfully!")));
      }
    } catch (e) {
      _showFastDialog(title: "Export Error", content: e.toString());
    }
  }
  void _saveSale({
    bool isEdit = false,
    String? primaryAcc,
    double? primaryAmt,
    String? secondaryAcc,
    double? secondaryAmt,
  }) async {
    // 1. Hard Re-entrancy Guard (Stops duplicate saves)
    if (_isSaving || _isLoading) return;
    _isSaving = true;

    // --- MANDATORY FIELDS CHECK (Account Name, Patient Name, Doctor Name) ---
    final String chosenPrimaryAcc = (primaryAcc != null && primaryAcc.trim().isNotEmpty)
        ? primaryAcc.trim()
        : (_customerAccCtrl.text.trim().isNotEmpty
            ? _customerAccCtrl.text.trim()
            : _customerAcc.trim());
    final String chosenPatient = _patientCtrl.text.trim();
    final String chosenDoctor = _doctorCtrl.text.trim();

    if (chosenPrimaryAcc.isEmpty) {
      _isSaving = false;
      _customerAccFocus.requestFocus();
      _showFastDialog(
        title: "Validation Error",
        content: "Account Name is mandatory. Please enter Account Name before saving.",
      );
      return;
    }

    if (chosenPatient.isEmpty) {
      _isSaving = false;
      _patientFocus.requestFocus();
      _showFastDialog(
        title: "Validation Error",
        content: "Patient Name is mandatory. Please enter Patient Name before saving.",
      );
      return;
    }

    if (chosenDoctor.isEmpty) {
      _isSaving = false;
      _doctorFocus.requestFocus();
      _showFastDialog(
        title: "Validation Error",
        content: "Doctor Name is mandatory. Please enter Doctor Name before saving.",
      );
      return;
    }

    final validItems = _items.where((it) => it.product.name.trim().isNotEmpty).toList();
    if (validItems.isEmpty) {
      _isSaving = false;
      _showFastDialog(title: "No Items", content: "Please add at least one valid item before saving.");
      return;
    }

    // --- Statutory Schedule H1 / Schedule X / Narcotic Compliance Guard ---
    final regulatedItems = validItems.where((it) {
      String sched = it.product.schedule.toUpperCase();
      return sched.contains("H1") || sched.contains("X") || sched.contains("NARCOTIC");
    }).toList();

    if (regulatedItems.isNotEmpty) {
      List<String> restrictedNames = regulatedItems.map((it) => "${it.product.name} (Schedule: ${it.product.schedule})").toList();
      final complianceResult = await showDialog<ScheduleH1ComplianceResult>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => ScheduleH1ComplianceDialog(
          initialDoctorName: chosenDoctor,
          initialPatientName: chosenPatient,
          restrictedItemNames: restrictedNames,
        ),
      );

      if (complianceResult == null) {
        _isSaving = false;
        return; // User cancelled statutory compliance entry
      }

      if (complianceResult.doctorName.trim().isEmpty) {
        _isSaving = false;
        _showFastDialog(
          title: "Validation Error",
          content: "Doctor Name is mandatory before saving.",
        );
        return;
      }

      if (complianceResult.patientName.trim().isEmpty) {
        _isSaving = false;
        _showFastDialog(
          title: "Validation Error",
          content: "Patient Name is mandatory before saving.",
        );
        return;
      }

      _doctorCtrl.text = complianceResult.doctorName;
      _doctorRegNoCtrl.text = complianceResult.doctorRegNo;
      _patientCtrl.text = complianceResult.patientName;
    }

    // 1. Single O(N) pass for stock usage & pure math (no redundant UI controller writes)
    double sub = 0.0;
    for (var it in validItems) {
      _recalculateItemSilent(it, isGstMode: _gstType == 1);
      sub += it.total;
    }

    // Build combined batch usage map across ALL rows before saving
    Map<String, int> combinedBillBatchUsage = {};
    for (var it in validItems) {
      if (it.product.id.isEmpty || it.product.batch.isEmpty) continue;
      String key = "${it.product.id}|${it.product.batch.trim().toUpperCase()}";
      combinedBillBatchUsage[key] = (combinedBillBatchUsage[key] ?? 0) + it.qty;
    }

    double discAmt = double.tryParse(_footerDiscAmtCtrl.text) ?? 0.0;
    double otherAmt = double.tryParse(_otherChargeAmtCtrl.text) ?? 0.0;
    double lessCr = double.tryParse(_salesReturnCtrl.text) ?? 0.0;

    double finalVal = sub - discAmt + otherAmt - lessCr;
    double roundedNet = finalVal.roundToDouble();
    double roundOffVal = roundedNet - finalVal;

    // Update text controllers synchronously
    _subTotalCtrl.text = _fmt(sub);
    _roundOffCtrl.text = _fmt(roundOffVal);
    _netTotalCtrl.text = _fmt(roundedNet);

    _subTotalNotifier.value = sub;
    _grandTotalNotifier.value = roundedNet;
    _roundOffNotifier.value = roundOffVal;

    double finalGrandTotal = roundedNet;
    if (finalGrandTotal < 1.0) {
      _isSaving = false;
      _showFastDialog(
        title: "Invalid Amount",
        content: "The Grand Total must be at least ₹1.00. Please verify quantities and discounts before saving.",
      );
      return;
    }

    final double chosenRcvdAmt = primaryAmt != null
        ? (primaryAmt + (secondaryAmt ?? 0.0))
        : (double.tryParse(_rcvdAmtCtrl.text) ?? 0.0);

    bool isFullyPaid = chosenPrimaryAcc == "Cash" ||
        chosenPrimaryAcc == "UPI" ||
        chosenPrimaryAcc == "Card" ||
        (chosenRcvdAmt >= (finalGrandTotal - 0.05));

    final p = Provider.of<PharmacyProvider>(context, listen: false);

    // === PRE-SAVE INTEGRITY GATE ===
    List<String> validationErrors = [];
    setState(() => _errorCells.clear());

    for (int i = 0; i < _items.length; i++) {
      final it = _items[i];
      if (it.product.name.trim().isEmpty) continue; // Skip blank trailing rows

      // 1. Verify Product Name exists in Product Master
      bool isValidProduct = p.productMaster.any(
        (m) => m.name.trim().toLowerCase() == it.product.name.trim().toLowerCase()
      );
      if (!isValidProduct) {
        _errorCells.putIfAbsent(i, () => {}).add(1); // Column 1: Product Name
        validationErrors.add("Row ${i + 1}: '${it.product.name}' is not selected or fully typed from the dropdown list.");
      }

      // 2. Verify Batch Selection & Expiry Format (MM/YY)
      if (it.product.batch.trim().isEmpty) {
        _errorCells.putIfAbsent(i, () => {}).add(3); // Column 3: Batch
        validationErrors.add("Row ${i + 1}: Batch number is missing or incomplete.");
      }

      String exp = it.product.expiry.trim();
      if (exp.isEmpty || exp == "--/--" || !exp.contains('/')) {
        _errorCells.putIfAbsent(i, () => {}).add(4); // Column 4: Expiry
        validationErrors.add("Row ${i + 1}: Expiry date must follow MM/YY format (e.g., 06/28).");
      } else {
        final parts = exp.split('/');
        int? month = int.tryParse(parts[0]);
        int? year = int.tryParse(parts[1]);
        if (month == null || month < 1 || month > 12 || year == null) {
          _errorCells.putIfAbsent(i, () => {}).add(4);
          validationErrors.add("Row ${i + 1}: Invalid expiry month ($exp). Must be between 01 and 12.");
        }
      }

      // 3. Verify Quantity Constraint
      if (it.qty <= 0) {
        _errorCells.putIfAbsent(i, () => {}).add(6); // Column 6: Quantity
        validationErrors.add("Row ${i + 1}: Quantity must be greater than 0.");
      }
    }

    // If any rule fails, highlight the cells in soft red and block saving entirely
    if (validationErrors.isNotEmpty) {
      _isSaving = false;
      setState(() {});
      AppDialogs.showFastDialog(
        context: context, 
        title: "Save Blocked: Incomplete Data", 
        content: validationErrors.join("\n")
      );
      return;
    }

    if (!isEdit) {
      final totalForDupCheck = double.tryParse(_netTotalCtrl.text) ?? 0;
      bool isDuplicate = p.isDuplicateRecentEntry(
        isPurchase: false,
        currentItems: validItems,
        currentTotal: totalForDupCheck,
      );

      if (isDuplicate) {
        if (!mounted) return;
        bool confirmSave = await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 28),
                const SizedBox(width: 10),
                const Text("Duplicate Entry Warning", style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: const Text(
              "Please confirm it is not a duplicate entry.\n\nA bill with these exact items and this exact total was saved very recently.",
              style: TextStyle(fontSize: 15),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("SAVE ANYWAY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ) ?? false;

        if (!confirmSave) {
          _isSaving = false;
          return;
        }
      }
    }

    setState(() => _errorCells.clear());
    bool hasError = false;
    String validationError = "";

    // === ⚡ HIGH-SPEED VALIDATION LOOP (Fixes Analysis #5, #6) ===
    // Validate accumulated quantities against live shelf stock
    for (int i = 0; i < _items.length; i++) {
      final it = _items[i];
      if (it.product.name.trim().isEmpty) continue;

      if (it.qty <= 0) {
        _errorCells.putIfAbsent(i, () => {}).add(6);
        hasError = true;
        validationError = "Quantity for ${it.product.name} is zero. Please enter a valid quantity.";
        continue;
      }

      if (it.product.batch.trim().isEmpty) {
        _errorCells.putIfAbsent(i, () => {}).add(3);
        hasError = true;
        validationError = "One or more items are missing Batch selection.";
        continue;
      }

      // Expiry validation (kept from original)
      final parts = it.product.expiry.split(RegExp(r'[-/]'));
      if (parts.length == 2) {
        int? month = int.tryParse(parts[0].trim());
        int? year = int.tryParse(parts[1].trim());

        if (month == null || month < 1 || month > 12 || year == null) {
          _errorCells.putIfAbsent(i, () => {}).add(4);
          hasError = true;
          validationError = "Row ${i+1}: Invalid expiry month (${it.product.expiry}). Must be between 01 and 12.";
          continue;
        }
      } else {
        _errorCells.putIfAbsent(i, () => {}).add(4);
        hasError = true;
        validationError = "Row ${i+1}: Expiry must follow MM/YY format.";
        continue;
      }

      String key = "${it.product.id}|${it.product.batch.trim().toUpperCase()}";
      int totalAggregatedQty = combinedBillBatchUsage[key] ?? it.qty;
      int existingInvoiceQty = isEdit ? (_originalInvoiceBatchQtys[key] ?? 0) : 0;
      int availableLiveStock = it.product.stock + existingInvoiceQty;

      if (totalAggregatedQty > availableLiveStock) {
        _errorCells.putIfAbsent(i, () => {}).add(6);
        hasError = true;
        validationError = "Total billed quantity for '${it.product.name}' (Batch: ${it.product.batch}) is $totalAggregatedQty, which exceeds the available stock of $availableLiveStock.";
      }

      if (it.total < 0.001) {
        _errorCells.putIfAbsent(i, () => {}).add(13);
        hasError = true;
        validationError = "Row ${i+1}: Item sale value must be at least ₹0.001";
      }
    }

    if (hasError) {
      _isSaving = false;
      setState(() {});
      await _showFastDialog(title: "Validation Error", content: validationError);
      return;
    }

    // =================================================

    setState(() => _isLoading = true);

    try {
      final days = int.tryParse(_daysCtrl.text) ?? 0;
      final String finalEntryNo = isEdit ? _entryNo : "";

      final sale = SaleInvoice(
        entryNo: finalEntryNo, 
        date: _date,
        customerAcc: chosenPrimaryAcc,
        patient: chosenPatient,
        mobile: _mobileCtrl.text,
        doctor: chosenDoctor,
        doctorRegNo: _doctorRegNoCtrl.text,
        specialOrderJson: jsonEncode(_buildSpecialOrderList()),
        taxType: _gstType == 1 ? "Gst" : "Non Gst",
        days: days,
        items: validItems,
        subTotal: double.tryParse(_subTotalCtrl.text) ?? 0,
        discount: double.tryParse(_footerDiscAmtCtrl.text) ?? 0,
        discountPercent: double.tryParse(_footerDiscPctCtrl.text) ?? 0,
        roundOff: double.tryParse(_roundOffCtrl.text) ?? 0,
        grandTotal: finalGrandTotal,
        rcvdAmt: chosenRcvdAmt,
        secondaryAcc: secondaryAcc ?? "",
        secondaryAmt: secondaryAmt ?? 0.0,
        isPaid: isFullyPaid,
        agent: p.salesSessions[p.activeSessionIdx]['agent']?.toString().isNotEmpty == true 
               ? p.salesSessions[p.activeSessionIdx]['agent'].toString() 
               : "Admin",
        expectingDate: _expectingDateCtrl.text,
        specialCustomerName: _specialCustomerNameCtrl.text,
        specialCustomerPhone: _specialCustomerPhoneCtrl.text,
        salesReturn: double.tryParse(_salesReturnCtrl.text) ?? 0.0,
        orderType: _orderType,
      );

      // Patient Registration Check (Ignores defaults and whitespace)
      final String patName = _patientCtrl.text.trim();
      if (patName.isNotEmpty && patName.toUpperCase() != "P1" && patName.toUpperCase() != "CASH") {
        bool exists = p.patientMaster.any((pat) => pat.name.toLowerCase().trim() == patName.toLowerCase());
        if (!exists) {
          bool? res = await AppDialogs.showConfirmDialog(
            context: context,
            title: "New Patient Detected",
            content: "'$patName' is not in your Patient Master. Would you like to save it?",
            yesLabel: "ADD",
            noLabel: "SKIP",
          );
          if (!mounted) return;
          if (res == true) await p.addPatient(patName);
        }
      }

      // Doctor Registration Check (Ignores defaults and whitespace)
      final String docName = _doctorCtrl.text.trim();
      if (docName.isNotEmpty && docName.toUpperCase() != "D1" && docName.toUpperCase() != "SELF") {
        bool exists = p.doctorMaster.any((doc) => doc.name.toLowerCase().trim() == docName.toLowerCase());
        if (!exists) {
          bool? res = await AppDialogs.showConfirmDialog(
            context: context,
            title: "New Doctor Detected",
            content: "'$docName' is not in your Doctor Master. Would you like to save it?",
            yesLabel: "ADD",
            noLabel: "SKIP",
          );
          if (!mounted) return;
          if (res == true) await p.addDoctor(docName);
        }
      }

      await p.saveSale(sale);
      await p.clearSaleDraft();

      // Write edit history only after the database transaction succeeds
      if (isEdit && _originalLoadedInvoice != null) {
        List<Map<String, dynamic>> completeOldSnapshot = _originalLoadedInvoice!.items.map((i) => {
          'name': i.product.name,
          'batch': i.product.batch,
          'expiry': i.product.expiry,
          'qty': i.qty,
          'pack': i.product.packSize,
          'mrp': i.mrp,
          's_rate': i.sRate,
          'disc_percent': i.discPercent,
          'disc_amt': i.discAmt,
          'gst_percent': i.gstPercent,
          'total': i.total,
        }).toList();

        List<Map<String, dynamic>> completeNewSnapshot = validItems.map((i) => {
          'name': i.product.name,
          'batch': i.product.batch,
          'expiry': i.product.expiry,
          'qty': i.qty,
          'pack': i.product.packSize,
          'mrp': i.mrp,
          's_rate': i.sRate,
          'disc_percent': i.discPercent,
          'disc_amt': i.discAmt,
          'gst_percent': i.gstPercent,
          'total': i.total,
        }).toList();

        await p.logEditHistory(
          entryNo: finalEntryNo,
          oldTotal: _originalLoadedInvoice!.grandTotal,
          oldItemsJson: jsonEncode(completeOldSnapshot),
          newItemsJson: jsonEncode(completeNewSnapshot),
          reason: "Manual Edit",
        );
      }

      SystemSound.play(SystemSoundType.alert);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Entry Saved", style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.green.shade800,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 50, left: 10, right: 1000),
            duration: const Duration(seconds: 3),
          ),
        );
        _isDirty = false;
        _resetPage();
      }
    } catch (e) {
      if (mounted) {
        _showFastDialog(
            title: "Save Failed",
            content: "An error occurred while saving: $e"
        );
      }
    } finally {
      _isSaving = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }


  // --- NEW: DELETE SALE METHOD ---
  void _deleteSale() async {
    if (!_isExistingEntry) {
      _showFastDialog(title: "Invalid Operation", content: "Cannot delete a new, unsaved entry.");
      return;
    }

    final p = Provider.of<PharmacyProvider>(context, listen: false);

    // 1. SECURITY CHECK: PIN for Deleting Sales
    if (p.securityToggles['require_pin_delete_sales'] == true) {
      if (!p.isAdminSessionActive()) {
        bool isUnlocked = await PinUnlockDialog.show(
            context,
            p,
            title: "Confirm Deletion",
            message: "Enter Master Password to permanently delete Entry $_entryNo."
        );
        if (!isUnlocked) return;
        p.refreshAdminSession();
      }
    }

    // PREVIOUS DAY LOCK CHECK REMOVED AS PER USER REQUEST

    final confirmed = await _showFastDialog(
        title: "Delete Entry?",
        content: "Are you sure you want to delete Sales Entry $_entryNo? This will restore the stock and mark the entry as deleted.",
        isYesNo: true,
        initialFocusIdx: 2
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        _isExistingEntry = false;
        _originalLoadedInvoice = null;
        await p.deleteSale(_entryNo);
        p.logAudit('DELETE_SALE', 'Sales Entry $_entryNo deleted by ${_agentCtrl.text.isNotEmpty ? _agentCtrl.text : "Admin"}.', userId: _agentCtrl.text.isNotEmpty ? _agentCtrl.text : "Admin");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Entry Deleted Successfully"), backgroundColor: Colors.red)
          );
          _isDirty = false;
          await _resetPage(force: true);
        }
      } catch (e) {
        if (mounted) _showFastDialog(title: "Delete Failed", content: "Error: $e");
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _importPrescription() async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final prescriptions = provider.prescriptions.where((p) => !p.isImported).toList();

    if (prescriptions.isEmpty) {
      _showFastDialog(title: "No Prescriptions", content: "No new prescriptions available to import.");
      return;
    }

    setState(() => _isDialogOpen = true);
    final Prescription? selected = await showDialog<Prescription>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Select Prescription"),
        content: SizedBox(
          width: 500,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: prescriptions.length,
            itemBuilder: (c, i) {
              final p = prescriptions[i];
              return ListTile(
                title: Text("${p.patientName} - ${p.doctorName}"),
                subtitle: Text("Date: ${DateFormat('dd/MM/yyyy').format(p.date)} | Items: ${p.items.length}"),
                onTap: () => Navigator.pop(ctx, p),
              );
            },
          ),
        ),
      ),
    );
    setState(() => _isDialogOpen = false);

    if (selected != null) {
      _saveUndoState();
      List<String> missingItems = [];
      DateTime today = DateTime.now();

      setState(() {
        _patientCtrl.text = selected.patientName;
        _mobileCtrl.text = selected.mobile;
        _doctorCtrl.text = selected.doctorName;
        _daysCtrl.text = selected.days.toString();

        for (var pItem in selected.items) {
          if (pItem.name.isEmpty) continue;

          // Find all available batches for this product name
          final allBatches = provider.products.where((p) =>
          p.name.toLowerCase() == pItem.name.toLowerCase() &&
              p.stock > 0 &&
              !_parseExpiry(p.expiry).isBefore(today)
          ).toList();

          // Sort by expiry (FEFO)
          allBatches.sort((a, b) => _parseExpiry(a.expiry).compareTo(_parseExpiry(b.expiry)));

          if (allBatches.isEmpty) {
            missingItems.add("${pItem.name} (No Stock/Expired)");
            // Add as empty item so user knows it was there
            _items.add(SaleItem(
              product: Product(id: "", name: pItem.name),
              qty: pItem.qty.toInt(),
            ));
            continue;
          }

          double remainingQty = pItem.qty.toDouble();
          for (var batch in allBatches) {
            if (remainingQty <= 0) break;

            int stockAlreadyUsed = _getCrossRowStockUsed(batch, -1);
            int totalLoose = batch.stock;
            int trueAvailable = totalLoose - stockAlreadyUsed;
            if (trueAvailable <= 0) continue;

            double qtyToTake = remainingQty > trueAvailable ? trueAvailable.toDouble() : remainingQty;
            remainingQty -= qtyToTake;

            double ps = batch.packSize == 0 ? 1 : batch.packSize.toDouble();
            double unitMrp = batch.mrp / ps;
            double unitSRate = (batch.salePrice > 0 ? batch.salePrice : batch.mrp) / ps;

            _items.add(SaleItem(
              product: Product(
                  id: batch.id, name: batch.name, batch: batch.batch, expiry: batch.expiry,
                  packSize: batch.packSize, mrp: batch.mrp, salePrice: batch.salePrice,
                  purchaseRate: batch.purchaseRate, gstPercent: batch.gstPercent,
                  rack: batch.rack, category: batch.category, manufacturer: batch.manufacturer,
                  genericName: batch.genericName
              )..stock = totalLoose,
              qty: qtyToTake.toInt(),
              packin: batch.packSize,
              mrp: unitMrp,
              sRate: unitSRate,
              taxableSP: unitSRate,
              discPercent: 0,
              discAmt: 0,
              gstPercent: batch.gstPercent,
              total: unitSRate * qtyToTake,
            ));
          }

          if (remainingQty > 0) {
            missingItems.add("${pItem.name} (Short by ${remainingQty.toInt()})");
          }
        }
        _calculateFooter();
      });

      if (missingItems.isNotEmpty) {
        _showFastDialog(
          title: "Import Status",
          content: "The following items were not fully fulfilled from inventory:\n\n${missingItems.join('\n')}",
        );
      }
      provider.markPrescriptionImported(selected.id);
    }
  }

  void _exportPrescription() async {
    if (_items.isEmpty) {
      _showFastDialog(title: "No Items", content: "Add items to export as a prescription.");
      return;
    }

    final p = Prescription(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      patientName: _patientCtrl.text,
      doctorName: _doctorCtrl.text,
      mobile: _mobileCtrl.text,
      days: int.tryParse(_daysCtrl.text) ?? 0,
      date: _date,
      items: _items.map((it) => PrescriptionItem(name: it.product.name, qty: it.qty.toDouble())).toList(),
    );

    await Provider.of<PharmacyProvider>(context, listen: false).addPrescription(p);
    _showFastDialog(title: "Exported", content: "Prescription exported successfully!", isSuccess: true);
  }

  void _safeDeleteRow(int rowToDelete) {
    if (rowToDelete < 0 || rowToDelete >= _items.length) return;

    _saveUndoState();

    setState(() {
      final item = _items[rowToDelete];

      // Remove and dispose text controllers
      if (_gridCtrls.containsKey(item)) {
        for (var c in _gridCtrls[item]!.values) {
          c.dispose();
        }
        _gridCtrls.remove(item);
      }

      // Detach listeners and dispose focus nodes
      if (_gridFocusNodes.containsKey(item)) {
        for (var f in _gridFocusNodes[item]!.values) {
          f.unfocus();
          f.dispose();
        }
        _gridFocusNodes.remove(item);
      }

      _items.removeAt(rowToDelete);
      _errorCells.clear();
      _calculateFooter();
    });

    _moveFocus(rowToDelete, 1);
  }

  Future<void> _resetPage({bool force = false}) async {
    if (_isResetting) return;
    _isResetting = true;

    try {
      // ---> THE FIX: Protect against losing unsaved edits <---
      if (!force && _isExistingEntry && _isDirty) {
        bool? discard = await _promptDiscardChanges();
        if (discard != true) {
          _isResetting = false;
          return; // User chose to stay
        }
      }
      if (!mounted) return;

      _isExistingEntry = false;
      _originalLoadedInvoice = null;
      _isDirty = false;
      _isDeleted = false;

      final p = Provider.of<PharmacyProvider>(context, listen: false);
      p.clearSaleDraft();
      p.clearSalesSession(p.activeSessionIdx); // Clear the global RAM session
      p.saveSalesDrafts(); // Persist the cleared state so it doesn't return on restart

      _closeAllDropdowns();
      FocusScope.of(context).unfocus();
      await Future.delayed(Duration.zero);
      if (!mounted) return;

      setState(() {
        // 1. MASS DISPOSAL (Stops RAM Leaks)
        for (var m in _gridCtrls.values) { for (var c in m.values) { c.dispose(); } }
        for (var m in _gridFocusNodes.values) { for (var f in m.values) { f.dispose(); } }
        for (var c in _nextRowCtrls.values) { c.dispose(); }
        for (var f in _nextRowNodes.values) { f.dispose(); }

        _gridCtrls.clear();
        _gridFocusNodes.clear();
        _nextRowCtrls.clear();
        _nextRowNodes.clear();

        _lastSyncedProdName = "";
        _footerAlts = [];
        _activeGenericName = "";
        _productHistory = [];

        _isExistingEntry = false;
        _isDirty = false; // Reset dirty flag on new
        _isDeleted = false;
        _items.clear();
        _errorCells.clear();
        _discountInteractedRows.clear();
        _customerAcc = "Cash";
        _customerAccCtrl.text = "Cash";
        _gstType = 2;
        _orderType = 0;
        _showSpecialOrderSidebar = false;
        _isSpecialOrderMinimized = false;
        _date = DateTime.now();
        _patientCtrl.text = "P1";
        _mobileCtrl.clear();
        _doctorCtrl.text = "D1";
        _daysCtrl.text = "0";
        _specialCustomerNameCtrl.clear();
        _specialCustomerPhoneCtrl.clear();
        _specialMainCtrl.clear();
        _agentCtrl.text = "Admin";
        _subTotalCtrl.text = "0.00";
        _salesReturnCtrl.text = "0.00";
        _expectingDateCtrl.clear();
        _rcvdAmtCtrl.text = "0";
        _footerDiscPctCtrl.text = "0";
        _footerDiscAmtCtrl.text = "0.00";
        _originalInvoiceBatchQtys.clear();
        _originalLoadedInvoice = null;
        _originalItemSnapshots.clear();
        _highlightEdits = false;
        _specialOrderQtys.clear();
        _extraSpecialItems.clear();
      });

      final nextNo = await p.getNextSaleEntryNo();
      if (mounted) {
        setState(() {
          _entryNo = nextNo;
          _calculateFooter();
        });
        _moveFocus(0, 1);
      }
    } finally {
      _isResetting = false;
    }
  }

  bool _hasValidItems() {
    if (_isExistingEntry) return _hasMeaningfulEdits();

    for (int i = 0; i < _items.length; i++) {
      final it = _items[i];
      final prodName = it.product.name.trim();
      int itemQty = it.qty;
      final ctrlText = _getGridCtrl(i, 7).text.trim();
      if (ctrlText.isNotEmpty) {
        final parsed = int.tryParse(ctrlText) ?? 0;
        if (parsed > 0) itemQty = parsed;
      }

      if (prodName.isNotEmpty && (itemQty > 0 || it.fQty > 0)) {
        return true;
      }
    }

    final newProdName = _getGridCtrl(_items.length, 2).text.trim();
    final newQtyText = _getGridCtrl(_items.length, 7).text.trim();
    final newQty = int.tryParse(newQtyText) ?? 0;
    if (newProdName.isNotEmpty && newQty > 0) {
      return true;
    }

    return false;
  }

  void _triggerAutoSaveDraft() async {
    if (_isExistingEntry) return;

    final p = Provider.of<PharmacyProvider>(context, listen: false);

    if (!_hasValidItems()) {
      p.clearSaleDraft();
      p.clearSalesSession(p.activeSessionIdx);
      await p.saveSalesDrafts();
      return;
    }

    _syncToGlobalSession();
    await p.saveSalesDrafts();
  }

  @override
  Widget build(BuildContext context) {
    // SYNC GLOBAL SESSION (Only if index actually changed to prevent loops)
    return Selector<PharmacyProvider, int>(
      selector: (_, p) => p.activeSessionIdx,
      builder: (context, sessionIdx, _) {
        final pharma = Provider.of<PharmacyProvider>(context, listen: false);

        if (!_isExistingEntry && _lastSyncedSessionIdx != sessionIdx) {
           _lastSyncedSessionIdx = sessionIdx;
           // Use a microtask to avoid modifying state during build
           Future.delayed(Duration.zero, () {
             if (mounted) _loadGlobalSession(pharma.salesSessions[sessionIdx]);
           });
        }

        return Focus(
          focusNode: _rootFocus,
          onKeyEvent: (node, event) => _handleGlobalKeys(event) ? KeyEventResult.handled : KeyEventResult.ignored,
          child: FocusScope(
          child: Scaffold(
            backgroundColor: AppColors.of(context).background,
            body: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  children: [
                    // Top Section: Toolbar, Header & Right Side Order Box / Notification Hub
                    _buildTopSection(),

                    // === THE GRID ===
                    Expanded(child: LayoutBuilder(builder: (ctx, con) {
                        double fixedTotal = 0;
                        _colWidths.forEach((k, v) { if (k != 2) fixedTotal += v; });
                        double productWidth = 280;
                        if (con.maxWidth > (fixedTotal + 280)) {
                          productWidth = con.maxWidth - fixedTotal;
                        }

                        _colWidths[2] = productWidth;

                        final double finalTw = fixedTotal + _colWidths[2]!;
                        return Scrollbar(
                            controller: _gridScrollCtrl, thumbVisibility: true,
                            child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal, controller: _gridScrollCtrl,
                                child: SizedBox(
                                    width: finalTw, height: con.maxHeight,
                                    child: Column(children: [
                                      _buildGridHeader(),
                                      Expanded(child: _buildGrid()),
                                      _buildTotalsRow(finalTw),
                                    ])
                                )
                            )
                        );
                      }),
                    ),
                    _buildFooter(),
                    _buildShortcutLegend(),
                  ],
                ),
                Positioned.fill(child: _buildOverlay()),
                _buildAgentWatermark(),
                if (_showSpecialOrderSidebar && !_isSpecialOrderMinimized) _buildSpecialOrderPanel(),
                if (_isLoading) Container(color: Colors.black12, child: const Center(child: CircularProgressIndicator())),
              ],
            ),
          ),
        ),
      );
      },
    );
  }

  // ---> NEW: SMART EDIT TRACKING <---

  bool _hasMeaningfulEdits() {
    if (!_isExistingEntry || _originalLoadedInvoice == null) return false;

    if (_patientCtrl.text.trim().toUpperCase() != _originalLoadedInvoice!.patient.trim().toUpperCase()) return true;
    if (_doctorCtrl.text.trim().toUpperCase() != _originalLoadedInvoice!.doctor.trim().toUpperCase()) return true;

    double currentDiscAmt = double.tryParse(_footerDiscAmtCtrl.text) ?? 0.0;
    if ((currentDiscAmt - _originalLoadedInvoice!.discount).abs() > 0.01) return true;

    final validItems = _items.where((it) => it.product.name.trim().isNotEmpty).toList();
    if (validItems.length != _originalItemSnapshots.length) return true;

    for (var it in validItems) {
      if (!_originalItemSnapshots.containsKey(it)) return true;
      final snap = _originalItemSnapshots[it]!;
      if (it.qty != snap['qty']) return true;
      if (it.product.batch.trim().toUpperCase() != snap['batch']) return true;
      if ((it.discPercent - (snap['discPercent'] as double)).abs() > 0.01) return true;
      if (it.product.name.trim().toUpperCase() != snap['name']) return true;
    }

    return false;
  }

  bool _isPatientModified() {
    if (!_highlightEdits || _originalLoadedInvoice == null) return false;
    return _patientCtrl.text.trim().toUpperCase() != _originalLoadedInvoice!.patient.trim().toUpperCase();
  }

  bool _isDoctorModified() {
    if (!_highlightEdits || _originalLoadedInvoice == null) return false;
    return _doctorCtrl.text.trim().toUpperCase() != _originalLoadedInvoice!.doctor.trim().toUpperCase();
  }

  Future<bool?> _promptDiscardChanges() async {
    if (!_isExistingEntry) {
      if (!_hasValidItems()) return true;
    } else if (!_hasMeaningfulEdits()) {
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
          "You have made changes to this saved invoice.\nIf you leave now, your edits will be lost.\n\nDo you want to discard your changes?",
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              _focusNotifier.value = null;
              setState(() => _highlightEdits = true);
              Navigator.pop(ctx, false);
            },
            child: const Text("HIGHLIGHT EDITS", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("DISCARD EDITS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildTopToolbar() {
    bool canSave = !_isExistingEntry && !_isDeleted;
    bool canEdit = _isExistingEntry && !_isDeleted;
    bool canDelete = _isExistingEntry && !_isDeleted;

    final c = AppColors.of(context);
    return Container(
      height: 52,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(bottom: BorderSide(color: c.border, width: 1)),
      ),
      child: Row(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "SALES ENTRY",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: c.primaryText),
              ),
              const SizedBox(width: 8),
              Text("Acc.", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.secondaryText)),
              const SizedBox(width: 4),
              _buildCustomerField(),
              if (_isDeleted)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                  child: const Text("DELETED", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
            ],
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _topActionBtn(Icons.add_box_rounded, "New", const Color(0xFF2196F3), onTap: _resetPage),
                    _topActionBtn(
                      Icons.check_circle_rounded,
                      "Save",
                      canSave ? const Color(0xFF4CAF50) : Colors.grey.shade400,
                      textColor: canSave ? null : Colors.grey.shade400,
                      onTap: canSave ? () => _saveSale(isEdit: false) : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Add at least one product item to save sale."), duration: Duration(seconds: 2)),
                        );
                      },
                    ),
                    _topActionBtn(
                      Icons.edit_document,
                      "Edit",
                      (canEdit && _isDirty) ? Colors.orange : Colors.grey.shade400,
                      textColor: (canEdit && _isDirty) ? null : Colors.grey.shade400,
                      onTap: (canEdit && _isDirty) ? _editSale : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(_isExistingEntry ? "No changes made to edit." : "Select an existing sale to edit."), duration: const Duration(seconds: 2)),
                        );
                      },
                    ),
                    _topActionBtn(Icons.search_rounded, "Find", const Color(0xFF3F51B5), onTap: _showFindDialog),
                    _topActionBtn(Icons.print_rounded, "Print", const Color(0xFF607D8B), onTap: _printSale),
                    _topActionBtn(Icons.info_outline_rounded, "Info & Guide", Colors.indigo, onTap: _showSalesManualAndLegendDialog),
                    _topActionBtn(
                      Icons.delete_forever_rounded,
                      "Del",
                      canDelete ? const Color(0xFFD32F2F) : Colors.grey.shade400,
                      textColor: canDelete ? null : Colors.grey.shade400,
                      onTap: canDelete ? _deleteSale : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Load an existing sale invoice first to delete."), duration: Duration(seconds: 2)),
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.blueGrey),
                      tooltip: "More Options",
                      onSelected: (val) {
                        if (val == 'pdf') _exportToPdf();
                        if (val == 'whatsapp') _shareInvoiceWhatsApp();
                        if (val == 'export') _exportToExcel();
                        if (val == 'import') {}
                        if (val == 'paste') {}
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'pdf',
                          child: Row(
                            children: [
                              Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFE53935), size: 20),
                              SizedBox(width: 10),
                              Text("Export PDF", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'whatsapp',
                          child: Row(
                            children: [
                              _buildWhatsAppLogo(size: 20),
                              const SizedBox(width: 10),
                              const Text("Share WhatsApp", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'export',
                          child: Row(
                            children: [
                              Icon(Icons.file_download_outlined, color: Color(0xFF2E7D32), size: 20),
                              SizedBox(width: 10),
                              Text("Export to Excel", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'import',
                          child: Row(
                            children: [
                              Icon(Icons.file_upload_outlined, color: Colors.blueGrey, size: 20),
                              SizedBox(width: 10),
                              Text("Import Excel", style: TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'paste',
                          child: Row(
                            children: [
                              Icon(Icons.paste_rounded, color: Colors.blueGrey, size: 20),
                              SizedBox(width: 10),
                              Text("Paste Clipboard", style: TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }





  Widget _buildTopSection() {
    final pharma = Provider.of<PharmacyProvider>(context);
    if (pharma.prescriptions.any((pr) => !pr.isImported) && !_activeNotificationTab.contains("mobile")) {
      // Logic to auto-set if needed, but for now we'll stick to provider source
    }
    bool showMobileBadge = pharma.prescriptions.any((pr) => !pr.isImported) && _hasNewMobileOrder;

    return Container(
      height: 156,
      color: Colors.white,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // LEFT SIDE: Toolbar & Billing Inputs (Responsive)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopToolbar(),
                Expanded(child: _buildHeader()),
              ],
            ),
          ),

          const SizedBox(width: 1, child: VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE0E0E0))),

          // MIDDLE: The 4 Vertical Notification Buttons (Yellow Box Column)
          Container(
            width: 135,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey, width: 0.5)
              )
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _hubToggleBtn(id: "mobile", icon: Icons.phone_android_rounded, label: "Mobile", count: showMobileBadge ? 1 : 0, color: Colors.blueGrey),
                _hubToggleBtn(id: "urgent", icon: Icons.access_alarm_rounded, label: "Urgent", count: _urgentOrders.length, color: Colors.blueGrey, badgeColor: Colors.orange.shade700),
                _hubToggleBtn(id: "stock", icon: Icons.inventory_2_rounded, label: "Low Stock", count: _lowStockOrders.length, color: Colors.blueGrey, badgeColor: Colors.blue.shade700),
                _hubToggleBtn(id: "special", icon: Icons.shopping_cart_rounded, label: "Special", count: _specialOrdersList.length, color: Colors.blueGrey),
              ],
            ),
          ),

          // RIGHT SIDE: The Notification Hub
          Container(
            width: 420,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                left: BorderSide(color: Colors.blueGrey.shade200),
                bottom: const BorderSide(color: Colors.grey, width: 0.5)
              ),
            ),
            child: _buildOverlayContent(),
          ),
        ],
      ),
    );
  }

  Future<void> _loadNotificationData() async {
    if (!mounted) return;
    setState(() => _isLoadingNotifications = true);
    try {
      final p = Provider.of<PharmacyProvider>(context, listen: false);
      final reorderList = await p.getReorderSuggestions();

      final rawSpecial = await p.fetchSpecialOrders();
      List<Map<String, dynamic>> specialItems = [];
      for (var s in rawSpecial) {
        try {
          List<dynamic> list = jsonDecode(s['special_order_json']);
          for (var item in list) {
            specialItems.add({
              'entry_no': s['entry_no'],
              'name': item['name'] ?? 'Product',
              'qty': item['qty'] ?? 1,
              'stock': item['stock'] ?? 0,
              'patient': (s['special_customer_name']?.toString().isNotEmpty ?? false)
                  ? s['special_customer_name']
                  : s['patient'] ?? '',
              'ordered': false,
              'pending': true,
            });
          }
        } catch (_) {}
      }

      List<Map<String, dynamic>> urgent = [];
      List<Map<String, dynamic>> lowStock = [];

      for (var item in reorderList) {
        final String name = item['product_name'] ?? item['name'] ?? 'Product';
        final int currentStock = (item['current_stock'] as num?)?.toInt() ?? 0;
        final int reorderLevel = (item['reorder_level'] as num?)?.toInt() ?? 10;
        final int suggestedQty = (item['suggested_qty'] as num?)?.toInt() ?? 10;

        final mapObj = {
          'id': item['id'],
          'name': name,
          'qty': suggestedQty > 0 ? suggestedQty : (reorderLevel - currentStock > 0 ? reorderLevel - currentStock : 10),
          'stock': currentStock,
          'reorder_level': reorderLevel,
          'ordered': false,
          'pending': currentStock <= reorderLevel,
        };

        if (currentStock <= reorderLevel) {
          lowStock.add(mapObj);
        }
        urgent.add(mapObj);
      }

      if (mounted) {
        setState(() {
          _urgentOrders = urgent;
          _lowStockOrders = lowStock;
          _specialOrdersList = specialItems;
          _isLoadingNotifications = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading notification data: $e");
      if (mounted) setState(() => _isLoadingNotifications = false);
    }
  }

  Widget _hubToggleBtn({required String id, required IconData icon, required String label, required int count, required Color color, Color? badgeColor}) {
    bool isSel = _activeNotificationTab == id;
    return InkWell(
      onTap: () {
        setState(() {
          if (_activeNotificationTab == id) {
            _activeNotificationTab = "none";
          } else {
            _activeNotificationTab = id;
            _alertPage = 1;
            if (id == "mobile") _hasNewMobileOrder = false;
            if (id == "special") {
              _showSpecialOrderSidebar = true;
              _isSpecialOrderMinimized = false;
            }
          }
        });
        _loadNotificationData();
      },
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: isSel ? Colors.blue.shade50 : Colors.transparent,
          border: Border.all(color: isSel ? Colors.blue : Colors.transparent),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            const SizedBox(width: 6),
            Icon(icon, size: 15, color: isSel ? Colors.blue : color),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSel ? Colors.blue : Colors.black87))),
            if (count > 0)
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: badgeColor ?? Colors.red, borderRadius: BorderRadius.circular(10)),
                child: Text(count.toString(), style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPagination(int totalItems) {
    int totalPages = (totalItems / 10).ceil();
    if (totalPages <= 1) return const SizedBox();

    List<Widget> pages = [];
    for (int i = 1; i <= totalPages; i++) {
      bool isSel = _alertPage == i;
      pages.add(InkWell(
        onTap: () => setState(() => _alertPage = i),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isSel ? Colors.blue.shade700 : Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: isSel ? Colors.blue.shade800 : Colors.grey.shade300),
          ),
          child: Text(i.toString(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSel ? Colors.white : Colors.blueGrey)),
        )
      ));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: pages);
  }

  Widget _buildOverlayContent() {
    List<Map<String, dynamic>> currentData = [];
    if (_activeNotificationTab == "urgent") {
      currentData = _urgentOrders;
    } else if (_activeNotificationTab == "stock") {
      currentData = _lowStockOrders;
    } else if (_activeNotificationTab == "special") {
      currentData = _specialOrdersList;
    }

    if (_orderFilter == "ORDERED") {
      currentData = currentData.where((i) => i['ordered'] == true).toList();
    } else if (_orderFilter == "PENDING") {
      currentData = currentData.where((i) => i['pending'] == true || i['ordered'] != true).toList();
    }

    int totalAlertItems = currentData.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: Colors.blueGrey.shade50,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200))
          ),
          child: Row(
            children: [
              Text(
                  _activeNotificationTab == "none" ? "Notifications Center" :
                  _activeNotificationTab == "mobile" ? "Incoming Mobile Orders" :
                  _activeNotificationTab == "urgent" ? "Urgent Order Book" :
                  _activeNotificationTab == "special" ? "Special Orders List" : "Low Stock Alerts",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155))
              ),
              const Spacer(),

              if (_activeNotificationTab != "none") ...[
                _buildPagination(totalAlertItems),
                const SizedBox(width: 12),
              ],

              if (_activeNotificationTab == "none") ...[
                _buildFilterOption("ORDERED"),
                const SizedBox(width: 8),
                _buildFilterOption("PENDING"),
                const SizedBox(width: 8),
              ],
              if (_activeNotificationTab != "none")
                InkWell(
                  onTap: () => setState(() => _activeNotificationTab = "none"),
                  child: const Icon(Icons.close, size: 18, color: Colors.red),
                )
            ],
          ),
        ),
        Expanded(
          child: _activeNotificationTab == "none"
              ? const Center(child: Text("Select a tab on the left to view data.", style: TextStyle(color: Colors.grey, fontSize: 12)))
              : _buildAlertList(_activeNotificationTab, currentData),
        ),
      ],
    );
  }

  Widget _buildFilterOption(String label) {
    bool isSelected = _orderFilter == label;
    return InkWell(
      onTap: () => setState(() => _orderFilter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF334155) : Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isSelected ? const Color(0xFF334155) : Colors.grey.shade400),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : const Color(0xFF334155),
          ),
        ),
      ),
    );
  }

  Widget _buildAlertList(String type, List<Map<String, dynamic>> currentData) {
    if (_isLoadingNotifications) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (currentData.isEmpty) {
      return Center(
        child: Text(
          "No ${type.toUpperCase()} items found.",
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      );
    }

    int startIdx = (_alertPage - 1) * 10;
    int endIdx = startIdx + 10;
    if (endIdx > currentData.length) endIdx = currentData.length;
    if (startIdx >= currentData.length) {
      startIdx = 0;
      endIdx = currentData.length < 10 ? currentData.length : 10;
    }

    List<Map<String, dynamic>> pageData = currentData.sublist(startIdx, endIdx);

    return Column(
      children: [
        // List Header
        Container(
          height: 24,
          color: Colors.grey.shade100,
          child: Row(
            children: [
              Container(width: 30, alignment: Alignment.center, child: const Text("SL", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey))),
              const Expanded(child: Padding(padding: EdgeInsets.only(left: 8), child: Text("PRODUCT", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey)))),
              Container(width: 40, alignment: Alignment.center, child: const Text("QTY", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey))),
              Container(width: 55, alignment: Alignment.center, child: const Text("ORDERED", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey))),
              Container(width: 55, alignment: Alignment.center, child: const Text("PENDING", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey))),
            ],
          ),
        ),
        // List Body
        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            thickness: 4,
            child: ListView.builder(
              itemCount: pageData.length,
              padding: EdgeInsets.zero,
              itemBuilder: (ctx, i) {
                final item = pageData[i];
                final actualIdx = startIdx + i;

                void toggleOrdered() {
                  setState(() {
                    item['ordered'] = !(item['ordered'] ?? false);
                    if (item['ordered'] == true) item['pending'] = false;
                  });
                }

                void togglePending() {
                  setState(() {
                    item['pending'] = !(item['pending'] ?? false);
                    if (item['pending'] == true) item['ordered'] = false;
                  });
                }

                final int stockQty = (item['stock'] as num?)?.toInt() ?? 0;

                return InkWell(
                  onTap: toggleOrdered,
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                    child: Row(
                      children: [
                        // Serial Number Box
                        Container(
                          width: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade100))),
                          child: Text("${actualIdx + 1}", style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                        ),
                        // Product Name & Stock Quantity Below
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['name'] ?? '',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  "Stock Qty: $stockQty",
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w600,
                                    color: stockQty <= 0 ? Colors.red : Colors.blueGrey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Qty
                        Container(
                          width: 40,
                          alignment: Alignment.center,
                          child: Text(
                            item['qty'].toString(),
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue),
                          ),
                        ),
                        // Ordered Checkbox
                        SizedBox(
                          width: 55,
                          child: Center(
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: Icon(
                                (item['ordered'] ?? false) ? Icons.check_box : Icons.check_box_outline_blank,
                                size: 16,
                                color: (item['ordered'] ?? false) ? Colors.blue : Colors.grey,
                              ),
                              onPressed: toggleOrdered,
                            ),
                          ),
                        ),
                        // Pending Checkbox
                        SizedBox(
                          width: 55,
                          child: Center(
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: Icon(
                                (item['pending'] ?? false) ? Icons.check_box : Icons.check_box_outline_blank,
                                size: 16,
                                color: (item['pending'] ?? false) ? Colors.blue : Colors.grey,
                              ),
                              onPressed: togglePending,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }



  void _showSalesManualAndLegendDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.blue.shade100, shape: BoxShape.circle),
              child: const Icon(Icons.info_outline_rounded, color: Colors.blue, size: 24),
            ),
            const SizedBox(width: 12),
            const Text("ℹ️ Sales Indicator Legend & Calculation Manual", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("COLOR INDICATORS LEGEND", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey, letterSpacing: 1.2)),
                const SizedBox(height: 10),
                _legendTile(Colors.amber.shade100, Colors.orange.shade900, "Orange / Amber Text", "Low Margin Alert (< 24.9% pure profit margin)"),
                _legendTile(Colors.red.shade100, Colors.red.shade900, "Red Highlight", "Expired Batch or Render/Validation Warning"),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                const Text("CALCULATION FORMULAS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey, letterSpacing: 1.2)),
                const SizedBox(height: 10),
                _formulaTile("Retail Selling Price (S.Rate)", "Base Price or (MRP - Special Discount)"),
                _formulaTile("Line Total Amount", "Qty × Selling Rate - Item Discount + Tax"),
                _formulaTile("Retail Profit Margin %", "((MRP - Purchase Rate) / Purchase Rate) × 100"),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CLOSE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _legendTile(Color bg, Color fg, String title, String desc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
      child: Row(
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: fg, fontSize: 12)),
          const SizedBox(width: 12),
          Expanded(child: Text(desc, style: const TextStyle(fontSize: 11, color: Colors.black87))),
        ],
      ),
    );
  }

  Widget _formulaTile(String title, String formula) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
          const SizedBox(height: 4),
          SelectableText(formula, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace', color: Colors.blue.shade900)),
        ],
      ),
    );
  }

  void _showSaleItemMathBreakdown(SaleItem item) {
    double mrp = item.mrp;
    double sRate = item.sRate;
    double discPct = item.discPercent;
    double discAmt = item.discAmt;
    double netAmt = (sRate * item.qty) - discAmt;
    double gstPct = item.gstPercent;
    double gstAmt = item.gstAmt;
    double totalAmt = item.total;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.teal.shade100, shape: BoxShape.circle),
              child: const Icon(Icons.calculate_rounded, color: Colors.teal, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text("Retail Sale Breakdown: ${item.product.name}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _mathRow("Maximum Retail Price (MRP)", "₹${mrp.toStringAsFixed(2)}", isBold: true),
              _mathRow("Selling Rate (S.Rate)", "₹${sRate.toStringAsFixed(2)}", isBold: true, color: Colors.blue.shade900),
              _mathRow("- Discount ($discPct%)", "-₹${discAmt.toStringAsFixed(2)}", color: Colors.red.shade700),
              const Divider(),
              _mathRow("Net Amount (before tax)", "₹${netAmt.toStringAsFixed(2)}"),
              _mathRow("+ GST Tax ($gstPct%)", "+₹${gstAmt.toStringAsFixed(2)}", color: Colors.teal.shade800),
              const Divider(),
              _mathRow("Line Total Amount", "₹${totalAmt.toStringAsFixed(2)}", isBold: true, color: Colors.teal.shade900),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CLOSE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _mathRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 12, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color ?? Colors.black87)),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: isBold ? FontWeight.bold : FontWeight.w600, color: color ?? Colors.black87)),
        ],
      ),
    );
  }

  Widget _entryNavBtn(String txt, {VoidCallback? onTap}) => InkWell(
    onTap: onTap,
    child: Container(
      width: 22, height: 26, alignment: Alignment.center,
      decoration: BoxDecoration(color: Colors.grey.shade200, border: Border.all(color: Colors.grey.shade400)),
      child: Text(txt, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    ),
  );

  Widget _topActionBtn(dynamic icon, String label, Color color, {Color? textColor, VoidCallback? onTap}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 5),
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon is IconData)
                Icon(icon, size: 28, color: color)
              else if (icon is Widget)
                SizedBox(width: 28, height: 28, child: icon),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor ?? Colors.black87),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildWhatsAppLogo({double size = 28}) {
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

  void _triggerAgentWatermark(String agent) {
    _watermarkTimer?.cancel();
    String displayName = agent;
    if (displayName.isEmpty) {
      final p = Provider.of<PharmacyProvider>(context, listen: false);
      displayName = "W${p.activeSessionIdx + 1}";
    }
    setState(() {
      _watermarkAgent = displayName;
      _showAgentWatermark = true;
    });
    _watermarkTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showAgentWatermark = false);
    });
  }

  Widget _buildAgentWatermark() {
    if (!_showAgentWatermark) return const SizedBox.shrink();
    return IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutBack,
          builder: (context, value, child) {
            return Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.5 + (value * 0.5),
                child: child,
              ),
            );
          },
          child: Text(
            _watermarkAgent.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 160,
              fontWeight: FontWeight.w500,
              letterSpacing: 10,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..color = Colors.white.withValues(alpha: 0.8),
              shadows: const [
                Shadow(blurRadius: 30, color: Colors.black12, offset: Offset(0, 10))
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAgentField() {
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);
    final agentList = pharma.staffNames.isNotEmpty ? pharma.staffNames : _agents;
    return Container(
      width: 100, height: 28,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: RawAutocomplete<String>(
        textEditingController: _agentCtrl,
        focusNode: _agentFocus,
        optionsBuilder: (TextEditingValue textEditingValue) {
          if (textEditingValue.text.isEmpty) return agentList;
          return agentList.where((o) => o.toLowerCase().contains(textEditingValue.text.toLowerCase()));
        },
        onSelected: (String selection) {
          setState(() {
            _selectedAgent = selection;
            _agentCtrl.text = selection;
            _syncToGlobalSession(notify: true);
          });
          _triggerAgentWatermark(selection);
          // Jump to table last item name field
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _moveFocus(_items.length, 1);
          });
        },
        fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            onEditingComplete: onEditingComplete,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            decoration: const InputDecoration(
              isDense: true, border: InputBorder.none,
              contentPadding: EdgeInsets.fromLTRB(10, 6, 10, 8),
              hintText: "Agent",
              hintStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.normal),
              suffixIcon: Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey),
              suffixIconConstraints: BoxConstraints(minWidth: 30, minHeight: 28),
            ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              child: Container(
                width: 100,
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300)),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (BuildContext context, int index) {
                    final String option = options.elementAt(index);
                    return InkWell(
                      onTap: () => onSelected(option),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Text(option, style: const TextStyle(color: Colors.black, fontSize: 11)),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _loadGlobalSession(Map<String, dynamic> s) {
    _items.clear();
    _gridCtrls.clear();
    _gridFocusNodes.clear();
    _isExistingEntry = false;
    _isDeleted = false;
    _items.addAll(List<SaleItem>.from(s['items']));
    _selectedAgent = s['agent'];
    _agentCtrl.text = _selectedAgent;
    _triggerAgentWatermark(_selectedAgent);
    _customerAcc = s['customerAcc'];
    _customerAccCtrl.text = _customerAcc;
    _patientCtrl.text = s['patient'];
    _mobileCtrl.text = s['mobile'];
    _doctorCtrl.text = s['doctor'];
    _gstType = s['taxType'];
    _orderType = s['orderType'] ?? 0;
    _calculateFooter();

    // RESTORE FOCUS
    int r = s['focusRow'] ?? _items.length;
    int c = s['focusCol'] ?? 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _moveFocus(r, c);
    });
  }

  void _syncToGlobalSession({int? index, bool notify = false}) {
    if (_isExistingEntry) return;
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);
    int targetIdx = index ?? pharma.activeSessionIdx;

    // ---> THE FIX: Read the Agent directly from the global system so it doesn't get erased! <---
    String currentGlobalAgent = pharma.salesSessions[targetIdx]['agent']?.toString() ?? "";

    pharma.updateSalesSession(targetIdx, {
      'items': List<SaleItem>.from(_items),
      'agent': currentGlobalAgent, 
      'customerAcc': _customerAcc,
      'patient': _patientCtrl.text,
      'mobile': _mobileCtrl.text,
      'doctor': _doctorCtrl.text,
      'taxType': _gstType,
      'orderType': _orderType,
      'focusRow': _focusedRowIndex,
      'focusCol': _focusedColIndex,
    }, notify: notify);
  }

  void _onProviderChanged() {
    if (!mounted || _isResetting) return;
    final p = Provider.of<PharmacyProvider>(context, listen: false);

    bool yearChanged = p.selectedFinancialYear != _lastYear;

    if (yearChanged) {
      _lastYear = p.selectedFinancialYear;
      if (!_isExistingEntry || (_originalLoadedInvoice != null && _originalLoadedInvoice!.financialYear != _lastYear)) {
        _resetPage();
        return;
      }
    }

    if (_isExistingEntry) {
      if (_originalLoadedInvoice != null && !p.hasSalesInvoice(_originalLoadedInvoice!.entryNo)) {
        _resetPage();
        return;
      }
    } else if (yearChanged) {
      // Only query SQLite if the financial year actually changed, NOT on every keystroke
      Future.microtask(() async {
        String next = await p.getNextSaleEntryNo();
        if (_entryNo != next && mounted) {
          setState(() {
            _entryNo = next;
          });
        }
      });
    }

    // ---> ENTERPRISE FIX: WORKSPACE SHIELD <---
    // Sync current session with workspace selection, but block it if dirty edits exist!
    if (p.activeSessionIdx != _lastSyncedSessionIdx) {
      if (_isExistingEntry && _isDirty) {
         // REVERT the provider index back because the user is trapped by unsaved edits!
         WidgetsBinding.instance.addPostFrameCallback((_) {
            p.setSalesSession(_lastSyncedSessionIdx); // Force the UI back to the current workspace
            _showFastDialog(
              title: "Workspace Locked", 
              content: "You have unsaved edits on an existing invoice.\n\nPlease 'Save' or press 'F2' to discard them before switching to a different billing workspace."
            );
         });
         return;
      }

      if (_lastSyncedSessionIdx != -1 && !_isExistingEntry) {
        _syncToGlobalSession(index: _lastSyncedSessionIdx, notify: false);
      }
      _switchSession();
    }
  }

  void _switchSession() {
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);
    final session = pharma.salesSessions[pharma.activeSessionIdx];
    setState(() {
      _loadGlobalSession(session);
      _lastSyncedSessionIdx = pharma.activeSessionIdx;
    });
  }


  Widget _buildCustomerField() {
    final provider = Provider.of<PharmacyProvider>(context);

    // Dynamic Styling based on stored Account colors
    Color baseColor = const Color(0xFF94A3B8); // Default Slate

    // Find the matching account object to get its assigned color
    final String currentAccName = _customerAcc.toUpperCase().trim();
    try {
      final account = provider.accountMaster.firstWhere(
        (a) => a.name.toUpperCase().trim() == currentAccName,
      );
      baseColor = Color(int.parse(account.color));
    } catch (_) {
      // Fallback logic for common legacy names if not found in master
      if (currentAccName == "CASH") {
        baseColor = const Color(0xFF4CAF50);
      } else if (currentAccName == "UPI") baseColor = const Color(0xFF2196F3);
      else if (currentAccName == "NOT RECIEVED" || currentAccName == "NOT RECEIVED") baseColor = const Color(0xFFEF5350);
      else if (currentAccName == "PREVIOUS DAY") baseColor = const Color(0xFFFBC02D);
    }

    bool isEmptyErr = _customerAccCtrl.text.trim().isEmpty && _customerAcc.trim().isEmpty;
    final Color bgColor = isEmptyErr ? Colors.red.shade50 : baseColor.withValues(alpha: 0.1);
    final Color borderColor = isEmptyErr ? Colors.red.shade600 : baseColor;
    final Color textColor = isEmptyErr ? Colors.red.shade900 : baseColor.withValues(alpha: 0.9); // Slightly darker for readability

    return Container(
      width: 140,
      height: 32,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: RawAutocomplete<String>(
        textEditingController: _customerAccCtrl,
        focusNode: _customerAccFocus,
        optionsBuilder: (TextEditingValue textEditingValue) {
          final query = textEditingValue.text.trim().toLowerCase();
          
          // Always return accounts so clicking the box shows the list
          if (query.isEmpty) {
            return provider.accounts;
          }

          return provider.accounts.where((acc) => acc.toLowerCase().contains(query));
        },
        onSelected: (String selection) {
          setState(() {
            _customerAcc = selection;
            _customerAccCtrl.text = selection;
            _markDirty();
            _syncToGlobalSession(notify: true);
          });
          _moveFocus(-1, 0); // Start at Entry No or Patient
        },
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            onSubmitted: (val) => onFieldSubmitted(),
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              border: InputBorder.none,
              suffixIcon: GestureDetector(
                onTap: () {
                  // Trigger dropdown by clearing and focusing
                  _customerAccCtrl.clear();
                  _customerAccFocus.requestFocus();
                  setState(() => _customerAcc = "");
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(Icons.arrow_drop_down, color: borderColor, size: 18),
                ),
              ),
              suffixIconConstraints: const BoxConstraints(minWidth: 24, minHeight: 20),
            ),
            onChanged: (val) {
              setState(() {
                _customerAcc = val;
                _markDirty();
              });
            },
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 160,
                constraints: const BoxConstraints(maxHeight: 250),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options.elementAt(index);
                    final highlightedIndex = AutocompleteHighlightedOption.of(context);
                    final bool isHighlighted = highlightedIndex == index;

                    return InkWell(
                      onTap: () => onSelected(option),
                      child: Container(
                        color: isHighlighted ? Colors.blue.shade50 : null,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Text(
                              option,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isHighlighted ? FontWeight.w900 : FontWeight.bold,
                                color: isHighlighted ? Colors.blue.shade900 : const Color(0xFF1E293B)
                              ),
                            ),
                            if (isHighlighted) ...[
                              const Spacer(),
                              const Icon(Icons.keyboard_return, size: 14, color: Colors.blue),
                            ]
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
            // ROW 1: Entry No, Patient, Mob, Days
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 160,
                    child: _headerColumn("Entry No:", Row(
                      children: [
                        _entryNavBtn("<", onTap: () => _navigateEntry('prev')),
                        Container(
                          width: 70, height: 26,
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.grey.shade400)
                          ),
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
                  ),
                  const SizedBox(width: 12),

                  _headerColumn("Patient", _buildPatientAutocomplete()),
                  const SizedBox(width: 12),
                  _headerColumn("Mob", _headerInp(1, width: 90, height: 26, onSubmitted: (_) => _moveFocus(-1, 2))),
                  const SizedBox(width: 12),
                  _headerColumn("Days", _headerInp(3, width: 35, height: 26, onSubmitted: (_) => _moveFocus(_items.length, 1))),
                  const SizedBox(width: 16),
                  _topActionBtn(Icons.biotech_rounded, "Generic (F3)", const Color(0xFF00897B), onTap: _openGenericSearchDialog),
                  const SizedBox(width: 12),
                  _headerColumn("TAX TYPE", Row(children: [_radio("Gst", 1), _radio("No", 2)]), align: CrossAxisAlignment.center),
                ],
              ),
            ),

            const SizedBox(height: 4),

            // ROW 2: Date & Time, Doctor, Import & Export, ORDER
            LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Date & Time Separated
                            SizedBox(
                              width: 160,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _headerColumn("Date", Container(
                                    width: 80, height: 26, padding: const EdgeInsets.symmetric(horizontal: 4),
                                    decoration: BoxDecoration(color: const Color(0xFFFFF0E0), border: Border.all(color: Colors.orange.shade300), borderRadius: BorderRadius.circular(4)),
                                    child: Row(children: [
                                      Text(DateFormat('d/M/yy').format(_date), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                                      const Spacer(), const Icon(Icons.calendar_month, size: 10, color: Colors.orange),
                                    ]),
                                  )),
                                  const SizedBox(width: 2),
                                  _headerColumn("Time", Container(
                                    width: 70, height: 26, alignment: Alignment.center,
                                    decoration: BoxDecoration(color: const Color(0xFFF1F8E9), border: Border.all(color: Colors.green.shade300), borderRadius: BorderRadius.circular(4)),
                                    child: Text(_timeString, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                                  )),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),

                            _headerColumn("Doctor", _buildDoctorAutocomplete()),
                            const SizedBox(width: 12),

                            _btnWithIcon(Icons.file_download_rounded, "Import", Colors.blue.shade700, onTap: _importPrescription),
                            const SizedBox(width: 4),
                            _btnWithIcon(Icons.file_upload_rounded, "Export", Colors.green.shade700, onTap: _exportPrescription),
                            const SizedBox(width: 12),
                            _headerColumn("ORDER", _buildOrderTypeToggle(), align: CrossAxisAlignment.center),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
    );
  }


  Widget _headerColumn(String label, Widget child, {CrossAxisAlignment align = CrossAxisAlignment.start}) => Column(
    crossAxisAlignment: align,
    children: [
      Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
      const SizedBox(height: 1), // Reduced height to remove blank space
      child,
    ],
  );

  Widget _buildOrderTypeToggle() {
    return Container(
      height: 28, // Reduced height
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _orderTypeSegment("NORMAL", 0),
          _orderTypeSegment("SPECIAL ORDER", 1),
          _orderTypeSegment("ONE TIME ORDER", 2),
        ],
      ),
    );
  }

  Widget _orderTypeSegment(String label, int type) {
    bool isSelected = _orderType == type;
    Color activeColor = Colors.blue.shade800;
    if (type == 1) activeColor = Colors.green.shade700;
    if (type == 2) activeColor = Colors.black;

    return GestureDetector(
      onTap: () {
        setState(() {
          _orderType = type;
          if (type == 1) {
            _showSpecialOrderSidebar = true;
            _isSpecialOrderMinimized = false;
            _isProductSyncEnabled = false;
            _isSpecialSyncEnabled = false;
            _specialOrderQtys.clear();
          } else {
            _showSpecialOrderSidebar = false;
            _isSpecialOrderMinimized = false;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6), // Reduced from 10 to save space
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected ? [const BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))] : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9, // Slightly smaller font
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _buildSpecialOrderList() {
    List<Map<String, dynamic>> list = [];
    Set<String> uniqueNames = {};

    if (_isProductSyncEnabled) {
      for (var it in _items) {
        if (it.product.name.isEmpty || uniqueNames.contains(it.product.name)) continue;
        uniqueNames.add(it.product.name);
        int defaultQty = _isSpecialSyncEnabled ? it.qty : 0;
        list.add({'name': it.product.name, 'qty': _specialOrderQtys[it.product.name] ?? defaultQty});
      }
    }

    for (var name in _extraSpecialItems) {
      if (uniqueNames.contains(name)) continue;
      uniqueNames.add(name);
      list.add({'name': name, 'qty': _specialOrderQtys[name] ?? 0});
    }
    return list;
  }

  TextEditingController _getSpecialCtrl(String productName, int initialQty) {
    if (!_specialOrderCtrls.containsKey(productName)) {
      _specialOrderCtrls[productName] = TextEditingController(text: initialQty.toString());
    }
    return _specialOrderCtrls[productName]!;
  }

  FocusNode _getSpecialFocusNode(String productName) {
    if (!_specialOrderFocusNodes.containsKey(productName)) {
      _specialOrderFocusNodes[productName] = FocusNode();
    }
    return _specialOrderFocusNodes[productName]!;
  }


  Widget _buildSpecialOrderPanel() {
    final List<Map<String, dynamic>> list = _buildSpecialOrderList();
    return Positioned(
      top: 110, right: 10, bottom: 200,
      child: GestureDetector(
        onTap: () {}, // Consume taps so background doesn't reset focus
        child: Container(
          width: 350,
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 15, offset: Offset(0, 5))],
              border: Border.all(color: Colors.blue.shade300, width: 2)
          ),
          child: Column(
            children: [
              Container(
                height: 35,
                decoration: BoxDecoration(
                    color: Colors.blue.shade800,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(10))
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  const Icon(Icons.shopping_basket, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(child: Text("SPECIAL ORDER LIST", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),

                  // SYNC CONTROLS
                  Theme(
                    data: ThemeData(unselectedWidgetColor: Colors.white60),
                    child: Checkbox(
                      value: _isProductSyncEnabled,
                      onChanged: (v) {
                        setState(() {
                          _isProductSyncEnabled = v!;
                          if (v) {
                            _specialCustomerNameCtrl.text = _patientCtrl.text;
                            _specialCustomerPhoneCtrl.text = _mobileCtrl.text;
                          } else {
                            _isSpecialSyncEnabled = false;
                          }
                        });
                      },
                      activeColor: Colors.white, checkColor: Colors.blue.shade800,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const Text("SYNC", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),

                  const SizedBox(width: 8),
                  // WINDOW CONTROLS (PC STYLE)
                  InkWell(
                    onTap: () => setState(() => _isSpecialOrderMinimized = true),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                      child: const Icon(Icons.remove, color: Colors.white, size: 16),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => setState(() => _showSpecialOrderSidebar = false),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.red.shade400, borderRadius: BorderRadius.circular(4)),
                      child: const Icon(Icons.close, color: Colors.white, size: 16),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: CompositedTransformTarget(
                        link: _specialCustomerLayer,
                        child: TextField(
                          controller: _specialCustomerNameCtrl,
                          focusNode: _specialCustomerNameFocus,
                          onChanged: (v) => _onHeaderSearch(v, _patientSearchList, (p) => p.patients),
                          onSubmitted: (_) => _specialCustomerPhoneFocus.requestFocus(),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [UpperCaseTextFormatter()],
                          decoration: InputDecoration(
                            hintText: "CUSTOMER NAME", isDense: true, filled: true, fillColor: Colors.blue.shade50,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.all(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: _specialCustomerPhoneCtrl,
                        focusNode: _specialCustomerPhoneFocus,
                        onSubmitted: (_) => _agentFocus.requestFocus(),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [UpperCaseTextFormatter()],
                        decoration: InputDecoration(
                          hintText: "CUSTOMER PHONE", isDense: true, filled: true, fillColor: Colors.blue.shade50,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.all(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _agentCtrl,
                        focusNode: _agentFocus,
                        onSubmitted: (_) => _expectingDateFocus.requestFocus(),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [UpperCaseTextFormatter()],
                        decoration: InputDecoration(
                          hintText: "AGENT NAME", isDense: true, filled: true, fillColor: Colors.blue.shade50,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.all(8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: _expectingDateCtrl,
                        focusNode: _expectingDateFocus,
                        readOnly: true,
                        enableInteractiveSelection: false,
                        onSubmitted: (_) => _saveSpecialOrderFocus.requestFocus(),
                        onTap: () async {
                          DateTime initial = DateTime.now();
                          try {
                            if (_expectingDateCtrl.text.isNotEmpty) {
                              initial = DateFormat('dd/MM/yyyy').parse(_expectingDateCtrl.text);
                            }
                          } catch (_) {}

                          final picked = await showAppDatePicker(
                            context: context,
                            initialDate: initial,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );

                          if (picked != null) {
                            setState(() {
                              _expectingDateCtrl.text = DateFormat('dd/MM/yyyy').format(picked);
                            });
                          } else if (_expectingDateCtrl.text.isEmpty) {
                            setState(() {
                              _expectingDateCtrl.text = DateFormat('dd/MM/yyyy').format(DateTime.now());
                            });
                          }
                          _saveSpecialOrderFocus.requestFocus();
                        },
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          hintText: "EXPECTING DATE", isDense: true, filled: true, fillColor: Colors.blue.shade50,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.all(8),
                          suffixIcon: const Icon(Icons.calendar_month, size: 14, color: Colors.blueGrey),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: CompositedTransformTarget(
                  link: _specialSearchLayer,
                  child: TextField(
                    controller: _specialMainCtrl,
                    focusNode: _specialSearchFocus,
                    onChanged: _startSpecialProductSearch,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [UpperCaseTextFormatter()],
                    decoration: InputDecoration(
                      hintText: "SEARCH",
                      isDense: true,
                      filled: true,
                      fillColor: Colors.blue.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.all(10),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: list.length,
                  itemBuilder: (ctx, i) {
                    final item = list[i];
                    final String name = item['name'];
                    int displayQty = item['qty'];

                    final ctrl = _getSpecialCtrl(name, displayQty);
                    if (_isSpecialSyncEnabled && i < _items.length) {
                      if (ctrl.text != _items[i].qty.toString()) {
                        ctrl.text = _items[i].qty.toString();
                      }
                    }

                    return Container(
                      height: 32,
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
                      child: Row(children: [
                        const SizedBox(width: 12),
                        Expanded(child: Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                        Container(
                          width: 60, height: 26,
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          child: TextField(
                            controller: ctrl,
                            focusNode: _getSpecialFocusNode(name),
                            key: ValueKey("special_$name"),
                            textAlign: TextAlign.right,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              hintText: displayQty.toString(),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                            ),
                            onChanged: (v) {
                              _specialOrderQtys[name] = int.tryParse(v) ?? 0;
                            },
                            onSubmitted: (_) {
                              _specialCustomerNameFocus.requestFocus();
                              _specialCustomerNameCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _specialCustomerNameCtrl.text.length);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        const SizedBox(width: 30, child: Text("NOS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey))),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            setState(() {
                              _extraSpecialItems.remove(name);
                              _specialOrderQtys.remove(name);
                              _specialOrderCtrls.remove(name);
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                      ]),
                    );
                  },
                ),
              ),
              Container(
                decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                    border: Border(top: BorderSide(color: Colors.grey.shade200))
                ),
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: Focus(
                        focusNode: _saveSpecialOrderFocus,
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
                            _saveSpecialOrderOnly();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: ValueListenableBuilder<bool>(
                          valueListenable: ValueNotifier(_saveSpecialOrderFocus.hasFocus),
                          builder: (context, isFocused, _) {
                            return ElevatedButton.icon(
                              onPressed: _saveSpecialOrderOnly,
                              icon: const Icon(Icons.save, size: 16, color: Colors.white),
                              label: const Text("SAVE SPECIAL ORDER", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: isFocused ? Colors.green.shade900 : Colors.green.shade700,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPatientSearchDialog() {
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    String filter = "";
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final filtered = p.patientMaster.where((pat) {
            final q = filter.toLowerCase().trim();
            if (q.isEmpty) return true;
            return pat.name.toLowerCase().contains(q) || pat.mobile.contains(q);
          }).toList();

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.person_search, color: Colors.blue),
                SizedBox(width: 8),
                Text("Search & Select Patient", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: 450,
              height: 450,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: "Search Patient Name or Mobile...",
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                    onChanged: (val) {
                      setStateDialog(() => filter = val);
                    },
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text("No patients found", style: TextStyle(color: Colors.grey)))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final pat = filtered[index];
                              return ListTile(
                                dense: true,
                                title: Text(pat.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                subtitle: Text("Mobile: ${pat.mobile.isNotEmpty ? pat.mobile : 'N/A'} | ID: ${pat.id}", style: const TextStyle(fontSize: 11)),
                                onTap: () {
                                  setState(() {
                                    _patientCtrl.text = pat.name;
                                    _mobileCtrl.text = pat.mobile;
                                  });
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("CANCEL"),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPatientAutocomplete() {
    bool isMod = _isPatientModified();
    bool isEmptyErr = _patientCtrl.text.trim().isEmpty;
    Color baseBg = isEmptyErr ? Colors.red.shade50 : (isMod ? _editHighlightBg : Colors.white);
    Border baseBorder = isEmptyErr
        ? Border.all(color: Colors.red.shade600, width: 1.5)
        : (isMod
            ? Border.all(color: _editHighlightBorder, width: 1.2)
            : Border.all(color: Colors.grey.shade400));

    return Container(
      width: 200, height: 26, 
      decoration: BoxDecoration(color: baseBg, border: baseBorder, borderRadius: BorderRadius.circular(4)), 
      child: RawAutocomplete<String>(
        textEditingController: _patientCtrl,
        focusNode: _patientFocus,
        optionsBuilder: (TextEditingValue textEditingValue) {
          if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
          final query = textEditingValue.text.toLowerCase().trim();
          final provider = Provider.of<PharmacyProvider>(context, listen: false);

          final matches = provider.patientMaster
              .where((p) => p.name.toLowerCase().startsWith(query))
              .map((p) => p.name)
              .toList();

          bool exactMatchExists = matches.any((name) => name.toLowerCase() == query);
          if (!exactMatchExists) {
            matches.add('ADD NEW NAME: ${textEditingValue.text.toUpperCase().trim()}');
          }

          return matches;
        },
        onSelected: (String selection) async {
          final provider = Provider.of<PharmacyProvider>(context, listen: false);
          if (selection.startsWith('ADD NEW NAME: ')) {
            final newName = selection.replaceAll('ADD NEW NAME: ', '').trim();
            final newPatient = Patient(
              id: "PAT_${DateTime.now().millisecondsSinceEpoch}",
              name: newName,
              mobile: _mobileCtrl.text.trim(),
            );
            await provider.registerPatient(newPatient);
            _patientCtrl.text = newName;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("PATIENT NAME CREATED"), backgroundColor: Colors.green),
              );
            }
          } else {
            _patientCtrl.text = selection;
            final existing = provider.patientMaster.cast<Patient?>().firstWhere(
                    (p) => p?.name == selection, orElse: () => null
            );
            if (existing != null && existing.mobile.isNotEmpty) {
              _mobileCtrl.text = existing.mobile;
            }
          }
          _moveFocus(-1, 1);
          _syncToGlobalSession();
        },
        fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
          const bool isLocked = false;
          final bool readOnly = _isDeleted || isLocked;

          return TextField(
            controller: controller,
            focusNode: focusNode,
            readOnly: readOnly,
            onTap: () {
              if (focusNode.hasFocus) {
                _focusedPatientText = controller.text;
              }
            },
            onEditingComplete: onEditingComplete,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              isDense: true, border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              child: Container(
                width: 300,
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.blue.shade900, width: 2)),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (BuildContext context, int index) {
                    final option = options.elementAt(index);
                    final isHighlighted = AutocompleteHighlightedOption.of(context) == index;
                    final isNew = option.startsWith('ADD NEW NAME: ');
                    final bool shouldHighlight = isHighlighted || (AutocompleteHighlightedOption.of(context) == -1 && index == 0);

                    return InkWell(
                      onTap: () => onSelected(option),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: shouldHighlight ? Colors.blue.shade50 : null,
                          border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                        ),
                        child: Text(
                          option,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: shouldHighlight || isNew ? FontWeight.bold : FontWeight.w600,
                            color: shouldHighlight ? Colors.blue.shade900 : (isNew ? Colors.blue.shade700 : Colors.black87),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDoctorAutocomplete() {
    const bool isLocked = false;
    final bool readOnly = _isDeleted || isLocked;

    bool isMod = _isDoctorModified();
    bool isEmptyErr = _doctorCtrl.text.trim().isEmpty;
    Color baseBg = isEmptyErr ? Colors.red.shade50 : (isMod ? _editHighlightBg : Colors.white);
    Border baseBorder = isEmptyErr
        ? Border.all(color: Colors.red.shade600, width: 1.5)
        : (isMod
            ? Border.all(color: _editHighlightBorder, width: 1.2)
            : Border.all(color: Colors.grey.shade400));

    return Container(
      width: 200, height: 26, 
      decoration: BoxDecoration(color: baseBg, border: baseBorder, borderRadius: BorderRadius.circular(4)), 
      child: RawAutocomplete<String>(
        textEditingController: _doctorCtrl,
        focusNode: _doctorFocus,
        optionsBuilder: (TextEditingValue textEditingValue) {
          if (textEditingValue.text.isEmpty) {
            return const Iterable<String>.empty();
          }
          final query = textEditingValue.text.toLowerCase().trim();
          final provider = Provider.of<PharmacyProvider>(context, listen: false);

          final matches = provider.doctorMaster
              .where((d) => d.name.toLowerCase().startsWith(query))
              .map((d) => d.name)
              .toList();

          bool exactMatchExists = matches.any((name) => name.toLowerCase() == query);
          if (!exactMatchExists) {
            matches.add('ADD NEW NAME: ${textEditingValue.text.toUpperCase().trim()}');
          }

          return matches;
        },
        onSelected: (String selection) async {
          final provider = Provider.of<PharmacyProvider>(context, listen: false);
          if (selection.startsWith('ADD NEW NAME: ')) {
            final newName = selection.replaceAll('ADD NEW NAME: ', '').trim();
            final newDoctor = Doctor(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              name: newName,
              mobile: "",
              specialization: "General",
              regNo: "",
              isActive: true,
            );
            await provider.registerDoctor(newDoctor);
            _doctorCtrl.text = newName;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("DOCTOR NAME CREATED"), backgroundColor: Colors.green),
              );
            }
          } else {
            _doctorCtrl.text = selection;
          }
          _moveFocus(-1, 3); // Jump to Days
          _syncToGlobalSession();
        },
        fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            readOnly: readOnly,
            onTap: () {
              if (focusNode.hasFocus) {
                _focusedDoctorText = controller.text;
              }
            },
            onEditingComplete: onEditingComplete,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(4),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (BuildContext context, int index) {
                    final option = options.elementAt(index);
                    final isHighlighted = AutocompleteHighlightedOption.of(context) == index;
                    final isNew = option.startsWith('ADD NEW NAME: ');
                    final bool shouldHighlight = isHighlighted || (AutocompleteHighlightedOption.of(context) == -1 && index == 0);

                    return InkWell(
                      onTap: () => onSelected(option),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                          color: shouldHighlight ? Colors.blue.shade50 : Colors.white,
                        ),
                        child: Text(
                          option,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: shouldHighlight || isNew ? FontWeight.bold : FontWeight.w600,
                            color: shouldHighlight ? Colors.blue.shade900 : (isNew ? Colors.blue.shade700 : Colors.black87),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _btnWithIcon(IconData icon, String label, Color color, {VoidCallback? onTap}) => InkWell(
    onTap: onTap,
    child: Container(
      height: 28, // Matches Order Type box height
      padding: const EdgeInsets.symmetric(horizontal: 10), // Matches Order Type segment padding
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)), // Radius 6 matches Order Type segments
      child: Row(children: [
        Icon(icon, color: Colors.white, size: 14), const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)), // Font size 9 matches Order Type
      ]),
    ),
  );

  Widget _radio(String label, int value) => Row(mainAxisSize: MainAxisSize.min, children: [
    SizedBox(
      width: 22,
      height: 22,
      child: Radio<int>(
          value: value,
          groupValue: _gstType,
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: (v) {
            setState(() {
              _gstType = v!;
              for (int i = 0; i < _items.length; i++) {
                _calculateItem(i);
              }
            });
          }),
    ),
    const SizedBox(width: 2),
    Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
  ]);

  Widget _headerInp(int col, {double? width, double? height, LayerLink? link, Function(String)? onChanged, Function(String)? onSubmitted}) {
    const bool isLocked = false;
    final bool readOnly = _isDeleted || isLocked;
    final bool isNumeric = (col == 1 || col == 3);

    Widget field = TextField(
        readOnly: readOnly,
        controller: _getHeaderCtrl(col), focusNode: _getHeaderFocus(col),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        textAlignVertical: TextAlignVertical.center,
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        onChanged: (v) {
          _markDirty();
          if (onChanged != null) onChanged(v);
          _syncToGlobalSession();
        },
        onSubmitted: readOnly ? null : onSubmitted,
        textCapitalization: isNumeric ? TextCapitalization.none : TextCapitalization.characters,
        inputFormatters: isNumeric ? [FilteringTextInputFormatter.digitsOnly] : [UpperCaseTextFormatter()],
        decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8))
    );

    if (link != null) {
      field = CompositedTransformTarget(link: link, child: field);
    }

    return Container(
        width: width, height: height ?? 26, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4)),
        child: field
    );
  }

  Widget _buildGridHeader() => Container(
        height: 32,
        color: const Color(0xFF37474F),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List.generate(
            17,
            (i) => _ResizableHdr(
              i,
              _getColName(i),
              _colWidths,
              tooltip: _getColTooltip(i),
              onResize: (v) => setState(() => _colWidths[i] = v),
              align: _getColAlign(i),
              onTap: i == 15 ? () => setState(() => _showProfitColumn = !_showProfitColumn) : null,
            ),
          ),
        ),
      );

  String _getColName(int i) => [
        "Slr", "BALANCE", "Product", "Rack", "Batch", "Expiry", "Pack", "Qty",
        "Strips / Loose", "MRP", "1 /MRP", "Disc%", "Disc Amt", "GST%", "Total",
        _showProfitColumn ? "👁️ Profit" : "👁️", ""
      ][i];

  String _getColTooltip(int i) => [
        "Serial Number",
        "Current Live Stock Balance",
        "Product Name",
        "Rack Location",
        "Batch Number",
        "Expiry Date (MM/YY)",
        "Packing Size",
        "Sale Quantity",
        "Strips / Loose Quantity Breakdown",
        "Maximum Retail Price",
        "Unit Price per Tablet (1 / MRP)",
        "Discount Percentage",
        "Discount Amount",
        "GST Percentage",
        "Total Amount",
        _showProfitColumn ? "Estimated Profit Amount" : "Toggle Profit Column",
        ""
      ][i];

  TextAlign _getColAlign(int i) => [TextAlign.center, TextAlign.center, TextAlign.left, TextAlign.center, TextAlign.left, TextAlign.center, TextAlign.right, TextAlign.right, TextAlign.center, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.right, TextAlign.center][i];

  Widget _buildGrid() => Scrollbar(
    controller: _verticalGridScrollCtrl,
    child: ListView.builder(
        controller: _verticalGridScrollCtrl,
        padding: EdgeInsets.zero,
        itemExtent: 30.0,
        itemCount: _items.length + (_isDeleted ? 0 : 1),
        itemBuilder: (ctx, i) => RepaintBoundary(
          child: i < _items.length ? _buildRow(i) : _buildEmptyRow(i),
        ),
    ),
  );

  // ---> FALLBACK GETTERS PREVENT SCOPE ERRORS <---
  Color get defaultColor => Colors.black87;
  Color get nameColor => Colors.black87;
  Color get expiryColor => Colors.black87;

  int _getLiveRemainingStock(int row) {
    if (row >= _items.length) return 0;
    final it = _items[row];
    final cleanName = Product.cleanProductName(it.product.name).toLowerCase();
    if (cleanName.isEmpty) return 0;

    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    // 1. Instant O(1) Map Lookup for Total Stock Across All Batches
    int totalAllBatchesStock = provider.getTotalStockForProduct(cleanName);
    if (totalAllBatchesStock <= 0 && it.product.stock > 0) {
      totalAllBatchesStock = it.product.stock;
    }

    // 2. Sum total quantity of this medicine added across ALL rows in current bill
    int totalQtyInBill = 0;
    for (int i = 0; i < _items.length; i++) {
      final other = _items[i];
      final otherCleanName = Product.cleanProductName(other.product.name).toLowerCase();
      if ((it.product.id.isNotEmpty && other.product.id == it.product.id) || otherCleanName == cleanName) {
        totalQtyInBill += other.qty + other.fQty;
      }
    }

    int remaining = totalAllBatchesStock - totalQtyInBill;
    return remaining < 0 ? 0 : remaining;
  }

  Widget _buildRow(int row) {
    final it = _items[row];
    double profit = it.profit;

    bool isExpired = it.product.expiry.isNotEmpty && _parseExpiry(it.product.expiry).isBefore(DateTime.now());
    bool isH1 = it.product.schedule.toUpperCase() == "H1";

    // Row-specific font colors
    Color rowNameColor = isH1 ? Colors.red.shade700 : (isExpired ? Colors.red.shade900 : Colors.black87);
    Color rowExpiryColor = isExpired ? Colors.red.shade900 : Colors.black87;
    Color rowDefaultColor = isH1 ? Colors.red.shade900 : Colors.black87;

    int liveRemStock = _getLiveRemainingStock(row);
    Color remColor = liveRemStock > 0
        ? Colors.teal.shade800
        : (liveRemStock == 0 ? Colors.orange.shade900 : Colors.red.shade700);

    bool isNewRow = false;
    bool isQtyMod = false;
    bool isBatchMod = false;
    bool isDiscMod = false;
    bool isProdMod = false;

    if (_isExistingEntry && _highlightEdits) {
      if (!_originalItemSnapshots.containsKey(it)) {
        isNewRow = true;
      } else {
        final snap = _originalItemSnapshots[it]!;
        if (it.product.name.trim().toUpperCase() != snap['name']) isProdMod = true;
        if (it.product.batch.trim().toUpperCase() != snap['batch']) isBatchMod = true;
        if (it.qty != snap['qty']) isQtyMod = true;
        if ((it.discPercent - (snap['discPercent'] as double)).abs() > 0.01) isDiscMod = true;
      }
    }

    return ValueListenableBuilder<IntPair?>(
      valueListenable: _focusNotifier,
      builder: (context, focus, _) {
        bool isRowActive = focus?.row == row;

        Color rowBg = isRowActive
            ? const Color(0xFFF0F7FF)
            : (isH1 ? Colors.red.shade50 : (row % 2 == 0 ? Colors.white : const Color(0xFFF9FAFB)));

        return Container(
          key: ValueKey("s_row_${it.uuid}"),
          height: 30,
          decoration: BoxDecoration(
            color: rowBg,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.5)),
          ),
          child: Row(
            children: [
              _cell(row, 0, "${row + 1}", _colWidths[0]!, align: TextAlign.center, color: rowDefaultColor),
              _cell(row, 1, "$liveRemStock", _colWidths[1]!, align: TextAlign.center, fontWeight: FontWeight.bold, color: remColor),
              _cell(row, 2, it.product.name.toUpperCase(), _colWidths[2]!, isInput: true, fontWeight: FontWeight.bold, color: rowNameColor, cellBg: (isNewRow || isProdMod) ? _editHighlightBg : null, onChanged: (v) {
                // Instantly allocate an independent Product object to prevent cross-row mutation
                it.product = Product(
                  id: "",
                  name: v,
                  batch: "",
                  expiry: "",
                  packSize: 1,
                  mrp: 0,
                  salePrice: 0,
                  purchaseRate: 0,
                  landingCost: 0,
                  gstPercent: 12,
                  rack: "",
                  category: "",
                  manufacturer: "",
                  genericName: "",
                  stock: 0,
                );
                _getGridCtrl(row, 4).clear();
                _getGridCtrl(row, 5).clear();
                _startProductSearch(v);
              }),
              _cell(row, 3, it.product.rack.toUpperCase(), _colWidths[3]!, align: TextAlign.center, color: rowDefaultColor),
              _cell(row, 4, _cleanBatch(it.product.batch).toUpperCase(), _colWidths[4]!, isInput: true, color: rowExpiryColor, cellBg: (isNewRow || isBatchMod) ? _editHighlightBg : null, onChanged: (v) {
                it.product.batch = v;
                _startBatchSearch(row, v);
              }),
              _cell(row, 5, it.product.expiry, _colWidths[5]!, isInput: true, align: TextAlign.center, color: rowExpiryColor, hint: "MM/YY", onChanged: (v) {
                it.product.expiry = v;
              }),
              _cell(row, 6, it.packin.toString(), _colWidths[6]!, align: TextAlign.right, color: Colors.blueGrey, isLocked: true),
              _cell(row, 7, it.qty.toString(), _colWidths[7]!, isInput: true, align: TextAlign.right, color: rowDefaultColor, cellBg: (isNewRow || isQtyMod) ? _editHighlightBg : null, onChanged: (v) {
                it.qty = int.tryParse(v) ?? 0;
                _calculateItem(row);
              }),
              _cell(row, 8, "", _colWidths[8]!, align: TextAlign.center, isLocked: true,
                customLabel: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Roboto'),
                    children: [
                      TextSpan(
                        text: "${it.qty ~/ (it.packin > 0 ? it.packin : 1)}",
                        style: TextStyle(color: (it.qty ~/ (it.packin > 0 ? it.packin : 1)) > 0 ? Colors.green.shade700 : Colors.blueGrey),
                      ),
                      const TextSpan(text: " / ", style: TextStyle(color: Colors.blueGrey)),
                      TextSpan(
                        text: "${it.qty % (it.packin > 0 ? it.packin : 1)}",
                        style: TextStyle(color: (it.qty % (it.packin > 0 ? it.packin : 1)) > 0 ? Colors.red.shade700 : Colors.blueGrey),
                      ),
                    ],
                  ),
                ),
              ),
              _cell(row, 9, it.product.mrp.toStringAsFixed(2), _colWidths[9]!, align: TextAlign.right, color: rowDefaultColor),
              _cell(row, 10, it.mrp.toStringAsFixed(2), _colWidths[10]!, align: TextAlign.right, color: rowDefaultColor),
              _cell(row, 11, it.discPercent.toStringAsFixed(2), _colWidths[11]!, isInput: true, align: TextAlign.right, color: rowDefaultColor, cellBg: (isNewRow || isDiscMod) ? _editHighlightBg : null, onChanged: (v) {
                it.discPercent = double.tryParse(v) ?? 0;
                _calculateItem(row);
              }),
              _cell(row, 12, it.discAmt.toStringAsFixed(2), _colWidths[12]!, align: TextAlign.right, color: rowDefaultColor),
              _cell(row, 13, (TaxCalculator.roundGstPercent(it.gstPercent) % 1 == 0 ? TaxCalculator.roundGstPercent(it.gstPercent).toInt().toString() : TaxCalculator.roundGstPercent(it.gstPercent).toStringAsFixed(1)), _colWidths[13]!, align: TextAlign.right, color: rowDefaultColor),
              _cell(row, 14, it.total.toStringAsFixed(2), _colWidths[14]!, align: TextAlign.right, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
              _cell(row, 15, _showProfitColumn ? profit.toStringAsFixed(2) : "", _colWidths[15]!, align: TextAlign.right, color: profit >= 0 ? Colors.green.shade700 : Colors.red),
              _isDeleted ? SizedBox(width: _colWidths[16]!) : Container(
                width: _colWidths[16]!,
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.info_outline_rounded, color: Colors.blueGrey, size: 14),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: "Line Math Breakdown",
                      onPressed: () => _showSaleItemMathBreakdown(it),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _safeDeleteRow(row),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyRow(int row) {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: (row % 2 == 0 ? Colors.white : const Color(0xFFF9FAFB)),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.5)),
      ),
      child: Row(
        children: [
          _cell(row, 0, "${row + 1}", _colWidths[0]!, align: TextAlign.center, color: defaultColor),
          _cell(row, 1, "", _colWidths[1]!, align: TextAlign.center, color: defaultColor),
          _cell(row, 2, "", _colWidths[2]!, isInput: true, hint: "Search Product...", color: defaultColor, onChanged: _startProductSearch),
          _cell(row, 3, "", _colWidths[3]!, align: TextAlign.center, color: defaultColor),
          _cell(row, 4, "", _colWidths[4]!, isInput: true, color: defaultColor, onChanged: (v) => _startBatchSearch(row, v)),
          _cell(row, 5, "", _colWidths[5]!, isInput: true, align: TextAlign.center, color: defaultColor, hint: "MM/YY"),
          _cell(row, 6, "", _colWidths[6]!, align: TextAlign.right, color: Colors.blueGrey, isLocked: true),
          _cell(row, 7, "", _colWidths[7]!, isInput: true, align: TextAlign.right, color: defaultColor),
          _cell(row, 8, "", _colWidths[8]!, align: TextAlign.center, isLocked: true),
          _cell(row, 9, "", _colWidths[9]!, align: TextAlign.right, color: defaultColor),
          _cell(row, 10, "", _colWidths[10]!, align: TextAlign.right, color: defaultColor),
          _cell(row, 11, "0", _colWidths[11]!, isInput: true, align: TextAlign.right, color: defaultColor),
          _cell(row, 12, "", _colWidths[12]!, align: TextAlign.right, color: defaultColor),
          _cell(row, 13, "", _colWidths[13]!, align: TextAlign.right, color: defaultColor),
          _cell(row, 14, "", _colWidths[14]!, align: TextAlign.right, color: defaultColor),
          _cell(row, 15, "", _colWidths[15]!, align: TextAlign.right, color: defaultColor),
          SizedBox(width: _colWidths[16]!),
        ],
      ),
    );
  }

  Widget _cell(int row, int col, String val, double w, {bool isInput = false, bool isLocked = false, TextAlign align = TextAlign.left, Color? color, FontWeight? fontWeight, String hint = "", String? subValue, Function(String)? onChanged, Widget? customLabel, Color? cellBg}) {
    final actualFocusNode = _getGridFocusNode(row, col);
    String rowId = row < _items.length ? _items[row].uuid : "new_row";

    return ListenableBuilder(
      listenable: actualFocusNode,
      builder: (context, _) {
        bool isFocused = (_focusNotifier.value?.row == row && _focusNotifier.value?.col == col) || actualFocusNode.hasFocus;
        bool isFocusable = _editableCols.contains(col);
        final ctrl = _getGridCtrl(row, col, val);
        
        if (!isFocused && ctrl.text != val) {
          ctrl.text = val;
        }

        const bool isEntryLocked = false;
        bool isActuallyInput = isInput && !_isDeleted && !isEntryLocked && !isLocked;
        bool renderAsTextField = isActuallyInput && isFocused;

        Color? bg;
        BoxBorder? customBorder;
        BorderRadius? customRadius;
        EdgeInsetsGeometry? customMargin;

        bool isModifiedCell = (cellBg != null);
        bool isQtyZero = (col == 7 && row < _items.length && (_items[row].qty <= 0 || ctrl.text.trim() == "0" || (double.tryParse(ctrl.text.trim()) ?? 0) <= 0));

        if (_errorCells[row]?.contains(col) == true || isQtyZero) {
          bg = Colors.red.shade100;
          customBorder = Border.all(color: Colors.red.shade700, width: 1.5);
          customRadius = BorderRadius.circular(2);
        } else if (isModifiedCell) {
          // ---> 3D RED BOX (MATCHING PHOTO 2 DATE BOX) <---
          bg = _editHighlightBg;
          customBorder = Border.all(color: _editHighlightBorder, width: 1.2);
          customRadius = BorderRadius.circular(4);
          customMargin = const EdgeInsets.symmetric(horizontal: 2, vertical: 2);
        } else if (isLocked) {
          bg = const Color(0xFFF1F5F9);
        } else {
          bg = (row % 2 == 0) ? Colors.white : const Color(0xFFF8FAFC);
          if (isFocused && isActuallyInput) {
            bg = const Color(0xFFEFF6FF);
          }
        }

        Color textColor = (color == Colors.blueGrey || color == Colors.grey || color == null)
            ? const Color(0xFF0F172A)
            : color;

        Widget cellContent = renderAsTextField
            ? TextField(
                key: ValueKey("s_tf_${rowId}_$col"), 
                controller: ctrl, 
                focusNode: actualFocusNode, 
                textAlign: align,
                keyboardType: (col == 7 || col == 11 || col == 12) ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                inputFormatters: (col == 7 || col == 11 || col == 12) ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : (col == 5 ? [ExpiryFormatter()] : [UpperCaseTextFormatter()]),
                onChanged: (v) {
                  if (_errorCells[row]?.contains(col) == true) {
                     setState(() {
                       _errorCells[row]?.remove(col);
                     });
                  }
                  _markDirty();
                  if (col == 2) {
                    // Only search/open dropdown if the user is typing a new query or the field was cleared
                    final existingName = row < _items.length ? _items[row].product.name : "";
                    if (v.trim().isEmpty || !(_isExistingEntry && v.trim().toUpperCase() == existingName.trim().toUpperCase())) {
                      _startProductSearch(v);
                    }
                  } else if (col == 4) {
                    _startBatchSearch(row, v);
                  } else {
                    if (onChanged != null) onChanged(v);
                  }
                },
                onTap: () {
                  setState(() {
                    _isSelectingBatch = (col == 4);
                  });

                  final bool isAlreadyFocused = (_focusNotifier.value?.row == row && _focusNotifier.value?.col == col);

                  if (!isAlreadyFocused) {
                    _moveFocus(row, col, autoOpen: (col == 2 || col == 4) && ctrl.text.trim().isEmpty);
                    if (ctrl.text.trim().isNotEmpty) {
                      ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
                    }
                  } else {
                    if (col == 2) {
                      if (ctrl.text.trim().isEmpty) {
                        _startProductSearch(ctrl.text);
                      }
                    } else if (col == 4) {
                      if (ctrl.text.trim().isEmpty) {
                        _startBatchSearch(row, ctrl.text);
                      }
                    }
                  }
                },
                textCapitalization: (col == 5 || col == 11) ? TextCapitalization.none : TextCapitalization.characters,
                textAlignVertical: TextAlignVertical.center,
                style: TextStyle(fontSize: 14, fontWeight: fontWeight ?? FontWeight.bold, color: textColor),
                decoration: InputDecoration(isDense: true, border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4), hintText: hint, hintStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.grey)),
                cursorColor: Colors.blue.shade900, cursorWidth: 2.0,
              )
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                alignment: align == TextAlign.center ? Alignment.center : (align == TextAlign.right ? Alignment.centerRight : Alignment.centerLeft),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: align == TextAlign.right ? CrossAxisAlignment.end : (align == TextAlign.center ? CrossAxisAlignment.center : CrossAxisAlignment.start),
                  children: [
                    customLabel ?? Text(val.toUpperCase(), style: TextStyle(fontSize: 12.5, color: textColor, fontWeight: fontWeight ?? FontWeight.w700), overflow: TextOverflow.ellipsis),
                    if (subValue != null && subValue.isNotEmpty)
                      Text(subValue, style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                  ],
                )
              );

        bool isCurrentSearchTarget = (col == 2) && (_focusNotifier.value?.row == row || actualFocusNode.hasFocus || _focusedRowIndex == row);
        bool isCurrentBatchTarget = (col == 4) && (_focusNotifier.value?.row == row || actualFocusNode.hasFocus || _focusedRowIndex == row);

        Widget content = Container(
            key: ValueKey("s_cell_${rowId}_$col"),
            margin: customMargin,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: customRadius,
              border: (isFocused && isFocusable)
                  ? Border.all(color: Colors.blue.shade800, width: 2.2)
                  : customBorder,
            ),
            child: (col == 2 || col == 4)
                ? CompositedTransformTarget(
                    link: isCurrentSearchTarget ? _searchLayer : (isCurrentBatchTarget ? _batchLayer : LayerLink()),
                    child: cellContent,
                  )
                : cellContent,
        );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            if (isFocusable && !isFocused) {
              final auto = (col == 2 || col == 4);
              _moveFocus(row, col, autoOpen: auto);
            }
          },
          child: Container(
            width: w,
            height: 30,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Colors.grey.shade300, width: 0.5),
                bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
              ),
            ),
            child: content,
          ),
        );
      },
    );
  }

  Widget _buildTotalsRow(double width) {
    double sumMrp = _items.fold(0, (sum, it) => sum + (it.mrp * (it.packin > 0 ? it.packin : 1)));
    int sumQty = _items.fold(0, (sum, it) => sum + it.qty);
    double sumDisc = _items.fold(0, (sum, it) => sum + it.discAmt);
    double sumTotal = _items.fold(0, (sum, it) => sum + it.total);
    double sumProfit = _items.fold(0, (sum, it) => sum + it.profit);

    return Container(
      height: 28, width: width, color: const Color(0xFF37474F),
      child: Row(children: [
        SizedBox(width: _colWidths[0]! + _colWidths[1]! + _colWidths[2]! + _colWidths[3]! + _colWidths[4]! + _colWidths[5]!),
        _Hdr(sumQty.toString(), width: _colWidths[6], align: TextAlign.right),
        SizedBox(width: _colWidths[7]!),
        _Hdr(sumMrp.toStringAsFixed(2), width: _colWidths[8], align: TextAlign.right),
        SizedBox(width: _colWidths[9]! + _colWidths[10]!),
        _Hdr(sumDisc.toStringAsFixed(2), width: _colWidths[11], align: TextAlign.right),
        SizedBox(width: _colWidths[12]!),
        _Hdr(sumTotal.toStringAsFixed(2), width: _colWidths[13], align: TextAlign.right),
        _Hdr(_showProfitColumn ? sumProfit.toStringAsFixed(2) : "", width: _colWidths[14], align: TextAlign.right),
        SizedBox(width: _colWidths[15]!),
      ]),
    );
  }

  Widget _buildOverlay() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _buildNameOverlay(_patientLayer, _patientSearchList, _patientCtrl, _mobileFocus),
        _buildNameOverlay(_doctorLayer, _doctorSearchList, _doctorCtrl, null),
        _buildNameOverlay(_specialCustomerLayer, _patientSearchList, _specialCustomerNameCtrl, _specialCustomerPhoneFocus),

        ListenableBuilder(
          listenable: Listenable.merge([_searchList, _batchList]),
          builder: (ctx, _) {
            // Auto-fallback prevents stale boolean states from hiding the dropdown
            final bool isBatch = _isSelectingBatch && _batchList.value.isNotEmpty;
            final list = isBatch ? _batchList.value : _searchList.value;
            
            if (list.isEmpty) return const SizedBox();
            
            final link = isBatch ? _batchLayer : _searchLayer;
            const double dropWidth = 1100.0;

            return CompositedTransformFollower(
              link: link,
              showWhenUnlinked: false,
              offset: const Offset(0, 30),
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) {
                  _isSelectingFromDropdown = true; // Prevents onBlur from closing dropdown
                },
                child: Material(
                  elevation: 16,
                  shadowColor: Colors.black54,
                  child: Container(
                    width: dropWidth,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(
                        color: isBatch ? Colors.teal : Colors.blue.shade900,
                        width: 2.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTapDown: (_) => _startFastScroll(true),
                          onTapUp: (_) => _stopFastScroll(),
                          onTapCancel: () => _stopFastScroll(),
                          child: Container(
                            height: 26,
                            color: isBatch ? Colors.teal : Colors.blue.shade900,
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
                                _Hdr("Profit%", flex: 1, align: TextAlign.right)
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
                                _Hdr("Use", flex: 1)
                              ],
                            ),
                          ),
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 168.0),
                          child: ValueListenableBuilder<int>(
                            valueListenable: _searchIdx,
                            builder: (ctx, idx, _) => Scrollbar(
                              controller: _dropdownScrollCtrl,
                              thumbVisibility: true,
                              child: ListView.builder(
                                controller: _dropdownScrollCtrl,
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemExtent: 24.0,
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: list.length,
                                itemBuilder: (ctx, i) {
                                  final p = list[i];
                                  bool sel = i == idx;

                                  int displayStock = p.stock;
                                  double ps = p.packSize == 0 ? 1 : p.packSize.toDouble();
                                  double pcsMrp = p.mrp / ps;
                                  double pcsPrice = p.mrp / ps;
                                  double profit = p.purchaseRate > 0
                                      ? ((p.mrp - p.purchaseRate) / p.purchaseRate) * 100
                                      : 0.0;

                                  Color bgColor = Colors.white;
                                  Color fontColor = Colors.black;

                                  if (isBatch) {
                                    bgColor = _getBatchBgColor(p.expiry);
                                    fontColor = _getBatchTextColor(p.expiry);
                                  } else {
                                    if (sel) bgColor = Colors.blue.shade50;
                                  }

                                  final bool isH1 = p.schedule.toUpperCase() == "H1";
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapDown: (_) {
                                      _isSelectingFromDropdown = true;
                                    },
                                    onTap: () {
                                      if (isBatch) {
                                        _finalizeBatchSelection(p);
                                      } else {
                                        _onProductSelected(p);
                                      }
                                    },
                                    child: Container(
                                      height: 24,
                                      decoration: BoxDecoration(
                                          color: sel ? Colors.blue.shade100 : (isH1 ? Colors.red.shade50 : Colors.white),
                                          border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 0.5))),
                                      child: Row(
                                        children: isBatch
                                            ? [
                                          _GridCell(_cleanBatch(p.batch), width: 150, fontWeight: FontWeight.bold, color: isH1 ? Colors.red.shade900 : Colors.black),
                                          _GridCell(displayStock.toString(), width: 80, align: TextAlign.right, fontWeight: FontWeight.bold, color: isH1 ? Colors.red.shade900 : Colors.black),
                                          _GridCell(p.packSize.toString(), width: 80, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : Colors.black),
                                          _GridCell("${displayStock ~/ (p.packSize > 0 ? p.packSize : 1)} / ${displayStock % (p.packSize > 0 ? p.packSize : 1)}", width: 80, align: TextAlign.center, color: isH1 ? Colors.red.shade700 : Colors.blue.shade700, fontWeight: FontWeight.bold),
                                          _GridCell(p.expiry, width: 90, align: TextAlign.center, fontWeight: FontWeight.bold, color: fontColor, bgColor: bgColor),
                                          _GridCell(p.mrp.toStringAsFixed(2), width: 90, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : Colors.black),
                                          _GridCell(p.mrp.toStringAsFixed(2), width: 100, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : Colors.black),
                                          _GridCell(p.sDiscPercent.toStringAsFixed(2), width: 70, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : Colors.black),
                                          _GridCell(pcsMrp.toStringAsFixed(2), width: 80, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : Colors.black),
                                          _GridCell(pcsPrice.toStringAsFixed(2), width: 90, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : Colors.black),
                                          _GridCell(p.purchaseRate.toStringAsFixed(2), width: 90, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : Colors.black),
                                          _GridCell(profit.toStringAsFixed(2), flex: 1, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : Colors.black)
                                        ]
                                            : (p.id == "NEW"
                                                ? [
                                                    _GridCell("+ CREATE NEW MEDICINE: '${p.name}'", flex: 1, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                                                  ]
                                                : [
                                          _GridCell(p.name, width: 300, fontWeight: FontWeight.bold, color: isH1 ? Colors.red.shade900 : null),
                                          _GridCell(displayStock.toString(), width: 70, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : Colors.blue.shade700, fontWeight: FontWeight.bold),
                                          _GridCell(p.packSize.toString(), width: 60, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : null),
                                          _GridCell("${displayStock ~/ (p.packSize > 0 ? p.packSize : 1)} / ${displayStock % (p.packSize > 0 ? p.packSize : 1)}", width: 80, align: TextAlign.center, color: isH1 ? Colors.red.shade900 : Colors.blue.shade700, fontWeight: FontWeight.bold),
                                          _GridCell(p.mrp.toStringAsFixed(2), width: 80, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : null),
                                          _GridCell(p.purchaseRate.toStringAsFixed(2), width: 80, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : null),
                                          _GridCell(p.rack, width: 60, color: isH1 ? Colors.red.shade900 : null),
                                          _GridCell(p.category.length > 3 ? p.category.substring(0, 3).toUpperCase() : p.category, width: 50, color: isH1 ? Colors.red.shade900 : null),
                                          _GridCell(p.patent, width: 120, color: isH1 ? Colors.red.shade900 : null),
                                          _GridCell(p.genericName.isNotEmpty ? p.genericName : (Provider.of<PharmacyProvider>(context, listen: false).productMaster.firstWhere((m) => m.id == p.id || m.name.toLowerCase().trim() == p.name.toLowerCase().trim(), orElse: () => Product(id: "", name: p.name)).genericName), width: 150, color: isH1 ? Colors.red.shade900 : null),
                                          _GridCell(p.use, flex: 1, color: isH1 ? Colors.red.shade900 : null)
                                        ]),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTapDown: (_) => _startFastScroll(false),
                          onTapUp: (_) => _stopFastScroll(),
                          onTapCancel: () => _stopFastScroll(),
                          child: Container(
                            height: 10,
                            color: isBatch ? Colors.teal.withValues(alpha: 0.2) : Colors.blue.shade900.withValues(alpha: 0.2),
                            width: double.infinity,
                            child: const Icon(Icons.keyboard_arrow_down, size: 10, color: Colors.white),
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

  Widget _buildNameOverlay(LayerLink link, ValueNotifier<List<dynamic>> listNotifier, TextEditingController ctrl, FocusNode? next) {
    return ValueListenableBuilder<List<dynamic>>(
      valueListenable: listNotifier,
      builder: (ctx, list, _) {
        if (list.isEmpty) return const SizedBox();
        return CompositedTransformFollower(
          link: link, showWhenUnlinked: false, offset: const Offset(0, 26),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) {
              _isSelectingFromDropdown = true;
            },
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
                      bool isNew = i == list.length - 1 && item is String && item.startsWith("ADD NEW");

                      if (item is Patient) {
                        title = item.name;
                        subtitle = item.mobile;
                      } else if (item is Doctor) {
                        title = item.name;
                        subtitle = "DOCTOR";
                      } else {
                        title = item.toString();
                        subtitle = "ADD NEW NAME";
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

  Widget _buildMinimizedSpecialOrder() {
    return Positioned(
      right: 0,
      top: 200,
      child: GestureDetector(
        onTap: () => setState(() => _isSpecialOrderMinimized = false),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.green.shade700,
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(25)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(-2, 0),
              )
            ],
          ),
          child: const Center(
            child: Text("🧺", style: TextStyle(fontSize: 24)),
          ),
        ),
      ),
    );
  }

  // CODE MASTER FIX: Debounced footer math to stop keyboard typing lag
  final bool _isBulkUpdating = false;
  void _calculateFooter() {
    if (_isBulkUpdating) return;

    _footerDebouncer.run(() {
      if (!mounted) return;
      
      int subPaise = _items.fold(0, (s, i) => s + TaxCalculator.toPaise(i.total));
      double sub = subPaise / 100.0;

      // We ONLY calculate percentages if the user is actively typing in the Amount box, and vice versa.
      // This prevents the controllers from fighting each other.
      if (_footerDiscAmtFocus.hasFocus) {
        int amtPaise = TaxCalculator.toPaise(double.tryParse(_footerDiscAmtCtrl.text) ?? 0);
        if (subPaise > 0) {
          String pctStr = _fmt((amtPaise * 100.0) / subPaise);
          if (_footerDiscPctCtrl.text != pctStr) _footerDiscPctCtrl.text = pctStr;
        }
      } else {
        double pct = double.tryParse(_footerDiscPctCtrl.text) ?? 0;
        int amtPaise = ((subPaise * pct) / 100.0).round();
        String amtStr = _fmt(amtPaise / 100.0);
        if (_footerDiscAmtCtrl.text != amtStr) _footerDiscAmtCtrl.text = amtStr;
      }

      if (_otherChargeAmtFocus.hasFocus) {
        int amtPaise = TaxCalculator.toPaise(double.tryParse(_otherChargeAmtCtrl.text) ?? 0);
        if (subPaise > 0) {
          String pctStr = _fmt((amtPaise * 100.0) / subPaise);
          if (_otherChargePctCtrl.text != pctStr) _otherChargePctCtrl.text = pctStr;
        }
      } else {
        double pct = double.tryParse(_otherChargePctCtrl.text) ?? 0;
        int amtPaise = ((subPaise * pct) / 100.0).round();
        String amtStr = _fmt(amtPaise / 100.0);
        if (_otherChargeAmtCtrl.text != amtStr) _otherChargeAmtCtrl.text = amtStr;
      }

      int otherAmtPaise = TaxCalculator.toPaise(double.tryParse(_otherChargeAmtCtrl.text) ?? 0);
      int lessCrPaise = TaxCalculator.toPaise(double.tryParse(_salesReturnCtrl.text) ?? 0);
      int discAmtPaise = TaxCalculator.toPaise(double.tryParse(_footerDiscAmtCtrl.text) ?? 0);

      int finalValPaise = subPaise - discAmtPaise + otherAmtPaise - lessCrPaise;
      int roundedGrandTotalPaise = ((finalValPaise / 100.0).round()) * 100;
      int roundOffPaise = roundedGrandTotalPaise - finalValPaise;

      double finalVal = finalValPaise / 100.0;
      double rounded = roundedGrandTotalPaise / 100.0;

      // Only update text controllers if the value actually changed to prevent cursor jumping
      String newSubStr = _fmt(sub);
      String newRoundStr = _fmt(roundOffPaise / 100.0);
      String newNetStr = _fmt(rounded);

      if (_subTotalCtrl.text != newSubStr) _subTotalCtrl.text = newSubStr;
      if (_roundOffCtrl.text != newRoundStr) _roundOffCtrl.text = newRoundStr;
      if (_netTotalCtrl.text != newNetStr) _netTotalCtrl.text = newNetStr;

      _subTotalNotifier.value = sub;
      _grandTotalNotifier.value = rounded;
      _roundOffNotifier.value = rounded - finalVal;
      
      double rcvd = double.tryParse(_rcvdAmtCtrl.text) ?? 0.0;
      if (rcvd > 0) {
        _balanceCtrl.text = _fmt(rcvd - rounded);
        _balanceNotifier.value = rcvd - rounded;
      } else {
        _balanceCtrl.text = "0.00";
        _balanceNotifier.value = 0.0;
      }

      _summaryNotifier.value++;
      _syncToGlobalSession(notify: false);
    });
  }

  Widget _buildFooter() => Container(height: 168, color: const Color(0xFFF1F5F9), padding: const EdgeInsets.all(6), child: Row(children: [
    Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_footerTitle("Recent Entries:", color: Colors.blue.shade800), _footerTableHdr([{'title': 'Entry No', 'flex': 2}, {'title': 'Total', 'flex': 2, 'align': Alignment.centerRight}]), Expanded(child: _buildRecentInvoicesList())] )),
    const SizedBox(width: 8),

    Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_footerTitle(_activeGenericName.isNotEmpty ? "Generic Availability Helper (${_activeGenericName.toUpperCase()}):" : "Generic Availability Helper:", color: Colors.blue.shade800), _footerTableHdr([{'title': 'Medicine Name', 'flex': 4}, {'title': 'Generic Name', 'flex': 4}, {'title': 'Stock', 'flex': 1, 'align': Alignment.centerRight}]), Expanded(child: _buildAlternativesList())])),
    const SizedBox(width: 8),

    Expanded(flex: 4, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_footerTitle("Previous History", color: Colors.blue.shade800), _footerTableHdr([{'title': 'Date', 'flex': 2}, {'title': 'Inv', 'flex': 1}, {'title': 'Qty', 'flex': 1, 'align': Alignment.centerRight}, {'title': 'MRP', 'flex': 2, 'align': Alignment.centerRight}, {'title': 'Rate', 'flex': 2, 'align': Alignment.centerRight}, {'title': 'D%', 'flex': 1, 'align': Alignment.centerRight}]), Expanded(child: _buildProductHistoryList())])),
    const SizedBox(width: 8),

    _buildQuickActions()
  ]));

  void _onGenericAltSelected(Product p) {
    int row = _focusedRowIndex;
    if (row < 0 || row >= _items.length) {
      if (_items.isEmpty) {
        _items.add(SaleItem(product: p));
        row = 0;
      } else if (_items.last.product.name.isNotEmpty) {
        _items.add(SaleItem(product: p));
        row = _items.length - 1;
      } else {
        row = _items.length - 1;
      }
    }

    final item = _items[row];
    item.product = p;
    item.extra = p.name;
    item.mrp = p.mrp;
    item.taxableSP = p.salePrice;
    item.sRate = p.salePrice;
    item.gstPercent = p.gstPercent;

    final ctrl = _getGridCtrl(row, 2, p.name);
    ctrl.text = p.name;

    _onProductSelected(p);

    setState(() {});

    // Focus cursor directly on Batch section (Col 4) and auto-open batch dropdown
    _moveFocus(row, 4, autoOpen: true);
  }

  Widget _buildAlternativesList() {
    if (_footerAlts.isEmpty) {
       return Container(
         decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), color: Colors.white),
         alignment: Alignment.center,
         child: Text(
           _activeGenericName.isNotEmpty
               ? "No Alternatives Found for '${_activeGenericName.toUpperCase()}'"
               : "No Alternatives Found",
           style: const TextStyle(color: Colors.grey, fontSize: 12),
         )
       );
    }

    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), color: Colors.white),
      child: ListView.builder(
        itemCount: _footerAlts.length,
        itemBuilder: (ctx, i) {
          final p = _footerAlts[i];
          bool isEven = i % 2 == 0;
          final genDisplay = p.genericName.isNotEmpty ? p.genericName : _activeGenericName;

          return InkWell(
            onTap: () => _onGenericAltSelected(p),
            child: Container(
              height: 24,
              decoration: BoxDecoration(
                color: isEven ? Colors.white : const Color(0xFFF8F9FA),
                border: Border(bottom: BorderSide(color: Colors.grey.shade200))
              ),
              child: Row(children: [
                Expanded(flex: 4, child: Padding(padding: const EdgeInsets.only(left: 8), child: Text(p.name.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade900), overflow: TextOverflow.ellipsis))),
                Expanded(flex: 4, child: Text(genDisplay.toUpperCase(), style: TextStyle(fontSize: 10, color: Colors.blue.shade700), overflow: TextOverflow.ellipsis)),
                Expanded(flex: 1, child: Container(padding: const EdgeInsets.only(right: 8), alignment: Alignment.centerRight, child: Text(p.stock.toString(), style: const TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.bold))))
              ]),
            ),
          );
        }
      )
    );
  }

  Widget _buildProductHistoryList() {
    if (_productHistory.isEmpty) {
      return Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), color: Colors.white),
        alignment: Alignment.center,
        child: const Text("No History Found", style: TextStyle(color: Colors.grey, fontSize: 12))
      );
    }

    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), color: Colors.white),
      child: ListView.builder(
        itemCount: _productHistory.length,
        itemBuilder: (ctx, i) {
          final h = _productHistory[i];
          String dateStr = "";
          try {
            DateTime dt = DateTime.parse(h['date'].toString());
            dateStr = DateFormat('dd/MM/yy').format(dt);
          } catch (_) {}

          return Container(
            height: 20,
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
            child: Row(children: [
              Expanded(flex: 2, child: Padding(padding: const EdgeInsets.only(left: 4), child: Text(dateStr, style: const TextStyle(fontSize: 9)))),
              Expanded(flex: 1, child: Text(h['entry_no'].toString(), style: const TextStyle(fontSize: 9))),
              Expanded(flex: 1, child: Container(alignment: Alignment.centerRight, child: Text(h['qty'].toString(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))),
              Expanded(flex: 2, child: Container(alignment: Alignment.centerRight, child: Text(double.tryParse(h['mrp'].toString())?.toStringAsFixed(2) ?? "0.00", style: const TextStyle(fontSize: 10)))),
              Expanded(flex: 2, child: Container(alignment: Alignment.centerRight, child: Text(double.tryParse(h['s_rate'].toString())?.toStringAsFixed(2) ?? "0.00", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)))),
              Expanded(flex: 1, child: Container(padding: const EdgeInsets.only(right: 4), alignment: Alignment.centerRight, child: Text(double.tryParse(h['disc_percent'].toString())?.toStringAsFixed(1) ?? "0.0", style: const TextStyle(fontSize: 9, color: Colors.red)))),
            ]),
          );
        },
      ),
    );
  }

  Widget _footerTitle(String title, {Color color = Colors.blue}) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(title, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)));
  Widget _footerTableHdr(List<Map<String, dynamic>> cols) => Container(height: 18, color: const Color(0xFF424242), child: Row(children: cols.map((c) => Expanded(flex: c['flex'] ?? 1, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4), alignment: c['align'] ?? Alignment.centerLeft, child: Text(c['title'], style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))))).toList()));

  Widget _buildRecentInvoicesList() {
    final provider = Provider.of<PharmacyProvider>(context);
    final sales = provider.sales.take(15).toList();

    if (sales.isEmpty) {
      return Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), color: Colors.white),
        alignment: Alignment.center,
        child: const Text("No Recent Entries", style: TextStyle(color: Colors.grey, fontSize: 12))
      );
    }

    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), color: Colors.white),
      child: ListView.builder(
        itemCount: sales.length,
        itemBuilder: (ctx, i) {
          final inv = sales[i];
          return InkWell(
            onTap: () => _openSalesAsWindow(inv.entryNo),
            child: Container(
              height: 20,
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
              child: Row(children: [
                Expanded(flex: 2, child: Padding(padding: const EdgeInsets.only(left: 4), child: Text(inv.entryNo, style: const TextStyle(fontSize: 10)))),
                Expanded(flex: 2, child: Container(padding: const EdgeInsets.only(right: 4), alignment: Alignment.centerRight, child: Text(inv.grandTotal.toStringAsFixed(2), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade800)))),
              ]),
            ),
          );
        },
      ),
    );
  }


  Widget _buildQuickActions() {
    final bool readOnly = _isDeleted;

    return Container(
      width: 280,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _quickRow("Sub Total", _subTotalCtrl, readOnly: true),
          _quickRow("Discount", _footerDiscAmtCtrl, pctCtrl: _footerDiscPctCtrl),
          _quickRow("Sales Return", _salesReturnCtrl, readOnly: false),
          _quickRow("Round Off", _roundOffCtrl, readOnly: true),

          Padding(
            padding: const EdgeInsets.only(bottom: 2, top: 1),
            child: Row(
              children: [
                const Text("Rcvd.Amt", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 22,
                    decoration: BoxDecoration(
                      color: readOnly ? Colors.grey.shade100 : Colors.white,
                      border: Border.all(color: Colors.blue.shade300, width: 1.5),
                      borderRadius: BorderRadius.circular(4)
                    ),
                    child: TextField(
                      controller: _rcvdAmtCtrl,
                      readOnly: readOnly,
                      focusNode: _rcvdAmtFocus,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      onChanged: (_) {
                        _markDirty();
                        _calculateFooter();
                      },
                      onSubmitted: readOnly ? null : (_) => _promptSave(),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
                      decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2)),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Text("Balance", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(4)
                    ),
                    child: TextField(
                      controller: _balanceCtrl,
                      readOnly: true,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.redAccent),
                      decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Grand Total", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                ValueListenableBuilder<double>(
                  valueListenable: _netTotalNotifier,
                  builder: (context, val, _) => Text(
                    val.toStringAsFixed(2),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black)
                  )
                )
              ]
            ),
          )
        ]
      ),
    );
  }

  Widget _quickRow(String label, TextEditingController ctrl, {TextEditingController? pctCtrl, bool readOnly = false}) {
    const bool isLocked = false;
    final bool isReadOnly = readOnly || _isDeleted || isLocked;

    return Padding(
        padding: const EdgeInsets.only(bottom: 1),
        child: Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
              if (pctCtrl != null) ...[
                Container(
                    width: 45, height: 20, decoration: BoxDecoration(color: isReadOnly ? Colors.grey.shade100 : Colors.white, border: Border.all(color: Colors.grey.shade300)),
                    child: TextField(
                        controller: pctCtrl, readOnly: isReadOnly, textAlign: TextAlign.center, cursorColor: Colors.black,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                        onChanged: (_) {
                          _markDirty();
                          _calculateFooter();
                        },
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black),
                        decoration: const InputDecoration(border: InputBorder.none, isDense: true, suffixText: "%", suffixStyle: TextStyle(fontSize: 9))
                    )
                ),
                const SizedBox(width: 4)
              ],
              Container(
                  width: 70, height: 20, decoration: BoxDecoration(color: isReadOnly ? Colors.grey.shade100 : Colors.white, border: Border.all(color: Colors.grey.shade300)),
                  child: TextField(
                      controller: ctrl, readOnly: isReadOnly, cursorColor: Colors.black,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      onChanged: (_) {
                        _markDirty();
                        _calculateFooter();
                      },
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                      decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4))
                  )
              )
            ]
        )
    );
  }

  Widget _buildShortcutLegend() => Container(height: 32, padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: Colors.grey.shade900, border: const Border(top: BorderSide(color: Colors.amber, width: 2))), child: ListView(scrollDirection: Axis.horizontal, children: [_shortcutTag("C+1", "Pur Hist"), _shortcutTag("C+2", "Sal Hist"), _shortcutTag("C+L", "Stock Hist"), _shortcutTag("F2", "New"), _shortcutTag("F3", "Search"), _shortcutTag("F6", "Save"), _shortcutTag("F7", "Cust"), _shortcutTag("F8", "Pay"), _shortcutTag("F9", "Preview"), _shortcutTag("F10", "Invoice"), _shortcutTag("F11", "Hold"), _shortcutTag("F12", "Print"), _shortcutTag("Enter/Tab", "Next"), _shortcutTag("S+Enter", "Prev"), _shortcutTag("Arrows", "Nav"), _shortcutTag("Home/End", "Jump"), _shortcutTag("PgUp/Dn", "Scroll"), _shortcutTag("Del", "Clear"), _shortcutTag("C+Del", "Del Row"), _shortcutTag("Esc", "Close")]));
  Widget _shortcutTag(String key, String label) => Padding(padding: const EdgeInsets.only(right: 15), child: Row(children: [Text(key, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 10)), const SizedBox(width: 4), Text(label, style: const TextStyle(color: Colors.white, fontSize: 10))]));

  void _openSalesAsWindow(String invNo) {
    setState(() => _isDialogOpen = true);
    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) {
        final ValueNotifier<Offset> offsetNotifier = ValueNotifier<Offset>(Offset.zero);
        bool isMinimized = false;
        bool isMaximized = false; // <-- NEW STATE

        return StatefulBuilder(
          builder: (context, setWindowState) {
            // MINIMIZED FLOATING TAB VIEW
            if (isMinimized) {
              return ValueListenableBuilder<Offset>(
                  valueListenable: offsetNotifier,
                  builder: (context, offset, child) {
                    return Transform.translate(
                      offset: offset,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: GestureDetector(
                            onPanUpdate: (d) => offsetNotifier.value += d.delta,
                            child: Material(
                              elevation: 10,
                              borderRadius: BorderRadius.circular(6),
                              color: Colors.blueGrey.shade900,
                              child: Container(
                                width: 250, height: 40,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Row(
                                  children: [
                                    const Icon(Icons.receipt_long, color: Colors.white, size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text("Sales: $invNo", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                                    WindowControlsBar(
                                      onMinimize: () => setWindowState(() => isMinimized = false),
                                      onClose: () => Navigator.pop(ctx),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }
              );
            }

            // FULL DRAGGABLE WINDOW VIEW
            return ValueListenableBuilder<Offset>(
              valueListenable: offsetNotifier,
              builder: (context, offset, child) {
                return Transform.translate(
                  offset: offset,
                  child: child,
                );
              },
              child: Dialog(
                // Remove padding entirely when maximized
                insetPadding: isMaximized ? EdgeInsets.zero : const EdgeInsets.all(30),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isMaximized ? 0 : 8)),
                clipBehavior: Clip.antiAlias,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  // Force full screen dimensions when maximized
                  width: isMaximized ? MediaQuery.of(context).size.width : 1200,
                  height: isMaximized ? MediaQuery.of(context).size.height : 800,
                  child: Column(
                    children: [
                      // === DRAGGABLE OS-STYLE HEADER ===
                      GestureDetector(
                        onPanUpdate: (details) {
                          if (isMaximized) return; // Block dragging if maximized
                          offsetNotifier.value += details.delta;
                        },
                        onDoubleTap: () {
                          // Double tap header to maximize/restore
                          setWindowState(() {
                            isMaximized = !isMaximized;
                            offsetNotifier.value = Offset.zero;
                          });
                        },
                        child: Container(
                          height: 32,
                          color: Colors.blueGrey.shade900,
                          padding: const EdgeInsets.only(left: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.receipt_long, size: 14, color: Colors.white70),
                              const SizedBox(width: 8),
                              Text("Viewing Sales Entry: $invNo", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                              const Spacer(),
                              WindowControlsBar(
                                backgroundColor: Colors.transparent,
                                onMinimize: () => setWindowState(() => isMinimized = true),
                                onMaximize: () => setWindowState(() {
                                  isMaximized = !isMaximized;
                                  offsetNotifier.value = Offset.zero;
                                }),
                                onClose: () => Navigator.pop(ctx),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // === ACTUAL SALES SCREEN ===
                      Expanded(
                        child: SalesScreen(initialInvoiceNo: invNo, isDialog: true),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      if (mounted) setState(() => _isDialogOpen = false);
    });
  }


  // =========================================================================
  // FIND DIALOG
  // =========================================================================
  void _showFindDialog() {
    final TextEditingController findCtrl = TextEditingController();
    final FocusNode findFocusNode = FocusNode();
    setState(() => _isDialogOpen = true);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("Find Invoice", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: SizedBox(
            width: 300,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Enter Entry Number:", style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: findCtrl,
                    focusNode: findFocusNode,
                    autofocus: true,
                    keyboardType: TextInputType.text,
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        Navigator.pop(ctx, val.trim());
                      }
                    },
                    decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                        hintText: "Entry No (Ex: 101 or INV-001)"
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
            ElevatedButton(
              onPressed: () {
                if (findCtrl.text.trim().isNotEmpty) {
                  Navigator.pop(ctx, findCtrl.text.trim());
                }
              },
              child: const Text("SEARCH"),
            ),
          ],
        );
      },
    ).then((val) async {
      if (mounted) setState(() => _isDialogOpen = false);
      if (val != null && val is String) {
        // ---> THE FIX: Protect against losing unsaved edits <---
        if (_isExistingEntry && _isDirty) {
          bool? discard = await _promptDiscardChanges();
          if (discard != true) return; // User chose to stay
        }

        // Use a slight delay to ensure dialog is fully closed and focus is returned
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _loadSaleData(val);
        });
      }
      // Delay disposal to avoid "used after dispose" errors during the pop animation
      Future.delayed(const Duration(seconds: 1), () {
        findFocusNode.dispose();
        findCtrl.dispose();
      });
    });
  }

  void _openStockMovementDrawer(String productName) {
    if (productName.trim().isEmpty) return;
    _isDialogOpen = true;
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);

    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: SizedBox(
            width: 750,
            height: 480,
            child: Column(
              children: [
                Container(
                  height: 40,
                  color: const Color(0xFF1E293B),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.history, color: Colors.amber, size: 18),
                      const SizedBox(width: 8),
                      Text("STOCK MOVEMENT HISTORY: ${productName.toUpperCase()}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 18),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FutureBuilder<Map<String, dynamic>>(
                    future: pharma.generateStockLedger(productName, DateTime.now().subtract(const Duration(days: 365)), DateTime.now()),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final data = snapshot.data ?? {};
                      final entries = List<Map<String, dynamic>>.from(data['entries'] ?? []);
                      if (entries.isEmpty) {
                        return const Center(child: Text("No stock movements recorded.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)));
                      }
                      final displayEntries = entries.length > 20 ? entries.sublist(entries.length - 20) : entries;

                      return Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            color: const Color(0xFFF1F5F9),
                            child: Row(
                              children: [
                                Text("Opening: ${data['opening'] ?? 0}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 16),
                                Text("Current Balance: ${data['closing'] ?? 0}", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                                const Spacer(),
                                Text("Showing last ${displayEntries.length} movements", style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              child: DataTable(
                                headingRowHeight: 32,
                                dataRowHeight: 34,
                                columns: const [
                                  DataColumn(label: Text("DATE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text("TYPE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text("REF NO", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text("BATCH", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text("IN", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text("OUT", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text("BAL", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                ],
                                rows: displayEntries.reversed.map((e) {
                                  final inQty = (e['in_qty'] as num?)?.toInt() ?? 0;
                                  final outQty = (e['out_qty'] as num?)?.toInt() ?? 0;
                                  return DataRow(cells: [
                                    DataCell(Text(e['date']?.toString() ?? '', style: const TextStyle(fontSize: 11))),
                                    DataCell(Text(e['type']?.toString() ?? '', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: inQty > 0 ? Colors.green.shade800 : Colors.orange.shade900))),
                                    DataCell(Text(e['ref_no']?.toString() ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                                    DataCell(Text(e['batch']?.toString() ?? '', style: const TextStyle(fontSize: 11, fontFamily: 'monospace'))),
                                    DataCell(Text(inQty > 0 ? "+$inQty" : "-", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade700))),
                                    DataCell(Text(outQty > 0 ? "-$outQty" : "-", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade700))),
                                    DataCell(Text("${e['balance'] ?? 0}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                  ]);
                                }).toList(),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) => setState(() => _isDialogOpen = false));
  }



  // =========================================================================
  // F3 GENERIC / CONTENT-WISE SEARCH DIALOG (AUTO-FILL BILLING)
  // =========================================================================
  void _openGenericSearchDialog() {
    _isDialogOpen = true;
    final TextEditingController searchCtrl = TextEditingController();
    final FocusNode searchFocusNode = FocusNode();
    final ScrollController listScrollCtrl = ScrollController();
    final SearchDebouncer searchDebouncer = SearchDebouncer(milliseconds: 80);

    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    // Master map for fast generic fallback lookup built ONCE per dialog open
    final Map<String, String> masterGenMap = {};
    for (var m in provider.productMaster) {
      final gen = m.genericName.trim();
      if (gen.isNotEmpty) {
        masterGenMap[m.id] = gen;
        masterGenMap[m.name.trim().toLowerCase()] = gen;
      }
    }
    for (var g in provider.genericMaster) {
      if (g.name.trim().isNotEmpty) {
        masterGenMap[g.id] = g.name.trim();
      }
    }

    int selectedIdx = 0;
    List<Product> results = [];
    Offset dialogOffset = Offset.zero;

    // Filter and Sort states
    bool showZeroStock = false;
    String selectedCategory = "ALL";
    String sortColumn = ""; // "name", "generic", "category", "cutStrip", "rack", "batch", "expiry", "stock", "mrp", "rate"
    bool sortAscending = true;

    // Helper functions for segment matching, content count & expiry
    List<String> getGenericSegments(String genName) {
      if (genName.trim().isEmpty) return [];
      return genName
          .split(RegExp(r'[-+/,]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    int getGenericContentCount(String genName) {
      final segs = getGenericSegments(genName);
      return segs.isEmpty ? 1 : segs.length;
    }

    bool matchesGenericSegments(String genName, String query) {
      final segs = getGenericSegments(genName);
      if (segs.isEmpty) return false;
      for (var seg in segs) {
        if (seg.toLowerCase().startsWith(query)) return true;
      }
      return false;
    }

    bool matchesWordStart(String text, String q) {
      if (text.trim().isEmpty || q.isEmpty) return false;
      final clean = text.trim().toLowerCase();
      if (clean.startsWith(q)) return true;
      final words = clean.split(RegExp(r'\s+'));
      for (var w in words) {
        if (w.startsWith(q)) return true;
      }
      return false;
    }

    bool matchesBatchStart(String batch, String q) {
      if (batch.trim().isEmpty || q.isEmpty) return false;
      return batch.trim().toLowerCase().startsWith(q);
    }

    bool isNearExpiry(String expiryStr) {
      if (expiryStr.trim().isEmpty) return false;
      try {
        final exp = expiryStr.trim();
        DateTime expDate;
        if (exp.contains('/')) {
          final parts = exp.split('/');
          if (parts.length == 2) {
            int month = int.tryParse(parts[0]) ?? 1;
            int year = int.tryParse(parts[1]) ?? DateTime.now().year;
            if (year < 100) year += 2000;
            expDate = DateTime(year, month + 1, 0);
          } else {
            return false;
          }
        } else if (exp.contains('-')) {
          expDate = DateTime.tryParse(exp) ?? DateTime.now().add(const Duration(days: 365));
        } else {
          return false;
        }
        final threshold = DateTime.now().add(const Duration(days: 180));
        return expDate.isBefore(threshold);
      } catch (_) {
        return false;
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (searchFocusNode.canRequestFocus) {
        searchFocusNode.requestFocus();
      }
    });

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Generic Search",
      barrierColor: Colors.black38,
      transitionDuration: Duration.zero,
      pageBuilder: (ctx, anim1, anim2) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            void performSearch(String q) {
              final query = q.trim().toLowerCase();
              if (query.isEmpty) {
                setDialogState(() {
                  results = [];
                  selectedIdx = 0;
                });
                return;
              }

              final List<Product> matched = [];
              final Set<String> seenKeys = {};
              final Set<String> matchedStockIds = {};
              final Set<String> matchedStockNames = {};

              // 1. Search live stock batches first
              for (var p in provider.products) {
                if (!showZeroStock && p.stock <= 0) continue;

                final nameLower = p.name.trim().toLowerCase();
                String genLower = p.genericName.trim().toLowerCase();
                if (genLower.isEmpty) {
                  genLower = (masterGenMap[p.id] ?? masterGenMap[nameLower] ?? "").toLowerCase();
                }

                final bool matchesName = matchesWordStart(nameLower, query);
                final bool matchesGenSegment = matchesGenericSegments(genLower, query);
                final bool matchesBatch = matchesBatchStart(p.batch, query);

                if (matchesName || matchesGenSegment || matchesBatch) {
                  final key = "${p.id}_${p.batch}_${p.expiry}_${p.mrp}_${p.salePrice}";
                  if (!seenKeys.contains(key)) {
                    seenKeys.add(key);
                    matchedStockIds.add(p.id);
                    matchedStockNames.add(nameLower);

                    final resolvedGen = p.genericName.trim().isNotEmpty
                        ? p.genericName.trim()
                        : (masterGenMap[p.id] ?? masterGenMap[nameLower] ?? "");

                    matched.add(Product(
                      id: p.id,
                      name: p.name,
                      batch: p.batch,
                      expiry: p.expiry,
                      packSize: p.packSize,
                      mrp: p.mrp,
                      salePrice: p.salePrice,
                      purchaseRate: p.purchaseRate,
                      landingCost: p.landingCost,
                      gstPercent: p.gstPercent,
                      rack: p.rack,
                      category: p.category.trim().isNotEmpty ? p.category.trim() : "General",
                      manufacturer: p.manufacturer,
                      genericName: resolvedGen,
                      stock: p.stock,
                    ));
                  }
                }
              }

              // 2. Also search product master (for zero stock or unbatched)
              for (var m in provider.productMaster) {
                if (!showZeroStock && m.stock <= 0) continue;

                final nameLower = m.name.trim().toLowerCase();
                final genLower = m.genericName.trim().toLowerCase();

                final bool matchesName = matchesWordStart(nameLower, query);
                final bool matchesGenSegment = matchesGenericSegments(genLower, query);

                if (matchesName || matchesGenSegment) {
                  final bool alreadyHasStockRow = matchedStockIds.contains(m.id) || matchedStockNames.contains(nameLower);
                  if (!alreadyHasStockRow) {
                    final key = "MASTER_${m.id}";
                    if (!seenKeys.contains(key)) {
                      seenKeys.add(key);
                      matched.add(m);
                    }
                  }
                }
              }

              // Apply Category Filter if selected Category != "ALL"
              List<Product> filtered = matched;
              if (selectedCategory != "ALL") {
                filtered = matched.where((p) {
                  final catUpper = p.category.trim().toUpperCase();
                  if (selectedCategory == "GENERIC") {
                    return catUpper.contains("GEN");
                  } else if (selectedCategory == "BRAND") {
                    return !catUpper.contains("GEN");
                  } else {
                    return catUpper.contains(selectedCategory.toUpperCase());
                  }
                }).toList();
              }

              // Sorting
              if (sortColumn.isNotEmpty) {
                filtered.sort((a, b) {
                  int cmp = 0;
                  switch (sortColumn) {
                    case "name":
                      cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
                      break;
                    case "generic":
                      cmp = a.genericName.toLowerCase().compareTo(b.genericName.toLowerCase());
                      break;
                    case "category":
                      cmp = a.category.toLowerCase().compareTo(b.category.toLowerCase());
                      break;
                    case "cutStrip":
                      bool cutA = a.packSize > 1 && a.stock > 0 && (a.stock % a.packSize > 0);
                      bool cutB = b.packSize > 1 && b.stock > 0 && (b.stock % b.packSize > 0);
                      cmp = (cutA == cutB) ? 0 : (cutA ? -1 : 1);
                      break;
                    case "rack":
                      cmp = a.rack.toLowerCase().compareTo(b.rack.toLowerCase());
                      break;
                    case "batch":
                      cmp = a.batch.toLowerCase().compareTo(b.batch.toLowerCase());
                      break;
                    case "expiry":
                      cmp = a.expiry.compareTo(b.expiry);
                      break;
                    case "stock":
                      cmp = a.stock.compareTo(b.stock);
                      break;
                    case "mrp":
                      cmp = a.mrp.compareTo(b.mrp);
                      break;
                    case "rate":
                      cmp = a.salePrice.compareTo(b.salePrice);
                      break;
                  }
                  return sortAscending ? cmp : -cmp;
                });
              } else {
                // Priority Default Sorting Rules:
                // 1. Stock available (stock > 0 first)
                // 2. Generic product priority (category contains GEN / GENERIC first)
                // 3. Salt content count (1 salt -> 2 salts -> 3 salts)
                // 4. Stock quantity descending
                filtered.sort((a, b) {
                  bool aHasStock = a.stock > 0;
                  bool bHasStock = b.stock > 0;
                  if (aHasStock != bHasStock) return aHasStock ? -1 : 1;

                  bool aIsGen = a.category.trim().toUpperCase().contains("GEN");
                  bool bIsGen = b.category.trim().toUpperCase().contains("GEN");
                  if (aIsGen != bIsGen) return aIsGen ? -1 : 1;

                  int aCount = getGenericContentCount(a.genericName);
                  int bCount = getGenericContentCount(b.genericName);
                  if (aCount != bCount) return aCount.compareTo(bCount);

                  return b.stock.compareTo(a.stock);
                });
              }

              setDialogState(() {
                results = filtered.take(150).toList();
                selectedIdx = 0;
              });
            }

            void toggleSort(String col) {
              setDialogState(() {
                if (sortColumn == col) {
                  sortAscending = !sortAscending;
                } else {
                  sortColumn = col;
                  sortAscending = true;
                }
              });
              performSearch(searchCtrl.text);
            }

            void selectItemAndClose(Product p) {
              Navigator.of(dialogCtx).pop();
              _isDialogOpen = false;

              int targetRow = _focusedRowIndex;
              if (targetRow < 0 || targetRow > _items.length) {
                targetRow = _items.length;
              }

              if (p.batch.isNotEmpty) {
                _handleBatchSelection(row: targetRow, product: p);
              } else {
                _onProductSelected(p);
              }
            }

            void scrollSelectedIntoView(int idx) {
              if (!listScrollCtrl.hasClients) return;
              double itemHeight = 32.0;
              double targetOffset = idx * itemHeight;
              double currentOffset = listScrollCtrl.offset;
              double viewportHeight = 320.0;

              if (targetOffset < currentOffset) {
                listScrollCtrl.jumpTo(targetOffset);
              } else if (targetOffset + itemHeight > currentOffset + viewportHeight) {
                listScrollCtrl.jumpTo(targetOffset + itemHeight - viewportHeight);
              }
            }

            Widget buildHeaderCell(String label, String col, {int flex = 1, TextAlign align = TextAlign.left, Color textColor = Colors.white}) {
              final bool isActive = sortColumn == col;
              MainAxisAlignment mainAlign = MainAxisAlignment.start;
              if (align == TextAlign.right) {
                mainAlign = MainAxisAlignment.end;
              } else if (align == TextAlign.center) {
                mainAlign = MainAxisAlignment.center;
              }

              return Expanded(
                flex: flex,
                child: InkWell(
                  onTap: () => toggleSort(col),
                  child: Row(
                    mainAxisAlignment: mainAlign,
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          textAlign: align,
                          style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isActive)
                        Icon(
                          sortAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                          color: Colors.amber,
                          size: 16,
                        ),
                    ],
                  ),
                ),
              );
            }

            Widget buildCutStripCell(Product p) {
              if (p.packSize <= 1) {
                return const Center(
                  child: Text("-", textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.black87)),
                );
              }
              final int fullStrips = p.stock > 0 ? (p.stock ~/ p.packSize) : 0;
              final int looseUnits = p.stock > 0 ? (p.stock % p.packSize) : 0;

              return Center(
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    children: [
                      TextSpan(
                        text: "$fullStrips ",
                        style: const TextStyle(color: Colors.black87),
                      ),
                      const TextSpan(
                        text: "/ ",
                        style: TextStyle(color: Colors.black87),
                      ),
                      TextSpan(
                        text: "$looseUnits",
                        style: TextStyle(
                          color: looseUnits > 0 ? Colors.red.shade700 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Transform.translate(
              offset: dialogOffset,
              child: Dialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                clipBehavior: Clip.antiAlias,
                elevation: 16,
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.escape) {
                        Navigator.of(dialogCtx).pop();
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        if (results.isNotEmpty) {
                          setDialogState(() {
                            selectedIdx = (selectedIdx + 1).clamp(0, results.length - 1);
                          });
                          scrollSelectedIntoView(selectedIdx);
                        }
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        if (results.isNotEmpty) {
                          setDialogState(() {
                            selectedIdx = (selectedIdx - 1).clamp(0, results.length - 1);
                          });
                          scrollSelectedIntoView(selectedIdx);
                        }
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.enter) {
                        if (results.isNotEmpty && selectedIdx >= 0 && selectedIdx < results.length) {
                          selectItemAndClose(results[selectedIdx]);
                        }
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Container(
                    width: 1060,
                    height: 540,
                    color: Colors.white,
                    child: Column(
                      children: [
                        // Header Bar
                        GestureDetector(
                          onPanUpdate: (details) {
                            setDialogState(() {
                              dialogOffset += details.delta;
                            });
                          },
                          child: Container(
                            height: 42,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.science_rounded, color: Colors.amber, size: 20),
                                const SizedBox(width: 8),
                                const Text(
                                  "F3: Generic & Content-Wise Product Search",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Row(
                                  children: [
                                    SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: Checkbox(
                                        value: showZeroStock,
                                        activeColor: Colors.amber,
                                        checkColor: Colors.black,
                                        onChanged: (val) {
                                          setDialogState(() {
                                            showZeroStock = val ?? false;
                                          });
                                          performSearch(searchCtrl.text);
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text("Show Zero Stock", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white24,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    "Press ESC to Close | [↑/↓] Navigate | [ENTER] Auto-Fill Bill",
                                    style: TextStyle(color: Colors.white, fontSize: 11, fontStyle: FontStyle.italic),
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white, size: 18),
                                  onPressed: () => Navigator.of(dialogCtx).pop(),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Search Input Field
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: TextField(
                            controller: searchCtrl,
                            focusNode: searchFocusNode,
                            autofocus: true,
                            onChanged: (val) {
                              searchDebouncer.run(() => performSearch(val));
                            },
                            decoration: InputDecoration(
                              hintText: "Type Generic Composition / Salt (e.g. Paracetamol, Cefixime, Pantoprazole) or Brand Name...",
                              prefixIcon: const Icon(Icons.search, color: Colors.blue),
                              suffixIcon: searchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () {
                                        searchCtrl.clear();
                                        performSearch("");
                                      },
                                    )
                                  : null,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: Colors.blue, width: 2),
                              ),
                            ),
                          ),
                        ),

                        // Category Filter Bar
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          color: const Color(0xFFEBF3FA),
                          child: Row(
                            children: [
                              const Text("Category: ", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                              const SizedBox(width: 6),
                              ...["ALL", "GENERIC", "BRAND", "COUNTER", "TABLETS", "SYRUPS"].map((cat) {
                                final bool isSel = selectedCategory == cat;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: InkWell(
                                    onTap: () {
                                      setDialogState(() {
                                        selectedCategory = cat;
                                      });
                                      performSearch(searchCtrl.text);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isSel ? Colors.blue.shade700 : Colors.white,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: isSel ? Colors.blue.shade800 : Colors.grey.shade300),
                                      ),
                                      child: Text(
                                        cat,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isSel ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),

                        // Results Header Table
                        Container(
                          height: 28,
                          color: const Color(0xFF1565C0),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              buildHeaderCell("Medicine Name (Brand)", "name", flex: 3),
                              buildHeaderCell("Generic Composition (Salt)", "generic", flex: 3, textColor: Colors.white),
                              buildHeaderCell("Category", "category", flex: 1),
                              buildHeaderCell("Cut Strip", "cutStrip", flex: 1, align: TextAlign.center),
                              buildHeaderCell("Rack", "rack", flex: 1),
                              buildHeaderCell("Batch No", "batch", flex: 2),
                              buildHeaderCell("Expiry", "expiry", flex: 1),
                              buildHeaderCell("Stock", "stock", flex: 1, align: TextAlign.right),
                              buildHeaderCell("MRP", "mrp", flex: 1, align: TextAlign.right),
                              buildHeaderCell("Rate", "rate", flex: 1, align: TextAlign.right),
                            ],
                          ),
                        ),

                        // Results List
                        Expanded(
                          child: results.isEmpty
                              ? Container(
                                  color: const Color(0xFFF8F9FA),
                                  alignment: Alignment.center,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.science_rounded, size: 48, color: Colors.blue.shade200),
                                      const SizedBox(height: 8),
                                      Text(
                                        searchCtrl.text.isEmpty
                                            ? "Type generic composition (salt name) or medicine brand above to search..."
                                            : "No medicines found matching '${searchCtrl.text}'",
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  controller: listScrollCtrl,
                                  itemCount: results.length,
                                  itemBuilder: (ctx, idx) {
                                    final p = results[idx];
                                    final bool isSelected = idx == selectedIdx;
                                    final bool hasStock = p.stock > 0;
                                    final bool nearExp = isNearExpiry(p.expiry);
                                    final bool isGenCategory = p.category.trim().toUpperCase().contains("GEN");

                                    return InkWell(
                                      onTap: () {
                                        setDialogState(() => selectedIdx = idx);
                                      },
                                      onDoubleTap: () => selectItemAndClose(p),
                                      child: Container(
                                        height: 32,
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? Colors.blue.shade100
                                              : (idx % 2 == 0 ? Colors.white : const Color(0xFFF5F7FA)),
                                          border: Border(
                                            bottom: BorderSide(color: Colors.grey.shade200),
                                            left: isSelected
                                                ? const BorderSide(color: Colors.blue, width: 4)
                                                : BorderSide.none,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              flex: 3,
                                              child: Text(
                                                p.name.toUpperCase(),
                                                style: TextStyle(
                                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                                  fontSize: 11,
                                                  color: Colors.black87,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Expanded(
                                              flex: 3,
                                              child: Text(
                                                p.genericName.isNotEmpty ? p.genericName.toUpperCase() : "-",
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11,
                                                  color: Colors.black87,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Expanded(
                                              flex: 1,
                                              child: Text(
                                                p.category.toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: isGenCategory ? Colors.green.shade700 : Colors.black87,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Expanded(
                                              flex: 1,
                                              child: buildCutStripCell(p),
                                            ),
                                            Expanded(
                                              flex: 1,
                                              child: Text(
                                                p.rack.isNotEmpty ? p.rack : "-",
                                                style: const TextStyle(fontSize: 10, color: Colors.black87),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                p.batch.isNotEmpty ? _cleanBatch(p.batch) : "-",
                                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 1,
                                              child: Text(
                                                p.expiry.isNotEmpty ? p.expiry : "-",
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: nearExp ? FontWeight.bold : FontWeight.normal,
                                                  color: nearExp ? Colors.red.shade700 : Colors.black87,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 1,
                                              child: Text(
                                                p.stock.toString(),
                                                textAlign: TextAlign.right,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 1,
                                              child: Text(
                                                p.mrp > 0 ? p.mrp.toStringAsFixed(2) : "-",
                                                textAlign: TextAlign.right,
                                                style: const TextStyle(fontSize: 10, color: Colors.black87),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 1,
                                              child: Text(
                                                p.salePrice > 0 ? p.salePrice.toStringAsFixed(2) : (p.mrp > 0 ? p.mrp.toStringAsFixed(2) : "-"),
                                                textAlign: TextAlign.right,
                                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),

                        // Dialog Footer Actions
                        Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          color: Colors.grey.shade100,
                          child: Row(
                            children: [
                              Text(
                                "Total Matching: ${results.length} items",
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                icon: const Icon(Icons.close, size: 16),
                                label: const Text("Cancel (ESC)"),
                                onPressed: () => Navigator.of(dialogCtx).pop(),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.check_circle, size: 16),
                                label: const Text("Select & Auto-Fill (ENTER)"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade700,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () {
                                  if (results.isNotEmpty && selectedIdx >= 0 && selectedIdx < results.length) {
                                    selectItemAndClose(results[selectedIdx]);
                                  }
                                },
                              ),
                            ],
                          ),
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
    ).then((_) {
      searchDebouncer.dispose();
      searchFocusNode.dispose();
      searchCtrl.dispose();
      listScrollCtrl.dispose();
      _isDialogOpen = false;
    });
  }

  // =========================================================================
  // F2 SALES HISTORY DIALOG
  // =========================================================================
  void _openHistoryWindow(String productName, bool isSales) {
    if (productName.trim().isEmpty) return;

    _isDialogOpen = true;
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
    ).then((_) {
      if (mounted) setState(() => _isDialogOpen = false);
    });
  }

  Future<void> _showH1DrugWarningDialog(String productName, String schedule) async {
    AppSounds.playError(); // Play alert sound

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Colors.red.shade50,
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade900, size: 28),
            const SizedBox(width: 10),
            Text("SCHEDULE $schedule DRUG ALERT", style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  productName.toUpperCase(),
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.red.shade900),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "This medicine falls under Schedule H1/H regulations.\n\n• Mandatory prescription required.\n• Ensure Patient Name, Doctor Name, and Prescribed Quantity are correctly logged.",
                style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
              ),
              const SizedBox(height: 12),
              const Text(
                "Press ENTER to acknowledge and continue billing.",
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade800,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              // Automatically focus the Doctor field to capture prescription info if needed
              if (_doctorCtrl.text == "D1" || _doctorCtrl.text.isEmpty) {
                _doctorFocus.requestFocus();
              }
            },
            child: const Text("ACKNOWLEDGE & CONTINUE (ENTER)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

}

class _ResizableHdr extends StatelessWidget {
  final int index;
  final String title;
  final String? tooltip;
  final Map<int, double> widths;
  final Function(double) onResize;
  final TextAlign align;
  final VoidCallback? onTap;

  const _ResizableHdr(this.index, this.title, this.widths, {this.tooltip, required this.onResize, this.align = TextAlign.left, this.onTap});

  @override
  Widget build(BuildContext context) {
    final String msg = tooltip ?? title;
    Widget child = Container(
      width: widths[index],
      decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.white24, width: 0.5))),
      child: Row(children: [
        Expanded(
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: align == TextAlign.left
                  ? Alignment.centerLeft
                  : (align == TextAlign.center ? Alignment.center : Alignment.centerRight),
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (details) => onResize((widths[index]! + details.delta.dx).clamp(20.0, 800.0)),
            child: Container(width: 4, color: Colors.transparent),
          ),
        ),
      ]),
    );

    if (msg.isNotEmpty) {
      child = ERPTooltip(message: msg, child: child);
    }
    return child;
  }
}

class _Hdr extends StatelessWidget {
  final String title; final String? tooltip; final double? width; final int? flex; final TextAlign align;
  const _Hdr(this.title, {this.tooltip, this.width, this.flex, this.align = TextAlign.left});
  @override Widget build(BuildContext context) { 
    final String msg = tooltip ?? title;
    Widget child = Container(width: width, alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.center ? Alignment.center : Alignment.centerRight), padding: const EdgeInsets.symmetric(horizontal: 8), decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.white24, width: 0.5))), child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold))); 
    if (msg.isNotEmpty) child = ERPTooltip(message: msg, child: child);
    return flex != null ? Expanded(flex: flex!, child: child) : child; 
  }
}

class _GridCell extends StatelessWidget {
  final String text; final double? width; final int? flex; final TextAlign align; final Color? color; final FontWeight? fontWeight; final Color? bgColor;
  const _GridCell(this.text, {this.width, this.flex, this.align = TextAlign.left, this.color, this.fontWeight, this.bgColor});
  @override Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Widget child = Container(width: width, alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.center ? Alignment.center : Alignment.centerRight), padding: const EdgeInsets.symmetric(horizontal: 6), decoration: BoxDecoration(color: bgColor, border: Border(right: BorderSide(color: c.border, width: 0.5))), child: Text(text, style: TextStyle(fontSize: 12, color: color ?? c.primaryText, fontWeight: fontWeight ?? FontWeight.normal), overflow: TextOverflow.ellipsis));
    return flex != null ? Expanded(flex: flex!, child: child) : child;
  }
}

class AnimatedMobileOrdersBtn extends StatefulWidget {
  final VoidCallback onTap;
  final bool hasNewNotification; // <--- ADDED THIS

  const AnimatedMobileOrdersBtn({
    super.key,
    required this.onTap,
    this.hasNewNotification = false, // Default is false
  });

  @override
  State<AnimatedMobileOrdersBtn> createState() => _AnimatedMobileOrdersBtnState();
}

class _AnimatedMobileOrdersBtnState extends State<AnimatedMobileOrdersBtn> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Start pulsing if there is a notification on load
    if (widget.hasNewNotification) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.value = 1.0; // Keep dot solid if no new alert
    }
  }

  // THIS IS THE MAGIC: It listens for changes from your backend/provider
  @override
  void didUpdateWidget(AnimatedMobileOrdersBtn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasNewNotification != oldWidget.hasNewNotification) {
      if (widget.hasNewNotification) {
        _pulseController.repeat(reverse: true); // Start pulsing
      } else {
        _pulseController.stop();
        _pulseController.value = 1.0; // Stop pulsing and make solid
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.only(left: 20),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          border: Border.all(color: Colors.red.shade200),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(Icons.phone_android, size: 18, color: Colors.red.shade800),
                Positioned(
                  right: -2,
                  top: -2,
                  child: FadeTransition(
                    opacity: _pulseController,
                    child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle
                        )
                    ),
                  ),
                )
              ],
            ),
            const SizedBox(width: 8),
            Text(
                "Mobile Orders",
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade900
                )
            ),
          ],
        ),
      ),
    );
  }
}