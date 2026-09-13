import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import '../providers/pharmacy_provider.dart';
import '../providers/mdi_controller.dart';
import '../utils/app_dialogs.dart';
import '../widgets/pin_unlock_dialog.dart';
import '../widgets/import_widgets.dart';
import '../widgets/dynamic_excel_mapping_dialog.dart';
import '../widgets/pdf_visual_mapper_dialog.dart';
import '../utils/invoice_pdf_generator.dart';
import '../utils/printer_service.dart';
import '../utils/tax_calculator.dart';
import '../widgets/erp_tooltip.dart';

import '../utils/app_formatters.dart';
import '../utils/theme_constants.dart';
import '../utils/search_debouncer.dart';
import '../widgets/purchase/purchase_header.dart';
import '../widgets/purchase/purchase_footer.dart';
import '../windows/window_spawner.dart';
import 'reports/sales_history_screen.dart';
import 'reports/purchase_history_screen.dart';
import 'master/product_registration_screen.dart';

class VisualWord {
  final String text;
  final Rect bounds;
  VisualWord({required this.text, required this.bounds});
}

class DiscountColorInfo {
  final Color bgColor;
  final Color textColor;
  const DiscountColorInfo({required this.bgColor, required this.textColor});
}

class ExpiryStyle {
  final Color bgColor;
  final Color textColor;
  const ExpiryStyle(this.bgColor, this.textColor);
}

DiscountColorInfo _getDiscountColorInfo(double discVal) {
  if (discVal <= 1.0) {
    return const DiscountColorInfo(
      bgColor: Color(0xFFE53935), // Red
      textColor: Colors.white,
    );
  } else if (discVal <= 3.0) {
    return const DiscountColorInfo(
      bgColor: Color(0xFFFB8C00), // Orange
      textColor: Colors.black,
    );
  } else if (discVal <= 4.0) {
    return const DiscountColorInfo(
      bgColor: Color(0xFFFFD54F), // Yellow
      textColor: Colors.black,
    );
  } else if (discVal <= 5.0) {
    return const DiscountColorInfo(
      bgColor: Color(0xFF81C784), // Light Green
      textColor: Colors.black,
    );
  } else {
    return const DiscountColorInfo(
      bgColor: Color(0xFF2E7D32), // Dark Green
      textColor: Colors.white,
    );
  }
}

class PurchaseItemData {
  static int _idCounter = 0;
  final String uuid;
  String productId = "";
  String productName = "";
  String lastPulledName = "";
  String batch = "";
  String rack = "";
  String hsncode = "";
  String expiry = "--/--";
  int packin = 1;
  int qty = 0;
  int fQty = 0;

  // NEW TRACKING VARIABLES
  bool isConsumed = false;
  int consumedLooseUnits = 0;
  int minStripsRequired = 0;

  double mrp = 0.0;
  double pRate = 0.0;
  double? masterMrp; // Last stored MRP in Product Master
  double? masterPRate; // Last stored Purchase Rate in Product Master
  double gross = 0.0;
  double discPercent = 0.0;
  double discAmt = 0.0;
  double net = 0.0;
  double gstPercent = 0.0;
  double? masterGstPercent; // Stores default GST rate from Product Master
  bool updateMasterGst = false; // Option B: Toggle to update Product Master GST
  double gstAmt = 0.0;
  double cgstAmt = 0.0;
  double sgstAmt = 0.0;
  double total = 0.0;
  double sDiscPercent = 0.0;
  double sDiscAmt = 0.0;
  double sRate = 0.0;
  double lCost = 0.0;

  double get effectivePRate {
    int totalUnits = qty + fQty;
    if (totalUnits <= 0) return pRate;
    return (pRate * qty) / totalUnits;
  }

  double get profitPctNoDisc {
    if (mrp <= 0) return 0.0;
    double effRate = effectivePRate;
    return ((mrp - effRate) / mrp) * 100.0;
  }

  bool get isLowMargin {
    if (mrp <= 0) return false;
    return profitPctNoDisc < 24.9;
  }

  bool get isNegativeMargin {
    if (mrp <= 0 || pRate <= 0) return false;
    return effectivePRate >= mrp;
  }

  bool get hasMrpChanged {
    if (masterMrp == null || masterMrp! <= 0 || mrp <= 0) return false;
    return (mrp - masterMrp!).abs() > 0.01;
  }

  bool get isMrpIncreased => masterMrp != null && mrp > masterMrp! + 0.01;
  bool get isMrpDecreased => masterMrp != null && mrp < masterMrp! - 0.01;

  bool get hasPRateChanged {
    if (masterPRate == null || masterPRate! <= 0 || pRate <= 0) return false;
    return (pRate - masterPRate!).abs() > 0.01;
  }

  bool get isPRateIncreased => masterPRate != null && pRate > masterPRate! + 0.01;
  bool get isPRateDecreased => masterPRate != null && pRate < masterPRate! - 0.01;

  bool get hasGstMismatch {
    if (masterGstPercent == null || productId.isEmpty) return false;
    return (gstPercent - masterGstPercent!).abs() > 0.01;
  }

  final Map<int, TextEditingController> controllers = {};
  final Map<int, FocusNode> focusNodes = {};

  final ValueNotifier<int> notifier = ValueNotifier(0);
  void notify() => notifier.value++;

  PurchaseItemData({String? uuid}) : uuid = uuid ?? "item_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}";

  void dispose() {
    for (var c in controllers.values) {
      c.dispose();
    }
    for (var f in focusNodes.values) {
      f.dispose();
    }
    notifier.dispose();
  }

  PurchaseItemData clone() {
    return PurchaseItemData(uuid: uuid)
      ..productId = productId
      ..productName = productName
      ..lastPulledName = lastPulledName
      ..batch = batch
      ..rack = rack
      ..hsncode = hsncode
      ..expiry = expiry
      ..packin = packin
      ..qty = qty
      ..fQty = fQty
      ..mrp = mrp
      ..pRate = pRate
      ..gross = gross
      ..discPercent = discPercent
      ..discAmt = discAmt
      ..net = net
      ..gstPercent = gstPercent
      ..gstAmt = gstAmt
      ..cgstAmt = cgstAmt
      ..sgstAmt = sgstAmt
      ..total = total
      ..sDiscPercent = sDiscPercent
      ..sDiscAmt = sDiscAmt
      ..sRate = sRate
      ..lCost = lCost;
  }

  void recalculate({
    required bool isGstMode,
    bool isDiscAmtFocused = false,
    bool isGstAmtFocused = false,
    bool isSDiscAmtFocused = false,
  }) {
    gross = pRate * qty;

    // 1. Discount Sync
    if (isDiscAmtFocused) {
      if (gross > 0) {
        discPercent = double.parse(((discAmt / gross) * 100.0).toStringAsFixed(2));
      }
    } else {
      if (discPercent < 0) discPercent = 0.0;
      if (discPercent > 100) discPercent = 100.0;
      discAmt = double.parse((gross * (discPercent / 100.0)).toStringAsFixed(2));
    }

    net = gross - discAmt;
    if (net < 0) net = 0.0;

    // 2. GST Sync
    if (isGstMode) {
      if (isGstAmtFocused) {
        if (net > 0) {
          gstPercent = TaxCalculator.roundGstPercent(double.parse(((gstAmt / net) * 100.0).toStringAsFixed(2)));
        }
      } else {
        gstPercent = TaxCalculator.roundGstPercent(gstPercent);
        gstAmt = double.parse((net * (gstPercent / 100.0)).toStringAsFixed(2));
      }
      cgstAmt = gstAmt / 2.0;
      sgstAmt = gstAmt / 2.0;
      total = net + gstAmt;
    } else {
      gstPercent = 0.0;
      gstAmt = 0.0;
      cgstAmt = 0.0;
      sgstAmt = 0.0;
      total = double.parse(net.toStringAsFixed(2));
    }

    // 3. Scheme Discount Sync (calculated from Net)
    if (isSDiscAmtFocused) {
      if (net > 0) {
        sDiscPercent = double.parse(((sDiscAmt / net) * 100.0).toStringAsFixed(2));
      }
    } else {
      if (sDiscPercent < 0) sDiscPercent = 0.0;
      if (sDiscPercent > 100) sDiscPercent = 100.0;
      sDiscAmt = double.parse((net * (sDiscPercent / 100.0)).toStringAsFixed(2));
    }

    if (packin <= 0) packin = 1;

    // 4. Landing Cost calculation (Protected against division by zero)
    double strips = (qty + fQty).toDouble();
    if (strips > 0) {
      lCost = double.parse((total / strips).toStringAsFixed(2));
    } else {
      lCost = pRate;
    }

    sRate = mrp;
  }

  String getColValue(int col) {
    switch (col) {
      case 1: return productName;
      case 2: return batch;
      case 3: return rack;
      case 4: return hsncode;
      case 5: return expiry;
      case 6: return packin > 0 ? packin.toString() : "1";
      case 7: return qty > 0 ? qty.toString() : "";
      case 8: return fQty > 0 ? fQty.toString() : "0";
      case 9: return mrp > 0 ? mrp.toStringAsFixed(2) : "";
      case 10: return pRate > 0 ? pRate.toStringAsFixed(2) : "";
      case 12: return discPercent > 0 ? (discPercent % 1 == 0 ? discPercent.toInt().toString() : discPercent.toStringAsFixed(1)) : "";
      case 13: return discAmt > 0 ? discAmt.toStringAsFixed(2) : "";
      case 15: {
        double g = TaxCalculator.roundGstPercent(gstPercent);
        return g > 0 ? (g % 1 == 0 ? g.toInt().toString() : g.toStringAsFixed(1)) : "12";
      }
      case 18: return (sDiscPercent % 1 == 0 ? sDiscPercent.toInt().toString() : sDiscPercent.toStringAsFixed(1));
      case 19: return sDiscAmt.toStringAsFixed(2);
      default: return "";
    }
  }

  void syncControllers() {
    for (int col in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 15, 18, 19]) {
      String val = getColValue(col);
      if (controllers.containsKey(col)) {
        controllers[col]!.text = val;
      } else {
        controllers[col] = TextEditingController(text: val);
      }
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'productId': productId,
      'productName': productName,
      'lastPulledName': lastPulledName,
      'batch': batch,
      'rack': rack,
      'hsncode': hsncode,
      'expiry': expiry,
      'packin': packin,
      'qty': qty,
      'fQty': fQty,
      'isConsumed': isConsumed,
      'consumedLooseUnits': consumedLooseUnits,
      'minStripsRequired': minStripsRequired,
      'mrp': mrp,
      'pRate': pRate,
      'gross': gross,
      'discPercent': discPercent,
      'discAmt': discAmt,
      'net': net,
      'gstPercent': gstPercent,
      'gstAmt': gstAmt,
      'cgstAmt': cgstAmt,
      'sgstAmt': sgstAmt,
      'total': total,
      'sDiscPercent': sDiscPercent,
      'sDiscAmt': sDiscAmt,
      'sRate': sRate,
      'lCost': lCost,
    };
  }

  factory PurchaseItemData.fromJson(Map<String, dynamic> json) {
    final item = PurchaseItemData(uuid: json['uuid'] as String?);
    item.productId = json['productId']?.toString() ?? "";
    item.productName = json['productName']?.toString() ?? "";
    item.lastPulledName = json['lastPulledName']?.toString() ?? "";
    item.batch = json['batch']?.toString() ?? "";
    item.rack = json['rack']?.toString() ?? "";
    item.hsncode = json['hsncode']?.toString() ?? "";
    item.expiry = json['expiry']?.toString() ?? "--/--";
    item.packin = (json['packin'] as num?)?.toInt() ?? 1;
    item.qty = (json['qty'] as num?)?.toInt() ?? 0;
    item.fQty = (json['fQty'] as num?)?.toInt() ?? 0;
    item.isConsumed = json['isConsumed'] as bool? ?? false;
    item.consumedLooseUnits = (json['consumedLooseUnits'] as num?)?.toInt() ?? 0;
    item.minStripsRequired = (json['minStripsRequired'] as num?)?.toInt() ?? 0;
    item.mrp = (json['mrp'] as num?)?.toDouble() ?? 0.0;
    item.pRate = (json['pRate'] as num?)?.toDouble() ?? 0.0;
    item.gross = (json['gross'] as num?)?.toDouble() ?? 0.0;
    item.discPercent = (json['discPercent'] as num?)?.toDouble() ?? 0.0;
    item.discAmt = (json['discAmt'] as num?)?.toDouble() ?? 0.0;
    item.net = (json['net'] as num?)?.toDouble() ?? 0.0;
    item.gstPercent = (json['gstPercent'] as num?)?.toDouble() ?? 0.0;
    item.gstAmt = (json['gstAmt'] as num?)?.toDouble() ?? 0.0;
    item.cgstAmt = (json['cgstAmt'] as num?)?.toDouble() ?? 0.0;
    item.sgstAmt = (json['sgstAmt'] as num?)?.toDouble() ?? 0.0;
    item.total = (json['total'] as num?)?.toDouble() ?? 0.0;
    item.sDiscPercent = (json['sDiscPercent'] as num?)?.toDouble() ?? 0.0;
    item.sDiscAmt = (json['sDiscAmt'] as num?)?.toDouble() ?? 0.0;
    item.sRate = (json['sRate'] as num?)?.toDouble() ?? 0.0;
    item.lCost = (json['lCost'] as num?)?.toDouble() ?? 0.0;
    return item;
  }
}

class LocalPurchaseScreen extends StatefulWidget {
  final String? initialInvoiceNo;
  final bool isDialog;
  const LocalPurchaseScreen({super.key, this.initialInvoiceNo, this.isDialog = false});

  @override
  State<LocalPurchaseScreen> createState() => _LocalPurchaseScreenState();
}

class _LocalPurchaseScreenState extends State<LocalPurchaseScreen> {
  final List<PurchaseItemData> _items = [];
  final List<List<PurchaseItemData>> _undoStack = [];

  void _saveUndoState() {
    if (!mounted) return;
    _undoStack.add(_items.map((it) => it.clone()).toList());
    if (_undoStack.length > 5) _undoStack.removeAt(0);
  }

  void _performUndo() {
    if (_undoStack.isEmpty) return;
    List<PurchaseItemData> lastState = _undoStack.removeLast();
    setState(() {
      for (var it in _items) {
        it.dispose();
      }
      _items.clear();
      _errorCells.clear();
      _items.addAll(lastState);
      for (int i = 0; i < _items.length; i++) {
        _calculateItem(i);
      }
    });
  }

