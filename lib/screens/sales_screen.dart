import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import '../services/pdf_worker_service.dart';
import '../services/print_spooler_service.dart';
import '../services/whatsapp_service.dart';
import '../services/lan_sync_service.dart';
import '../services/sync_event_bus.dart';
import '../services/server_config_service.dart';
import '../services/supabase_sync_service.dart';
import '../services/delta_sync_service.dart';
import '../services/app_notification_service.dart';
import '../database/db_helper.dart';

// Providers & Controllers
import '../providers/pharmacy_provider.dart';
import '../providers/app_provider.dart';

// Models & Utils
import '../models/product_ranking.dart';
import '../utils/tax_calculator.dart';
import '../utils/theme_constants.dart';
import '../utils/app_dialogs.dart';
import '../utils/app_formatters.dart';
import '../utils/app_logger.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/erp_tooltip.dart';
import '../widgets/fluent_nav_button.dart';
import '../utils/app_sounds.dart';
import '../utils/printer_service.dart';
import '../utils/invoice_pdf_generator.dart';
import '../utils/search_debouncer.dart';
import '../utils/unsaved_handler.dart';

// Widgets & Sub-components
import '../widgets/pin_unlock_dialog.dart';
import '../widgets/schedule_h1_compliance_dialog.dart';
import '../widgets/sales/wholesale_availability_dialog.dart';
import '../widgets/sales/dynamic_upi_qr_dialog.dart';
import '../widgets/erp_grid_text_field.dart';
import '../windows/window_spawner.dart';







class SalesScreen extends StatefulWidget {
  final String? initialInvoiceNo;
  final String? highlightProduct;
  final bool isDialog;
  const SalesScreen({super.key, this.initialInvoiceNo, this.highlightProduct, this.isDialog = false});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> implements UnsavedHandler {
  final Set<int> _highlightedRowIndices = {};

  // Variables for Headless Barcode Scanning
  String _barcodeBuffer = "";
  DateTime _lastKeyPress = DateTime.now();

  // Focus nodes to jump around with Hotkeys
  final FocusNode _itemSearchFocusNode = FocusNode();

  final List<SaleItem> _items = [];
  String _entryNo = "";
  String _rawEntryNo = "";
  final TextEditingController _entryNoCtrl = TextEditingController();
  bool _isBlankRecord = false;
  Timer? _draftTimer;
  String _customerAcc = "Cash";
  String _selectedAgent = "";
  int _lastSyncedSessionIdx = -1;
  String _lastYear = "";
  String _activeNotificationTab = "none";
  bool _isNotificationHubMinimized = false;
  String _drawerSearchQuery = "";
  final TextEditingController _drawerSearchCtrl = TextEditingController();
  String _orderFilter = "PENDING";

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
  bool _isImported = false; // NEW: Tracks if record was imported from historical data
  bool _isResetting = false; // Prevents recursive re-entrant reset loops
  bool _hasNewMobileOrder = false;
  bool _showProfitColumn = false; 
  SaleInvoice? _originalLoadedInvoice; 
  String _loadedInvoiceUpdatedAt = "";
  final Map<SaleItem, Map<String, dynamic>> _originalItemSnapshots = {};
  bool _highlightEdits = false;

  // ---> Real-Time Edit Highlighting Theme (Soft Amber & Soft Green) <---
  static const Color _editHighlightBg = Color(0xFFFEF3C7); // Soft Amber fill
  static const Color _editHighlightBorder = Color(0xFFF59E0B); // Amber border outline

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
  final TextEditingController _specialSearchQtyCtrl = TextEditingController(text: "1");
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
  final ScrollController _tierListScrollCtrl = ScrollController();
  final ScrollController _notifListScrollCtrl = ScrollController();

  final Map<int, double> _colWidths = {
    0: 35, 1: 75, 2: 280, 3: 90, 4: 140, 5: 60, 6: 60, 7: 60, 8: 60,
    9: 80, 10: 80, 11: 60, 12: 80, 13: 50, 14: 100, 15: 80, 16: 48,
  };

  bool _hasCustomColWidths = false;
  bool _isLayoutReady = true;

  Future<void> _loadColumnWidths() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final String? jsonStr = prefs.getString('sales_col_widths');
      if (jsonStr != null) {
        final Map<String, dynamic> decoded = jsonDecode(jsonStr);
        if (mounted) {
          setState(() {
            decoded.forEach((key, value) {
              int idx = int.parse(key);
              if (value is num) {
                _colWidths[idx] = value.toDouble();
              }
            });
            _hasCustomColWidths = true;
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading column widths: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLayoutReady = true;
        });
      }
    }
  }

  Timer? _saveColWidthsTimer;

  void _debouncedSaveColumnWidths() {
    _saveColWidthsTimer?.cancel();
    _saveColWidthsTimer = Timer(const Duration(milliseconds: 300), () {
      _saveColumnWidths();
    });
  }