  String? _activeFormatName;
  DateTime _date = DateTime.now();
  DateTime _supInvDate = DateTime.now();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 30));
  bool _isExistingEntry = false;
  bool _isDeleted = false;
  bool _isDirty = false;
  bool _isAutoGeneratedSupInv = false;
  final Map<PurchaseItemData, Map<int, TextEditingController>> _gridCtrls = {};
  final Map<PurchaseItemData, Map<int, FocusNode>> _gridFocusNodes = {};
  PurchaseEntry? _originalLoadedEntry; // NEW: To capture pre-edit state
  bool _isLoading = false;
  bool _isSaving = false; // Multi-tap and rapid shortcut guard

  int _paymentMode = 1;
  int _gstMode = 1;

  final Map<int, Set<int>> _errorCells = {};
  final Set<String> _discountInteractedRows = {};

  final TextEditingController _entryNoCtrl = TextEditingController();
  final TextEditingController _supplierCtrl = TextEditingController();
  final TextEditingController _doneByCtrl = TextEditingController();
  final TextEditingController _supInvNoCtrl = TextEditingController();
  final TextEditingController _invTotalCtrl = TextEditingController();
  final TextEditingController _remarksCtrl = TextEditingController();
  final TextEditingController _poNoCtrl = TextEditingController();

  final FocusNode _supplierFocus = FocusNode();
  final FocusNode _doneByFocus = FocusNode();
  final FocusNode _supInvNoFocus = FocusNode();
  final FocusNode _invTotalFocus = FocusNode();
  final FocusNode _remarksFocus = FocusNode();
  final FocusNode _poNoFocus = FocusNode();

  final FocusNode _footerDiscPctFocus = FocusNode();
  final FocusNode _footerDiscAmtFocus = FocusNode();
  final FocusNode _otherChargePctFocus = FocusNode();
  final FocusNode _otherChargeAmtFocus = FocusNode();

  final TextEditingController _subTotalCtrl = TextEditingController(text: "0.00");
  final TextEditingController _footerDiscPctCtrl = TextEditingController(text: "0");
  final TextEditingController _footerDiscAmtCtrl = TextEditingController(text: "0.00");
  final TextEditingController _otherChargePctCtrl = TextEditingController(text: "0");
  final TextEditingController _otherChargeAmtCtrl = TextEditingController(text: "0.00");
  final TextEditingController _lessCrNoteCtrl = TextEditingController(text: "0.00");
  final TextEditingController _roundOffCtrl = TextEditingController(text: "0.00");
  final TextEditingController _grandTotalCtrl = TextEditingController(text: "0.00");

  final ScrollController _gridScrollCtrl = ScrollController();
  final ScrollController _verticalGridScrollCtrl = ScrollController();
  final ScrollController _dropdownScrollCtrl = ScrollController();

  final Map<int, double> _colWidths = {
    0: 30, 1: 220, 2: 90, 3: 40, 4: 70, 5: 50, 6: 35, 7: 55, 8: 55, 9: 65, 10: 65,
    11: 75, 12: 38, 13: 65, 14: 75, 15: 38, 16: 54, 17: 85, 18: 42, 19: 52, 20: 75, 21: 75, 22: 48,
  };
  double _totalWidth = 0;

  final List<int> _navCols = [1, 2, 4, 5, 6, 7, 8, 9, 10, 12, 13, 15, 18, 19];

  final ValueNotifier<IntPair?> _focusNotifier = ValueNotifier(const IntPair(0, 1));
  IntPair? _lastFocus;
  final FocusNode _rootFocus = FocusNode();

  final ValueNotifier<double> _grandTotalNotifier = ValueNotifier(0.0);
  final ValueNotifier<int> _summaryNotifier = ValueNotifier(0);
  final ValueNotifier<List<Product>> _searchList = ValueNotifier([]);
  final ValueNotifier<List<Product>> _batchList = ValueNotifier([]);
  final ValueNotifier<List<String>> _supplierSearchList = ValueNotifier([]);
  final ValueNotifier<List<String>> _doneBySearchList = ValueNotifier([]);
  final ValueNotifier<int> _searchIdx = ValueNotifier(0);
  final LayerLink _searchLayer = LayerLink();
  final LayerLink _batchLayer = LayerLink();
  final LayerLink _supplierLayer = LayerLink();
  final LayerLink _doneByLayer = LayerLink();

  Timer? _scrollTimer;
  final SearchDebouncer _searchDebouncer = SearchDebouncer(milliseconds: 150);
  final SearchDebouncer _historyDebouncer = SearchDebouncer(milliseconds: 250);
  final SearchDebouncer _footerDebouncer = SearchDebouncer(milliseconds: 100);
  bool _isSelectingBatch = false;
  final bool _isDialogOpen = false;
  bool _isSelectingFromDropdown = false;
  List<Map<String, dynamic>> _productHistory = [];
  String _historyProductName = "";

  PurchaseItemData _nextItem = PurchaseItemData();

  int get _focusedRowIndex => _focusNotifier.value?.row ?? -1;
  int get _focusedColIndex => _focusNotifier.value?.col ?? 1;

  PurchaseItemData _getItemAt(int row) => (row < _items.length && row >= 0) ? _items[row] : _nextItem;


  String _lastYear = "";

  void _onProviderChange() {
    if (!mounted) return;
    final p = Provider.of<PharmacyProvider>(context, listen: false);

    bool yearChanged = p.selectedFinancialYear != _lastYear;

    if (yearChanged) {
      _lastYear = p.selectedFinancialYear;
      // If we are looking at an old entry, or just started a new one,
      // refresh the entry number when the year changes globally.
      if (!_isExistingEntry || (_originalLoadedEntry != null && _originalLoadedEntry!.financialYear != _lastYear)) {
        _resetPage();
        return;
      }
    }

    // Only query SQLite if the financial year changed, NOT on every keystroke notification
    if (!_isExistingEntry && yearChanged) {
      Future.microtask(() async {
        String next = await p.getNextPurchaseEntryNo();
        if (_entryNoCtrl.text != next && mounted) {
          setState(() {
            _entryNoCtrl.text = next;
          });
        }
      });
    }
  }

  PharmacyProvider? _pharmacyProvider;
  Timer? _draftTimer;

  @override
  void initState() {
    super.initState();
    _colWidths.forEach((k, v) => _totalWidth += v);
    _pharmacyProvider = Provider.of<PharmacyProvider>(context, listen: false);
    _lastYear = _pharmacyProvider!.selectedFinancialYear;
    _pharmacyProvider!.addListener(_onProviderChange);
    
    _isExistingEntry = widget.initialInvoiceNo != null;
    if (widget.initialInvoiceNo != null) {
      _entryNoCtrl.text = widget.initialInvoiceNo!;
    } else {
      Future.microtask(() async {
        final next = await _pharmacyProvider!.getNextPurchaseEntryNo();
        if (mounted) setState(() => _entryNoCtrl.text = next);
      });
    }

    _footerDiscPctCtrl.addListener(_calculateFooter);
    _footerDiscAmtCtrl.addListener(_calculateFooter);
    _otherChargePctCtrl.addListener(_calculateFooter);
    _otherChargeAmtCtrl.addListener(_calculateFooter);
    _lessCrNoteCtrl.addListener(_calculateFooter);
    _supInvNoCtrl.addListener(() { if (mounted) setState(() {}); });
    _supplierCtrl.addListener(() { if (mounted) setState(() {}); });

    _draftTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) _triggerAutoSaveDraft();
    });

    if (!_isExistingEntry) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkAndPromptDraftRecovery();
      });
    }

    // SYNC HEADER FOCUS WITH NOTIFIER (For Mouse Clicks)
    _supplierFocus.addListener(() { 
      if (_supplierFocus.hasFocus) {
        _focusNotifier.value = const IntPair(-1, 0); 
      } else {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (!_isSelectingFromDropdown && mounted && !_supplierFocus.hasFocus) {
            _supplierSearchList.value = [];
          }
        });
      }
    });
    _doneByFocus.addListener(() { 
      if (_doneByFocus.hasFocus) {
        _focusNotifier.value = const IntPair(-1, 1); 
      } else {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (!_isSelectingFromDropdown && mounted && !_doneByFocus.hasFocus) {
            _doneBySearchList.value = [];
          }
        });
      }
    });
    _supInvNoFocus.addListener(() {
      if (_supInvNoFocus.hasFocus) {
        _focusNotifier.value = const IntPair(-1, 2);
        _closeAllDropdowns();
      } else {
        String cleaned = cleanInvoiceNo(_supInvNoCtrl.text);
        if (cleaned != _supInvNoCtrl.text) {
          _supInvNoCtrl.text = cleaned;
        }
      }
    });
    _invTotalFocus.addListener(() { if (_invTotalFocus.hasFocus) { _focusNotifier.value = const IntPair(-1, 3); _closeAllDropdowns(); } });
    _poNoFocus.addListener(() { if (_poNoFocus.hasFocus) { _focusNotifier.value = const IntPair(-1, 4); _closeAllDropdowns(); } });

    _focusNotifier.addListener(() {
      if (_lastFocus != null) _getItemAt(_lastFocus!.row).notify();
      if (_focusNotifier.value != null) _getItemAt(_focusNotifier.value!.row).notify();
      _lastFocus = _focusNotifier.value;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialInvoiceNo != null) {
        _loadPurchaseData(widget.initialInvoiceNo!);
      } else {
        _moveFocus(-1, 0);
      }
    });
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _closeAllDropdowns();
    _searchList.dispose();
    _batchList.dispose();
    _supplierSearchList.dispose();
    _doneBySearchList.dispose();
    _searchIdx.dispose();
    _grandTotalNotifier.dispose();
    _summaryNotifier.dispose();
    _focusNotifier.dispose();
    _pharmacyProvider?.removeListener(_onProviderChange);
    _scrollTimer?.cancel();
    _searchDebouncer.dispose();
    _historyDebouncer.dispose();
    _footerDebouncer.dispose();
    _gridScrollCtrl.dispose();
    _verticalGridScrollCtrl.dispose();
    _dropdownScrollCtrl.dispose();
    _rootFocus.dispose();
    _entryNoCtrl.dispose();
    _subTotalCtrl.dispose();
    _footerDiscPctCtrl.dispose();
    _footerDiscAmtCtrl.dispose();
    _otherChargePctCtrl.dispose();
    _otherChargeAmtCtrl.dispose();
    _lessCrNoteCtrl.dispose();
    _roundOffCtrl.dispose();
    _grandTotalCtrl.dispose();
    _supplierFocus.dispose();
    _doneByFocus.dispose();
    _supInvNoFocus.dispose();
    _invTotalFocus.dispose();
    _remarksFocus.dispose();
    _poNoFocus.dispose();
    _footerDiscPctFocus.dispose();
    _footerDiscAmtFocus.dispose();
    _otherChargePctFocus.dispose();
    _otherChargeAmtFocus.dispose();
    for (var it in _items) {
      it.dispose();
    }
    _nextItem.dispose();
    super.dispose();
  }

  bool _hasValidItems() {
    if (_isExistingEntry) return _isDirty;

    for (int i = 0; i < _items.length; i++) {
      final it = _items[i];
      final prodName = it.productName.trim().isNotEmpty
          ? it.productName.trim()
          : (it.controllers[1]?.text.trim() ?? "");
      final ctrlQty = int.tryParse(it.controllers[7]?.text.trim() ?? "") ?? 0;
      final ctrlFQty = int.tryParse(it.controllers[8]?.text.trim() ?? "") ?? 0;
      final totalQty = (it.qty > 0 ? it.qty : ctrlQty) + (it.fQty > 0 ? it.fQty : ctrlFQty);

      if (prodName.isNotEmpty && totalQty > 0) {
        return true;
      }
    }

    final nextName = _nextItem.productName.trim().isNotEmpty
        ? _nextItem.productName.trim()
        : (_nextItem.controllers[1]?.text.trim() ?? "");
    final nextCtrlQty = int.tryParse(_nextItem.controllers[7]?.text.trim() ?? "") ?? 0;
    final nextCtrlFQty = int.tryParse(_nextItem.controllers[8]?.text.trim() ?? "") ?? 0;
    final nextTotalQty = (_nextItem.qty > 0 ? _nextItem.qty : nextCtrlQty) + (_nextItem.fQty > 0 ? _nextItem.fQty : nextCtrlFQty);

    if (nextName.isNotEmpty && nextTotalQty > 0) {
      return true;
    }

    return false;
  }

  void _triggerAutoSaveDraft() async {
    if (_isExistingEntry || _pharmacyProvider == null) return;

    if (!_hasValidItems()) {
      await _pharmacyProvider!.clearPurchaseDraft();
      return;
    }

    final validItems = _items.where((it) {
      final pName = it.productName.trim().isNotEmpty ? it.productName.trim() : (it.controllers[1]?.text.trim() ?? "");
      final cQty = int.tryParse(it.controllers[7]?.text.trim() ?? "") ?? 0;
      final cFQty = int.tryParse(it.controllers[8]?.text.trim() ?? "") ?? 0;
      final tQty = (it.qty > 0 ? it.qty : cQty) + (it.fQty > 0 ? it.fQty : cFQty);
      return pName.isNotEmpty && tQty > 0;
    }).map((it) {
      final cQty = int.tryParse(it.controllers[7]?.text.trim() ?? "") ?? 0;
      final cFQty = int.tryParse(it.controllers[8]?.text.trim() ?? "") ?? 0;
      if (it.qty <= 0 && cQty > 0) it.qty = cQty;
      if (it.fQty <= 0 && cFQty > 0) it.fQty = cFQty;
      return it.toJson();
    }).toList();

    final nextName = _nextItem.productName.trim().isNotEmpty
        ? _nextItem.productName.trim()
        : (_nextItem.controllers[1]?.text.trim() ?? "");
    final nextCtrlQty = int.tryParse(_nextItem.controllers[7]?.text.trim() ?? "") ?? 0;
    final nextCtrlFQty = int.tryParse(_nextItem.controllers[8]?.text.trim() ?? "") ?? 0;
    final nextTotalQty = (_nextItem.qty > 0 ? _nextItem.qty : nextCtrlQty) + (_nextItem.fQty > 0 ? _nextItem.fQty : nextCtrlFQty);

    if (nextName.isNotEmpty && nextTotalQty > 0) {
      _nextItem.productName = nextName;
      if (_nextItem.qty <= 0 && nextCtrlQty > 0) _nextItem.qty = nextCtrlQty;
      if (_nextItem.fQty <= 0 && nextCtrlFQty > 0) _nextItem.fQty = nextCtrlFQty;
      validItems.add(_nextItem.toJson());
    }

    if (validItems.isEmpty) {
      await _pharmacyProvider!.clearPurchaseDraft();
      return;
    }

    final draftData = {
      'timestamp': DateTime.now().toIso8601String(),
      'supplier': _supplierCtrl.text,
      'supInvNo': _supInvNoCtrl.text,
      'supInvDate': _supInvDate.toIso8601String(),
      'entryNo': _entryNoCtrl.text,
      'entryDate': _date.toIso8601String(),
      'gstMode': _gstMode,
      'items': validItems,
    };

    await _pharmacyProvider!.savePurchaseDraft(draftData);
  }

  Future<void> _checkAndPromptDraftRecovery() async {
    if (_isExistingEntry || _pharmacyProvider == null) return;
    final draft = await _pharmacyProvider!.loadPurchaseDraft();
    if (draft == null || !mounted) return;

    final List rawItemsJson = draft['items'] as List? ?? [];
    final itemsJson = rawItemsJson.where((ij) {
      if (ij is! Map) return false;
      final String name = (ij['productName'] ?? ij['product_name'] ?? ij['name'] ?? '').toString().trim();
      final int q = (ij['qty'] as num?)?.toInt() ?? 0;
      final int fq = (ij['fQty'] as num?)?.toInt() ?? (ij['fqty'] as num?)?.toInt() ?? 0;
      return name.isNotEmpty && (q + fq) > 0;
    }).toList();

    if (itemsJson.isEmpty) {
      await _pharmacyProvider?.clearPurchaseDraft();
      return;
    }

    final String timeStr = draft['timestamp'] != null
        ? DateFormat('dd-MM-yyyy hh:mm a').format(DateTime.tryParse(draft['timestamp']) ?? DateTime.now())
        : 'Recent Session';

    final bool? shouldRestore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF334155), width: 1),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
        actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade900.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.history_toggle_off_rounded, color: Colors.amberAccent, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Unsaved Purchase Draft Found",
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 2),
                  Text(
                    "Review draft contents before restoring or discarding",
                    style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11, fontWeight: FontWeight.normal),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 700,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary Info Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.business_rounded, color: Colors.amberAccent, size: 14),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  "Supplier: ${draft['supplier']?.toString().isNotEmpty == true ? draft['supplier'] : 'N/A'}",
                                  style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.receipt_long_rounded, color: Color(0xFFCBD5E1), size: 14),
                              const SizedBox(width: 6),
                              Text(
                                "Inv No: ${draft['supInvNo']?.toString().isNotEmpty == true ? draft['supInvNo'] : 'N/A'}",
                                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          timeStr,
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade900.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade700),
                          ),
                          child: Text(
                            "${itemsJson.length} Items",
                            style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Item List Header
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E293B),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6)),
                ),
                child: const Row(
                  children: [
                    SizedBox(width: 24, child: Text("#", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold))),
                    Expanded(flex: 4, child: Text("ITEM / PRODUCT NAME", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold))),
                    Expanded(flex: 2, child: Text("BATCH / EXP", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold))),
                    Expanded(flex: 2, child: Text("QTY (+FREE)", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                    Expanded(flex: 2, child: Text("P.RATE / MRP", style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                  ],
                ),
              ),

              // Item List Scrollable Table
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF020617),
                    border: Border.all(color: const Color(0xFF1E293B)),
                    borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(6), bottomRight: Radius.circular(6)),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: itemsJson.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFF1E293B)),
                    itemBuilder: (context, idx) {
                      final ij = itemsJson[idx] as Map;
                      final String pName = (ij['productName'] ?? ij['product_name'] ?? ij['name'] ?? 'Item #${idx + 1}').toString().trim();
                      final String batch = (ij['batch'] ?? '-').toString().trim();
                      final String exp = (ij['expiry'] ?? ij['exp'] ?? '-').toString().trim();
                      final int q = (ij['qty'] as num?)?.toInt() ?? 0;
                      final int fq = (ij['fQty'] as num?)?.toInt() ?? (ij['fqty'] as num?)?.toInt() ?? 0;
                      final double pRate = (ij['pRate'] as num?)?.toDouble() ?? (ij['prate'] as num?)?.toDouble() ?? 0.0;
                      final double mrp = (ij['mrp'] as num?)?.toDouble() ?? 0.0;

                      final String qtyStr = fq > 0 ? "$q + $fq Free" : "$q";
                      final String batchExpStr = batch.isNotEmpty && batch != '-' ? "$batch (${exp.isNotEmpty ? exp : '-'})" : (exp.isNotEmpty ? exp : '-');

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        color: idx % 2 == 0 ? Colors.transparent : const Color(0xFF0F172A).withOpacity(0.5),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              child: Text(
                                "${idx + 1}",
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                            Expanded(
                              flex: 4,
                              child: Tooltip(
                                message: pName,
                                child: Text(
                                  pName,
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                batchExpStr,
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                qtyStr,
                                style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                pRate > 0 ? "₹${pRate.toStringAsFixed(2)}" : (mrp > 0 ? "₹${mrp.toStringAsFixed(2)}" : "-"),
                                style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 12),
              const Text(
                "Would you like to restore this draft or start a new bill?",
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await _pharmacyProvider?.clearPurchaseDraft();
              if (ctx.mounted) Navigator.of(ctx).pop(false);
            },
            icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
            label: const Text("Discard Draft", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.check_circle_rounded, size: 18),
            label: const Text("Restore Draft", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (shouldRestore == true && mounted) {
      setState(() {
        _supplierCtrl.text = draft['supplier']?.toString() ?? '';
        _supInvNoCtrl.text = draft['supInvNo']?.toString() ?? '';
        if (draft['supInvDate'] != null) {
          _supInvDate = DateTime.tryParse(draft['supInvDate']) ?? DateTime.now();
        }
        if (draft['entryDate'] != null) {
          _date = DateTime.tryParse(draft['entryDate']) ?? DateTime.now();
        }
        _gstMode = (draft['gstMode'] as num?)?.toInt() ?? 1;

        for (var it in _items) {
          it.dispose();
        }
        _items.clear();
        for (var ij in itemsJson) {
          _items.add(PurchaseItemData.fromJson(Map<String, dynamic>.from(ij)));
        }
        _calculateFooter();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Restored ${itemsJson.length} items from unsaved draft."),
          backgroundColor: Colors.teal.shade800,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  DateTime _parseExpiry(String exp) {
    if (exp.contains('/')) {
      final parts = exp.split('/');
      int m = int.tryParse(parts[0].replaceAll('-', '0')) ?? 1;
      int y = int.tryParse(parts[1].replaceAll('-', '0')) ?? 99;
      
      // Strict month validation to prevent report pollution
      if (m < 1 || m > 12) m = 12; 
      
      if (y < 100) y += 2000;
      return DateTime(y, m + 1, 0);
    }
    return DateTime(2099);
  }

  ExpiryStyle? _getExpiryStyle(String expiryStr) {
    final trimmed = expiryStr.trim();
    if (trimmed.isEmpty || trimmed == "--/--" || trimmed.contains('-') || !trimmed.contains('/')) {
      return null;
    }

    final parts = trimmed.split('/');
    if (parts.length != 2) return null;
    int? m = int.tryParse(parts[0]);
    int? y = int.tryParse(parts[1]);
    if (m == null || y == null || m < 1 || m > 12) return null;

    if (y < 100) y += 2000;
    DateTime expDate = DateTime(y, m + 1, 0);

    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);

    int months = (expDate.year - now.year) * 12 + (expDate.month - now.month);

    if (expDate.isBefore(today) || months <= 3) {
      // 1. Up to 3 Months / Expired ➜ Dark Red 🔴
      return ExpiryStyle(Colors.red.shade900, Colors.white);
    } else if (months <= 6) {
      // 2. Up to 6 Months ➜ Red 🔴
      return ExpiryStyle(Colors.red.shade700, Colors.white);
    } else if (months <= 12) {
      // 3. Up to 1 Year (12 Months) ➜ Orange 🟧
      return ExpiryStyle(Colors.orange.shade800, Colors.white);
    } else if (months <= 18) {
      // 4. Up to 1.5 Years (18 Months) ➜ Yellow 🟨
      return ExpiryStyle(Colors.amber.shade700, Colors.white);
    } else if (months <= 24) {
      // 5. Up to 2 Years (24 Months) ➜ Light Green 🟢
      return ExpiryStyle(Colors.lightGreen.shade700, Colors.white);
    } else if (months <= 36) {
      // 6. Up to 3 Years (36 Months) ➜ Green 🟢
      return ExpiryStyle(Colors.green.shade700, Colors.white);
    } else {
      // 7. More than 3 Years (> 36 Months) ➜ Dark Green 🟢
      return ExpiryStyle(Colors.teal.shade800, Colors.white);
    }
  }

  Color _getBatchBgColor(String expiryStr) {
    ExpiryStyle? style = _getExpiryStyle(expiryStr);
    return style?.bgColor ?? Colors.green.shade800.withValues(alpha: 0.9);
  }

  Color? _getExpiryColor(String expiryStr) {
    ExpiryStyle? style = _getExpiryStyle(expiryStr);
    return style?.bgColor;
  }

  String _fmt(double val) {
    if (val % 1 == 0) return val.toInt().toString();
    return val.toStringAsFixed(2);
  }

  TextEditingController _getHeaderCtrl(int col) {
    if (col == 0) return _supplierCtrl;
    if (col == 1) return _doneByCtrl;
    if (col == 2) return _supInvNoCtrl;
    if (col == 3) return _invTotalCtrl;
    return _poNoCtrl;
  }

  TextEditingController _getGridCtrl(int row, int col, [String init = ""]) {
    final it = _getItemAt(row);
    if (!it.controllers.containsKey(col)) {
      String val = init;
      if (val.isEmpty && row < _items.length) {
        val = it.getColValue(col);
      }
      it.controllers[col] = TextEditingController(text: val);
    }
    return it.controllers[col]!;
  }

  FocusNode _getGridFocusNode(int row, int col) {
    final it = _getItemAt(row);
    if (!it.focusNodes.containsKey(col)) {
      final fn = FocusNode();
      fn.addListener(() {
        // CODE MASTER FIX: Dynamic Row Lookup to prevent data corruption after row deletion
        int currentRow = _items.indexOf(it);
        if (currentRow == -1 && it == _nextItem) currentRow = _items.length;
        if (currentRow == -1) return; // Item was deleted, do nothing

        if (fn.hasFocus) {
          final ctrl = _getGridCtrl(currentRow, col); 
          if (_focusNotifier.value?.row != currentRow || _focusNotifier.value?.col != col) {
            _focusNotifier.value = IntPair(currentRow, col);
            _updateHistory(it.productName);
          }
          if (col == 2) {
            if (!_isSelectingBatch) {
              setState(() => _isSelectingBatch = true);
            }
            _startBatchSearch(currentRow, "");
          }
          if (ctrl.text.isNotEmpty) {
            Timer.run(() {
              if (fn.hasFocus) {
                ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
              }
            });
          }
        } else {
          _onBlur(currentRow, col, _getGridCtrl(currentRow, col).text);
          // DELAY DROPDOWN CLOSURE: Gives the click event 150ms to register
          Future.delayed(const Duration(milliseconds: 150), () {
            if (!_isSelectingFromDropdown && mounted) {
              final currentFocus = _focusNotifier.value;
              if (currentFocus != null && currentFocus.row != -1) {
                if (currentFocus.col == 1 || currentFocus.col == 2) {
                  return;
                }
              }
              _closeAllDropdowns();
            }
          });
        }
      });
      it.focusNodes[col] = fn;
    }
    return it.focusNodes[col]!;
  }

  void _showPurchaseHeadingsHint() {
    final List<String> fields = [
      'Product Code', 'Product', 'Batch', 'Exp', 'Packing', 'Qty', 'Fqty',
      'Prate', 'Mrp', 'DisPer', 'TaxPer (Total)', 'CGST', 'SGST', 'Sdisc'
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 10),
            Text("Purchase Import Fields", style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("You can map your file columns to these application fields (any order):", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: fields.map((h) => Chip(
                  label: Text(h, style: const TextStyle(fontSize: 11)),
                  backgroundColor: Colors.blue.shade50,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                )).toList(),
              ),
              const SizedBox(height: 15),
              const Text("Note: The smart mapper will try to auto-detect these headers from your Excel or PDF file.", style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: fields.join("\t")));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Headings copied to clipboard!"), duration: Duration(seconds: 1)));
            },
            child: const Text("COPY ALL"),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK")),
        ],
      ),
    );
  }

  void _onBlur(int row, int col, String value) {
    if (_isSelectingFromDropdown) return;

    if (col == 12 && row < _items.length && value.trim().isNotEmpty) {
      _discountInteractedRows.add(_items[row].uuid);
    }

    // Purchase screen handles _items[row] OR _nextItem if it's the last empty row
    final it = _getItemAt(row);

    // ---> THE FIX: AUTO-FILL PRODUCT ON BLUR <---
    if (col == 1) {
      if (value.trim().isNotEmpty && it.productId.isEmpty) {
        final p = Provider.of<PharmacyProvider>(context, listen: false);
        final matches = p.searchProducts(value.trim(), includeGenerics: false);
        if (matches.isNotEmpty) {
          final best = matches.first;
          it.productId = best.id;
          it.productName = best.name;
          it.lastPulledName = best.name;
          it.hsncode = best.hsnCode;
          it.packin = best.packSize;
          it.mrp = best.mrp;
          it.pRate = best.purchaseRate;
          it.gstPercent = best.gstPercent;
          it.rack = best.rack;
          _getGridCtrl(row, 1).text = best.name;
        } else {
          it.productName = value;
        }
      } else {
        it.productName = value;
      }

      if (row == _items.length && it.productName.isNotEmpty) {
        setState(() {
          _items.add(it);
          _nextItem = PurchaseItemData();
          _calculateItem(row);
        });
        return;
      }
    }
    // ---> THE FIX: AUTO-FILL BATCH ON BLUR <---
    else if (col == 2) {
      if (value.trim().isEmpty && it.productName.isNotEmpty) {
        final p = Provider.of<PharmacyProvider>(context, listen: false);
        final availableBatches = p.products.where((prod) => prod.name.toLowerCase() == it.productName.toLowerCase()).toList();

        if (availableBatches.isNotEmpty) {
          // Sort to pull the oldest batch as a template
          availableBatches.sort((a, b) => _parseExpiry(a.expiry).compareTo(_parseExpiry(b.expiry)));
          final bestBatch = availableBatches.first;

          it.batch = bestBatch.batch;
          it.expiry = bestBatch.expiry;
          it.hsncode = bestBatch.hsnCode;
          it.packin = bestBatch.packSize;
          it.mrp = bestBatch.mrp;
          it.pRate = bestBatch.purchaseRate;
          it.gstPercent = bestBatch.gstPercent;
          it.sDiscPercent = bestBatch.sDiscPercent;
          it.rack = bestBatch.rack;

          _getGridCtrl(row, 2).text = cleanBatch(bestBatch.batch);
          _getGridCtrl(row, 5).text = bestBatch.expiry;
        } else {
          it.batch = value;
        }
      } else {
        it.batch = value;
      }
    }
    else if (col == 3) {
      it.rack = value;
    } else if (col == 4) {
      it.hsncode = value;
    } else if (col == 5) {
      it.expiry = value;
    } else if (col == 6) {
      it.packin = int.tryParse(value) ?? it.packin;
    } else if (col == 7) {
      it.qty = int.tryParse(value) ?? 0;
      
      // ---> THE FIX: NO AUTO-CORRECT. Just show a warning popup! <---
      if (it.isConsumed && (it.qty + it.fQty) < it.minStripsRequired) {
        _showFastDialog(
          title: "Warning: Quantity Too Low", 
          content: "You entered ${it.qty}. However, ${it.minStripsRequired} strips have already been consumed from this batch.\n\nThe system will block you from saving this entry unless you fix the quantity."
        );
      }
      
    } else if (col == 8) {
      it.fQty = int.tryParse(value) ?? 0;
    } else if (col == 9) {
      it.mrp = double.tryParse(value) ?? 0.0;
    } else if (col == 10) {
      it.pRate = double.tryParse(value) ?? 0.0;
    } else if (col == 12) {
      it.discPercent = double.tryParse(value) ?? 0.0;
    } else if (col == 13) {
      it.discAmt = double.tryParse(value) ?? 0.0;
    } else if (col == 15) {
      it.gstPercent = TaxCalculator.roundGstPercent(double.tryParse(value) ?? 0.0);
    } else if (col == 18) {
      it.sDiscPercent = double.tryParse(value) ?? 0.0;
    } else if (col == 19) {
      it.sDiscAmt = double.tryParse(value) ?? 0.0;
    }

    if (row < _items.length) {
      _calculateItem(row);
    }
  }

  void _calculateItem(int row) {
    final it = (row < _items.length) ? _items[row] : _nextItem;

    it.recalculate(
      isGstMode: _gstMode == 1,
      isDiscAmtFocused: _getGridFocusNode(row, 13).hasFocus,
      isGstAmtFocused: _getGridFocusNode(row, 16).hasFocus,
      isSDiscAmtFocused: _getGridFocusNode(row, 19).hasFocus,
    );

    void updateCtrl(int col, String val) {
      final c = _getGridCtrl(row, col);
      if (c.text != val) c.text = val;
    }

    if (!_getGridFocusNode(row, 1).hasFocus) updateCtrl(1, it.productName);
    if (!_getGridFocusNode(row, 2).hasFocus) updateCtrl(2, it.batch);
    if (!_getGridFocusNode(row, 4).hasFocus) updateCtrl(4, it.hsncode);
    if (!_getGridFocusNode(row, 3).hasFocus) updateCtrl(3, it.rack);
    if (!_getGridFocusNode(row, 6).hasFocus) updateCtrl(6, it.packin.toString());
    if (!_getGridFocusNode(row, 7).hasFocus) updateCtrl(7, it.qty.toString());
    if (!_getGridFocusNode(row, 8).hasFocus) updateCtrl(8, it.fQty.toString());
    if (!_getGridFocusNode(row, 9).hasFocus) updateCtrl(9, _fmt(it.mrp));
    if (!_getGridFocusNode(row, 10).hasFocus) updateCtrl(10, _fmt(it.pRate));
    updateCtrl(11, _fmt(it.gross));

    if (!_getGridFocusNode(row, 12).hasFocus) updateCtrl(12, _fmt(it.discPercent));
    if (!_getGridFocusNode(row, 13).hasFocus) updateCtrl(13, _fmt(it.discAmt));

    updateCtrl(14, _fmt(it.net));
    if (!_getGridFocusNode(row, 15).hasFocus) updateCtrl(15, _fmt(TaxCalculator.roundGstPercent(it.gstPercent)));
    updateCtrl(16, _fmt(it.gstAmt));
    updateCtrl(17, _fmt(it.total));

    if (!_getGridFocusNode(row, 18).hasFocus) updateCtrl(18, _fmt(it.sDiscPercent));
    if (!_getGridFocusNode(row, 19).hasFocus) updateCtrl(19, _fmt(it.sDiscAmt));

    updateCtrl(20, _fmt(it.sRate));
    updateCtrl(21, _fmt(it.lCost));
    _calculateFooter();
  }

  // CODE MASTER FIX: Debounced Footer math to eliminate typing lag
  bool _isBulkUpdating = false;
  void _calculateFooter() {
    if (_isBulkUpdating) return;

    _footerDebouncer.run(() {
      if (!mounted) return;
      
      double sub = _items.fold(0.0, (s, i) => s + i.total);

      if (_footerDiscAmtFocus.hasFocus) {
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

      double footerDiscAmt = double.tryParse(_footerDiscAmtCtrl.text) ?? 0;
      double otherAmt = double.tryParse(_otherChargeAmtCtrl.text) ?? 0;
      double lessCr = double.tryParse(_lessCrNoteCtrl.text) ?? 0;

      double finalVal = sub - footerDiscAmt + otherAmt - lessCr;
      if (finalVal < 0) finalVal = 0.0;
      double rounded = finalVal.roundToDouble();

      _subTotalCtrl.text = _fmt(sub);
      _roundOffCtrl.text = _fmt(rounded - finalVal);
      _grandTotalCtrl.text = _fmt(rounded);
      _grandTotalNotifier.value = rounded;
      _summaryNotifier.value++;
    });
  }

  void _moveFocus(int row, int col, {bool autoOpen = false}) {
    int safeRow = row.clamp(-1, _items.length);
    
    // STRICT RULE: If the column is not in _navCols, jump to the nearest valid one
    int safeCol = col;
    if (safeRow >= 0 && !_navCols.contains(col)) {
      if (col < _navCols.first) {
        safeCol = _navCols.first;
      } else if (col > _navCols.last) {
        safeCol = _navCols.last;
      } else {
        safeCol = _navCols.reduce((a, b) => (a - col).abs() < (b - col).abs() ? a : b);
      }
    }

    final oldFocus = _focusNotifier.value;
    if (oldFocus?.row != safeRow || oldFocus?.col != safeCol) {
      if (safeCol != 1 && safeCol != 2) {
        _closeAllDropdowns();
      }
    }

    _focusNotifier.value = IntPair(safeRow, safeCol);

    final bool targetIsBatch = (safeCol == 2);
    if (_isSelectingBatch != targetIsBatch) {
      setState(() {
        _isSelectingBatch = targetIsBatch;
      });
    }

    // Request focus immediately for snappier "one-click" experience
    if (safeRow != -1) {
      _getGridFocusNode(safeRow, safeCol).requestFocus();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (safeRow == -1) {
        FocusNode? fn;
        if (safeCol == 0) {
          fn = _supplierFocus;
        } else if (safeCol == 1) {
          fn = _doneByFocus;
        } else if (safeCol == 2) {
          fn = _supInvNoFocus;
        } else if (safeCol == 3) {
          fn = _invTotalFocus;
        } else {
          fn = _poNoFocus;
        }

        bool wasFocused = fn.hasFocus;
        if (!wasFocused) {
          fn.requestFocus();
          final ctrl = _getHeaderCtrl(safeCol);
          ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
        }
      } else {
        final fn = _getGridFocusNode(safeRow, safeCol);
        final ctrl = _getGridCtrl(safeRow, safeCol);
        final initialText = ctrl.text;

        fn.requestFocus();
        
        // Ensure selection is full on focus change
        if (initialText.isNotEmpty) {
          ctrl.selection = TextSelection(baseOffset: 0, extentOffset: initialText.length);
        }

        if (autoOpen || safeCol == 2) {
          if (safeCol == 1 && initialText.trim().isEmpty) {
            _startProductSearch("");
          } else if (safeCol == 2) {
            _startBatchSearch(safeRow, "");
          }
        }
      }
    });
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (_isDialogOpen) return false;
    if (event is KeyUpEvent) return false;
    final key = event.logicalKey;

    if (_footerDiscPctFocus.hasFocus) {
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.tab) {
        _promptSave();
        return true;
      }
    }

    if (key == LogicalKeyboardKey.f6) {
      _isExistingEntry ? _savePurchase(isEdit: true) : _savePurchase();
      return true;
    }

    if (key == LogicalKeyboardKey.f1) {
      _moveFocus(_focusedRowIndex != -1 ? _focusedRowIndex : _items.length, 1);
      return true;
    }

    if (key == LogicalKeyboardKey.f2) {
      _resetPage();
      return true;
    }

    if (key == LogicalKeyboardKey.f12) {
      _printPurchase();
      return true;
    }

    if (key == LogicalKeyboardKey.escape) {
      if (_searchList.value.isNotEmpty || _batchList.value.isNotEmpty || _supplierSearchList.value.isNotEmpty || _doneBySearchList.value.isNotEmpty) {
        _closeAllDropdowns();
        return true;
      }
    }

    if (HardwareKeyboard.instance.isControlPressed) {
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
        final it = _items[_focusedRowIndex];
        if (it.isConsumed) {
          _showFastDialog(
              title: "Row Locked",
              content: "Cannot delete this row because ${it.consumedLooseUnits} units are already consumed."
          );
          return true;
        }
        _saveUndoState();
        setState(() {
          final removed = _items.removeAt(_focusedRowIndex);
          removed.dispose();
          _errorCells.clear();
          _calculateFooter();
        });
        _moveFocus(_focusedRowIndex, 1);
        return true;
      }
    }

    if (HardwareKeyboard.instance.isControlPressed && key == LogicalKeyboardKey.keyV) {
      _processPastedClipboardData();
      return true;
    }

    if (HardwareKeyboard.instance.isAltPressed) {
      if (key == LogicalKeyboardKey.arrowLeft) { _navigateEntry("prev"); return true; }
      if (key == LogicalKeyboardKey.arrowRight) { _navigateEntry("next"); return true; }
    }

    final bool isBatchActive = _isSelectingBatch && _batchList.value.isNotEmpty;
    final bool isSearchActive = !_isSelectingBatch && _searchList.value.isNotEmpty;
    final bool isSupplierActive = _supplierSearchList.value.isNotEmpty;
    final bool isDoneByActive = _doneBySearchList.value.isNotEmpty;

    final bool isOverlayOpen = isSupplierActive || isDoneByActive || isBatchActive || isSearchActive;

    if (isOverlayOpen) {
      final List list = isSupplierActive ? _supplierSearchList.value 
                      : isDoneByActive ? _doneBySearchList.value 
                      : isBatchActive ? _batchList.value 
                      : _searchList.value;

      if (list.isNotEmpty) {
        if (key == LogicalKeyboardKey.arrowDown) {
          _searchIdx.value = (_searchIdx.value + 1) % list.length;
          if (isSearchActive && list[_searchIdx.value] is Product) {
            _updateHistory((list[_searchIdx.value] as Product).name);
          }
          _scrollToIdx(_searchIdx.value);
          return true;
        } else if (key == LogicalKeyboardKey.arrowUp) {
          _searchIdx.value = (_searchIdx.value - 1 + list.length) % list.length;
          if (isSearchActive && list[_searchIdx.value] is Product) {
            _updateHistory((list[_searchIdx.value] as Product).name);
          }
          _scrollToIdx(_searchIdx.value);
          return true;
        } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
          if (isSupplierActive) {
            _onSupplierSelected(list[_searchIdx.value] as String);
          } else if (isDoneByActive) {
            _onDoneBySelected(list[_searchIdx.value] as String);
          } else if (isBatchActive) {
            _finalizeBatchSelection(list[_searchIdx.value] as Product);
          } else {
            _onProductSelected(list[_searchIdx.value] as Product);
          }
          return true;
        }
      }
    }

    int row = _focusedRowIndex;
    int col = _focusedColIndex;
    if (row == -1) {
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.tab) {
        // ---> THE FIX: Sequential Header Jumping <---
        if (col == 0) {
          _moveFocus(-1, 1); // Supplier -> Done By
        } else if (col == 1) {
          _moveFocus(-1, 2); // Done By -> Sup Inv No
        } else if (col == 2) {
          _moveFocus(-1, 3); // Sup Inv No -> Inv Total
        } else {
          _moveFocus(_items.length, 1, autoOpen: true); // Inv Total -> Grid Blank Line
        }
        return true;
      }

      final hCtrl = _getHeaderCtrl(col);
      if (key == LogicalKeyboardKey.arrowRight) {
        if (!hCtrl.selection.isValid || hCtrl.selection.baseOffset >= hCtrl.text.length) {
          if (col < 3) {
            _moveFocus(-1, col + 1);
          } else {
            _moveFocus(_items.length, 1);
          }
          return true;
        }
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        if (col > 0) _moveFocus(-1, col - 1);
        return true;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _moveFocus(_items.length, 1);
        return true;
      }
      return false;
    }

    final ctrl = _getGridCtrl(row, col);
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if ((key == LogicalKeyboardKey.tab || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) && isShift) {
      int curIdx = _navCols.indexOf(col);
      if (curIdx > 0) {
        _moveFocus(row, _navCols[curIdx - 1], autoOpen: _navCols[curIdx - 1] == 2);
      } else if (curIdx == 0 && row > 0) {
        _moveFocus(row - 1, _navCols.last);
      }
      return true;
    }

    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.tab) {
      _onFieldSubmitted(row, col);
      return true;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      int curIdx = _navCols.indexOf(col);
      if (curIdx > 0) {
        _moveFocus(row, _navCols[curIdx - 1], autoOpen: _navCols[curIdx - 1] == 2);
        return true;
      } else if (curIdx == 0 && row > 0) {
        _moveFocus(row - 1, _navCols.last);
        return true;
      }
      return false;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (!ctrl.selection.isValid || ctrl.selection.baseOffset >= ctrl.text.length) {
        int curIdx = _navCols.indexOf(col);
        if (curIdx != -1 && curIdx < _navCols.length - 1) {
          _moveFocus(row, _navCols[curIdx + 1], autoOpen: row == _items.length && (_navCols[curIdx + 1] == 1 || _navCols[curIdx + 1] == 2));
          return true;
        } else if (curIdx == _navCols.length - 1 && row < _items.length) {
          // THE FIX: Right arrow at the end of the line jumps straight to blank line
          _moveFocus(_items.length, 1, autoOpen: true);
          return true;
        }
      }
      return false;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (row < _items.length) {
        _moveFocus(row + 1, col, autoOpen: (row + 1) == _items.length && (col == 1 || col == 2));
      }
      return true;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (row > 0) {
        _moveFocus(row - 1, col, autoOpen: false); // Never auto-open moving up to old rows
      } else {
        _moveFocus(-1, 0);
      }
      return true;
    }

    return false;
  }

  void _scrollToIdx(int index) {
    if (!_dropdownScrollCtrl.hasClients) return;
    const double itemHeight = 30.0;
    const double viewportHeight = 200.0;
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
      final list = _supplierSearchList.value.isNotEmpty ? _supplierSearchList.value : (_isSelectingBatch ? _batchList.value : _searchList.value);
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

  // CODE MASTER FIX: Debounced Database queries to prevent UI freezing
  void _updateHistory(String productName) {
    if (productName.isEmpty) {
      setState(() { _productHistory = []; _historyProductName = ""; });
      return;
    }
    
    // CODE MASTER FIX: Safely reads the provider before the async gap
    final p = Provider.of<PharmacyProvider>(context, listen: false); 
    
    _historyDebouncer.run(() async {
      final history = await p.getProductPurchaseHistory(productName);
      if (mounted) {
        setState(() {
          _productHistory = history;
          _historyProductName = productName;
        });
      }
    });
  }

  void _startSupplierSearch(String q) {
    if (q.trim().isEmpty) { _supplierSearchList.value = []; return; }
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    _supplierSearchList.value = p.suppliers.where((s) => s.toLowerCase().contains(q.toLowerCase())).take(50).toList();
    _searchIdx.value = 0;
  }

  void _startDoneBySearch(String q) {
    if (q.trim().isEmpty) { _doneBySearchList.value = []; return; }
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    _doneBySearchList.value = p.doneByNames.where((s) => s.toLowerCase().contains(q.toLowerCase())).take(20).toList();
    _searchIdx.value = 0;
  }

  void _onDoneBySelected(String name) {
    _isSelectingFromDropdown = true;
    setState(() {
      _doneByCtrl.text = name;
      _doneBySearchList.value = [];
    });
    _moveFocus(-1, 2); // Jump to Sup Inv No
    Future.delayed(const Duration(milliseconds: 100), () => _isSelectingFromDropdown = false);
  }

  void _onSupplierSelected(String s) {
    _isSelectingFromDropdown = true;
    _supplierCtrl.text = s;
    _supplierSearchList.value = [];
    _autoSelectFormat(s);
    _moveFocus(-1, 1); // ---> THE FIX: Jumps straight to Done By
    Future.delayed(const Duration(milliseconds: 100), () => _isSelectingFromDropdown = false);
  }

  void _autoSelectFormat(String supplierName) {
    if (supplierName.trim().isEmpty) return;

    final p = Provider.of<PharmacyProvider>(context, listen: false);

    final allNames = {
      ...p.importMappings.map((m) => m.name.replaceAll(' - EXCEL', '').replaceAll(' - PDF', '')),
      ...p.suppliers
    }.toList();

    String searchName = supplierName.trim().toLowerCase();
    String? matchedName;

    for (var name in allNames) {
      if (name.toLowerCase() == searchName) {
        matchedName = name;
        break;
      }
    }

    if (matchedName != null) {
      setState(() => _activeFormatName = matchedName);

      bool hasMapping = p.importMappings.any((m) =>
      m.name == "$matchedName - EXCEL" || m.name == "$matchedName - PDF"
      );

      if (hasMapping) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Format linked for $matchedName"), backgroundColor: Colors.green.shade700, duration: const Duration(seconds: 1)),
        );
      }
    }
  }

  void _startProductSearch(String q) {
    setState(() => _isSelectingBatch = false);
    final query = q.trim();
    if (query.isEmpty) {
      _searchList.value = [];
      return;
    }

    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    List<Product> matches = provider.searchProducts(query);
    if (matches.isEmpty) {
      matches = [Product(id: "NEW", name: query.toUpperCase())];
    }

    _searchList.value = matches.take(50).toList();
    _searchIdx.value = 0;
  }

  void _startBatchSearch(int row, String q) {
    if (!_isSelectingBatch) {
      setState(() => _isSelectingBatch = true);
    }
    _searchList.value = []; // Clear product search list so dropdown doesn't conflict
    final p = Provider.of<PharmacyProvider>(context, listen: false);

    String prodName = row < _items.length ? _items[row].productName.trim() : "";
    if (prodName.isEmpty) {
      prodName = _getGridCtrl(row, 1).text.trim();
    }
    if (prodName.isEmpty) { 
      _batchList.value = []; 
      return; 
    }

    final String targetNameLower = prodName.toLowerCase();
    final List<Product> allStock = [];
    final Set<String> seenBatches = {};

    // 1. Add active stock batches via O(1) fast lookup
    final batchesFromMap = p.getBatchesForProductName(prodName);
    for (var prod in batchesFromMap) {
      final String bKey = cleanBatch(prod.batch).toUpperCase();
      if (bKey.isNotEmpty && !seenBatches.contains(bKey)) {
        seenBatches.add(bKey);
        allStock.add(prod);
      }
    }

    // 2. Find master record for default pricing/pack/generic info
    final masterMatch = p.productMaster.firstWhere(
      (m) => m.name.trim().toLowerCase() == targetNameLower,
      orElse: () => Product(id: "", name: prodName),
    );

    if (masterMatch.batch.trim().isNotEmpty) {
      final String mbKey = cleanBatch(masterMatch.batch).toUpperCase();
      if (!seenBatches.contains(mbKey)) {
        seenBatches.add(mbKey);
        allStock.add(masterMatch);
      }
    }

    // 3. Add historical purchase batches for this product
    try {
      for (var pur in p.purchases) {
        for (var item in pur.items) {
          if (item.productName.trim().toLowerCase() == targetNameLower) {
            final String bKey = cleanBatch(item.batch).toUpperCase();
            if (bKey.isNotEmpty && !seenBatches.contains(bKey)) {
              seenBatches.add(bKey);
              allStock.add(Product(
                id: masterMatch.id,
                name: item.productName,
                batch: item.batch,
                expiry: item.expiry,
                mrp: item.mrp,
                purchaseRate: item.pRate,
                salePrice: item.sRate,
                packSize: item.packin,
                gstPercent: item.gstPercent,
                supplier: pur.supplierName,
                genericName: masterMatch.genericName,
              )..stock = 0);
            }
          }
        }
      }
    } catch (_) {}

    final String query = q.trim().toLowerCase();
    final matches = query.isEmpty 
        ? allStock 
        : allStock.where((b) => cleanBatch(b.batch).toLowerCase().contains(query)).toList();

    matches.sort((a, b) {
      int expComp = _parseExpiry(a.expiry).compareTo(_parseExpiry(b.expiry));
      if (expComp != 0) return expComp;
      return b.stock.compareTo(a.stock);
    });
    _batchList.value = matches;
    _searchIdx.value = 0;
  }

  Future<void> _openProductRegistrationDialog(String initialName) async {
    final Product? newProd = await showDialog<Product>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 600,
          height: 680,
          child: ProductRegistrationScreen(
            initialName: initialName,
            isCompact: true,
          ),
        ),
      ),
    );

    if (newProd != null) {
      _onProductSelected(newProd);
    }
  }

  void _onProductSelected(Product p) {
    _isSelectingFromDropdown = true;
    final int row = _focusedRowIndex;
    bool isNewRow = (row == _items.length);

    // If user selected the "+ Create New" option
    if (p.id == "NEW") {
      _searchList.value = [];
      _openProductRegistrationDialog(p.name);
      return;
    }

    setState(() {
      _getGridCtrl(row, 1, p.name).text = p.name;
      if (isNewRow) {
        final it = _nextItem;
        it.productId = p.id;
        it.productName = p.name;
        it.lastPulledName = p.name;
        it.packin = p.packSize;
        it.mrp = p.mrp;
        it.pRate = p.purchaseRate;
        it.masterMrp = p.mrp;
        it.masterPRate = p.purchaseRate;
        it.masterGstPercent = p.gstPercent;
        it.hsncode = p.hsnCode;
        it.gstPercent = p.gstPercent;
        it.rack = p.rack;
        it.sDiscPercent = p.sDiscPercent;

        _items.add(it);
        _nextItem = PurchaseItemData();
        _calculateItem(_items.length - 1);
      } else {
        final it = _items[row];
        it.productId = p.id;
        it.productName = p.name;
        it.lastPulledName = p.name;
        it.masterMrp = p.mrp;
        it.masterPRate = p.purchaseRate;
        it.masterGstPercent = p.gstPercent;
        it.hsncode = p.hsnCode;
        it.rack = p.rack;
        it.sDiscPercent = p.sDiscPercent;
        _calculateItem(row);
      }
    });

    _searchList.value = [];
    _updateHistory(p.name);
    _moveFocus(isNewRow ? _items.length - 1 : row, 2, autoOpen: true);
    Future.delayed(const Duration(milliseconds: 100), () => _isSelectingFromDropdown = false);
  }

  void _finalizeBatchSelection(Product p) {
    _isSelectingFromDropdown = true;
    setState(() {
      final row = _focusedRowIndex;
      final String batchClean = cleanBatch(p.batch);
      _getGridCtrl(row, 2, batchClean).text = batchClean;
      _getGridCtrl(row, 5, p.expiry).text = p.expiry;
      if (row < _items.length) {
        _items[row].batch = p.batch;
        _items[row].expiry = p.expiry;
        if (p.mrp > 0) {
          _items[row].mrp = p.mrp;
          _getGridCtrl(row, 9, p.mrp.toStringAsFixed(2)).text = p.mrp.toStringAsFixed(2);
        }
        if (p.purchaseRate > 0) {
          _items[row].pRate = p.purchaseRate;
          _getGridCtrl(row, 10, p.purchaseRate.toStringAsFixed(2)).text = p.purchaseRate.toStringAsFixed(2);
        }
        if (p.salePrice > 0) {
          _items[row].sRate = p.salePrice;
        }
        if (p.packSize > 0) {
          _items[row].packin = p.packSize;
          _getGridCtrl(row, 6, p.packSize.toString()).text = p.packSize.toString();
        }
        if (p.gstPercent > 0) {
          _items[row].gstPercent = p.gstPercent;
          _getGridCtrl(row, 15, p.gstPercent.toStringAsFixed(2)).text = p.gstPercent.toStringAsFixed(2);
        }
        _calculateItem(row);
      }
    });
    _batchList.value = [];
    _moveFocus(_focusedRowIndex, 4);
    Future.delayed(const Duration(milliseconds: 100), () => _isSelectingFromDropdown = false);
  }

  void _readPdfDirectly() async {
    if (_activeFormatName == null) {
      String supplierPart = _supplierCtrl.text.isNotEmpty ? " for ${_supplierCtrl.text}" : "";
      _showFastDialog(title: "Format Required", content: "Please select a Format$supplierPart from the top dropdown before reading PDF.");
      return;
    }
    _importPdfFile();
  }

  Widget _buildSmartPasteZone() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F7FD),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.blue.shade300, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Read Excel Button
          InkWell(
            onTap: _importExcel,
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(5), bottomLeft: Radius.circular(5)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.grid_on_rounded, size: 18, color: Colors.green.shade700),
                  const SizedBox(height: 2),
                  Text("Read Excel", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 32, color: Colors.blue.shade200),

          // 2. Paste Excel ! (Open Window) Button
          InkWell(
            onTap: _processPastedClipboardData,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.assignment_outlined, size: 15, color: Colors.blue.shade900),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text("Paste Excel ", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                          Text("!", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.blue.shade900)),
                        ],
                      ),
                      Text("(Open Window)", style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 32, color: Colors.blue.shade200),

          // 3. Read PDF Button
          InkWell(
            onTap: _readPdfDirectly,
            borderRadius: const BorderRadius.only(topRight: Radius.circular(5), bottomRight: Radius.circular(5)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.red.shade700),
                  const SizedBox(height: 2),
                  Text("Read PDF", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _processRawPastedText(String text) async {
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final rows = text.split(RegExp(r'\r?\n')).where((r) => r.trim().isNotEmpty).toList();
    if (rows.isEmpty) return;

    String delimiter = '\t';
    if (!rows[0].contains('\t') && rows[0].contains(',')) {
      delimiter = ',';
    }

    List<String> headers = rows[0].split(delimiter).map((h) => h.trim().replaceAll('"', '')).toList();
    if (headers.length < 2) {
      _showFastDialog(title: "Paste Error", content: "Invalid data format. Please copy tab-separated or comma-separated rows from Excel.");
      return;
    }

    ImportMapping? mapping;
    if (_activeFormatName != null && _activeFormatName!.trim().isNotEmpty) {
      String cleanActive = _activeFormatName!
          .replaceAll(' - EXCEL', '')
          .replaceAll(' - PDF', '')
          .trim()
          .toLowerCase();

      mapping = p.importMappings.cast<ImportMapping?>().firstWhere(
        (m) {
          if (m == null) return false;
          String cleanM = m.name
              .replaceAll(' - EXCEL', '')
              .replaceAll(' - PDF', '')
              .trim()
              .toLowerCase();
          return cleanM == cleanActive;
        },
        orElse: () => null,
      );
    }

    // Fallback to default format if no custom format exists or active format is null
    mapping ??= ImportMapping.defaultMapping();

    List<List<dynamic>> dataRows = [];
    for (int i = 1; i < rows.length; i++) {
      dataRows.add(rows[i].split(delimiter).map((cell) => cell.trim().replaceAll('"', '')).toList());
    }

    _importPastedRows(mapping, headers, dataRows);
  }

  Widget _buildGridHeader() {
    return Container(
      height: 32,
      color: const Color(0xFF37474F),
      child: Row(
        children: [
          _Hdr("Slno", tooltip: "Serial Number", width: _colWidths[0], align: TextAlign.center, isLocked: true),
          _Hdr("Product Name", tooltip: "Product Name", width: _colWidths[1]),
          _Hdr("Batch", tooltip: "Batch Number", width: _colWidths[2]),
          _Hdr("Rack", tooltip: "Rack Location", width: _colWidths[3], isLocked: true),
          _Hdr("HSN", tooltip: "HSN Code", width: _colWidths[4]),
          _Hdr("Expiry", tooltip: "Expiry Date (MM/YY)", width: _colWidths[5], align: TextAlign.center),
          _Hdr("Pack", tooltip: "Packing Size", width: _colWidths[6], align: TextAlign.right),
          _Hdr("Qty", tooltip: "Purchased Quantity", width: _colWidths[7], align: TextAlign.right),
          _Hdr("F.Qty", tooltip: "Free Quantity", width: _colWidths[8], align: TextAlign.right),
          _Hdr("MRP", tooltip: "Maximum Retail Price", width: _colWidths[9], align: TextAlign.right),
          _Hdr("P.Rate", tooltip: "Purchase Rate", width: _colWidths[10], align: TextAlign.right),
          _Hdr("Gross", tooltip: "Gross Amount", width: _colWidths[11], align: TextAlign.right, isLocked: true),
          _Hdr("Disc%", tooltip: "Discount Percentage", width: _colWidths[12], align: TextAlign.right),
          _Hdr("DiscAmt", tooltip: "Discount Amount", width: _colWidths[13], align: TextAlign.right),
          _Hdr("Net", tooltip: "Net Amount", width: _colWidths[14], align: TextAlign.right, isLocked: true),
          _Hdr("GST%", tooltip: "GST Percentage", width: _colWidths[15], align: TextAlign.right),
          _Hdr("GSTAmt", tooltip: "GST Amount", width: _colWidths[16], align: TextAlign.right, isLocked: true),
          _Hdr("Total", tooltip: "Total Amount", width: _colWidths[17], align: TextAlign.right, isLocked: true),
          _Hdr("S.Disc%", tooltip: "Sale Discount Percentage", width: _colWidths[18], align: TextAlign.right),
          _Hdr("S.Amt", tooltip: "Sale Discount Amount", width: _colWidths[19], align: TextAlign.right),
          _Hdr("S.Rate", tooltip: "Selling Rate", width: _colWidths[20], align: TextAlign.right, isLocked: true),
          _Hdr("L.Cost", tooltip: "Landing Cost", width: _colWidths[21], align: TextAlign.right, isLocked: true),
          _Hdr("", width: _colWidths[22]),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    return Scrollbar(
      controller: _verticalGridScrollCtrl,
      child: ListView.builder(
        controller: _verticalGridScrollCtrl,
        itemCount: _items.length + 1,
        itemExtent: 28.0,
        itemBuilder: (ctx, i) => RepaintBoundary(child: _buildGridRow(i)),
      ),
    );
  }

  Widget _buildGridRow(int row) {
    final it = _getItemAt(row);
    final isNewRow = row == _items.length;
    
    return ValueListenableBuilder<IntPair?>(
      valueListenable: _focusNotifier,
      builder: (context, focus, _) {
        bool isFocused = focus?.row == row;
        Color rowBg = isFocused ? const Color(0xFFE3F2FD) : (row % 2 == 0 ? Colors.white : const Color(0xFFF5F7F9));
        
        // Highlight row in RED if Negative Margin (Purchase Rate >= MRP)
        if (row < _items.length && _items[row].isNegativeMargin) {
          rowBg = Colors.red.shade100;
        }

        // Highlight background colors for read-only / calculated locked cells
        const Color lockedBg = Color(0xFFF1F5F9);
        const Color totalLockedBg = Color(0xFFEFF6FF);
        const Color slnoBg = Color(0xFFF8FAFC);

        return Container(
          height: 28,
          decoration: BoxDecoration(
            color: rowBg,
            border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 0.5)),
          ),
          child: Row(
            children: [
              _GridCell("${row + 1}", width: _colWidths[0], align: TextAlign.center, bgColor: slnoBg),
              _buildEditableCell(row, 1), 
              _buildEditableCell(row, 2), 
              _GridCell(it.rack.toUpperCase(), width: _colWidths[3], bgColor: lockedBg),  
              _buildEditableCell(row, 4), 
              _buildEditableCell(row, 5, formatter: _ExpiryFormatter()), 
              _buildEditableCell(row, 6, isNumeric: true), 
              _buildEditableCell(row, 7, isNumeric: true), 
              _buildEditableCell(row, 8, isNumeric: true), 
              _buildEditableCell(row, 9, isNumeric: true), 
              _buildEditableCell(row, 10, isNumeric: true), 
              _GridCell(_fmt(it.gross), width: _colWidths[11], align: TextAlign.right, bgColor: lockedBg),
              _buildEditableCell(row, 12, isNumeric: true), 
              _buildEditableCell(row, 13, isNumeric: true), 
              _GridCell(_fmt(it.net), width: _colWidths[14], align: TextAlign.right, bgColor: lockedBg),
              _buildEditableCell(row, 15, isNumeric: true), 
              _GridCell(_fmt(it.gstAmt), width: _colWidths[16], align: TextAlign.right, bgColor: lockedBg),
              _GridCell(_fmt(it.total), width: _colWidths[17], align: TextAlign.right, fontWeight: FontWeight.bold, color: Colors.blue.shade900, bgColor: totalLockedBg),
              _buildEditableCell(row, 18, isNumeric: true), 
              _buildEditableCell(row, 19, isNumeric: true), 
              _GridCell(_fmt(it.sRate), width: _colWidths[20], align: TextAlign.right, bgColor: lockedBg),
              _GridCell(_fmt(it.lCost), width: _colWidths[21], align: TextAlign.right, bgColor: lockedBg),
              Container(
                width: _colWidths[22],
                alignment: Alignment.center,
                child: isNewRow ? null : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.info_outline_rounded, size: 14, color: Colors.blueGrey),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: "Live Math Breakdown",
                      onPressed: () => _showPurchaseItemMathBreakdown(it),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close, size: 14, color: Colors.red),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        _saveUndoState();
                        setState(() {
                          _items.removeAt(row).dispose();
                          _calculateFooter();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildEditableCell(int row, int col, {bool isNumeric = false, TextInputFormatter? formatter}) {
    final actualFocusNode = _getGridFocusNode(row, col);
    final ctrl = _getGridCtrl(row, col);

    return ListenableBuilder(
      listenable: Listenable.merge([actualFocusNode, ctrl, _focusNotifier]),
      builder: (context, _) {
        bool isActive = (_focusNotifier.value?.row == row && _focusNotifier.value?.col == col) || actualFocusNode.hasFocus;
        bool hasError = _errorCells[row]?.contains(col) ?? false;

        Color? customCellBg;
        Color textColor = Colors.black;

        if (col == 12) {
          final it = _getItemAt(row);
          final text = ctrl.text.trim();
          bool hasValue = text.isNotEmpty || row < _items.length || it.productName.isNotEmpty;
          if (hasValue) {
            double discVal = double.tryParse(text) ?? it.discPercent;
            DiscountColorInfo info = _getDiscountColorInfo(discVal);
            customCellBg = info.bgColor;
            textColor = info.textColor;
          }
        } else if (col == 5) {
          final text = ctrl.text.trim();
          if (text.isNotEmpty && text != "--/--") {
            ExpiryStyle? style = _getExpiryStyle(text);
            if (style != null) {
              customCellBg = style.bgColor;
              textColor = style.textColor;
            }
          }
        } else if (col == 9 && row < _items.length) {
          if (_items[row].hasMrpChanged) {
            textColor = Colors.blue.shade800;
          }
        } else if (col == 10 && row < _items.length) {
          if (_items[row].isLowMargin) {
            customCellBg = Colors.amber.shade100;
            textColor = Colors.orange.shade900;
          } else if (_items[row].hasPRateChanged) {
            textColor = Colors.blue.shade800;
          }
        } else if (col == 15 && row < _items.length) {
          if (_items[row].hasGstMismatch) {
            customCellBg = Colors.amber.shade300;
            textColor = Colors.amber.shade900;
          }
        }

        Widget cellChild;

        if (isActive) {
          cellChild = TextField(
            controller: ctrl,
            focusNode: actualFocusNode,
            textAlign: isNumeric ? TextAlign.right : (col == 5 ? TextAlign.center : TextAlign.left),
            cursorColor: customCellBg != null ? textColor : null,
            onSubmitted: (_) => _onFieldSubmitted(row, col),
            onTap: () {
              final bool isAlreadyFocused = (_focusNotifier.value?.row == row && _focusNotifier.value?.col == col);

              if (!isAlreadyFocused) {
                _moveFocus(row, col, autoOpen: col == 2 || ctrl.text.trim().isEmpty);
                if (ctrl.text.trim().isNotEmpty) {
                  ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
                }
              } else {
                if (col == 1) {
                  _startProductSearch(ctrl.text);
                } else if (col == 2) {
                  _startBatchSearch(row, "");
                }
              }
            },
            onChanged: (v) {
              if (_errorCells[row]?.contains(col) == true) {
                setState(() => _errorCells[row]?.remove(col));
              }
              if (col == 1) {
                final existingName = _getItemAt(row).productName;
                if (v.trim().isEmpty || !(_isExistingEntry && v.trim().toUpperCase() == existingName.trim().toUpperCase())) {
                  _startProductSearch(v);
                }
              } else if (col == 2) {
                _startBatchSearch(row, v);
              } else {
                _onBlur(row, col, v);
              }
            },
            inputFormatters: [
              if (formatter != null) formatter,
              if (isNumeric) FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              if (!isNumeric && formatter == null && col != 1 && col != 4) UpperCaseTextFormatter(),
            ],
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: customCellBg != null ? textColor : const Color(0xFF0F172A),
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              hintText: col == 1 && row == _items.length ? "Search Product..." : "",
              hintStyle: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          );
        } else {
          final String displayText = ctrl.text.isEmpty && col == 1 && row == _items.length ? "Search Product..." : ctrl.text;
          final bool isHint = ctrl.text.isEmpty && col == 1 && row == _items.length;

          String extraSuffix = "";
          String? cellTooltip;

          if (row < _items.length) {
            final item = _items[row];
            if (col == 9 && item.hasMrpChanged) {
              extraSuffix = item.isMrpIncreased ? " ▲" : " ▼";
              cellTooltip = "MRP Changed! Old Master MRP: ₹${item.masterMrp!.toStringAsFixed(2)}";
            } else if (col == 10) {
              if (item.hasPRateChanged) {
                extraSuffix = item.isPRateIncreased ? " ▲" : " ▼";
                cellTooltip = "P.Rate Changed! Old Master Rate: ₹${item.masterPRate!.toStringAsFixed(2)}";
              }
              if (item.isLowMargin) {
                cellTooltip = "${cellTooltip != null ? '$cellTooltip | ' : ''}⚠️ Low Margin: ${item.profitPctNoDisc.toStringAsFixed(1)}% (< 24.9%)";
              }
            } else if (col == 15 && item.hasGstMismatch) {
              cellTooltip = "Invoice GST: ${item.gstPercent.toStringAsFixed(1)}% (Master GST: ${item.masterGstPercent?.toStringAsFixed(1)}%)";
            }
          }

          Widget textWidget = Text(
            "$displayText$extraSuffix",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isHint ? Colors.grey : textColor,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          );

          if (cellTooltip != null) {
            textWidget = Tooltip(
              message: cellTooltip,
              child: textWidget,
            );
          }

          cellChild = InkWell(
            onTap: () {
              _moveFocus(row, col, autoOpen: col == 2 || ctrl.text.trim().isEmpty);
            },
            child: Container(
              alignment: isNumeric ? Alignment.centerRight : (col == 5 ? Alignment.center : Alignment.centerLeft),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: textWidget,
            ),
          );
        }

        Widget content = Container(
          decoration: BoxDecoration(
            border: isActive ? Border.all(color: Colors.blue.shade800, width: 1.5) : null,
            color: hasError
                ? Colors.red.shade50
                : (customCellBg ?? (isActive ? Colors.white : null)),
          ),
          child: (col == 1 || col == 2)
              ? CompositedTransformTarget(
                  link: ((isActive || _focusedRowIndex == row) && col == 1) ? _searchLayer : (((isActive || _focusedRowIndex == row) && col == 2) ? _batchLayer : LayerLink()),
                  child: cellChild,
                )
              : cellChild,
        );

        return Container(
          width: _colWidths[col],
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: Colors.grey.shade300, width: 0.5)),
          ),
          child: content,
        );
      },
    );
  }

  Widget _buildGridSummary() {
    return Container(
      height: 24,
      color: const Color(0xFF455A64),
      child: Row(
        children: [
          SizedBox(width: _colWidths[0]! + _colWidths[1]!),
          const Text(" TOTALS: ", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _recentPurchasesList() {
    return Consumer<PharmacyProvider>(
      builder: (context, p, child) {
        final recent = p.purchases.take(15).toList();
        return ListView.builder(
          itemCount: recent.length,
          itemBuilder: (ctx, i) {
            final e = recent[i];
            return InkWell(
              onTap: () => _loadPurchaseData(e.entryNo),
              child: Container(
                height: 22,
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                child: Row(children: [
                  Expanded(flex: 1, child: Text(cleanEntryNo(e.entryNo), style: const TextStyle(fontSize: 10))),
                  Expanded(flex: 3, child: Text(e.supplierName, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis)),
                  Expanded(flex: 2, child: Text(_fmt(e.grandTotal), textAlign: TextAlign.right, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                ]),
              ),
            );
          },
        );
      }
    );
  }

  Widget _purchaseHistoryList() {
    return ListView.builder(
      itemCount: _productHistory.length,
      itemBuilder: (ctx, i) {
        final h = _productHistory[i];
        return Container(
          height: 22,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
          child: Row(children: [
            SizedBox(width: 70, child: Text(DateFormat('dd/MM/yy').format(DateTime.parse(h['date'])), style: const TextStyle(fontSize: 10))),
            SizedBox(width: 70, child: Text(h['entry_no'], style: const TextStyle(fontSize: 10))),
            Expanded(flex: 2, child: Text(h['supplier_name'], style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis)),
            SizedBox(width: 60, child: Text(_fmt(h['mrp']), textAlign: TextAlign.right, style: const TextStyle(fontSize: 10))),
            SizedBox(width: 60, child: Text(_fmt(h['p_rate']), textAlign: TextAlign.right, style: const TextStyle(fontSize: 10))),
            SizedBox(width: 45, child: Text("${h['f_qty']}", textAlign: TextAlign.right, style: const TextStyle(fontSize: 10))),
            SizedBox(width: 45, child: Text("${h['disc_percent']}", textAlign: TextAlign.right, style: const TextStyle(fontSize: 10))),
            SizedBox(width: 70, child: Text(_fmt(h['l_cost']), textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade900))),
          ]),
        );
      },
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
            _calcRow("Less CrNote:", _lessCrNoteCtrl),
            _calcRow("Round Off:", _roundOffCtrl, readOnly: true),
            const Divider(height: 4, thickness: 1, color: Colors.black26),
            Row(children: [
              const Text("GRAND TOTAL:", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.blue)),
              const Spacer(),
              Text("₹ ${_fmt(total)}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.blue)),
            ]),
          ]),
        );
      }
    );
  }

  void _resetGridAndInvoiceFieldsForImport() {
    for (var it in _items) {
      it.dispose();
    }
    _nextItem.dispose();
    _items.clear();
    _errorCells.clear();
    _discountInteractedRows.clear();
    _nextItem = PurchaseItemData();
  }

  void _finalizeImportAfterMapping(List<PurchaseItem>? mappedItems, List<PurchaseItem> importedItems, List<PurchaseItem> validItems) {
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    if (mappedItems != null && mappedItems.isNotEmpty) {
      String norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

      for (var mapped in mappedItems) {
        for (var original in importedItems) {
          if (original.id == "UNKNOWN") {
            bool match = false;

            // 1. Primary Match: Match by External Description (Unique Wholesaler Item Name)
            String origExtName = norm(original.externalName.isNotEmpty ? original.externalName : original.productName);
            String mapExtName = norm(mapped.externalName.isNotEmpty ? mapped.externalName : mapped.productName);

            if (origExtName.isNotEmpty && origExtName == mapExtName) {
              match = true;
            } 
            // 2. Secondary Match: Match by External Code ONLY if external names match or are empty
            else if (mapped.externalCode.isNotEmpty && 
                     original.externalCode.isNotEmpty && 
                     mapped.externalCode.trim() == original.externalCode.trim()) {
              if (origExtName.isEmpty || origExtName == mapExtName) {
                match = true;
              }
            }

            if (match) {
              original.id = mapped.id;
              original.productName = mapped.productName;
              original.mrp = mapped.mrp > 0 ? mapped.mrp : original.mrp;
              original.gstPercent = mapped.gstPercent > 0 ? mapped.gstPercent : original.gstPercent;
              original.packin = mapped.packin > 0 ? mapped.packin : original.packin;
              original.rack = mapped.rack.isNotEmpty ? mapped.rack : original.rack;
              original.hsnCode = mapped.hsnCode.isNotEmpty ? mapped.hsnCode : original.hsnCode;
              original.sDiscPercent = mapped.sDiscPercent;

              if (original.mrp <= 0) {
                final provider = Provider.of<PharmacyProvider>(context, listen: false);
                final pm = provider.productMaster.cast<Product?>().firstWhere(
                  (prod) => prod != null && (prod.id == original.id || prod.name.trim().toLowerCase() == original.productName.trim().toLowerCase()),
                  orElse: () => null,
                );
                if (pm != null && pm.mrp > 0) {
                  original.mrp = pm.mrp;
                }
              }

              if (!validItems.contains(original)) {
                validItems.add(original);
              }
              break; // Prevent mapped item from overwriting other distinct rows!
            }
          }
        }
      }

      // Fallback: If matching didn't catch all mapped items, append remaining mapped items directly
      for (var mapped in mappedItems) {
        if (mapped.id.isNotEmpty && mapped.id != "UNKNOWN") {
          bool alreadyInValid = validItems.any((v) => v.id == mapped.id && v.batch == mapped.batch);
          if (!alreadyInValid) {
            validItems.add(mapped);
          }
        }
      }
    }

    if (validItems.isNotEmpty) {
      setState(() {
        _resetGridAndInvoiceFieldsForImport();

        // Preserve current supplier text if already entered
        if (_supplierCtrl.text.trim().isEmpty && _activeFormatName != null && _activeFormatName!.trim().isNotEmpty) {
          _supplierCtrl.text = _activeFormatName!;
        }

        for (var item in validItems) {
          final matchedPm = p.productMaster.cast<Product?>().firstWhere(
            (pm) => pm != null && (pm.id == item.id || pm.name.trim().toLowerCase() == item.productName.trim().toLowerCase()),
            orElse: () => null,
          );

          final it = PurchaseItemData()
            ..productId = item.id
            ..productName = item.productName
            ..batch = item.batch
            ..rack = item.rack
            ..hsncode = item.hsnCode
            ..expiry = item.expiry
            ..packin = item.packin
            ..qty = item.qty
            ..fQty = item.fQty
            ..mrp = item.mrp
            ..pRate = item.pRate
            ..masterMrp = matchedPm?.mrp
            ..masterPRate = matchedPm?.purchaseRate
            ..discPercent = item.discPercent
            ..gstPercent = item.gstPercent
            ..masterGstPercent = matchedPm?.gstPercent
            ..sDiscPercent = item.sDiscPercent;

          it.recalculate(isGstMode: _gstMode == 1);
          it.syncControllers();
          _discountInteractedRows.add(it.uuid);
          _items.add(it);
        }

        _isBulkUpdating = true;
        for (int i = 0; i < _items.length; i++) {
          _calculateItem(i);
        }
        _isBulkUpdating = false;
        _calculateTotals();
      });

      _calculateFooter();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Imported ${validItems.length} items instantly"), backgroundColor: Colors.green));
    }
  }

  int _getFirstBlankProductRowIndex() {
    for (int i = 0; i < _items.length; i++) {
      if (_items[i].productName.trim().isEmpty) return i;
    }
    return _items.length;
  }

  void _onFieldSubmitted(int row, int col) {
    // ---> THE FIX: Catch the Header Jumps FIRST before checking column numbers <---
    if (row == -1) { 
      if (col == 0) {
        _moveFocus(-1, 1); // Supplier -> Done By
      } else if (col == 1) _moveFocus(-1, 2); // Done By -> Sup Inv No
      else if (col == 2) _moveFocus(-1, 3); // Sup Inv No -> Inv Total
      else if (col == 3) _moveFocus(_getFirstBlankProductRowIndex(), 1, autoOpen: true); // Inv Total -> New Blank Line
      else _moveFocus(_getFirstBlankProductRowIndex(), 1, autoOpen: true);
      return; // Stop here so it doesn't run the grid code below!
    }

    // --- GRID JUMPS BELOW ---
    if (col == 1) {
      String typedText = _getGridCtrl(row, 1).text.trim();

      if (_searchList.value.isNotEmpty) {
        _onProductSelected(_searchList.value[_searchIdx.value]);
      }
      else if (typedText.isEmpty && row == _items.length) {
        // Drop down to footer when finishing purchase entry
        _footerDiscPctFocus.requestFocus();
      }
      else if (typedText.isNotEmpty) {
        final p = Provider.of<PharmacyProvider>(context, listen: false);
        final matches = p.searchProducts(typedText, includeGenerics: false);

        if (matches.isNotEmpty) {
          _onProductSelected(matches.first);
        } else {
          _moveFocus(row, 2, autoOpen: true);
        }
      } else {
        int curIdx = _navCols.indexOf(col);
        if (curIdx != -1 && curIdx < _navCols.length - 1) {
          _moveFocus(row, _navCols[curIdx + 1], autoOpen: _navCols[curIdx + 1] == 1 || _navCols[curIdx + 1] == 2);
        }
      }
    }
    else if (col == 2) {
      String typed = _getGridCtrl(row, 2).text.trim().toUpperCase();

      if (_batchList.value.isNotEmpty) {
        final selected = _batchList.value[_searchIdx.value];
        final exactIdx = _batchList.value.indexWhere((b) => b.batch.toUpperCase() == typed);
        if (exactIdx != -1) {
          _finalizeBatchSelection(_batchList.value[exactIdx]);
        } else {
          _finalizeBatchSelection(selected);
        }
        return;
      }

      final p = Provider.of<PharmacyProvider>(context, listen: false);
      String prodName = row < _items.length ? _items[row].productName.trim() : "";
      if (prodName.isEmpty) {
        prodName = _getGridCtrl(row, 1).text.trim();
      }

      final availableBatches = p.products.where((it) => it.name.toLowerCase() == prodName.toLowerCase()).toList();
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
        if (row < _items.length) {
          _items[row].batch = typed;
        }
        _moveFocus(row, 4);
      }
    }
    else {
      int curIdx = _navCols.indexOf(col);
      if (curIdx != -1 && curIdx < _navCols.length - 1) {
        _moveFocus(row, _navCols[curIdx + 1], autoOpen: row == _items.length && (_navCols[curIdx + 1] == 1 || _navCols[curIdx + 1] == 2));
      } else {
        // Reached the end of the line. Jump straight to the blank line!
        _moveFocus(_items.length, 1, autoOpen: true);
      }
    }
  }

  void _showManualMappingDialog(PharmacyProvider p, {ImportMapping? initialMapping, int? index}) {
    final windowId = initialMapping == null ? "manual_mapping_new" : "manual_mapping_${initialMapping.name}";
    Provider.of<MdiController>(context, listen: false).openWindow(
      MdiWindow(
        id: windowId,
        title: initialMapping == null ? "Create Manual Mapping" : "Edit Manual Mapping",
        width: 600,
        height: 600,
        content: DynamicExcelMappingDialog(
          excelHeaders: const [],
          filePath: initialMapping == null ? "manual" : "manual_edit",
          provider: p,
          initialMapping: initialMapping,
          mappingIndex: index,
          closeWindow: (_) {
            Provider.of<MdiController>(context, listen: false).closeWindow(windowId);
          },
          onImportComplete: (newMapping) {
            Provider.of<MdiController>(context, listen: false).closeWindow(windowId);
            setState(() => _activeFormatName = newMapping.name.replaceAll(' - EXCEL', '').replaceAll(' - PDF', ''));
          },
        ),
      ),
    );
  }

  void _showFormatTypePicker(PharmacyProvider p) {
    Provider.of<MdiController>(context, listen: false).openWindow(
      MdiWindow(
        id: "format_type_picker",
        title: "Create New Format",
        width: 400,
        height: 250,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.table_chart, color: Colors.blue),
              title: const Text("Excel / CSV Format"),
              onTap: () {
                Provider.of<MdiController>(context, listen: false).closeWindow("format_type_picker");
                _showManualMappingDialog(p);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text("Visual PDF Format"),
              onTap: () {
                Provider.of<MdiController>(context, listen: false).closeWindow("format_type_picker");
                _startNewPdfMapping(p);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _startNewPdfMapping(PharmacyProvider p) {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PdfVisualMapperDialog(
          currentSupplier: _supplierCtrl.text,
          onImportReady: (mapping, headers, rows, isSilent) {
            Navigator.pop(ctx);
            if (isSilent) {
              setState(() => _activeFormatName = mapping.name.replaceAll(' - EXCEL', '').replaceAll(' - PDF', ''));
            } else {
              Provider.of<MdiController>(context, listen: false).openWindow(
                MdiWindow(
                  id: "pdf_visual_mapping",
                  title: "Visual PDF Mapping",
                  width: 600,
                  height: 600,
                  content: DynamicExcelMappingDialog(
                    excelHeaders: headers,
                    filePath: "pdf_visual",
                    provider: p,
                    initialMapping: mapping,
                    closeWindow: (_) {
                      Provider.of<MdiController>(context, listen: false).closeWindow("pdf_visual_mapping");
                    },
                    onImportComplete: (finalMapping) {
                      Provider.of<MdiController>(context, listen: false).closeWindow("pdf_visual_mapping");
                      setState(() => _activeFormatName = finalMapping.name.replaceAll(' - EXCEL', '').replaceAll(' - PDF', ''));
                    },
                  ),
                ),
              );
            }
          },
        )
    );
  }

  void _showUnifiedFormatManagerDialog(PharmacyProvider p) {
    Provider.of<MdiController>(context, listen: false).openWindow(
      MdiWindow(
        id: "format_manager",
        title: "Format Manager",
        width: 500,
        height: 550,
        content: ImportFormatSelectionDialog(
          provider: p,
          onFormatSelected: (mapping) {
            Provider.of<MdiController>(context, listen: false).closeWindow("format_manager");
            setState(() => _activeFormatName = mapping.name.replaceAll(' - EXCEL', '').replaceAll(' - PDF', ''));
          },
          onEdit: (mapping, index) {
            Provider.of<MdiController>(context, listen: false).closeWindow("format_manager");
            bool isPdf = mapping.name.endsWith('- PDF');
            if (isPdf) {
              showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx2) => PdfVisualMapperDialog(
                    currentSupplier: mapping.name.replaceAll(' - PDF', ''),
                    initialMapping: mapping,
                    isEditMode: true,
                    mappingIndex: index,
                    onImportReady: (newMapping, headers, rows, isSilent) {
                      Navigator.pop(ctx2);
                      setState(() => _activeFormatName = newMapping.name.replaceAll(' - EXCEL', '').replaceAll(' - PDF', ''));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("PDF Format Updated!"), backgroundColor: Colors.green));
                    },
                  )
              );
            } else {
              _showManualMappingDialog(p, initialMapping: mapping, index: index);
            }
          },
          onAddNew: (isPdf) {
            Provider.of<MdiController>(context, listen: false).closeWindow("format_manager");
            if (isPdf) {
              _startNewPdfMapping(p);
            } else {
              _showManualMappingDialog(p);
            }
          },
        ),
      ),
    );
  }

  // --- GENERATE DETAILED EDIT DIFF SPANS FOR RE-WRITE DIALOG ---
  List<InlineSpan> _generateDiffSpans() {
    final List<InlineSpan> diffSpans = [];

    if (!_isExistingEntry || _originalLoadedEntry == null) {
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
    final origSupplier = _originalLoadedEntry!.supplierName.trim();
    if (currentSupplier.toUpperCase() != origSupplier.toUpperCase()) {
      addDiffLine([
        const TextSpan(text: "supplier name ", style: normalStyle),
        TextSpan(text: origSupplier.isEmpty ? "(blank)" : origSupplier, style: redStyle),
        const TextSpan(text: " to ", style: normalStyle),
        TextSpan(text: currentSupplier.isEmpty ? "(blank)" : currentSupplier, style: redStyle),
        const TextSpan(text: ".", style: normalStyle),
      ]);
    }

    // Supplier Inv No
    final currentInvNo = cleanInvoiceNo(_supInvNoCtrl.text);
    final origInvNo = cleanInvoiceNo(_originalLoadedEntry!.supInvNo);
    if (currentInvNo.toUpperCase() != origInvNo.toUpperCase()) {
      addDiffLine([
        const TextSpan(text: "supplier bill no ", style: normalStyle),
        TextSpan(text: origInvNo.isEmpty ? "(blank)" : origInvNo, style: redStyle),
        const TextSpan(text: " to ", style: normalStyle),
        TextSpan(text: currentInvNo.isEmpty ? "(blank)" : currentInvNo, style: redStyle),
        const TextSpan(text: ".", style: normalStyle),
      ]);
    }

    // Supplier Inv Date
    final currentInvDateStr = DateFormat('dd/MM/yyyy').format(_supInvDate);
    final origInvDateStr = DateFormat('dd/MM/yyyy').format(_originalLoadedEntry!.supInvDate);
    if (currentInvDateStr != origInvDateStr) {
      addDiffLine([
        const TextSpan(text: "bill date ", style: normalStyle),
        TextSpan(text: origInvDateStr, style: redStyle),
        const TextSpan(text: " to ", style: normalStyle),
        TextSpan(text: currentInvDateStr, style: redStyle),
        const TextSpan(text: ".", style: normalStyle),
      ]);
    }

    // Footer Discount
    final currentDiscAmt = double.tryParse(_footerDiscAmtCtrl.text) ?? 0.0;
    final origDiscAmt = _originalLoadedEntry!.discount;
    if ((currentDiscAmt - origDiscAmt).abs() > 0.01) {
      addDiffLine([
        const TextSpan(text: "footer discount ", style: normalStyle),
        TextSpan(text: "₹${origDiscAmt.toStringAsFixed(2)}", style: redStyle),
        const TextSpan(text: " to ", style: normalStyle),
        TextSpan(text: "₹${currentDiscAmt.toStringAsFixed(2)}", style: redStyle),
        const TextSpan(text: ".", style: normalStyle),
      ]);
    }

    // Other Charges
    final currentOtherCharge = double.tryParse(_otherChargeAmtCtrl.text) ?? 0.0;
    final origOtherCharge = _originalLoadedEntry!.otherCharge;
    if ((currentOtherCharge - origOtherCharge).abs() > 0.01) {
      addDiffLine([
        const TextSpan(text: "other charges ", style: normalStyle),
        TextSpan(text: "₹${origOtherCharge.toStringAsFixed(2)}", style: redStyle),
        const TextSpan(text: " to ", style: normalStyle),
        TextSpan(text: "₹${currentOtherCharge.toStringAsFixed(2)}", style: redStyle),
        const TextSpan(text: ".", style: normalStyle),
      ]);
    }

    // 2. ITEM COMPARISONS
    final origItems = _originalLoadedEntry!.items;
    final currentValidItems = _items.where((it) => it.productName.trim().isNotEmpty).toList();

    int maxLen = origItems.length > currentValidItems.length ? origItems.length : currentValidItems.length;

    for (int i = 0; i < maxLen; i++) {
      if (i < origItems.length && i < currentValidItems.length) {
        final orig = origItems[i];
        final curr = currentValidItems[i];

        // Product Name
        final origName = orig.productName.trim();
        final currName = curr.productName.trim();
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
        final currBatch = curr.batch.trim();
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

        // Free Qty
        if (orig.fQty != curr.fQty) {
          addDiffLine([
            TextSpan(text: "free qty ($currName) changed from ", style: normalStyle),
            TextSpan(text: "${orig.fQty}", style: redStyle),
            const TextSpan(text: " to ", style: normalStyle),
            TextSpan(text: "${curr.fQty}", style: redStyle),
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

        // MRP
        if ((orig.mrp - curr.mrp).abs() > 0.01) {
          addDiffLine([
            TextSpan(text: "mrp ($currName) changed from ", style: normalStyle),
            TextSpan(text: "₹${orig.mrp.toStringAsFixed(2)}", style: redStyle),
            const TextSpan(text: " to ", style: normalStyle),
            TextSpan(text: "₹${curr.mrp.toStringAsFixed(2)}", style: redStyle),
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
          TextSpan(text: curr.productName.trim(), style: redStyle),
          const TextSpan(text: " (qty: ", style: normalStyle),
          TextSpan(text: "${curr.qty}", style: redStyle),
          if (curr.batch.isNotEmpty) ...[
            const TextSpan(text: ', batch: "', style: normalStyle),
            TextSpan(text: curr.batch.trim(), style: redStyle),
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

  bool _hasResolvedGstMismatches = false;
  bool _hasConfirmedNearExpiry = false;

  Future<bool?> _showGstMismatchDialog(List<PurchaseItemData> mismatchedItems) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.amber.shade100, shape: BoxShape.circle),
                    child: Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text("⚠️ Purchase GST Rate Mismatch", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ],
              ),
              content: SizedBox(
                width: 580,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "The GST rate on the imported/entered purchase invoice differs from your Product Master default GST rate for the following items:",
                      style: TextStyle(fontSize: 12, color: Colors.blueGrey, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: SingleChildScrollView(
                        child: Column(
                          children: mismatchedItems.map((item) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.amber.shade300, width: 1),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(color: Colors.amber.shade200, borderRadius: BorderRadius.circular(6)),
                                        child: Text("Invoice GST: ${item.gstPercent.toStringAsFixed(1)}%", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.compare_arrows_rounded, size: 16, color: Colors.grey),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                                        child: Text("Master GST: ${(item.masterGstPercent ?? 0.0).toStringAsFixed(1)}%", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      InkWell(
                                        onTap: () {
                                          setDialogState(() => item.updateMasterGst = false);
                                          setState(() {});
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: !item.updateMasterGst ? Colors.blue.shade800 : Colors.white,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: !item.updateMasterGst ? Colors.blue.shade800 : Colors.grey.shade400),
                                          ),
                                          child: Text(
                                            "Option A: Keep Invoice GST Only",
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: !item.updateMasterGst ? Colors.white : Colors.black87),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      InkWell(
                                        onTap: () {
                                          setDialogState(() => item.updateMasterGst = true);
                                          setState(() {});
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: item.updateMasterGst ? Colors.teal.shade700 : Colors.white,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: item.updateMasterGst ? Colors.teal.shade700 : Colors.grey.shade400),
                                          ),
                                          child: Text(
                                            "Option B: Update Product Master",
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: item.updateMasterGst ? Colors.white : Colors.black87),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                OutlinedButton(
                  onPressed: () {
                    for (var item in mismatchedItems) {
                      item.updateMasterGst = false; // Option A for all
                    }
                    setState(() {});
                    Navigator.pop(ctx, true);
                  },
                  child: const Text("Keep All Invoice GST Only (Option A)", style: TextStyle(fontSize: 11)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white),
                  onPressed: () {
                    for (var item in mismatchedItems) {
                      item.updateMasterGst = true; // Option B for all
                    }
                    setState(() {});
                    Navigator.pop(ctx, true);
                  },
                  child: const Text("Update All Product Masters (Option B)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade800, foregroundColor: Colors.white),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("Apply & Continue", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _savePurchase({bool isEdit = false}) async {
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
        _showFastDialog(
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
        _showFastDialog(
          title: "Invalid Wholesaler",
          content: "The Wholesaler / Supplier '$supplierInput' is not selected from the dropdown list. Please select a valid Wholesaler from the dropdown before saving.",
        );
        _supplierFocus.requestFocus();
        return;
      }

      if (double.tryParse(_invTotalCtrl.text) == null || double.parse(_invTotalCtrl.text) <= 0) {
        _showFastDialog(title: "Required", content: "ENTER INVOICE TOTAL");
        _invTotalFocus.requestFocus();
        return;
      }
      if (_items.isEmpty) { _showFastDialog(title: "Empty", content: "ADD ITEMS"); return; }
      
      // === MINIMUM ₹1.00 GRAND TOTAL RULE ===
      if (_grandTotalNotifier.value < 1.0) { 
        _showFastDialog(
          title: "Invalid Grand Total", 
          content: "Purchase grand total must be at least ₹1.00.",
        ); 
        return; 
      }

      double enteredTotal = double.tryParse(_invTotalCtrl.text) ?? 0.0;
      if ((enteredTotal - _grandTotalNotifier.value).abs() >= 0.01) {
        _showFastDialog(
            title: "Total Mismatch",
            content: "INV TOTAL (${_fmt(enteredTotal)}) DOES NOT MATCH CALCULATED GRAND TOTAL (${_fmt(_grandTotalNotifier.value)}).\n\nPlease verify your items or the invoice total."
        );
        _invTotalFocus.requestFocus();
        return;
      }

      // === PRE-SAVE INTEGRITY GATE ===
      List<String> validationErrors = [];
      setState(() => _errorCells.clear());

      for (int i = 0; i < _items.length; i++) {
        final it = _items[i];
        if (it.productName.trim().isEmpty) continue; // Skip blank trailing rows

        // 1. Verify Product Name exists in Product Master
        bool isValidProduct = p.productMaster.any(
          (m) => m.name.trim().toLowerCase() == it.productName.trim().toLowerCase()
        );
        if (!isValidProduct) {
          _errorCells.putIfAbsent(i, () => {}).add(1); // Column 1: Product Name
          validationErrors.add("Row ${i + 1}: '${it.productName}' is not selected or fully typed from the dropdown list.");
        }

        // 2. Verify Batch Selection & Expiry Format (MM/YY)
        if (it.batch.trim().isEmpty) {
          _errorCells.putIfAbsent(i, () => {}).add(2); // Column 2: Batch
          validationErrors.add("Row ${i + 1}: Batch number is missing or incomplete.");
        }

        String exp = it.expiry.trim();
        if (exp.isEmpty || exp == "--/--" || !exp.contains('/')) {
          _errorCells.putIfAbsent(i, () => {}).add(5); // Column 5: Expiry
          validationErrors.add("Row ${i + 1}: Expiry date must follow MM/YY format (e.g., 06/28).");
        } else {
          final parts = exp.split('/');
          int? month = int.tryParse(parts[0]);
          int? year = int.tryParse(parts[1]);
          if (month == null || month < 1 || month > 12 || year == null) {
            _errorCells.putIfAbsent(i, () => {}).add(5); // Column 5: Expiry
            validationErrors.add("Row ${i + 1}: Invalid expiry month ($exp). Must be between 01 and 12.");
          } else {
            DateTime expDate = _parseExpiry(exp);
            DateTime now = DateTime.now();
            DateTime today = DateTime(now.year, now.month, now.day);
            if (expDate.isBefore(today)) {
              _errorCells.putIfAbsent(i, () => {}).add(5); // Column 5: Expiry
              validationErrors.add("🚫 Row ${i + 1}: Batch '${it.batch}' for '${it.productName}' is ALREADY EXPIRED ($exp). Cannot purchase or save expired stock.");
            }
          }
        }

        // 3. Verify Quantity Constraint (Qty + F.Qty > 0)
        if ((it.qty + it.fQty) <= 0) {
          _errorCells.putIfAbsent(i, () => {}).add(7); // Column 7: Quantity
          _errorCells.putIfAbsent(i, () => {}).add(8); // Column 8: Free Quantity
          validationErrors.add("Row ${i + 1}: Total Quantity (Qty + F.Qty) must be greater than 0.");
        }
      }

      // If any rule fails, highlight the cells in soft red and block saving entirely
      if (validationErrors.isNotEmpty) {
        _isSaving = false;
        setState(() {});
        AppDialogs.showFastDialog(
          context: context, 
          title: "Save Blocked: Incomplete / Expired Data", 
          content: validationErrors.join("\n")
        );
        return;
      }

      // --- DISTRIBUTOR RETURN WARNING ALERT (< CONFIGURABLE MONTHS) ---
      final prefs = await SharedPreferences.getInstance();
      int minAcceptableMonths = prefs.getInt('min_purchase_expiry_months') ?? 6;
      List<String> nearExpiryAlerts = [];

      for (int i = 0; i < _items.length; i++) {
        final it = _items[i];
        if (it.productName.trim().isEmpty) continue;
        DateTime expDate = _parseExpiry(it.expiry);
        DateTime now = DateTime.now();
        DateTime today = DateTime(now.year, now.month, now.day);
        int monthsRemaining = (expDate.year - now.year) * 12 + (expDate.month - now.month);

        if (!expDate.isBefore(today) && monthsRemaining < minAcceptableMonths) {
          nearExpiryAlerts.add("• ${it.productName} (Batch: ${it.batch}, Exp: ${it.expiry} - $monthsRemaining months left)");
        }
      }

      if (nearExpiryAlerts.isNotEmpty && !_hasConfirmedNearExpiry) {
        _isSaving = false;
        final bool? confirmNearExpiry = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.orange.shade100, shape: BoxShape.circle),
                  child: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade900, size: 28),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text("⚠️ Distributor Return Warning", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "The following stock items expire in under $minAcceptableMonths months:\n",
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: nearExpiryAlerts.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(e, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.deepOrange)),
                        )).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Distributors / Suppliers may NOT accept returns for near-expiry stock. Do you want to accept and proceed anyway?",
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey, height: 1.4),
                  ),
                ],
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("CANCEL & REVIEW", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("ACCEPT & PROCEED", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );

        if (confirmNearExpiry != true) return;
        _hasConfirmedNearExpiry = true;
        _isSaving = true;
      }
        return;
      }

      // --- GST MISMATCH WORKFLOW CHECK ---
      final mismatchedItems = _items.where((it) => it.hasGstMismatch).toList();
      if (mismatchedItems.isNotEmpty && !_hasResolvedGstMismatches) {
        _isSaving = false;
        final bool? resolved = await _showGstMismatchDialog(mismatchedItems);
        if (resolved != true) return;
        _hasResolvedGstMismatches = true;
        _isSaving = true;
      }

      // --- OPTION B: UPDATE PRODUCT MASTER DEFAULT GST RATES ---
      final db = await p.database;
      for (var it in _items) {
        if (it.updateMasterGst && it.productId.isNotEmpty && it.gstPercent > 0) {
          try {
            await db.rawUpdate(
              "UPDATE product_master SET gst_percent = ? WHERE id = ?",
              [it.gstPercent, it.productId],
            );
            final pmList = p.productMaster.where((prod) => prod.id == it.productId);
            for (var pm in pmList) {
              pm.gstPercent = it.gstPercent;
            }
          } catch (e) {
            debugPrint("Failed to update Product Master GST for ${it.productName}: $e");
          }
        }
      }

      // --- COMMERCIAL EDIT AUDIT LOG (SILENT) ---
      if (isEdit && _originalLoadedEntry != null) {
        // Snapshot the old items from the loaded entry
        List<Map<String, dynamic>> oldItemsSnapshot = _originalLoadedEntry!.items.map((i) => {
          'name': i.productName,
          'batch': i.batch,
          'qty': i.qty,
          'pack': i.packin,
          'mrp': i.mrp,
          'p_rate': i.pRate,
          'total': i.total,
        }).toList();

        List<Map<String, dynamic>> newItemsSnapshot = _items.map((i) => {
          'name': i.productName,
          'batch': i.batch,
          'qty': i.qty,
          'pack': i.packin,
          'mrp': i.mrp,
          'p_rate': i.pRate,
          'total': i.total,
        }).toList();

        // Save to the ledger BEFORE applying the update with a default reason
        await p.logEditHistory(
          entryNo: _entryNoCtrl.text,
          oldTotal: _originalLoadedEntry!.grandTotal,
          oldItemsJson: jsonEncode(oldItemsSnapshot),
          newItemsJson: jsonEncode(newItemsSnapshot),
          reason: "Edited from Purchase Entry",
        );
      }

      final validProductNames = p.productMaster.map((prod) => prod.name.toLowerCase().trim()).toSet();

      final List<String> errors = [];
      setState(() => _errorCells.clear()); // Clear previous errors
      bool hasError = false;

      for (int i = 0; i < _items.length; i++) {
        final it = _items[i];

        if (it.productName.trim().isEmpty) continue; // Skip blank rows

        if (!validProductNames.contains(it.productName.toLowerCase().trim())) {
          _errorCells.putIfAbsent(i, () => {}).add(1); // Col 1: Name
          hasError = true;
          errors.add("Row ${i+1}: '${it.productName}' is not a valid Product Name");
        }

        if (it.batch.isEmpty) { 
          _errorCells.putIfAbsent(i, () => {}).add(2); // Col 2: Batch
          hasError = true;
          errors.add("Row ${i+1}: Batch required"); 
        }
        // Strict Expiry Validator Check
        final parts = it.expiry.split(RegExp(r'[-/]'));
        if (parts.length == 2) {
          int? month = int.tryParse(parts[0].trim());
          int? year = int.tryParse(parts[1].trim());
          
          if (month == null || month < 1 || month > 12 || year == null) {
            _errorCells.putIfAbsent(i, () => {}).add(5); // Column 5 is Expiry
            hasError = true;
            errors.add("Row ${i+1}: Invalid expiry month (${it.expiry}). Must be between 01 and 12.");
          }
        } else {
          _errorCells.putIfAbsent(i, () => {}).add(5);
          hasError = true;
          errors.add("Row ${i+1}: Expiry must follow MM/YY format.");
        }
        
        // ---> THE FIX: Pack Size Validation <---
        if (it.packin <= 0) {
          _errorCells.putIfAbsent(i, () => {}).add(6); // Col 6: Pack
          hasError = true;
          errors.add("Row ${i+1}: Pack size must be 1 or greater");
        }

        if ((it.qty + it.fQty) <= 0) {
          _errorCells.putIfAbsent(i, () => {}).add(7); // Col 7: Qty
          _errorCells.putIfAbsent(i, () => {}).add(8); // Col 8: F.Qty
          hasError = true;
          errors.add("Row ${i+1}: Total Qty (Qty + F.Qt) must be > 0");
        }
        if (it.mrp <= 0) { 
          _errorCells.putIfAbsent(i, () => {}).add(9); // Col 9: MRP
          hasError = true;
          errors.add("Row ${i+1}: MRP > 0"); 
        }

        if (it.qty > 0 && it.total < 0.001) {
          _errorCells.putIfAbsent(i, () => {}).add(20); // Total is Col 20 in Purchase
          hasError = true;
          errors.add("Row ${i+1}: Item total must be at least ₹0.001");
        }
      }

      if (hasError) {
        _isSaving = false;
        _showFastDialog(title: "Errors", content: errors.join("\n"));
        return;
      }

      // --- EXPIRED ITEMS WARNING CHECK ---
      List<String> expiredItemWarnings = [];
      DateTime now = DateTime.now();
      DateTime today = DateTime(now.year, now.month, now.day);

      for (int i = 0; i < _items.length; i++) {
        final it = _items[i];
        if (it.productName.trim().isEmpty) continue;

        if (it.expiry.trim().isNotEmpty && it.expiry.trim() != "--/--") {
          DateTime expDate = _parseExpiry(it.expiry);
          if (expDate.isBefore(today)) {
            expiredItemWarnings.add("• Row ${i + 1}: ${it.productName} (Batch: ${it.batch}, Exp: ${it.expiry})");
          }
        }
      }

      if (expiredItemWarnings.isNotEmpty) {
        bool confirmExpired = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 28),
                const SizedBox(width: 10),
                const Text("Expired Items Warning", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "This purchase entry contains expired item(s):",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    expiredItemWarnings.join("\n"),
                    style: TextStyle(color: Colors.red.shade900, fontSize: 13, height: 1.3),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Are you sure you want to save this purchase entry with expired items?",
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("SAVE ANYWAY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ) ?? false;

        if (!confirmExpired) {
          _isSaving = false;
          setState(() {});
          return;
        }
      }

      // --- SMART DUPLICATE DETECTOR ---
      // Only check if it's a brand new entry (not an edit)
      if (!isEdit) {
        final validItemsForDupCheck = _items.map((it) => PurchaseItem(
          id: it.productId, productName: it.productName, batch: it.batch, expiry: it.expiry, qty: it.qty, mrp: it.mrp, pRate: it.pRate, total: it.total,
        )).toList();
        final totalForDupCheck = _grandTotalNotifier.value;

        if (p.isDuplicateRecentEntry(isPurchase: true, currentItems: validItemsForDupCheck, currentTotal: totalForDupCheck)) {
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
                "Please confirm it is not a duplicate entry.\n\nA purchase with these exact items and this exact total was saved very recently.",
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

          if (!confirmSave) return;
        }
      }

      if (isEdit) {
        // PIN security check removed as per user request (always unlocked)
        final oldEntry = p.purchases.cast<PurchaseEntry?>().firstWhere((e) => e?.entryNo == _entryNoCtrl.text, orElse: () => null);
        if (oldEntry != null) {
          final validationError = p.validatePurchaseEdit(oldEntry, _items.map((it) => PurchaseItem(
            id: it.productId,
            productName: it.productName, batch: it.batch, expiry: it.expiry,
            packin: it.packin, qty: it.qty, fQty: it.fQty, mrp: it.mrp, pRate: it.pRate,
            gross: it.gross, discPercent: it.discPercent, discAmt: it.discAmt, net: it.net,
            gstPercent: it.gstPercent, gstAmt: it.gstAmt, total: it.total, rack: it.rack,
            hsnCode: it.hsncode, sDiscPercent: it.sDiscPercent, sRate: it.sRate, lCost: it.lCost,
          )).toList());

          if (validationError != null) {
            _showFastDialog(title: "Edit Blocked", content: validationError);
            return;
          }
        }

        if (mounted) {
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
                  "No modifications were detected on Entry ${_entryNoCtrl.text}.\nThere are no changes to save.",
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
                      "Re-write Entry ${_entryNoCtrl.text}?",
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
                      "The following changes will be applied to this purchase entry:",
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
                      "Are you sure you want to overwrite Entry ${_entryNoCtrl.text}? Stock and supplier ledger will be updated accordingly.",
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

        if (!mounted) return;

      }

      final entry = PurchaseEntry(
        // If editing, use the visible number. If saving new, send empty string to safely auto-generate.
        entryNo: isEdit ? _entryNoCtrl.text : "",
        date: _date,
        supplierName: _supplierCtrl.text,
        supInvNo: cleanInvoiceNo(_supInvNoCtrl.text),
        supInvDate: _supInvDate,
        doneBy: _doneByCtrl.text,
        invTotal: double.tryParse(_invTotalCtrl.text) ?? 0.0,
        remarks: _remarksCtrl.text,
        subTotal: double.tryParse(_subTotalCtrl.text) ?? 0.0,
        discount: double.tryParse(_footerDiscAmtCtrl.text) ?? 0.0,
        otherCharge: double.tryParse(_otherChargeAmtCtrl.text) ?? 0.0,
        roundOff: double.tryParse(_roundOffCtrl.text) ?? 0.0,
        items: _items.map((it) => PurchaseItem(
          id: it.productId,
          productName: it.productName, batch: it.batch, expiry: it.expiry,
          packin: it.packin, qty: it.qty, fQty: it.fQty, mrp: it.mrp, pRate: it.pRate,
          gross: it.gross, discPercent: it.discPercent, discAmt: it.discAmt, net: it.net,
          gstPercent: it.gstPercent, gstAmt: it.gstAmt, total: it.total, rack: it.rack,
          hsnCode: it.hsncode, sDiscPercent: it.sDiscPercent, sRate: it.sRate, lCost: it.lCost,
        )).toList(),
        grandTotal: _grandTotalNotifier.value,
      );

      if (mounted) setState(() => _isLoading = true);
      await p.savePurchase(entry);
      await p.clearPurchaseDraft();

      // Trigger the native system alert/success sound
      SystemSound.play(SystemSoundType.alert);

      if (!mounted) return;
      _isDirty = false;
      _isAutoGeneratedSupInv = false;
      _resetPage();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Entry Saved"), backgroundColor: Colors.green));
    } catch (e) {
      if (!mounted) return;
      _showFastDialog(title: "Error", content: e.toString());
    } finally {
      _isSaving = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _importExcel() async {
    final p = Provider.of<PharmacyProvider>(context, listen: false);

    ImportMapping? mapping;
    if (_activeFormatName != null && _activeFormatName!.trim().isNotEmpty) {
      String cleanActive = _activeFormatName!
          .replaceAll(' - EXCEL', '')
          .replaceAll(' - PDF', '')
          .trim()
          .toLowerCase();

      // 1. Check for format matching the selected Wholesaler name
      mapping = p.importMappings.cast<ImportMapping?>().firstWhere(
        (m) {
          if (m == null) return false;
          String cleanM = m.name
              .replaceAll(' - EXCEL', '')
              .replaceAll(' - PDF', '')
              .trim()
              .toLowerCase();
          return cleanM == cleanActive;
        },
        orElse: () => null,
      );
    }

    // 2. Fallback to default format if no custom format exists
    mapping ??= ImportMapping.defaultMapping();

    // 3. Open file picker directly without asking for format again
    _pickAndImport(mapping);
  }

  void _showExcelFormatPickerDialog(PharmacyProvider p) {
    final excelMappings = p.importMappings
        .where((m) => m.name.toUpperCase().endsWith('- EXCEL'))
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.table_chart_rounded, color: Colors.green),
            SizedBox(width: 10),
            Text("Select Wholesaler Format", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Different wholesalers have different Excel column formats. Please select the wholesaler format for this file:",
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
              const SizedBox(height: 12),
              if (excelMappings.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "No custom wholesaler Excel formats found. You can create a new mapping for this wholesaler or use the default format.",
                          style: TextStyle(fontSize: 11, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: excelMappings.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final map = excelMappings[index];
                      final displayName = map.name.replaceAll(' - EXCEL', '');
                      final isCurrent = _activeFormatName == displayName;

                      return ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.business_rounded,
                          color: isCurrent ? Colors.green.shade800 : Colors.blueGrey,
                          size: 20,
                        ),
                        title: Text(
                          displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isCurrent ? Colors.green.shade900 : Colors.black87,
                          ),
                        ),
                        subtitle: Text(
                          "${map.fieldMappings.length} columns mapped",
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () {
                          Navigator.pop(ctx);
                          setState(() => _activeFormatName = displayName);
                          _pickAndImport(map);
                        },
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
              const Divider(),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showManualMappingDialog(p);
                    },
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text("Create New Format", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _pickAndImport(ImportMapping.defaultMapping());
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    child: const Text("Use Default Format", style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _pickAndImport(ImportMapping mapping, [String? filePath]) async {
    try {
      String? path = filePath;
      if (path == null) {
        FilePickerResult? result = await FilePicker.pickFiles(
          type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv', 'pdf'],
        );
        if (result != null && result.files.single.path != null) {
          path = result.files.single.path!;
        }
      }

      if (path != null) {
        if (!mounted) return;
        final p = Provider.of<PharmacyProvider>(context, listen: false);

        final file = File(path);
        final fileNameWithExt = file.uri.pathSegments.last;
        final fileNameWithoutExt = fileNameWithExt.contains('.') 
            ? fileNameWithExt.substring(0, fileNameWithExt.lastIndexOf('.')) 
            : fileNameWithExt;

        // Extract invoice text/number after last '-', '_', or '/' from right side
        final cleanSupInv = _extractInvoiceFromFileName(fileNameWithoutExt);

        setState(() {
          // Only auto-fill if supplier invoice number is currently empty
          if (_supInvNoCtrl.text.trim().isEmpty) {
            _supInvNoCtrl.text = cleanSupInv;
            _isAutoGeneratedSupInv = true; // Track that it's auto-filled
          }
        });

        if (path.toLowerCase().endsWith('.pdf')) {
          _importPdfFile(mapping, path);
          return;
        }

        final importedItems = await p.importPurchaseExcel(path, mapping: mapping);

        if (importedItems.isNotEmpty) {
          final unknownItems = importedItems.where((it) => it.id == "UNKNOWN").toList();
          final validItems = importedItems.where((it) => it.id != "UNKNOWN").toList();

          if (unknownItems.isNotEmpty) {
            final Map<String, PurchaseItem> uniqueMap = {};
            for (var item in unknownItems) {
              String key = "${item.externalName.toLowerCase().trim()}|${item.externalCode.trim()}";
              uniqueMap.putIfAbsent(key, () => item);
            }
            final uniqueUnknown = uniqueMap.values.toList();

            if (!mounted) return;
            Provider.of<MdiController>(context, listen: false).openWindow(
              MdiWindow(
                id: "mapping_unknown_${mapping.name}",
                title: "Link Unknown Products (${mapping.name})",
                width: 950,
                height: 650,
                content: ProductMappingDialog(
                  wholesalerName: mapping.name,
                  unknownItems: uniqueUnknown,
                  provider: p,
                  onImportRequested: (mappedItems) {
                    Provider.of<MdiController>(context, listen: false).closeWindow("mapping_unknown_${mapping.name}");
                    _finalizeImportAfterMapping(mappedItems, importedItems, validItems);
                  },
                ),
              ),
            );
            return;
          }

          _finalizeImportAfterMapping(null, importedItems, validItems);
        } else {
          // If auto-detection didn't yield items, open DynamicExcelMappingDialog with prefilled headers
          final excelData = await p.getExcelDataForPreview(path);
          final List<String> headers = (excelData['headers'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

          if (!mounted) return;
          Provider.of<MdiController>(context, listen: false).openWindow(
            MdiWindow(
              id: "auto_mapping_dialog",
              title: "Define Excel Column Mappings",
              width: 600,
              height: 600,
              content: DynamicExcelMappingDialog(
                excelHeaders: headers,
                filePath: path,
                provider: p,
                initialMapping: mapping,
                onImportComplete: (newMapping) async {
                  Provider.of<MdiController>(context, listen: false).closeWindow("auto_mapping_dialog");
                  setState(() => _activeFormatName = newMapping.name.replaceAll(' - EXCEL', '').replaceAll(' - PDF', ''));
                  _pickAndImport(newMapping, path);
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) _showFastDialog(title: "Import Error", content: e.toString());
    }
  }

  String _extractInvoiceFromFileName(String fileNameWithoutExt) {
    String text = fileNameWithoutExt.trim();
    int lastIndex = text.lastIndexOf(RegExp(r'[\-_/]'));
    if (lastIndex != -1 && lastIndex < text.length - 1) {
      text = text.substring(lastIndex + 1);
    }
    return text.replaceAll(RegExp(r'[^a-zA-Z0-9/]'), '').toUpperCase();
  }

  void _importPdfFile([ImportMapping? initialMap, String? pdfPath]) async {
    final p = Provider.of<PharmacyProvider>(context, listen: false);

    String? pickedPath = pdfPath;
    if (pickedPath == null) {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null || result.files.single.path == null) return;
      pickedPath = result.files.single.path!;
    }

    final file = File(pickedPath);
    final fileNameWithExt = file.uri.pathSegments.last;
      final fileNameWithoutExt = fileNameWithExt.contains('.') 
          ? fileNameWithExt.substring(0, fileNameWithExt.lastIndexOf('.')) 
          : fileNameWithExt;

      setState(() {
        if (_supInvNoCtrl.text.trim().isEmpty) {
          final cleanSupInv = _extractInvoiceFromFileName(fileNameWithoutExt);
          _supInvNoCtrl.text = cleanSupInv;
          _isAutoGeneratedSupInv = true;
        }
      });

    ImportMapping? mapping = initialMap;
    if (mapping == null && _activeFormatName != null) {
      mapping = p.importMappings.cast<ImportMapping?>().firstWhere(
        (m) => m?.name == "$_activeFormatName - PDF",
        orElse: () => null,
      );
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PdfVisualMapperDialog(
        currentSupplier: _supplierCtrl.text.trim().isNotEmpty
            ? _supplierCtrl.text.trim()
            : (_activeFormatName ?? ''),
        initialFilePath: pickedPath,
        initialMapping: mapping,
        onImportReady: (newMapping, headers, rows, isSilent) {
          _populateGridFromImportedRows(headers, rows);
        },
      ),
    );
  }

  void _calculateTotals() => _calculateFooter();

  String _sanitizeProductName(String rawName) {
    if (rawName.isEmpty) return "UNKNOWN PRODUCT";
    
    // Remove leading numbers, amounts (e.g. 513.78), or commas
    String cleaned = rawName.replaceAll(RegExp(r'^\d+(\.\d+)?\s*,?\s*'), '');
    
    // Remove store name or common headers if accidentally caught in the text block
    cleaned = cleaned.replaceAll(RegExp(r'SAHAKAR MEDICALS.*', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'GREEN SPECIALITIES.*', caseSensitive: false), '');
    
    // Trim extra spaces and leading symbols
    cleaned = cleaned.replaceAll(RegExp(r'^[\s,.-]+'), '').trim();
    
    return cleaned.isNotEmpty ? cleaned.toUpperCase() : rawName.toUpperCase();
  }

  void _populateGridFromImportedRows(List<String> headers, List<List<dynamic>> rows) async {
    if (rows.isEmpty) return;

    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final String currentSupplier = _supplierCtrl.text.trim().isNotEmpty
        ? _supplierCtrl.text.trim()
        : (_activeFormatName ?? 'General');

    double parseNum(dynamic val) {
      if (val == null) return 0.0;
      String clean = val.toString().replaceAll(RegExp(r'[^0-9.]'), '').trim();
      double parsed = double.tryParse(clean) ?? 0.0;
      return double.parse(parsed.toStringAsFixed(2));
    }

    int parseInt(dynamic val) => parseNum(val).toInt();

    // 1. Parse raw vendor entries
    List<Map<String, dynamic>> parsedEntries = [];
    Set<String> vendorItemsToMap = {};

    for (var row in rows) {
      Map<String, dynamic> rowMap = {};
      for (int i = 0; i < headers.length; i++) {
        if (i < row.length) {
          rowMap[headers[i]] = row[i];
        }
      }

      // Read exclusively from the assigned "Product" header column
      String vendorName = (rowMap['Product'] ?? '').toString().trim();
      if (vendorName.isEmpty) {
        vendorName = (rowMap['Item Name'] ?? rowMap['Particulars'] ?? '').toString().trim();
      }

      // If vendorName is empty or purely numeric (e.g. "307422"), find actual medicine description from rowMap
      if (vendorName.isEmpty || double.tryParse(vendorName) != null || RegExp(r'^\d+$').hasMatch(vendorName)) {
        for (var entry in rowMap.entries) {
          String headerKey = entry.key.trim().toLowerCase();
          if (headerKey.contains('code') || headerKey.contains('id') || headerKey.contains('hsn') || 
              headerKey.contains('batch') || headerKey.contains('mrp') || headerKey.contains('rate') || 
              headerKey.contains('qty') || headerKey.contains('total') || headerKey.contains('amount') ||
              headerKey.contains('disc') || headerKey.contains('gst')) {
            continue; // Skip code/id/hsn/batch/mrp/rate/qty/total/amount/disc/gst columns
          }
          if (headerKey.contains('name') || headerKey.contains('product') || headerKey.contains('description') || headerKey.contains('item') || headerKey.contains('particulars')) {
            String val = entry.value?.toString().trim() ?? "";
            if (val.isNotEmpty && 
                double.tryParse(val) == null && 
                val.length < 45 && 
                !val.contains(',') && 
                !val.toLowerCase().contains('sahakar') && 
                !val.toLowerCase().contains('total') && 
                RegExp(r'[a-zA-Z]').hasMatch(val)) {
              vendorName = val;
              break;
            }
          }
        }
      }

      // Fallback if no explicit text header matched: pick the first non-numeric text column
      if (vendorName.isEmpty || double.tryParse(vendorName) != null || RegExp(r'^\d+$').hasMatch(vendorName)) {
        vendorName = rowMap.values.firstWhere(
          (v) => v != null && 
                 v.toString().trim().isNotEmpty && 
                 double.tryParse(v.toString().trim()) == null && 
                 v.toString().trim().length < 45 &&
                 !v.toString().contains(',') &&
                 !v.toString().toLowerCase().contains('sahakar') &&
                 !v.toString().toLowerCase().contains('total') &&
                 RegExp(r'[a-zA-Z]').hasMatch(v.toString()),
          orElse: () => vendorName.isNotEmpty ? vendorName : "UNKNOWN ITEM",
        ).toString().trim();
      }

      vendorName = _sanitizeProductName(vendorName);

      String vendorCode = (rowMap['Product Code'] ?? rowMap['Code'] ?? rowMap['Item Code'] ?? '').toString().trim();

      // Discard buyer/header lines
      String lowerV = vendorName.toLowerCase();
      if (lowerV.contains('sahakar') ||
          lowerV.contains('customer') ||
          lowerV.contains('grand total') ||
          lowerV.contains('sub total') ||
          lowerV.isEmpty) {
        continue;
      }

      // Strip leading price or rate artifacts if combined into one column
      if (vendorName.contains(',') && RegExp(r'^\d+(\.\d+)?\s*,').hasMatch(vendorName)) {
        vendorName = vendorName.substring(vendorName.indexOf(',') + 1).trim();
      }

      vendorItemsToMap.add(vendorName);
      parsedEntries.add(rowMap);
    }

    if (parsedEntries.isEmpty) return;

    // 2. Check and prompt Product Mapping Dialog for unknown wholesaler descriptions
    Map<String, ProductMapping> resolvedMappings = {};
    for (String vName in vendorItemsToMap) {
      final matchingRow = parsedEntries.firstWhere(
        (r) => (r['Product'] ?? r['Item'] ?? r['Description'] ?? r['Particulars'] ?? '').toString().trim() == vName,
        orElse: () => {},
      );
      String vCode = (matchingRow['Product Code'] ?? matchingRow['Code'] ?? '').toString().trim();

      ProductMapping? mappingObj = p.findProductMapping(currentSupplier, vName, vCode);
      if (mappingObj != null) {
        resolvedMappings[vName] = mappingObj;
      }
    }

    List<String> unmappedList = vendorItemsToMap.where((name) => !resolvedMappings.containsKey(name)).toList();
    List<PurchaseItem>? userMappedItems;

    if (unmappedList.isNotEmpty) {
      final List<PurchaseItem> unknownItems = unmappedList.map((name) {
        final matchingRow = parsedEntries.firstWhere(
          (r) => (r['Product'] ?? r['Item'] ?? r['Description'] ?? r['Particulars'] ?? '').toString().trim() == name,
          orElse: () => {},
        );

        dynamic rawCode;
        dynamic rawBatch;
        dynamic rawMrp;

        for (var entry in matchingRow.entries) {
          String k = entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (rawCode == null && (k.contains('code') || k.contains('id'))) {
            rawCode = entry.value;
          }
          if (rawBatch == null && k.contains('batch')) {
            rawBatch = entry.value;
          }
          if (rawMrp == null && k.contains('mrp')) {
            rawMrp = entry.value;
          }
        }

        String code = (rawCode ?? matchingRow['Product Code'] ?? matchingRow['Code'] ?? '').toString().trim();
        String batch = (rawBatch ?? matchingRow['Batch'] ?? matchingRow['Batch No'] ?? '').toString().trim();
        double mrpVal = parseNum(rawMrp ?? matchingRow['Mrp'] ?? matchingRow['MRP']);

        return PurchaseItem(
          productName: name,
          externalName: name,
          externalCode: code,
          batch: batch,
          mrp: mrpVal,
          id: "UNKNOWN",
        );
      }).toList();

      bool? mappingDone = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ProductMappingDialog(
            wholesalerName: currentSupplier,
            unknownItems: unknownItems,
            provider: p,
            onImportRequested: (mapped) {
              userMappedItems = mapped;
            },
          ),
        ),
      );

      if (mappingDone != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Import canceled: Product mapping not completed."), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      for (String vName in vendorItemsToMap) {
        final matchingRow = parsedEntries.firstWhere(
          (r) => (r['Product'] ?? r['Item'] ?? r['Description'] ?? r['Particulars'] ?? '').toString().trim() == vName,
          orElse: () => {},
        );
        String vCode = (matchingRow['Product Code'] ?? matchingRow['Code'] ?? '').toString().trim();

        ProductMapping? mappingObj = p.findProductMapping(currentSupplier, vName, vCode);
        if (mappingObj != null) {
          resolvedMappings[vName] = mappingObj;
        }
      }
    }

    // 3. Build PurchaseItem entries using resolved Master Product names
    List<PurchaseItemData> newItems = [];

    for (var rowMap in parsedEntries) {
      String rawVendorName = (rowMap['Product'] ?? rowMap['Item'] ?? rowMap['Description'] ?? rowMap['Particulars'] ?? '').toString().trim();
      String rawVendorCode = (rowMap['Product Code'] ?? rowMap['Code'] ?? '').toString().trim();

      ProductMapping? mappingObj = resolvedMappings[rawVendorName] ?? p.findProductMapping(currentSupplier, rawVendorName, rawVendorCode);
      Product? matchedProduct;

      if (mappingObj != null) {
        if (mappingObj.productId.isNotEmpty) {
          matchedProduct = p.productMaster.cast<Product?>().firstWhere(
            (pm) => pm?.id == mappingObj.productId,
            orElse: () => null,
          );
        }
        if (matchedProduct == null && mappingObj.internalName.isNotEmpty) {
          String cleanInternal = mappingObj.internalName.trim().toUpperCase();
          matchedProduct = p.productMaster.cast<Product?>().firstWhere(
            (pm) => pm?.name.trim().toUpperCase() == cleanInternal,
            orElse: () => null,
          );
        }
      }

      if (matchedProduct == null && userMappedItems != null) {
        final userMapped = userMappedItems!.cast<PurchaseItem?>().firstWhere(
          (m) {
            if (m == null) return false;
            String norm(String s) => s.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
            return norm(m.externalName) == norm(rawVendorName) || (m.externalCode.isNotEmpty && m.externalCode == rawVendorCode);
          },
          orElse: () => null,
        );
        if (userMapped != null && userMapped.productName.isNotEmpty) {
          String cleanName = userMapped.productName.trim().toUpperCase();
          matchedProduct = p.productMaster.cast<Product?>().firstWhere(
            (pm) => pm?.id == userMapped.id || pm?.name.trim().toUpperCase() == cleanName,
            orElse: () => null,
          );
        }
      }

      if (matchedProduct == null && rawVendorName.isNotEmpty) {
        String cleanRaw = rawVendorName.trim().toUpperCase();
        matchedProduct = p.productMaster.cast<Product?>().firstWhere(
          (pm) => pm?.name.trim().toUpperCase() == cleanRaw,
          orElse: () => null,
        );
      }

      String resolvedProductName = matchedProduct?.name ??
          (mappingObj?.internalName.isNotEmpty == true ? mappingObj!.internalName : rawVendorName);
      String resolvedProductId = matchedProduct?.id ?? (mappingObj?.productId ?? "");

      int qty = parseInt(rowMap['Qty']);
      int fqty = parseInt(rowMap['Fqty']);
      if (qty <= 0 && fqty <= 0) qty = 1;
      double prate = parseNum(rowMap['Prate'] ?? rowMap['Rate'] ?? rowMap['P.Rate']);
      double mrp = parseNum(rowMap['Mrp'] ?? rowMap['MRP'] ?? rowMap['M.R.P']);
      if (mrp <= 0) mrp = matchedProduct != null && matchedProduct.mrp > 0 ? matchedProduct.mrp : prate;
      int pack = parseInt(rowMap['Packing'] ?? rowMap['Pack']);
      if (pack <= 0) pack = matchedProduct != null && matchedProduct.packSize > 0 ? matchedProduct.packSize : 1;

      double gross = prate * qty;

      // Discount Sync
      double discPercent = parseNum(rowMap['Disc %'] ?? rowMap['DisPer'] ?? rowMap['Discount %']);
      double discAmt = parseNum(rowMap['Disc Amt'] ?? rowMap['DiscAmt'] ?? rowMap['Disc'] ?? rowMap['Discount']);
      if (discAmt > 0 && discPercent == 0 && gross > 0) {
        discPercent = double.parse(((discAmt / gross) * 100.0).toStringAsFixed(2));
      } else if (discPercent > 0 && discAmt == 0 && gross > 0) {
        discAmt = double.parse((gross * (discPercent / 100.0)).toStringAsFixed(2));
      }

      double net = gross - discAmt;
      if (net < 0) net = 0.0;

      // GST Sync
      double cgstPercent = parseNum(rowMap['CGST %'] ?? rowMap['CGST']);
      double sgstPercent = parseNum(rowMap['SGST %'] ?? rowMap['SGST']);
      double gstPercent = 0.0;

      if (cgstPercent > 0 && sgstPercent > 0) {
        gstPercent = TaxCalculator.roundGstPercent(cgstPercent + sgstPercent);
      } else if (cgstPercent > 0) {
        gstPercent = TaxCalculator.roundGstPercent(cgstPercent * 2);
      } else if (sgstPercent > 0) {
        gstPercent = TaxCalculator.roundGstPercent(sgstPercent * 2);
      } else {
        gstPercent = TaxCalculator.roundGstPercent(parseNum(rowMap['GST %'] ?? rowMap['TaxPer (Total)'] ?? rowMap['GST'] ?? rowMap['Tax %']));
      }

      if (gstPercent <= 0 && matchedProduct != null && matchedProduct.gstPercent > 0) {
        gstPercent = matchedProduct.gstPercent;
      }
      double gstAmt = parseNum(rowMap['GST Amt'] ?? rowMap['GSTAmt']);
      double cgstAmt = parseNum(rowMap['CGST Amt']);
      double sgstAmt = parseNum(rowMap['SGST Amt']);
      if (cgstAmt > 0 || sgstAmt > 0) gstAmt = cgstAmt + sgstAmt;

      if (gstAmt > 0 && gstPercent == 0 && net > 0) {
        gstPercent = TaxCalculator.roundGstPercent(double.parse(((gstAmt / net) * 100.0).toStringAsFixed(2)));
      } else if (gstPercent > 0 && gstAmt == 0 && net > 0) {
        gstAmt = double.parse((net * (gstPercent / 100.0)).toStringAsFixed(2));
      }

      // Scheme Discount Sync
      double sDiscPercent = parseNum(rowMap['S.Disc %'] ?? rowMap['SDisc%']);
      if (sDiscPercent <= 0 && matchedProduct != null && matchedProduct.sDiscPercent > 0) {
        sDiscPercent = matchedProduct.sDiscPercent;
      }
      double sDiscAmt = parseNum(rowMap['S.Amt'] ?? rowMap['SAmt']);
      if (sDiscAmt > 0 && sDiscPercent == 0 && net > 0) {
        sDiscPercent = double.parse(((sDiscAmt / net) * 100.0).toStringAsFixed(2));
      } else if (sDiscPercent > 0 && sDiscAmt == 0 && net > 0) {
        sDiscAmt = double.parse((net * (sDiscPercent / 100.0)).toStringAsFixed(2));
      }

      String rackVal = (rowMap['Rack'] ?? '').toString();
      if (rackVal.isEmpty && matchedProduct != null && matchedProduct.rack.isNotEmpty) {
        rackVal = matchedProduct.rack;
      }
      String hsnVal = (rowMap['Product Code'] ?? rowMap['Code'] ?? rowMap['HSN'] ?? '').toString();
      if (hsnVal.isEmpty && matchedProduct != null && matchedProduct.hsnCode.isNotEmpty) {
        hsnVal = matchedProduct.hsnCode;
      }

      final it = PurchaseItemData()
        ..productId = resolvedProductId
        ..productName = resolvedProductName
        ..batch = (rowMap['Batch'] ?? '').toString()
        ..hsncode = hsnVal
        ..expiry = (rowMap['Exp'] ?? rowMap['Expiry'] ?? '--/--').toString()
        ..qty = qty
        ..fQty = fqty
        ..packin = pack
        ..pRate = prate
        ..mrp = mrp
        ..discPercent = discPercent
        ..discAmt = discAmt
        ..gstPercent = gstPercent
        ..gstAmt = gstAmt
        ..sDiscPercent = sDiscPercent
        ..sDiscAmt = sDiscAmt
        ..rack = rackVal;

      it.recalculate(isGstMode: _gstMode == 1);
      it.syncControllers();
      newItems.add(it);
    }

    if (newItems.isNotEmpty) {
      setState(() {
        _resetGridAndInvoiceFieldsForImport();

        if (_activeFormatName != null && _activeFormatName!.trim().isNotEmpty) {
          _supplierCtrl.text = _activeFormatName!;
        }

        for (var item in newItems) {
          _discountInteractedRows.add(item.uuid);
          _items.add(item);
        }

        for (int i = 0; i < _items.length; i++) {
          _calculateItem(i);
        }

        _isDirty = true;
        _calculateTotals();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Imported ${newItems.length} mapped products into Purchase Grid!"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _processPastedClipboardData() async {
    try {
      ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null && data.text!.trim().isNotEmpty) {
        final text = data.text!.trim();
        final rows = text.split(RegExp(r'\r?\n')).where((r) => r.trim().isNotEmpty).toList();
        if (rows.isNotEmpty) {
          final delimiter = text.contains('\t') ? '\t' : (text.contains(',') ? ',' : '');
          if (delimiter.isNotEmpty && rows[0].split(delimiter).length >= 2) {
            _processRawPastedText(text);
            return;
          }
        }
      }
      _showManualPasteWindow();
    } catch (e) {
      _showManualPasteWindow();
    }
  }

  void _showManualPasteWindow() {
    final p = Provider.of<PharmacyProvider>(context, listen: false);

    Provider.of<MdiController>(context, listen: false).openWindow(
      MdiWindow(
        id: "manual_paste_window",
        title: "Manual Excel Paste & Table Preview",
        width: 950,
        height: 650,
        content: ManualPasteTableWidget(
          provider: p,
          onImport: (newItems) {
            Provider.of<MdiController>(context, listen: false).closeWindow("manual_paste_window");
            if (newItems.isNotEmpty) {
              setState(() {
                if (_items.length == 1 && _items.first.productName.isEmpty) {
                  _items.clear();
                  _items.addAll(newItems);
                } else {
                  _items.addAll(newItems);
                }
                _isDirty = true;
                _calculateTotals();
              });

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Imported ${newItems.length} products into Purchase Grid!"),
                  backgroundColor: Colors.green,
                ),
              );
            }
          },
          onCancel: () {
            Provider.of<MdiController>(context, listen: false).closeWindow("manual_paste_window");
          },
        ),
      ),
    );
  }

  void _importPastedRows(ImportMapping mapping, List<String> headers, List<List<dynamic>> dataRows) async {
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    List<PurchaseItem> items = [];


    String cleanWholesalerName = (mapping.name.isEmpty || mapping.name == "Default")
        ? (_activeFormatName ?? "General")
        : mapping.name.replaceAll(' - PDF', '').replaceAll(' - EXCEL', '').trim().toUpperCase();

    final wholesalerMappings = p.productMappings.where((m) {
      String baseName = m.wholesalerName.replaceAll(' - PDF', '').replaceAll(' - EXCEL', '').trim().toUpperCase();
      return baseName == cleanWholesalerName;
    }).toList();

    final codeToMappingMap = {
      for (var m in wholesalerMappings)
        if (m.externalCode.isNotEmpty)
          m.externalCode.trim().toUpperCase(): m
    };
    final nameToMappingMap = {
      for (var m in wholesalerMappings)
        m.externalName.trim().toUpperCase(): m
    };

    final productIdMap = {for (var p in p.productMaster) p.id: p};
    final productNameMap = {for (var p in p.productMaster) p.name.trim().toUpperCase(): p};

    for (var row in dataRows) {
      if (row.isEmpty) continue;

      String extract(String appField) {
        List<String> keywords = [];
        if (mapping.fieldMappings.containsKey(appField) && mapping.fieldMappings[appField]!.isNotEmpty) {
          keywords.addAll(mapping.fieldMappings[appField]!);
        }
        final defaultKw = ImportMapping.defaultMapping().fieldMappings[appField];
        if (defaultKw != null) {
          for (var d in defaultKw) {
            if (!keywords.contains(d)) keywords.add(d);
          }
        }

        for (var k in keywords) {
          final cleanK = k.toLowerCase().replaceAll(RegExp(r'[\s._%\-]'), '');
          if (cleanK.isEmpty) continue;

          int colIdx = headers.indexWhere((h) {
            final rawH = h.trim().toLowerCase();
            if (appField == 'Mrp' && (rawH.contains('vaton') || rawH.contains('vat_on') || rawH.contains('tax_on') || rawH.contains('taxonsch') || rawH.contains('discon'))) {
              return false;
            }
            if (appField == 'Product') {
              if (rawH.contains('code') || 
                  rawH.contains('id') || 
                  rawH.contains('party') || 
                  rawH.contains('customer') || 
                  rawH.contains('buyer')) {
                return false;
              }
            }
            final cleanH = h.toLowerCase().replaceAll(RegExp(r'[\r\n\s._%\-]'), '');
            return cleanH == cleanK || (cleanH.isNotEmpty && (cleanH.startsWith(cleanK) || cleanK.startsWith(cleanH)));
          });
          if (colIdx != -1 && colIdx < row.length) {
            String val = row[colIdx]?.toString().trim() ?? "";
            if (val.isNotEmpty) return val;
          }
        }
        return "";
      }

      String rawProductName = extract('Product');
      String rawProductCode = extract('Product Code');
      if (rawProductName.isEmpty && rawProductCode.isEmpty && extract('Batch').isEmpty) continue;

      ProductMapping? foundMapping = p.findProductMapping(cleanWholesalerName, rawProductName, rawProductCode);
      Product? matchedProduct;

      if (foundMapping != null) {
        if (foundMapping.productId.isNotEmpty) {
          matchedProduct = productIdMap[foundMapping.productId];
        }
        if (matchedProduct == null && foundMapping.internalName.isNotEmpty) {
          matchedProduct = productNameMap[foundMapping.internalName.trim().toUpperCase()];
        }

        if (foundMapping.externalCode.isEmpty && rawProductCode.isNotEmpty) {
          p.saveProductMapping(ProductMapping(
            id: foundMapping.id,
            wholesalerName: foundMapping.wholesalerName,
            externalCode: rawProductCode,
            externalName: foundMapping.externalName,
            internalName: foundMapping.internalName,
            productId: foundMapping.productId,
          ));
        }
      }

      if (matchedProduct == null && rawProductName.isNotEmpty) {
        matchedProduct = productNameMap[rawProductName.trim().toUpperCase()];
      }

      double parseDouble(String v) => double.tryParse(v.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
      int parseInt(String v) => double.tryParse(v.replaceAll(RegExp(r'[^0-9.]'), ''))?.toInt() ?? 0;

      double totalTax = parseDouble(extract('TaxPer (Total)'));
      double cgst = parseDouble(extract('CGST'));
      double sgst = parseDouble(extract('SGST'));

      double finalGstPercent = totalTax;
      if (cgst > 0 && sgst > 0) {
        finalGstPercent = TaxCalculator.roundGstPercent(cgst + sgst);
      } else if (cgst > 0) {
        finalGstPercent = TaxCalculator.roundGstPercent(cgst * 2);
      } else if (sgst > 0) {
        finalGstPercent = TaxCalculator.roundGstPercent(sgst * 2);
      }

      String resolvedProductId = "UNKNOWN";
      String resolvedProductName = rawProductName;
      int resolvedPackin = parseInt(extract('Packing'));
      double resolvedGst = finalGstPercent;
      double resolvedSDisc = parseDouble(extract('Sdisc'));
      String resolvedRack = "";
      String resolvedHsn = extract('HSN');

      if (matchedProduct != null) {
        resolvedProductId = matchedProduct.id;
        resolvedProductName = matchedProduct.name;
        if (resolvedPackin <= 0) resolvedPackin = matchedProduct.packSize;
        if (resolvedGst <= 0) resolvedGst = matchedProduct.gstPercent;
        if (resolvedSDisc <= 0) resolvedSDisc = matchedProduct.sDiscPercent;
        resolvedRack = matchedProduct.rack;
        if (resolvedHsn.isEmpty) resolvedHsn = matchedProduct.hsnCode;
      } else if (foundMapping != null && foundMapping.productId.isNotEmpty) {
        resolvedProductId = foundMapping.productId;
        resolvedProductName = foundMapping.internalName.trim().isNotEmpty ? foundMapping.internalName.trim() : rawProductName;
      } else if (foundMapping != null && foundMapping.internalName.trim().isNotEmpty) {
        resolvedProductName = foundMapping.internalName.trim();
      }

      double extractedMrp = parseDouble(extract('Mrp'));
      if (extractedMrp <= 0 && matchedProduct != null && matchedProduct.mrp > 0) {
        extractedMrp = matchedProduct.mrp;
      }

      items.add(PurchaseItem(
        id: resolvedProductId,
        productName: resolvedProductName.isNotEmpty ? resolvedProductName : (rawProductCode.isNotEmpty ? "CODE: $rawProductCode" : "BATCH: ${extract('Batch')}"),
        externalName: rawProductName,
        externalCode: rawProductCode,
        batch: extract('Batch'),
        expiry: extract('Exp'),
        qty: parseInt(extract('Qty')),
        fQty: parseInt(extract('Fqty')),
        pRate: parseDouble(extract('Prate')),
        mrp: extractedMrp,
        discPercent: parseDouble(extract('DisPer')),
        gstPercent: TaxCalculator.roundGstPercent(resolvedGst > 0 ? resolvedGst : 12.0),
        sDiscPercent: resolvedSDisc,
        packin: resolvedPackin > 0 ? resolvedPackin : 1,
        hsnCode: resolvedHsn,
        rack: resolvedRack,
      ));
    }

    if (items.isEmpty) {
      _showFastDialog(title: "Import", content: "No items could be mapped.");
      return;
    }

    final unknownItems = items.where((it) => it.id == "UNKNOWN").toList();
    final validItems = items.where((it) => it.id != "UNKNOWN").toList();

    if (unknownItems.isNotEmpty) {
      final Map<String, PurchaseItem> uniqueMap = {};
      for (var item in unknownItems) {
        String key = "${item.externalName.toLowerCase().trim()}|${item.externalCode.trim()}";
        uniqueMap.putIfAbsent(key, () => item);
      }
      final uniqueUnknown = uniqueMap.values.toList();

      if (!mounted) return;
      Provider.of<MdiController>(context, listen: false).openWindow(
        MdiWindow(
          id: "mapping_unknown_pasted_$cleanWholesalerName",
          title: "Link Unknown Products ($cleanWholesalerName)",
          width: 950,
          height: 650,
          content: ProductMappingDialog(
            wholesalerName: cleanWholesalerName,
            unknownItems: uniqueUnknown,
            provider: p,
            onImportRequested: (mappedItems) {
              Provider.of<MdiController>(context, listen: false).closeWindow("mapping_unknown_pasted_$cleanWholesalerName");
              _finalizeImportAfterMapping(mappedItems, items, validItems);
            },
          ),
        ),
      );
      return;
    }

    _finalizeImportAfterMapping(null, items, validItems);
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

    String nextNo = await p.getNextPurchaseEntryNo();

    if (mounted) {
      setState(() {
        _isExistingEntry = false;
        _isDeleted = false;
        _isDirty = false; // Reset dirty flag
        _hasResolvedGstMismatches = false;
        _isAutoGeneratedSupInv = false;
        _originalLoadedEntry = null; // Clear audit snapshot
        
        _entryNoCtrl.text = nextNo;

        _items.clear();
        _errorCells.clear();
        _discountInteractedRows.clear();
        _nextItem = PurchaseItemData();

        _supplierCtrl.clear();
        _doneByCtrl.clear();
        _supInvNoCtrl.clear();
        _invTotalCtrl.clear();
        _remarksCtrl.clear();
        _poNoCtrl.clear();

        _footerDiscPctCtrl.text = "0";
        _footerDiscAmtCtrl.text = "0.00";
        _otherChargePctCtrl.text = "0";
        _otherChargeAmtCtrl.text = "0.00";
        _lessCrNoteCtrl.text = "0.00";
        _calculateFooter();
      });
      _moveFocus(-1, 0);
    }
  }

  void _closeAllDropdowns() {
    _searchList.value = [];
    _batchList.value = [];
    _supplierSearchList.value = [];
    _doneBySearchList.value = [];
    _searchIdx.value = 0;
    _isSelectingFromDropdown = false;
  }

  void _navigateEntry(String dir) async {
    // ---> THE FIX: Protect against losing unsaved edits <---
    if (_isExistingEntry && _isDirty) {
      bool? discard = await _promptDiscardChanges();
      if (discard != true) return; // User chose to stay
    }

    // ---> THE FIX: Kill dropdowns before navigating <---
    _closeAllDropdowns();

    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final data = await p.navigateInvoice(_entryNoCtrl.text, dir, isPurchase: true);
    if (data != null) {
      _loadPurchaseData(data['entry_no'].toString());
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

  void _showJumpToEntryDialog() {
    final TextEditingController jumpCtrl = TextEditingController(text: _entryNoCtrl.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Go to Purchase Entry", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 260,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Enter Entry No or Supplier Inv No:", style: TextStyle(fontSize: 12)),
              const SizedBox(height: 10),
              TextField(
                controller: jumpCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  hintText: "e.g. 100, PUR-1, or Inv No",
                ),
                onSubmitted: (val) {
                  Navigator.pop(ctx);
                  if (val.trim().isNotEmpty) _loadPurchaseData(val.trim());
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (jumpCtrl.text.trim().isNotEmpty) _loadPurchaseData(jumpCtrl.text.trim());
            },
            child: const Text("GO"),
          ),
        ],
      ),
    );
  }

  void _loadPurchaseData(String invNo) async {
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final data = await p.navigateInvoice(invNo, 'find', isPurchase: true);

    // 1. If data is found AND not deleted
    if (data != null && data['is_deleted'] != 1) {
      final items = await p.getInvoiceItems(data['entry_no'], isPurchase: true);
      setState(() {
        _isExistingEntry = true;
        _isDeleted = false; // Mark active
        _isAutoGeneratedSupInv = false;

        String rawEntry = data['entry_no']?.toString() ?? invNo;
        if (rawEntry.contains('_')) {
          rawEntry = rawEntry.substring(rawEntry.indexOf('_') + 1);
        }
        _entryNoCtrl.text = rawEntry;
        _date = DateTime.tryParse(data['date']) ?? DateTime.now();
        _supplierCtrl.text = data['supplier_name'] ?? "";
        _supInvNoCtrl.text = cleanInvoiceNo(data['sup_inv_no']);
        _doneByCtrl.text = data['done_by'] ?? "";
        _invTotalCtrl.text = data['inv_total']?.toString() ?? "";
        _remarksCtrl.text = data['remarks'] ?? "";

        for (var it in _items) {
          it.dispose();
        }
        _nextItem.dispose();

        _items.clear();
        _discountInteractedRows.clear();
        _nextItem = PurchaseItemData();

        for (var m in items) {
          // CALCULATE CONSUMPTION ON LOAD
          int dbQty = int.tryParse(m['qty']?.toString() ?? "0") ?? 0;
          int dbFQty = int.tryParse(m['f_qty']?.toString() ?? "0") ?? 0;
          int dbPackin = int.tryParse(m['packin']?.toString() ?? "1") ?? 1;

          int originalLoose = (dbQty + dbFQty) * dbPackin;
          int currentStock = p.products.firstWhere(
                  (prod) => prod.id == m['product_id'] && prod.batch == m['batch'],
              orElse: () => Product(id: "", name: "", batch: "", stock: 0)
          ).stock;

          int consumed = originalLoose - currentStock;
          bool consumedFlag = consumed > 0;
          int minReq = consumedFlag ? (consumed / dbPackin).ceil() : 0;

          final it = PurchaseItemData()
            ..isConsumed = consumedFlag
            ..consumedLooseUnits = consumed
            ..minStripsRequired = minReq
            ..productId = m['product_id']?.toString() ?? ""
            ..productName = m['product_name'] ?? ""
            ..batch = m['batch'] ?? ""
            ..rack = (m['rack']?.toString() ?? "").isNotEmpty ? m['rack'] : (m['master_rack']?.toString() ?? "")
            ..hsncode = (m['hsn_code']?.toString() ?? "").isNotEmpty ? m['hsn_code'] : (m['master_hsn']?.toString() ?? "")
            ..expiry = m['expiry'] ?? ""
            ..packin = dbPackin
            ..qty = dbQty
            ..fQty = dbFQty
            ..mrp = double.tryParse(m['mrp']?.toString() ?? "0") ?? 0.0
            ..pRate = double.tryParse(m['p_rate']?.toString() ?? "0") ?? 0.0
            ..sRate = double.tryParse(m['s_rate']?.toString() ?? "0") ?? 0.0
            ..lCost = double.tryParse(m['l_cost']?.toString() ?? "0") ?? 0.0
            ..discPercent = double.tryParse(m['disc_percent']?.toString() ?? "0") ?? 0.0
            ..sDiscPercent = (double.tryParse(m['s_disc_percent']?.toString() ?? "0") ?? 0.0) != 0.0
                ? (double.tryParse(m['s_disc_percent']?.toString() ?? "0") ?? 0.0)
                : (double.tryParse(m['master_s_disc']?.toString() ?? "0") ?? 0.0)
            ..gstPercent = TaxCalculator.roundGstPercent(double.tryParse(m['gst_percent']?.toString() ?? "0") ?? 0.0);

          it.recalculate(isGstMode: _gstMode == 1);
          it.syncControllers();

          if (it.discPercent != 0) {
            _discountInteractedRows.add(it.uuid);
          }
          _items.add(it);
        }
        _isBulkUpdating = true;
        for (int i = 0; i < _items.length; i++) {
          _calculateItem(i);
        }
        _isBulkUpdating = false;
        _calculateFooter();

        // Snapshot the original entry for audit logging
        _originalLoadedEntry = PurchaseEntry(
          entryNo: _entryNoCtrl.text,
          date: _date,
          supplierName: _supplierCtrl.text.trim(),
          supInvNo: _supInvNoCtrl.text.trim(),
          supInvDate: _supInvDate,
          doneBy: _doneByCtrl.text.trim(),
          remarks: _remarksCtrl.text.trim(),
          discount: double.tryParse(_footerDiscAmtCtrl.text) ?? 0.0,
          otherCharge: double.tryParse(_otherChargeAmtCtrl.text) ?? 0.0,
          items: _items.where((it) => it.productName.trim().isNotEmpty).map((it) => PurchaseItem(
            id: it.productId,
            productName: it.productName,
            batch: it.batch,
            expiry: it.expiry,
            packin: it.packin,
            qty: it.qty,
            fQty: it.fQty,
            mrp: it.mrp,
            pRate: it.pRate,
            discPercent: it.discPercent,
            discAmt: it.discAmt,
            gstPercent: it.gstPercent,
            total: it.total,
            sRate: it.sRate,
            lCost: it.lCost,
            rack: it.rack,
            hsnCode: it.hsncode,
          )).toList(),
          grandTotal: _grandTotalNotifier.value,
        );
      });
    }
      // 2. THE FIX: Handle Deleted / Null Purchase Entries
      else if (mounted) {
        FocusScope.of(context).unfocus();
        if (data == null) {
          setState(() {
            _isExistingEntry = true;
            _isDeleted = true; // Lock UI because it doesn't exist
            _entryNoCtrl.text = invNo;

            for (var it in _items) {
              it.dispose();
            }
            _nextItem.dispose();
            _items.clear();
            _nextItem = PurchaseItemData();
            _discountInteractedRows.clear();
            _supplierCtrl.clear();
            _doneByCtrl.clear();
            _supInvNoCtrl.clear();
            _invTotalCtrl.clear();
            _remarksCtrl.clear();
            _poNoCtrl.clear();
            _footerDiscPctCtrl.text = "0";
            _footerDiscAmtCtrl.text = "0.00";
            _otherChargePctCtrl.text = "0";
            _otherChargeAmtCtrl.text = "0.00";
            _lessCrNoteCtrl.text = "0.00";
            _calculateFooter();
          });
          _showFastDialog(title: "Not Found", content: "Entry #$invNo does not exist.");
        } else {
          // DELETED ENTRY DETECTED! LET THEM REUSE THE NUMBER!
          setState(() {
            _isExistingEntry = true; // Crucial: so save overwrites this number!
            _isDeleted = false; // UNLOCKED!
            _isDirty = false;
            _entryNoCtrl.text = invNo;
            
            for (var it in _items) {
              it.dispose();
            }
            _nextItem.dispose();
            _items.clear();
            _nextItem = PurchaseItemData();
            _discountInteractedRows.clear();
            _supplierCtrl.clear();
            _doneByCtrl.clear();
            _supInvNoCtrl.clear();
            _invTotalCtrl.clear();
            _remarksCtrl.clear();
            _poNoCtrl.clear();
            _footerDiscPctCtrl.text = "0";
            _footerDiscAmtCtrl.text = "0.00";
            _otherChargePctCtrl.text = "0";
            _otherChargeAmtCtrl.text = "0.00";
            _lessCrNoteCtrl.text = "0.00";
            _calculateFooter();
          });
          
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Reusing Deleted Entry #$invNo"),
            backgroundColor: Colors.blue.shade800,
            duration: const Duration(seconds: 2),
          ));
          _moveFocus(-1, 0); // Start cursor at Supplier
        }
      }
  }

  void _showFastDialog({required String title, required String content}) {
    AppDialogs.showFastDialog(context: context, title: title, content: content);
  }

  void _showFindDialog() {
    final TextEditingController findCtrl = TextEditingController();
    final FocusNode findFocusNode = FocusNode();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Find Purchase Entry"),
        content: TextField(
          controller: findCtrl, focusNode: findFocusNode, autofocus: true,
          keyboardType: TextInputType.text,
          decoration: const InputDecoration(hintText: "Enter Entry No..."),
          onSubmitted: (v) { Navigator.pop(ctx, v); },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, findCtrl.text), child: const Text("SEARCH")),
        ],
      ),
    ).then((val) {
      if (val != null && val.toString().isNotEmpty) _loadPurchaseData(val.toString());
    });
  }

  void _showDeleteConfirm() async {
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final entry = p.purchases.cast<PurchaseEntry?>().firstWhere((e) => e?.entryNo == _entryNoCtrl.text, orElse: () => null);

    if (entry != null) {
      final error = p.canDeletePurchase(entry);
      if (error != null) {
        _showFastDialog(title: "Delete Blocked", content: error);
        return;
      }
    }

    // 1. SECURITY CHECK: PIN for Deleting
    if (p.securityToggles['require_pin_delete_purchases'] == true) {
      bool isUnlocked = await PinUnlockDialog.show(
          context,
          p,
          title: "Confirm Deletion",
          message: "Enter Master Password to permanently delete Purchase Entry ${_entryNoCtrl.text}."
      );
      if (!isUnlocked) return;
    }

    // PREVIOUS DAY LOCK CHECK REMOVED AS PER USER REQUEST

    final res = await AppDialogs.showConfirmDialog(
      context: context,
      title: "Delete Entry?",
      content: "Are you sure you want to delete Purchase Entry ${_entryNoCtrl.text}?",
      isDangerous: true,
    );

    if (res == true) {
      await p.deletePurchase(_entryNoCtrl.text);
      p.logAudit('DELETE_PURCHASE', 'Purchase Entry ${_entryNoCtrl.text} deleted by ${_doneByCtrl.text.isNotEmpty ? _doneByCtrl.text : "Admin"}.', userId: _doneByCtrl.text.isNotEmpty ? _doneByCtrl.text : "Admin");
      _resetPage();
    }
  }

  void _printPurchase() {
    _exportToPdf();
  }

  void _exportToPdf() async {
    if (_items.isEmpty) return;
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);

    final entry = PurchaseEntry(
      entryNo: _entryNoCtrl.text.isEmpty ? "DRAFT" : _entryNoCtrl.text,
      date: _date,
      supplierName: _supplierCtrl.text,
      supInvNo: cleanInvoiceNo(_supInvNoCtrl.text),
      supInvDate: _supInvDate,
      items: _items.where((it) => it.productName.isNotEmpty).map((it) => PurchaseItem(
        id: it.productId,
        productName: it.productName, batch: it.batch, expiry: it.expiry,
        packin: it.packin, qty: it.qty, fQty: it.fQty, mrp: it.mrp, pRate: it.pRate,
        gross: it.gross, discPercent: it.discPercent, discAmt: it.discAmt, net: it.net,
        gstPercent: it.gstPercent, gstAmt: it.gstAmt, total: it.total, rack: it.rack,
        hsnCode: it.hsncode, sDiscPercent: it.sDiscPercent, sRate: it.sRate, lCost: it.lCost,
      )).toList(),
      subTotal: double.tryParse(_subTotalCtrl.text) ?? 0.0,
      discount: double.tryParse(_footerDiscAmtCtrl.text) ?? 0.0,
      grandTotal: _grandTotalNotifier.value,
    );

    await printWithCurrentProfile(
      context: context,
      invoice: entry,
      companyProfile: pharma.companyProfile,
      a4PdfBuilder: () async => await InvoicePdfGenerator.buildPurchasePdf(entry, pharma.companyProfile, isAutoGenerated: _isAutoGeneratedSupInv),
      isAutoGeneratedSupInv: _isAutoGeneratedSupInv,
    );
  }

  void _exportToExcel() async {
    final validItems = _items.where((it) => it.productName.trim().isNotEmpty).toList();
    if (validItems.isEmpty) {
      AppDialogs.showFastDialog(context: context, title: "Export Excel", content: "No items in the current purchase entry to export.");
      return;
    }
    try {
      final p = Provider.of<PharmacyProvider>(context, listen: false);
      String entryNoStr = _entryNoCtrl.text.isEmpty ? "DRAFT" : _entryNoCtrl.text.replaceAll('/', '_');
      String? result = await FilePicker.saveFile(
        dialogTitle: 'Save Purchase Excel',
        fileName: 'purchase_$entryNoStr.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (result != null) {
        final entry = PurchaseEntry(
          entryNo: _entryNoCtrl.text.isEmpty ? "DRAFT" : _entryNoCtrl.text,
          date: _date,
          supplierName: _supplierCtrl.text,
          supInvNo: cleanInvoiceNo(_supInvNoCtrl.text),
          supInvDate: _supInvDate,
          items: validItems.map((it) => PurchaseItem(
            id: it.productId,
            productName: it.productName, batch: it.batch, expiry: it.expiry,
            packin: it.packin, qty: it.qty, fQty: it.fQty, mrp: it.mrp, pRate: it.pRate,
            gross: it.gross, discPercent: it.discPercent, discAmt: it.discAmt, net: it.net,
            gstPercent: it.gstPercent, gstAmt: it.gstAmt, total: it.total, rack: it.rack,
            hsnCode: it.hsncode, sDiscPercent: it.sDiscPercent, sRate: it.sRate, lCost: it.lCost,
          )).toList(),
          subTotal: double.tryParse(_subTotalCtrl.text) ?? 0.0,
          discount: double.tryParse(_footerDiscAmtCtrl.text) ?? 0.0,
          grandTotal: _grandTotalNotifier.value,
        );
        await p.exportSinglePurchaseToExcel(result, entry);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Purchase Entry Exported successfully!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) AppDialogs.showFastDialog(context: context, title: "Export Error", content: "Export failed: $e");
    }
  }

  void _exportAllPurchasesToExcel() async {
    try {
      final p = Provider.of<PharmacyProvider>(context, listen: false);
      String? result = await FilePicker.saveFile(
        dialogTitle: 'Save All Purchases Excel',
        fileName: 'all_purchases_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (result != null) {
        await p.exportPurchaseToExcel(result);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All Purchases Exported successfully!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) AppDialogs.showFastDialog(context: context, title: "Export Error", content: "Export failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Provider.of<PharmacyProvider>(context);
    final String currentSupplier = _supplierCtrl.text.trim().toLowerCase();
    final String currentSupInvNo = cleanInvoiceNo(_supInvNoCtrl.text.trim()).toLowerCase();
    final String currentEntryNo = _entryNoCtrl.text.trim();

    bool isDuplicateSupInv = false;
    if (currentSupplier.isNotEmpty && currentSupInvNo.isNotEmpty) {
      isDuplicateSupInv = p.purchases.any((pur) {
        if (pur.entryNo == currentEntryNo) return false;
        final purSup = pur.supplierName.trim().toLowerCase();
        final purInv = cleanInvoiceNo(pur.supInvNo.trim()).toLowerCase();
        return purSup == currentSupplier && purInv == currentSupInvNo;
      });
    }

    return Focus(
      focusNode: _rootFocus,
      onKeyEvent: (node, event) {
        bool handled = _handleKeyEvent(event);
        return handled ? KeyEventResult.handled : KeyEventResult.ignored;
      },
      child: FocusScope(
        child: Scaffold(
            backgroundColor: AppColors.of(context).background,
            body: Stack(
              clipBehavior: Clip.none,
              children: [
              Column(children: [
                _buildTopToolbar(),
                PurchaseHeader(
                  entryNo: _entryNoCtrl.text,
                  entryNavBox: _entryNavBox(),
                  paymentMode: _paymentMode,
                  onPaymentModeChanged: (v) => setState(() => _paymentMode = v),
                  supplierCtrl: _supplierCtrl,
                  supplierFocus: _supplierFocus,
                  supplierLayer: _supplierLayer,
                  onSupplierChanged: _startSupplierSearch,
                  dueDate: _dueDate,
                  onDueDateChanged: (d) => setState(() => _dueDate = d),
                  doneByCtrl: _doneByCtrl,
                  doneByFocus: _doneByFocus,
                  doneByLayer: _doneByLayer,
                  onDoneByChanged: _startDoneBySearch,
                  gstMode: _gstMode,
                  onGstModeChanged: (v) => setState(() => _gstMode = v),
                  date: _date,
                  onDateChanged: (d) => setState(() => _date = d),
                  supInvDate: _supInvDate,
                  onSupInvDateChanged: (d) => setState(() => _supInvDate = d),
                  supInvNoCtrl: _supInvNoCtrl,
                  supInvNoFocus: _supInvNoFocus,
                  isAutoGeneratedSupInv: _isAutoGeneratedSupInv,
                  isDuplicateSupInv: isDuplicateSupInv,
                  onSupInvNoChanged: (val) {
                    if (_isAutoGeneratedSupInv) {
                      setState(() => _isAutoGeneratedSupInv = false);
                    }
                  },
                  invTotalCtrl: _invTotalCtrl,
                  invTotalFocus: _invTotalFocus,
                  formatSelector: _buildFormatSelector(),
                  smartPasteZone: _buildSmartPasteZone(),
                ),
                Expanded(child: LayoutBuilder(builder: (ctx, con) {
                  double fixedTotal = 0;
                  _colWidths.forEach((k, v) {
                    if (k != 1) fixedTotal += v;
                  });
                  double productWidth = 220;
                  if (con.maxWidth > (fixedTotal + 220)) {
                    productWidth = con.maxWidth - fixedTotal;
                  }
                  _colWidths[1] = productWidth;
                  final double finalTw = fixedTotal + _colWidths[1]!;

                  return Scrollbar(
                    controller: _gridScrollCtrl, thumbVisibility: true,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal, controller: _gridScrollCtrl,
                      child: SizedBox(
                        width: finalTw, 
                        height: con.maxHeight,
                        child: Column(children: [
                          _buildGridHeader(),
                          Expanded(child: _buildGrid()),
                          _buildGridSummary(),
                        ])),
                    ),
                  );
                })),
                PurchaseFooter(
                  recentPurchasesList: _recentPurchasesList(),
                  purchaseHistoryList: _purchaseHistoryList(),
                  historyProductName: _historyProductName,
                  remarksCtrl: _remarksCtrl,
                  remarksFocus: _remarksFocus,
                  totalCalculationSection: _totalCalculationSection(),
                ),
                _buildShortcutLegend(),
              ]),
              Positioned.fill(child: _buildOverlays()),
              if (_isLoading) Container(color: Colors.black12, child: const Center(child: CircularProgressIndicator())),
            ]),
          ),
        ),
      );
  }

  void _markDirty() {
    if (_isExistingEntry && !_isDirty) {
      if (mounted) setState(() => _isDirty = true);
    }
  }

  void _showManualAndLegendDialog() {
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
            const Text("ℹ️ Indicator Legend & Calculation Manual", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                _legendTile(Colors.white, Colors.blue.shade800, "Blue Text with ▲ / ▼", "Price / MRP Changed compared to Product Master"),
                _legendTile(Colors.amber.shade300, Colors.amber.shade900, "Yellow Highlight", "GST Rate Mismatch between Invoice and Product Master"),
                _legendTile(Colors.red.shade100, Colors.red.shade900, "Red Row Highlight", "Negative Margin (P.Rate >= MRP) or Expired Stock"),
                const SizedBox(height: 12),
                const Text("EXPIRY COLOR SLABS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.blueGrey)),
                const SizedBox(height: 6),
                _legendTile(Colors.red.shade900, Colors.white, "Dark Red 🔴", "Expired or ≤ 3 Months Shelf Life"),
                _legendTile(Colors.red.shade700, Colors.white, "Red 🔴", "≤ 6 Months Shelf Life (Distributor Return Warning)"),
                _legendTile(Colors.orange.shade800, Colors.white, "Orange 🟧", "≤ 1 Year / 12 Months Shelf Life"),
                _legendTile(Colors.amber.shade700, Colors.white, "Yellow 🟨", "≤ 1.5 Years / 18 Months Shelf Life"),
                _legendTile(Colors.lightGreen.shade700, Colors.white, "Light Green 🟢", "≤ 2 Years / 24 Months Shelf Life"),
                _legendTile(Colors.green.shade700, Colors.white, "Green 🟢", "≤ 3 Years / 36 Months Shelf Life"),
                _legendTile(Colors.teal.shade800, Colors.white, "Dark Green 🟢", "> 3 Years / > 36 Months Shelf Life"),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                const Text("CALCULATION FORMULAS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey, letterSpacing: 1.2)),
                const SizedBox(height: 10),
                _formulaTile("Effective Purchase Rate (with FQTY)", "(Purchase Rate × Paid Qty) / (Paid Qty + Free Qty)"),
                _formulaTile("Pure Margin % (No Discount)", "((MRP - Effective P.Rate) / MRP) × 100"),
                _formulaTile("Net Margin % (With L.Cost)", "((MRP - Landed Cost) / Landed Cost) × 100"),
                _formulaTile("Net Landed Cost", "(Purchase Rate - Discount) + GST Tax Amount"),
                _formulaTile("GST Tax Amount", "Net Amount × (GST % / 100)"),
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

  void _showPurchaseItemMathBreakdown(PurchaseItemData item) {
    double baseRate = item.pRate;
    int qty = item.qty;
    int fQty = item.fQty;
    double effRate = item.effectivePRate;
    double discPct = item.discPercent;
    double discAmt = item.discAmt;
    double netAmt = item.net;
    double gstPct = item.gstPercent;
    double gstAmt = item.gstAmt;
    int totalUnits = qty + fQty;
    double lCost = item.lCost > 0 ? item.lCost : ((netAmt + gstAmt) / (totalUnits > 0 ? totalUnits : 1));
    double mrp = item.mrp;
    double pureMargin = item.profitPctNoDisc;
    double netMargin = lCost > 0 ? ((mrp - lCost) / lCost) * 100.0 : 0.0;

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
              child: Text("Line Calculation: ${item.productName}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _mathRow("Entered Purchase Rate (P.Rate)", "₹${baseRate.toStringAsFixed(2)}", isBold: true),
              _mathRow("Paid Qty: $qty | Free Qty (FQTY): $fQty", "Total Units: $totalUnits"),
              if (fQty > 0)
                _mathRow("Effective Purchase Rate (with FQTY)", "₹${effRate.toStringAsFixed(2)}", isBold: true, color: Colors.teal.shade900),
              _mathRow("- Discount ($discPct%)", "-₹${discAmt.toStringAsFixed(2)}", color: Colors.red.shade700),
              const Divider(),
              _mathRow("Net Amount (before tax)", "₹${netAmt.toStringAsFixed(2)}"),
              _mathRow("+ GST Tax ($gstPct%)", "+₹${gstAmt.toStringAsFixed(2)}", color: Colors.teal.shade800),
              const Divider(),
              _mathRow("Landed Cost per Unit (L.Cost)", "₹${lCost.toStringAsFixed(2)}", isBold: true, color: Colors.blue.shade900),
              _mathRow("Maximum Retail Price (MRP)", "₹${mrp.toStringAsFixed(2)}", isBold: true),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: item.isNegativeMargin ? Colors.red.shade100 : (item.isLowMargin ? Colors.amber.shade100 : Colors.teal.shade50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: item.isNegativeMargin ? Colors.red.shade400 : (item.isLowMargin ? Colors.amber.shade400 : Colors.teal.shade200)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text("Pure Margin % (no disc):", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Text("${pureMargin.toStringAsFixed(2)}%", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: item.isNegativeMargin ? Colors.red.shade900 : (item.isLowMargin ? Colors.orange.shade900 : Colors.teal.shade800))),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text("Net Margin % (with L.Cost):", style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                        const Spacer(),
                        Text("${netMargin.toStringAsFixed(2)}%", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                      ],
                    ),
                  ],
                ),
              ),
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

  // ---> NEW: DIRTY STATE INTERCEPTOR <---
  Future<bool?> _promptDiscardChanges() async {
    if (!_isExistingEntry) {
      if (!_hasValidItems()) return true; // Safe to leave without warning if no valid items added
    } else if (!_isDirty) {
      return true; // Safe to proceed
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
          "You have made changes to this saved purchase entry.\nIf you leave now, your edits will be lost.\n\nDo you want to discard your changes?",
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

  Widget _buildTopToolbar() {
    bool canSave = !_isExistingEntry && !_isDeleted;
    bool canEdit = _isExistingEntry && !_isDeleted;
    final c = AppColors.of(context);

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: c.cardBg, border: Border(bottom: BorderSide(color: c.border, width: 0.5))),
      child: Row(
        children: [
          Text("PURCHASE ENTRY", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: c.primaryText)),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _topActionBtn(Icons.add_box_rounded, "New", const Color(0xFF2196F3), onTap: _resetPage),
                    _topActionBtn(Icons.check_circle_rounded, "Save", canSave ? const Color(0xFF4CAF50) : Colors.grey.shade400, textColor: canSave ? null : Colors.grey.shade400, onTap: canSave ? () => _savePurchase(isEdit: false) : () {}),
                    _topActionBtn(Icons.edit_document, "Edit", canEdit ? Colors.orange : Colors.grey.shade400, textColor: canEdit ? null : Colors.grey.shade400, onTap: canEdit ? () => _savePurchase(isEdit: true) : () {}),
                    _topActionBtn(Icons.search_rounded, "Find", const Color(0xFF3F51B5), onTap: _showFindDialog),
                    _topActionBtn(Icons.print_rounded, "Print", const Color(0xFF607D8B), onTap: _printPurchase),
                    _topActionBtn(Icons.picture_as_pdf_rounded, "PDF", const Color(0xFFE53935), onTap: _exportToPdf),
                    _topActionBtn(Icons.file_download_outlined, "Export", const Color(0xFF2E7D32), onTap: _exportToExcel),
                    _topActionBtn(Icons.info_outline_rounded, "Manual", Colors.indigo, onTap: _showManualAndLegendDialog),
                    _topActionBtn(Icons.delete_forever_rounded, "Del", canEdit ? const Color(0xFFD32F2F) : Colors.grey.shade400, textColor: canEdit ? null : Colors.grey.shade400, onTap: canEdit ? _showDeleteConfirm : null),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.blueGrey),
                      onSelected: (val) {
                        if (val == 'import') _importExcel();
                        if (val == 'export_current') _exportToExcel();
                        if (val == 'export_all') _exportAllPurchasesToExcel();
                        if (val == 'export_pdf') _exportToPdf();
                        if (val == 'paste') _processPastedClipboardData();
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(value: 'import', child: Row(children: [Icon(Icons.file_upload_outlined, size: 18, color: Colors.teal), SizedBox(width: 8), Text("Import File (Excel / PDF)")])),
                        const PopupMenuItem(value: 'export_current', child: Row(children: [Icon(Icons.file_download_outlined, size: 18, color: Colors.green), SizedBox(width: 8), Text("Export Current Purchase (Excel)")])),
                        const PopupMenuItem(value: 'export_all', child: Row(children: [Icon(Icons.table_view_outlined, size: 18, color: Colors.blue), SizedBox(width: 8), Text("Export All Purchases (Excel)")])),
                        const PopupMenuItem(value: 'export_pdf', child: Row(children: [Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.red), SizedBox(width: 8), Text("Export PDF / Print")])),
                        const PopupMenuItem(value: 'paste', child: Row(children: [Icon(Icons.paste_rounded, size: 18, color: Colors.orange), SizedBox(width: 8), Text("Paste Clipboard (Smart Paste)")])),
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

  Widget _topActionBtn(IconData icon, String label, Color color, {Color? textColor, VoidCallback? onTap}) => Padding(
    padding: const EdgeInsets.only(left: 12),
    child: InkWell(
      onTap: onTap, 
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center, 
        children: [
          Icon(icon, size: 28, color: color),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor ?? Colors.black87)),
        ]
      )
    ),
  );

  Widget _buildFormatSelector() {
    return Consumer<PharmacyProvider>(
      builder: (context, p, child) {
        final uniqueNames = {
          ...p.importMappings.map((m) => m.name.replaceAll(' - EXCEL', '').replaceAll(' - PDF', '')),
          ...p.suppliers
        }.toList();
        uniqueNames.sort();

        return Container(
          height: 28,
          padding: const EdgeInsets.only(left: 8, right: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blueGrey.shade300),
            borderRadius: BorderRadius.circular(4),
            color: Colors.blueGrey.shade50,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: uniqueNames.contains(_activeFormatName) ? _activeFormatName : null,
                  hint: const Text("Select Format", style: TextStyle(fontSize: 11, color: Colors.black54)),
                  icon: const Icon(Icons.arrow_drop_down, size: 16, color: Colors.blueGrey),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text("Select Format", style: TextStyle(color: Colors.black54)),
                    ),
                    ...uniqueNames.map((name) {
                      return DropdownMenuItem(
                        value: name,
                        child: Text(name),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _activeFormatName = val;
                      if (val != null && val.trim().isNotEmpty) {
                        _supplierCtrl.text = val.trim();
                      }
                      _resetGridAndInvoiceFieldsForImport();
                    });
                  },
                ),
              ),
              const SizedBox(width: 4),
              Container(width: 1, height: 16, color: Colors.blueGrey.shade200),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => _showFormatTypePicker(p),
                child: const Icon(Icons.add, size: 18, color: Colors.blueGrey),
              ),
              const SizedBox(width: 4),
              Container(width: 1, height: 16, color: Colors.blueGrey.shade200),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => _showUnifiedFormatManagerDialog(p),
                child: Icon(Icons.format_list_bulleted, size: 18, color: Colors.blueGrey.shade700),
              ),
            ],
          ),
        );
      }
    );
  }

  void _promptSave() async {
    final res = await AppDialogs.showConfirmDialog(
      context: context,
      title: _isExistingEntry ? "Update Purchase?" : "Save Purchase?",
      content: _isExistingEntry
          ? "Do you want to update this existing Purchase Entry?"
          : "Do you want to save this new Purchase Entry?",
      yesLabel: _isExistingEntry ? "UPDATE" : "SAVE",
      noLabel: "CANCEL",
    );
    if (res == true) {
      _savePurchase(isEdit: _isExistingEntry);
    } else {
      _footerDiscPctFocus.requestFocus();
    }
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

  Widget _entryNavBox() => Row(children: [
    InkWell(onTap: () => _navigateEntry('prev'), child: _smallBtn("<")),
    InkWell(
      onTap: _showJumpToEntryDialog,
      child: Tooltip(
        message: "Click to jump to entry #",
        child: Container(
          width: 55, height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.blue.shade50, border: Border.all(color: Colors.blue.shade300), borderRadius: BorderRadius.circular(3)),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _entryNoCtrl.text.contains('_') ? _entryNoCtrl.text.substring(_entryNoCtrl.text.indexOf('_') + 1) : _entryNoCtrl.text,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue),
              maxLines: 1,
            ),
          ),
        ),
      ),
    ),
    InkWell(onTap: () => _navigateEntry('next'), child: _smallBtn(">"))
  ]);
  Widget _smallBtn(String txt) => Container(width: 22, height: 22, alignment: Alignment.center, decoration: BoxDecoration(color: Colors.grey.shade200, border: Border.all(color: Colors.grey.shade400)), child: Text(txt));

  Widget _buildOverlays() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _listOverlay(_searchList, _searchLayer),
        _listOverlay(_batchList, _batchLayer, isBatch: true),
        _listOverlay(_supplierSearchList, _supplierLayer, isSupplier: true),
        _listOverlay(_doneBySearchList, _doneByLayer, isDoneBy: true),
      ],
    );
  }

  Widget _listOverlay<T>(ValueNotifier<List<T>> notifier, LayerLink link, {bool isBatch = false, bool isSupplier = false, bool isDoneBy = false}) {
    return ValueListenableBuilder<List<T>>(valueListenable: notifier, builder: (ctx, list, _) {
      if (list.isEmpty) return const SizedBox();
      final double dropWidth = (isSupplier || isDoneBy) ? 300.0 : 1100.0;
      final double yOffset = (isSupplier || isDoneBy) ? 26.0 : 30.0;

      return CompositedTransformFollower(
        link: link, showWhenUnlinked: false, offset: Offset(0, yOffset), 
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) {
            _isSelectingFromDropdown = true;
          },
          child: Material(
              elevation: 12, shadowColor: Colors.black, 
              child: Container(
              width: dropWidth, constraints: const BoxConstraints(maxHeight: 270),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isSupplier && !isDoneBy) GestureDetector(
                    onTapDown: (_) => _startFastScroll(true),
                    onTapUp: (_) => _stopFastScroll(),
                    onTapCancel: () => _stopFastScroll(),
                    child: Container(
                      height: 20,
                      width: double.infinity,
                      color: isBatch ? Colors.teal : Colors.blue.shade900,
                      child: Row(
                        children: isBatch
                            ? const [
                          _Hdr("Batch", width: 150),
                          _Hdr("Stock", width: 80, align: TextAlign.right),
                          _Hdr("Packing", width: 80, align: TextAlign.right),
                          _Hdr("Expiry", width: 90, align: TextAlign.center),
                          _Hdr("MRP", width: 90, align: TextAlign.right),
                          _Hdr("Sales Price", width: 100, align: TextAlign.right),
                          _Hdr("Disc%", width: 70, align: TextAlign.right),
                          _Hdr("PcsMrp", width: 80, align: TextAlign.right),
                          _Hdr("/PcsPrice", width: 90, align: TextAlign.right),
                          _Hdr("LCWT", width: 90, align: TextAlign.right),
                          _Hdr("Profit%", flex: 1, align: TextAlign.right)
                        ]
                            : const [
                          _Hdr("Name", width: 300),
                          _Hdr("Stock", width: 80, align: TextAlign.right),
                          _Hdr("Packin", width: 70, align: TextAlign.right),
                          _Hdr("MRP", width: 90, align: TextAlign.right),
                          _Hdr("PRate", width: 90, align: TextAlign.right),
                          _Hdr("Rack", width: 70),
                          _Hdr("Cat", width: 60),
                          _Hdr("Patent", width: 150),
                          _Hdr("Generic Name", flex: 1)
                        ],
                      ),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ValueListenableBuilder<int>(
                        valueListenable: _searchIdx,
                        builder: (ctx, idx, _) => Scrollbar(
                            controller: _dropdownScrollCtrl,
                            thumbVisibility: true,
                            child: ListView.builder(
                                controller: _dropdownScrollCtrl,
                                padding: EdgeInsets.zero, shrinkWrap: true,
                                itemCount: list.length,
                                itemBuilder: (ctx, i) {
                                  bool sel = i == idx;
                                  Color bgColor = sel ? Colors.blue.shade50 : Colors.white;

                                  if (isSupplier || isDoneBy) {
                                    return InkWell(
                                      onHover: (v) { if (v) _searchIdx.value = i; },
                                      onTap: () {
                                        if (isSupplier) {
                                          _onSupplierSelected(list[i] as String);
                                        } else {
                                          _onDoneBySelected(list[i] as String);
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        color: bgColor,
                                        child: Text(list[i] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                      ),
                                    );
                                  }

                                  final p = list[i] as Product;
                                  Color fontColor = Colors.black;

                                  if (isBatch) {
                                    bgColor = _getBatchBgColor(p.expiry);
                                    fontColor = (p.expiry.isNotEmpty && _parseExpiry(p.expiry).difference(DateTime.now()).inDays <= 30) ? Colors.white : Colors.black;
                                    if (sel) bgColor = Color.alphaBlend(Colors.teal.shade200.withValues(alpha: 0.5), bgColor);
                                  }

                                  double ps = p.packSize == 0 ? 1 : p.packSize.toDouble();
                                  double pcsMrp = p.mrp / ps;
                                  double pcsPrice = p.salePrice / ps;
                                  double profit = p.purchaseRate > 0 ? ((p.salePrice - p.purchaseRate) / p.purchaseRate) * 100 : 0.0;

                                  return InkWell(
                                      onHover: (v) { if (v) _searchIdx.value = i; },
                                      onTap: () {
                                        if (isBatch) {
                                          _finalizeBatchSelection(p);
                                        } else {
                                          _onProductSelected(p);
                                        }
                                      },
                                      child: Container(
                                          height: 30,
                                          decoration: BoxDecoration(color: sel ? Colors.blue.shade50 : Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 0.5))),
                                          child: Row(
                                            children: isBatch
                                                ? [
                                              _GridCell(cleanBatch(p.batch), width: 150, fontWeight: FontWeight.bold, color: Colors.black),
                                              _GridCell(p.stock.toString(), width: 80, align: TextAlign.right, fontWeight: FontWeight.bold, color: Colors.black),
                                              _GridCell(p.packSize.toString(), width: 80, align: TextAlign.right, color: Colors.black),
                                              _GridCell(p.expiry, width: 90, align: TextAlign.center, fontWeight: FontWeight.bold, color: fontColor, bgColor: bgColor),
                                              _GridCell(p.mrp.toStringAsFixed(2), width: 90, align: TextAlign.right, color: Colors.black),
                                              _GridCell(p.salePrice.toStringAsFixed(2), width: 100, align: TextAlign.right, color: Colors.black),
                                              _GridCell(p.sDiscPercent.toStringAsFixed(2), width: 70, align: TextAlign.right, color: Colors.black),
                                              _GridCell(pcsMrp.toStringAsFixed(2), width: 80, align: TextAlign.right, color: Colors.black),
                                              _GridCell(pcsPrice.toStringAsFixed(2), width: 90, align: TextAlign.right, color: Colors.black),
                                              _GridCell(p.purchaseRate.toStringAsFixed(2), width: 90, align: TextAlign.right, color: Colors.black),
                                              _GridCell(profit.toStringAsFixed(2), flex: 1, align: TextAlign.right, color: Colors.black)
                                            ]
                                                : (p.id == "NEW"
                                                    ? [
                                                        _GridCell("+ CREATE NEW MEDICINE: '${p.name}'", flex: 1, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                                                      ]
                                                    : [
                                              _GridCell(p.name, width: 300, fontWeight: FontWeight.bold),
                                              _GridCell(p.stock.toString(), width: 80, align: TextAlign.right, color: Colors.blue.shade700, fontWeight: FontWeight.bold),
                                              _GridCell(p.packSize.toString(), width: 70, align: TextAlign.right),
                                              _GridCell(p.mrp.toStringAsFixed(2), width: 90, align: TextAlign.right),
                                              _GridCell(p.purchaseRate.toStringAsFixed(2), width: 90, align: TextAlign.right),
                                              _GridCell(p.rack, width: 70),
                                              _GridCell(p.category.length > 3 ? p.category.substring(0, 3).toUpperCase() : p.category, width: 60),
                                              _GridCell(p.manufacturer, width: 150),
                                              _GridCell(p.genericName, flex: 1)
                                            ]),
                                          )
                                      )
                                  );
                                }
                            )
                        )
                    ),
                  ),
                  if (!isSupplier) GestureDetector(
                    onTapDown: (_) => _startFastScroll(false),
                    onTapUp: (_) => _stopFastScroll(),
                    onTapCancel: () => _stopFastScroll(),
                    child: Container(
                      height: 10,
                      width: double.infinity,
                      color: Colors.blue.shade900.withValues(alpha: 0.2),
                      child: const Icon(Icons.keyboard_arrow_down, size: 10, color: Colors.white),
                    ),
                  ),
                ]
              )
            )
          )
        )
      );
    });
  }
  Widget _buildShortcutLegend() => Container(height: 32, padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: Colors.grey.shade900, border: const Border(top: BorderSide(color: Colors.amber, width: 2))), child: ListView(scrollDirection: Axis.horizontal, children: [_shortcutTag("F2", "New"), _shortcutTag("F6", "Save"), _shortcutTag("F12", "Print"), _shortcutTag("Enter/Tab", "Next"), _shortcutTag("S+Enter", "Prev"), _shortcutTag("Arrows", "Nav"), _shortcutTag("C+Z", "Undo"), _shortcutTag("C+Del", "Del Row"), _shortcutTag("Esc", "Close")]));
  Widget _shortcutTag(String key, String label) => Padding(padding: const EdgeInsets.only(right: 15), child: Row(children: [Text(key, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 10)), const SizedBox(height: 4), Text(label, style: const TextStyle(color: Colors.white, fontSize: 10))]));

  String _getActiveProductName() {
    final p = Provider.of<PharmacyProvider>(context, listen: false);

    // 1. If dropdown is open, grab the highlighted item!
    if (_searchList.value.isNotEmpty) {
      return _searchList.value[_searchIdx.value].name;
    }
    // 2. Otherwise, grab the text from the current row
    int row = _focusedRowIndex;
    String name = "";
    if (row >= 0 && row < _items.length) {
      name = _items[row].productName;
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
                            color: const Color(0xFF1E293B),
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
}

class _Hdr extends StatelessWidget {
  final String title; final String? tooltip; final double? width; final int? flex; final TextAlign align; final bool isLocked;
  const _Hdr(this.title, {this.tooltip, this.width, this.flex, this.align = TextAlign.left, this.isLocked = false});
  @override Widget build(BuildContext context) { 
    final String msg = tooltip ?? title;
    Widget child = Container(
      width: width, 
      alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.center ? Alignment.center : Alignment.centerRight), 
      padding: const EdgeInsets.symmetric(horizontal: 6), 
      decoration: BoxDecoration(
        color: isLocked ? const Color(0xFF263238) : null,
        border: const Border(right: BorderSide(color: Colors.white24, width: 0.5)),
      ), 
      child: Text(
        title, 
        style: TextStyle(
          color: isLocked ? const Color(0xFFECEFF1) : Colors.white, 
          fontSize: 9, 
          fontWeight: FontWeight.bold,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    ); 
    if (msg.isNotEmpty) {
      child = ERPTooltip(message: msg, child: child);
    }
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

class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.length > 4) text = text.substring(0, 4);

    String res = "";
    for (int i = 0; i < text.length; i++) {
      if (i == 0) {
        int d = int.tryParse(text[i]) ?? 0;
        if (d > 1) {
          res = "0$d/";
          continue;
        }
      }
      if (i == 1) {
        if (text[0] == '1') {
          int d = int.tryParse(text[i]) ?? 0;
          if (d > 2) text = "${text[0]}2";
        }
      }
      res += text[i];
      if (i == 1 && text.length > 2) res += "/";
    }

    return TextEditingValue(
      text: res,
      selection: TextSelection.collapsed(offset: res.length),
    );
  }
}

class ManualPasteTableWidget extends StatefulWidget {
  final PharmacyProvider provider;
  final Function(List<PurchaseItemData>) onImport;
  final VoidCallback onCancel;

  const ManualPasteTableWidget({
    super.key,
    required this.provider,
    required this.onImport,
    required this.onCancel,
  });

  @override
  State<ManualPasteTableWidget> createState() => _ManualPasteTableWidgetState();
}

class _ManualPasteTableWidgetState extends State<ManualPasteTableWidget> {
  final TextEditingController _textCtrl = TextEditingController();
  bool _isTableMode = false;
  List<Map<String, TextEditingController>> _tableRows = [];

  @override
  void dispose() {
    _textCtrl.dispose();
    for (var row in _tableRows) {
      for (var ctrl in row.values) {
        ctrl.dispose();
      }
    }
    super.dispose();
  }

  String _fmt(double val) {
    if (val % 1 == 0) return val.toInt().toString();
    return val.toStringAsFixed(2);
  }

  double _calculateRowTotal(Map<String, TextEditingController> r) {
    int qty = int.tryParse(r['qty']?.text ?? '') ?? 0;
    int fqty = int.tryParse(r['fqty']?.text ?? '') ?? 0;
    int pack = int.tryParse(r['pack']?.text ?? '') ?? 1;
    double mrp = double.tryParse(r['mrp']?.text ?? '') ?? 0.0;
    double prate = double.tryParse(r['prate']?.text ?? '') ?? 0.0;
    double disc = double.tryParse(r['disc']?.text ?? '') ?? 0.0;
    double gst = double.tryParse(r['gst']?.text ?? '') ?? 12.0;
    double sdisc = double.tryParse(r['sdisc']?.text ?? '') ?? 0.0;

    final it = PurchaseItemData()
      ..packin = pack > 0 ? pack : 1
      ..qty = (qty + fqty) > 0 ? qty : 1
      ..fQty = fqty
      ..mrp = mrp > 0 ? mrp : prate
      ..pRate = prate
      ..discPercent = disc
      ..gstPercent = gst
      ..sDiscPercent = sdisc;

    it.recalculate(isGstMode: false);
    return it.total;
  }

  double _calculateRowProfit(Map<String, TextEditingController> r) {
    int qty = int.tryParse(r['qty']?.text ?? '') ?? 0;
    int fqty = int.tryParse(r['fqty']?.text ?? '') ?? 0;
    int pack = int.tryParse(r['pack']?.text ?? '') ?? 1;
    double mrp = double.tryParse(r['mrp']?.text ?? '') ?? 0.0;
    double prate = double.tryParse(r['prate']?.text ?? '') ?? 0.0;
    double disc = double.tryParse(r['disc']?.text ?? '') ?? 0.0;
    double gst = double.tryParse(r['gst']?.text ?? '') ?? 12.0;
    double sdisc = double.tryParse(r['sdisc']?.text ?? '') ?? 0.0;

    final it = PurchaseItemData()
      ..packin = pack > 0 ? pack : 1
      ..qty = (qty + fqty) > 0 ? qty : 1
      ..fQty = fqty
      ..mrp = mrp > 0 ? mrp : prate
      ..pRate = prate
      ..discPercent = disc
      ..gstPercent = gst
      ..sDiscPercent = sdisc;

    it.recalculate(isGstMode: false);
    if (it.lCost > 0 && it.mrp > 0) {
      return ((it.mrp - it.lCost) / it.lCost) * 100.0;
    }
    return 0.0;
  }

  void _parseTextToTable() {
    String text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    final rows = text.split(RegExp(r'\r?\n')).where((r) => r.trim().isNotEmpty).toList();
    if (rows.isEmpty) return;

    String delimiter = rows[0].contains('\t') ? '\t' : (rows[0].contains(',') ? ',' : '   ');
    List<String> headers = rows[0].split(delimiter).map((h) => h.trim().replaceAll('"', '')).toList();

    List<Map<String, TextEditingController>> parsedRows = [];

    int startIndex = (headers.any((h) => h.toLowerCase().contains('product') || h.toLowerCase().contains('item'))) ? 1 : 0;

    for (int i = startIndex; i < rows.length; i++) {
      List<String> cells = rows[i].split(delimiter).map((c) => c.trim().replaceAll('"', '')).toList();
      if (cells.isEmpty || (cells.length == 1 && cells[0].isEmpty)) continue;

      String getVal(List<String> keys) {
        for (var k in keys) {
          int idx = headers.indexWhere((h) => h.toLowerCase().replaceAll(RegExp(r'[\s._%\-]'), '') == k.toLowerCase().replaceAll(RegExp(r'[\s._%\-]'), ''));
          if (idx != -1 && idx < cells.length) return cells[idx];
        }
        return "";
      }

      String prod = getVal(['product', 'item', 'name', 'particulars']);
      if (prod.isEmpty && cells.isNotEmpty) prod = cells[0];
      
      String batch = getVal(['batch', 'batchno']);
      if (batch.isEmpty && cells.length > 1) batch = cells[1];

      String exp = getVal(['exp', 'expiry']);
      if (exp.isEmpty && cells.length > 2) exp = cells[2];

      String pack = getVal(['packing', 'pack', 'packin']);
      if (pack.isEmpty && cells.length > 3) pack = cells[3];

      String qty = getVal(['qty', 'quantity']);
      if (qty.isEmpty && cells.length > 4) qty = cells[4];

      String fqty = getVal(['fqty', 'free', 'f.qty']);
      if (fqty.isEmpty && cells.length > 5) fqty = cells[5];

      String prate = getVal(['prate', 'p.rate', 'rate', 'cost']);
      if (prate.isEmpty && cells.length > 6) prate = cells[6];

      String mrp = getVal(['mrp']);
      if (mrp.isEmpty && cells.length > 7) mrp = cells[7];

      String disper = getVal(['disper', 'disc%', 'discount']);
      if (disper.isEmpty && cells.length > 8) disper = cells[8];

      String taxper = getVal(['taxper', 'gst', 'gst%', 'tax%']);
      if (taxper.isEmpty && cells.length > 9) taxper = cells[9];

      String sdisc = getVal(['sdisc', 's.disc', 'special discount']);
      if (sdisc.isEmpty && cells.length > 10) sdisc = cells[10];

      parsedRows.add({
        'product': TextEditingController(text: prod),
        'batch': TextEditingController(text: batch),
        'exp': TextEditingController(text: exp),
        'pack': TextEditingController(text: pack.isEmpty ? '1' : pack),
        'qty': TextEditingController(text: qty.isEmpty ? '1' : qty),
        'fqty': TextEditingController(text: fqty.isEmpty ? '0' : fqty),
        'mrp': TextEditingController(text: mrp.isEmpty ? '0' : mrp),
        'prate': TextEditingController(text: prate.isEmpty ? '0' : prate),
        'disc': TextEditingController(text: disper.isEmpty ? '0' : disper),
        'gst': TextEditingController(text: taxper.isEmpty ? '12' : taxper),
        'sdisc': TextEditingController(text: sdisc.isEmpty ? '0' : sdisc),
      });
    }

    setState(() {
      _tableRows = parsedRows;
      _isTableMode = true;
    });
  }

  void _addNewRow() {
    setState(() {
      _tableRows.add({
        'product': TextEditingController(),
        'batch': TextEditingController(),
        'exp': TextEditingController(),
        'pack': TextEditingController(text: '1'),
        'qty': TextEditingController(text: '1'),
        'fqty': TextEditingController(text: '0'),
        'mrp': TextEditingController(text: '0'),
        'prate': TextEditingController(text: '0'),
        'disc': TextEditingController(text: '0'),
        'gst': TextEditingController(text: '12'),
        'sdisc': TextEditingController(text: '0'),
      });
    });
  }

  void _finishImport() {
    List<PurchaseItemData> items = [];
    for (var r in _tableRows) {
      final prodCtrl = r['product'];
      final batchCtrl = r['batch'];
      final expCtrl = r['exp'];
      final packCtrl = r['pack'];
      final qtyCtrl = r['qty'];
      final fqtyCtrl = r['fqty'];
      final mrpCtrl = r['mrp'];
      final prateCtrl = r['prate'];
      final discCtrl = r['disc'];
      final gstCtrl = r['gst'];
      final sdiscCtrl = r['sdisc'];

      if (prodCtrl == null) continue;
      String prodName = prodCtrl.text.trim();
      if (prodName.isEmpty) continue;

      int qty = int.tryParse(qtyCtrl?.text ?? '') ?? 0;
      int fqty = int.tryParse(fqtyCtrl?.text ?? '') ?? 0;
      int pack = int.tryParse(packCtrl?.text ?? '') ?? 1;
      double mrp = double.tryParse(mrpCtrl?.text ?? '') ?? 0.0;
      double prate = double.tryParse(prateCtrl?.text ?? '') ?? 0.0;
      double disc = double.tryParse(discCtrl?.text ?? '') ?? 0.0;
      double gst = double.tryParse(gstCtrl?.text ?? '') ?? 12.0;
      double sdisc = double.tryParse(sdiscCtrl?.text ?? '') ?? 0.0;

      Product? matched;
      try {
        matched = widget.provider.productMaster.firstWhere(
          (p) => p.name.toLowerCase().trim() == prodName.toLowerCase().trim(),
        );
      } catch (_) {}

      final it = PurchaseItemData()
        ..productId = matched?.id ?? "UNKNOWN"
        ..productName = matched?.name ?? prodName
        ..batch = batchCtrl?.text.trim() ?? ''
        ..expiry = (expCtrl?.text.trim().isNotEmpty ?? false) ? expCtrl!.text.trim() : '--/--'
        ..packin = pack > 0 ? pack : 1
        ..qty = (qty + fqty) > 0 ? qty : 1
        ..fQty = fqty
        ..mrp = mrp > 0 ? mrp : prate
        ..pRate = prate
        ..discPercent = disc
        ..gstPercent = gst > 0 ? gst : (matched?.gstPercent ?? 12.0)
        ..sDiscPercent = sdisc
        ..rack = matched?.rack ?? ""
        ..hsncode = matched?.hsnCode ?? "";

      it.recalculate(isGstMode: false);
      it.syncControllers();
      items.add(it);
    }

    widget.onImport(items);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.blue.shade800,
            child: Row(
              children: [
                const Icon(Icons.paste, color: Colors.white),
                const SizedBox(width: 10),
                const Text("MANUAL DATA PASTE & INTERACTIVE TABLE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_isTableMode)
                  TextButton.icon(
                    onPressed: () => setState(() => _isTableMode = false),
                    icon: const Icon(Icons.edit_note, color: Colors.white, size: 16),
                    label: const Text("Edit Raw Text", style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: !_isTableMode ? _buildRawPaste() : _buildTable(),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text("CANCEL"),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isTableMode ? _finishImport : _parseTextToTable,
                  icon: Icon(_isTableMode ? Icons.check_circle : Icons.table_chart),
                  label: Text(_isTableMode ? "IMPORT INTO PURCHASE GRID" : "PREVIEW TABLE"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRawPaste() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Paste your Excel rows here (including headers):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          Expanded(
            child: TextField(
              controller: _textCtrl,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: "Copy from Excel and Paste here (Ctrl+V)...",
                border: OutlineInputBorder(borderSide: BorderSide(color: Colors.blue.shade200)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                onPressed: _parseTextToTable,
                icon: const Icon(Icons.table_chart_rounded),
                label: const Text("PREVIEW & EDIT IN TABLE"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.blue.shade50,
          child: Row(
            children: [
              const Text("Review and edit imported rows before adding to purchase grid:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _addNewRow,
                icon: const Icon(Icons.add, size: 14),
                label: const Text("Add Row", style: TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                headingRowHeight: 32,
                dataRowMinHeight: 34,
                dataRowMaxHeight: 38,
                columns: const [
                  DataColumn(label: Text("Product Name", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                  DataColumn(label: Text("Batch", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                  DataColumn(label: Text("Exp", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                  DataColumn(label: Text("Pack", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                  DataColumn(label: Text("Qty", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                  DataColumn(label: Text("F.Qty", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                  DataColumn(label: Text("MRP", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                  DataColumn(label: Text("P.Rate", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                  DataColumn(label: Text("Disc%", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                  DataColumn(label: Text("GST%", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                  DataColumn(label: Text("S.Disc%", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                  DataColumn(label: Text("Total", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                  DataColumn(label: Text("Profit", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                  DataColumn(label: Text("Action", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                ],
                rows: List.generate(_tableRows.length, (index) {
                  final r = _tableRows[index];
                  return DataRow(cells: [
                    DataCell(SizedBox(
                      width: 220,
                      child: Autocomplete<Product>(
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text.trim().isEmpty) {
                            return const Iterable<Product>.empty();
                          }
                          return widget.provider.searchProducts(textEditingValue.text.trim(), includeGenerics: false);
                        },
                        displayStringForOption: (Product option) => option.name,
                        onSelected: (Product selection) {
                          setState(() {
                            r['product']!.text = selection.name;
                            r['mrp']!.text = selection.mrp.toString();
                            r['prate']!.text = selection.purchaseRate.toString();
                            r['pack']!.text = selection.packSize.toString();
                            r['gst']!.text = selection.gstPercent.toString();
                          });
                        },
                        fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
                          if (textController.text != r['product']!.text) {
                            textController.text = r['product']!.text;
                          }
                          return TextField(
                            controller: textController,
                            focusNode: focusNode,
                            style: const TextStyle(fontSize: 12),
                            decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                            onChanged: (v) {
                              r['product']!.text = v;
                            },
                          );
                        },
                      ),
                    )),
                    DataCell(SizedBox(width: 90, child: TextField(controller: r['batch'], style: const TextStyle(fontSize: 12), decoration: const InputDecoration(border: InputBorder.none, isDense: true)))),
                    DataCell(SizedBox(width: 65, child: TextField(controller: r['exp'], style: const TextStyle(fontSize: 12), decoration: const InputDecoration(border: InputBorder.none, isDense: true)))),
                    DataCell(SizedBox(width: 45, child: TextField(controller: r['pack'], onChanged: (_) => setState(() {}), style: const TextStyle(fontSize: 12), decoration: const InputDecoration(border: InputBorder.none, isDense: true)))),
                    DataCell(SizedBox(width: 45, child: TextField(controller: r['qty'], onChanged: (_) => setState(() {}), style: const TextStyle(fontSize: 12), decoration: const InputDecoration(border: InputBorder.none, isDense: true)))),
                    DataCell(SizedBox(width: 45, child: TextField(controller: r['fqty'], onChanged: (_) => setState(() {}), style: const TextStyle(fontSize: 12), decoration: const InputDecoration(border: InputBorder.none, isDense: true)))),
                    DataCell(SizedBox(width: 70, child: TextField(controller: r['mrp'], onChanged: (_) => setState(() {}), style: const TextStyle(fontSize: 12), decoration: const InputDecoration(border: InputBorder.none, isDense: true)))),
                    DataCell(SizedBox(width: 70, child: TextField(controller: r['prate'], onChanged: (_) => setState(() {}), style: const TextStyle(fontSize: 12), decoration: const InputDecoration(border: InputBorder.none, isDense: true)))),
                    DataCell(SizedBox(width: 45, child: TextField(controller: r['disc'], onChanged: (_) => setState(() {}), style: const TextStyle(fontSize: 12), decoration: const InputDecoration(border: InputBorder.none, isDense: true)))),
                    DataCell(SizedBox(width: 45, child: TextField(controller: r['gst'], onChanged: (_) => setState(() {}), style: const TextStyle(fontSize: 12), decoration: const InputDecoration(border: InputBorder.none, isDense: true)))),
                    DataCell(SizedBox(width: 50, child: TextField(controller: r['sdisc'], onChanged: (_) => setState(() {}), style: const TextStyle(fontSize: 12), decoration: const InputDecoration(border: InputBorder.none, isDense: true)))),
                    DataCell(SizedBox(
                      width: 75,
                      child: Text(
                        _fmt(_calculateRowTotal(r)),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                    )),
                    DataCell(SizedBox(
                      width: 65,
                      child: Text(
                        "${_calculateRowProfit(r).toStringAsFixed(2)}%",
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    )),
                    DataCell(
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          setState(() {
                            _tableRows.removeAt(index);
                          });
                        },
                      ),
                    ),
                  ]);
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