  Future<void> _saveColumnWidths() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, double> toSave = {};
      _colWidths.forEach((k, v) => toSave[k.toString()] = v);
      await prefs.setString('sales_col_widths', jsonEncode(toSave));
    } catch (e) {
      debugPrint("Error saving column widths: $e");
    }
  }

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
  bool _isPatientTyping = false;
  bool _isDoctorTyping = false;
  final FocusNode _doctorRegNoFocus = FocusNode();
  final FocusNode _daysFocus = FocusNode();
  final FocusNode _specialSearchFocus = FocusNode();
  final FocusNode _specialSearchQtyFocus = FocusNode();
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
  final bool _enableAutoRoundOff = true;

  String _fmt(double val) => val.toStringAsFixed(2);

  int get _focusedRowIndex => _focusNotifier.value?.row ?? -1;
  int get _focusedColIndex => _focusNotifier.value?.col ?? 0;

  final LayerLink _searchLayer = LayerLink();
  final LayerLink _batchLayer = LayerLink();
  final LayerLink _patientLayer = LayerLink();
  final LayerLink _doctorLayer = LayerLink();
  final LayerLink _specialCustomerLayer = LayerLink();

  final ValueNotifier<List<Product>> _searchList = ValueNotifier([]);
  final ValueNotifier<List<Product>> _batchList = ValueNotifier([]);
  final ValueNotifier<List<Product>> _specialSearchList = ValueNotifier([]);
  final ValueNotifier<List<dynamic>> _patientSearchList = ValueNotifier([]);
  final ValueNotifier<List<dynamic>> _doctorSearchList = ValueNotifier([]);
  final ValueNotifier<int> _searchIdx = ValueNotifier(0);

  Timer? _scrollTimer;
  Timer? _timeTimer;
  final SearchDebouncer _productSearchDebouncer = SearchDebouncer(milliseconds: 100);
  final SearchDebouncer _historyDebouncer = SearchDebouncer(milliseconds: 200);
  final SearchDebouncer _footerDebouncer = SearchDebouncer(milliseconds: 50);
  final SearchDebouncer _footerUpdateDebouncer = SearchDebouncer(milliseconds: 200);
  final SearchDebouncer _barcodeDebouncer = SearchDebouncer(milliseconds: 80);
  final ValueNotifier<String> _timeNotifier = ValueNotifier<String>("");
  bool _lastDraftSavedStateDirty = true;
  bool _isRcvdAmtConfirmed = false;

  bool _isLoading = false;
  bool _isNavigating = false; // Multi-tap and rapid navigation debounce lock
  bool _isSaving = false; // ---> Hard guard against rapid double-clicks & hotkey spam
  bool _isDeleting = false;
  String? _cachedValidationError; // ---> Eager reactive validation cache for 0ms save overhead
  final FocusNode _dummyFocusNode = FocusNode();
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
    String trimmed = expiryStr.trim();
    if (trimmed.isEmpty || trimmed == "--/--" || !trimmed.contains('/')) {
      return Colors.white;
    }
    DateTime expDate = _parseExpiry(expiryStr);
    DateTime ref = DateTime(_date.year, _date.month, _date.day);

    if (expDate.isBefore(ref)) {
      return Colors.black; // Expired relative to invoice date
    }

    int months = (expDate.year - _date.year) * 12 + (expDate.month - _date.month);

    if (months <= 3) {
      return Colors.red.shade700; // Critical near expiry
    } else if (months <= 6) {
      return Colors.orange.shade800; // Caution near expiry
    } else {
      return Colors.white; // > 6 months: Normal white background
    }
  }

  Color _getBatchTextColor(String expiryStr) {
    String trimmed = expiryStr.trim();
    if (trimmed.isEmpty || trimmed == "--/--" || !trimmed.contains('/')) {
      return Colors.black;
    }
    DateTime expDate = _parseExpiry(expiryStr);
    DateTime ref = DateTime(_date.year, _date.month, _date.day);

    if (expDate.isBefore(ref)) {
      return Colors.white; // White text on black background for expired
    }

    int months = (expDate.year - _date.year) * 12 + (expDate.month - _date.month);

    if (months <= 6) {
      return Colors.white; // White text on red/orange background
    } else {
      return Colors.black; // Normal black text for > 6 months
    }
  }


  // ---> NEW: Instantly unlocks the Edit button when a change happens <---
  void _markDirty() {
    _lastDraftSavedStateDirty = true;
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


  Future<void> _initializeNewBillNumber() async {
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    if (_entryNo.isNotEmpty) {
      p.releaseEntryNo(_entryNo);
    }
    if (mounted) {
      setState(() {
        _entryNo = "";
        _entryNoCtrl.text = "...";
      });
    }

    final nextNo = await p.getNextSaleEntryNo();

    if (mounted && !_isExistingEntry) {
      setState(() {
        _entryNo = cleanEntryNo(nextNo);
        _entryNoCtrl.text = formatSaleDisplayNo(_entryNo);
        p.reserveEntryNo(_entryNo);
      });
    }
  }

  StreamSubscription<AppNotification>? _watchdogSub;
  StreamSubscription? _syncBusSub;

  @override
  void initState() {
    super.initState();
    DbHelper.setBillingActive(true);
    UnsavedChangesRegistry.register("SALES ENTRY", this);

    _loadColumnWidths();

    final p = Provider.of<PharmacyProvider>(context, listen: false);
    _lastYear = p.selectedFinancialYear;
    _isExistingEntry = widget.initialInvoiceNo != null;

    if (_isExistingEntry) {
      _entryNo = cleanEntryNo(widget.initialInvoiceNo!);
      _entryNoCtrl.text = formatSaleDisplayNo(_entryNo);
    } else {
      _entryNo = "";
      _entryNoCtrl.text = "...";
    }

    _watchdogSub = AppNotificationService.instance.watchdogStream.listen((notif) {
      if (!mounted) return;
      final cat = notif.detectedCategory;
      if (cat == 'STOCK' || cat == 'CATALOG' || cat == 'SALES' || cat == 'PURCHASE') {
        final prov = Provider.of<PharmacyProvider>(context, listen: false);
        prov.refreshLiveStock();
      }

      if (_isExistingEntry && _entryNo.isNotEmpty) {
        final bool matchesCurrentEntry = notif.message.contains('#$_entryNo') ||
            (notif.actionPayload != null &&
                notif.actionPayload!['entryNo'].toString().trim() == _entryNo.trim());

        if (matchesCurrentEntry) {
          ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
          ScaffoldMessenger.of(context).showMaterialBanner(
            MaterialBanner(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              content: Text(
                "⚡ Live Notice: Invoice #$_entryNo was updated on another PC (${notif.terminalName ?? 'Cloud Server'}).",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
              leading: const Icon(Icons.bolt_rounded, color: Colors.amberAccent),
              backgroundColor: Colors.purple.shade900,
              actions: [
                TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                    _loadSaleData(_entryNo);
                  },
                  child: const Text("RELOAD INVOICE", style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                  onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
                ),
              ],
            ),
          );
        }
      }
    });

    _syncBusSub = SyncEventBus.instance.stream.listen((event) {
      if (!mounted) return;
      final table = (event is TableChangedEvent) ? event.tableName : event.toString();
      if (table == 'stock_batches' || table == 'product_master' || table == 'sales_invoices' || table == 'sales_items' || table == 'patients') {
        final p = Provider.of<PharmacyProvider>(context, listen: false);
        p.syncInventoryFromDb();
        if (!_isExistingEntry && _items.isEmpty && !_isDirty) {
          _checkAndRefreshEntryNo();
        }
        setState(() {});
      }
    });

    // ASYNC INITIALIZATION
    Future.microtask(() async {
      if (!_isExistingEntry) {
        await _initializeNewBillNumber();
      }
      _loadNotificationData();
    });

    // ---> START AUTO-SAVE TIMER (Every 30 seconds) <---
    _draftTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) _triggerAutoSaveDraft();
    });

    _timeNotifier.value = DateFormat('hh:mm a').format(_date);
    _timeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && !_isExistingEntry) {
        _timeNotifier.value = DateFormat('hh:mm a').format(DateTime.now());
      }
    });

    p.addListener(_onProviderChanged);
    ServerConfigService.instance.addListener(_onConfigChanged);
    _lastSyncedSessionIdx = p.activeSessionIdx;

    LanSyncService.instance.initLanListener(
      onLanEvent: (event) {
        if (event['action'] == 'SALE_COMPLETED' || event['action'] == 'SALE_SAVED') {
          // If PC 2 is currently sitting on an empty, unsaved bill:
          if (!_isExistingEntry && _items.isEmpty && mounted) {
            final p = Provider.of<PharmacyProvider>(context, listen: false);
            p.getNextSaleEntryNo().then((freshNext) {
              if (mounted && !_isExistingEntry && _items.isEmpty) {
                setState(() {
                  _entryNo = cleanEntryNo(freshNext);
                  _entryNoCtrl.text = formatSaleDisplayNo(_entryNo);
                });
              }
            });
          }
        }
      },
    );

    // --- THE FIX: ADD FOCUS & DAYS LISTENER ---
    _patientFocus.addListener(() {
      if (!_patientFocus.hasFocus) {
        _isPatientTyping = false;
      }
    });
    _doctorFocus.addListener(() {
      if (!_doctorFocus.hasFocus) {
        _isDoctorTyping = false;
      }
    });
    _daysCtrl.addListener(_onDaysChanged);
    _searchIdx.addListener(_onSearchIdxChanged);
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
        _focusProductFirstBox();
      }
    });
  }

  void _focusProductFirstBox() {
    if (!mounted) return;
    _moveFocus(0, 2, autoOpen: false);
    final fn = _getGridFocusNode(0, 2);
    FocusScope.of(context).requestFocus(fn);
    final ctrl = _getGridCtrl(0, 2);
    if (ctrl.text.isNotEmpty) {
      ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
    }
  }

  void _onConfigChanged() {
    if (mounted) setState(() {});
  }

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    _watchdogSub?.cancel();
    ServerConfigService.instance.removeListener(_onConfigChanged);
    _saveColWidthsTimer?.cancel();
    DbHelper.setBillingActive(false);
    UnsavedChangesRegistry.unregister("SALES ENTRY");
    _daysCtrl.removeListener(_onDaysChanged);
    _draftTimer?.cancel(); // Clean up timer
    _scrollTimer?.cancel();
    _timeTimer?.cancel();
    _productSearchDebouncer.dispose();
    _historyDebouncer.dispose();
    _footerDebouncer.dispose();
    _footerUpdateDebouncer.dispose();
    _barcodeDebouncer.dispose();
    _gridScrollCtrl.dispose();
    _verticalGridScrollCtrl.dispose();
    _dropdownScrollCtrl.dispose();
    _topScrollCtrl.dispose();
    _tierListScrollCtrl.dispose();
    _notifListScrollCtrl.dispose();
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
    _drawerSearchCtrl.dispose();
    _rcvdAmtFocus.dispose();
    _focusNotifier.dispose();
    _timeNotifier.dispose();
    _searchList.dispose();
    _batchList.dispose();
    _searchIdx.removeListener(_onSearchIdxChanged);
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

    _syncBusSub?.cancel();
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

    if (row < 0 || row > _items.length) return _dummyFocusNode;

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
              final sel = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
              if (ctrl.selection != sel) {
                ctrl.selection = sel;
              }
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
    if (_isSaving || _isLoading || _isDialogOpen) return;
    _promptSave();
  }

  void _processBarcode(String barcode) async {
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final cleanCode = barcode.trim().toUpperCase();
    Product? found;

    // Check GS1 / DataMatrix parsing ((01)GTIN(17)EXP(10)BATCH)
    final gs1 = _parseGs1Barcode(barcode);
    if (gs1 != null && (gs1['gtin']!.isNotEmpty || gs1['batch']!.isNotEmpty)) {
      final targetBatch = gs1['batch']!.trim().toUpperCase();
      final targetGtin = gs1['gtin']!.trim();

      try {
        found = p.products.firstWhere(
          (it) => (targetBatch.isNotEmpty && it.batch.trim().toUpperCase() == targetBatch) ||
                  (targetGtin.isNotEmpty && it.id == targetGtin),
        );
      } catch (_) {}
    }

    // 1. PRIORITY: Check if barcode identifies a specific active batch
    if (found == null) {
      try {
        found = p.products.firstWhere(
          (it) => (it.batch.trim().toUpperCase() == cleanCode || it.id.trim().toUpperCase() == cleanCode) && it.stock > 0,
        );
      } catch (_) {}
    }

    // 2. Fallback: Check if barcode matches a Product Master ID
    if (found == null) {
      Product? matchedMaster;
      try {
        matchedMaster = p.productMaster.firstWhere(
          (pm) => pm.id.trim().toUpperCase() == cleanCode || pm.hsnCode.trim().toUpperCase() == cleanCode,
        );
      } catch (_) {}

      if (matchedMaster != null) {
        // Only trigger FEFO search when scanning the product generally (not a specific batch)
        final fefoBatch = p.getAutoFefoBatch(matchedMaster.name);
        found = fefoBatch ?? matchedMaster;
      }
    }

    if (found != null) {
      // Check if this exact product and batch is already in the grid
      int existingRowIndex = _items.indexWhere((it) => 
          it.product.id == found!.id && it.product.batch == found.batch);

      if (existingRowIndex != -1) {
        int usedInOtherRows = _getCrossRowStockUsed(found, existingRowIndex);
        int origQty = _originalInvoiceBatchQtys["${found.id}|${found.batch.trim().toUpperCase()}"] ?? 0;
        int avail = found.stock + origQty - usedInOtherRows;
        int currentQty = _items[existingRowIndex].qty;

        if (currentQty + 1 > avail) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("STOCK SHORTAGE: Cannot add more ${found.name}. Available: $avail"),
              backgroundColor: Colors.red.shade800,
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }

        setState(() {
          _items[existingRowIndex].qty += 1;
          _getGridCtrl(existingRowIndex, 7).text = _items[existingRowIndex].qty.toString();
          _calculateItem(existingRowIndex);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("RAPID DISPATCH UPDATED: ${found.name} (Qty: ${_items[existingRowIndex].qty})"),
            backgroundColor: Colors.blue.shade800,
            duration: const Duration(milliseconds: 700),
          ),
        );
      } else {
        int usedInOtherRows = _getCrossRowStockUsed(found, -1);
        int origQty = _originalInvoiceBatchQtys["${found.id}|${found.batch.trim().toUpperCase()}"] ?? 0;
        int avail = found.stock + origQty - usedInOtherRows;
        if (avail <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("ZERO STOCK: ${found.name} (Batch: ${found.batch}) has no available stock."),
              backgroundColor: Colors.red.shade800,
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }

        int row = _focusedRowIndex;
        if (row < 0 || (row < _items.length && _items[row].product.name.isNotEmpty && _focusedColIndex != 3)) {
          row = _items.length;
        }

        _handleBatchSelection(row: row, product: found);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("RAPID DISPATCH SCANNED: ${found.name}"),
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

  Map<String, String>? _parseGs1Barcode(String rawBarcode) {
    try {
      String code = rawBarcode;
      String? gtin;
      String? expiry;
      String? batch;

      if (code.contains('(01)')) {
        int idx = code.indexOf('(01)');
        int start = idx + 4;
        if (code.length >= start + 14) {
          gtin = code.substring(start, start + 14);
        }
      }
      if (code.contains('(17)')) {
        int idx = code.indexOf('(17)');
        int start = idx + 4;
        if (code.length >= start + 6) {
          expiry = code.substring(start, start + 6);
        }
      }
      if (code.contains('(10)')) {
        int idx = code.indexOf('(10)');
        int start = idx + 4;
        batch = code.substring(start).replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
      }

      if (gtin != null || batch != null || expiry != null) {
        return {'gtin': gtin ?? '', 'expiry': expiry ?? '', 'batch': batch ?? ''};
      }
    } catch (_) {}
    return null;
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
          if (matches.isNotEmpty) {
            final best = matches.firstWhere(
              (m) => Product.cleanProductName(m.name).toLowerCase() == Product.cleanProductName(value).toLowerCase(),
              orElse: () => matches.first,
            );
            _commitSelection(row, best, stayOnProduct: true);
          } else {
            it.product = Product(id: "", name: "");
            _getGridCtrl(row, 2).clear();
            _updateFooter(it.product);
          }
        } else if (value.trim().isEmpty) {
          it.product = Product(id: "", name: "");
          _updateFooter(it.product);
        }
      }

      // Auto-fill Batch on blur
      if (col == 4) {
        if (value.trim().isEmpty && it.product.name.isNotEmpty) {
          final p = Provider.of<PharmacyProvider>(context, listen: false);
          final now = DateTime.now();

          // Only auto-fill unexpired batches with stock (O(1) Fast Lookup)
          final candidateBatches = p.getBatchesForProduct(it.product.id, it.product.name);
          final availableBatches = candidateBatches.where((prod) {
            int origQty = _originalInvoiceBatchQtys["${prod.id}|${prod.batch.trim().toUpperCase()}"] ?? 0;
            int usedInOtherRows = _getCrossRowStockUsed(prod, row);
            int trueAvailable = prod.stock + origQty - usedInOtherRows;
            return trueAvailable > 0 && !_parseExpiry(prod.expiry).isBefore(now);
          }).toList();

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
          int typedQty = int.tryParse(val) ?? 0;
          if (typedQty > 0) {
            int bLoose = it.product.stock;
            int stockAlreadyUsed = _getCrossRowStockUsed(it.product, row);
            int originalQtyInThisInvoice = _originalInvoiceBatchQtys["${it.product.id}|${it.product.batch.trim().toUpperCase()}"] ?? 0;
            int trueAvailableInCurrent = bLoose + originalQtyInThisInvoice - stockAlreadyUsed;

            if (typedQty > trueAvailableInCurrent) {
              _handleAutoSplit(row, typedQty, trueAvailableInCurrent);
            } else {
              it.qty = typedQty;
              if (!_getGridFocusNode(row, 7).hasFocus) {
                _getGridCtrl(row, 7).text = it.qty.toString();
              }
            }
          } else {
            it.qty = 0;
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
          if (!_getGridFocusNode(row, 11).hasFocus) {
            _getGridCtrl(row, 11).text = it.discPercent.toStringAsFixed(2);
          }
        }
        _calculateItem(row);
      }
    }
  }

  // ---> NEW: Master function to instantly kill all dropdowns <---
  void _closeAllDropdowns() {
    _productSearchDebouncer.cancel();
    _searchList.value = [];
    _batchList.value = [];
    _specialSearchList.value = [];
    _patientSearchList.value = [];
    _doctorSearchList.value = [];
    _searchIdx.value = 0;
    int row = _focusedRowIndex;
    if (row >= 0 && row < _items.length) {
      _updateFooter(_items[row].product);
    } else {
      _updateFooter(Product(id: "", name: ""));
    }
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
      final fn = _getGridFocusNode(safeRow, safeCol);
      FocusScope.of(context).requestFocus(fn);
    }

    if (safeRow >= 0 && _showSpecialOrderSidebar && !_isSpecialOrderMinimized) {
      setState(() => _isSpecialOrderMinimized = true);
    }

    // ---> EXECUTE IMMEDIATELY INSTEAD OF WAITING FOR POST-FRAME <---
    if (safeRow == -1) {
      final fn = _getHeaderFocus(safeCol < 4 ? safeCol : 3);
      final ctrl = _getHeaderCtrl(safeCol < 4 ? safeCol : 3);

      bool wasFocused = fn.hasFocus;
      if (!wasFocused) {
        FocusScope.of(context).requestFocus(fn);
        ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
      }
    } else {
      final fn = _getGridFocusNode(safeRow, safeCol);
      final ctrl = _getGridCtrl(safeRow, safeCol);
      final initialText = ctrl.text;

      FocusScope.of(context).requestFocus(fn);
      
      if (initialText.isNotEmpty) {
        ctrl.selection = TextSelection(baseOffset: 0, extentOffset: initialText.length);
      }

      // Open the dropdown table upon focus
      if (autoOpen) {
        if (safeCol == 2 && initialText.trim().isEmpty) {
          _startProductSearch("");
        } else if (safeCol == 4) {
          _startBatchSearch(safeRow, "");
        }
      }
    }
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

  void _onSearchIdxChanged() {
    if (!mounted) return;
    if (_searchList.value.isNotEmpty && _batchList.value.isEmpty) {
      final safeIdx = _searchIdx.value.clamp(0, _searchList.value.length - 1);
      final p = _searchList.value[safeIdx];
      if (p.id != "NEW") {
        _updateFooter(p);
      }
    }
  }

  void _updateFooter(Product p) {
    if (!mounted) return;

    _footerUpdateDebouncer.run(() async {
      if (!mounted) return;
      final provider = Provider.of<PharmacyProvider>(context, listen: false);

      final cleanName = Product.cleanProductName(p.name).trim();

      // Only show generic availability helper if a valid product with a non-empty name is selected!
      if (cleanName.isEmpty || p.id == "NEW") {
        _activeGenericName = "";
        _lastSyncedProdName = "";
        if (mounted) {
          setState(() {
            _footerAlts = [];
            _productHistory = [];
          });
        }
        return;
      }

      String genName = p.genericName.trim();
      if (genName.isEmpty) {
        genName = provider.resolveGenericName(cleanName, productId: p.id);
      }
      _activeGenericName = genName;

      if (cleanName != _lastSyncedProdName) {
        _lastSyncedProdName = cleanName;
        _updateHistory(cleanName);
      }

      if (genName.isNotEmpty) {
        final query = genName.toUpperCase();
        final alts = provider.searchProducts(query, isSalesWindow: true)
            .where((alt) => alt.name.trim().toUpperCase() != cleanName.toUpperCase())
            .where((alt) => alt.stock > 0) // Only show products with stock > 0
            .take(50) // Take top 50 first to prevent heavy RegExp sorting thrashing on thousands of items
            .toList();

        _sortGenericAlternatives(alts, p, genName, provider);

        if (mounted) {
          setState(() {
            _footerAlts = alts;
          });
        }
      } else {
        if (_footerAlts.isNotEmpty && mounted) {
          setState(() => _footerAlts = []);
        }
      }
    });
  }

  List<String> _getAltGenericSegments(String genName) {
    if (genName.trim().isEmpty) return [];
    return genName
        .split(RegExp(r'[-+/,]'))
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  int _getAltGenericContentCount(String genName) {
    final segs = _getAltGenericSegments(genName);
    return segs.isEmpty ? 1 : segs.length;
  }

  Set<String> _extractStrengthTokens(String text) {
    if (text.trim().isEmpty) return {};
    final String upper = text.toUpperCase();
    final Set<String> tokens = {};

    // 1. Explicit unit regex: matches e.g. 125MG, 125 MG, 0.5MG, 2.5MG, 500MCG, 1GM, 60000IU, 2%
    final unitRegExp = RegExp(
      r'\b(\d+(?:\.\d+)?)\s*(MG|MCG|GM|G|IU|UG|PERCENT|%)\b',
      caseSensitive: false,
    );
    final unitMatches = unitRegExp.allMatches(upper);

    bool foundExplicit = false;
    for (final m in unitMatches) {
      final numStr = m.group(1)!;
      final unitStr = m.group(2)!.toLowerCase();

      final double? dVal = double.tryParse(numStr);
      final String cleanNum = (dVal != null && dVal == dVal.toInt())
          ? dVal.toInt().toString()
          : numStr;

      tokens.add('$cleanNum$unitStr');
      tokens.add(cleanNum);
      foundExplicit = true;
    }

    // If explicit strength units (MG, MCG, GM, IU, etc.) were found, return them directly.
    if (foundExplicit) {
      return tokens;
    }

    // 2. Standalone strength numbers (e.g., DOLO 650, PAN 40, CALPOL 500, FLUMOL 650)
    final numRegExp = RegExp(r'\b\d+(?:\.\d+)?\b');
    final numMatches = numRegExp.allMatches(upper);

    for (final m in numMatches) {
      final valStr = m.group(0)!;
      final double? val = double.tryParse(valStr);
      if (val == null) continue;

      final int start = m.start;
      final int end = m.end;
      final String after = upper.substring(end, (end + 6).clamp(0, upper.length)).trimLeft();
      final String before = upper.substring((start - 6).clamp(0, upper.length), start).trimRight();

      // Skip liquid volume numbers like "60 ML", "100 ML", "30 ML" if standalone
      if (after.startsWith('ML') || after.startsWith(' L') || after.startsWith('BOTTLE')) {
        continue;
      }

      // Skip pack sizes / counts like "10 TAB", "10 CAP", "10 S", "10'S", "10T", "10C", "1X10", "10X10"
      bool isLikelyPackSize = (after.startsWith('TAB') || after.startsWith('CAP') || after.startsWith('STRIP') ||
              after.startsWith('PACK') || after.startsWith('S ') || after.startsWith("'S") ||
              after.startsWith('T ') || after.startsWith('C ') || before.endsWith('X') || after.startsWith('X')) &&
          (val < 20 && val == val.toInt());

      if (isLikelyPackSize) {
        continue;
      }

      if (val >= 0.1) {
        String cleanNum = val == val.toInt() ? val.toInt().toString() : val.toString();
        tokens.add(cleanNum);
        tokens.add('${cleanNum}mg');
      }
    }

    return tokens;
  }

  void _sortGenericAlternatives(List<Product> alts, Product selectedProd, String selectedGenName, PharmacyProvider provider) {
    final selectedSaltCount = _getAltGenericContentCount(selectedGenName);
    final selectedStrengths = _extractStrengthTokens(selectedProd.name);

    alts.sort((a, b) {
      // 1st Priority: Same Dosage / Strength Match
      if (selectedStrengths.isNotEmpty) {
        final aStrengths = _extractStrengthTokens(a.name);
        final bStrengths = _extractStrengthTokens(b.name);
        final bool aDosageMatch = aStrengths.intersection(selectedStrengths).isNotEmpty;
        final bool bDosageMatch = bStrengths.intersection(selectedStrengths).isNotEmpty;

        if (aDosageMatch != bDosageMatch) {
          return aDosageMatch ? -1 : 1;
        }
      }

      // 2nd Priority: Salt / Content Count Match
      final aGenName = a.genericName.isNotEmpty ? a.genericName : selectedGenName;
      final bGenName = b.genericName.isNotEmpty ? b.genericName : selectedGenName;
      final aSaltCount = _getAltGenericContentCount(aGenName);
      final bSaltCount = _getAltGenericContentCount(bGenName);
      final bool aExactSalt = (aSaltCount == selectedSaltCount);
      final bool bExactSalt = (bSaltCount == selectedSaltCount);

      if (aExactSalt != bExactSalt) {
        return aExactSalt ? -1 : 1;
      }

      // 3rd Priority: Available Stock (Stock > 0 first)
      final bool aHasStock = a.stock > 0;
      final bool bHasStock = b.stock > 0;
      if (aHasStock != bHasStock) {
        return aHasStock ? -1 : 1;
      }

      // 4th Priority: Category & Profit Margin Priority
      // Rank 0 = Generic Category (Green)
      // Rank 1 = Profit Margin > 40% (Blue)
      // Rank 2 = Others
      int getCategoryRank(Product prod) {
        if (provider.isGenericProduct(prod)) return 0;
        final margin = prod.purchaseRate > 0
            ? (((prod.mrp > 0 ? prod.mrp : prod.salePrice) - prod.purchaseRate) / prod.purchaseRate) * 100
            : 0.0;
        if (margin > 40.0) return 1;
        return 2;
      }

      final aRank = getCategoryRank(a);
      final bRank = getCategoryRank(b);
      if (aRank != bRank) {
        return aRank.compareTo(bRank);
      }

      // 5th Priority: Stock Quantity (Highest Stock First)
      final stockCmp = b.stock.compareTo(a.stock);
      if (stockCmp != 0) return stockCmp;

      return a.name.compareTo(b.name);
    });
  }

  bool existingNamesInByPass(String name, Set<String> set) => set.contains(name);

  void _updateHistory(String productName) {
    _historyDebouncer.run(() async {
      final p = Provider.of<PharmacyProvider>(context, listen: false);
      final history = await p.getProductSaleHistory(productName);
      if (!mounted) return;
      if (mounted) {
        setState(() {
          _productHistory = history;
        });
      }
    });
  }

  void _onHeaderSearch(String query, ValueNotifier<List<dynamic>> targetList, List<dynamic> Function(PharmacyProvider) source, {bool showAllIfEmpty = false}) {
    final p = Provider.of<PharmacyProvider>(context, listen: false);

    if (query.trim().isEmpty) {
      if (showAllIfEmpty) {
        final all = source(p);
        targetList.value = all.take(20).toList();
        _searchIdx.value = 0;
      } else {
        targetList.value = [];
      }
      return;
    }
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



  void _abortAllActiveSearches() {
    _productSearchDebouncer.cancel();
    _historyDebouncer.cancel();
    _footerDebouncer.cancel();
    _footerUpdateDebouncer.cancel();
    _barcodeDebouncer.cancel();

    _searchList.value = [];
    _batchList.value = [];
    _specialSearchList.value = [];
    _patientSearchList.value = [];
    _doctorSearchList.value = [];
    _closeAllDropdowns();
    _isSelectingFromDropdown = false;
    _isSelectingBatch = false;
  }

  void _rebindGridFocusPostFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      int r = _focusedRowIndex.clamp(0, _items.length);
      int c = _focusNotifier.value?.col ?? 2;
      if (!_navCols.contains(c)) c = 2;

      final fn = _getGridFocusNode(r, c);
      FocusScope.of(context).requestFocus(fn);
      final ctrl = _getGridCtrl(r, c);
      if (ctrl.text.isNotEmpty) {
        ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
      }
    });
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
        _specialSearchQtyFocus.hasFocus ||
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

    if (isOverlayOpen && (event is KeyDownEvent || event is KeyRepeatEvent)) {
      final list = _patientSearchList.value.isNotEmpty ? _patientSearchList.value
          : _doctorSearchList.value.isNotEmpty ? _doctorSearchList.value
          : _specialSearchList.value.isNotEmpty ? _specialSearchList.value
          : ((_isSelectingBatch || _focusedColIndex == 4) && _batchList.value.isNotEmpty ? _batchList.value
          : (_searchList.value.isNotEmpty ? _searchList.value : _batchList.value));

      // Allow vertical arrows to navigate the list properly even if focus is inside the TextField
      if (key == LogicalKeyboardKey.arrowDown) {
        if (list.isEmpty) return true;
        _searchIdx.value = (_searchIdx.value + 1).clamp(0, list.length - 1);
        _scrollToIdx(_searchIdx.value);
        return true;
      } else if (key == LogicalKeyboardKey.arrowUp) {
        if (list.isEmpty) return true;
        _searchIdx.value = (_searchIdx.value - 1).clamp(0, list.length - 1);
        _scrollToIdx(_searchIdx.value);
        return true;
      }
      else if (event is KeyDownEvent && (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter)) {
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
            // ---> FIX: Explicitly commit the selected batch/product and STOP propagation <---
            final selectedItem = list[_searchIdx.value];
            if (_searchList.value.isNotEmpty && selectedItem is Product) {
              _onProductSelected(selectedItem);
            } else if (_batchList.value.isNotEmpty && selectedItem is Product) {
              _handleBatchSelection(row: _focusedRowIndex, product: selectedItem);
            }
          }
          return true; // <--- CRITICAL: Stops event from leaking to grid submission
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

      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_searchList.value.isNotEmpty || _batchList.value.isNotEmpty) {
          _abortAllActiveSearches();
          _rebindGridFocusPostFrame();
          return true;
        }
        if (widget.isDialog) {
          Navigator.of(context).maybePop();
          return true;
        }
        _abortAllActiveSearches();
        _rebindGridFocusPostFrame();
        return true;
      }

      if (_isDialogOpen) return false;

      // F1: New Sale (or Shift/Ctrl + F1: Cheat Sheet)
      if (event.logicalKey == LogicalKeyboardKey.f1) {
        if (isShift || isCtrl) {
          _showShortcutsDialog(); // Shift/Ctrl + F1: Cheat Sheet
        } else {
          _resetPage(); // F1: New Sale
        }
        return true;
      }
      // F2: Generic / Substitute Search
      if (event.logicalKey == LogicalKeyboardKey.f2) {
        _openGenericSearchDialog();
        return true;
      }
      // F3: Wholesale Availability Directory
      if (event.logicalKey == LogicalKeyboardKey.f3) {
        _openWholesaleAvailability();
        return true;
      }
      // F4: Jump directly to Product Grid / Item Search
      if (event.logicalKey == LogicalKeyboardKey.f4) {
        _itemSearchFocusNode.requestFocus();
        return true;
      }
      // F5: Generic / Substitute Search
      if (event.logicalKey == LogicalKeyboardKey.f5) {
        _openGenericSearchDialog();
        return true;
      }
      // F6: Save Invoice or Edit
      if (event.logicalKey == LogicalKeyboardKey.f6) {
        _isExistingEntry && !_isDeleted ? _editSale() : _saveSale(isEdit: false);
        return true;
      }
      // F7: Focus Customer / Patient Name
      if (event.logicalKey == LogicalKeyboardKey.f7) {
        _patientFocus.requestFocus();
        return true;
      }
      // F8: Focus Cash Received Amount (Pay)
      if (event.logicalKey == LogicalKeyboardKey.f8) {
        _rcvdAmtFocus.requestFocus();
        return true;
      }
      // F9: Export / Preview Invoice PDF
      if (event.logicalKey == LogicalKeyboardKey.f9) {
        _exportToPdf();
        return true;
      }
      // F10: Save Invoice or Edit
      if (event.logicalKey == LogicalKeyboardKey.f10) {
        _isExistingEntry && !_isDeleted ? _editSale() : _saveSale(isEdit: false);
        return true;
      }
      // F11: Hold current billing session and switch workspace
      if (event.logicalKey == LogicalKeyboardKey.f11) {
        if (_isExistingEntry && _isDirty) {
          _showFastDialog(title: "Workspace Locked", content: "You have unsaved edits. Please save or press F1 to clear before switching workspaces.");
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
      // F12: Express Save & Print
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

    // === Ctrl + Q FOR DYNAMIC UPI QR PAYMENT ===
    if (isCtrl && key == LogicalKeyboardKey.keyQ) {
      _triggerDynamicUpiQrPayment();
      return true;
    }

    // === NEW: Ctrl + 1 FOR PURCHASE HISTORY ===
    if (isCtrl && key == LogicalKeyboardKey.digit1) {
      String pName = _getActiveProductName();
      if (pName.trim().isNotEmpty) {
        _openHistoryWindow(pName.trim(), false);
      }
      return true;
    }

    // === NEW: Ctrl + 2 FOR SALES HISTORY ===
    if (isCtrl && key == LogicalKeyboardKey.digit2) {
      String pName = _getActiveProductName();
      if (pName.trim().isNotEmpty) {
        _openHistoryWindow(pName.trim(), true);
      }
      return true;
    }

    // === NEW: Ctrl + L FOR STOCK MOVEMENT LEDGER ===
    if (isCtrl && key == LogicalKeyboardKey.keyL) {
      String pName = _getActiveProductName();
      if (pName.trim().isNotEmpty) {
        _openStockMovementDrawer(pName.trim());
      }
      return true;
    }

    // === Alt + Down Arrow to open dropdown list in grid ===
    if (HardwareKeyboard.instance.isAltPressed && key == LogicalKeyboardKey.arrowDown) {
      if (_focusedColIndex == 2) {
        _startProductSearch(_getGridCtrl(_focusedRowIndex, 2).text);
        return true;
      } else if (_focusedColIndex == 4) {
        _startBatchSearch(_focusedRowIndex, "");
        return true;
      }
    }

    // === Home / End Keys to Jump First / Last Row in Table ===
    if (key == LogicalKeyboardKey.home) {
      if (_items.isNotEmpty) {
        _moveFocus(0, 1);
      }
      return true;
    }
    if (key == LogicalKeyboardKey.end) {
      if (_items.isNotEmpty) {
        _moveFocus((_items.length - 1).clamp(0, 999), 1);
      }
      return true;
    }

    if (HardwareKeyboard.instance.isAltPressed) {
      if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.pageUp) { _navigateEntry("prev"); return true; }
      if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.pageDown) { _navigateEntry("next"); return true; }
    }

    // PageUp / PageDown: Scroll grid or navigate entries
    if (key == LogicalKeyboardKey.pageUp) {
      if (HardwareKeyboard.instance.isAltPressed) {
        _navigateEntry("prev");
      } else if (_focusedRowIndex >= 0) {
        int targetRow = (_focusedRowIndex - 5).clamp(0, _items.length);
        _moveFocus(targetRow, _focusedColIndex > 0 ? _focusedColIndex : 1);
      } else {
        _navigateEntry("prev");
      }
      return true;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      if (HardwareKeyboard.instance.isAltPressed) {
        _navigateEntry("next");
      } else if (_focusedRowIndex >= 0) {
        int targetRow = (_focusedRowIndex + 5).clamp(0, _items.length);
        _moveFocus(targetRow, _focusedColIndex > 0 ? _focusedColIndex : 1);
      } else {
        _navigateEntry("next");
      }
      return true;
    }

    // Delete key: Ctrl + Del = Delete Row, Standalone Del = Clear Focused Field
    if (key == LogicalKeyboardKey.delete) {
      if (HardwareKeyboard.instance.isControlPressed) {
        if (_focusedRowIndex >= 0 && _focusedRowIndex < _items.length) {
          _safeDeleteRow(_focusedRowIndex); // CODE MASTER FIX
          _moveFocus(_focusedRowIndex, 1);
          return true;
        }
      } else {
        if (_focusedRowIndex >= 0) {
          final ctrl = _getGridCtrl(_focusedRowIndex, _focusedColIndex);
          if (ctrl.text.isNotEmpty) {
            ctrl.clear();
            _markDirty();
            _calculateFooter();
            return true;
          }
        } else if (_patientFocus.hasFocus) {
          _patientCtrl.clear();
          return true;
        } else if (_doctorFocus.hasFocus) {
          _doctorCtrl.clear();
          return true;
        }
      }
    }

    if (HardwareKeyboard.instance.isControlPressed) {
      if (key == LogicalKeyboardKey.keyZ) {
        _performUndo();
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

    // Allow native Left and Right arrow keys to move the cursor character-by-character inside the text field
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      return false;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (row < _items.length) {
        int nextCol = _navCols.contains(col) ? col : 1;
        _moveFocus(row + 1, nextCol);
      } else {
        _rcvdAmtFocus.requestFocus();
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
      if (!mounted || !_dropdownScrollCtrl.hasClients) {
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
    Product? p;
    if (item is SaleItem) {
      p = item.product;
    } else if (item is Product) {
      p = item;
    }
    if (p == null) return "";
    String idOrName = p.id.isNotEmpty ? p.id.trim().toUpperCase() : Product.cleanProductName(p.name).toLowerCase();
    String cleanB = cleanBatch(p.batch).trim().toUpperCase();
    return "${idOrName}_${cleanB}_${p.expiry.trim()}_${p.mrp}_${p.packSize > 0 ? p.packSize : 1}_${p.landingCost}_${p.gstPercent}_${p.purchaseRate}_${p.supplier.trim().toUpperCase()}";
  }

  int _getCrossRowStockUsed(dynamic target, int excludeRow) {
    int used = 0;
    String targetKey = _getBatchUniqueKey(target);
    if (targetKey.isEmpty) return 0;
    for (int i = 0; i < _items.length; i++) {
      if (i != excludeRow && _getBatchUniqueKey(_items[i]) == targetKey) {
        used += _items[i].qty + _items[i].fQty;
      }
    }
    return used;
  }

  int _getCrossRowStockUsedForProduct(dynamic target, int excludeRow) {
    int used = 0;
    String targetName = "";
    String targetId = "";
    if (target is SaleItem) {
      targetName = Product.cleanProductName(target.product.name).toLowerCase();
      targetId = target.product.id;
    } else if (target is Product) {
      targetName = Product.cleanProductName(target.name).toLowerCase();
      targetId = target.id;
    }
    if (targetName.isEmpty && targetId.isEmpty) return 0;

    for (int i = 0; i < _items.length; i++) {
      if (i != excludeRow) {
        final itemProd = _items[i].product;
        bool nameMatch = targetName.isNotEmpty && Product.cleanProductName(itemProd.name).toLowerCase() == targetName;
        bool idMatch = targetId.isNotEmpty && itemProd.id.isNotEmpty && itemProd.id == targetId;
        if (nameMatch || idMatch) {
          used += _items[i].qty + _items[i].fQty;
        }
      }
    }
    return used;
  }

  // FORCEFUL HARDWARE ENTER KEY LISTENER

  Future<dynamic> _showFastDialog({
    required String title,
    required String content,
    Widget? contentWidget,
    bool isYesNo = false,
    bool isSuccess = false,
    bool showSpecialOrder = false,
    int initialFocusIdx = 1,
    String? confirmText,
    String? cancelText,
  }) {
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
                                              backgroundColor: focusedIdx == 2 ? Colors.blue.shade800 : Colors.grey.shade100,
                                              foregroundColor: focusedIdx == 2 ? Colors.white : Colors.black,
                                              side: focusedIdx == 2 ? const BorderSide(color: Colors.black26, width: 2) : null,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                            ),
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: Text(cancelText ?? "NO", style: const TextStyle(fontWeight: FontWeight.bold))
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: focusedIdx == 1 ? Colors.blue.shade800 : Colors.grey.shade300,
                                            foregroundColor: focusedIdx == 1 ? Colors.white : Colors.black,
                                            side: focusedIdx == 1 ? const BorderSide(color: Colors.black26, width: 2) : null,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                          ),
                                          onPressed: () => Navigator.pop(ctx, true),
                                          child: Text(confirmText ?? (isYesNo ? "YES" : "OK"), style: const TextStyle(fontWeight: FontWeight.bold))
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
      if (mounted) {
        setState(() => _isDialogOpen = false);
        if (_focusedRowIndex >= 0 && _focusedRowIndex <= _items.length) {
          _moveFocus(_focusedRowIndex, 2);
        }
      }
      return val;
    });
  }

  void _onFieldSubmitted(int row, int col) async {
    // If on the blank row and Product is empty, ANY 'Enter' or 'Tab' jumps to Rcvd Amt
    if (row == _items.length && _getGridCtrl(row, 2).text.trim().isEmpty) {
      _closeAllDropdowns();
      _focusNotifier.value = null;
      _rcvdAmtFocus.requestFocus();
      _rcvdAmtCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _rcvdAmtCtrl.text.length);
      return;
    }

    // Handle product name field submission
    if (col == 2) {
      String typedText = _getGridCtrl(row, 2).text.trim();

      if (_searchList.value.isNotEmpty) {
        int safeIdx = _searchIdx.value.clamp(0, _searchList.value.length - 1);
        final selected = _searchList.value[safeIdx];
        if (selected.id == "NEW") {
          _promptCreateNewProduct(selected.name);
          return;
        }
        _onProductSelected(selected);
        return;
      }

      if (typedText.isNotEmpty) {
        final p = Provider.of<PharmacyProvider>(context, listen: false);
        final matches = p.searchProducts(typedText, includeGenerics: false);
        if (matches.isNotEmpty) {
          _onProductSelected(matches.first);
        } else {
          _promptCreateNewProduct(typedText);
        }
      } else {
        _moveFocus(row, 4, autoOpen: true);
      }
    } else if (col == 4) {
      String typed = _getGridCtrl(row, 4).text.trim().toUpperCase();

      if (_batchList.value.isNotEmpty) {
        int safeIdx = _searchIdx.value.clamp(0, _batchList.value.length - 1);
        final selected = _batchList.value[safeIdx];
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
          // AUTO-SELECT BEST NON-EXPIRED FEFO BATCH IF SKIPPED OR MISMATCHED
          availableBatches.sort((a, b) => _parseExpiry(a.expiry).compareTo(_parseExpiry(b.expiry)));
          _commitSelection(row, availableBatches.first, stayOnProduct: false);
        } else {
          _moveFocus(row, 7);
        }
      }
    } else if (col == 7) {
      if (_getGridCtrl(row, 7).text.isEmpty) _getGridCtrl(row, 7).text = "0";

      if (row < _items.length) {
        final it = _items[row];
        final val = _getGridCtrl(row, 7).text.trim();
        int typedQty = int.tryParse(val) ?? 0;
        if (typedQty > 0) {
          int bLoose = it.product.stock;
          int stockAlreadyUsed = _getCrossRowStockUsed(it.product, row);
          int originalQtyInThisInvoice = _originalInvoiceBatchQtys["${it.product.id}|${it.product.batch.trim().toUpperCase()}"] ?? 0;
          int trueAvailableInCurrent = bLoose + originalQtyInThisInvoice - stockAlreadyUsed;

          if (typedQty > trueAvailableInCurrent) {
            _handleAutoSplit(row, typedQty, trueAvailableInCurrent);
            return;
          }
        }
      }

      _moveFocus(row, 11);
    } else if (col == 11) {
      if (_getGridCtrl(row, 11).text.isEmpty) _getGridCtrl(row, 11).text = "0";
      _moveFocus(_items.length, 2, autoOpen: true);
    } else {
      int curIdx = _navCols.indexOf(col);
      if (curIdx != -1 && curIdx < _navCols.length - 1) {
        _moveFocus(row, _navCols[curIdx + 1], autoOpen: _navCols[curIdx + 1] == 4);
      } else {
        _moveFocus(_items.length, 2, autoOpen: true);
      }
    }
  }

  void _handleAutoSplit(int startRow, int totalRequested, int availableInCurrent) async {
    _saveUndoState();

    String prodName = _items[startRow].product.name;
    String prodId = _items[startRow].product.id;

    // Purge subsequent automatic split rows for that same product
    while (startRow + 1 < _items.length) {
      final nextItem = _items[startRow + 1];
      bool isSameProduct = (nextItem.product.id.isNotEmpty && nextItem.product.id == prodId) ||
          (prodName.isNotEmpty && nextItem.product.name.trim().toLowerCase() == prodName.trim().toLowerCase());
      if (isSameProduct) {
        final removed = _items.removeAt(startRow + 1);
        if (_gridCtrls.containsKey(removed)) {
          for (var c in _gridCtrls[removed]!.values) {
            c.dispose();
          }
          _gridCtrls.remove(removed);
        }
      } else {
        break;
      }
    }

    int startingQty = availableInCurrent < 0 ? 0 : availableInCurrent;
    int remaining = totalRequested - startingQty;

    _items[startRow].qty = startingQty;
    _getGridCtrl(startRow, 7, startingQty.toString()).text = startingQty.toString();

    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final String currentBatchKey = _getBatchUniqueKey(_items[startRow].product);
    final candidateBatches = p.getBatchesForProduct(prodId, prodName);
    final otherBatches = candidateBatches.where((it) =>
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
      final res = await _showFastDialog(
          title: "Stock Shortage",
          content: "This item currently has no available stock.\n$remaining Qty is short across all valid batches.",
          showSpecialOrder: true,
          initialFocusIdx: 1, // Auto-select right option ("OK")
          confirmText: "OK",
      );
      if (!mounted) return;

      if (res == "special" && mounted) {
        // ROUTE DIRECTLY TO THE SIDEBAR
        _triggerSpecialOrderFocus(_items[startRow].product.name, remaining);
      } else {
        if (!mounted) return;
        final pharma = Provider.of<PharmacyProvider>(context, listen: false);
        pharma.logStockEnquiry(productName: _items[startRow].product.name, productId: _items[startRow].product.id, requestedQty: remaining, agent: _agentCtrl.text);
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
      _isProductSyncEnabled = false; // Turn off sync so it acts as an independent order
      _isSpecialSyncEnabled = false;

      _extraSpecialItems.remove(pName);
      _extraSpecialItems.insert(0, pName);
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
      int row = _focusedRowIndex;
      if (row >= 0 && row < _items.length) {
        _updateFooter(_items[row].product);
      } else {
        _updateFooter(Product(id: "", name: ""));
      }
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
      if (list.isNotEmpty) {
        final first = list[0];
        if (first.id != "NEW") {
          _updateFooter(first);
        } else if (list.length > 1) {
          _updateFooter(list[1]);
        }
      } else {
        _updateFooter(Product(id: "", name: ""));
      }
    });
  }

  void _startBatchSearch(int row, String q) {
    if (!_isSelectingBatch) {
      _isSelectingBatch = true;
    }
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    String prodName = row < _items.length ? _items[row].product.name : _getGridCtrl(row, 1).text;
    String prodId = row < _items.length ? _items[row].product.id : "";
    if (prodName.trim().isEmpty && prodId.trim().isEmpty) {
      _batchList.value = [];
      return;
    }

    final String query = q.trim().toUpperCase();

    // Instant O(1) hashmap lookup returning pre-consolidated & pre-sorted FEFO batches with stock
    final candidateBatches = p.getBatchesForProduct(prodId, prodName).where((prod) {
      int origQty = _originalInvoiceBatchQtys["${prod.id}|${prod.batch.trim().toUpperCase()}"] ?? 0;
      int usedInOtherRows = _getCrossRowStockUsed(prod, row);
      return (prod.stock + origQty - usedInOtherRows) > 0;
    }).toList();

    if (query.isEmpty) {
      _batchList.value = candidateBatches;
      return;
    }

    _batchList.value = candidateBatches.where((prod) {
      return _cleanBatch(prod.batch).toUpperCase().contains(query);
    }).toList();
  }

  void _startSpecialProductSearch(String q) {
    final String query = q.trim();
    if (query.isEmpty) {
      _specialSearchList.value = [];
      _searchIdx.value = 0;
      return;
    }
    _productSearchDebouncer.run(() {
      if (!mounted) return;
      final provider = Provider.of<PharmacyProvider>(context, listen: false);
      final results = provider.searchProducts(query, isSalesWindow: true);
      _specialSearchList.value = results.take(20).toList();
      _searchIdx.value = 0;
    });
  }

  Future<void> _pickExpectingDate() async {
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
    if (!mounted) return;

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
  }

  void _onSpecialProductSelected(Product p, {int? qty}) {
    final int itemQty = qty ?? int.tryParse(_specialSearchQtyCtrl.text.trim()) ?? 1;
    setState(() {
      _extraSpecialItems.remove(p.name);
      _extraSpecialItems.insert(0, p.name);
      _specialOrderQtys[p.name] = itemQty;
      _specialMainCtrl.clear();
      _specialSearchList.value = [];
      _specialSearchQtyCtrl.text = "1";
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _specialSearchFocus.requestFocus();
    });
  }

  Future<void> _promptCreateNewProduct(String productName) async {
    _closeAllDropdowns();
    final String cleanName = productName.trim();
    if (cleanName.isEmpty) return;

    final dynamic res = await _showFastDialog(
      title: "Create New Product?",
      content: "Product '$cleanName' was not found in Product Master.\n\nWould you like to register this as a new product?",
      isYesNo: true,
      initialFocusIdx: 1, // Auto-select right option ("YES, CREATE")
      confirmText: "YES, CREATE",
      cancelText: "NO",
    );
    if (!mounted) return;

    if (res == true && mounted) {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      appProvider.openProductRegistration(initialName: cleanName);
    }
  }

  void _onProductSelected(Product p) async {
    _productSearchDebouncer.cancel();
    _searchList.value = [];
    if (_itemSearchFocusNode.hasFocus) {
      _itemSearchFocusNode.unfocus();
    }
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

    final pharma = Provider.of<PharmacyProvider>(context, listen: false);
    int totalProductStock = pharma.getTotalStockForProduct(p.name);
    if (totalProductStock <= 0 && p.stock > 0) totalProductStock = p.stock;
    int usedInBill = _getCrossRowStockUsedForProduct(p, row);
    int availableProductStock = totalProductStock - usedInBill;

    if (availableProductStock <= 0) {
      final res = await _showFastDialog(
        title: "Zero Stock",
        content: "This item currently has no available stock ($totalProductStock total stock, $usedInBill used in this entry).",
        showSpecialOrder: true,
        initialFocusIdx: 1, 
      );
      if (!mounted) return;

      if (res == "special") {
        setState(() {
          _getGridCtrl(row, 1).clear();
          if (row < _items.length) {
            _items.removeAt(row);
          }
          _orderType = 1;
          _showSpecialOrderSidebar = true;
          _isSpecialOrderMinimized = false;
        });
        _triggerSpecialOrderFocus(p.name, 1);
      } else {
        if (!mounted) return;
        pharma.logStockEnquiry(productName: p.name, productId: p.id, requestedQty: 1, agent: _agentCtrl.text);
        if (res == true) {
          _commitSelection(row, p, stayOnProduct: true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              final fn = _getGridFocusNode(row, 2);
              FocusScope.of(context).requestFocus(fn);
              final ctrl = _getGridCtrl(row, 2);
              if (ctrl.text.isNotEmpty) {
                ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
              }
            }
          });
        }
      }
      _isSelectingFromDropdown = false;
      return;
    }

    // Use the verified _commitSelection which correctly creates SaleItem and updates controllers
    _commitSelection(row, p);
    _isSelectingFromDropdown = false;
  }

  void _handleBatchSelection({required int row, required Product product}) async {
    _batchList.value = [];
    _searchList.value = [];

    int usedInOtherRows = _getCrossRowStockUsed(product, row);
    int origQty = _originalInvoiceBatchQtys["${product.id}|${product.batch.trim().toUpperCase()}"] ?? 0;
    int available = product.stock + origQty - usedInOtherRows;

    if (available <= 0) {
      final res = await _showFastDialog(
        title: "Zero Stock",
        content: "This batch (${product.batch}) currently has no available stock across this invoice.",
        showSpecialOrder: true,
        initialFocusIdx: 1, 
      );
      if (!mounted) return;

      if (res == "special") {
        setState(() {
          _getGridCtrl(row, 1).clear();
          if (row < _items.length) {
            _items.removeAt(row);
          }
          _orderType = 1;
          _showSpecialOrderSidebar = true;
          _isSpecialOrderMinimized = false;
        });
        _triggerSpecialOrderFocus(product.name, 1);
      } else {
        if (!mounted) return;
        final pharma = Provider.of<PharmacyProvider>(context, listen: false);
        pharma.logStockEnquiry(productName: product.name, productId: product.id, requestedQty: 1, agent: _agentCtrl.text);
        if (res == true) {
          _commitSelection(row, product, stayOnProduct: true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              final fn = _getGridFocusNode(row, 2);
              FocusScope.of(context).requestFocus(fn);
              final ctrl = _getGridCtrl(row, 2);
              if (ctrl.text.isNotEmpty) {
                ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
              }
            }
          });
        }
      }
      return;
    }

    _checkExpiryAndCommit(row, product);
  }

  void _checkExpiryAndCommit(int row, Product product) async {
    final expDate = _parseExpiry(product.expiry);
    final now = DateTime.now();
    if (expDate.isBefore(now)) {
      await _showFastDialog(
        title: "EXPIRED STOCK BLOCKED",
        content: "Batch '${product.batch}' expired on ${product.expiry}. Expired inventory cannot be billed.",
        isYesNo: false,
        initialFocusIdx: 1,
      );
      return; // Strictly block selection
    }

    final daysRemaining = expDate.difference(now).inDays;
    if (daysRemaining <= 60 && daysRemaining > 0) {
      bool? proceed = await _showFastDialog(
        title: "NEAR EXPIRY WARNING",
        content: "Batch '${product.batch}' expires in $daysRemaining days (${product.expiry}). Proceed with billing?",
        isYesNo: true,
        initialFocusIdx: 2,
      );
      if (!mounted) return;
      if (proceed != true) return; // User chose not to proceed
    }

    _commitSelection(row, product);
  }

  void _finalizeBatchSelection(Product p) async {
    final row = _focusedRowIndex;
    int usedInOtherRows = _getCrossRowStockUsed(p, row);
    int origQty = _originalInvoiceBatchQtys["${p.id}|${p.batch.trim().toUpperCase()}"] ?? 0;
    int available = p.stock + origQty - usedInOtherRows;

    if (available <= 0) {
      final res = await _showFastDialog(
        title: "Zero Stock",
        content: "Batch '${p.batch}' currently has no available stock (${p.stock} total, $usedInOtherRows used in this entry).",
        showSpecialOrder: true,
        initialFocusIdx: 1, 
      );
      if (!mounted) return;

      if (res == "special") {
        setState(() {
          _getGridCtrl(row, 1).clear();
          if (row < _items.length) {
            _items.removeAt(row);
          }
          _orderType = 1;
          _showSpecialOrderSidebar = true;
          _isSpecialOrderMinimized = false;
        });
        _triggerSpecialOrderFocus(p.name, 1);
      } else {
        if (!mounted) return;
        final pharma = Provider.of<PharmacyProvider>(context, listen: false);
        pharma.logStockEnquiry(productName: p.name, productId: p.id, requestedQty: 1, agent: _agentCtrl.text);
      }
      return; // Block selection
    }

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
        it.product.packSize = p.packSize > 0 ? p.packSize : it.product.packSize;
        it.packin = p.packSize > 0 ? p.packSize : (it.packin > 0 ? it.packin : 1);

        if (p.mrp > 0) it.product.mrp = p.mrp;
        if (p.salePrice > 0) it.product.salePrice = p.salePrice;
        double ps = it.packin.toDouble();
        it.mrp = it.product.mrp / ps;
        it.sRate = (it.product.salePrice > 0 ? it.product.salePrice : it.product.mrp) / ps;
        it.taxableSP = it.sRate;
        it.gstPercent = p.gstPercent;
        _calculateItem(row);
      }
    });
    
    _isSelectingBatch = false;
    _batchList.value = [];
    _moveFocus(_focusedRowIndex, 7);
    _isSelectingFromDropdown = false;
  }

  void _commitSelection(int row, Product p, {bool stayOnProduct = false}) {
    _productSearchDebouncer.cancel();
    _searchList.value = [];
    if (p.id == "NEW") {
      _promptCreateNewProduct(p.name);
      return;
    }
    _isSelectingFromDropdown = true; // LOCKS FOCUS
    _saveUndoState();

    if (p.schedule.toUpperCase().contains('H1')) {
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
          if (p.sDiscPercent > 0 && (it.discPercent == 0 || it.discPercent == 0.0)) {
            it.discPercent = p.sDiscPercent;
            it.discAmt = (unitSRate * it.qty * p.sDiscPercent) / 100.0;
          }

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
      final pharma = Provider.of<PharmacyProvider>(context, listen: false);

      // AUTO-FETCH BEST FEFO BATCH IF SELECTED ITEM IS FROM PRODUCT MASTER (p.batch IS EMPTY)
      Product targetProduct = p;
      if (targetProduct.batch.trim().isEmpty) {
        final fefo = pharma.getAutoFefoBatch(p.name) ??
            pharma.getBatchesForProduct(p.id, p.name).where((b) => b.stock > 0).firstOrNull;
        if (fefo != null) {
          targetProduct = fefo;
        }
      }

      final masterMatch = pharma.masterNameMap[targetProduct.name.trim().toUpperCase()];
      String resRack = targetProduct.rack.trim().isNotEmpty 
          ? targetProduct.rack.trim() 
          : (masterMatch?.rack.trim() ?? "");
      double resDisc = targetProduct.sDiscPercent > 0 
          ? targetProduct.sDiscPercent 
          : (masterMatch?.sDiscPercent ?? 0.0);

      int trueLooseStock = targetProduct.stock;
      int packSize = targetProduct.packSize > 0 ? targetProduct.packSize : (masterMatch?.packSize ?? 1);
      double pack = packSize.toDouble();
      double unitMrp = targetProduct.mrp > 0 ? (targetProduct.mrp / pack) : ((masterMatch?.mrp ?? 0.0) / pack);
      double unitSRate = targetProduct.salePrice > 0 ? (targetProduct.salePrice / pack) : unitMrp;
      double unitLCost = targetProduct.landingCost > 0 ? (targetProduct.landingCost / pack) : (targetProduct.purchaseRate / pack);

      setState(() {
        _getGridCtrl(row, 2, targetProduct.name).text = targetProduct.name;
        _getGridCtrl(row, 3).text = resRack;
        _getGridCtrl(row, 4).text = _cleanBatch(targetProduct.batch);
        _getGridCtrl(row, 5).text = targetProduct.expiry;

        if (row == _items.length) {
          final newItem = SaleItem(
            product: Product(
              id: targetProduct.id,
              name: targetProduct.name,
              batch: targetProduct.batch,
              expiry: targetProduct.expiry,
              packSize: packSize,
              mrp: targetProduct.mrp > 0 ? targetProduct.mrp : (masterMatch?.mrp ?? 0.0),
              salePrice: targetProduct.salePrice > 0 ? targetProduct.salePrice : targetProduct.mrp,
              purchaseRate: targetProduct.purchaseRate,
              landingCost: targetProduct.landingCost,
              gstPercent: targetProduct.gstPercent > 0 ? targetProduct.gstPercent : (masterMatch?.gstPercent ?? 12.0),
              rack: resRack,
              sDiscPercent: resDisc,
              category: targetProduct.category,
              manufacturer: targetProduct.manufacturer,
              genericName: targetProduct.genericName,
              stock: trueLooseStock,
            ),
            qty: 1, packin: packSize, mrp: unitMrp, sRate: unitSRate, taxableSP: unitSRate,
            discPercent: resDisc > 0 ? resDisc : 0,
            discAmt: resDisc > 0 ? ((unitSRate * resDisc) / 100.0) : 0,
            gstPercent: targetProduct.gstPercent > 0 ? targetProduct.gstPercent : (masterMatch?.gstPercent ?? 12.0),
            total: unitSRate,
            landingCost: unitLCost, purchaseRate: targetProduct.purchaseRate / pack,
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
            id: targetProduct.id,
            name: targetProduct.name,
            batch: targetProduct.batch,
            expiry: targetProduct.expiry,
            packSize: packSize,
            mrp: targetProduct.mrp > 0 ? targetProduct.mrp : (masterMatch?.mrp ?? 0.0),
            salePrice: targetProduct.salePrice > 0 ? targetProduct.salePrice : targetProduct.mrp,
            purchaseRate: targetProduct.purchaseRate,
            landingCost: targetProduct.landingCost,
            gstPercent: targetProduct.gstPercent > 0 ? targetProduct.gstPercent : (masterMatch?.gstPercent ?? 12.0),
            rack: resRack,
            category: targetProduct.category,
            manufacturer: targetProduct.manufacturer,
            genericName: targetProduct.genericName,
            stock: trueLooseStock,
          );
          it.packin = packSize; it.mrp = unitMrp; it.sRate = unitSRate;
          it.taxableSP = unitSRate; it.landingCost = unitLCost;
          it.purchaseRate = targetProduct.purchaseRate / pack;
          it.gstPercent = targetProduct.gstPercent > 0 ? targetProduct.gstPercent : (masterMatch?.gstPercent ?? 12.0);
          if (resDisc > 0 && it.discPercent == 0) it.discPercent = resDisc;
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final fn = _getGridFocusNode(row, 2);
            FocusScope.of(context).requestFocus(fn);
            final ctrl = _getGridCtrl(row, 2);
            if (ctrl.text.isNotEmpty) {
              ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
            }
          }
        });
      } else {
        _moveFocus(row, 4, autoOpen: true);
      }
    }

    _isSelectingFromDropdown = false;
  }

  // Pure math calculation: zero text controller touches, zero UI overhead
  void _recalculateItemSilent(SaleItem it, {required bool isGstMode}) {
    _recalculateItem(it, isGstMode: isGstMode);
  }

  // UI-facing calculation: only updates controllers if not currently focused on them
  void _calculateItem(int row) {
    if (row >= _items.length) return;
    final it = _items[row];

    _recalculateItemSilent(it, isGstMode: _gstType == 1);

    String formatMoney(double val) => (val * 1000) % 10 == 0 ? val.toStringAsFixed(2) : val.toStringAsFixed(3);

    // Only update read-only display cells, avoid touching active input controllers during typing
    if (!_getGridFocusNode(row, 9).hasFocus) {
      _getGridCtrl(row, 9).text = formatMoney(it.product.mrp);
    }
    if (!_getGridFocusNode(row, 10).hasFocus) {
      _getGridCtrl(row, 10).text = formatMoney(it.mrp);
    }
    if (!_getGridFocusNode(row, 11).hasFocus) {
      _getGridCtrl(row, 11).text = it.discPercent.toStringAsFixed(2);
    }
    if (!_getGridFocusNode(row, 12).hasFocus) {
      _getGridCtrl(row, 12).text = formatMoney(it.discAmt);
    }
    double gVal = _gstType == 1 ? TaxCalculator.roundGstPercent(it.gstPercent) : 0.0;
    if (!_getGridFocusNode(row, 13).hasFocus) {
      _getGridCtrl(row, 13).text = gVal % 1 == 0 ? gVal.toInt().toString() : gVal.toStringAsFixed(1);
    }
    if (!_getGridFocusNode(row, 14).hasFocus) {
      _getGridCtrl(row, 14).text = formatMoney(it.total);
    }

    _calculateFooter();
  }

  void _recalculateItem(SaleItem item, {bool isGstMode = false}) {
    if (item.packin <= 0) {
      item.packin = item.product.packSize > 0 ? item.product.packSize : 1;
    }
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
    } else if (item.discAmt > 0 && grossPaise > 0) {
      item.discPercent = (item.discAmt / (grossPaise / 100.0)) * 100.0;
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

    // Minimum line total requirement: Only force if total is 0 and no selling rate/price was provided
    if (item.total <= 0 && item.sRate <= 0 && (item.qty > 0 || item.fQty > 0)) {
      item.total = 1.00;
    }

    // Unit Landing Cost Calculation:
    // Effective pack landed cost divided by packing size = landed cost per single tablet
    int netSalesTaxablePaise = (isGstMode && item.gstPercent > 0)
        ? TaxCalculator.calculateInclusivePaise(netTaxablePaise, item.gstPercent).taxablePaise
        : netTaxablePaise;

    double netSalesTaxable = netSalesTaxablePaise / 100.0;

    double packLCost = item.product.landingCost > 0 
        ? item.product.landingCost 
        : (item.product.purchaseRate > 0 ? item.product.purchaseRate : 0.0);
    double unitLCost = pack > 0 ? (packLCost / pack) : packLCost;

    item.landingCost = unitLCost;

    // RULE 1: If item has explicit imported/saved profit, keep it 1:1
    if (item.profit != 0) {
      if ((item.qty + item.fQty) > 0) {
        double totalCost = netSalesTaxable - item.profit;
        if (totalCost > 0) {
          item.landingCost = totalCost / (item.qty + item.fQty);
        }
      }
    } else if (item.landingCost > 0) {
      // RULE 2: Profit = Actual Selling Price (Net Taxable) - Total Acquisition Cost
      double totalCost = item.landingCost * (item.qty + item.fQty);
      item.profit = netSalesTaxable - totalCost;
    } else {
      item.profit = 0.0;
    }
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
      final String entryNo = await p.getNextSpecialOrderNo();
      if (!mounted) return;

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
      if (!mounted) return;

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




  double _getFirstDouble(Map<dynamic, dynamic> m, List<String> keys, [double fallback = 0.0]) {
    for (var k in keys) {
      if (m.containsKey(k) && m[k] != null) {
        final v = (m[k] as num?)?.toDouble();
        if (v != null) return v;
      }
    }
    return fallback;
  }

  Future<bool> _loadSaleData(String invNo, {Map<String, dynamic>? initialData}) async {
    AppLogger.instance.info("UI_NAVIGATION", "[ENTRY_OPENED] Opened Sales Entry #${formatSaleDisplayNo(invNo)} ($invNo)");

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
      final data = initialData ?? await p.navigateInvoice(invNo, 'find', isPurchase: false);
      if (!mounted) return false;

      // 1. If data is found (active or deleted), load it normally
      if (data != null && mounted) {
        if (data['is_blank'] == true) {
          FocusScope.of(context).unfocus();
          setState(() {
            _clearGridMaps();
            _isExistingEntry = false;
            _isBlankRecord = true;
            _isDeleted = false;
            _isImported = false;
            _isDirty = false;
            _items.clear();
            _rawEntryNo = data['entry_no']?.toString() ?? invNo;
            _entryNo = cleanEntryNo(_rawEntryNo);
            _entryNoCtrl.text = formatSaleDisplayNo(_entryNo);
            _date = DateTime.now();
            _timeNotifier.value = DateFormat('hh:mm a').format(_date);
            _customerAcc = 'Cash';
            _customerAccCtrl.text = _customerAcc;
            _patientCtrl.text = 'P1';
            _mobileCtrl.text = '';
            _doctorCtrl.text = 'D1';
            _doctorRegNoCtrl.text = '';
            _daysCtrl.text = '0';
            _subTotalCtrl.text = '0.00';
            _netTotalCtrl.text = '0.00';
            _rcvdAmtCtrl.text = '0';
            _balanceCtrl.text = '0.00';
            _footerDiscAmtCtrl.text = '0.00';
            _footerDiscPctCtrl.text = '0';
            _isLoading = false;
          });
          return true;
        }

        // --- SAFE FOCUS TRANSITION ---
        FocusScope.of(context).unfocus();
        if (!mounted) return false;

        final loadedEntryNo = data['entry_no']?.toString() ?? data['invoice_no']?.toString() ?? invNo;
        _rawEntryNo = loadedEntryNo;
        final items = await p.getInvoiceItems(loadedEntryNo, isPurchase: false, financialYear: p.selectedFinancialYear);
        if (!mounted) return false;
        if (!mounted) return false;

        // Use O(1) cached maps for fast batch & master product lookup
        final productBatchMap = p.productBatchMap;
        final masterIdMap = p.masterIdMap;
        final masterNameMap = p.masterNameMap;

        setState(() {
          // RESET TO DEFAULTS FIRST to avoid data bleeding
          _clearGridMaps();
          _isExistingEntry = true;
          _isBlankRecord = false;
          _isDirty = false; // Reset dirty flag on load
          _isDeleted = (data['is_deleted'] == 1 || data['is_deleted'] == true || data['is_deleted'] == '1'); // Check if deleted
          _isImported = (data['is_imported'] == 1 || data['is_imported'] == true || data['is_imported'] == '1');
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
          final actualDbEntry = data['entry_no']?.toString() ?? invNo;
          _rawEntryNo = actualDbEntry;
          String rawEntry = cleanEntryNo(actualDbEntry);
          _entryNo = rawEntry;
          _entryNoCtrl.text = formatSaleDisplayNo(_entryNo);
          _date = DateTime.tryParse(data['date'].toString()) ?? DateTime.now();
          _timeNotifier.value = DateFormat('hh:mm a').format(_date);
          _customerAcc = data['customer_acc']?.toString() ?? 'Cash';
          _customerAccCtrl.text = _customerAcc;
          _gstType = (data['tax_type'] == "Gst") ? 1 : 2;

          String rawPat = data['patient']?.toString().trim() ?? '';
          if (rawPat.isEmpty || rawPat.toLowerCase() == 'general' || rawPat.toLowerCase() == 'unknown') {
            rawPat = 'P1';
          }
          _patientCtrl.text = rawPat;
          _mobileCtrl.text = data['mobile']?.toString() ?? '';

          String rawDoc = data['doctor']?.toString().trim() ?? '';
          if (rawDoc.isEmpty || rawDoc.toLowerCase() == 'unknown' || rawDoc.toLowerCase() == 'dr. unknown') {
            rawDoc = 'D1';
          }
          _doctorCtrl.text = rawDoc;
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
            String pId = m['product_id']?.toString() ?? "";
            String pName = (m['product_name'] ?? '').toString().trim().toUpperCase();
            String pBatch = m['batch_number']?.toString().trim().toUpperCase() ?? "";
            String key = "$pId|$pBatch";

            final batchMatch = productBatchMap[key] ?? productBatchMap["$pName|$pBatch"];
            final masterMatch = masterIdMap[pId] ?? masterNameMap[pName];

            int packin = (m['packin'] as num?)?.toInt() ?? (m['packing'] as num?)?.toInt() ?? 0;
            if (packin <= 0) {
              packin = batchMatch?.packSize ?? masterMatch?.packSize ?? 1;
            }
            if (packin <= 0) packin = 1;
            double pack = packin.toDouble();

            double packMrp = (m['mrp'] as num?)?.toDouble() ?? 0.0;
            double pRateVal = (m['purchase_rate'] as num?)?.toDouble() ?? 0.0;
            double lCostVal = (m['landing_cost'] as num?)?.toDouble() ?? 0.0;

            // Rates stored in sales_items are per loose unit; convert to pack rate for consistent evaluation against batch/master fallbacks
            if (pRateVal > 0 && m['purchase_rate'] != null) {
              pRateVal = pRateVal * pack;
            }
            if (lCostVal > 0 && m['landing_cost'] != null) {
              lCostVal = lCostVal * pack;
            }

            // Fallback for missing/zero rates from batch or product master
            if (packMrp <= 0) {
              packMrp = batchMatch?.mrp ?? masterMatch?.mrp ?? 0.0;
            }
            if (pRateVal <= 0) {
              pRateVal = batchMatch?.purchaseRate ?? masterMatch?.purchaseRate ?? 0.0;
            }
            if (lCostVal <= 0) {
              lCostVal = batchMatch?.landingCost ?? (pRateVal > 0 ? pRateVal : (masterMatch?.purchaseRate ?? 0.0));
            }

            double sRateVal = (m['s_rate'] as num?)?.toDouble() ?? (m['sale_rate'] as num?)?.toDouble() ?? 0.0;
            double unitSRate = sRateVal > 0 ? sRateVal : (packMrp > 0 ? (packMrp / pack) : (batchMatch?.salePrice ?? 0.0) / pack);
            double unitMrp = packMrp > 0 ? (packMrp / pack) : unitSRate;
            double profitVal = (m['profit'] as num?)?.toDouble() ?? 0.0;

            double itemGst = _getFirstDouble(m, [
              'gst_percent', 'tax_percent', 'gst_rate', 'gst_perc', 'gst_per',
              'gst_pct', 'tax_rate', 'vat_percent', 'vat_rate', 'gst', 'tax'
            ], -1.0);

            if (itemGst < 0 || (itemGst == 0.0 && _gstType == 1 && (batchMatch?.gstPercent ?? masterMatch?.gstPercent ?? 0) > 0)) {
              itemGst = batchMatch?.gstPercent ?? masterMatch?.gstPercent ?? 0.0;
            }
            if (itemGst < 0) itemGst = 0.0;

            double itemDiscPct = _getFirstDouble(m, [
              'disc_percent', 'discount_percent', 's_disc_percent', 'disc_perc',
              'disc_per', 'disc_pct', 'dis_percent', 'dis_per', 's_disc', 'trade_disc'
            ], 0.0);

            double itemDiscAmt = _getFirstDouble(m, [
              'disc_amt', 'discount_amount', 'disc_amount', 'dis_amt', 'discount'
            ], 0.0);

            double grossForDisc = unitSRate * ((m['qty'] as num?)?.toInt() ?? (m['quantity'] as num?)?.toInt() ?? 1);
            if (itemDiscPct > 0 && (itemDiscPct == itemDiscAmt || (itemDiscAmt > 0 && itemDiscPct > 50)) && grossForDisc > 0 && itemDiscAmt < grossForDisc) {
              itemDiscPct = (itemDiscAmt / grossForDisc) * 100.0;
            } else if (itemDiscPct > 0 && itemDiscAmt == 0.0 && grossForDisc > 0) {
              if (itemDiscPct > 50 && itemDiscPct <= grossForDisc) {
                itemDiscAmt = itemDiscPct;
                itemDiscPct = (itemDiscAmt / grossForDisc) * 100.0;
              } else {
                itemDiscAmt = (grossForDisc * itemDiscPct) / 100.0;
              }
            } else if (itemDiscPct == 0.0 && itemDiscAmt > 0 && grossForDisc > 0) {
              itemDiscPct = (itemDiscAmt / grossForDisc) * 100.0;
            } else if (itemDiscPct == 0.0 && itemDiscAmt == 0.0) {
              itemDiscPct = batchMatch?.sDiscPercent ?? masterMatch?.sDiscPercent ?? 0.0;
              if (itemDiscPct > 0 && grossForDisc > 0) {
                itemDiscAmt = (grossForDisc * itemDiscPct) / 100.0;
              }
            }



            final prod = batchMatch ?? Product(
              id: pId,
              name: m['product_name']?.toString() ?? "",
              batch: m['batch_number']?.toString() ?? "",
              expiry: m['expiry_date']?.toString() ?? "",
              mrp: packMrp,
              salePrice: packMrp,
              packSize: packin,
              purchaseRate: pRateVal,
              landingCost: lCostVal,
              gstPercent: TaxCalculator.roundGstPercent(itemGst),
              supplier: m['supplier_name']?.toString() ?? "",
            );

            // Prefer saved invoice product name if present
            String savedItemName = (m['product_name'] ?? '').toString().trim();
            if (savedItemName.isNotEmpty) {
              prod.name = savedItemName;
            }

            // Attach master generic name and rack if batch product lacks them
            if (prod.genericName.isEmpty && masterMatch != null) {
              prod.genericName = masterMatch.genericName;
            }

            String itemRack = (m['rack'] ?? m['master_rack'] ?? m['master_rack_id'] ?? '').toString().trim();
            if (itemRack.isNotEmpty) {
              prod.rack = itemRack;
            } else if (prod.rack.isEmpty) {
              prod.rack = (batchMatch?.rack.trim().isNotEmpty == true) ? batchMatch!.rack : (masterMatch?.rack.trim() ?? '');
            }

            // Ensure prod has pack-level MRP stored
            prod.mrp = packMrp;
            prod.packSize = packin;

            String itemExpiry = (m['expiry_date'] ?? m['expiry'] ?? m['exp_date'] ?? '').toString().trim();
            if (itemExpiry.isNotEmpty && itemExpiry != 'MM/YY') {
              prod.expiry = itemExpiry;
            } else if (prod.expiry.isEmpty || prod.expiry == 'MM/YY') {
              prod.expiry = (batchMatch?.expiry.trim().isNotEmpty == true && batchMatch!.expiry != 'MM/YY') ? batchMatch.expiry : '';
            }

            if (prod.sDiscPercent <= 0 && itemDiscPct > 0) {
              prod.sDiscPercent = itemDiscPct;
            }

            // CRITICAL: Clone product so each row owns an isolated copy in memory
            final isolatedProd = _cloneProduct(prod);

            // Track original stock reserved by this invoice
            _originalInvoiceBatchQtys[key] = (_originalInvoiceBatchQtys[key] ?? 0) + ((m['qty'] as num?)?.toInt() ?? 0);

            _items.add(SaleItem(
              product: isolatedProd, // <--- Use the isolated copy
              qty: (m['qty'] as num?)?.toInt() ?? (m['quantity'] as num?)?.toInt() ?? 0,
              packin: packin,
              mrp: unitMrp,
              sRate: unitSRate,
              taxableSP: (m['taxable_sp'] as num?)?.toDouble() ?? unitSRate,
              discPercent: itemDiscPct,
              discAmt: itemDiscAmt,
              gstPercent: TaxCalculator.roundGstPercent(itemGst),
              gstAmt: (m['gst_amt'] as num?)?.toDouble() ?? 0.0,
              cgstAmt: (m['cgst_amt'] as num?)?.toDouble() ?? 0.0,
              sgstAmt: (m['sgst_amt'] as num?)?.toDouble() ?? 0.0,
              total: (m['total'] as num?)?.toDouble() ?? 0.0,
              profit: profitVal,
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
          _loadedInvoiceUpdatedAt = data['updated_at']?.toString() ?? data['date']?.toString() ?? DateTime.now().toIso8601String();

          _highlightedRowIndices.clear();
          if (widget.highlightProduct != null && widget.highlightProduct!.trim().isNotEmpty) {
            final target = widget.highlightProduct!.trim().toUpperCase();
            for (int i = 0; i < _items.length; i++) {
              final pName = _items[i].product.name.trim().toUpperCase();
              if (pName.isNotEmpty && (pName == target || pName.contains(target) || target.contains(pName))) {
                _highlightedRowIndices.add(i);
              }
            }
          }
        });

        if (_highlightedRowIndices.isNotEmpty) {
          _focusNotifier.value = IntPair(_highlightedRowIndices.first, 2);
        } else {
          // Remove focus so nothing is highlighted when viewing history
          _focusNotifier.value = null;
        }
        return true;
      }
      // 2. BLANK OR UNUSED ENTRY NUMBER
      else if (mounted) {
        FocusScope.of(context).unfocus();
        if (mounted) setState(() => _isLoading = false);
        await Future.delayed(Duration.zero);
        if (!mounted) return false;

        _resetPage();
        _entryNo = cleanEntryNo(invNo);
        _isExistingEntry = false;
        _isDeleted = false;
        setState(() {});
        return true;
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
    if (_isSaving || _isLoading || _isDialogOpen) return;

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

    _isDialogOpen = true;
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
                          style: const TextStyle(fontSize: 14, color: Colors.black),
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
    if (mounted) setState(() => _isDialogOpen = false);

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

  String cleanEntryNo(String entryNo) {
    String clean = entryNo.trim();
    if (clean.startsWith("SO-")) clean = clean.substring(3);
    if (clean.startsWith("ORD-")) clean = clean.substring(4);
    if (clean.contains('_')) clean = clean.substring(clean.indexOf('_') + 1);
    clean = clean.replaceAll(RegExp(r'^\d{4}[-/]\d{2,4}[-/_]'), '');
    clean = clean.replaceAll(RegExp(r'^\d{2}[-/]\d{2}[-/_]'), '');
    return clean;
  }

  void _navigateEntry(String dir) async {
    // 0. Mutex lock against rapid clicks, ghost touch, and multi-triggers
    if (_isNavigating || _isLoading || _isSaving || _isDeleting) return;
    _isNavigating = true;
    if (mounted) setState(() {});

    try {
      // 1. Unsaved edits protection
      if (hasUnsavedChanges()) {
        bool? discard = await _promptDiscardChanges();
        if (!mounted || discard != true) {
          return; // User chose to stay
        }
      }
      if (!mounted) return;

      _closeAllDropdowns();
      final p = Provider.of<PharmacyProvider>(context, listen: false);

      if (dir == 'next') {
        // If currently looking at an unsaved new entry, do not allow jumping further
        if (!_isExistingEntry) {
          _showFastDialog(
            title: "Navigation Blocked", 
            content: "Save Entry #${formatSaleDisplayNo(_entryNo)} first to unlock the next entry number.",
          );
          return;
        }
      }

      // 2. Database navigation step with exact target financial year
      final String currentNavKey = _rawEntryNo.isNotEmpty ? _rawEntryNo : _entryNo;
      final String targetFy = _originalLoadedInvoice?.financialYear ?? p.selectedFinancialYear;
      final data = await p.navigateInvoice(
        currentNavKey, 
        dir, 
        isPurchase: false, 
        targetFinancialYear: targetFy,
        isExistingEntry: _isExistingEntry,
      );
      if (!mounted) return;
      if (data != null) {
        if (data['is_blank'] == true) {
          _resetPage();
          _rawEntryNo = data['entry_no'].toString();
          _entryNo = cleanEntryNo(_rawEntryNo);
          _entryNoCtrl.text = formatSaleDisplayNo(_entryNo);
          setState(() {});
        } else {
          await _loadSaleData(data['entry_no'].toString(), initialData: data);
        }
      } else if (dir == 'next') {
        _showFastDialog(title: "Navigation Limit", content: "MAX ENTRY LIMIT REACHED");
      } else if (dir == 'prev') {
        _showFastDialog(title: "Navigation Limit", content: "FIRST RECORD REACHED (Entry #${formatSaleDisplayNo(_entryNo)})");
      }
    } finally {
      if (mounted) {
        setState(() => _isNavigating = false);
      }
    }
  }



  // --- EDIT CONFIRMATION METHOD ---
  void _editSale() async {
    AppLogger.instance.info("USER_ACTION", "[EDIT_CLICKED] Edit/Update initiated for Sales Entry #${formatSaleDisplayNo(_entryNo)} ($_entryNo)");

    if (!ServerConfigService.instance.isConnected) {
      _showFastDialog(
        title: "Server Disconnected",
        content: "SERVER DISCONNECTED — WORKING IN OFFLINE READ-ONLY MODE\n\nCannot update sales invoice while disconnected from Supabase Cloud Server.",
      );
      return;
    }

    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final String? origTerminalId = _originalLoadedInvoice?.agent; // Or terminal context

    if (!p.canEditCrossTerminalEntry(origTerminalId)) {
      _showFastDialog(
        title: "Online Connection Required",
        content: "This invoice was created on another counter.\n\nEditing entries from other counters requires an active internet connection to prevent edit conflicts.",
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.save_rounded, color: Colors.blue, size: 28),
            SizedBox(width: 10),
            Text("Update Sales Invoice", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text(
          "Are you sure you want to update Entry #${formatSaleDisplayNo(_entryNo)}?\nAll modifications will be saved to your stock and customer ledger.",
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
            child: const Text("Update Invoice", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (!mounted) return;

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
    if (!mounted) return;
  }

  void handleAsyncPdfExport(SaleInvoice invoice, CompanyProfile company) async {
    final pdfBytes = await PdfWorkerService.generateInvoicePdfInBackground(
      invoice: invoice, 
      company: company,
    );
    if (!mounted) return;
    
    await Printing.layoutPdf(onLayout: (format) async => pdfBytes);
    if (!mounted) return;
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
    if (!mounted) return;
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
        await p.exportSalesToExcel(result);
        if (!mounted) return;
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Exported successfully!")));
      }
    } catch (e) {
      _showFastDialog(title: "Export Error", content: e.toString());
    }
  }

  void _copySalesGridToClipboard() async {
    final validItems = _items.where((it) => it.product.name.trim().isNotEmpty).toList();
    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No items in sales grid to copy."), duration: Duration(seconds: 2)),
      );
      return;
    }

    final StringBuffer sb = StringBuffer();
    for (var it in validItems) {
      sb.writeln("${it.product.name.trim()}\t${it.qty}");
    }

    await Clipboard.setData(ClipboardData(text: sb.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Copied ${validItems.length} items to clipboard!"),
        backgroundColor: Colors.blue.shade800,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _pasteSalesGridFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim() ?? "";
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Clipboard is empty or contains no text."), duration: Duration(seconds: 2)),
      );
      return;
    }

    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final lines = text.split(RegExp(r'[\r\n]+'));

    List<Map<String, dynamic>> addedItems = [];
    List<Map<String, dynamic>> shortageItems = [];
    List<String> unavailableItems = [];

    for (var line in lines) {
      String cleanLine = line.trim();
      if (cleanLine.isEmpty) continue;

      String name = "";
      int requestedQty = 1;

      if (cleanLine.contains('\t')) {
        final parts = cleanLine.split('\t');
        name = parts[0].trim();
        if (parts.length > 1) requestedQty = int.tryParse(parts[1].trim()) ?? 1;
      } else if (cleanLine.contains('|')) {
        final parts = cleanLine.split('|');
        name = parts[0].trim();
        if (parts.length > 1) requestedQty = int.tryParse(parts[1].trim()) ?? 1;
      } else if (cleanLine.contains(',')) {
        final parts = cleanLine.split(',');
        name = parts[0].trim();
        if (parts.length > 1) requestedQty = int.tryParse(parts[1].trim()) ?? 1;
      } else {
        name = cleanLine;
        requestedQty = 1;
      }

      if (name.isEmpty) continue;
      if (requestedQty <= 0) requestedQty = 1;

      final matches = p.searchProducts(name, includeGenerics: false);
      if (matches.isEmpty) {
        unavailableItems.add("$name (Requested: $requestedQty)");
        continue;
      }

      final matchedProd = matches.first;
      final batches = p.getBatchesForProduct(matchedProd.id, matchedProd.name);
      int totalLiveStock = batches.isNotEmpty
          ? batches.fold(0, (sum, b) => sum + b.stock)
          : matchedProd.stock;

      if (totalLiveStock <= 0) {
        unavailableItems.add("${matchedProd.name} (0 Stock Available, Requested: $requestedQty)");
        continue;
      }

      int actualAddedQty = requestedQty;
      if (requestedQty > totalLiveStock) {
        actualAddedQty = totalLiveStock;
        shortageItems.add({
          'name': matchedProd.name,
          'requested': requestedQty,
          'added': totalLiveStock,
          'missing': requestedQty - totalLiveStock,
        });
      }

      final candidateBatch = batches.isNotEmpty
          ? (p.getAutoFefoBatch(matchedProd.name) ?? batches.first)
          : matchedProd;

      _addItemToGridFromPaste(candidateBatch, actualAddedQty);
      addedItems.add({
        'name': candidateBatch.name,
        'batch': candidateBatch.batch,
        'qty': actualAddedQty,
      });
    }

    if (addedItems.isNotEmpty) {
      _calculateFooter();
      setState(() {});
    }

    if (shortageItems.isNotEmpty || unavailableItems.isNotEmpty) {
      _showClipboardStockShortageDialog(
        addedCount: addedItems.length,
        shortageItems: shortageItems,
        unavailableItems: unavailableItems,
      );
    } else if (addedItems.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Successfully pasted ${addedItems.length} items from clipboard into sales bill!"),
          backgroundColor: Colors.green.shade800,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No matching products with available stock were found in clipboard text."),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _addItemToGridFromPaste(Product p, int qty) {
    int pack = p.packSize > 0 ? p.packSize : 1;
    double unitMrp = p.mrp / pack;
    double unitSRate = (p.salePrice > 0 ? p.salePrice : p.mrp) / pack;
    double unitLCost = p.landingCost / pack;

    SaleItem newItem = SaleItem(
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
      qty: qty,
      packin: pack,
      mrp: unitMrp,
      sRate: unitSRate,
      taxableSP: unitSRate,
      discPercent: 0,
      discAmt: 0,
      gstPercent: p.gstPercent,
      total: unitSRate * qty,
      landingCost: unitLCost,
      purchaseRate: p.purchaseRate / pack,
    );

    _recalculateItemSilent(newItem, isGstMode: _gstType == 1);
    _items.add(newItem);
    int newRowIdx = _items.length - 1;
    _getGridCtrl(newRowIdx, 1).text = newItem.product.name;
    _getGridCtrl(newRowIdx, 2).text = newItem.product.batch;
    _getGridCtrl(newRowIdx, 3).text = newItem.product.expiry;
    _getGridCtrl(newRowIdx, 4).text = newItem.product.rack;
    _getGridCtrl(newRowIdx, 5).text = newItem.packin.toString();
    _getGridCtrl(newRowIdx, 7).text = newItem.qty.toString();
  }

  void _showClipboardStockShortageDialog({
    required int addedCount,
    required List<Map<String, dynamic>> shortageItems,
    required List<String> unavailableItems,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: Colors.orange.shade800, size: 26),
            const SizedBox(width: 10),
            const Text("Clipboard Paste Stock Report", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Added $addedCount item(s) to sales bill. Below are stock shortages and unavailable items:",
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (shortageItems.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(4)),
                          child: Text("PARTIAL STOCK SHORTAGES (${shortageItems.length})",
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                        ),
                        const SizedBox(height: 6),
                        ...shortageItems.map((s) => Padding(
                          padding: const EdgeInsets.only(bottom: 6, left: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  "${s['name']} — Requested: ${s['requested']}, Added: ${s['added']} (Shortage: ${s['missing']})",
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        )),
                        const SizedBox(height: 12),
                      ],
                      if (unavailableItems.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                          child: Text("NOT AVAILABLE IN STOCK (${unavailableItems.length})",
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade900)),
                        ),
                        const SizedBox(height: 6),
                        ...unavailableItems.map((u) => Padding(
                          padding: const EdgeInsets.only(bottom: 6, left: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  u,
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red.shade900),
                                ),
                              ),
                            ],
                          ),
                        )),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade800),
            child: const Text("OK, GOT IT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _saveSale({
    bool isEdit = false,
    String? primaryAcc,
    double? primaryAmt,
    String? secondaryAcc,
    double? secondaryAmt,
  }) async {
    AppLogger.instance.info("USER_ACTION", "[SAVE_CLICKED] Save button clicked for Sales Entry #${formatSaleDisplayNo(_entryNo)} ($_entryNo) [IsEdit: $isEdit]");

    // 1. Hard Re-entrancy Guard (Stops duplicate saves)
    if (_isSaving || _isLoading) return;

    // === STRICT OFFLINE SAVE BLOCK ===
    if (!ServerConfigService.instance.isConnected) {
      _isSaving = false;
      if (mounted) setState(() {});
      AppDialogs.showFastDialog(
        context: context,
        title: "Server Disconnected",
        content: "SERVER DISCONNECTED — WORKING IN OFFLINE READ-ONLY MODE\n\nCannot save sales invoice while disconnected from Supabase Cloud Server.",
      );
      return;
    }

    _isSaving = true;
    if (mounted) setState(() {});

    final p = Provider.of<PharmacyProvider>(context, listen: false);

      // --- MANDATORY FIELDS CHECK (Account Name, Patient Name, Doctor Name) ---
      final String chosenPrimaryAcc = (primaryAcc != null && primaryAcc.trim().isNotEmpty)
          ? primaryAcc.trim()
          : (_customerAccCtrl.text.trim().isNotEmpty
              ? _customerAccCtrl.text.trim()
              : (_customerAcc.trim().isNotEmpty ? _customerAcc.trim() : "Cash"));
      final String chosenPatient = _patientCtrl.text.trim().isNotEmpty ? _patientCtrl.text.trim() : "P1";
      final String chosenDoctor = _doctorCtrl.text.trim().isNotEmpty ? _doctorCtrl.text.trim() : "D1";

      if (chosenPrimaryAcc.isEmpty) {
        _customerAccFocus.requestFocus();
        _isSaving = false;
        if (mounted) setState(() {});
        _showFastDialog(
          title: "Validation Error",
          content: "Account Name is mandatory. Please enter Account Name before saving.",
        );
        return;
      }

      final validItems = _items.where((it) => it.product.name.trim().isNotEmpty).toList();
      if (validItems.isEmpty || _cachedValidationError != null) {
        _isSaving = false;
        if (mounted) setState(() {});
        final errText = _cachedValidationError ?? "Please add at least one valid item before saving.";
        _showFastDialog(title: "Incomplete Data", content: errText);
        return;
      }

    // --- Statutory Schedule H1 / Schedule X / Narcotic Compliance Guard ---
    final regulatedItems = validItems.where((it) {
      String sched = it.product.schedule.toUpperCase();
      return sched.contains("H1") || sched.contains("X") || sched.contains("NARCOTIC");
    }).toList();

    if (regulatedItems.isNotEmpty) {
      List<String> restrictedNames = regulatedItems.map((it) => "${it.product.name} (Schedule: ${it.product.schedule})").toList();
      _isSaving = false;
      if (mounted) setState(() {});
      final complianceResult = await showDialog<ScheduleH1ComplianceResult>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => ScheduleH1ComplianceDialog(
          initialDoctorName: chosenDoctor,
          initialPatientName: chosenPatient,
          restrictedItemNames: restrictedNames,
        ),
      );
      if (!mounted) return;

      if (complianceResult == null) {
        return; // User cancelled statutory compliance entry
      }

      if (complianceResult.doctorName.trim().isEmpty) {
        _showFastDialog(
          title: "Validation Error",
          content: "Doctor Name is mandatory before saving.",
        );
        return;
      }

      if (complianceResult.patientName.trim().isEmpty) {
        _showFastDialog(
          title: "Validation Error",
          content: "Patient Name is mandatory before saving.",
        );
        return;
      }

      _doctorCtrl.text = complianceResult.doctorName;
      _doctorRegNoCtrl.text = complianceResult.doctorRegNo;
      _patientCtrl.text = complianceResult.patientName;
      _isSaving = true;
      if (mounted) setState(() {});
    }

    if (!mounted) return;

    // 1. Single O(N) pass for stock usage & pure math (no redundant UI controller writes)
    double sub = 0.0;
    for (var it in validItems) {
      _recalculateItemSilent(it, isGstMode: _gstType == 1);
      sub += it.total;
    }

    // Build combined batch usage map across ALL rows before saving
    Map<String, int> combinedBillBatchUsage = {};
    for (var it in validItems) {
      String resolvedProdId = it.product.id.trim();
      if (resolvedProdId.isEmpty) {
        resolvedProdId = p.getProductMasterByName(it.product.name)?.id.trim() ?? "";
        if (resolvedProdId.isNotEmpty) {
          it.product = it.product.copyWith(id: resolvedProdId);
        }
      }
      if (resolvedProdId.isEmpty || it.product.batch.trim().isEmpty) continue;
      
      String key = "$resolvedProdId|${it.product.batch.trim().toUpperCase()}";
      combinedBillBatchUsage[key] = (combinedBillBatchUsage[key] ?? 0) + it.qty;
    }

    // --- PRE-SAVE BATCH STOCK INTEGRITY GATE ---
    List<String> zeroStockViolations = [];
    for (var entry in combinedBillBatchUsage.entries) {
      final parts = entry.key.split('|');
      final pId = parts[0];
      final batchNo = parts[1];
      final requiredQty = entry.value;

      int availableStock = 0;
      final matchingProduct = p.products.cast<Product?>().firstWhere(
        (prod) => prod != null && prod.id == pId && prod.batch.trim().toUpperCase() == batchNo,
        orElse: () => null,
      );
      if (matchingProduct != null) {
        availableStock = matchingProduct.stock;
      }

      if (availableStock < requiredQty) {
        final prodName = matchingProduct?.name ?? p.getProductMasterByName(pId)?.name ?? "Product";
        zeroStockViolations.add("• $prodName (Batch: $batchNo) — Required: $requiredQty, Available Stock in Batch: $availableStock");
      }
    }

    if (zeroStockViolations.isNotEmpty) {
      _isSaving = false;
      if (mounted) setState(() {});
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
              SizedBox(width: 10),
              Text("Insufficient Batch Stock", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "The following item(s) selected a batch with zero or insufficient stock:\n",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  zeroStockViolations.join("\n\n"),
                  style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Please select an active batch with available stock before saving.",
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade800, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx),
              child: const Text("OK, I WILL FIX BATCH", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    double discAmt = double.tryParse(_footerDiscAmtCtrl.text) ?? 0.0;
    double otherAmt = double.tryParse(_otherChargeAmtCtrl.text) ?? 0.0;
    double lessCr = double.tryParse(_salesReturnCtrl.text) ?? 0.0;

    // --- Role-Based Discount Threshold Protection ---
    if (sub > 0 && discAmt > 0) {
      double discPct = (discAmt / sub) * 100.0;
      if (discPct > 10.0 && p.securityToggles['require_pin_high_discount'] != false) {
        if (!p.isAdminSessionActive()) {
          _isSaving = false;
          if (mounted) setState(() {});
          bool isUnlocked = await PinUnlockDialog.show(
            context,
            p,
            title: "High Discount Protection (${discPct.toStringAsFixed(1)}%)",
            message: "Enter Master Password to approve discount exceeding 10%.",
          );
          if (!mounted) return;
          if (!isUnlocked) {
            return;
          }
          _isSaving = true;
          if (mounted) setState(() {});
        }
      }
    }

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
      if (mounted) setState(() {});
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

    int getTotalLiveStockForBatch(Product prod) {
      final candidateBatches = p.getBatchesForProduct(prod.id, prod.name);
      if (candidateBatches.isNotEmpty) {
        final matching = candidateBatches.where((b) => b.batch.trim().toUpperCase() == prod.batch.trim().toUpperCase());
        if (matching.isNotEmpty) {
          return matching.fold(0, (sum, b) => sum + b.stock);
        }
      }
      return prod.stock;
    }

    // === PRE-SAVE INTEGRITY GATE ===
    List<String> validationErrors = [];
    setState(() => _errorCells.clear());

    for (int i = 0; i < _items.length; i++) {
      final it = _items[i];
      if (it.product.name.trim().isEmpty) continue; // Skip blank trailing rows

      // 1. Verify Product Name exists in Product Master or RAM
      bool isValidProduct = it.product.name.trim().isNotEmpty &&
          (p.getProductMasterByName(it.product.name) != null ||
           p.products.any((prod) => prod.name.trim().toLowerCase() == it.product.name.trim().toLowerCase()) ||
           p.productMaster.any((pm) => pm.name.trim().toLowerCase() == it.product.name.trim().toLowerCase()));
      if (!isValidProduct) {
        _errorCells.putIfAbsent(i, () => {}).add(1); // Column 1: Product Name
        validationErrors.add("Row ${i + 1}: '${it.product.name}' is missing or invalid product name.");
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

      // 4. Verify Stock Availability Constraint
      String resolvedProdId = it.product.id.trim();
      if (resolvedProdId.isEmpty) {
        resolvedProdId = p.getProductMasterByName(it.product.name)?.id.trim() ?? "";
      }
      String batchKey = "$resolvedProdId|${it.product.batch.trim().toUpperCase()}";
      int existingInvoiceQty = isEdit ? (_originalInvoiceBatchQtys[batchKey] ?? 0) : 0;
      int liveStock = getTotalLiveStockForBatch(it.product) + existingInvoiceQty;
      if (liveStock <= 0) {
        _errorCells.putIfAbsent(i, () => {}).add(6);
        validationErrors.add("Row ${i + 1}: '${it.product.name}' has 0 available stock.");
      } else if (it.qty > liveStock) {
        _errorCells.putIfAbsent(i, () => {}).add(6);
        validationErrors.add("Row ${i + 1}: '${it.product.name}' quantity (${it.qty}) exceeds available stock ($liveStock).");
      }
    }

    // If any rule fails, highlight the cells in soft red and block saving entirely
    if (validationErrors.isNotEmpty) {
      _isSaving = false;
      if (mounted) setState(() {});
      AppDialogs.showFastDialog(
        context: context, 
        title: "Save Blocked: Incomplete Data", 
        content: validationErrors.join("\n")
      );
      return;
    }

    // 4. CONCURRENT EDIT LOCK CHECK
    if ((_isExistingEntry || isEdit) && _loadedInvoiceUpdatedAt.isNotEmpty && ServerConfigService.instance.isConnected) {
      final bool hasConflict = await p.checkConcurrentInvoiceEditConflict(
        entryNo: _entryNo,
        loadedUpdatedAt: _loadedInvoiceUpdatedAt,
      );
      if (hasConflict) {
        _isSaving = false;
        if (mounted) setState(() {});
        _showFastDialog(
          title: "Concurrent Edit Lock",
          content: "Invoice #$_entryNo was updated on PC1 while you were editing. Please reload.",
        );
        return;
      }
    }

    // 3. PRE-SAVE STOCK COLLISION GUARD
    if (ServerConfigService.instance.isConnected) {
      final verificationFutures = combinedBillBatchUsage.entries.map((entry) async {
        final parts = entry.key.split('|');
        final prodId = parts[0];
        final batchNo = parts[1];
        final reqQty = entry.value;

        final stockCheck = await p.verifyStockOnlineFirst(
          productId: prodId,
          batchNumber: batchNo,
          requestedQty: reqQty,
        );
        return MapEntry(entry.key, stockCheck);
      }).toList();

      final verificationResults = await Future.wait(verificationFutures);
      for (var res in verificationResults) {
        if (!res.value.isAvailable) {
          final parts = res.key.split('|');
          final batchNo = parts[1];
          _isSaving = false;
          if (mounted) setState(() {});
          _showFastDialog(
            title: "Stock Conflict Warning",
            content: "Stock Conflict Warning: Batch '$batchNo' stock was recently sold on another counter. Only ${res.value.serverStock.toInt()} remaining.",
          );
          return;
        }
      }
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
        _isSaving = false;
        if (mounted) setState(() {});
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
        if (!mounted) return;

        if (!confirmSave) return;
        _isSaving = true;
        if (mounted) setState(() {});
      }
    }

    setState(() => _errorCells.clear());

    try {
      final days = int.tryParse(_daysCtrl.text) ?? 0;
      // 1. DYNAMIC NUMBER CLAIMING & OVERWRITE PROTECTION (Only for NEW bills, not when editing)
      String finalEntryNo = isEdit ? _entryNo : "";
      if (!isEdit) {
        _date = DateTime.now();
        final requested = (_entryNo.isNotEmpty && _entryNo != "...") ? _entryNo : await p.getNextSaleEntryNo();
        final resolvedNo = await p.resolveGuaranteedNextEntryNo('sales_invoices', requested, excludePrefix: 'SO-');
        if (resolvedNo != requested && requested.isNotEmpty) {
          if (mounted) {
            final dispReq = formatSaleDisplayNo(requested);
            final dispRes = formatSaleDisplayNo(resolvedNo);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Bill #$dispReq already taken. Automatically saved as Bill #$dispRes"),
                backgroundColor: Colors.blue.shade800,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
        finalEntryNo = resolvedNo;
        _entryNo = resolvedNo;
        _entryNoCtrl.text = formatSaleDisplayNo(_entryNo);
      }

      // 2. Build the invoice object with the confirmed number and terminal ID
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
        financialYear: p.selectedFinancialYear,
      );

      // Patient Registration Check (Ignores defaults and whitespace)
      final String patName = _patientCtrl.text.trim();
      if (patName.isNotEmpty && patName.toUpperCase() != "P1" && patName.toUpperCase() != "CASH") {
        bool exists = p.patientMaster.any((pat) => pat.name.toLowerCase().trim() == patName.toLowerCase());
        if (!exists) {
          if (!mounted) return;
          bool? res = await AppDialogs.showConfirmDialog(
            context: context,
            title: "New Patient Detected",
            content: "'$patName' is not in your Patient Master. Would you like to save it?",
            yesLabel: "ADD",
            noLabel: "SKIP",
          );
          if (!mounted) return;
          if (res == true) await p.addPatient(patName);
          if (!mounted) return;
        }
      }

      // Doctor Registration Check (Ignores defaults and whitespace)
      final String docName = _doctorCtrl.text.trim();
      if (docName.isNotEmpty && docName.toUpperCase() != "D1" && docName.toUpperCase() != "SELF") {
        bool exists = p.doctorMaster.any((doc) => doc.name.toLowerCase().trim() == docName.toLowerCase());
        if (!exists) {
          if (!mounted) return;
          bool? res = await AppDialogs.showConfirmDialog(
            context: context,
            title: "New Doctor Detected",
            content: "'$docName' is not in your Doctor Master. Would you like to save it?",
            yesLabel: "ADD",
            noLabel: "SKIP",
          );
          if (!mounted) return;
          if (res == true) await p.addDoctor(docName);
          if (!mounted) return;
        }
      }

      // Save to database
      try {
        await p.saveSaleOnlineFirst(sale, isEditMode: isEdit);
      } catch (e) {
        if (!mounted) return;
        await AppDialogs.showFastDialog(
          context: context,
          title: "Pure Cloud Live Save Failed",
          content: "Unable to save bill to Cloud Server.\n\n${e.toString().replaceAll('Exception: ', '')}",
        );
        return; // Abort clearing form so user's typed items are preserved
      }
      if (!mounted) return;

      // Broadcast instant 1ms local network update to PC 2 and PC 3
      final eventId = "EVT_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(100000)}";
      final invoiceMap = {
        'entry_no': finalEntryNo,
        'terminal_id': ServerConfigService.instance.terminalId,
        'event_id': eventId,
      };
      final deductions = validItems.map((it) => {
        'batch_id': it.product.batch,
        'product_id': it.product.id,
        'quantity_deducted': (it.qty + it.fQty) * it.packin,
      }).toList();

      LanSyncService.instance.broadcastEvent('SALE_SAVED', {
        'event_id': eventId,
        'entry_no': finalEntryNo,
        'invoice': invoiceMap,
        'batch_deductions': deductions,
      });
      LanSyncService.instance.broadcastEvent('SALE_COMPLETED', {
        'event_id': eventId,
        'entry_no': finalEntryNo,
        'terminal_id': ServerConfigService.instance.terminalId,
        'invoice': invoiceMap,
        'batch_deductions': deductions,
        'items': validItems.map((it) => {
          'product_id': it.product.id,
          'product_name': it.product.name,
          'batch_number': it.product.batch,
          'qty': it.qty,
        }).toList(),
      });

      unawaited(p.clearSaleDraft());

      // Write edit history asynchronously in background without blocking UI thread
      if (isEdit && _originalLoadedInvoice != null) {
        unawaited(() async {
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
        }());
      }

      SystemSound.play(SystemSoundType.alert);

      AppLogger.instance.info("BUSINESS", "[SAVE_COMPLETED] Sales Entry #${formatSaleDisplayNo(finalEntryNo)} ($finalEntryNo) saved successfully.");

      final bool bgSyncEnabled = ServerConfigService.instance.bgSyncOnSave;
      if (bgSyncEnabled) {
        DeltaSyncService.instance.triggerBackgroundSync(forcePostSave: true);
        SupabaseSyncService.instance.triggerInstantSync();
      }

      if (mounted) {
        _isDirty = false;
        final messenger = ScaffoldMessenger.of(context);
        await _resetPage(force: true);
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: const Text("Entry Saved", style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.green.shade800,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 50, left: 10, right: 1000),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showFastDialog(
            title: "Save Failed",
            content: "An error occurred while saving: $e"
        );
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


  // --- NEW: DELETE SALE METHOD ---
  void _deleteSale() async {
    AppLogger.instance.info("USER_ACTION", "[DELETE_CLICKED] Delete requested for Sales Entry #${formatSaleDisplayNo(_entryNo)} ($_entryNo)");

    if (_isDeleting || _isSaving || _isLoading) return;
    _isDeleting = true;

    try {
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
          if (!mounted) return;
          if (!isUnlocked) return;
          p.refreshAdminSession();
        }
      }

      final confirmed = await _showFastDialog(
          title: "Delete Entry?",
          content: "Are you sure you want to delete Sales Entry $_entryNo? This will restore the stock and mark the entry as deleted.",
          isYesNo: true,
          initialFocusIdx: 2
      );
      if (!mounted) return;

      if (confirmed == true) {
        setState(() => _isLoading = true);
        try {
          final oldItems = await p.getCurrentInvoiceItems(_entryNo);
          final oldItemsJson = jsonEncode(oldItems);
          final oldTotal = double.tryParse(_netTotalCtrl.text) ?? 0.0;
          final staffId = _agentCtrl.text.trim().isNotEmpty ? _agentCtrl.text.trim() : "Admin";

          await p.logEditHistory(
            entryNo: _entryNo,
            oldTotal: oldTotal,
            oldItemsJson: oldItemsJson,
            newItemsJson: jsonEncode([]),
            reason: "DELETED by $staffId: Sales Entry #$_entryNo marked as deleted",
          );

          _isExistingEntry = false;
          _originalLoadedInvoice = null;
          _loadedInvoiceUpdatedAt = "";
          await p.deleteSale(_entryNo);
          AppLogger.instance.info("BUSINESS", "[DELETE_COMPLETED] Sales Entry #${formatSaleDisplayNo(_entryNo)} ($_entryNo) marked as DELETED.");
          if (!mounted) return;
          p.logAudit('DELETE_SALE', 'Sales Entry $_entryNo deleted by $staffId.', userId: staffId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Entry Deleted Successfully"), backgroundColor: Colors.red)
            );
            _isDirty = false;
            await _resetPage(force: true);
          }
        } catch (e) {
          if (mounted) _showFastDialog(title: "Delete Failed", content: "Error: $e");
        }
      }
    } finally {
      _isDeleting = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onDaysChanged() {
    if (!mounted) return;
    int targetDays = int.tryParse(_daysCtrl.text) ?? 0;
    bool needsRecalc = false;

    for (int i = 0; i < _items.length; i++) {
      final it = _items[i];
      if (it.dailyDosage != null && it.dailyDosage! > 0) {
        int newQty;
        if (targetDays <= 0) {
          newQty = (it.originalExportQty ?? it.qty.toDouble()).toInt();
        } else {
          newQty = (it.dailyDosage! * targetDays).ceil();
        }
        if (newQty <= 0) newQty = 1;

        if (it.qty != newQty) {
          it.qty = newQty;
          _calculateItem(i);
          _getGridCtrl(i, 7).text = newQty.toString();
          needsRecalc = true;
        }
      }
    }

    if (needsRecalc && mounted) {
      _calculateFooter();
      setState(() {});
    }
  }

  void _importPrescription() async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final prescriptions = provider.prescriptions;

    if (prescriptions.isEmpty) {
      _showFastDialog(title: "No Prescriptions", content: "No saved prescriptions available to import.");
      return;
    }

    setState(() => _isDialogOpen = true);
    final Prescription? selected = await showDialog<Prescription>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Select Prescription / Registered Template", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 520,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: prescriptions.length,
            itemBuilder: (c, i) {
              final p = prescriptions[i];
              final String patientStr = p.patientName.trim().isEmpty ? "Unassigned Patient" : p.patientName;
              final String docStr = p.doctorName.trim().isEmpty ? "" : " (Dr. ${p.doctorName})";
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  title: Text("$patientStr$docStr", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  subtitle: Text("Date: ${DateFormat('dd/MM/yyyy').format(p.date)} | Mobile: ${p.mobile.isEmpty ? 'N/A' : p.mobile} | Items: ${p.items.length}", style: const TextStyle(fontSize: 11)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                    tooltip: "Delete Prescription",
                    onPressed: () async {
                      await provider.deletePrescription(p.id);
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        _importPrescription();
                      }
                    },
                  ),
                  onTap: () => Navigator.pop(ctx, p),
                ),
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

      int userTypedDays = int.tryParse(_daysCtrl.text) ?? 0;
      int exportDays = selected.days > 0 ? selected.days : 1;
      int targetDays = userTypedDays > 0 ? userTypedDays : selected.days;

      setState(() {
        _items.clear();
        String patStr = selected.patientName.trim();
        if (patStr.isEmpty || patStr.toLowerCase() == 'general' || patStr.toLowerCase() == 'unknown') {
          patStr = 'P1';
        }
        _patientCtrl.text = patStr;
        _mobileCtrl.text = selected.mobile;

        String docStr = selected.doctorName.trim();
        if (docStr.isEmpty || docStr.toLowerCase() == 'unknown' || docStr.toLowerCase() == 'dr. unknown') {
          docStr = 'D1';
        }
        _doctorCtrl.text = docStr;
        if (targetDays > 0) {
          _daysCtrl.text = targetDays.toString();
        } else {
          _daysCtrl.text = "0";
        }

        for (var pItem in selected.items) {
          if (pItem.name.isEmpty) continue;

          double exportQty = pItem.qty.toDouble();
          double dailyDosage = exportQty / exportDays;
          double targetTotalQty;
          if (targetDays <= 0) {
            targetTotalQty = exportQty;
          } else {
            targetTotalQty = (dailyDosage * targetDays).ceilToDouble();
          }
          if (targetTotalQty <= 0) targetTotalQty = 1.0;

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
              qty: targetTotalQty.toInt(),
              dailyDosage: dailyDosage,
              originalExportQty: exportQty,
            ));
            continue;
          }

          double remainingQty = targetTotalQty;
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
                  purchaseRate: batch.purchaseRate, landingCost: batch.landingCost, gstPercent: batch.gstPercent,
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
              purchaseRate: batch.purchaseRate / ps,
              landingCost: batch.landingCost > 0 ? (batch.landingCost / ps) : (batch.purchaseRate / ps),
              dailyDosage: dailyDosage,
              originalExportQty: exportQty,
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
    }
  }

  void _exportPrescription() async {
    if (_items.isEmpty) {
      _showFastDialog(title: "No Items", content: "Add items to export as a prescription.");
      return;
    }

    String docStr = _doctorCtrl.text.trim();
    if (docStr.isEmpty || docStr.toLowerCase() == 'unknown' || docStr.toLowerCase() == 'dr. unknown') {
      docStr = 'D1';
    }

    String patStr = _patientCtrl.text.trim();
    if (patStr.isEmpty || patStr.toLowerCase() == 'general' || patStr.toLowerCase() == 'unknown') {
      patStr = 'P1';
    }

    final p = Prescription(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      patientName: patStr,
      doctorName: docStr,
      mobile: _mobileCtrl.text,
      days: int.tryParse(_daysCtrl.text) ?? 0,
      date: _date,
      items: _items.map((it) => PrescriptionItem(name: it.product.name, qty: it.qty.toDouble())).toList(),
    );

    await Provider.of<PharmacyProvider>(context, listen: false).addPrescription(p);
    if (!mounted) return;
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
      // Protect against losing unsaved edits
      if (!force && hasUnsavedChanges()) {
        bool? discard = await _promptDiscardChanges();
        if (!mounted) return;
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
      _isImported = false;

      final p = Provider.of<PharmacyProvider>(context, listen: false);
      p.clearReservedEntryNumbers();
      p.clearSaleDraft();
      p.clearSalesSession(p.activeSessionIdx); // Clear the global RAM session
      p.saveSalesDrafts(); // Persist the cleared state so it doesn't return on restart

      _closeAllDropdowns();
      FocusScope.of(context).unfocus();

      // Clear & recycle all grid controllers including active next row
      _clearGridMaps();

      setState(() {
        _lastSyncedProdName = "";
        _footerAlts = [];
        _activeGenericName = "";
        _productHistory = [];

        _isExistingEntry = false;
        _isBlankRecord = false;
        _isRcvdAmtConfirmed = false;
        _isDirty = false; // Reset dirty flag on new
        _isDeleted = false;
        _isImported = false;
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
        _timeNotifier.value = DateFormat('hh:mm a').format(_date);
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
        _loadedInvoiceUpdatedAt = "";
        _originalItemSnapshots.clear();
        _highlightEdits = false;
        _specialOrderQtys.clear();
        _extraSpecialItems.clear();
        _entryNo = "";
        _rawEntryNo = "";
        _entryNoCtrl.text = "...";
        _calculateFooter();
      });

      await _initializeNewBillNumber();

      if (mounted) {
        _focusProductFirstBox();
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
    if (_isDisposed || !mounted || _isExistingEntry) return;

    final p = Provider.of<PharmacyProvider>(context, listen: false);

    if (!_hasValidItems()) {
      if (_lastDraftSavedStateDirty) {
        p.clearSaleDraft();
        p.clearSalesSession(p.activeSessionIdx);
        try {
          await p.saveSalesDrafts().timeout(const Duration(seconds: 3));
        } catch (_) {}
        if (!mounted) return;
        _lastDraftSavedStateDirty = false;
      }
      return;
    }

    if (_lastDraftSavedStateDirty) {
      _syncToGlobalSession();
      try {
        await p.saveSalesDrafts().timeout(const Duration(seconds: 3));
      } catch (_) {}
      if (!mounted) return;
      _lastDraftSavedStateDirty = false;
    }
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

        return PopScope(
          canPop: _items.isEmpty,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            if (_items.isNotEmpty) {
              bool? exit = await _showFastDialog(
                title: "Unsaved Invoice Items",
                content: "You have unsaved items in the sales grid. Exit without saving?",
                isYesNo: true,
                initialFocusIdx: 2,
              );
              if (exit == true && context.mounted) {
                Navigator.of(context).pop();
              }
            }
          },
          child: Focus(
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

                    if (!ServerConfigService.instance.isConnected)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        color: const Color(0xFF991B1B),
                        child: Row(
                          children: [
                            const Icon(Icons.cloud_off_rounded, color: Colors.amberAccent, size: 20),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                "SERVER DISCONNECTED — WORKING IN OFFLINE READ-ONLY MODE",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: const Color(0xFF450A0A), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.amberAccent)),
                              child: const Text("OFFLINE", style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                            ),
                          ],
                        ),
                      ),

                    if (_isImported)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        color: const Color(0xFF1E3A8A),
                        child: Row(
                          children: [
                            const Icon(Icons.lock_rounded, color: Colors.cyanAccent, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "🔒 HISTORICAL IMPORTED ENTRY: Sales Invoice #$_entryNo is locked (Read-Only). Use Stock Adjustment for inventory changes.",
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: const Color(0xFF1E1B4B), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.cyanAccent)),
                              child: const Text("READ-ONLY", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                            ),
                          ],
                        ),
                      ),

                    if (_isDeleted)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        color: const Color(0xFF7F1D1D),
                        child: Row(
                          children: [
                            const Icon(Icons.delete_forever_rounded, color: Colors.amberAccent, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "🗑️ DELETED ENTRY: Sales Invoice #$_entryNo is marked as DELETED and is Read-Only.",
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: const Color(0xFF450A0A), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.amberAccent)),
                              child: const Text("READ-ONLY", style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                            ),
                          ],
                        ),
                      ),

                    if (_isBlankRecord)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        color: const Color(0xFF1E293B),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded, color: Colors.lightBlueAccent, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "ℹ️ UNCREATED / BLANK ENTRY: Entry #$_entryNo has no saved invoice data in the database.",
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.lightBlueAccent)),
                              child: const Text("BLANK DRAFT", style: TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                            ),
                          ],
                        ),
                      ),

                    // === THE GRID ===
                    Expanded(child: LayoutBuilder(builder: (ctx, con) {
                        final double availableWidth = con.maxWidth;
                        if (!_hasCustomColWidths && availableWidth > 0) {
                          double defaultSum = 0;
                          _colWidths.forEach((k, v) => defaultSum += v);
                          if (defaultSum > 0) {
                            double scale = availableWidth / defaultSum;
                            if (scale < 1.0) {
                              _colWidths[0] = (35 * scale).clamp(25.0, 35.0);
                              _colWidths[1] = (75 * scale).clamp(35.0, 75.0);
                              _colWidths[2] = (280 * scale).clamp(150.0, 400.0);
                              _colWidths[3] = (90 * scale).clamp(45.0, 90.0);
                              _colWidths[4] = (140 * scale).clamp(80.0, 140.0);
                              _colWidths[5] = (60 * scale).clamp(45.0, 60.0);
                              _colWidths[6] = (60 * scale).clamp(40.0, 60.0);
                              _colWidths[7] = (60 * scale).clamp(40.0, 60.0);
                              _colWidths[8] = (60 * scale).clamp(45.0, 60.0);
                              _colWidths[9] = (80 * scale).clamp(55.0, 80.0);
                              _colWidths[10] = (80 * scale).clamp(55.0, 80.0);
                              _colWidths[11] = (60 * scale).clamp(40.0, 60.0);
                              _colWidths[12] = (80 * scale).clamp(55.0, 80.0);
                              _colWidths[13] = (50 * scale).clamp(38.0, 50.0);
                              _colWidths[14] = (100 * scale).clamp(65.0, 100.0);
                              _colWidths[15] = (80 * scale).clamp(50.0, 80.0);
                              _colWidths[16] = 48.0;
                            } else {
                              double fixedTotal = 0;
                              _colWidths.forEach((k, v) { if (k != 2) fixedTotal += v; });
                              if (availableWidth > fixedTotal + 280) {
                                _colWidths[2] = availableWidth - fixedTotal;
                              }
                            }
                          }
                        }

                        double finalTw = 0;
                        _colWidths.forEach((_, v) => finalTw += v);
                        if (finalTw < availableWidth) finalTw = availableWidth;

                        return AnimatedOpacity(
                          opacity: _isLayoutReady ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 100),
                          child: _safeScrollbar(
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
                          ),
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
                if (_activeNotificationTab != "none")
                  _isNotificationHubMinimized
                      ? _buildMinimizedNotificationBadge()
                      : _buildOrderDrawerPanel(),
                if (_isLoading) Container(color: Colors.black12, child: const Center(child: CircularProgressIndicator())),
              ],
            ),
          ),
        ),
      ),
      );
      },
    );
  }

  // ---> NEW: SMART EDIT TRACKING <---

  bool _hasMeaningfulEdits() {
    if (!_isExistingEntry) return false;
    if (_originalLoadedInvoice == null) return _isDirty;

    if (_patientCtrl.text.trim().toUpperCase() != _originalLoadedInvoice!.patient.trim().toUpperCase()) return true;
    if (_doctorCtrl.text.trim().toUpperCase() != _originalLoadedInvoice!.doctor.trim().toUpperCase()) return true;
    if (_mobileCtrl.text.trim() != _originalLoadedInvoice!.mobile.trim()) return true;
    if (_customerAcc != _originalLoadedInvoice!.customerAcc) return true;

    double currentDiscAmt = double.tryParse(_footerDiscAmtCtrl.text) ?? 0.0;
    if ((currentDiscAmt - _originalLoadedInvoice!.discount).abs() > 0.01) return true;

    final validItems = _items.where((it) => it.product.name.trim().isNotEmpty).toList();
    final origItems = _originalLoadedInvoice!.items;
    if (validItems.length != origItems.length) return true;

    for (int i = 0; i < validItems.length; i++) {
      final it = validItems[i];
      final orig = origItems[i];

      if (it.product.name.trim().toUpperCase() != orig.product.name.trim().toUpperCase()) return true;
      if (it.product.batch.trim().toUpperCase() != orig.product.batch.trim().toUpperCase()) return true;
      if (it.qty != orig.qty) return true;
      if (it.fQty != orig.fQty) return true;
      if ((it.mrp - orig.mrp).abs() > 0.01) return true;
      if ((it.sRate - orig.sRate).abs() > 0.01) return true;
      if ((it.discPercent - orig.discPercent).abs() > 0.01) return true;
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

  @override
  bool hasUnsavedChanges() {
    double total = _grandTotalNotifier.value;
    if (total <= 0) {
      total = double.tryParse(_netTotalCtrl.text) ?? 0.0;
    }
    if (total <= 0) {
      total = _items.fold(0.0, (s, i) => s + i.total);
    }
    // If grand total is 0 or less, NEVER show unsaved changes popup
    if (total <= 0) return false;

    if (_isExistingEntry) {
      return _hasMeaningfulEdits();
    } else {
      return total > 1.0;
    }
  }

  @override
  void showDifferences() {
    if (mounted) {
      setState(() {
        _highlightEdits = true;
      });
    }
  }

  Future<bool?> _promptDiscardChanges() async {
    if (!hasUnsavedChanges()) return true;

    final result = await showUnsavedChangesDialog(context);
    if (!mounted) return false;
    if (result == UnsavedDialogResult.discard) {
      return true;
    } else {
      return false;
    }
  }

  Widget _buildTopToolbar() {
    final bool isConnected = ServerConfigService.instance.isConnected;
    bool hasEdits = hasUnsavedChanges();
    bool canSave = isConnected && !_isDeleted && !_isImported && (!_isExistingEntry || hasEdits);
    bool canEdit = isConnected && _isExistingEntry && !_isDeleted && !_isImported && !hasEdits;
    bool canDelete = isConnected && _isExistingEntry && !_isDeleted && !_isImported;

    final c = AppColors.of(context);
    return Container(
      height: 38,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8),
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
              const SizedBox(width: 8),
              InkWell(
                onTap: _openGenericSearchDialog,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    border: Border.all(color: Colors.amber.shade700, width: 1.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.biotech_rounded, size: 16, color: Colors.amber.shade900),
                      const SizedBox(width: 4),
                      Text(
                        "Generic (F2)",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                      ),
                    ],
                  ),
                ),
              ),
              if (_isDeleted)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFF7F1D1D), borderRadius: BorderRadius.circular(4)),
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
                    _topActionBtn(Icons.add_box_rounded, "New (F1)", const Color(0xFF2196F3), onTap: _resetPage),
                    _topActionBtn(
                      Icons.check_circle_rounded,
                      "Save (F6)",
                      canSave ? const Color(0xFF4CAF50) : Colors.grey.shade400,
                      textColor: canSave ? null : Colors.grey.shade400,
                      onTap: canSave ? () => (_isExistingEntry ? _editSale() : _saveSale(isEdit: false)) : null,
                    ),
                    _topActionBtn(
                      Icons.edit_document,
                      "Edit",
                      canEdit ? Colors.orange : Colors.grey.shade400,
                      textColor: canEdit ? null : Colors.grey.shade400,
                      onTap: canEdit ? _editSale : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(_isExistingEntry ? "No changes made to edit." : "Select an existing sale to edit."), duration: const Duration(seconds: 2)),
                        );
                      },
                    ),
                    _topActionBtn(
                      Icons.search_rounded,
                      "Search",
                      const Color(0xFF009688),
                      onTap: _showFindDialog,
                    ),
                    _topActionBtn(Icons.storefront_rounded, "Wholesale (F3)", const Color(0xFF3F51B5), onTap: _openWholesaleAvailability),
                    _topActionBtn(Icons.print_rounded, "Print (F12)", const Color(0xFF607D8B), onTap: _printSale),
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
                    _topActionBtn(Icons.sync_rounded, "Sync Settings", Colors.teal, onTap: _showSyncSettingsDialog),
                    _topActionBtn(Icons.info_outline_rounded, "Info & Guide", Colors.indigo, onTap: _showSalesManualAndLegendDialog),
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.blueGrey),
                      tooltip: "More Options",
                      onSelected: (val) {
                        if (val == 'pdf') _exportToPdf();
                        if (val == 'whatsapp') _shareInvoiceWhatsApp();
                        if (val == 'export') _exportToExcel();
                        if (val == 'copy') _copySalesGridToClipboard();
                        if (val == 'paste') _pasteSalesGridFromClipboard();
                        if (val == 'import') _importPrescription();
                        if (val == 'sync_settings') _showSyncSettingsDialog();
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
                          value: 'copy',
                          child: Row(
                            children: [
                              Icon(Icons.copy_rounded, color: Colors.blue, size: 20),
                              SizedBox(width: 10),
                              Text("Copy Grid to Clipboard", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'paste',
                          child: Row(
                            children: [
                              Icon(Icons.paste_rounded, color: Colors.teal, size: 20),
                              SizedBox(width: 10),
                              Text("Paste Clipboard (Smart Stock)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
                              Text("Import Prescription / Excel", style: TextStyle(fontSize: 13)),
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

  Widget _safeScrollbar({
    required ScrollController controller,
    required Widget child,
    bool thumbVisibility = false,
    double? thickness,
  }) {
    if (!controller.hasClients) return child;
    return Scrollbar(
      controller: controller,
      thumbVisibility: thumbVisibility,
      thickness: thickness,
      child: child,
    );
  }

  Widget _buildTopSection() {
    return Consumer<PharmacyProvider>(
      builder: (context, p, _) {
        final hasNewMobileOrder = p.prescriptions.any((pr) => !pr.isImported);
        bool showMobileBadge = hasNewMobileOrder && _hasNewMobileOrder;

        return Container(
          height: 132,
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

          // CENTER-RIGHT: Priority Reorder & Urgent Dock
          _buildPriorityReorderColumn(),

          const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE0E0E0)),

          // FAR-RIGHT: The 4 Vertically Aligned Notification Hub Toggle Buttons
          Container(
            width: 125,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                left: BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
                bottom: BorderSide(color: Colors.grey, width: 0.5),
              ),
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
        ],
      ),
    );
      },
    );
  }

  Widget _buildPriorityReorderColumn() {
    // 1. Tier 1: Urgent Orders (Retain all items including ordered)
    final tier1Urgent = List<Map<String, dynamic>>.from(_urgentOrders);

    // 2. Tier 2: Special Orders (Retain all items including ordered)
    final tier2Special = List<Map<String, dynamic>>.from(_specialOrdersList);

    // Zero stock items
    final zeroStockItems = _lowStockOrders.where((i) => ((i['stock'] as num?)?.toInt() ?? 0) <= 0).toList();

    // 3. Tier 3: High Rank (> 3) Zero Stock - Sorted High to Low
    final tier3HighRank = zeroStockItems.where((i) {
      final double r = (i['rank'] as num?)?.toDouble() ?? 0.0;
      return r > 3.0;
    }).toList()..sort((a, b) => ((b['rank'] as num?)?.toDouble() ?? 0.0).compareTo((a['rank'] as num?)?.toDouble() ?? 0.0));

    // 4. Tier 4: Medium Rank (3 to 4) Zero Stock
    final tier4MedRank = zeroStockItems.where((i) {
      final double r = (i['rank'] as num?)?.toDouble() ?? 0.0;
      return r >= 3.0 && r <= 4.0 && !tier3HighRank.contains(i);
    }).toList()..sort((a, b) => ((b['rank'] as num?)?.toDouble() ?? 0.0).compareTo((a['rank'] as num?)?.toDouble() ?? 0.0));

    // 5. Tier 5: Low Rank (< 3) Zero Stock
    final tier5LowRank = zeroStockItems.where((i) {
      final double r = (i['rank'] as num?)?.toDouble() ?? 0.0;
      return r < 3.0 && !tier3HighRank.contains(i) && !tier4MedRank.contains(i);
    }).toList()..sort((a, b) => ((b['rank'] as num?)?.toDouble() ?? 0.0).compareTo((a['rank'] as num?)?.toDouble() ?? 0.0));

    int totalPriorityCount = tier1Urgent.length + tier2Special.length + tier3HighRank.length + tier4MedRank.length + tier5LowRank.length;

    return Container(
      width: 380,
      height: 132,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: Colors.grey.shade300, width: 1.0),
          bottom: const BorderSide(color: Colors.grey, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          // LIGHT SLATE TABLE COLUMN HEADERS
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: const Row(
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      "PRODUCT NAME",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                    ),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Center(
                    child: Text(
                      "PHYSICAL\nQTY",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF334155), height: 1.1),
                    ),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Center(
                    child: Text(
                      "ORDER\nQTY",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF334155), height: 1.1),
                    ),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Center(
                    child: Text(
                      "ORDERED\nQTY",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF334155), height: 1.1),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // TIERS LIST BODY
          Expanded(
            child: totalPriorityCount == 0
                ? Center(
                    child: Text(
                      _isLoadingNotifications ? "Loading priorities..." : "No zero stock alerts found.",
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                  )
                : _safeScrollbar(
                    controller: _tierListScrollCtrl,
                    thumbVisibility: true,
                    thickness: 4,
                    child: ListView(
                      controller: _tierListScrollCtrl,
                      padding: EdgeInsets.zero,
                      children: [
                        if (tier1Urgent.isNotEmpty)
                          ...tier1Urgent.map((item) => _priorityItemTile(item, badgeText: "URGENT", badgeColor: Colors.red.shade700)),
                        if (tier2Special.isNotEmpty)
                          ...tier2Special.map((item) => _priorityItemTile(item, badgeText: "SPECIAL", badgeColor: Colors.purple.shade700)),
                        if (tier3HighRank.isNotEmpty)
                          ...tier3HighRank.map((item) {
                            final double r = (item['rank'] as num?)?.toDouble() ?? 0.0;
                            return _priorityItemTile(item, badgeText: r > 0 ? "R${r.toStringAsFixed(1)}" : "HIGH", badgeColor: Colors.orange.shade800);
                          }),
                        if (tier4MedRank.isNotEmpty)
                          ...tier4MedRank.map((item) {
                            final double r = (item['rank'] as num?)?.toDouble() ?? 0.0;
                            return _priorityItemTile(item, badgeText: r > 0 ? "R${r.toStringAsFixed(1)}" : "MED", badgeColor: Colors.amber.shade800);
                          }),
                        if (tier5LowRank.isNotEmpty)
                          ...tier5LowRank.map((item) {
                            final double r = (item['rank'] as num?)?.toDouble() ?? 0.0;
                            return _priorityItemTile(item, badgeText: r > 0 ? "R${r.toStringAsFixed(1)}" : "LOW", badgeColor: Colors.blueGrey.shade700);
                          }),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _priorityItemTile(Map<String, dynamic> item, {required String badgeText, required Color badgeColor}) {
    final int stockQty = (item['stock'] as num?)?.toInt() ?? 0;
    final int orderQty = (item['qty'] as num?)?.toInt() ?? 10;
    final bool isOrdered = item['ordered'] == true;
    final dynamic orderedQtyVal = item['ordered_qty'] ?? (isOrdered ? orderQty : null);

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: isOrdered ? Colors.blue.shade50.withValues(alpha: 0.3) : Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          // 1. PRODUCT NAME
          Expanded(
            child: Text(
              item['name'] ?? '',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isOrdered ? Colors.grey.shade700 : Colors.black,
                decoration: isOrdered ? TextDecoration.lineThrough : TextDecoration.none,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // 2. PHYSICAL QTY
          SizedBox(
            width: 52,
            child: Center(
              child: Text(
                "$stockQty",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: stockQty <= 0 ? Colors.red.shade700 : Colors.blueGrey.shade700,
                ),
              ),
            ),
          ),

          // 3. ORDER QTY
          SizedBox(
            width: 52,
            child: Center(
              child: Text(
                "$orderQty",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
              ),
            ),
          ),

          // 4. ORDERED QTY (Editable field)
          SizedBox(
            width: 52,
            child: Center(
              child: Container(
                height: 20,
                width: 38,
                padding: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: isOrdered ? Colors.white : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: isOrdered ? Colors.blue.shade400 : Colors.grey.shade300),
                ),
                child: TextField(
                  key: ValueKey('ord_qty_${item['id']}_$orderedQtyVal'),
                  controller: TextEditingController(text: orderedQtyVal != null ? "$orderedQtyVal" : ""),
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                  ),
                  onSubmitted: (v) {
                    final int? val = int.tryParse(v.trim());
                    setState(() {
                      if (val != null && val > 0) {
                        item['ordered_qty'] = val;
                        item['ordered'] = true;
                        item['pending'] = false;
                      } else {
                        item['ordered_qty'] = null;
                        item['ordered'] = false;
                        item['pending'] = true;
                      }
                    });
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadNotificationData({bool forceRefresh = false}) async {
    if (!mounted) return;
    if (_urgentOrders.isEmpty && _lowStockOrders.isEmpty && _specialOrdersList.isEmpty) {
      setState(() => _isLoadingNotifications = true);
    } else if (forceRefresh) {
      // Background update without blocking UI loader
    }
    try {
      final p = Provider.of<PharmacyProvider>(context, listen: false);
      final reorderList = await p.getReorderSuggestions();
      if (!mounted) return;

      final rawSpecial = await p.fetchSpecialOrders();
      if (!mounted) return;

      final Map<String, ProductRanking> rankingsMap = await p.getProductRankingsMap();

      // Existing maps to preserve user toggles & order quantities
      final Map<dynamic, bool> existingUrgentOrdered = {for (var i in _urgentOrders) i['id']: i['ordered'] ?? false};
      final Map<dynamic, bool> existingUrgentPending = {for (var i in _urgentOrders) i['id']: i['pending'] ?? false};
      final Map<dynamic, int> existingUrgentQty = {for (var i in _urgentOrders) i['id']: i['qty']};
      final Map<dynamic, dynamic> existingUrgentOrderedQty = {for (var i in _urgentOrders) i['id']: i['ordered_qty']};

      final Map<dynamic, bool> existingLowStockOrdered = {for (var i in _lowStockOrders) i['id']: i['ordered'] ?? false};
      final Map<dynamic, bool> existingLowStockPending = {for (var i in _lowStockOrders) i['id']: i['pending'] ?? false};
      final Map<dynamic, int> existingLowStockQty = {for (var i in _lowStockOrders) i['id']: i['qty']};
      final Map<dynamic, dynamic> existingLowStockOrderedQty = {for (var i in _lowStockOrders) i['id']: i['ordered_qty']};

      final Map<dynamic, bool> existingSpecialOrdered = {for (var i in _specialOrdersList) i['id']: i['ordered'] ?? false};
      final Map<dynamic, bool> existingSpecialPending = {for (var i in _specialOrdersList) i['id']: i['pending'] ?? false};
      final Map<dynamic, dynamic> existingSpecialOrderedQty = {for (var i in _specialOrdersList) i['id']: i['ordered_qty']};

      final Set<String> validMasterNames = {};
      for (var pm in p.productMaster) {
        if (pm.isActive && p.isValidProductName(pm.name)) {
          final trimmed = pm.name.trim().toLowerCase();
          if (trimmed.isNotEmpty) validMasterNames.add(trimmed);
        }
      }

      List<Map<String, dynamic>> specialItems = [];
      for (var s in rawSpecial) {
        try {
          List<dynamic> list = jsonDecode(s['special_order_json']);
          for (var item in list) {
            final String prodName = (item['name'] ?? '').toString().trim();
            if (prodName.isEmpty) continue;
            if (!p.isValidProductName(prodName)) continue;
            // Only include in Order Book if product exists in Product Master catalog!
            if (!validMasterNames.contains(prodName.toLowerCase())) continue;

            final String itemId = '${s['entry_no']}_$prodName';
            final bool wasOrdered = existingSpecialOrdered[itemId] ?? false;
            final bool wasPending = existingSpecialPending[itemId] ?? !wasOrdered;
            final dynamic wasOrderedQty = existingSpecialOrderedQty[itemId] ?? (wasOrdered ? (item['qty'] ?? 1) : null);

            specialItems.add({
              'entry_no': s['entry_no'],
              'id': itemId,
              'name': prodName,
              'qty': item['qty'] ?? 1,
              'ordered_qty': wasOrderedQty,
              'stock': item['stock'] ?? 0,
              'p_rate': (item['p_rate'] as num?)?.toDouble() ?? (item['purchase_rate'] as num?)?.toDouble() ?? 0.0,
              'patient': (s['special_customer_name']?.toString().isNotEmpty ?? false)
                  ? s['special_customer_name']
                  : s['patient'] ?? '',
              'ordered': wasOrdered,
              'pending': wasPending,
            });
          }
        } catch (_) {}
      }

      List<Map<String, dynamic>> urgent = [];
      List<Map<String, dynamic>> lowStock = [];

      for (var item in reorderList) {
        final dynamic id = item['id'];
        final String pId = item['id']?.toString() ?? '';
        final String name = (item['product_name'] ?? item['name'] ?? 'Product').toString().trim();
        if (name.isEmpty) continue;
        if (!p.isValidProductName(name)) continue;
        if (!validMasterNames.contains(name.toLowerCase())) continue;
        final int currentStock = (item['current_stock'] as num?)?.toInt() ?? 0;
        final int reorderLevel = (item['reorder_level'] as num?)?.toInt() ?? 10;
        final int suggestedQty = (item['suggested_qty'] as num?)?.toInt() ?? 10;
        final double pRate = (item['purchase_rate'] as num?)?.toDouble() ?? (item['p_rate'] as num?)?.toDouble() ?? 0.0;

        double rankScore = 0.0;
        final pr = rankingsMap[pId] ?? rankingsMap[name.toUpperCase().trim()];
        if (pr != null) {
          rankScore = pr.weightedScore;
        }

        final bool wasUrgentOrdered = existingUrgentOrdered[id] ?? false;
        final bool wasUrgentPending = existingUrgentPending[id] ?? (currentStock <= reorderLevel);
        final int urgentQty = existingUrgentQty[id] ?? (suggestedQty > 0 ? suggestedQty : (reorderLevel - currentStock > 0 ? reorderLevel - currentStock : 10));
        final dynamic wasUrgentOrderedQty = existingUrgentOrderedQty[id] ?? (wasUrgentOrdered ? urgentQty : null);

        final bool wasLowStockOrdered = existingLowStockOrdered[id] ?? false;
        final bool wasLowStockPending = existingLowStockPending[id] ?? (currentStock <= reorderLevel);
        final int lowStockQty = existingLowStockQty[id] ?? (suggestedQty > 0 ? suggestedQty : (reorderLevel - currentStock > 0 ? reorderLevel - currentStock : 10));
        final dynamic wasLowStockOrderedQty = existingLowStockOrderedQty[id] ?? (wasLowStockOrdered ? lowStockQty : null);

        final mapUrgentObj = {
          'id': id,
          'name': name,
          'qty': urgentQty,
          'ordered_qty': wasUrgentOrderedQty,
          'stock': currentStock,
          'reorder_level': reorderLevel,
          'p_rate': pRate,
          'rank': rankScore,
          'ordered': wasUrgentOrdered,
          'pending': wasUrgentPending,
        };

        final mapLowStockObj = {
          'id': id,
          'name': name,
          'qty': lowStockQty,
          'ordered_qty': wasLowStockOrderedQty,
          'stock': currentStock,
          'reorder_level': reorderLevel,
          'p_rate': pRate,
          'rank': rankScore,
          'ordered': wasLowStockOrdered,
          'pending': wasLowStockPending,
        };

        if (currentStock <= reorderLevel) {
          lowStock.add(mapLowStockObj);
        }
        urgent.add(mapUrgentObj);
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
    bool isSel = _activeNotificationTab == id && !_isNotificationHubMinimized;
    return InkWell(
      onTap: () {
        setState(() {
          if (_activeNotificationTab == id && !_isNotificationHubMinimized) {
            _activeNotificationTab = "none";
          } else {
            _activeNotificationTab = id;
            _isNotificationHubMinimized = false;
            if (id == "mobile") _hasNewMobileOrder = false;
          }
        });
        if (_urgentOrders.isEmpty && _lowStockOrders.isEmpty && _specialOrdersList.isEmpty) {
          _loadNotificationData();
        }
      },
      child: Container(
        height: 29,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: isSel ? Colors.blue.shade50 : Colors.transparent,
          border: Border.all(color: isSel ? Colors.blue : Colors.transparent),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: isSel ? Colors.blue : color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSel ? Colors.blue : Colors.black,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (count > 0)
              Container(
                margin: const EdgeInsets.only(left: 2),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: badgeColor ?? Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterOption(String label) {
    bool isSelected = _orderFilter == label;
    return InkWell(
      onTap: () => setState(() => _orderFilter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isSelected ? Colors.black : Colors.grey.shade400),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : Colors.black,
          ),
        ),
      ),
    );
  }

  Widget _drawerTabChip(String id, String label, int count, Color color) {
    bool isSel = _activeNotificationTab == id;
    return InkWell(
      onTap: () => setState(() => _activeNotificationTab = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSel ? color : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSel ? color : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSel ? Colors.white : Colors.black),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSel ? Colors.white : color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "$count",
                  style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: isSel ? color : Colors.white),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildMinimizedNotificationBadge() {
    String label = "Order Alerts";
    int count = 0;
    if (_activeNotificationTab == "stock") {
      label = "Low Stock Alerts";
      count = _lowStockOrders.length;
    } else if (_activeNotificationTab == "urgent") {
      label = "Urgent Orders";
      count = _urgentOrders.length;
    } else if (_activeNotificationTab == "special") {
      label = "Special Orders";
      count = _specialOrdersList.length;
    } else if (_activeNotificationTab == "mobile") {
      label = "Mobile Orders";
      count = 1;
    }

    return Positioned(
      top: 140,
      right: 12,
      child: InkWell(
        onTap: () => setState(() => _isNotificationHubMinimized = false),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
            border: Border.all(color: Colors.blue.shade400, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inventory_2_rounded, color: Colors.lightBlueAccent, size: 16),
              const SizedBox(width: 8),
              Text(
                "$label ($count)",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.open_in_full_rounded, color: Colors.white, size: 14),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderDrawerPanel() {
    List<Map<String, dynamic>> currentData = [];
    if (_activeNotificationTab == "urgent") {
      currentData = _urgentOrders;
    } else if (_activeNotificationTab == "stock") {
      currentData = _lowStockOrders;
    } else if (_activeNotificationTab == "special") {
      currentData = _specialOrdersList;
    } else {
      currentData = [];
    }

    if (_orderFilter == "ORDERED") {
      currentData = currentData.where((i) => i['ordered'] == true).toList();
    } else if (_orderFilter == "PENDING") {
      currentData = currentData.where((i) => i['pending'] == true || i['ordered'] != true).toList();
    }

    if (_drawerSearchQuery.trim().isNotEmpty) {
      String q = _drawerSearchQuery.trim().toLowerCase();
      currentData = currentData.where((i) {
        String name = (i['name'] ?? '').toString().toLowerCase();
        return name.contains(q);
      }).toList();
    }

    String tabTitle = "LOW STOCK ALERTS";
    switch (_activeNotificationTab) {
      case "urgent":
        tabTitle = "URGENT ORDER BOOK";
        break;
      case "special":
        tabTitle = "SPECIAL ORDERS LIST";
        break;
      case "mobile":
        tabTitle = "MOBILE ORDERS";
        break;
    }

    return Positioned(
      top: 10,
      right: 10,
      bottom: 10,
      width: 550,
      child: GestureDetector(
        onTap: () {}, // Consume clicks
        child: Material(
          elevation: 16,
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blueGrey.shade300, width: 1.5),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 15, offset: Offset(0, 5))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // PANEL HEADER WITH MINIMIZE & CLOSE BUTTONS
                Container(
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E293B),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.inventory_2_rounded, color: Colors.lightBlueAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "$tabTitle (${currentData.length})",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // MINIMIZE BUTTON
                      InkWell(
                        onTap: () => setState(() => _isNotificationHubMinimized = true),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                          child: const Icon(Icons.remove, color: Colors.white, size: 16),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // CLOSE BUTTON
                      InkWell(
                        onTap: () => setState(() => _activeNotificationTab = "none"),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: Colors.red.shade600, borderRadius: BorderRadius.circular(4)),
                          child: const Icon(Icons.close, color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),

                // TAB SWITCHER CHIPS & SEARCH BAR
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  color: Colors.blueGrey.shade50,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _drawerTabChip("stock", "Low Stock", _lowStockOrders.length, Colors.blue),
                          const SizedBox(width: 6),
                          _drawerTabChip("urgent", "Urgent", _urgentOrders.length, Colors.orange.shade800),
                          const SizedBox(width: 6),
                          _drawerTabChip("special", "Special", _specialOrdersList.length, Colors.purple),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: TextField(
                                controller: _drawerSearchCtrl,
                                onChanged: (v) => setState(() => _drawerSearchQuery = v),
                                style: const TextStyle(fontSize: 11),
                                decoration: InputDecoration(
                                  hintText: "Search items in list...",
                                  hintStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                                  prefixIcon: const Icon(Icons.search, size: 16, color: Colors.grey),
                                  suffixIcon: _drawerSearchQuery.isNotEmpty
                                      ? InkWell(
                                          onTap: () {
                                            _drawerSearchCtrl.clear();
                                            setState(() => _drawerSearchQuery = "");
                                          },
                                          child: const Icon(Icons.clear, size: 14, color: Colors.grey),
                                        )
                                      : null,
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildFilterOption("PENDING"),
                          const SizedBox(width: 4),
                          _buildFilterOption("ORDERED"),
                        ],
                      ),
                    ],
                  ),
                ),

                // TABLE HEADERS (REQUESTED SPECIFIC HEADINGS)
                Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                  ),
                  child: Row(
                    children: [
                      Container(width: 40, alignment: Alignment.center, child: const Text("SL NO", style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)))),
                      const Expanded(child: Center(child: Text("ITEM NAME", textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF334155))))),
                      Container(width: 80, alignment: Alignment.center, child: const Text("GENERATED ORDER QTY", textAlign: TextAlign.center, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)))),
                      Container(width: 70, alignment: Alignment.center, child: const Text("ORDERED QTY", textAlign: TextAlign.center, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)))),
                      Container(width: 70, alignment: Alignment.center, child: const Text("ORDER STATUS", textAlign: TextAlign.center, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)))),
                      Container(width: 70, alignment: Alignment.center, child: const Text("P.RATE", textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)))),
                    ],
                  ),
                ),

                // FULL-HEIGHT SCROLLABLE LIST BODY
                Expanded(
                  child: currentData.isEmpty
                      ? Center(
                          child: Text(
                            _isLoadingNotifications ? "Loading alerts..." : "No items found in list.",
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        )
                      : _safeScrollbar(
                          controller: _notifListScrollCtrl,
                          thumbVisibility: true,
                          thickness: 6,
                          child: ListView.builder(
                            controller: _notifListScrollCtrl,
                            itemCount: currentData.length,
                            padding: EdgeInsets.zero,
                            itemBuilder: (ctx, i) {
                              final item = currentData[i];
                              return _NotificationItemRow(
                                key: ValueKey(item['id'] ?? i),
                                item: item,
                                index: i,
                                onChanged: () => setState(() {}),
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
  }



  void _showSyncSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final config = ServerConfigService.instance;
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.sync_rounded, color: Colors.teal),
                SizedBox(width: 8),
                Text("Save & Cloud Sync Settings"),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    "Instant Storage + Background Cloud Sync",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  subtitle: const Text(
                    "Saves entries to local storage immediately and syncs to cloud in background without showing loading screen.",
                    style: TextStyle(fontSize: 11),
                  ),
                  value: config.bgSyncOnSave,
                  activeThumbColor: Colors.teal,
                  onChanged: (val) async {
                    await config.setBgSyncOnSave(val);
                    setDlgState(() {});
                  },
                ),
                const Divider(),
                const Text(
                  "CLOUD STATUS",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      config.isConnected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                      color: config.isConnected ? Colors.green : Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      config.isConnected ? "Cloud Server Connected" : "Offline / Standby Mode",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: config.isConnected ? Colors.green.shade800 : Colors.orange.shade800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text("Sync Pending Records Now"),
                onPressed: () {
                  SupabaseSyncService.instance.triggerInstantSync();
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Sync cycle triggered in background")),
                  );
                },
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Close"),
              ),
            ],
          );
        },
      ),
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
                _legendTile(Colors.amber.shade100, Colors.orange.shade900, "Orange / Amber Text", "Low Margin Alert (< 23.7% pure profit margin)"),
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
          Expanded(child: Text(desc, style: const TextStyle(fontSize: 11, color: Colors.black))),
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
          Text(label, style: TextStyle(fontSize: 12, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color ?? Colors.black)),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: isBold ? FontWeight.bold : FontWeight.w600, color: color ?? Colors.black)),
        ],
      ),
    );
  }

  Widget _topActionBtn(dynamic icon, String label, Color color, {Color? textColor, VoidCallback? onTap}) {
    bool isBusy = _isSaving || _isLoading || _isDeleting;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: label,
        child: MouseRegion(
          cursor: isBusy ? SystemMouseCursors.basic : SystemMouseCursors.click,
          child: InkWell(
            onTap: isBusy ? null : onTap,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: icon is IconData
                  ? Icon(icon, size: 26, color: isBusy ? Colors.grey : color)
                  : SizedBox(width: 26, height: 26, child: icon),
            ),
          ),
        ),
      ),
    );
  }

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
    _watermarkTimer = Timer(const Duration(milliseconds: 2000), () {
      if (mounted) setState(() => _showAgentWatermark = false);
    });
  }

  Widget _buildAgentWatermark() {
    if (!_showAgentWatermark) return const SizedBox.shrink();
    return IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutBack,
          builder: (context, value, child) {
            return Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.6 + (value * 0.4),
                child: child,
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 24, offset: Offset(0, 8))
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_pin_rounded, size: 42, color: Colors.white),
                const SizedBox(width: 14),
                Text(
                  _watermarkAgent.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }



  void _clearGridMaps() {
    final oldCtrls = Map.from(_gridCtrls);
    final oldNodes = Map.from(_gridFocusNodes);
    _gridCtrls.clear();
    _gridFocusNodes.clear();

    for (var ctrl in _nextRowCtrls.values) {
      ctrl.clear();
      try { ctrl.dispose(); } catch (_) {}
    }
    _nextRowCtrls.clear();

    for (var node in _nextRowNodes.values) {
      try { node.dispose(); } catch (_) {}
    }
    _nextRowNodes.clear();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (var m in oldCtrls.values) {
        for (var c in m.values) {
          try { c.dispose(); } catch (_) {}
        }
      }
      for (var m in oldNodes.values) {
        for (var f in m.values) {
          try { f.dispose(); } catch (_) {}
        }
      }
    });
  }

  void _loadGlobalSession(Map<String, dynamic> s) {
    _items.clear();
    _clearGridMaps();
    _isExistingEntry = false;
    _isDeleted = false;
    _date = DateTime.now();
    _timeNotifier.value = DateFormat('hh:mm a').format(_date);
    _items.addAll(List<SaleItem>.from(s['items']));
    _selectedAgent = s['agent'];
    _agentCtrl.text = _selectedAgent;
    _triggerAgentWatermark(_selectedAgent);
    _customerAcc = s['customerAcc'];
    _customerAccCtrl.text = _customerAcc;
    _patientCtrl.text = s['patient'];
    _mobileCtrl.text = s['mobile'];
    String docRestored = s['doctor']?.toString().trim() ?? '';
    if (docRestored.isEmpty || docRestored.toLowerCase() == 'unknown' || docRestored.toLowerCase() == 'dr. unknown') {
      docRestored = 'D1';
    }
    _doctorCtrl.text = docRestored;
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

  bool _isCheckingEntryNo = false;

  Future<void> _checkAndRefreshEntryNo() async {
    if (_isCheckingEntryNo || _isExistingEntry || _items.isNotEmpty || _isDirty || _isDisposed || !mounted) return;
    _isCheckingEntryNo = true;
    try {
      final p = Provider.of<PharmacyProvider>(context, listen: false);
      final bool currentTaken = await p.isEntryTaken('sales_invoices', _entryNo);
      final String freshNext = await p.getNextSaleEntryNo();

      if (!mounted || _isExistingEntry || _items.isNotEmpty || _isDirty || _isDisposed) return;

      int currentNum = p.parseSequenceNumber(_entryNo);
      int freshNum = p.parseSequenceNumber(freshNext);

      // Refresh if current entry was taken OR if server has a higher entry sequence
      if ((currentTaken || freshNum > currentNum) && freshNext.isNotEmpty && _entryNo != freshNext) {
        if (!_isDisposed && mounted) {
          setState(() {
            p.releaseEntryNo(_entryNo);
            _entryNo = freshNext;
            _entryNoCtrl.text = formatSaleDisplayNo(_entryNo);
            p.reserveEntryNo(_entryNo);
          });
        }
      }
    } catch (_) {
    } finally {
      _isCheckingEntryNo = false;
    }
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

    if (!_isExistingEntry && _items.isEmpty && !_isDirty) {
      _checkAndRefreshEntryNo();
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
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final accountMaster = p.accountMaster;
    final accounts = p.accounts;

    // Dynamic Styling based on stored Account colors
    Color baseColor = const Color(0xFF94A3B8); // Default Slate

    // Find the matching account object to get its assigned color
    final String currentAccName = _customerAcc.toUpperCase().trim();
    try {
      final account = accountMaster.firstWhere(
        (a) => a.name.toUpperCase().trim() == currentAccName,
      );
      baseColor = Color(int.parse(account.color));
    } catch (_) {
      // Fallback logic for common legacy names if not found in master
      if (currentAccName == "CASH") {
        baseColor = const Color(0xFF4CAF50);
      } else if (currentAccName == "UPI") {
        baseColor = const Color(0xFF2196F3);
      } else if (currentAccName == "NOT RECIEVED" || currentAccName == "NOT RECEIVED") {
        baseColor = const Color(0xFFEF5350);
      } else if (currentAccName == "PREVIOUS DAY") {
        baseColor = const Color(0xFFFBC02D);
      }
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
            return accounts;
          }

          return accounts.where((acc) => acc.toLowerCase().contains(query));
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
            // ROW 1: Left (Entry No, Patient, Mob, Dues Badge) -> Right (Days, Import, Export, TAX TYPE)
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
                            SizedBox(
                              width: 165,
                              child: _headerColumn("Entry No:", Row(
                                children: [
                                  FluentNavButton(
                                    icon: Icons.chevron_left_rounded,
                                    tooltip: "Previous Entry (Page Up / Left)",
                                    isBusy: _isNavigating,
                                    onTap: _isNavigating ? null : () => _navigateEntry('prev'),
                                  ),
                                  const SizedBox(width: 3),
                                  Container(
                                    width: 70, height: 26,
                                    padding: const EdgeInsets.symmetric(horizontal: 2),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: _isDeleted ? const Color(0xFFFEF2F2) : (_isBlankRecord ? const Color(0xFFEFF6FF) : Colors.white),
                                      border: Border.all(
                                        color: _isNavigating ? Colors.blue.shade600 : (_isDeleted ? const Color(0xFF7F1D1D) : (_isBlankRecord ? Colors.lightBlue : Colors.grey.shade400)), 
                                        width: (_isDeleted || _isBlankRecord || _isNavigating) ? 1.5 : 1.0,
                                      ),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: _isNavigating
                                        ? SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(strokeWidth: 1.8, valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade700)),
                                          )
                                        : TextField(
                                            controller: _entryNoCtrl,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _isDeleted ? const Color(0xFF7F1D1D) : Colors.black87),
                                            decoration: const InputDecoration(
                                              border: InputBorder.none,
                                              isDense: true,
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                            onSubmitted: (typedNo) {
                                              final clean = typedNo.trim();
                                              if (clean.isNotEmpty) {
                                                _loadSaleData(clean);
                                              }
                                            },
                                          ),
                                  ),
                                  const SizedBox(width: 3),
                                  FluentNavButton(
                                    icon: Icons.chevron_right_rounded,
                                    tooltip: "Next Entry (Page Down / Right)",
                                    isBusy: _isNavigating,
                                    onTap: _isNavigating ? null : () => _navigateEntry('next'),
                                  ),
                                ],
                              )),
                            ),
                            const SizedBox(width: 12),

                            _headerColumn("Patient", _buildPatientAutocomplete()),
                            const SizedBox(width: 8),
                            _headerColumn("Mob", _headerInp(1, width: 90, height: 26, onSubmitted: (_) => _moveFocus(-1, 2))),
                            const SizedBox(width: 4),
                            _buildPatientLedgerBadge(),
                          ],
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _headerColumn("Days", _headerInp(3, width: 35, height: 26, onSubmitted: (_) => _moveFocus(_items.length, 1))),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    _btnWithIcon(Icons.file_download_rounded, "Import", Colors.blue.shade700, onTap: _importPrescription),
                                    const SizedBox(width: 4),
                                    _btnWithIcon(Icons.file_upload_rounded, "Export", Colors.green.shade700, onTap: _exportPrescription),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            _headerColumn("TAX TYPE", Row(children: [_radio("Gst", 1), _radio("No", 2)]), align: CrossAxisAlignment.center),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 4),

            // ROW 2: Date & Time, Doctor, ORDER
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
                                      Text(DateFormat('dd/MM/yyyy').format(_date), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                                      const Spacer(), const Icon(Icons.calendar_month, size: 10, color: Colors.orange),
                                    ]),
                                  )),
                                  const SizedBox(width: 2),
                                  _headerColumn("Time", Container(
                                    width: 70, height: 26, alignment: Alignment.center,
                                    decoration: BoxDecoration(color: const Color(0xFFF1F8E9), border: Border.all(color: Colors.green.shade300), borderRadius: BorderRadius.circular(4)),
                                    child: ValueListenableBuilder<String>(
                                      valueListenable: _timeNotifier,
                                      builder: (_, timeStr, __) => Text(timeStr, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                                    ),
                                  )),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),

                            _headerColumn("Doctor", _buildDoctorAutocomplete()),
                            const SizedBox(width: 12),
                            _headerColumn("ORDER", _buildOrderTypeToggle(), align: CrossAxisAlignment.center),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 12),
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      _orderType = 1; // Special Order
                                      _showSpecialOrderSidebar = true;
                                      _isSpecialOrderMinimized = false;
                                      _isProductSyncEnabled = false;
                                      _isSpecialSyncEnabled = false;
                                      _specialOrderQtys.clear();
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        _specialSearchFocus.requestFocus();
                                      });
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    height: 28,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade700,
                                      borderRadius: BorderRadius.circular(6),
                                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.add_shopping_cart_rounded, size: 15, color: Colors.white),
                                        SizedBox(width: 5),
                                        Text(
                                          "+ Add Special Order",
                                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _specialSearchFocus.requestFocus();
            });
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

    for (var name in _extraSpecialItems) {
      if (uniqueNames.contains(name)) continue;
      uniqueNames.add(name);
      list.add({'name': name, 'qty': _specialOrderQtys[name] ?? 0});
    }

    if (_isProductSyncEnabled) {
      for (var it in _items.reversed) {
        if (it.product.name.isEmpty || uniqueNames.contains(it.product.name)) continue;
        uniqueNames.add(it.product.name);
        int defaultQty = _isSpecialSyncEnabled ? it.qty : 0;
        list.add({'name': it.product.name, 'qty': _specialOrderQtys[it.product.name] ?? defaultQty});
      }
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
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Focus(
                            onKeyEvent: (node, event) {
                              if (_specialSearchList.value.isNotEmpty) {
                                final list = _specialSearchList.value;
                                if (event is KeyDownEvent || event is KeyRepeatEvent) {
                                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                                    _searchIdx.value = (_searchIdx.value + 1).clamp(0, list.length - 1);
                                    _scrollToIdx(_searchIdx.value);
                                    return KeyEventResult.handled;
                                  } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                                    _searchIdx.value = (_searchIdx.value - 1).clamp(0, list.length - 1);
                                    _scrollToIdx(_searchIdx.value);
                                    return KeyEventResult.handled;
                                  } else if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
                                    final idx = _searchIdx.value.clamp(0, list.length - 1);
                                    _specialMainCtrl.text = list[idx].name;
                                    _specialSearchList.value = []; // CLOSE DROPDOWN IMMEDIATELY
                                    _specialSearchQtyFocus.requestFocus();
                                    _specialSearchQtyCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _specialSearchQtyCtrl.text.length);
                                    return KeyEventResult.handled;
                                  }
                                }
                              }
                              return KeyEventResult.ignored;
                            },
                            child: TextField(
                              controller: _specialMainCtrl,
                              focusNode: _specialSearchFocus,
                              onChanged: _startSpecialProductSearch,
                              onSubmitted: (v) {
                                if (_specialSearchList.value.isNotEmpty) {
                                  final list = _specialSearchList.value;
                                  final idx = _searchIdx.value.clamp(0, list.length - 1);
                                  _specialMainCtrl.text = list[idx].name;
                                  _specialSearchList.value = []; // CLOSE DROPDOWN IMMEDIATELY
                                } else {
                                  _specialSearchList.value = [];
                                }
                                if (_specialMainCtrl.text.trim().isEmpty) {
                                  _specialCustomerNameFocus.requestFocus();
                                  _specialCustomerNameCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _specialCustomerNameCtrl.text.length);
                                } else {
                                  _specialSearchQtyFocus.requestFocus();
                                  _specialSearchQtyCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _specialSearchQtyCtrl.text.length);
                                }
                              },
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
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 75,
                          child: TextField(
                            controller: _specialSearchQtyCtrl,
                            focusNode: _specialSearchQtyFocus,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            onTap: () {
                              _specialSearchList.value = []; // CLOSE DROPDOWN IF QTY IS TAPPED
                            },
                            onSubmitted: (_) {
                              final String v = _specialMainCtrl.text.trim();
                              final int qtyVal = int.tryParse(_specialSearchQtyCtrl.text.trim()) ?? 1;
                              if (v.isNotEmpty) {
                                setState(() {
                                  _extraSpecialItems.remove(v);
                                  _extraSpecialItems.insert(0, v);
                                  _specialOrderQtys[v] = qtyVal;
                                  _specialMainCtrl.clear();
                                  _specialSearchList.value = [];
                                  _specialSearchQtyCtrl.text = "1";
                                });
                              }
                              _specialSearchFocus.requestFocus();
                            },
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              hintText: "QTY",
                              isDense: true,
                              filled: true,
                              fillColor: Colors.blue.shade50,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                    ValueListenableBuilder<List<Product>>(
                      valueListenable: _specialSearchList,
                      builder: (ctx, list, _) {
                        if (list.isEmpty) return const SizedBox();
                        return Container(
                          margin: const EdgeInsets.only(top: 4),
                          height: 150,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.blue.shade900, width: 2),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                height: 24,
                                color: Colors.blue.shade900,
                                child: const Row(
                                  children: [
                                    _Hdr("Product", width: 180),
                                    _Hdr("Pack", width: 70, align: TextAlign.right),
                                    _Hdr("Qty", flex: 1, align: TextAlign.right),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ValueListenableBuilder<int>(
                                  valueListenable: _searchIdx,
                                  builder: (ctx, idx, _) => ListView.builder(
                                    padding: EdgeInsets.zero,
                                    itemCount: list.length,
                                    itemBuilder: (ctx, i) {
                                      final p = list[i];
                                      bool sel = i == idx;
                                      return InkWell(
                                        onTap: () => _onSpecialProductSelected(p),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: sel ? Colors.blue.shade100 : Colors.white,
                                            border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.5)),
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                flex: 3,
                                                child: Text(
                                                  p.name,
                                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: sel ? Colors.blue.shade900 : Colors.black),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              SizedBox(
                                                width: 70,
                                                child: Text(
                                                  p.packSize > 0 ? p.packSize.toString() : "",
                                                  textAlign: TextAlign.right,
                                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 1,
                                                child: Text(
                                                  p.stock.toString(),
                                                  textAlign: TextAlign.right,
                                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: p.stock > 0 ? Colors.green.shade800 : Colors.red.shade800),
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
                          ),
                        );
                      },
                    ),
                  ],
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
                              _specialSearchFocus.requestFocus();
                              _specialMainCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _specialMainCtrl.text.length);
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
              const Divider(height: 1),
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
                        onSubmitted: (_) {
                          _expectingDateFocus.requestFocus();
                          _pickExpectingDate();
                        },
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
                        onSubmitted: (_) => _pickExpectingDate(),
                        onTap: _pickExpectingDate,
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



  Widget _buildPatientLedgerBadge() {
    String patientName = _patientCtrl.text.trim();
    if (patientName.isEmpty ||
        patientName.toUpperCase() == 'P1' ||
        patientName.toUpperCase() == 'GENERAL' ||
        patientName.toUpperCase() == 'CASH') {
      return const SizedBox.shrink();
    }

    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    return FutureBuilder<double>(
      future: provider.getPatientNetBalance(patientName),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == 0.0) {
          return const SizedBox.shrink();
        }
        double prevDues = snapshot.data!;
        return Container(
          margin: const EdgeInsets.only(left: 4, top: 12),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: prevDues > 0 ? Colors.red.shade50 : Colors.green.shade50,
            border: Border.all(color: prevDues > 0 ? Colors.red.shade300 : Colors.green.shade300),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                prevDues > 0 ? Icons.account_balance_wallet_outlined : Icons.check_circle_outline,
                size: 11,
                color: prevDues > 0 ? Colors.red.shade800 : Colors.green.shade800,
              ),
              const SizedBox(width: 3),
              Text(
                "Prev: ₹${prevDues.toStringAsFixed(2)}",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: prevDues > 0 ? Colors.red.shade900 : Colors.green.shade900,
                ),
              ),
            ],
          ),
        );
      },
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
          if (!_isPatientTyping || textEditingValue.text.trim().isEmpty) return const Iterable<String>.empty();
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
          _isPatientTyping = false;
          final provider = Provider.of<PharmacyProvider>(context, listen: false);
          if (selection.startsWith('ADD NEW NAME: ')) {
            final newName = selection.replaceAll('ADD NEW NAME: ', '').trim();
            final newPatient = Patient(
              id: "PAT_${DateTime.now().millisecondsSinceEpoch}",
              name: newName,
              mobile: _mobileCtrl.text.trim(),
            );
            await provider.registerPatient(newPatient);
            if (!mounted) return;
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
            onEditingComplete: onEditingComplete,
            onChanged: (val) {
              if (!_isPatientTyping) {
                setState(() {
                  _isPatientTyping = true;
                });
              }
            },
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
                            color: shouldHighlight ? Colors.blue.shade900 : (isNew ? Colors.blue.shade700 : Colors.black),
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
          if (!_isDoctorTyping || textEditingValue.text.trim().isEmpty) {
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
          _isDoctorTyping = false;
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
            if (!mounted) return;
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
            onEditingComplete: onEditingComplete,
            onChanged: (val) {
              if (!_isDoctorTyping) {
                setState(() {
                  _isDoctorTyping = true;
                });
              }
            },
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
                            color: shouldHighlight ? Colors.blue.shade900 : (isNew ? Colors.blue.shade700 : Colors.black),
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
          // ignore: deprecated_member_use
          groupValue: _gstType,
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          // ignore: deprecated_member_use
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
              onResize: (v) {
                setState(() {
                  _colWidths[i] = v;
                  _hasCustomColWidths = true;
                });
                _debouncedSaveColumnWidths();
              },
              align: _getColAlign(i),
              onTap: i == 15 ? () => setState(() => _showProfitColumn = !_showProfitColumn) : null,
            ),
          ),
        ),
      );

  String _getColName(int i) => [
        "Slr", "BALANCE", "Product", "Rack", "Batch", "Expiry", "Pack", "Qty",
        "Strips", "MRP", "1 /MRP", "Disc%", "Disc Amt", "GST%", "Total",
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

  Widget _buildGrid() {
    final billQuantities = _getBillQuantitiesMap();
    return RepaintBoundary(
      child: _safeScrollbar(
        controller: _verticalGridScrollCtrl,
        child: ListView.builder(
          controller: _verticalGridScrollCtrl,
          padding: EdgeInsets.zero,
          itemExtent: 30.0,
          itemCount: _items.length + (_isDeleted ? 0 : 1),
          itemBuilder: (ctx, i) => RepaintBoundary(
            child: i < _items.length ? _buildRow(i, billQuantities) : _buildEmptyRow(i),
          ),
        ),
      ),
    );
  }

  // ---> FALLBACK GETTERS PREVENT SCOPE ERRORS <---
  Color get defaultColor => Colors.black;
  Color get nameColor => Colors.black;
  Color get expiryColor => Colors.black;

  // Pre-computes bill quantities in a single pass to eliminate O(N^2) frame lag
  Map<String, int> _getBillQuantitiesMap() {
    Map<String, int> usage = {};
    for (var other in _items) {
      final nameKey = Product.cleanProductName(other.product.name).toLowerCase();
      if (nameKey.isNotEmpty) {
        usage[nameKey] = (usage[nameKey] ?? 0) + other.qty + other.fQty;
      }
      if (other.product.id.isNotEmpty) {
        usage[other.product.id] = (usage[other.product.id] ?? 0) + other.qty + other.fQty;
      }
    }
    return usage;
  }

  int _getLiveRemainingStock(int row, Map<String, int> billQuantities) {
    if (row >= _items.length) return 0;
    final it = _items[row];
    final cleanName = Product.cleanProductName(it.product.name).toLowerCase();
    if (cleanName.isEmpty) return 0;

    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    int totalAllBatchesStock = provider.getTotalStockForProduct(cleanName);
    if (totalAllBatchesStock <= 0 && it.product.stock > 0) {
      totalAllBatchesStock = it.product.stock;
    }

    int totalQtyInBill = billQuantities[it.product.id] ?? billQuantities[cleanName] ?? 0;

    int remaining = totalAllBatchesStock - totalQtyInBill;
    return remaining < 0 ? 0 : remaining;
  }

  Widget _buildRow(int row, Map<String, int> billQuantities) {
    final it = _items[row];
    double profit = it.profit;

    bool isExpired = it.product.expiry.isNotEmpty && _parseExpiry(it.product.expiry).isBefore(DateTime(_date.year, _date.month, _date.day));
    bool isH1 = it.product.schedule.toUpperCase() == "H1";

    // Row-specific font colors
    Color rowNameColor = isH1 ? Colors.red.shade700 : (isExpired ? Colors.red.shade900 : Colors.black);
    Color rowExpiryColor = isExpired ? Colors.red.shade900 : Colors.black;
    Color rowDefaultColor = isH1 ? Colors.red.shade900 : Colors.black;

    int liveRemStock = _getLiveRemainingStock(row, billQuantities);
    Color remColor = liveRemStock > 0
        ? Colors.teal.shade800
        : (liveRemStock == 0 ? Colors.orange.shade900 : Colors.red.shade700);

    bool isNewRow = false;
    bool isQtyMod = false;
    bool isBatchMod = false;
    bool isDiscMod = false;
    bool isProdMod = false;

    if (_isExistingEntry && _originalLoadedInvoice != null) {
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

        bool isHighlightedProduct = _highlightedRowIndices.contains(row);
        Color rowBg = isHighlightedProduct
            ? const Color(0xFFFFF9C4)
            : (isRowActive
                ? const Color(0xFFF0F7FF)
                : (isH1 ? Colors.red.shade50 : (row % 2 == 0 ? Colors.white : const Color(0xFFF9FAFB))));

        return Container(
          key: ValueKey("s_row_${it.uuid}"),
          height: 30,
          decoration: BoxDecoration(
            color: rowBg,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.5)),
          ),
          child: Row(
            children: [
              _cell(row, 0, _isDeleted ? "" : "${row + 1}", _colWidths[0]!, align: TextAlign.center, color: rowDefaultColor),
              _cell(row, 1, _isDeleted ? "" : "$liveRemStock", _colWidths[1]!, align: TextAlign.center, fontWeight: FontWeight.bold, color: remColor),
              _cell(row, 2, _isDeleted ? "" : it.product.name.toUpperCase(), _colWidths[2]!, isInput: true, fontWeight: FontWeight.bold, color: rowNameColor, cellBg: (isNewRow || isProdMod) ? _editHighlightBg : null, onChanged: (v) {
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
              _cell(row, 3, _isDeleted ? "" : it.product.rack.toUpperCase(), _colWidths[3]!, align: TextAlign.center, color: rowDefaultColor),
              _cell(row, 4, _isDeleted ? "" : _cleanBatch(it.product.batch).toUpperCase(), _colWidths[4]!, isInput: true, color: rowExpiryColor, cellBg: (isNewRow || isBatchMod) ? _editHighlightBg : null, onChanged: (v) {
                it.product.batch = v;
                _startBatchSearch(row, v);
              }),
              _cell(row, 5, _isDeleted ? "" : it.product.expiry, _colWidths[5]!, isInput: true, align: TextAlign.center, color: rowExpiryColor, hint: "MM/YY", onChanged: (v) {
                it.product.expiry = v;
              }),
              _cell(row, 6, _isDeleted ? "" : it.packin.toString(), _colWidths[6]!, align: TextAlign.right, color: Colors.blueGrey, isLocked: true),
              _cell(row, 7, _isDeleted ? "" : it.qty.toString(), _colWidths[7]!, isInput: true, align: TextAlign.right, color: rowDefaultColor, cellBg: (isNewRow || isQtyMod) ? _editHighlightBg : null, onChanged: (v) {
                it.qty = int.tryParse(v) ?? 0;
                _calculateItem(row);
              }),
              _cell(row, 8, "", _colWidths[8]!, align: TextAlign.center, isLocked: true,
                customLabel: _isDeleted ? const SizedBox.shrink() : RichText(
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
              _cell(row, 9, _isDeleted ? "" : ((it.product.mrp >= it.mrp && it.product.mrp > it.mrp * 1.5) ? it.product.mrp : (it.mrp * (it.packin > 0 ? it.packin : 1))).toStringAsFixed(2), _colWidths[9]!, align: TextAlign.right, color: rowDefaultColor),
              _cell(row, 10, _isDeleted ? "" : it.mrp.toStringAsFixed(2), _colWidths[10]!, align: TextAlign.right, color: rowDefaultColor),
              _cell(row, 11, _isDeleted ? "" : it.discPercent.toStringAsFixed(2), _colWidths[11]!, isInput: true, align: TextAlign.right, color: rowDefaultColor, cellBg: (isNewRow || isDiscMod) ? _editHighlightBg : null, onChanged: (v) {
                it.discPercent = double.tryParse(v) ?? 0;
                _calculateItem(row);
              }),
              _cell(row, 12, _isDeleted ? "" : it.discAmt.toStringAsFixed(2), _colWidths[12]!, align: TextAlign.right, color: rowDefaultColor),
              _cell(row, 13, _isDeleted ? "" : ((_gstType == 1 ? TaxCalculator.roundGstPercent(it.gstPercent) : 0.0) % 1 == 0 ? (_gstType == 1 ? TaxCalculator.roundGstPercent(it.gstPercent) : 0.0).toInt().toString() : (_gstType == 1 ? TaxCalculator.roundGstPercent(it.gstPercent) : 0.0).toStringAsFixed(1)), _colWidths[13]!, align: TextAlign.right, color: rowDefaultColor),
              _cell(row, 14, _isDeleted ? "" : it.total.toStringAsFixed(2), _colWidths[14]!, align: TextAlign.right, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
              _cell(row, 15, (_showProfitColumn && !_isDeleted) ? profit.toStringAsFixed(2) : "", _colWidths[15]!, align: TextAlign.right, color: profit >= 0 ? Colors.green.shade700 : Colors.red),
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

  ({Color bg, Color text})? _evalSalesRuleStyle(PharmacyProvider provider, SaleItem item, int col, String text) {
    final rules = provider.getValidationRules("SALES");
    if (rules.isEmpty) return null;

    for (var rule in rules) {
      if (!rule.enabled) continue;

      bool appliesToCol = false;
      if (rule.fieldA == "Disc %" && col == 11) appliesToCol = true;
      if (rule.fieldA == "Expiry (Months)" && col == 5) appliesToCol = true;
      if (rule.fieldA == "Pack Size" && col == 6) appliesToCol = true;
      if (rule.fieldA == "Qty" && col == 7) appliesToCol = true;
      if (rule.fieldA == "MRP" && (col == 9 || col == 10)) appliesToCol = true;
      if (rule.fieldA == "GST %" && col == 13) appliesToCol = true;
      if (rule.fieldA == "Total" && col == 14) appliesToCol = true;

      if (!appliesToCol) continue;

      double valA = 0.0;
      switch (rule.fieldA) {
        case "Disc %":
          valA = double.tryParse(text) ?? item.discPercent;
          break;
        case "Expiry (Months)":
          valA = _getExpiryMonths(text.isNotEmpty ? text : item.product.expiry);
          break;
        case "Pack Size":
          valA = item.packin.toDouble();
          break;
        case "Qty":
          valA = double.tryParse(text) ?? item.qty.toDouble();
          break;
        case "MRP":
          valA = item.mrp;
          break;
        case "GST %":
          valA = item.gstPercent;
          break;
        case "Total":
          valA = item.total;
          break;
        default:
          valA = 0.0;
      }

      if (valA <= 0 && rule.fieldA != "Expiry (Months)") {
        continue;
      }

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
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !isFocused && ctrl.text != val) {
              ctrl.text = val;
            }
          });
        }

        const bool isEntryLocked = false;
        bool isActuallyInput = isInput && !_isDeleted && !isEntryLocked && !isLocked;
        bool renderAsTextField = isActuallyInput;

        Color? bg;
        BoxBorder? customBorder;
        BorderRadius? customRadius;
        EdgeInsetsGeometry? customMargin;

        bool isModifiedCell = (cellBg != null);
        bool hasProduct = row < _items.length && _items[row].product.name.trim().isNotEmpty;
        bool isQtyZero = (!_isDeleted && hasProduct && col == 7 && (_items[row].qty <= 0 || ctrl.text.trim() == "0" || (double.tryParse(ctrl.text.trim()) ?? 0) <= 0));

        bool isHighlightedProduct = _highlightedRowIndices.contains(row);

        final provider = Provider.of<PharmacyProvider>(context, listen: false);
        final ruleStyle = (row < _items.length && !_isDeleted) ? _evalSalesRuleStyle(provider, _items[row], col, val) : null;

        if (_errorCells[row]?.contains(col) == true || isQtyZero) {
          bg = Colors.red.shade100;
          customBorder = Border.all(color: Colors.red.shade700, width: 1.5);
          customRadius = BorderRadius.circular(2);
        } else if (ruleStyle != null) {
          bg = ruleStyle.bg;
        } else if (isModifiedCell) {
          // ---> 3D RED BOX (MATCHING PHOTO 2 DATE BOX) <---
          bg = _editHighlightBg;
          customBorder = Border.all(color: _editHighlightBorder, width: 1.2);
          customRadius = BorderRadius.circular(4);
          customMargin = const EdgeInsets.symmetric(horizontal: 2, vertical: 2);
        } else if (isHighlightedProduct) {
          bg = const Color(0xFFFFF9C4);
        } else if (isLocked) {
          bg = const Color(0xFFF1F5F9);
        } else {
          bg = (row % 2 == 0) ? Colors.white : const Color(0xFFF8FAFC);
          if (isFocused && isActuallyInput) {
            bg = const Color(0xFFEFF6FF);
          }
        }

        Color textColor = (ruleStyle != null)
            ? ruleStyle.text
            : ((color == Colors.blueGrey || color == Colors.grey || color == null)
                ? Colors.black
                : color);

        Widget cellContent = renderAsTextField
            ? ErpGridTextField(
                key: ValueKey("s_tf_${rowId}_$col"), 
                controller: ctrl, 
                focusNode: actualFocusNode, 
                textAlign: align,
                keyboardType: (col == 7 || col == 11 || col == 12) ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                inputFormatters: (col == 7 || col == 11 || col == 12) ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : (col == 5 ? [ExpiryFormatter()] : [UpperCaseTextFormatter()]),
                onNavigatePrevious: () {
                  int curIdx = _navCols.indexOf(col);
                  if (curIdx > 0) {
                    _moveFocus(row, _navCols[curIdx - 1], autoOpen: _navCols[curIdx - 1] == 4);
                  } else if (curIdx == 0 && row > 0) {
                    _moveFocus(row - 1, _navCols.last);
                  }
                },
                onNavigateNext: () {
                  if (row == _items.length && _getGridCtrl(row, 2).text.trim().isEmpty) {
                    _closeAllDropdowns();
                    _focusNotifier.value = null;
                    _rcvdAmtFocus.requestFocus();
                    _rcvdAmtCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _rcvdAmtCtrl.text.length);
                  } else {
                    int curIdx = _navCols.indexOf(col);
                    if (curIdx != -1 && curIdx < _navCols.length - 1) {
                      _moveFocus(row, _navCols[curIdx + 1], autoOpen: _navCols[curIdx + 1] == 4);
                    } else if (curIdx == _navCols.length - 1 && row < _items.length) {
                      _moveFocus(_items.length, _navCols.first, autoOpen: true);
                    }
                  }
                },
                onNavigateUp: () {
                  final bool isOverlayOpen = _searchList.value.isNotEmpty ||
                      _batchList.value.isNotEmpty ||
                      _specialSearchList.value.isNotEmpty ||
                      _patientSearchList.value.isNotEmpty ||
                      _doctorSearchList.value.isNotEmpty;
                  if (isOverlayOpen) {
                    final list = _patientSearchList.value.isNotEmpty ? _patientSearchList.value
                        : _doctorSearchList.value.isNotEmpty ? _doctorSearchList.value
                        : _specialSearchList.value.isNotEmpty ? _specialSearchList.value
                        : ((_isSelectingBatch || col == 4) && _batchList.value.isNotEmpty ? _batchList.value
                        : (_searchList.value.isNotEmpty ? _searchList.value : _batchList.value));
                    if (list.isNotEmpty) {
                      _searchIdx.value = (_searchIdx.value - 1).clamp(0, list.length - 1);
                      _scrollToIdx(_searchIdx.value);
                    }
                    return;
                  }
                  if (row > 0) {
                    int nextCol = _navCols.contains(col) ? col : 1;
                    _moveFocus(row - 1, nextCol);
                  } else {
                    _moveFocus(-1, 0);
                  }
                },
                onNavigateDown: () {
                  final bool isOverlayOpen = _searchList.value.isNotEmpty ||
                      _batchList.value.isNotEmpty ||
                      _specialSearchList.value.isNotEmpty ||
                      _patientSearchList.value.isNotEmpty ||
                      _doctorSearchList.value.isNotEmpty;
                  if (isOverlayOpen) {
                    final list = _patientSearchList.value.isNotEmpty ? _patientSearchList.value
                        : _doctorSearchList.value.isNotEmpty ? _doctorSearchList.value
                        : _specialSearchList.value.isNotEmpty ? _specialSearchList.value
                        : ((_isSelectingBatch || col == 4) && _batchList.value.isNotEmpty ? _batchList.value
                        : (_searchList.value.isNotEmpty ? _searchList.value : _batchList.value));
                    if (list.isNotEmpty) {
                      _searchIdx.value = (_searchIdx.value + 1).clamp(0, list.length - 1);
                      _scrollToIdx(_searchIdx.value);
                    }
                    return;
                  }
                  if (row < _items.length - 1) {
                    int nextCol = _navCols.contains(col) ? col : 1;
                    _moveFocus(row + 1, nextCol);
                  } else {
                    _rcvdAmtFocus.requestFocus();
                  }
                },
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
                    _moveFocus(row, col, autoOpen: (col == 2 && ctrl.text.trim().isEmpty) || col == 4);
                    if (ctrl.text.trim().isNotEmpty) {
                      ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
                    }
                  } else {
                    if (col == 2) {
                      if (ctrl.text.trim().isEmpty) {
                        _startProductSearch(ctrl.text);
                      }
                    } else if (col == 4) {
                      _startBatchSearch(row, "");
                    }
                  }
                },
                textCapitalization: (col == 5 || col == 11) ? TextCapitalization.none : TextCapitalization.characters,
                style: TextStyle(fontSize: 14, fontWeight: fontWeight ?? FontWeight.bold, color: textColor),
                decoration: InputDecoration(isDense: true, border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4), hintText: hint, hintStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.grey)),
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
    int sumQty = _items.fold(0, (sum, it) => sum + it.qty);
    double sumDisc = _items.fold(0, (sum, it) => sum + it.discAmt);
    double sumTotal = _items.fold(0, (sum, it) => sum + it.total);
    double sumProfit = _items.fold(0, (sum, it) => sum + it.profit);

    return Container(
      height: 28, width: width, color: const Color(0xFF37474F),
      child: Row(children: [
        SizedBox(width: _colWidths[0]! + _colWidths[1]! + _colWidths[2]! + _colWidths[3]! + _colWidths[4]! + _colWidths[5]! + _colWidths[6]!),
        _Hdr(sumQty.toString(), width: _colWidths[7], align: TextAlign.right),
        SizedBox(width: _colWidths[8]! + _colWidths[9]! + _colWidths[10]! + _colWidths[11]!),
        _Hdr(sumDisc.toStringAsFixed(2), width: _colWidths[12], align: TextAlign.right),
        SizedBox(width: _colWidths[13]!),
        _Hdr(sumTotal.toStringAsFixed(2), width: _colWidths[14], align: TextAlign.right),
        _Hdr(_showProfitColumn ? sumProfit.toStringAsFixed(2) : "", width: _colWidths[15], align: TextAlign.right),
        SizedBox(width: _colWidths[16]!),
      ]),
    );
  }

  Widget _buildOverlay() {
    return ListenableBuilder(
      listenable: Listenable.merge([_patientSearchList, _searchList, _batchList, _focusNotifier]),
      builder: (ctx, _) {
        final bool hasActiveOverlay = _patientSearchList.value.isNotEmpty ||
            _searchList.value.isNotEmpty ||
            _batchList.value.isNotEmpty;

        return IgnorePointer(
          ignoring: !hasActiveOverlay,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _buildNameOverlay(_patientLayer, _patientSearchList, _patientCtrl, _mobileFocus),
              _buildNameOverlay(_doctorLayer, _doctorSearchList, _doctorCtrl, null),
              _buildNameOverlay(_specialCustomerLayer, _patientSearchList, _specialCustomerNameCtrl, _specialCustomerPhoneFocus),
              // Obsolete global special order overlay removed.

        ListenableBuilder(
          listenable: Listenable.merge([_searchList, _batchList, _focusNotifier]),
          builder: (ctx, _) {
            final int focusedCol = _focusedColIndex;
            final bool isBatch = (focusedCol == 4 || _isSelectingBatch) && _batchList.value.isNotEmpty;
            final bool isProduct = (focusedCol == 2 || focusedCol == -1) && _searchList.value.isNotEmpty;

            if (!isBatch && !isProduct) return const SizedBox(key: ValueKey('empty_overlay'));

            final list = isBatch ? _batchList.value : _searchList.value;
            if (list.isEmpty) return const SizedBox(key: ValueKey('empty_overlay'));
            
            final link = isBatch ? _batchLayer : _searchLayer;
            final double dropWidth = isBatch ? 780.0 : 1250.0;
            final Offset dropOffset = isBatch ? const Offset(-80, 30) : const Offset(0, 30);

            return CompositedTransformFollower(
              key: ValueKey(isBatch ? 'batch_overlay' : 'product_overlay'),
              link: link,
              showWhenUnlinked: false,
              offset: dropOffset,
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
                                _Hdr("Batch", width: 100),
                                _Hdr("Stock", width: 55, align: TextAlign.right),
                                _Hdr("Packing", width: 55, align: TextAlign.right),
                                _Hdr("Strips/L", width: 65, align: TextAlign.center),
                                _Hdr("Expiry", width: 60, align: TextAlign.center),
                                _Hdr("MRP", width: 65, align: TextAlign.right),
                                _Hdr("S.PRICE", width: 65, align: TextAlign.right),
                                _Hdr("Disc%", width: 50, align: TextAlign.right),
                                _Hdr("1 /MRP", width: 60, align: TextAlign.right),
                                _Hdr("1 /S.PRICE", width: 65, align: TextAlign.right),
                                _Hdr("LCWT", width: 60, align: TextAlign.right),
                                _Hdr("Profit%", flex: 1, align: TextAlign.right)
                              ]
                                  : const [
                                _Hdr("Name", width: 380),
                                _Hdr("Stock", width: 60, align: TextAlign.right),
                                _Hdr("Packin", width: 50, align: TextAlign.right),
                                _Hdr("Strips/L", width: 65, align: TextAlign.center),
                                _Hdr("MRP", width: 65, align: TextAlign.right),
                                _Hdr("PRate", width: 65, align: TextAlign.right),
                                _Hdr("Rack", width: 45),
                                _Hdr("Cat", width: 40),
                                _Hdr("Patent", width: 80),
                                _Hdr("Generic Name", width: 110),
                                _Hdr("Use", flex: 1)
                              ],
                            ),
                          ),
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 168.0),
                          child: _safeScrollbar(
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
                                return ValueListenableBuilder<int>(
                                  valueListenable: _searchIdx,
                                  builder: (ctx, idx, _) {
                                    final p = list[i];
                                    bool sel = i == idx;

                                    int displayStock = p.stock < 0 ? 0 : p.stock;
                                    double ps = p.packSize == 0 ? 1 : p.packSize.toDouble();
                                    double pcsMrp = p.mrp / ps;
                                    double pcsPrice = (p.salePrice > 0 ? p.salePrice : p.mrp) / ps;
                                    double profit = p.purchaseRate > 0
                                        ? ((p.mrp - p.purchaseRate) / p.purchaseRate) * 100
                                        : 0.0;

                                    Color bgColor = Colors.white;
                                    Color fontColor = Colors.black;

                                    if (isBatch) {
                                      if (sel) {
                                        bgColor = Colors.blue.shade200;
                                        fontColor = Colors.blue.shade900;
                                      } else {
                                        bgColor = _getBatchBgColor(p.expiry);
                                        fontColor = _getBatchTextColor(p.expiry);
                                      }
                                    } else {
                                      if (sel) bgColor = Colors.blue.shade50;
                                    }

                                    final bool isH1 = p.schedule.toUpperCase() == "H1";
                                    return MouseRegion(
                                      onHover: (PointerHoverEvent event) {
                                        if (event.kind == PointerDeviceKind.mouse && event.delta != Offset.zero) {
                                          if (_searchIdx.value != i) {
                                            _searchIdx.value = i;
                                            if (!isBatch && p.id != "NEW") {
                                              _updateFooter(p);
                                            }
                                          }
                                        }
                                      },
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTapDown: (_) {
                                          _isSelectingFromDropdown = true;
                                          _searchIdx.value = i;
                                          if (!isBatch && p.id != "NEW") {
                                            _updateFooter(p);
                                          }
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
                                            border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 0.5)),
                                          ),
                                          child: Row(
                                            children: isBatch
                                                ? [
                                                    _GridCell(_cleanBatch(p.batch), width: 100, fontWeight: FontWeight.bold, color: isH1 ? Colors.red.shade900 : Colors.black),
                                                    _GridCell(displayStock.toString(), width: 55, align: TextAlign.right, fontWeight: FontWeight.bold, color: isH1 ? Colors.red.shade900 : Colors.black),
                                                    _GridCell(p.packSize.toString(), width: 55, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : Colors.black),
                                                    _GridCell("${displayStock ~/ (p.packSize > 0 ? p.packSize : 1)} / ${displayStock % (p.packSize > 0 ? p.packSize : 1)}", width: 65, align: TextAlign.center, color: isH1 ? Colors.red.shade700 : Colors.blue.shade700, fontWeight: FontWeight.bold),
                                                    _GridCell(p.expiry, width: 60, align: TextAlign.center, fontWeight: FontWeight.bold, color: fontColor, bgColor: bgColor),
                                                    _GridCell(p.mrp.toStringAsFixed(2), width: 65, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : Colors.black),
                                                    _GridCell((p.salePrice > 0 ? p.salePrice : p.mrp).toStringAsFixed(2), width: 65, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : Colors.black),
                                                    _GridCell(p.sDiscPercent.toStringAsFixed(2), width: 50, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : Colors.black),
                                                    _GridCell(pcsMrp.toStringAsFixed(2), width: 60, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : Colors.black),
                                                    _GridCell(pcsPrice.toStringAsFixed(2), width: 65, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : Colors.black),
                                                    _GridCell(p.purchaseRate.toStringAsFixed(2), width: 60, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : Colors.black),
                                                    _GridCell(profit.toStringAsFixed(2), flex: 1, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : Colors.black),
                                                  ]
                                                : (p.id == "NEW"
                                                    ? [
                                                        _GridCell("+ CREATE NEW MEDICINE: '${p.name}'", flex: 1, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                                                      ]
                                                    : [
                                                        _GridCell(p.name, width: 380, fontWeight: FontWeight.bold, color: isH1 ? Colors.red.shade900 : null),
                                                        _GridCell(displayStock.toString(), width: 60, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : Colors.blue.shade700, fontWeight: FontWeight.bold),
                                                        _GridCell(p.packSize.toString(), width: 50, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : null),
                                                        _GridCell("${displayStock ~/ (p.packSize > 0 ? p.packSize : 1)} / ${displayStock % (p.packSize > 0 ? p.packSize : 1)}", width: 65, align: TextAlign.center, color: isH1 ? Colors.red.shade900 : Colors.blue.shade700, fontWeight: FontWeight.bold),
                                                        _GridCell(p.mrp.toStringAsFixed(2), width: 65, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : null),
                                                        _GridCell(p.purchaseRate.toStringAsFixed(2), width: 65, align: TextAlign.right, color: isH1 ? Colors.red.shade900 : null),
                                                        _GridCell(p.rack, width: 45, color: isH1 ? Colors.red.shade900 : null),
                                                        _GridCell(p.category.length > 3 ? p.category.substring(0, 3).toUpperCase() : p.category, width: 40, color: isH1 ? Colors.red.shade900 : null),
                                                        _GridCell(p.patent, width: 80, color: isH1 ? Colors.red.shade900 : null),
                                                        _GridCell(p.genericName.isNotEmpty ? p.genericName : (Provider.of<PharmacyProvider>(context, listen: false).getProductById(p.id)?.genericName ?? Provider.of<PharmacyProvider>(context, listen: false).getProductMasterByName(p.name)?.genericName ?? ""), width: 110, color: isH1 ? Colors.red.shade900 : null),
                                                        _GridCell(p.use.isNotEmpty ? p.use : (Provider.of<PharmacyProvider>(context, listen: false).getProductById(p.id)?.use ?? Provider.of<PharmacyProvider>(context, listen: false).getProductMasterByName(p.name)?.use ?? ""), flex: 1, color: isH1 ? Colors.red.shade900 : null),
                                                      ]),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
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
    ),
  );
      },
    );
  }

  Widget _buildNameOverlay(LayerLink link, ValueNotifier<List<dynamic>> listNotifier, TextEditingController ctrl, FocusNode? next) {
    return ValueListenableBuilder<List<dynamic>>(
      valueListenable: listNotifier,
      builder: (ctx, list, _) {
        if (list.isEmpty) return const SizedBox(key: ValueKey('empty_name_overlay'));
        return CompositedTransformFollower(
          key: ValueKey(link.hashCode),
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
                                    Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isNew ? Colors.blue.shade900 : Colors.black)),
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
      if (finalValPaise < 0) finalValPaise = 0;
      int roundedGrandTotalPaise = _enableAutoRoundOff
          ? (((finalValPaise / 100.0).round()) * 100)
          : finalValPaise;
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
        double diff = rcvd - rounded;
        _balanceCtrl.text = _fmt(diff.abs());
        _balanceNotifier.value = diff;
      } else {
        _balanceCtrl.text = "0.00";
        _balanceNotifier.value = 0.0;
      }

      _summaryNotifier.value++;
      _syncToGlobalSession(notify: false);

      // --- Reactive Continuous Validation (Eager 0ms Save Overhead) ---
      final validItems = _items.where((it) => it.product.name.trim().isNotEmpty).toList();
      if (validItems.isEmpty) {
        _cachedValidationError = "Please add at least one valid item before saving.";
      } else {
        String? err;
        for (int i = 0; i < validItems.length; i++) {
          final it = validItems[i];
          if (it.qty <= 0 && it.fQty <= 0) {
            err = "Row ${i + 1}: '${it.product.name}' quantity must be greater than 0.";
            break;
          }
          if (it.product.batch.trim().isEmpty) {
            err = "Row ${i + 1}: '${it.product.name}' is missing Batch selection.";
            break;
          }
        }
        _cachedValidationError = err;
      }
    });
  }

  Widget _buildFooter() => Container(height: 168, color: const Color(0xFFF1F5F9), padding: const EdgeInsets.all(6), child: Row(children: [
    Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_footerTitle("Recent Entries:", color: Colors.blue.shade800), _footerTableHdr([{'title': 'Entry No', 'flex': 2}, {'title': 'Total', 'flex': 2, 'align': Alignment.centerRight}]), Expanded(child: _buildRecentInvoicesList())] )),
    const SizedBox(width: 8),

    Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_footerTitle(_activeGenericName.isNotEmpty ? "Generic Availability Helper (${_activeGenericName.toUpperCase()}):" : "Generic Availability Helper:", color: Colors.blue.shade800), _footerTableHdr([{'title': 'Medicine Name', 'flex': 4}, {'title': 'Pack', 'flex': 1, 'align': Alignment.center}, {'title': 'Generic Name', 'flex': 4}, {'title': 'Strips/Loose', 'flex': 2, 'align': Alignment.center}, {'title': 'Stock', 'flex': 1, 'align': Alignment.centerRight}]), Expanded(child: _buildAlternativesList())])),
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
           style: const TextStyle(color: Color(0xFF1E293B), fontSize: 12, fontWeight: FontWeight.bold),
         )
       );
    }

    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), color: Colors.white),
      child: ListView.builder(
        itemCount: _footerAlts.length,
        itemBuilder: (ctx, i) {
          final p = _footerAlts[i];
          bool isEven = i % 2 == 0;
          final genDisplay = p.genericName.isNotEmpty ? p.genericName : _activeGenericName;

          final bool isGenCat = provider.isGenericProduct(p);
          final double margin = p.purchaseRate > 0
              ? (((p.mrp > 0 ? p.mrp : p.salePrice) - p.purchaseRate) / p.purchaseRate) * 100
              : 0.0;
          final bool isHighProfit = !isGenCat && (margin > 40.0);

          final Color rowTextColor = isGenCat
              ? const Color(0xFF15803D) // Green
              : (isHighProfit ? const Color(0xFF1D4ED8) : Colors.blue.shade900); // Blue or Default

          final Color genColor = isGenCat
              ? const Color(0xFF15803D)
              : (isHighProfit ? const Color(0xFF1D4ED8) : Colors.blue.shade700);

          final Color stockColor = isGenCat
              ? const Color(0xFF15803D)
              : (isHighProfit ? const Color(0xFF1D4ED8) : Colors.blue);

          final int packSize = p.packSize > 0 ? p.packSize : 1;
          final int strips = p.stock > 0 ? (p.stock ~/ packSize) : 0;
          final int loose = p.stock > 0 ? (p.stock % packSize) : 0;

          return InkWell(
            onTap: () => _onGenericAltSelected(p),
            child: Container(
              height: 24,
              decoration: BoxDecoration(
                color: isEven ? Colors.white : const Color(0xFFF8F9FA),
                border: Border(bottom: BorderSide(color: Colors.grey.shade200))
              ),
              child: Row(children: [
                Expanded(flex: 4, child: Padding(padding: const EdgeInsets.only(left: 8), child: Text(p.name.toUpperCase(), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: rowTextColor), overflow: TextOverflow.ellipsis))),
                Expanded(flex: 1, child: Container(alignment: Alignment.center, child: Text(packSize.toString(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800), overflow: TextOverflow.ellipsis))),
                Expanded(flex: 4, child: Text(genDisplay.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: (isGenCat || isHighProfit) ? FontWeight.bold : FontWeight.w600, color: genColor), overflow: TextOverflow.ellipsis)),
                Expanded(flex: 2, child: Container(alignment: Alignment.center, child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    children: [
                      TextSpan(
                        text: "$strips",
                        style: const TextStyle(color: Color(0xFF15803D)),
                      ),
                      TextSpan(
                        text: " / ",
                        style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.normal),
                      ),
                      TextSpan(
                        text: "$loose",
                        style: const TextStyle(color: Color(0xFFDC2626)),
                      ),
                    ],
                  ),
                ))),
                Expanded(flex: 1, child: Container(padding: const EdgeInsets.only(right: 8), alignment: Alignment.centerRight, child: Text(p.stock.toString(), style: TextStyle(fontSize: 11.5, color: stockColor, fontWeight: FontWeight.bold))))
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
        child: const Text("No History Found", style: TextStyle(color: Color(0xFF1E293B), fontSize: 12, fontWeight: FontWeight.bold))
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
            height: 22,
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
            child: Row(children: [
              Expanded(flex: 2, child: Padding(padding: const EdgeInsets.only(left: 4), child: Text(dateStr, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)))),
              Expanded(flex: 1, child: Text(h['entry_no'].toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
              Expanded(flex: 1, child: Container(alignment: Alignment.centerRight, child: Text(h['qty'].toString(), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)))),
              Expanded(flex: 2, child: Container(alignment: Alignment.centerRight, child: Text(double.tryParse(h['mrp'].toString())?.toStringAsFixed(2) ?? "0.00", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)))),
              Expanded(flex: 2, child: Container(alignment: Alignment.centerRight, child: Text(double.tryParse(h['s_rate'].toString())?.toStringAsFixed(2) ?? "0.00", style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.blue)))),
              Expanded(flex: 1, child: Container(padding: const EdgeInsets.only(right: 4), alignment: Alignment.centerRight, child: Text(double.tryParse(h['disc_percent'].toString())?.toStringAsFixed(1) ?? "0.0", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red)))),
            ]),
          );
        },
      ),
    );
  }

  Widget _footerTitle(String title, {Color color = Colors.blue}) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(title, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.bold)));
  Widget _footerTableHdr(List<Map<String, dynamic>> cols) => Container(height: 20, color: const Color(0xFF424242), child: Row(children: cols.map((c) => Expanded(flex: c['flex'] ?? 1, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4), alignment: c['align'] ?? Alignment.centerLeft, child: Text(c['title'], style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold))))).toList()));

  Widget _buildRecentInvoicesList() {
    final p = Provider.of<PharmacyProvider>(context);
    final Set<String> seenNos = {};
    final sales = p.sales.where((s) => !s.isDeleted && seenNos.add(cleanEntryNo(s.entryNo))).take(15).toList();

    if (sales.isEmpty) {
      return Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), color: Colors.white),
        alignment: Alignment.center,
        child: const Text("No Recent Entries", style: TextStyle(color: Color(0xFF1E293B), fontSize: 12, fontWeight: FontWeight.bold))
      );
    }

    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), color: Colors.white),
      child: ListView.builder(
        itemCount: sales.length,
        itemBuilder: (ctx, i) {
          final inv = sales[i];
          final displayNo = formatSaleDisplayNo(inv.entryNo);
          return InkWell(
            onTap: () async {
              if (_isExistingEntry && _isDirty) {
                bool? discard = await _promptDiscardChanges();
                if (discard != true) return;
              }
              _loadSaleData(inv.entryNo);
            },
            child: Container(
              height: 22,
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
              child: Row(children: [
                Expanded(flex: 2, child: Padding(padding: const EdgeInsets.only(left: 4), child: Text(displayNo, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)))),
                Expanded(flex: 2, child: Container(padding: const EdgeInsets.only(right: 4), alignment: Alignment.centerRight, child: Text(inv.grandTotal.toStringAsFixed(2), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.blue.shade800)))),
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
                        _isRcvdAmtConfirmed = false;
                        _markDirty();
                        _calculateFooter();
                      },
                      onSubmitted: readOnly ? null : (_) {
                        _calculateFooter();
                        if (!_isRcvdAmtConfirmed) {
                          setState(() {
                            _isRcvdAmtConfirmed = true;
                          });
                        } else {
                          _promptSave();
                        }
                      },
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
                      decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2)),
                    ),
                  ),
                ),
                ValueListenableBuilder<double>(
                  valueListenable: _balanceNotifier,
                  builder: (context, diff, _) {
                    bool isReturn = diff > 0.005;
                    bool isDue = diff < -0.005;

                    String label = isReturn
                        ? "Change Return"
                        : (isDue ? "Balance Due" : "Balance");
                    Color labelColor = isReturn
                        ? Colors.green.shade800
                        : (isDue ? Colors.red.shade800 : Colors.black);
                    Color valueColor = isReturn
                        ? Colors.green.shade800
                        : (isDue ? Colors.redAccent : Colors.black);
                    Color bgColor = isReturn
                        ? Colors.green.shade50
                        : (isDue ? Colors.red.shade50 : Colors.grey.shade200);
                    Color borderColor = isReturn
                        ? Colors.green.shade400
                        : (isDue ? Colors.red.shade300 : Colors.grey.shade400);

                    return Row(
                      children: [
                        const SizedBox(width: 4),
                        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: labelColor)),
                        const SizedBox(width: 4),
                        Container(
                          width: 65,
                          height: 22,
                          decoration: BoxDecoration(
                            color: bgColor,
                            border: Border.all(color: borderColor),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: TextField(
                            controller: _balanceCtrl,
                            readOnly: true,
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: valueColor),
                            decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2)),
                          ),
                        ),
                      ],
                    );
                  },
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

  Widget _buildShortcutLegend() => Container(height: 32, padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: Colors.grey.shade900, border: const Border(top: BorderSide(color: Colors.amber, width: 2))), child: ListView(scrollDirection: Axis.horizontal, children: [_shortcutTag("F1", "New"), _shortcutTag("F2", "Generics"), _shortcutTag("F3", "Wholesale"), _shortcutTag("C+1", "Pur Hist"), _shortcutTag("C+2", "Sal Hist"), _shortcutTag("C+L", "Stock Hist"), _shortcutTag("F6", "Save"), _shortcutTag("F7", "Cust"), _shortcutTag("F8", "Pay"), _shortcutTag("F9", "Preview"), _shortcutTag("F10", "Invoice"), _shortcutTag("F11", "Hold"), _shortcutTag("F12", "Print"), _shortcutTag("Enter/Tab", "Next"), _shortcutTag("S+Enter", "Prev"), _shortcutTag("Arrows", "Nav"), _shortcutTag("Home/End", "Jump"), _shortcutTag("PgUp/Dn", "Scroll"), _shortcutTag("Del", "Clear"), _shortcutTag("C+Del", "Del Row"), _shortcutTag("Esc", "Close")]));
  Widget _shortcutTag(String key, String label) => Padding(padding: const EdgeInsets.only(right: 15), child: Row(children: [Text(key, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 10)), const SizedBox(width: 4), Text(label, style: const TextStyle(color: Colors.white, fontSize: 10))]));

  String _getActiveProductName() {
    final p = Provider.of<PharmacyProvider>(context, listen: false);

    if (_searchList.value.isNotEmpty) {
      final safeIdx = _searchIdx.value.clamp(0, _searchList.value.length - 1);
      return _searchList.value[safeIdx].name;
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

  void _openWholesaleAvailability() {
    String pName = _getActiveProductName();
    String pPatent = "";
    String pCategory = "";
    String pId = "";

    int row = _focusedRowIndex;
    if (row >= 0 && row < _items.length) {
      final p = _items[row].product;
      pId = p.id;
      if (pName.trim().isEmpty) pName = p.name;
      pPatent = p.patent;
      pCategory = p.category;
    }

    if (pName.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please type or select a medicine name first to check Wholesale Availability."),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    WholesaleAvailabilityDialog.show(
      context,
      productName: pName,
      company: pPatent,
      category: pCategory,
      productId: pId,
    );
  }




  // =========================================================================
  // FIND DIALOG
  // =========================================================================
  void _showFindDialog() {
    final TextEditingController patientCtrl = TextEditingController();
    final TextEditingController doctorCtrl = TextEditingController();
    final TextEditingController entryNoCtrl = TextEditingController();
    final TextEditingController mobileCtrl = TextEditingController();
    final TextEditingController billValueCtrl = TextEditingController();

    // Persistent focus nodes to prevent element tree corruption
    final FocusNode patientSearchFocus = FocusNode();
    final FocusNode doctorSearchFocus = FocusNode();

    final ValueNotifier<List<Map<String, dynamic>>> searchResults = ValueNotifier([]);
    final ValueNotifier<bool> isSearching = ValueNotifier(false);
    final SearchDebouncer findDebouncer = SearchDebouncer(milliseconds: 180);
    int querySeq = 0;

    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    void runQuery({bool immediate = false}) {
      Future<void> execute() async {
        final seq = ++querySeq;
        isSearching.value = true;
        try {
          final results = await provider.searchSalesInvoices(
            patient: patientCtrl.text,
            doctor: doctorCtrl.text,
            mobile: mobileCtrl.text,
            billValue: billValueCtrl.text,
          );
          if (!mounted || seq != querySeq) return;
          searchResults.value = results;
        } finally {
          if (mounted && seq == querySeq) {
            isSearching.value = false;
          }
        }
      }

      if (immediate) {
        findDebouncer.cancel();
        execute();
      } else {
        findDebouncer.run(execute);
      }
    }

    // Instantly preload 25 recent sales entries on open
    runQuery(immediate: true);

    setState(() => _isDialogOpen = true);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (dialogContext.mounted && Navigator.of(dialogContext).canPop()) {
                      Navigator.pop(dialogContext);
                    }
                  });
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: const Row(
                    children: [
                      Icon(Icons.search, color: Colors.blue, size: 24),
                      SizedBox(width: 8),
                      Text("Search Sales Entry", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  content: SizedBox(
                width: 650,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildFindAutocompleteRow(
                        "Patient",
                        patientCtrl,
                        patientSearchFocus,
                        Icons.person,
                        provider.patientMaster.map((p) => p.name).toList(),
                        onChanged: (_) => runQuery(),
                        onSearch: () => runQuery(),
                      ),
                      const SizedBox(height: 8),
                      _buildFindAutocompleteRow(
                        "Doctor",
                        doctorCtrl,
                        doctorSearchFocus,
                        Icons.medical_services,
                        provider.doctorMaster.map((d) => d.name).toList(),
                        onChanged: (_) => runQuery(),
                        onSearch: () => runQuery(),
                      ),
                      const SizedBox(height: 8),
                      _buildFindRow(
                        "Entry No:",
                        entryNoCtrl,
                        Icons.receipt_long,
                        (val) {
                          if (val.trim().isNotEmpty) {
                            // ---> FIX: Safely pop on the next frame <---
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext, val.trim());
                              }
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildFindRow(
                        "Mobile",
                        mobileCtrl,
                        Icons.phone_android,
                        (val) => runQuery(),
                        onChanged: (_) => runQuery(),
                      ),
                      const SizedBox(height: 8),
                      _buildFindRow(
                        "Bill Value",
                        billValueCtrl,
                        Icons.payments,
                        (val) => runQuery(),
                        onChanged: (_) => runQuery(),
                      ),
                      const SizedBox(height: 14),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Matching Sales History",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.blue.shade800, width: 1.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          children: [
                            Container(
                              height: 30,
                              color: Colors.blue.shade900,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: const Row(
                                children: [
                                  SizedBox(width: 75, child: Text("Entry No", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                                  SizedBox(width: 85, child: Text("Date", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                                  Expanded(flex: 2, child: Text("Patient", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                                  Expanded(flex: 2, child: Text("Doctor", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                                  SizedBox(width: 95, child: Text("Mobile", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                                  SizedBox(width: 85, child: Text("Total", textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ValueListenableBuilder<bool>(
                                valueListenable: isSearching,
                                builder: (ctx, loading, _) {
                                  if (loading) {
                                    return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                                  }
                                  return ValueListenableBuilder<List<Map<String, dynamic>>>(
                                    valueListenable: searchResults,
                                    builder: (ctx, list, _) {
                                      if (list.isEmpty) {
                                        return Container(color: Colors.white);
                                      }
                                      return ListView.builder(
                                        padding: EdgeInsets.zero,
                                        itemCount: list.length,
                                        itemBuilder: (ctx, i) {
                                          final row = list[i];
                                          final String entryNo = row['entry_no']?.toString() ?? '';
                                          String dtStr = "";
                                          try {
                                            final dt = DateTime.tryParse(row['date']?.toString() ?? '');
                                            if (dt != null) dtStr = DateFormat('dd/MM/yyyy').format(dt);
                                          } catch (_) {}

                                          final String patStr = row['patient']?.toString() ?? '';
                                          final String docStr = row['doctor']?.toString() ?? '';
                                          final String mobStr = row['mobile']?.toString() ?? '';
                                          final double totalVal = (row['grand_total'] as num?)?.toDouble() ?? 0.0;

                                          return InkWell(
                                            onTap: () {
                                              // ---> FIX: Safely pop on the next frame <---
                                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                                if (dialogContext.mounted) {
                                                  Navigator.pop(dialogContext, entryNo);
                                                }
                                              });
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: i % 2 == 0 ? Colors.white : Colors.blue.shade50.withValues(alpha: 0.4),
                                                border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.5)),
                                              ),
                                              child: Row(
                                                children: [
                                                  SizedBox(width: 75, child: Text(entryNo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue))),
                                                  SizedBox(width: 85, child: Text(dtStr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                                                  Expanded(flex: 2, child: Text(patStr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                                                  Expanded(flex: 2, child: Text(docStr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                                                  SizedBox(width: 95, child: Text(mobStr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                                                  SizedBox(width: 85, child: Text("₹${totalVal.toStringAsFixed(2)}", textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (dialogContext.mounted && Navigator.of(dialogContext).canPop()) {
                        Navigator.pop(dialogContext);
                      }
                    });
                  },
                  child: const Text("CANCEL", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        },
      );
    }).then((val) async {
      findDebouncer.dispose();
      if (mounted) setState(() => _isDialogOpen = false);
      if (val != null && val is String) {
        if (_isExistingEntry && _isDirty) {
          bool? discard = await _promptDiscardChanges();
          if (!mounted) return;
          if (discard != true) return;
        }
        if (mounted) {
          _loadSaleData(val);
        }
      }
      patientCtrl.dispose();
      doctorCtrl.dispose();
      entryNoCtrl.dispose();
      mobileCtrl.dispose();
      billValueCtrl.dispose();
      patientSearchFocus.dispose();
      doctorSearchFocus.dispose();
      searchResults.dispose();
      isSearching.dispose();
    });
  }

  Widget _buildFindAutocompleteRow(
    String label,
    TextEditingController ctrl,
    FocusNode focusNode,
    IconData icon,
    List<String> options, {
    void Function(String)? onChanged,
    VoidCallback? onSearch,
  }) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        const SizedBox(width: 8),
        Expanded(
          child: RawAutocomplete<String>(
            textEditingController: ctrl,
            focusNode: focusNode,
            optionsBuilder: (TextEditingValue textEditingValue) {
              final query = textEditingValue.text.trim().toLowerCase();
              if (query.isEmpty) return const Iterable<String>.empty();
              return options.where((opt) => opt.toLowerCase().contains(query)).take(8);
            },
            onSelected: (String selection) {
              ctrl.text = selection;
              focusNode.unfocus();
              if (onChanged != null) onChanged(selection);
            },
            fieldViewBuilder: (context, controller, fn, onEditingComplete) {
              return TextField(
                controller: controller,
                focusNode: fn,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                onChanged: onChanged,
                onSubmitted: (_) {
                  onEditingComplete();
                  if (onSearch != null) onSearch();
                },
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    width: 320,
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (BuildContext context, int index) {
                        final String option = options.elementAt(index);
                        return InkWell(
                          onTap: () => onSelected(option),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Text(option, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: onSearch,
          icon: Icon(icon, size: 16),
          label: const Text("Search"),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3F51B5),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildFindRow(String label, TextEditingController ctrl, IconData icon, void Function(String) onSearch, {void Function(String)? onChanged}) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: ctrl,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            onChanged: onChanged,
            onSubmitted: (val) {
              onSearch(val);
            },
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: () {
            onSearch(ctrl.text);
          },
          icon: Icon(icon, size: 16),
          label: const Text("Search"),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3F51B5), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
        ),
      ],
    );
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
                                dataRowMinHeight: 34,
                                dataRowMaxHeight: 34,
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
  // F1 SHORTCUTS CHEAT-SHEET OVERLAY DIALOG
  // =========================================================================
  void _showShortcutsDialog() {
    _isDialogOpen = true;
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            width: 560,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2638) : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.keyboard_outlined, size: 28, color: Colors.blueAccent),
                    const SizedBox(width: 10),
                    const Text("POS Hotkeys & Shortcuts Cheat-Sheet", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(ctx).pop()),
                  ],
                ),
                const Divider(height: 16),
                SizedBox(
                  height: 380,
                  child: ListView(
                    children: const [
                      _ShortcutRowWidget("F1", "Show Hotkeys Cheat-Sheet"),
                      _ShortcutRowWidget("Shift + F1 / Ctrl + N", "New Invoice / Reset Form"),
                      _ShortcutRowWidget("F2", "Focus Patient / Customer Name"),
                      _ShortcutRowWidget("F3", "Wholesale Stock Directory"),
                      _ShortcutRowWidget("F4", "Jump to Product Item Grid"),
                      _ShortcutRowWidget("F5", "Substitute Generic Salt Finder"),
                      _ShortcutRowWidget("F6", "Dynamic UPI Payment QR Checkout"),
                      _ShortcutRowWidget("F7", "Fast Save & Thermal Invoice Print"),
                      _ShortcutRowWidget("F8", "Focus Cash Received Amount"),
                      _ShortcutRowWidget("F9", "Invoice PDF Preview & Export"),
                      _ShortcutRowWidget("F10", "Save Invoice / Edit Record"),
                      _ShortcutRowWidget("F11", "Hold Billing Session & Switch Workspace"),
                      _ShortcutRowWidget("F12", "Express Save & Print Bill"),
                      _ShortcutRowWidget("Ctrl + 1", "Product Purchase History"),
                      _ShortcutRowWidget("Ctrl + 2", "Product Sales History"),
                      _ShortcutRowWidget("Ctrl + L", "Product Stock Movement Ledger"),
                      _ShortcutRowWidget("Ctrl + Z", "Undo Last Grid Action"),
                      _ShortcutRowWidget("Ctrl + Del", "Delete Selected Grid Row"),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text("Close (Esc)"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      _isDialogOpen = false;
    });
  }

  // =========================================================================
  // F6 DYNAMIC UPI PAYMENT QR CHECKOUT
  // =========================================================================
  Future<void> _triggerDynamicUpiQrPayment() async {
    final double amt = _netTotalNotifier.value > 0 
        ? _netTotalNotifier.value 
        : (double.tryParse(_netTotalCtrl.text) ?? 0.0);

    if (amt <= 0) {
      _showFastDialog(
        title: "Invalid Amount",
        content: "Cannot generate UPI QR code for a bill with zero total.",
      );
      return;
    }

    final company = CompanyProfile();
    final upiVpa = company.upiVpaId.isNotEmpty ? company.upiVpaId : "sahakarmedicals@upi";
    final payeeName = company.upiPayeeName.isNotEmpty ? company.upiPayeeName : company.name;
    final invNo = _entryNo.isNotEmpty ? _entryNo : "NEW";

    final bool? paid = await DynamicUpiQrDialog.show(
      context,
      billAmount: amt,
      invoiceNo: invNo,
      upiVpa: upiVpa,
      payeeName: payeeName,
    );

    if (paid == true) {
      setState(() {
        _customerAcc = "UPI";
        _customerAccCtrl.text = "UPI";
        _rcvdAmtCtrl.text = amt.toStringAsFixed(2);
      });
      _saveAndPrintBill();
    }
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
                  child: Text("-", textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.black)),
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
                        style: const TextStyle(color: Colors.black),
                      ),
                      const TextSpan(
                        text: "/ ",
                        style: TextStyle(color: Colors.black),
                      ),
                      TextSpan(
                        text: "$looseUnits",
                        style: TextStyle(
                          color: looseUnits > 0 ? Colors.red.shade700 : Colors.black,
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
                                  "F2: Generic & Content-Wise Product Search",
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
                              const Text("Category: ", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black)),
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
                                          color: isSel ? Colors.white : Colors.black,
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
                                                  color: Colors.black,
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
                                                  color: Colors.black,
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
                                                  color: isGenCategory ? Colors.green.shade700 : Colors.black,
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
                                                style: const TextStyle(fontSize: 10, color: Colors.black),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                p.batch.isNotEmpty ? _cleanBatch(p.batch) : "-",
                                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 1,
                                              child: Text(
                                                p.expiry.isNotEmpty ? p.expiry : "-",
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: nearExp ? FontWeight.bold : FontWeight.normal,
                                                  color: nearExp ? Colors.red.shade700 : Colors.black,
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
                                                  color: Colors.black,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 1,
                                              child: Text(
                                                p.mrp > 0 ? p.mrp.toStringAsFixed(2) : "-",
                                                textAlign: TextAlign.right,
                                                style: const TextStyle(fontSize: 10, color: Colors.black),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 1,
                                              child: Text(
                                                p.salePrice > 0 ? p.salePrice.toStringAsFixed(2) : (p.mrp > 0 ? p.mrp.toStringAsFixed(2) : "-"),
                                                textAlign: TextAlign.right,
                                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
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
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black),
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
  // F2 SALES HISTORY DIALOG - Spawns as true floating Windows OS window (Matching YesPlus ERP)
  // =========================================================================
  void _openHistoryWindow(String productName, bool isSales) {
    if (productName.trim().isEmpty) return;
    spawnOSWindow(isSales ? "sales_history" : "purchase_history", productName.trim());
  }

  Future<void> _showH1DrugWarningDialog(String productName, String schedule) async {
    AppSounds.playError(); // Play alert sound

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        void acknowledgeAndContinue() {
          Navigator.pop(ctx);
          // Automatically focus the Doctor field to capture prescription info if needed
          if (_doctorCtrl.text == "D1" || _doctorCtrl.text.isEmpty) {
            _doctorFocus.requestFocus();
          }
        }

        return Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                  event.logicalKey == LogicalKeyboardKey.space) {
                acknowledgeAndContinue();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: AlertDialog(
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
                    "This medicine falls under Schedule H1 regulations.\n\n• Mandatory prescription required.\n• Ensure Patient Name, Doctor Name, and Prescribed Quantity are correctly logged.",
                    style: TextStyle(fontSize: 13, color: Colors.black, height: 1.4),
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
                autofocus: true,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade800,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: acknowledgeAndContinue,
                child: const Text("ACKNOWLEDGE & CONTINUE (ENTER)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
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
  final String title; final double? width; final int? flex; final TextAlign align;
  const _Hdr(this.title, {this.width, this.flex, this.align = TextAlign.left});
  @override Widget build(BuildContext context) { 
    Widget child = Container(
      width: width,
      alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.center ? Alignment.center : Alignment.centerRight),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.white24, width: 0.5))),
      child: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    ); 
    if (title.isNotEmpty) child = ERPTooltip(message: title, child: child);
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

class _NotificationItemRow extends StatefulWidget {
  final Map<String, dynamic> item;
  final int index;
  final VoidCallback onChanged;

  const _NotificationItemRow({
    super.key,
    required this.item,
    required this.index,
    required this.onChanged,
  });

  @override
  State<_NotificationItemRow> createState() => _NotificationItemRowState();
}

class _NotificationItemRowState extends State<_NotificationItemRow> {
  late TextEditingController _orderedQtyController;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();

    int? ordQty = widget.item['ordered_qty'] != null ? (widget.item['ordered_qty'] as num).toInt() : null;
    if (ordQty == null && widget.item['ordered'] == true) {
      ordQty = (widget.item['qty'] as num?)?.toInt() ?? 1;
      widget.item['ordered_qty'] = ordQty;
    }
    String initialText = (ordQty != null && ordQty > 0) ? "$ordQty" : "";
    _orderedQtyController = TextEditingController(text: initialText);
  }

  @override
  void didUpdateWidget(covariant _NotificationItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus) {
      int? currentOrdQty = (widget.item['ordered_qty'] as num?)?.toInt();
      bool isOrdered = widget.item['ordered'] == true;
      if (isOrdered && (currentOrdQty == null || currentOrdQty <= 0)) {
        currentOrdQty = (widget.item['qty'] as num?)?.toInt() ?? 1;
        widget.item['ordered_qty'] = currentOrdQty;
      }
      String expectedText = (isOrdered && currentOrdQty != null && currentOrdQty > 0) ? "$currentOrdQty" : "";
      if (_orderedQtyController.text != expectedText) {
        _orderedQtyController.text = expectedText;
      }
    }
  }

  @override
  void dispose() {
    _orderedQtyController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleOrderStatus() {
    bool currentlyOrdered = widget.item['ordered'] == true;
    bool newOrdered = !currentlyOrdered;

    widget.item['ordered'] = newOrdered;
    widget.item['pending'] = !newOrdered;

    if (newOrdered) {
      int genQty = (widget.item['qty'] as num?)?.toInt() ?? 1;
      int existingOrd = (widget.item['ordered_qty'] as num?)?.toInt() ?? 0;
      int fillQty = existingOrd > 0 ? existingOrd : genQty;
      widget.item['ordered_qty'] = fillQty;
      _orderedQtyController.text = "$fillQty";
    } else {
      widget.item['ordered_qty'] = 0;
      _orderedQtyController.text = "";
    }

    widget.onChanged();
  }

  void _onOrderedTextChanged(String val) {
    String trimmed = val.trim();
    int? parsed = int.tryParse(trimmed);

    if (parsed != null && parsed > 0) {
      widget.item['ordered_qty'] = parsed;
      if (widget.item['ordered'] != true) {
        widget.item['ordered'] = true;
        widget.item['pending'] = false;
      }
    } else {
      widget.item['ordered_qty'] = 0;
      if (widget.item['ordered'] == true) {
        widget.item['ordered'] = false;
        widget.item['pending'] = true;
      }
    }

    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final int i = widget.index;
    final int stockQty = (item['stock'] as num?)?.toInt() ?? 0;
    final double pRate = (item['p_rate'] as num?)?.toDouble() ?? 0.0;
    final bool isOrdered = item['ordered'] == true;

    return InkWell(
      onTap: _toggleOrderStatus,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isOrdered ? Colors.blue.shade50.withValues(alpha: 0.4) : Colors.white,
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            // 1. SL NO
            Container(
              width: 40,
              alignment: Alignment.center,
              child: Text(
                "${i + 1}",
                style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
              ),
            ),
            // 2. ITEM NAME
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item['name'] ?? '',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isOrdered ? Colors.grey.shade700 : Colors.black,
                        decoration: isOrdered ? TextDecoration.lineThrough : TextDecoration.none,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Stock Qty: $stockQty",
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: stockQty <= 0 ? Colors.red.shade700 : Colors.blueGrey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 3. GENERATED ORDER QTY
            Container(
              width: 80,
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Text(
                  "${item['qty']}",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                ),
              ),
            ),
            // 4. ORDERED QTY (EDITABLE BOX)
            Container(
              width: 70,
              alignment: Alignment.center,
              child: GestureDetector(
                onTap: () {}, // Prevent row onTap from firing when tapping inside input box
                child: Container(
                  height: 26,
                  width: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isOrdered ? Colors.blue.shade50 : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isOrdered ? Colors.blue.shade400 : Colors.grey.shade300,
                      width: isOrdered ? 1.2 : 1.0,
                    ),
                  ),
                  child: TextField(
                    controller: _orderedQtyController,
                    focusNode: _focusNode,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isOrdered ? Colors.blue.shade900 : Colors.black,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      border: InputBorder.none,
                      hintText: "0",
                      hintStyle: TextStyle(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.normal),
                    ),
                    onChanged: _onOrderedTextChanged,
                  ),
                ),
              ),
            ),
            // 5. ORDER STATUS (Tick / No Tick Checkbox)
            SizedBox(
              width: 70,
              child: Center(
                child: Checkbox(
                  value: isOrdered,
                  onChanged: (_) => _toggleOrderStatus(),
                  activeColor: Colors.blue.shade700,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            // 6. P.RATE (Old Purchase Rate)
            Container(
              width: 70,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                "₹${pRate.toStringAsFixed(2)}",
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutRowWidget extends StatelessWidget {
  final String keyName;
  final String description;
  const _ShortcutRowWidget(this.keyName, this.description);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
            ),
            child: Text(
              keyName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.blueAccent),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(description, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
