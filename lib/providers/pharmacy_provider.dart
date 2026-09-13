import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart' as sql;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:excel/excel.dart';
import 'package:synchronized/synchronized.dart';
import '../models/erp_models.dart';
import '../models/product_ranking.dart';
export '../models/erp_models.dart';
import '../database/db_helper.dart';
import '../utils/security_crypto.dart';
import '../utils/tax_calculator.dart';
import '../utils/app_formatters.dart';
import '../services/excel_worker_service.dart';

typedef Transaction = sql.Transaction;

class PharmacyProvider extends ChangeNotifier {
  final Lock _dbLock = Lock();

  /// Executes any critical database write inside a locked, atomic transaction block
  Future<T> executeSerializedTransaction<T>(Future<T> Function(Transaction txn) action) async {
    final db = await DbHelper.instance.database;
    return await _dbLock.synchronized(() async {
      return await db.transaction((txn) async {
        return await action(txn);
      });
    });
  }

  final List<Product> _products = [];
  final List<Product> _productMaster = []; // UNIQUE Medicine names and details
  final List<Product> _recentModifiedProducts = [];
  final List<SaleInvoice> _sales = [];
  final List<SaleReturnInvoice> _saleReturns = [];
  final List<PurchaseEntry> _purchases = [];
  final List<PurchaseReturnEntry> _purchaseReturns = [];
  final List<StockAdjustment> _adjustments = [];
  final List<StockWriteOff> _writeOffs = [];
  final List<SupplierPayment> _supplierPayments = [];
  final List<SupplierCreditNote> _supplierCreditNotes = [];
  final List<Prescription> _prescriptions = [];
  final List<Account> _accountMaster = [];
  final Map<String, List<Product>> _searchCache = {};

  final Map<String, List<Product>> _productBatchesMap = {};
  int _stockVersion = 0;
  int get stockVersion => _stockVersion;

  List<Product> getBatchesForProductName(String name) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return const [];
    return _productBatchesMap[key] ?? const [];
  }

  void invalidateSearchProductsCache() {
    _searchCache.clear();
  }

  void _rebuildSearchIndex() {
    _stockVersion++;
    _searchCache.clear();
    _productBatchesMap.clear();
    for (var p in _products) {
      final key = p.name.trim().toLowerCase();
      if (key.isNotEmpty) {
        _productBatchesMap.putIfAbsent(key, () => []).add(p);
      }
    }
  }
  final List<String> _accounts = [];

  // Aggregated Stats (Calculated via SQL for scalability)
  double _todayRevenue = 0.0;
  int _todaySalesCount = 0;
  double _todayPurchase = 0.0;
  int _todayPurchasesCount = 0;
  double _monthlyPurchase = 0.0;
  List<Product> _nonMovingProducts = [];

  final List<String> _categories = ["General", "Tablets", "Syrups", "Injections", "OTC"];
  final List<String> _racks = ["A1", "A2", "B1", "B2"];
  final Map<String, bool> _rackStatus = {};
  final List<String> _suppliers = [];
  final List<Supplier> _supplierMaster = [];
  final List<String> _patients = ["P1", "P2", "General"];
  final List<Patient> _patientMaster = [];
  final List<String> _doctors = ["D1", "D2", "Unknown"];
  final List<Doctor> _doctorMaster = [];
  final List<Staff> _staffMaster = [];
  final List<String> _manufacturers = ["NEVIA", "GSK", "CIPLA"];
  final List<Generic> _generics = [];
  final List<ImportMapping> _importMappings = [];
  final List<ProductMapping> _productMappings = [];
  final CompanyProfile companyProfile = CompanyProfile();

  String _selectedFinancialYear = "";
  List<String> get availableFinancialYears => _generateFinancialYears();

  String get selectedFinancialYear => _selectedFinancialYear;

  void setSelectedFinancialYear(String year) {
    _selectedFinancialYear = year;
    loadFromDatabase(); // Reload data for the selected year
    notifyListeners();
  }

  String _getCalculatedFY(DateTime date) {
    int startYear = date.year;
    if (date.month < 4) startYear -= 1;
    return "$startYear-${(startYear + 1).toString().substring(2)}";
  }

  String getCalculatedFY(DateTime date) => _getCalculatedFY(date);

  DateTime? _softwareOpeningDate;
  DateTime get softwareOpeningDate => _softwareOpeningDate ?? DateTime(2021, 7, 5);

  Future<void> loadSoftwareOpeningDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? savedStr = prefs.getString('software_opening_date');
      if (savedStr != null && savedStr.isNotEmpty) {
        _softwareOpeningDate = DateTime.tryParse(savedStr);
      } else {
        _softwareOpeningDate = DateTime(2021, 7, 5); // Default: July 5, 2021
      }
    } catch (e) {
      debugPrint("Error loading software opening date: $e");
      _softwareOpeningDate = DateTime(2021, 7, 5);
    }
  }

  Future<void> setSoftwareOpeningDate(DateTime date) async {
    _softwareOpeningDate = date;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('software_opening_date', date.toIso8601String());
    } catch (e) {
      debugPrint("Error saving software opening date: $e");
    }
    await loadFromDatabase();
    notifyListeners();
  }

  List<String> _generateFinancialYears() {
    DateTime now = DateTime.now();
    String current = _getCalculatedFY(now);
    
    // We'll populate this properly in loadFromDatabase, 
    // but for the getter, we return the cached list or just current if empty.
    if (_availableYears.isEmpty) return [current];
    return _availableYears;
  }
  
  List<String> _availableYears = [];

  // Global Sales Workspaces
  final List<Map<String, dynamic>> _salesSessions = List.generate(3, (i) => {
    'items': <SaleItem>[],
    'agent': '',
    'customerAcc': 'Cash',
    'patient': 'P1',
    'mobile': '',
    'doctor': 'D1',
    'taxType': 2, 
    'orderType': 0,
    'focusRow': 0,
    'focusCol': 1,
  });
  int _activeSessionIdx = 0;

  String? _autoRegisteredSupId;

  bool _cancelImport = false;
  final bool _isImportInProgress = false;

  bool get isImportInProgress => _isImportInProgress;

  void cancelImport() {
    _cancelImport = true;
    notifyListeners();
  }

  // Background Data Synchronization Queue
  final List<SyncTask> _syncQueue = [];
  final List<_PendingSyncTask> _pendingSyncQueue = [];
  bool _isProcessingSyncQueue = false;

  List<SyncTask> get syncQueue => List.unmodifiable(_syncQueue);
  bool get isProcessingSyncQueue => _isProcessingSyncQueue;

  void addSyncTask({
    required String title,
    required String type,
    required Future<Map<String, dynamic>> Function(Function(double, String) onProgress) taskRunner,
  }) {
    final task = SyncTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      type: type,
    );
    _syncQueue.add(task);
    _pendingSyncQueue.add(_PendingSyncTask(task: task, taskRunner: taskRunner));
    notifyListeners();

    _processSyncQueue();
  }

  void _processSyncQueue() async {
    if (_isProcessingSyncQueue) return;
    _isProcessingSyncQueue = true;

    while (_pendingSyncQueue.isNotEmpty) {
      final pendingItem = _pendingSyncQueue.removeAt(0);
      final task = pendingItem.task;

      task.status = 'In Progress';
      task.statusMessage = 'Starting...';
      task.progress = 0.0;
      notifyListeners();

      int lastNotifyTime = DateTime.now().millisecondsSinceEpoch;

      try {
        final res = await pendingItem.taskRunner((p, statusMsg) {
          task.progress = p.clamp(0.0, 1.0);
          task.statusMessage = statusMsg;

          // Throttle UI rebuilds to max once per 100ms or on completion to keep UI smooth
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - lastNotifyTime >= 100 || p >= 1.0) {
            lastNotifyTime = now;
            notifyListeners();
          }
        });

        if (res['success'] == true) {
          task.status = 'Completed';
          task.progress = 1.0;
          task.resultMessage = res['message'] ?? 'Task completed successfully.';
        } else {
          task.status = 'Failed';
          task.resultMessage = res['message'] ?? 'Task failed.';
        }
      } catch (e) {
        task.status = 'Failed';
        task.resultMessage = 'Error: $e';
      }

      notifyListeners();

      // Yield to Windows OS message loop & Flutter renderer between tasks
      await Future.delayed(const Duration(milliseconds: 100));
    }

    _isProcessingSyncQueue = false;
    notifyListeners();
  }

  void clearCompletedSyncTasks() {
    _syncQueue.removeWhere((t) => t.status == 'Completed' || t.status == 'Failed');
    notifyListeners();
  }

  List<Map<String, dynamic>> get salesSessions => _salesSessions;
  int get activeSessionIdx => _activeSessionIdx;

  void setSalesSession(int index) {
    _activeSessionIdx = index;
    notifyListeners();
  }

  void clearSalesSession(int index) {
    // ---> THE FIX: Remember the Agent before clearing the invoice! <---
    String keptAgent = _salesSessions[index]['agent']?.toString() ?? "";
    
    _salesSessions[index] = {
      'items': <SaleItem>[],
      'agent': keptAgent, 
      'customerAcc': 'Cash',
      'patient': 'P1',
      'mobile': '',
      'doctor': 'D1',
      'taxType': 2,
      'orderType': 0,
      'focusRow': 0,
      'focusCol': 1,
    };
    notifyListeners();
  }

  void updateSalesSession(int index, Map<String, dynamic> data, {bool notify = true}) {
    _salesSessions[index] = data;
    if (notify) notifyListeners();
  }

  bool isLoading = false;
  // ---> NEW: SECURITY & AUDIT TRACKERS <---
  bool _adminSessionActive = false;
  Timer? _adminSessionTimer;
  final Map<String, bool> securityToggles = {};
  String errorMessage = "";

  PharmacyProvider() {
    _selectedFinancialYear = _getCalculatedFY(DateTime.now());
    _initData();
  }

  Future<void> _fixMissingFinancialYears() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('fy_migration_v74_done') == true) {
        return; // Already fixed
      }

      final db = await DbHelper.instance.database;
      final tables = ['sales_invoices', 'purchase_entries', 'sales_return_invoices', 'purchase_return_entries', 'stock_adjustments', 'stock_write_offs', 'prescriptions'];
      
      for (var table in tables) {
        final List<Map<String, dynamic>> records = await db.query(table, where: "financial_year IS NULL OR financial_year = ''");
        if (records.isNotEmpty) {
          debugPrint("Fixing ${records.length} records in $table with missing Financial Year");
          await db.transaction((txn) async {
            for (var r in records) {
              String dateStr = r['date']?.toString() ?? "";
              if (dateStr.isNotEmpty) {
                DateTime? dt = DateTime.tryParse(dateStr);
                if (dt != null) {
                  String fy = _getCalculatedFY(dt);
                  String idCol = (table == 'stock_write_offs') ? 'id' : 'entry_no';
                  await txn.update(table, {'financial_year': fy}, where: '$idCol = ?', whereArgs: [r[idCol]]);
                }
              }
            }
          });
        }
      }

      await prefs.setBool('fy_migration_v74_done', true);
    } catch (e) {
      debugPrint("Error fixing financial years: $e");
    }
  }

  List<Product> get products => _products;
  List<Product> get productMaster => _productMaster;
  List<Product> get negativeStockProducts => _productMaster.where((p) => p.stock < 0).toList();

  List<Product> get recentModifiedProducts {
    if (_recentModifiedProducts.isEmpty) {
      final sourceList = _productMaster.isNotEmpty ? _productMaster : _products;
      final Map<String, Product> uniqueMap = {};
      for (var p in sourceList.reversed) {
        final key = p.name.trim().toLowerCase();
        if (!uniqueMap.containsKey(key)) {
          uniqueMap[key] = p;
        }
        if (uniqueMap.length >= 20) break;
      }
      _recentModifiedProducts.addAll(uniqueMap.values);
    }
    return List.unmodifiable(_recentModifiedProducts);
  }

  void trackProductModified(Product p) {
    _recentModifiedProducts.removeWhere((item) =>
        item.id == p.id || item.name.trim().toLowerCase() == p.name.trim().toLowerCase());
    _recentModifiedProducts.insert(0, p);
    if (_recentModifiedProducts.length > 20) {
      _recentModifiedProducts.removeRange(20, _recentModifiedProducts.length);
    }
    notifyListeners();
  }
  List<ImportMapping> get importMappings => _importMappings;
  List<ProductMapping> get productMappings => _productMappings;
  List<SaleInvoice> get sales => _sales;
  List<SaleReturnInvoice> get saleReturns => _saleReturns;
  List<PurchaseEntry> get purchases => _purchases;
  List<String> get doneByNames {
    final names = _purchases.map((p) => p.doneBy).where((n) => n.isNotEmpty).toSet().toList();
    names.addAll(_adjustments.map((a) => a.doneBy).where((n) => n.isNotEmpty));
    return names.toSet().toList()..sort();
  }
  List<PurchaseReturnEntry> get purchaseReturns => _purchaseReturns;
  List<StockAdjustment> get adjustments => _adjustments;
  List<StockWriteOff> get writeOffs => _writeOffs;
  List<SupplierPayment> get supplierPayments => _supplierPayments;
  List<SupplierCreditNote> get supplierCreditNotes => _supplierCreditNotes;
  List<Prescription> get prescriptions => _prescriptions;
  List<Account> get accountMaster => _accountMaster;
  List<String> get accounts => _accounts;
  List<String> get categories => _categories;
  List<String> get racks {
    final sorted = List<String>.from(_racks);
    sorted.sort(_naturalCompare);
    return sorted;
  }

  bool isRackActive(String rackName) => _rackStatus[rackName] ?? true;

  bool hasSalesInvoice(String entryNo) {
    if (entryNo.trim().isEmpty) return false;
    final trimmed = entryNo.trim();
    return _sales.any((inv) =>
        (inv.entryNo == trimmed ||
            inv.entryNo == "SALE-$trimmed" ||
            (int.tryParse(trimmed) != null && int.tryParse(inv.entryNo) == int.tryParse(trimmed))) &&
        inv.isDeleted != true);
  }

  Future<SaleInvoice?> getSaleInvoiceById(String invoiceNo) async {
    try {
      final trimmed = invoiceNo.trim();
      if (trimmed.isEmpty) return null;

      // 1. Check RAM cache first (only if items are loaded!)
      final cached = _sales.cast<SaleInvoice?>().firstWhere(
        (inv) => inv != null && inv.items.isNotEmpty && (
          inv.entryNo == trimmed ||
          inv.entryNo == "SALE-$trimmed" ||
          (int.tryParse(trimmed) != null && int.tryParse(inv.entryNo) == int.tryParse(trimmed))
        ),
        orElse: () => null,
      );
      if (cached != null) return cached;

      // 2. Query Database
      final db = await DbHelper.instance.database;
      List<Map<String, dynamic>> maps = await db.query(
        'sales_invoices',
        where: '(entry_no = ? OR invoice_no = ? OR entry_no = ?) AND (is_deleted IS NULL OR is_deleted = 0)',
        whereArgs: [trimmed, trimmed, "SALE-$trimmed"],
      );

      if (maps.isEmpty && int.tryParse(trimmed) != null) {
        final numVal = int.parse(trimmed);
        maps = await db.rawQuery(
          "SELECT * FROM sales_invoices WHERE (CAST(entry_no AS INTEGER) = ? OR CAST(invoice_no AS INTEGER) = ?) AND (is_deleted IS NULL OR is_deleted = 0) LIMIT 1",
          [numVal, numVal],
        );
      }

      if (maps.isEmpty) return null;

      final s = maps.first;
      final actualEntryNo = s['entry_no']?.toString() ?? s['invoice_no']?.toString() ?? trimmed;

      // 3. Fetch item details joining with product_master
      final List<Map<String, dynamic>> itemsData = await db.rawQuery('''
        SELECT s.*, p.name as product_name, p.hsn_code as master_hsn
        FROM sales_items s
        LEFT JOIN product_master p ON s.product_id = p.id
        WHERE s.invoice_no = ? OR s.invoice_no = ?
      ''', [actualEntryNo, trimmed]);

      DateTime parsedDate;
      try { parsedDate = DateTime.parse(s['date']); }
      catch (_) { parsedDate = DateTime.tryParse(s['date'].toString().replaceAll('/', '-')) ?? DateTime.now(); }

      final items = itemsData.map((m) {
        final pName = (m['product_name'] as String?)?.isNotEmpty == true
            ? m['product_name'].toString()
            : (m['extra']?.toString() ?? m['product_id']?.toString() ?? '');
        final pId = m['product_id']?.toString() ?? '';
        final bNo = m['batch_number']?.toString() ?? '';
        final exp = m['expiry_date']?.toString() ?? '';
        final hsn = m['master_hsn']?.toString() ?? m['hsn_code']?.toString() ?? '';
        final mrpVal = (m['mrp'] as num?)?.toDouble() ?? 0.0;
        final sRateVal = (m['s_rate'] as num?)?.toDouble() ?? (m['sale_rate'] as num?)?.toDouble() ?? 0.0;
        final pRateVal = (m['purchase_rate'] as num?)?.toDouble() ?? 0.0;
        final lCostVal = (m['landing_cost'] as num?)?.toDouble() ?? 0.0;
        final packVal = (m['packin'] as num?)?.toInt() ?? (m['packing'] as num?)?.toInt() ?? 1;
        final gstVal = TaxCalculator.roundGstPercent((m['gst_percent'] as num?)?.toDouble() ?? (m['tax_percent'] as num?)?.toDouble() ?? 0.0);
        final suppVal = m['supplier_name']?.toString() ?? '';

        final prod = Product(
          id: pId,
          name: pName,
          batch: bNo,
          expiry: exp,
          hsnCode: hsn,
          mrp: mrpVal,
          salePrice: sRateVal,
          purchaseRate: pRateVal,
          landingCost: lCostVal,
          packSize: packVal,
          gstPercent: gstVal,
          supplier: suppVal,
        );

        double ps = packVal > 0 ? packVal.toDouble() : 1.0;
        double unitMrp = mrpVal / ps;
        double unitSRate = (sRateVal > 0 && sRateVal == mrpVal && packVal > 1)
            ? (sRateVal / ps)
            : (sRateVal > 0 ? sRateVal : unitMrp);
        double taxSpRaw = (m['taxable_sp'] as num?)?.toDouble() ?? 0.0;
        double unitTaxSp = (taxSpRaw > 0 && taxSpRaw == mrpVal && packVal > 1)
            ? (taxSpRaw / ps)
            : (taxSpRaw > 0 ? taxSpRaw : unitSRate);

        return SaleItem(
          product: prod,
          qty: (m['qty'] as num?)?.toInt() ?? (m['quantity'] as num?)?.toInt() ?? 0,
          packin: packVal,
          mrp: unitMrp,
          sRate: unitSRate,
          taxableSP: unitTaxSp,
          discPercent: (m['disc_percent'] as num?)?.toDouble() ?? 0.0,
          discAmt: (m['disc_amt'] as num?)?.toDouble() ?? 0.0,
          gstPercent: gstVal,
          gstAmt: (m['gst_amt'] as num?)?.toDouble() ?? 0.0,
          cgstAmt: (m['cgst_amt'] as num?)?.toDouble() ?? 0.0,
          sgstAmt: (m['sgst_amt'] as num?)?.toDouble() ?? 0.0,
          igstAmt: (m['igst_amt'] as num?)?.toDouble() ?? 0.0,
          total: (m['total'] as num?)?.toDouble() ?? 0.0,
          purchaseRate: pRateVal,
          landingCost: lCostVal,
          supplier: suppVal,
        );
      }).toList();

      return SaleInvoice(
        entryNo: actualEntryNo,
        date: parsedDate,
        customerAcc: s['customer_acc'] ?? "Cash",
        patient: s['patient'] ?? "General",
        mobile: s['mobile'] ?? "",
        doctor: s['doctor'] ?? "Unknown",
        doctorRegNo: s['doctor_reg_no'] ?? "",
        specialOrderJson: s['special_order_json'] ?? "[]",
        taxType: s['tax_type'] ?? "Non Gst",
        days: s['days'] ?? 0,
        items: items,
        subTotal: (s['sub_total'] as num?)?.toDouble() ?? (s['total_amount'] as num?)?.toDouble() ?? 0.0,
        discountPercent: (s['discount_percent'] as num?)?.toDouble() ?? 0.0,
        discount: (s['discount'] as num?)?.toDouble() ?? 0.0,
        additionalDiscount: (s['additional_discount'] as num?)?.toDouble() ?? 0.0,
        otherCharge: (s['other_charge'] as num?)?.toDouble() ?? 0.0,
        rcvdAmt: (s['rcvd_amt'] as num?)?.toDouble() ?? 0.0,
        roundOff: (s['round_off'] as num?)?.toDouble() ?? 0.0,
        grandTotal: (s['grand_total'] as num?)?.toDouble() ?? (s['total_amount'] as num?)?.toDouble() ?? 0.0,
        agent: s['agent'] ?? "Admin",
        expectingDate: s['expecting_date'] ?? "",
        specialCustomerName: s['special_customer_name'] ?? "",
        specialCustomerPhone: s['special_customer_phone'] ?? "",
        paymentRemarks: s['payment_remarks'] ?? "",
        secondaryAcc: s['secondary_acc'] ?? "",
        secondaryAmt: (s['secondary_amt'] as num?)?.toDouble() ?? 0.0,
        financialYear: s['financial_year'] ?? _getCalculatedFY(parsedDate),
        salesReturn: (s['sales_return_amt'] as num?)?.toDouble() ?? 0.0,
        isDeleted: (s['is_deleted'] as int?) == 1,
        isPaid: (s['is_paid'] as int?) == 1,
      );
    } catch (e) {
      debugPrint("getSaleInvoiceById Error: $e");
      return null;
    }
  }

  SaleReturnInvoice? getSaleReturnByNo(String returnNo) {
    try {
      return _saleReturns.firstWhere((inv) => inv.entryNo == returnNo || inv.entryNo == "SRET-$returnNo");
    } catch (e) {
      return null;
    }
  }

  Future<String> getNextPurchaseReturnEntryNo() async {
    return _peekNextNo('purchase_return_entries', 'entry_no', _selectedFinancialYear);
  }

  Future<String> getNextSaleReturnEntryNo() async {
    return _peekNextNo('sales_return_invoices', 'entry_no', _selectedFinancialYear);
  }

  int _naturalCompare(String a, String b) {
    final RegExp re = RegExp(r'(\d+)|(\D+)');
    final Iterable<RegExpMatch> matchesA = re.allMatches(a.toUpperCase());
    final Iterable<RegExpMatch> matchesB = re.allMatches(b.toUpperCase());
    final List<String> partsA = matchesA.map((m) => m.group(0)!).toList();
    final List<String> partsB = matchesB.map((m) => m.group(0)!).toList();

    for (int i = 0; i < partsA.length && i < partsB.length; i++) {
      final String partA = partsA[i];
      final String partB = partsB[i];
      final int? numA = int.tryParse(partA);
      final int? numB = int.tryParse(partB);

      if (numA != null && numB != null) {
        if (numA != numB) return numA.compareTo(numB);
      } else if (partA != partB) {
        return partA.compareTo(partB);
      }
    }
    return partsA.length.compareTo(partsB.length);
  }

  List<String> get suppliers => _suppliers;
  List<Supplier> get supplierMaster => _supplierMaster;
  List<String> get patients => _patients;
  List<Patient> get patientMaster => _patientMaster;
  List<String> get doctors => _doctors;
  List<Doctor> get doctorMaster => _doctorMaster;
  List<Staff> get staffMaster => _staffMaster;
  List<Staff> get activeStaffList => _staffMaster.where((s) => s.isActive).toList();
  List<String> get staffNames {
    if (_staffMaster.isNotEmpty) {
      return activeStaffList.map((s) => s.name).toList();
    }
    return ["Admin", "Jiyad", "Suresh", "Ramesh", "Staff 1", "Staff 2"];
  }
  List<String> get manufacturers => _manufacturers;
  List<Generic> get genericMaster => _generics;
  List<String> get generics => _generics.map((g) => g.name).toList();

  List<String> getRecentPatients() {
    final oneYearAgo = DateTime.now().subtract(const Duration(days: 365));
    final patients = _sales
        .where((s) => !s.isDeleted && s.date.isAfter(oneYearAgo))
        .map((s) => s.patient.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    patients.sort();
    return patients;
  }

  List<String> getRecentDoctors() {
    final oneYearAgo = DateTime.now().subtract(const Duration(days: 365));
    final doctors = _sales
        .where((s) => !s.isDeleted && s.date.isAfter(oneYearAgo))
        .map((s) => s.doctor.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    doctors.sort();
    return doctors;
  }

  double _cachedStockValue = 0.0;
  int _cachedStockCount = 0;
  List<Product> _cachedLowStockItems = [];
  List<Map<String, dynamic>> _cachedSpecialOrders = [];

  double get totalStockValue => _cachedStockValue;
  int get totalStockCount => _cachedStockCount;
  List<Product> get lowStockItems => _cachedLowStockItems;
  List<Map<String, dynamic>> get specialOrders => _cachedSpecialOrders;

  void _recalculateStockTotals() {
    double val = 0.0;
    int count = 0;
    for (var p in _products) {
      double ps = p.packSize > 0 ? p.packSize.toDouble() : 1.0;
      val += ((p.stock / ps) * p.purchaseRate);
      count += p.stock;
    }
    _cachedStockValue = val;
    _cachedStockCount = count;

    _cachedLowStockItems = _products
        .where((p) => p.stock > 0 && p.stock <= p.reorderLevel)
        .take(8)
        .toList();
  }

  void recalculateSpecialOrders() {
    List<Map<String, dynamic>> results = [];
    for (var sale in _sales) {
      if (sale.specialOrderJson != "[]" && sale.specialOrderJson.isNotEmpty) {
        try {
          List<dynamic> list = jsonDecode(sale.specialOrderJson);
          for (var item in list) {
            results.add({
              'name': item['name'],
              'qty': item['qty'],
              'patient': sale.patient,
              'date': sale.date,
              'customer': sale.specialCustomerName.isNotEmpty ? sale.specialCustomerName : sale.patient,
            });
          }
        } catch (_) {}
      }
    }
    results.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
    _cachedSpecialOrders = results;
  }

  double get todayRevenue => _todayRevenue;
  int get todaySalesCount => _todaySalesCount;
  double get todayPurchase => _todayPurchase;
  int get todayPurchasesCount => _todayPurchasesCount;

  double get monthlyPurchase => _monthlyPurchase;

  List<Product> get nonMovingProducts => _nonMovingProducts;

  Future<void> loadCompanyProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      companyProfile.name = prefs.getString('cp_name') ?? "SAHAKAR MEDICALS & SURGICALS";
      companyProfile.address = prefs.getString('cp_address') ?? "KALPETTA TOWN, WAYANAD";
      companyProfile.phone = prefs.getString('cp_phone') ?? "+91 0000000000";
      companyProfile.email = prefs.getString('cp_email') ?? "sahakar@gmail.com";
      companyProfile.gstIn = prefs.getString('cp_gst') ?? "32AAAAA0000A1Z5";
      companyProfile.dlNumber = prefs.getString('cp_dl') ?? "DL/123/2024";
      companyProfile.tagline = prefs.getString('cp_tagline') ?? "Professional Pharmacy Care";
      notifyListeners();
    } catch (e) {
      debugPrint("Error loading company profile: $e");
    }
  }

  Future<void> saveCompanyProfile(CompanyProfile profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cp_name', profile.name);
      await prefs.setString('cp_address', profile.address);
      await prefs.setString('cp_phone', profile.phone);
      await prefs.setString('cp_email', profile.email);
      await prefs.setString('cp_gst', profile.gstIn);
      await prefs.setString('cp_dl', profile.dlNumber);
      await prefs.setString('cp_tagline', profile.tagline);

      // Update in-memory profile
      companyProfile.name = profile.name;
      companyProfile.address = profile.address;
      companyProfile.phone = profile.phone;
      companyProfile.email = profile.email;
      companyProfile.gstIn = profile.gstIn;
      companyProfile.dlNumber = profile.dlNumber;
      companyProfile.tagline = profile.tagline;

      notifyListeners();
    } catch (e) {
      debugPrint("Error saving company profile: $e");
    }
  }

  Future<void> _initData() async {
    await loadCompanyProfile();
    await loadSoftwareOpeningDate();
    await loadSecuritySettings();
    await loadFromDatabase();
    await loadSalesDrafts();
    _loadImportMappings();
    _loadProductMappings();
    _fixMissingFinancialYears();
    
    // Pre-load voucher sequences into memory to make screen transitions instant
    unawaited(syncVoucherSequences());
  }


  Future<void> clearProductMaster() async {
    if (kIsWeb) return;
    final db = await DbHelper.instance.database;
    try {
      await db.transaction((txn) async {
        await txn.execute('PRAGMA foreign_keys = OFF;');
        await txn.delete('stock_batches');
        await txn.delete('product_master');
        await txn.delete('categories');
        await txn.delete('racks');
        await txn.delete('manufacturers');
        await txn.delete('generics');
        await txn.execute('PRAGMA foreign_keys = ON;');
      });
    } catch (e) {
      debugPrint("Clear Product Master Error: $e");
    }
    _products.clear();
    _productMaster.clear();
    _categories.clear();
    _categories.add("General");
    _racks.clear();
    _manufacturers.clear();
    _generics.clear();
    _searchCache.clear();
    notifyListeners();
  }

  Future<void> clearInventoryOnly() async {
    if (kIsWeb) return;
    final db = await DbHelper.instance.database;
    try {
      await db.delete('stock_batches');
    } catch (e) {
      debugPrint("Clear Inventory Error: $e");
    }
    await loadFromDatabase();
    notifyListeners();
  }

  Future<void> clearTransactionsOnly() async {
    if (kIsWeb) return;
    final db = await DbHelper.instance.database;
    try {
      await db.transaction((txn) async {
        final tables = [
          'sales_items', 'sales_invoices',
          'purchase_items', 'purchase_entries',
          'sales_return_items', 'sales_return_invoices',
          'purchase_return_items', 'purchase_return_entries',
          'stock_adjustment_items', 'stock_adjustments',
          'stock_write_offs',
          'supplier_payments', 'supplier_credit_notes',
          'prescriptions', 'prescription_items',
          'stock_batches' // Tied to transactions
        ];

        for (var table in tables) {
          try {
            await txn.delete(table);
          } catch (e) {
            debugPrint("Table $table clearing error: $e");
          }
        }

        // Reset balances in master tables as they depend on transactions
        await txn.update('suppliers', {'current_balance': 0.0});
        await txn.update('patients', {'current_balance': 0.0});
      });
    } catch (e) {
      debugPrint("Transaction Reset Error: $e");
    }

    _sales.clear();
    _purchases.clear();
    _saleReturns.clear();
    _purchaseReturns.clear();
    _adjustments.clear();
    _writeOffs.clear();
    _supplierPayments.clear();
    _supplierCreditNotes.clear();
    _prescriptions.clear();
    _products.clear();

    await loadFromDatabase();
    notifyListeners();
  }

  Future<void> clearAllStock() async {
    if (kIsWeb) return;
    final db = await DbHelper.instance.database;
    try {
      await db.transaction((txn) async {
        // Use a more robust way to clear tables
        final tables = [
          'stock_batches', 'product_master', 'sales_items', 'sales_invoices',
          'purchase_items', 'purchase_entries', 'sales_return_items',
          'sales_return_invoices', 'purchase_return_items', 'purchase_return_entries',
          'suppliers', 'patients', 'categories', 'racks', 'manufacturers', 'generics'
        ];

        for (var table in tables) {
          try {
            await txn.delete(table);
          } catch (e) {
            debugPrint("Table $table might not exist: $e");
          }
        }
      });
    } catch (e) {
      debugPrint("Transaction Error: $e");
    }

    // Explicitly clear all in-memory state
    _products.clear();
    _productMaster.clear();
    _sales.clear();
    _purchases.clear();
    _saleReturns.clear();
    _purchaseReturns.clear();

    _suppliers.clear();
    _patients.clear();
    _patients.add("General");
    _doctors.clear();
    _doctors.add("Unknown");
    _categories.clear();
    _categories.add("General");
    _racks.clear();
    _manufacturers.clear();
    _generics.clear();

    _searchCache.clear();

    await loadFromDatabase();
    notifyListeners();
  }

  Future<void> deleteProduct(String productId) async {
    try {
      final db = await DbHelper.instance.database;

      await db.transaction((txn) async {
        // 1. Guard: Block deletion if active shelf stock exists
        final stockCheck = await txn.rawQuery(
          'SELECT SUM(current_stock) as total_stock FROM stock_batches WHERE product_id = ?',
          [productId]
        );
        int totalStock = (stockCheck.first['total_stock'] as num?)?.toInt() ?? 0;
        if (totalStock > 0) {
          throw "Cannot deactivate product while $totalStock units of stock remain in inventory.";
        }

        // 2. Soft-delete by marking inactive instead of physical removal
        await txn.update(
          'product_master',
          {'is_active': 0},
          where: 'id = ?',
          whereArgs: [productId],
        );

        // Deactivate associated empty batches
        await txn.update(
          'stock_batches',
          {'is_active': 0},
          where: 'product_id = ?',
          whereArgs: [productId],
        );
      });

      // Synchronize in-memory caches
      _products.removeWhere((p) => p.id == productId);
      final mIdx = _productMaster.indexWhere((p) => p.id == productId);
      if (mIdx != -1) {
        _productMaster[mIdx].isActive = false;
      }
      _rebuildSearchIndex();
      notifyListeners();
    } catch (e) {
      debugPrint("Deactivate Product Error: $e");
      rethrow;
    }
  }

  Future<void> linkAllHistoricalData() async {
    final db = await DbHelper.instance.database;

    await db.transaction((txn) async {
      // 1. Link purchase items missing product_id by exact/case-insensitive name match
      await txn.rawUpdate('''
        UPDATE purchase_items 
        SET product_id = (
          SELECT pm.id FROM product_master pm 
          WHERE LOWER(TRIM(pm.name)) = LOWER(TRIM(purchase_items.product_name)) 
          LIMIT 1
        )
        WHERE product_id IS NULL OR product_id = '' OR product_id = 'UNKNOWN'
      ''');

      // 2. Link sales items missing product_id
      await txn.rawUpdate('''
        UPDATE sales_items 
        SET product_id = (
          SELECT pm.id FROM product_master pm 
          WHERE LOWER(TRIM(pm.name)) = LOWER(TRIM(sales_items.product_name)) 
          LIMIT 1
        )
        WHERE product_id IS NULL OR product_id = '' OR product_id = 'UNKNOWN'
      ''');

      // 3. Link stock batches to latest purchase metadata (P.Rate, Supplier, Landing Cost)
      await txn.rawUpdate('''
        UPDATE stock_batches 
        SET 
          purchase_rate = IFNULL((
            SELECT pi.p_rate FROM purchase_items pi 
            WHERE pi.product_id = stock_batches.product_id 
              AND pi.batch = stock_batches.batch_number 
            ORDER BY pi.id DESC LIMIT 1
          ), purchase_rate),
          supplier_name = IFNULL((
            SELECT pe.supplier_name FROM purchase_items pi 
            JOIN purchase_entries pe ON pi.entry_no = pe.entry_no
            WHERE pi.product_id = stock_batches.product_id 
              AND pi.batch = stock_batches.batch_number 
            ORDER BY pe.date DESC LIMIT 1
          ), supplier_name)
      ''');
    });

    await loadFromDatabase(); // Refresh in-memory state
    notifyListeners();
  }

  Future<void> loadFromDatabase() async {
    if (kIsWeb) return;
    try {
      invalidateSearchProductsCache();
      final db = await DbHelper.instance.database;

      // Auto-cleanup any dummy/invalid product entries created by misaligned Excel imports
      await _autoCleanupInvalidProducts(db);

      // confirm counts for the user log
      final countResult = await db.rawQuery('SELECT COUNT(*) as total FROM product_master');
      final totalInDb = countResult.first['total'] as int;
      debugPrint("--- DATABASE SYNC: $totalInDb products found in Master ---");

      // 0. Fetch all unique Financial Years from Opening Date + DB
      final Set<String> years = {};

      DateTime opening = softwareOpeningDate;
      int startYr = opening.year;
      if (opening.month < 4) startYr -= 1;

      DateTime now = DateTime.now();
      int currentYr = now.year;
      if (now.month < 4) currentYr -= 1;

      for (int y = startYr; y <= currentYr; y++) {
        years.add("$y-${(y + 1).toString().substring(2)}");
      }

      final saleYears = await db.rawQuery("SELECT DISTINCT financial_year FROM sales_invoices WHERE financial_year IS NOT NULL AND financial_year != ''");
      final purYears = await db.rawQuery("SELECT DISTINCT financial_year FROM purchase_entries WHERE financial_year IS NOT NULL AND financial_year != ''");
      final sRetYears = await db.rawQuery("SELECT DISTINCT financial_year FROM sales_return_invoices WHERE financial_year IS NOT NULL AND financial_year != ''");
      final pRetYears = await db.rawQuery("SELECT DISTINCT financial_year FROM purchase_return_entries WHERE financial_year IS NOT NULL AND financial_year != ''");
      final dmgYears = await db.rawQuery("SELECT DISTINCT financial_year FROM stock_write_offs WHERE financial_year IS NOT NULL AND financial_year != ''");
      final invYears = await db.rawQuery("SELECT DISTINCT financial_year FROM stock_batches WHERE financial_year IS NOT NULL AND financial_year != ''");

      for (var r in [...saleYears, ...purYears, ...sRetYears, ...pRetYears, ...dmgYears, ...invYears]) {
        if (r['financial_year'] != null && r['financial_year'].toString().trim().isNotEmpty) {
          years.add(r['financial_year'].toString().trim());
        }
      }
      
      // Sort descending (Newest on top!)
      _availableYears = years.toList()..sort((a, b) => b.compareTo(a));

      if (_selectedFinancialYear.isEmpty && _availableYears.isNotEmpty) {
        _selectedFinancialYear = _availableYears.first; // Default to newest year on top
      }

      _products.clear();
      _productMaster.clear();
      _searchCache.clear();

      // 1. FULL PRODUCT MASTER LOAD: Non-blocking chunked parsing to avoid isolate serialization lag
      final List<Map<String, dynamic>> masterResults = await db.query('product_master');
      final Map<String, Product> masterMap = {};

      const int chunkSize = 5000;
      for (int i = 0; i < masterResults.length; i += chunkSize) {
        final end = (i + chunkSize < masterResults.length) ? i + chunkSize : masterResults.length;
        for (int j = i; j < end; j++) {
          final row = masterResults[j];
          final p = Product(
            id: row['id'].toString(),
            name: row['name'] ?? "UNKNOWN",
            hsnCode: row['hsn_code'] ?? "",
            rack: row['rack_id'] ?? "",
            category: row['category_id'] ?? "General",
            subCategory: row['sub_category_id'] ?? "",
            packSize: (row['packing'] as num?)?.toInt() ?? 1,
            mrp: (row['mrp'] as num?)?.toDouble() ?? 0.0,
            purchaseRate: (row['purchase_rate'] as num?)?.toDouble() ?? 0.0,
            salePrice: (row['sale_rate'] as num?)?.toDouble() ?? 0.0,
            gstPercent: TaxCalculator.roundGstPercent((row['gst_percent'] as num?)?.toDouble() ?? 12.0),
            sDiscPercent: (row['s_disc_percent'] as num?)?.toDouble() ?? 0.0,
            patent: row['patent'] ?? "",
            schedule: row['schedule'] ?? "",
            reorderLevel: (row['reorder_level'] as num?)?.toInt() ?? 10,
            maxLevel: (row['max_level'] as num?)?.toInt() ?? 100,
            manufacturer: row['manufacturer_id'] ?? "",
            genericName: row['generic_name'] ?? "",
            stock: 0,
          );
          masterMap[p.id] = p;
        }
        if (end < masterResults.length) {
          await Future.delayed(Duration.zero); // Yield to keep UI smooth & 60fps
        }
      }

      // 2. INVENTORY LOAD: Load only ACTIVE stock batches with LEFT JOIN to guarantee product names
      final List<Map<String, dynamic>> batchResults = await db.rawQuery('''
        SELECT sb.*, 
               pm.name as master_name, 
               pm.generic_name as master_generic, 
               pm.hsn_code as master_hsn, 
               pm.category_id as master_category, 
               pm.rack_id as master_rack, 
               pm.packing as master_packing
        FROM stock_batches sb
        LEFT JOIN product_master pm ON sb.product_id = pm.id
        WHERE sb.current_stock > 0
      ''');

      for (int i = 0; i < batchResults.length; i++) {
        final row = batchResults[i];
        final productId = row['product_id'].toString();
        final currentStock = (row['current_stock'] as num?)?.toInt() ?? 0;

        String resolvedName = masterMap[productId]?.name ?? row['master_name']?.toString() ?? "UNKNOWN";

        final p = Product(
          id: productId,
          name: resolvedName,
          genericName: masterMap[productId]?.genericName ?? row['master_generic']?.toString() ?? "",
          hsnCode: masterMap[productId]?.hsnCode ?? row['master_hsn']?.toString() ?? "",
          category: masterMap[productId]?.category ?? row['master_category']?.toString() ?? "General",
          packSize: (row['packing'] as num?)?.toInt() ?? masterMap[productId]?.packSize ?? (row['master_packing'] as num?)?.toInt() ?? 1,
          batch: row['batch_number'] ?? "",
          expiry: row['expiry_date'] ?? "",
          stock: currentStock,
          purchaseRate: (row['purchase_rate'] as num?)?.toDouble() ?? 0.0,
          landingCost: (row['landing_cost'] as num?)?.toDouble() ?? 0.0,
          gstPercent: TaxCalculator.roundGstPercent((row['gst_percent'] as num?)?.toDouble() ?? 12.0),
          mrp: (row['mrp'] as num?)?.toDouble() ?? 0.0,
          salePrice: (row['sale_rate'] as num?)?.toDouble() ?? 0.0,
          supplier: row['supplier_name'] ?? "",
          rack: row['rack'] ?? masterMap[productId]?.rack ?? row['master_rack']?.toString() ?? "",
        );

        _products.add(p);

        // Update the total stock in the master record
        if (masterMap.containsKey(productId)) {
          masterMap[productId]!.stock += currentStock;
        }
        if (i % 2000 == 0 && i > 0) {
          await Future.delayed(Duration.zero);
        }
      }

      // Finalize initial master list & shelf inventory
      _productMaster.clear();
      _productMaster.addAll(masterMap.values);
      _recalculateStockTotals();

      // PROGRESSIVE UI HYDRATION: Update dashboard counters immediately
      notifyListeners();

      // DISABLED: masterResults already loaded the catalog.
      // Running this microtask re-allocates 50,000 objects and blocks the UI thread.
      // Future.microtask(() => _loadRemainingMasterProductsInBackground());

      // CODE MASTER FIX: EMERGENCY DATA SYNC
      // If _productMaster is still empty but we know rows exist, load basic names directly
      if (_productMaster.isEmpty && totalInDb > 0) {
        debugPrint("--- DATA RECOVERY: Loading $totalInDb master names directly ---");
        final basicResults = await db.query('product_master', columns: ['id', 'name', 'hsn_code', 'rack_id', 'category_id', 'packing', 'mrp', 'purchase_rate', 'sale_rate', 'gst_percent']);
        for (var row in basicResults) {
          _productMaster.add(Product(
            id: row['id'].toString(),
            name: row['name']?.toString() ?? "UNKNOWN",
            hsnCode: row['hsn_code']?.toString() ?? "",
            rack: row['rack_id']?.toString() ?? "",
            category: row['category_id']?.toString() ?? "General",
            packSize: (row['packing'] as num?)?.toInt() ?? 1,
            mrp: (row['mrp'] as num?)?.toDouble() ?? 0.0,
            purchaseRate: (row['purchase_rate'] as num?)?.toDouble() ?? 0.0,
            salePrice: (row['sale_rate'] as num?)?.toDouble() ?? 0.0,
            gstPercent: TaxCalculator.roundGstPercent((row['gst_percent'] as num?)?.toDouble() ?? 12.0),
            stock: 0,
          ));
        }
      }

      // Load Sales Transaction Frequency map
      await refreshSalesFrequency();

      // 2. Load Sales Invoices (Limit to 50 latest for UI speed)
      final List<Map<String, dynamic>> saleMaps = await db.query(
        'sales_invoices',
        where: "financial_year = ? OR financial_year IS NULL OR financial_year = ''",
        whereArgs: [_selectedFinancialYear],
        orderBy: 'date DESC',
        limit: 50
      );
      _sales.clear();

      for (var s in saleMaps) {
        DateTime? parsedDate;
        try {
          parsedDate = DateTime.parse(s['date']);
        } catch (_) {
          parsedDate = DateTime.tryParse(s['date'].toString().replaceAll('/', '-')) ?? DateTime.now();
        }

        String fy = s['financial_year']?.toString() ?? _getCalculatedFY(parsedDate);
        if (fy != _selectedFinancialYear) continue;

        String cleanSaleEntryNo = s['entry_no']?.toString() ?? "";
        if (cleanSaleEntryNo.contains('_')) {
          cleanSaleEntryNo = cleanSaleEntryNo.substring(cleanSaleEntryNo.indexOf('_') + 1);
        }

        _sales.add(SaleInvoice(
          entryNo: cleanSaleEntryNo,
          date: parsedDate,
          customerAcc: s['customer_acc'] ?? "Cash",
          patient: s['patient'] ?? "General",
          mobile: s['mobile'] ?? "",
          doctor: s['doctor'] ?? "Unknown",
          doctorRegNo: s['doctor_reg_no'] ?? "",
          specialOrderJson: s['special_order_json'] ?? "[]",
          taxType: s['tax_type'] ?? "Non Gst",
          days: s['days'] ?? 0,
          items: [],
          subTotal: (s['sub_total'] as num?)?.toDouble() ?? (s['total_amount'] as num?)?.toDouble() ?? 0.0,
          discountPercent: (s['discount_percent'] as num?)?.toDouble() ?? 0.0,
          discount: (s['discount'] as num?)?.toDouble() ?? 0.0,
          additionalDiscount: (s['additional_discount'] as num?)?.toDouble() ?? 0.0,
          otherCharge: (s['other_charge'] as num?)?.toDouble() ?? 0.0,
          rcvdAmt: (s['rcvd_amt'] as num?)?.toDouble() ?? 0.0,
          roundOff: (s['round_off'] as num?)?.toDouble() ?? 0.0,
          grandTotal: (s['grand_total'] as num?)?.toDouble() ?? (s['total_amount'] as num?)?.toDouble() ?? 0.0,
          agent: s['agent'] ?? "Admin", expectingDate: s['expecting_date'] ?? "",
          specialCustomerName: s['special_customer_name'] ?? "",
          specialCustomerPhone: s['special_customer_phone'] ?? "",
          paymentRemarks: s['payment_remarks'] ?? "",
          secondaryAcc: s['secondary_acc'] ?? "",
          secondaryAmt: (s['secondary_amt'] as num?)?.toDouble() ?? 0.0,
          financialYear: fy,
          isDeleted: (s['is_deleted'] as int?) == 1,
          isPaid: (s['is_paid'] as int?) == 1,
        ));
      }

      // 3. Load Purchase Entries (Limit to 50 latest for UI speed)
      final List<Map<String, dynamic>> purMaps = await db.query(
          'purchase_entries',
          where: "(financial_year = ? OR financial_year IS NULL OR financial_year = '') AND IFNULL(is_deleted, 0) = 0",
          whereArgs: [_selectedFinancialYear],
          orderBy: 'date DESC',
          limit: 50
      );

      // PRE-LOAD ITEMS FOR THE 50 LATEST ENTRIES
      final List<String> purEntryNos = purMaps.map((m) => m['entry_no'].toString()).toList();
      final String purInClause = purEntryNos.map((no) => "'$no'").join(',');
      final List<Map<String, dynamic>> allPurItems = purEntryNos.isEmpty ? [] : await db.rawQuery('''
        SELECT i.* FROM purchase_items i
        WHERE i.entry_no IN ($purInClause)
      ''');

      final Map<String, List<PurchaseItem>> purItemsMap = {};
      for (var i in allPurItems) {
        final en = i['entry_no']?.toString() ?? "";
        purItemsMap.putIfAbsent(en, () => []).add(PurchaseItem(
          id: i['product_id']?.toString() ?? "",
          productName: i['product_name'] ?? "",
          extra: i['extra'] ?? "",
          batch: i['batch'] ?? "",
          expiry: i['expiry'] ?? "",
          packin: (i['packin'] as num?)?.toInt() ?? 1,
          qty: (i['qty'] as num?)?.toInt() ?? 0,
          fQty: (i['f_qty'] as num?)?.toInt() ?? 0,
          mrp: (i['mrp'] as num?)?.toDouble() ?? 0.0,
          pRate: (i['p_rate'] as num?)?.toDouble() ?? 0.0,
          gross: (i['gross'] as num?)?.toDouble() ?? 0.0,
          discPercent: (i['disc_percent'] as num?)?.toDouble() ?? 0.0,
          discAmt: (i['disc_amt'] as num?)?.toDouble() ?? 0.0,
          net: (i['net'] as num?)?.toDouble() ?? 0.0,
          gstPercent: (i['gst_percent'] as num?)?.toDouble() ?? 0.0,
          gstAmt: (i['gst_amt'] as num?)?.toDouble() ?? 0.0,
          total: (i['total'] as num?)?.toDouble() ?? 0.0,
          sRate: (i['s_rate'] as num?)?.toDouble() ?? 0.0,
          lCost: (i['l_cost'] as num?)?.toDouble() ?? 0.0,
        ));
      }

      _purchases.clear();
      for (var p in purMaps) {
        DateTime purDate = DateTime.parse(p['date']);
        String fy = p['financial_year']?.toString() ?? _getCalculatedFY(purDate);
        if (fy != _selectedFinancialYear) continue;

        String rawDbEntryNo = p['entry_no']?.toString() ?? "";
        List<PurchaseItem> items = purItemsMap[rawDbEntryNo] ?? [];
        String cleanNo = rawDbEntryNo;
        if (cleanNo.contains('_')) {
          cleanNo = cleanNo.substring(cleanNo.indexOf('_') + 1);
        }

        _purchases.add(PurchaseEntry(
          entryNo: cleanNo,
          date: purDate,
          supplierName: p['supplier_name'] ?? "",
          supInvNo: cleanInvoiceNo(p['sup_inv_no']),
          supInvDate: p['sup_inv_date'] != null ? (DateTime.tryParse(p['sup_inv_date']) ?? purDate) : purDate,
          doneBy: p['done_by'] ?? "",
          invTotal: (p['inv_total'] as num?)?.toDouble() ?? 0.0,
          remarks: p['remarks'] ?? "",
          days: (p['days'] as num?)?.toInt() ?? 0,
          items: items,
          subTotal: (p['sub_total'] as num?)?.toDouble() ?? 0.0,
          discount: (p['discount'] as num?)?.toDouble() ?? 0.0,
          otherCharge: (p['other_charge'] as num?)?.toDouble() ?? 0.0,
          roundOff: (p['round_off'] as num?)?.toDouble() ?? 0.0,
          grandTotal: (p['grand_total'] as num?)?.toDouble() ?? 0.0,
          financialYear: fy,
          paymentStatus: p['payment_status'] ?? 0,
          paymentMode: p['payment_mode'],
          paymentRemarks: p['payment_remarks'],
          paymentDate: p['payment_date'] != null ? DateTime.tryParse(p['payment_date']) : null,
          paidAmount: (p['paid_amount'] as num?)?.toDouble() ?? 0.0,
        ));
      }

      // 3.1 Load Purchase Returns (Limit to 50)
      final List<Map<String, dynamic>> prMaps = await db.query(
          'purchase_return_entries',
          where: "(financial_year = ? OR financial_year IS NULL OR financial_year = '') AND IFNULL(is_deleted, 0) = 0",
          whereArgs: [_selectedFinancialYear],
          orderBy: 'date DESC',
          limit: 50
      );

      final List<String> prEntryNos = prMaps.map((m) => m['entry_no'].toString()).toList();
      final String prInClause = prEntryNos.map((no) => "'$no'").join(',');
      final List<Map<String, dynamic>> allPRItems = prEntryNos.isEmpty ? [] : await db.rawQuery('''
        SELECT i.* FROM purchase_return_items i
        WHERE i.entry_no IN ($prInClause)
      ''');

      final Map<String, List<PurchaseItem>> prItemsMap = {};
      for (var i in allPRItems) {
        final en = i['entry_no']?.toString() ?? "";
        prItemsMap.putIfAbsent(en, () => []).add(PurchaseItem(
          productName: i['product_name'] ?? "",
          batch: i['batch'] ?? "",
          expiry: i['expiry'] ?? "",
          qty: (i['qty'] as num?)?.toInt() ?? 0,
          fQty: (i['f_qty'] as num?)?.toInt() ?? 0,
          unit: i['unit'] ?? "BULK",
          packin: (i['packin'] as num?)?.toInt() ?? 1,
          mrp: (i['mrp'] as num?)?.toDouble() ?? 0.0,
          pRate: (i['p_rate'] as num?)?.toDouble() ?? 0.0,
          sRate: (i['s_rate'] as num?)?.toDouble() ?? 0.0,
          discPercent: (i['disc_percent'] as num?)?.toDouble() ?? 0.0,
          gstPercent: (i['gst_percent'] as num?)?.toDouble() ?? 0.0,
          total: (i['total'] as num?)?.toDouble() ?? 0.0,
          reason: i['reason'] ?? "",
          supplier: i['supplier'] ?? "",
          hsnCode: i['hsn_code'] ?? "",
        ));
      }

      _purchaseReturns.clear();
      for (var p in prMaps) {
        DateTime prDate = DateTime.parse(p['date']);
        String fy = p['financial_year']?.toString() ?? _getCalculatedFY(prDate);
        if (fy != _selectedFinancialYear) continue;

        String rawDbEntryNo = p['entry_no']?.toString() ?? "";
        List<PurchaseItem> items = prItemsMap[rawDbEntryNo] ?? [];
        String cleanNo = rawDbEntryNo;
        if (cleanNo.contains('_')) {
          cleanNo = cleanNo.substring(cleanNo.indexOf('_') + 1);
        }

        _purchaseReturns.add(PurchaseReturnEntry(
          entryNo: cleanNo,
          date: prDate,
          supplierName: p['supplier_name'] ?? "",
          originalPurchaseNo: p['original_purchase_no'] ?? "",
          doneBy: p['done_by'] ?? "",
          items: items,
          grandTotal: (p['grand_total'] as num?)?.toDouble() ?? 0.0,
          financialYear: fy,
        ));
      }

      // 3.2 Load Sales Returns (Limit to 50)
      final List<Map<String, dynamic>> srMaps = await db.query(
          'sales_return_invoices',
          where: "(financial_year = ? OR financial_year IS NULL OR financial_year = '') AND IFNULL(is_deleted, 0) = 0",
          whereArgs: [_selectedFinancialYear],
          orderBy: 'date DESC',
          limit: 50
      );

      final List<String> srEntryNos = srMaps.map((m) => m['entry_no'].toString()).toList();
      final String srInClause = srEntryNos.map((no) => "'$no'").join(',');
      final List<Map<String, dynamic>> allSRItems = srEntryNos.isEmpty ? [] : await db.rawQuery('''
        SELECT i.* FROM sales_return_items i
        WHERE i.return_no IN ($srInClause)
      ''');

      final Map<String, List<SaleItem>> srItemsMap = {};
      final Map<String, Product> productBatchLookup = {
        for (var prod in _products) "${prod.id}|${prod.batch.trim().toUpperCase()}": prod
      };

      for (var i in allSRItems) {
        final en = i['return_no']?.toString() ?? "";
        final pId = i['product_id'] ?? "";
        final pBatch = (i['batch_number'] ?? "").toString().trim();

        int qVal = (i['qty'] as num?)?.toInt() ?? (i['quantity'] as num?)?.toInt() ?? 0;
        int pVal = (i['packing'] as num?)?.toInt() ?? (i['packin'] as num?)?.toInt() ?? 1;
        double mrpVal = (i['mrp'] as num?)?.toDouble() ?? 0.0;
        double sRateVal = (i['sale_rate'] as num?)?.toDouble() ?? 0.0;
        double discPctVal = (i['disc_percent'] as num?)?.toDouble() ?? 0.0;
        double discAmtVal = (i['disc_amt'] as num?)?.toDouble() ?? 0.0;
        double gstPctVal = (i['gst_percent'] as num?)?.toDouble() ?? 12.0;

        final String lookupKey = "$pId|${pBatch.toUpperCase()}";
        final p = productBatchLookup[lookupKey] ?? Product(
          id: pId,
          name: i['product_name'] ?? "Unknown",
          batch: pBatch,
          expiry: i['expiry_date'] ?? "",
          mrp: mrpVal,
          salePrice: sRateVal,
          purchaseRate: (i['purchase_rate'] as num?)?.toDouble() ?? 0.0,
          landingCost: (i['landing_cost'] as num?)?.toDouble() ?? 0.0,
          gstPercent: gstPctVal,
          packSize: pVal,
          hsnCode: i['hsn_code']?.toString() ?? "",
        );

        srItemsMap.putIfAbsent(en, () => []).add(SaleItem(
          product: p,
          qty: qVal,
          packin: pVal,
          mrp: mrpVal,
          sRate: sRateVal,
          taxableSP: sRateVal,
          discPercent: discPctVal,
          discAmt: discAmtVal,
          gstPercent: gstPctVal,
          total: (i['total'] as num?)?.toDouble() ?? 0.0,
          purchaseRate: (i['purchase_rate'] as num?)?.toDouble() ?? 0.0,
          landingCost: (i['landing_cost'] as num?)?.toDouble() ?? 0.0,
          supplier: i['supplier_name']?.toString() ?? "",
        ));
      }

      _saleReturns.clear();
      for (var s in srMaps) {
        DateTime srDate = DateTime.parse(s['date']);
        String fy = s['financial_year']?.toString() ?? _getCalculatedFY(srDate);
        if (fy != _selectedFinancialYear) continue;

        String rawDbEntryNo = s['entry_no']?.toString() ?? "";
        List<SaleItem> items = srItemsMap[rawDbEntryNo] ?? [];
        String cleanNo = rawDbEntryNo;
        if (cleanNo.contains('_')) {
          cleanNo = cleanNo.substring(cleanNo.indexOf('_') + 1);
        }

        _saleReturns.add(SaleReturnInvoice(
          entryNo: cleanNo,
          date: srDate,
          customerAcc: s['customer_acc'] ?? "Cash",
          patient: s['patient'] ?? "General",
          doctor: s['doctor'] ?? "Unknown",
          originalInvoiceNo: s['original_invoice_no'] ?? "",
          items: items,
          subTotal: (s['sub_total'] as num?)?.toDouble() ?? 0.0,
          discount: (s['discount'] as num?)?.toDouble() ?? 0.0,
          roundOff: (s['round_off'] as num?)?.toDouble() ?? 0.0,
          grandTotal: (s['grand_total'] as num?)?.toDouble() ?? 0.0,
          narration: s['narration']?.toString() ?? "",
          gstMode: (s['gst_mode'] as int?) ?? 1,
          financialYear: fy,
        ));
      }

      // 3.1 Load Supplier Payments (Limit 100)
      final List<Map<String, dynamic>> payMaps = await db.query('supplier_payments', orderBy: 'date DESC', limit: 100);
      _supplierPayments.clear();
      for (var p in payMaps) {
        _supplierPayments.add(SupplierPayment(
          id: p['id'],
          supplierName: p['supplier_name'],
          date: DateTime.parse(p['date']),
          amount: (p['amount'] as num).toDouble(),
          invoiceNo: p['invoice_no'] ?? "",
          paymentMethod: p['payment_method'] ?? "CASH",
          remarks: p['remarks'] ?? "",
        ));
      }

      // 3.1.2 Load Patient Payments (Limit 100)
      final List<Map<String, dynamic>> patPayMaps = await db.query('patient_payments', orderBy: 'date DESC', limit: 100);
      _patientPayments.clear();
      for (var p in patPayMaps) {
        _patientPayments.add(SupplierPayment(
          id: p['id'],
          supplierName: p['patient_name'], // Note: using patient_name from DB
          date: DateTime.parse(p['date']),
          amount: (p['amount'] as num).toDouble(),
          invoiceNo: p['invoice_no'] ?? "",
          paymentMethod: p['payment_method'] ?? "CASH",
          remarks: p['remarks'] ?? "",
        ));
      }

      // 3.2 Load Supplier Credit Notes (Limit 100)
      final List<Map<String, dynamic>> cnMaps = await db.query('supplier_credit_notes', orderBy: 'date DESC', limit: 100);
      _supplierCreditNotes.clear();
      for (var p in cnMaps) {
        _supplierCreditNotes.add(SupplierCreditNote(
          id: p['id'],
          supplierName: p['supplier_name'],
          date: DateTime.parse(p['date']),
          amount: (p['amount'] as num).toDouble(),
          invoiceNo: p['invoice_no'] ?? "",
          remarks: p['remarks'] ?? "",
        ));
      }

      // 4. Load Stock Adjustments (Optimized Batch Loading)
      final List<Map<String, dynamic>> adjMaps = await db.query(
          'stock_adjustments',
          where: "(financial_year = ? OR financial_year IS NULL OR financial_year = '') AND IFNULL(is_deleted, 0) = 0",
          whereArgs: [_selectedFinancialYear],
          orderBy: 'date DESC'
      );

      final List<Map<String, dynamic>> allAdjItems = await db.rawQuery('''
        SELECT i.* FROM stock_adjustment_items i
        JOIN stock_adjustments e ON i.adjustment_no = e.entry_no
        WHERE (e.financial_year = ? OR e.financial_year IS NULL OR e.financial_year = '') AND IFNULL(e.is_deleted, 0) = 0
      ''', [_selectedFinancialYear]);

      final Map<String, List<StockAdjustmentItem>> adjItemsMap = {};
      for (var i in allAdjItems) {
        final en = i['adjustment_no']?.toString().trim() ?? "";
        final pId = (i['product_id'] ?? "").toString();
        final pBatch = (i['batch_number'] ?? "").toString().trim();

        final String lookupKey = "$pId|${pBatch.toUpperCase()}";
        final p = productBatchLookup[lookupKey] ?? Product(id: pId, name: "Unknown", batch: pBatch);

        adjItemsMap.putIfAbsent(en, () => []).add(StockAdjustmentItem(
          product: p,
          qty: (i['qty'] as num?)?.toInt() ?? 0,
          purchaseRate: (i['purchase_rate'] as num?)?.toDouble() ?? 0.0,
          total: (i['total'] as num?)?.toDouble() ?? 0.0,
        ));
      }

      _adjustments.clear();
      for (var adj in adjMaps) {
        final rawEn = adj['entry_no']?.toString().trim() ?? "";
        DateTime adjDate;
        try {
          adjDate = DateTime.parse(adj['date']);
        } catch (_) {
          adjDate = DateTime.now();
        }
        String fy = adj['financial_year']?.toString() ?? _getCalculatedFY(adjDate);
        if (fy != _selectedFinancialYear) continue;

        List<StockAdjustmentItem> items = adjItemsMap[rawEn] ?? [];
        String cleanNo = rawEn;
        if (cleanNo.contains('_')) {
          cleanNo = cleanNo.substring(cleanNo.indexOf('_') + 1);
        }

        _adjustments.add(StockAdjustment(
          entryNo: cleanNo,
          date: adjDate,
          doneBy: adj['done_by'] ?? "",
          reason: adj['reason'] ?? "",
          items: items,
          grandTotal: (adj['grand_total'] as num?)?.toDouble() ?? 0.0,
          financialYear: fy,
        ));
      }

      // 5. Load Stock Write-Offs
      final List<Map<String, dynamic>> writeOffMaps = await db.query(
          'stock_write_offs',
          where: "financial_year = ? OR financial_year IS NULL OR financial_year = ''",
          whereArgs: [_selectedFinancialYear],
          orderBy: 'date DESC'
      );
      _writeOffs.clear();
      for (var row in writeOffMaps) {
        DateTime woDate = DateTime.parse(row['date']);
        String fy = row['financial_year']?.toString() ?? _getCalculatedFY(woDate);
        if (fy != _selectedFinancialYear) continue;

        final p = _products.firstWhere(
                (prod) => prod.id == row['product_id'] && prod.batch == row['batch_number'],
            orElse: () => Product(id: row['product_id'] ?? '', name: "Unknown", batch: row['batch_number'] ?? "")
        );
        _writeOffs.add(StockWriteOff(
          id: row['id'],
          date: woDate,
          product: p,
          quantity: row['quantity'],
          reason: row['reason'] ?? "Damaged",
          lossValue: (row['loss_value'] as num?)?.toDouble() ?? 0.0,
          financialYear: fy,
        ));
      }

      // 4. Load Masters - Scan both dedicated tables and transaction data to populate drop-downs

      // 4.1 Suppliers
      _suppliers.clear();
      _supplierMaster.clear();

      await _loadSuppliersFromPrefs(); // Load from Prefs first (optional, depends on intent)

      final List<Map<String, dynamic>> supMaps = await db.query('suppliers');

      final List<Map<String, String>> initialSuppliers = [
        {'name': 'STARLEX HEALTH SERVICES AND PRODUCTS PVT LTD', 'phone': '7561005789', 'dl': 'KL-MLP-162224/20B,KL-MLP-162225/21B', 'gst': '32ABACS3075R1ZZ', 'addr': '5/1309, KOOTTAPPULAN BUILDING NEAR MOULANA HOSPITAL OOTY ROAD PERINTHALMANNA'},
        {'name': 'SAKTHI WHOLESALE', 'phone': '04936207673', 'dl': 'RLF20B2023KL000621', 'gst': '32AAACW4234F1ZR', 'addr': ''},
        {'name': 'WHITELINE ASSOCIATES', 'phone': '9061041276', 'dl': 'KL-WYD-147661', 'gst': '32AAAFW6395E1Z5', 'addr': ''},
        {'name': 'BY PHARMA', 'phone': '9895661133', 'dl': 'RLF20KL202300313', 'gst': '32AAJFB8040Q1Z6', 'addr': ''},
        {'name': 'ARAMANKAL ASSOCIATES', 'phone': '9400666477', 'dl': 'RLF20KL20230003138', 'gst': '32FXYPS5021K1ZU', 'addr': ''},
        {'name': 'FERNS HOSPITAL SUPPLIES', 'phone': '9526524400', 'dl': '137401/20B/2018', 'gst': '32AAAFF4746J1ZK', 'addr': ''},
        {'name': 'RESORT MEDICALS', 'phone': '', 'dl': 'RLF20KL202300', 'gst': '32AAMFR7845J1ZQ', 'addr': ''},
        {'name': 'NAVANA AGENCIES', 'phone': '', 'dl': '12/0012/21B', 'gst': '32AACFN3523F1ZU', 'addr': ''},
        {'name': 'NILIKKANDY MEDICALS', 'phone': '', 'dl': '', 'gst': '', 'addr': ''},
        {'name': 'flipkart', 'phone': '', 'dl': '', 'gst': '32AACCF0683K1ZQ', 'addr': ''},
        {'name': 'AMAZONE', 'phone': '', 'dl': '', 'gst': '32AAICA3918J1ZR', 'addr': ''},
        {'name': 'NESTO', 'phone': '', 'dl': '', 'gst': '32AAHAHCB9104E1Z4', 'addr': ''},
        {'name': 'pharma associates', 'phone': '', 'dl': '', 'gst': '32aaqfp4038d1ze', 'addr': ''},
        {'name': 'SOORYA LIFECARE', 'phone': '', 'dl': '', 'gst': '32ACGFS9095P1Z9', 'addr': ''},
        {'name': 'TOMS AGENCIES', 'phone': '', 'dl': 'RLF20KL2023003138', 'gst': '32AABFT6539Q1Z0', 'addr': ''},
        {'name': 'WAYANAD SURGICALS', 'phone': '', 'dl': '', 'gst': '32AABFW5972C1ZB', 'addr': ''},
        {'name': 'JANAPRIYA SHOP', 'phone': '', 'dl': '', 'gst': '12213210202121', 'addr': ''},
        {'name': 'RELIANCE DRUGS', 'phone': '', 'dl': 'RLF20KL2023003138', 'gst': '', 'addr': ''},
        {'name': 'LIYA COLLECTIONS', 'phone': '', 'dl': '', 'gst': '32BDXPA9344N1ZY', 'addr': ''},
        {'name': 'UNITED ENTERPRICES', 'phone': '', 'dl': '', 'gst': '32AAHFU8104A1ZP', 'addr': ''},
        {'name': 'NAVANA  AGENCIES', 'phone': '', 'dl': 'RLF20KL202300', 'gst': '32AACFN3523F1ZU', 'addr': ''},
        {'name': 'LIYA  COLLECTIONS', 'phone': '', 'dl': '', 'gst': '32BDXPA9344N1ZY', 'addr': ''},
        {'name': 'jeevamedicals', 'phone': '', 'dl': '', 'gst': 'fd32f222fdfdfdf', 'addr': ''},
        {'name': 'JAYALAKSHMI STORES', 'phone': '', 'dl': '', 'gst': 'DFDFD121F651DF2', 'addr': ''},
        {'name': 'RICHU MEDICAL AGENCY', 'phone': '', 'dl': 'WLF21B2024KL000043', 'gst': '32ABHFR7869L1ZH', 'addr': ''},
        {'name': 'JAYALAKSHMI TRADINGS', 'phone': '', 'dl': '', 'gst': '32AATPU4727D1ZH', 'addr': ''},
        {'name': 'PKM BUSINESS CORPORATION', 'phone': '', 'dl': '', 'gst': '32ABDFP5854F1ZB', 'addr': ''},
        {'name': 'SABARI DISTRIBUTION PVT LTD', 'phone': '', 'dl': '', 'gst': '32AAFCS3552D1ZR', 'addr': ''},
        {'name': 'VEEGEO ASSOCIATES', 'phone': '9567996535', 'dl': '', 'gst': '32AAKFV5592L1ZK', 'addr': ''},
        {'name': 'AGNISUTRA AYURVEDICS', 'phone': '7561094663', 'dl': '', 'gst': 'VIMAL KUMAR', 'addr': ''},
        {'name': 'WAYAND FLAVERS', 'phone': '9847627982', 'dl': '', 'gst': '', 'addr': ''},
        {'name': 'SREEV MARKETING', 'phone': '8547980454', 'dl': '', 'gst': '32AEZFS6630K1ZD', 'addr': ''},
        {'name': 'VET LINK PHARMA', 'phone': '9048669696', 'dl': 'RLF20KL2023003138', 'gst': '', 'addr': ''},
        {'name': 'KABANI SURGICALS', 'phone': '9747610397', 'dl': 'KL-WYD/154916', 'gst': 'RLF21KL2023003145', 'addr': ''},
        {'name': 'MEDPOPULUS HEALTHCARE', 'phone': '', 'dl': 'RLF20KL2023003138', 'gst': '32ABZFM4932B1Z7', 'addr': ''},
        {'name': 'ESTIMATE WHOLESALE', 'phone': '', 'dl': '', 'gst': '', 'addr': ''},
        {'name': 'UNITED AGENCIES BATHERY', 'phone': '9747874747', 'dl': '', 'gst': '', 'addr': ''},
        {'name': 'GEETHANJALI MEPPADI', 'phone': '', 'dl': '', 'gst': '32AOYPV2634K2Z8', 'addr': ''},
        {'name': 'JS ENTERPRICESS', 'phone': '', 'dl': '', 'gst': '', 'addr': ''},
        {'name': 'ARP AGENCIES BATHERY', 'phone': '9744687072', 'dl': '', 'gst': '', 'addr': ''},
        {'name': 'HEALTH ROOTS FOOD PRODUCT LLP', 'phone': '', 'dl': '', 'gst': '', 'addr': ''},
        {'name': 'PERFECT TRADE LINKS', 'phone': '9447759399', 'dl': '', 'gst': '', 'addr': 'MANANTHAVADY'},
        {'name': 'UNIVERSAL AGENCIES', 'phone': '', 'dl': '', 'gst': '', 'addr': ''},
        {'name': 'HITECH AGENCY', 'phone': '', 'dl': '', 'gst': '', 'addr': ''},
        {'name': 'MAS ENTERPRISES', 'phone': '', 'dl': '', 'gst': '32AADFM7727M1Z1', 'addr': ''},
        {'name': 'ANANDHA PHARMACY', 'phone': '', 'dl': 'KL-EKM-20B-135080', 'gst': '32AASCA4495Q', 'addr': ''},
        {'name': 'GREEN SPECIALITIES', 'phone': '', 'dl': 'KL-EKM-20B-135080', 'gst': '32AAHCG8341C1ZY', 'addr': ''},
        {'name': 'AEDENZ PHARMA', 'phone': '', 'dl': '', 'gst': '32AXXPV3580E1ZY', 'addr': ''},
        {'name': 'MANAYIL VEDAS', 'phone': '', 'dl': '', 'gst': '', 'addr': ''},
        {'name': 'KATTAKAYAM DRUG LINES', 'phone': '', 'dl': 'WLF20B2024KL000298', 'gst': '32AAVFK2576Q', 'addr': ''},
        {'name': 'SASA AGENCIES', 'phone': '', 'dl': 'RLF20KL2023003138', 'gst': '', 'addr': ''},
        {'name': 'CENTRAL AGENCIES', 'phone': '', 'dl': '0860/21B/NZ/93', 'gst': '32ACSPR4073Q1ZR', 'addr': ''},
        {'name': 'GREENS MARKETING', 'phone': '', 'dl': '', 'gst': '32AAJFG7879A1ZD', 'addr': ''},
        {'name': 'RINRAZ PHARMACEUTICALS', 'phone': '', 'dl': '', 'gst': '', 'addr': ''},
        {'name': 'THODUPUZHA DRUG HOUSE', 'phone': '', 'dl': 'WLF20B2024KL001001', 'gst': '', 'addr': ''},
        {'name': 'HANNA PHARMA', 'phone': '9447544957', 'dl': 'KL-WYD-133333/20B/18', 'gst': '32AALFH0910P1ZD', 'addr': 'MP VIII/479N, AMBALAPPADI, 54TH MILE, MEENANGADI 673591'},
        {'name': 'ALFA AGENCIES', 'phone': '', 'dl': '', 'gst': 'C14772', 'addr': ''},
        {'name': 'AVICOT SURGICALS', 'phone': '', 'dl': '', 'gst': '', 'addr': ''},
        {'name': 'VICTORY MEDICAL STORES', 'phone': '', 'dl': '', 'gst': '', 'addr': ''},
        {'name': 'CITY DRUGS', 'phone': '', 'dl': '', 'gst': '', 'addr': ''},
        {'name': 'DOCTORS PHARMA', 'phone': '', 'dl': '', 'gst': '', 'addr': ''},
        {'name': 'JAYA LAKSHMI', 'phone': '', 'dl': '', 'gst': '', 'addr': ''},
        {'name': 'YUZAXY PHARMA', 'phone': '', 'dl': '', 'gst': '', 'addr': ''},
        {'name': 'BIOREX SUPER SPECIALITY', 'phone': '', 'dl': '', 'gst': '', 'addr': ''},
        {'name': 'CENTURY PLASTICS', 'phone': '9745272035', 'dl': '', 'gst': '32AAHFC8674PIZT', 'addr': ''},
        {'name': 'THEKKEDATH DRUGS', 'phone': '', 'dl': 'RLF20KL2023003138', 'gst': '32AAKPC9592P1Z2', 'addr': ''},
        {'name': 'STAR AGENCIES', 'phone': '', 'dl': '', 'gst': '', 'addr': ''},
        {'name': 'JACKSON DRUG HOUSE', 'phone': '', 'dl': 'RLF20KL2023003145', 'gst': '32AACFJ2195H1ZK', 'addr': ''},
        {'name': 'CARCINO SPECIALITY PHARMA', 'phone': '', 'dl': 'RLF20KL2025000723', 'gst': '32AAMCC2025000723', 'addr': ''},
        {'name': 'V2R AGENCIES', 'phone': '', 'dl': '', 'gst': '', 'addr': ''},
        {'name': 'PEECEE DRUGS', 'phone': '', 'dl': 'WLF20B2024KL000402', 'gst': '', 'addr': ''},
      ];

      // Ensure all initial suppliers are in DB if they don't exist
      final supPrefs = await SharedPreferences.getInstance();
      if (supPrefs.getBool('initial_suppliers_seeded') != true) {
        await db.transaction((txn) async {
          for (var s in initialSuppliers) {
            bool exists = supMaps.any((m) => m['name'] == s['name']);
            if (!exists) {
              final id = DateTime.now().millisecondsSinceEpoch.toString() + s['name']!.hashCode.toString();
              await txn.insert('suppliers', {
                'id': id,
                'name': s['name'],
                'phone': s['phone'],
                'dl_number': s['dl'],
                'gst_in': s['gst'],
                'address': s['addr'],
                'current_balance': 0.0
              });
            }
          }
        });
        await supPrefs.setBool('initial_suppliers_seeded', true);
      }

      // Re-query to get everything (existing + newly added)
      final List<Map<String, dynamic>> allSupMaps = await db.query('suppliers');
      for (var s in allSupMaps) {
        String name = s['name']?.toString().trim() ?? "";
        if (name.isNotEmpty && !_suppliers.contains(name)) {
          _suppliers.add(name);
          _supplierMaster.add(Supplier(
            id: s['id'],
            name: name,
            address: s['address'] ?? "",
            phone: s['phone'] ?? "",
            gstIn: s['gst_in'] ?? "",
            dlNumber: s['dl_number'] ?? "",
            currentBalance: (s['current_balance'] ?? 0.0).toDouble(),
          ));
        }
      }
      // Scan purchase history for existing suppliers
      final List<Map<String, dynamic>> purSups = await db.rawQuery('SELECT DISTINCT supplier_name FROM purchase_entries');
      for (var s in purSups) {
        String name = s['supplier_name']?.toString().trim() ?? "";
        if (name.isNotEmpty && !_suppliers.contains(name)) {
          _suppliers.add(name);
          if (!_supplierMaster.any((it) => it.name == name)) {
            _supplierMaster.add(Supplier(id: "SUP_HIST_$name", name: name));
          }
        }
      }
      await _saveSuppliersToPrefs();

      // 4.2 Patients & Doctors
      _patients.clear();
      _patients.add("General");
      _patientMaster.clear();

      final List<Map<String, dynamic>> patMaps = await db.query('patients');
      for (var p in patMaps) {
        final patient = Patient.fromMap(p);
        _patientMaster.add(patient);
        if (!_patients.contains(patient.name)) {
          _patients.add(patient.name);
        }
      }

      final oneYearAgo = DateTime.now().subtract(const Duration(days: 365)).toIso8601String();
      final List<Map<String, dynamic>> patEntries = await db.rawQuery(
          'SELECT DISTINCT patient FROM sales_invoices WHERE date >= ?', [oneYearAgo]
      );
      for (var p in patEntries) {
        String name = p['patient']?.toString().trim() ?? "";
        if (name.isNotEmpty && !_patients.contains(name)) {
          _patients.add(name);
          if (!_patientMaster.any((it) => it.name == name)) {
            _patientMaster.add(Patient(id: "PAT_HIST_$name", name: name));
          }
        }
      }

      _doctors.clear();
      _doctors.add("Unknown");
      _doctorMaster.clear();
      final List<Map<String, dynamic>> docMaps = await db.query('doctors');
      for (var d in docMaps) {
        final doctor = Doctor.fromMap(d);
        _doctorMaster.add(doctor);
        if (!_doctors.contains(doctor.name)) {
          _doctors.add(doctor.name);
        }
      }

      final List<Map<String, dynamic>> docEntries = await db.rawQuery(
          'SELECT DISTINCT doctor FROM sales_invoices WHERE date >= ?', [oneYearAgo]
      );
      for (var d in docEntries) {
        String name = d['doctor']?.toString().trim() ?? "";
        if (name.isNotEmpty && !_doctors.contains(name)) {
          _doctors.add(name);
          if (!_doctorMaster.any((it) => it.name == name)) {
            _doctorMaster.add(Doctor(id: "DOC_HIST_$name", name: name));
          }
        }
      }

      // 4.2.1 Staff Master
      await _loadStaffFromDb(db);

      // 4.3 Prescriptions (Optimized Loading)
      final List<Map<String, dynamic>> presMaps = await db.query(
          'prescriptions',
          where: "financial_year = ? OR financial_year IS NULL OR financial_year = ''",
          whereArgs: [_selectedFinancialYear],
          orderBy: 'date DESC'
      );

      final List<Map<String, dynamic>> allPresItems = await db.rawQuery('''
        SELECT i.* FROM prescription_items i
        JOIN prescriptions e ON i.prescription_id = e.id
        WHERE e.financial_year = ? OR e.financial_year IS NULL OR e.financial_year = ''
      ''', [_selectedFinancialYear]);

      final Map<String, List<PrescriptionItem>> presItemsMap = {};
      for (var item in allPresItems) {
        final presId = item['prescription_id'] as String;
        presItemsMap.putIfAbsent(presId, () => []).add(PrescriptionItem(
          name: item['name'],
          qty: (item['qty'] as num?)?.toDouble() ?? 0.0,
        ));
      }

      _prescriptions.clear();
      for (var p in presMaps) {
        final id = p['id'] as String;
        DateTime presDate = DateTime.parse(p['date']);
        String fy = p['financial_year']?.toString() ?? _getCalculatedFY(presDate);
        if (fy != _selectedFinancialYear) continue;

        _prescriptions.add(Prescription(
          id: id,
          prescriptionNo: p['prescription_no'] ?? 0,
          patientName: p['patient_name'] ?? "",
          doctorName: p['doctor_name'] ?? "",
          diseaseName: p['disease_name'] ?? "",
          mobile: p['mobile'] ?? "",
          days: p['days'] ?? 0,
          date: presDate,
          saleEntryNo: p['sale_entry_no'] ?? "",
          isActive: (p['is_active'] as int?) == 1,
          isImported: (p['is_imported'] as int?) == 1,
          financialYear: fy,
          items: presItemsMap[id] ?? [],
        ));
      }

      // 4.4 Categories - Load from table only (Avoid 50k table scan)
      _categories.clear();
      _categories.addAll(["General", "Tablets", "Syrups", "Injections", "OTC"]);
      final List<Map<String, dynamic>> catMaps = await db.query('categories');
      for (var c in catMaps) {
        String name = c['name']?.toString().trim() ?? "";
        if (name.isNotEmpty && !_categories.contains(name)) _categories.add(name);
      }

      // 4.5 Racks - Load from table only (Avoid 50k table scan)
      _racks.clear();
      _rackStatus.clear();
      _racks.addAll(["A1", "A2", "B1", "B2"]);
      final List<Map<String, dynamic>> rackMaps = await db.query('racks');
      for (var r in rackMaps) {
        String name = r['name']?.toString().trim() ?? "";
        if (name.isNotEmpty) {
          if (!_racks.contains(name)) _racks.add(name);
          _rackStatus[name] = (r['is_active'] as int?) == 1;
        }
      }

      // 4.6 Manufacturers - Load from table only (Avoid 50k table scan)
      _manufacturers.clear();
      _manufacturers.addAll(["NEVIA", "GSK", "CIPLA"]);
      final List<Map<String, dynamic>> manMaps = await db.query('manufacturers');
      for (var m in manMaps) {
        String name = m['name']?.toString().trim() ?? "";
        if (name.isNotEmpty && !_manufacturers.contains(name)) _manufacturers.add(name);
      }

      // 4.7 Generics - Load from table only (Avoid 50k table scan)
      _generics.clear();
      final List<Map<String, dynamic>> genMaps = await db.query('generics');
      for (var g in genMaps) {
        _generics.add(Generic.fromMap(g));
      }

      // 5. Calculate Dashboard Stats using indexed date bounds
      final todayStart = DateTime(now.year, now.month, now.day, 0, 0, 0).toIso8601String();
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59).toIso8601String();
      final monthStartStr = DateFormat('yyyy-MM-01').format(now);

      final List<Map<String, dynamic>> salesStats = await db.rawQuery('''
        SELECT SUM(grand_total) as revenue, COUNT(*) as count 
        FROM sales_invoices 
        WHERE date >= ? AND date <= ? AND is_deleted = 0
      ''', [todayStart, todayEnd]);
      _todayRevenue = (salesStats.first['revenue'] as num?)?.toDouble() ?? 0.0;
      _todaySalesCount = (salesStats.first['count'] as num?)?.toInt() ?? 0;

      final List<Map<String, dynamic>> purStats = await db.rawQuery('''
        SELECT SUM(grand_total) as total, COUNT(*) as count 
        FROM purchase_entries 
        WHERE date >= ? AND date <= ? AND is_deleted = 0
      ''', [todayStart, todayEnd]);
      _todayPurchase = (purStats.first['total'] as num?)?.toDouble() ?? 0.0;
      _todayPurchasesCount = (purStats.first['count'] as num?)?.toInt() ?? 0;

      final List<Map<String, dynamic>> monthPur = await db.rawQuery('''
        SELECT SUM(grand_total) as total 
        FROM purchase_entries 
        WHERE date >= ? AND is_deleted = 0 AND (financial_year = ? OR financial_year IS NULL OR financial_year = '')
      ''', [monthStartStr, _selectedFinancialYear]);
      _monthlyPurchase = (monthPur.first['total'] as num?)?.toDouble() ?? 0.0;

      // Defer non-moving items calculation to a microtask so startup renders immediately
      Future.microtask(() async {
        try {
          final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
          final List<Map<String, dynamic>> soldRecently = await db.rawQuery('''
            SELECT DISTINCT product_id FROM sales_items si
            JOIN sales_invoices sn ON si.invoice_no = sn.entry_no
            WHERE sn.date >= ? AND sn.is_deleted = 0
          ''', [thirtyDaysAgo]);
          final soldIds = soldRecently.map((r) => r['product_id'].toString()).toSet();
          _nonMovingProducts = _products.where((p) => p.stock > 0 && !soldIds.contains(p.id)).toList();
        } catch (_) {}
      });

      _rebuildSearchIndex();
      await fetchAccounts();
      notifyListeners();
    } catch (e) {
      debugPrint("DB Load Error: $e");
    }
  }

  Future<String> getNextSaleEntryNo() async {
    return _peekNextNo('sales_invoices', 'entry_no', _selectedFinancialYear, excludePrefix: 'ORD-');
  }

  Future<String> getNextPurchaseEntryNo() async {
    return _peekNextNo('purchase_entries', 'entry_no', _selectedFinancialYear);
  }

  Future<String> getNextAdjustmentNo() async {
    return _peekNextNo('stock_adjustments', 'entry_no', _selectedFinancialYear);
  }

  Future<String> _peekNextNo(String table, String column, String fy, {String? excludePrefix}) async {
    final db = await DbHelper.instance.database;

    final res = await db.query(
      'voucher_sequences',
      columns: ['last_sequence'],
      where: 'voucher_type = ? AND financial_year = ?',
      whereArgs: [table, fy],
    );

    int lastSeq = 0;
    if (res.isNotEmpty) {
      lastSeq = (res.first['last_sequence'] as int? ?? 0);
    }

    if (lastSeq > 0) {
      int effectiveLast = lastSeq;
      if (table == 'purchase_entries' && _purchases.isNotEmpty) {
        for (var p in _purchases) {
          String clean = cleanEntryNo(p.entryNo);
          int? parsed = int.tryParse(clean);
          if (parsed != null && parsed > effectiveLast) effectiveLast = parsed;
        }
      } else if (table == 'sales_invoices' && _sales.isNotEmpty) {
        for (var s in _sales) {
          String clean = cleanEntryNo(s.entryNo);
          int? parsed = int.tryParse(clean);
          if (parsed != null && parsed > effectiveLast) effectiveLast = parsed;
        }
      }
      return (effectiveLast + 1).toString();
    }

    String cleanColExpr = "CASE WHEN instr($column, '_') > 0 THEN substr($column, instr($column, '_') + 1) ELSE REPLACE(REPLACE(REPLACE(REPLACE($column, 'SRET-', ''), 'PRET-', ''), 'ADJ-', ''), 'ORD-', '') END";
    String where = "financial_year = ?";
    List<dynamic> args = [fy];
    if (excludePrefix != null) {
      where += " AND $column NOT LIKE ?";
      args.add("$excludePrefix%");
    }
    
    final maxRes = await db.rawQuery(
        "SELECT MAX(CAST($cleanColExpr AS INTEGER)) as max_no FROM $table WHERE $where", 
        args
    );
    int maxInDb = (maxRes.first['max_no'] as num?)?.toInt() ?? 0;

    int effectiveLast = maxInDb > lastSeq ? maxInDb : lastSeq;

    if (table == 'purchase_entries' && _purchases.isNotEmpty) {
      for (var p in _purchases) {
        String clean = cleanEntryNo(p.entryNo);
        int? parsed = int.tryParse(clean);
        if (parsed != null && parsed > effectiveLast) {
          effectiveLast = parsed;
        }
      }
    } else if (table == 'sales_invoices' && _sales.isNotEmpty) {
      for (var s in _sales) {
        String clean = cleanEntryNo(s.entryNo);
        int? parsed = int.tryParse(clean);
        if (parsed != null && parsed > effectiveLast) {
          effectiveLast = parsed;
        }
      }
    }

    if (effectiveLast > lastSeq || res.isEmpty) {
      await db.insert('voucher_sequences', {
        'voucher_type': table,
        'financial_year': fy,
        'last_sequence': effectiveLast
      }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
    }

    int nextSeq = effectiveLast + 1;
    return nextSeq.toString();
  }

  Future<void> syncVoucherSequences() async {
    try {
      final db = await DbHelper.instance.database;
      final tables = [
        {'table': 'purchase_entries', 'col': 'entry_no'},
        {'table': 'sales_invoices', 'col': 'entry_no'},
        {'table': 'purchase_return_entries', 'col': 'entry_no'},
        {'table': 'sales_return_invoices', 'col': 'entry_no'},
        {'table': 'stock_adjustments', 'col': 'entry_no'},
      ];

      for (var t in tables) {
        String table = t['table']!;
        String col = t['col']!;
        
        final fyList = await db.rawQuery("SELECT DISTINCT financial_year FROM $table WHERE financial_year IS NOT NULL AND financial_year != ''");
        List<String> fys = fyList.map((r) => r['financial_year'] as String).toList();
        if (_selectedFinancialYear.isNotEmpty && !fys.contains(_selectedFinancialYear)) {
          fys.add(_selectedFinancialYear);
        }

        for (String fy in fys) {
          String cleanColExpr = "CASE WHEN instr($col, '_') > 0 THEN substr($col, instr($col, '_') + 1) ELSE REPLACE(REPLACE(REPLACE($col, 'SRET-', ''), 'PRET-', ''), 'ADJ-', '') END";
          final maxRes = await db.rawQuery("SELECT MAX(CAST($cleanColExpr AS INTEGER)) as max_no FROM $table WHERE financial_year = ?", [fy]);
          int maxInDb = (maxRes.first['max_no'] as num?)?.toInt() ?? 0;

          if (maxInDb > 0) {
            final res = await db.query(
              'voucher_sequences',
              where: 'voucher_type = ? AND financial_year = ?',
              whereArgs: [table, fy],
            );
            if (res.isNotEmpty) {
              int lastSeq = (res.first['last_sequence'] as int? ?? 0);
              if (maxInDb > lastSeq) {
                await db.update('voucher_sequences', {'last_sequence': maxInDb}, where: 'voucher_type = ? AND financial_year = ?', whereArgs: [table, fy]);
              }
            } else {
              await db.insert('voucher_sequences', {'voucher_type': table, 'financial_year': fy, 'last_sequence': maxInDb});
            }
          }
        }
      }
    } catch (e) {
      debugPrint("syncVoucherSequences error: $e");
    }
  }

  Future<String> getNextPrescriptionNo() async {
    return _peekNextNo('prescriptions', 'prescription_no', _selectedFinancialYear);
  }

  int _lastProductNumId = 0;

  String generateUniqueId() {
    int now = DateTime.now().millisecondsSinceEpoch;
    if (now <= _lastProductNumId) {
      now = _lastProductNumId + 1;
    }
    _lastProductNumId = now;
    return now.toString();
  }

  String generate10DigitId() => generateUniqueId();

  void addProduct(Product p) async {
    if (p.patent.trim().isNotEmpty && !_manufacturers.contains(p.patent.trim())) {
      _manufacturers.add(p.patent.trim());
    }
    if (p.manufacturer.trim().isNotEmpty && !_manufacturers.contains(p.manufacturer.trim())) {
      _manufacturers.add(p.manufacturer.trim());
    }
    if (p.category.trim().isNotEmpty && !_categories.contains(p.category.trim())) {
      _categories.add(p.category.trim());
    }

    // Only register to Product Master (Master catalog)
    if (!_productMaster.any((master) => master.id == p.id)) {
      _productMaster.add(p);
    }

    // Only add to _products (active batches) if it has a real batch number and stock
    if (p.batch.trim().isNotEmpty && p.stock > 0) {
      _products.add(p);
    }

    if (!kIsWeb) {
      final db = await DbHelper.instance.database;

      if (p.rack.isNotEmpty) {
        await db.insert('rack_history', {
          'product_id': p.id,
          'product_name': p.name,
          'old_rack': "NONE",
          'new_rack': p.rack,
          'change_date': DateTime.now().toIso8601String(),
        });
      }

      await db.insert('product_master', p.toMasterMap(), conflictAlgorithm: sql.ConflictAlgorithm.replace);
    }
    _rebuildSearchIndex();
    trackProductModified(p);
  }

  void updateProduct(Product p) async {
    if (p.patent.trim().isNotEmpty && !_manufacturers.contains(p.patent.trim())) {
      _manufacturers.add(p.patent.trim());
    }
    if (p.manufacturer.trim().isNotEmpty && !_manufacturers.contains(p.manufacturer.trim())) {
      _manufacturers.add(p.manufacturer.trim());
    }
    if (p.category.trim().isNotEmpty && !_categories.contains(p.category.trim())) {
      _categories.add(p.category.trim());
    }

    int mIdx = _productMaster.indexWhere((m) => m.id == p.id);
    String oldRack = "";
    if (mIdx != -1) {
      oldRack = _productMaster[mIdx].rack;
      _productMaster[mIdx] = p;
    }

    // Update all batches in memory
    for (int i = 0; i < _products.length; i++) {
      if (_products[i].id == p.id) {
        _products[i].name = p.name;
        _products[i].hsnCode = p.hsnCode;
        _products[i].category = p.category;
        _products[i].packSize = p.packSize;
        _products[i].rack = p.rack;
        _products[i].genericName = p.genericName;
        _products[i].gstPercent = p.gstPercent;
        _products[i].sDiscPercent = p.sDiscPercent;
        _products[i].schedule = p.schedule;
        _products[i].patent = p.patent;
        _products[i].preferredWholesale = p.preferredWholesale;
        _products[i].leadTime = p.leadTime;
      }
    }

    if (!kIsWeb) {
      final db = await DbHelper.instance.database;

      // RECORD RACK HISTORY IF CHANGED
      if (oldRack != p.rack) {
        await db.insert('rack_history', {
          'product_id': p.id,
          'product_name': p.name,
          'old_rack': oldRack,
          'new_rack': p.rack,
          'change_date': DateTime.now().toIso8601String(),
        });
      }

      await db.update('product_master', p.toMasterMap(), where: 'id = ?', whereArgs: [p.id]);

      // Also update name and other master fields in stock_batches if they are stored there (usually not, joined via product_id)
      // If name is duplicated in stock_batches for performance, update it there too.
    }
    _rebuildSearchIndex();
    trackProductModified(p);
  }


  void addCategory(String name) async {
    if (!_categories.contains(name)) {
      _categories.add(name);
      if (!kIsWeb) {
        final db = await DbHelper.instance.database;
        await db.insert('categories', {'id': name, 'name': name}, conflictAlgorithm: sql.ConflictAlgorithm.ignore);
      }
      notifyListeners();
    }
  }

  void addSupplier(String name) async {
    if (!_suppliers.contains(name)) {
      _suppliers.add(name);
      _supplierMaster.add(Supplier(id: name, name: name));
      if (!kIsWeb) {
        final db = await DbHelper.instance.database;
        await db.insert('suppliers', {'id': name, 'name': name}, conflictAlgorithm: sql.ConflictAlgorithm.ignore);
      }
      await _saveSuppliersToPrefs();
      notifyListeners();
    }
  }

  Future<void> registerSupplier(Supplier s) async {
    final db = await DbHelper.instance.database;
    await db.insert('suppliers', {
      'id': s.id,
      'name': s.name,
      'address': s.address,
      'phone': s.phone,
      'gst_in': s.gstIn,
      'dl_number': s.dlNumber,
      'current_balance': s.currentBalance,
    }, conflictAlgorithm: sql.ConflictAlgorithm.replace);

    _supplierMaster.add(s);
    if (!_suppliers.contains(s.name)) {
      _suppliers.add(s.name);
      await _saveSuppliersToPrefs();
    }
    notifyListeners();
  }


  Future<void> updateSupplier(Supplier s) async {
    final db = await DbHelper.instance.database;
    await db.update('suppliers', {
      'name': s.name,
      'address': s.address,
      'phone': s.phone,
      'gst_in': s.gstIn,
      'dl_number': s.dlNumber,
      'current_balance': s.currentBalance,
    }, where: 'id = ?', whereArgs: [s.id]);

    int idx = _supplierMaster.indexWhere((it) => it.id == s.id);
    if (idx != -1) {
      String oldName = _supplierMaster[idx].name;
      _supplierMaster[idx] = s;
      int sIdx = _suppliers.indexOf(oldName);
      if (sIdx != -1) {
        _suppliers[sIdx] = s.name;
        await _saveSuppliersToPrefs();
      }
    }
    notifyListeners();
  }


  Future<void> deleteSupplier(String id) async {
    final db = await DbHelper.instance.database;
    await db.delete('suppliers', where: 'id = ?', whereArgs: [id]);

    int idx = _supplierMaster.indexWhere((it) => it.id == id);
    if (idx != -1) {
      String name = _supplierMaster[idx].name;
      _supplierMaster.removeAt(idx);
      _suppliers.remove(name);
    }
    await _saveSuppliersToPrefs();
    notifyListeners();
  }

  // --- ACCOUNTS MANAGEMENT ---
  Future<void> fetchAccounts() async {
    final db = await DbHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query('accounts');
    _accountMaster.clear();
    _accounts.clear();
    for (var m in maps) {
      final acc = Account.fromMap(m);
      _accountMaster.add(acc);
      _accounts.add(acc.name);
    }
    notifyListeners();
  }

  Future<bool> addAccount(String name, {bool isActive = true, String? color}) async {
    final db = await DbHelper.instance.database;
    
    if (_accounts.any((a) => a.toLowerCase() == name.toLowerCase())) return false;

    final id = "ACC_${DateTime.now().millisecondsSinceEpoch}";
    
    // Random attractive colors
    final List<String> randomColors = [
      '0xFF6366F1', '0xFF8B5CF6', '0xFFEC4899', '0xFFF97316', 
      '0xFF14B8A6', '0xFFF59E0B', '0xFF0EA5E9'
    ];
    final assignedColor = color ?? randomColors[Random().nextInt(randomColors.length)];

    final acc = Account(id: id, name: name, isActive: isActive, color: assignedColor);
    await db.insert('accounts', acc.toMap());
    
    _accountMaster.add(acc);
    _accounts.add(name);
    notifyListeners();
    return true;
  }

  Future<bool> updateAccount(String id, String newName, {bool isActive = true, String? color}) async {
    final db = await DbHelper.instance.database;
    
    int mIdx = _accountMaster.indexWhere((a) => a.id == id);
    if (mIdx == -1) return false;

    String oldName = _accountMaster[mIdx].name;

    // Duplicate check if name changed
    if (oldName.toLowerCase() != newName.toLowerCase()) {
      if (_accounts.any((a) => a.toLowerCase() == newName.toLowerCase())) return false;
    }

    final Map<String, dynamic> updateData = {
      'name': newName,
      'is_active': isActive ? 1 : 0,
    };
    if (color != null) updateData['color'] = color;

    await db.update('accounts', updateData, where: 'id = ?', whereArgs: [id]);
    
    _accountMaster[mIdx].name = newName;
    _accountMaster[mIdx].isActive = isActive;
    if (color != null) _accountMaster[mIdx].color = color;
    
    int sIdx = _accounts.indexOf(oldName);
    if (sIdx != -1) {
      _accounts[sIdx] = newName;
    }
    
    notifyListeners();
    return true;
  }

  Future<void> deleteAccount(String id) async {
    final db = await DbHelper.instance.database;
    
    int idx = _accountMaster.indexWhere((a) => a.id == id);
    if (idx == -1 || _accountMaster[idx].name == "CASH") return;

    final account = _accountMaster[idx];
    
    // Check if account has been used in sales
    final List<Map> usage = await db.query('sales_invoices', where: 'customer_acc = ?', whereArgs: [account.name], limit: 1);
    
    if (usage.isNotEmpty) {
      // Soft Delete: Rename and Deactivate
      String deletedName = "${account.name} [DELETED]";
      await db.update('accounts', {
        'name': deletedName,
        'is_active': 0,
      }, where: 'id = ?', whereArgs: [id]);
      
      account.name = deletedName;
      account.isActive = false;
      
      int sIdx = _accounts.indexOf(account.name.replaceAll(' [DELETED]', ''));
      if (sIdx != -1) _accounts[sIdx] = deletedName;
    } else {
      // Hard Delete: Not used anywhere
      await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
      _accounts.remove(account.name);
      _accountMaster.removeAt(idx);
    }
    
    notifyListeners();
  }

  // --- SharedPreferences for Suppliers ---
  Future<void> _saveSuppliersToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('supplier_names', _suppliers);
    } catch (e) {
      debugPrint("Error saving suppliers to prefs: $e");
    }
  }

  Future<void> _loadSuppliersFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? stored = prefs.getStringList('supplier_names');
      if (stored != null && stored.isNotEmpty) {
        for (var name in stored) {
          if (!_suppliers.contains(name)) {
            _suppliers.add(name);
            if (!_supplierMaster.any((it) => it.name == name)) {
              _supplierMaster.add(Supplier(id: "SUP_PREF_$name", name: name));
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error loading suppliers from prefs: $e");
    }
  }


  Future<void> registerPatient(Patient p) async {
    final db = await DbHelper.instance.database;
    await db.insert('patients', p.toMap(), conflictAlgorithm: sql.ConflictAlgorithm.replace);

    _patientMaster.add(p);
    if (!_patients.contains(p.name)) _patients.add(p.name);
    notifyListeners();
  }

  Future<void> updatePatient(Patient p) async {
    final db = await DbHelper.instance.database;
    await db.update('patients', p.toMap(), where: 'id = ?', whereArgs: [p.id]);

    int idx = _patientMaster.indexWhere((it) => it.id == p.id);
    if (idx != -1) {
      String oldName = _patientMaster[idx].name;
      _patientMaster[idx] = p;
      int pIdx = _patients.indexOf(oldName);
      if (pIdx != -1) _patients[pIdx] = p.name;
    }
    notifyListeners();
  }

  Future<void> deletePatient(String id) async {
    final db = await DbHelper.instance.database;
    await db.delete('patients', where: 'id = ?', whereArgs: [id]);

    int idx = _patientMaster.indexWhere((it) => it.id == id);
    if (idx != -1) {
      String name = _patientMaster[idx].name;
      _patientMaster.removeAt(idx);
      _patients.remove(name);
    }
    notifyListeners();
  }

  Future<void> registerDoctor(Doctor d) async {
    final db = await DbHelper.instance.database;
    await db.insert('doctors', d.toMap(), conflictAlgorithm: sql.ConflictAlgorithm.replace);
    _doctorMaster.add(d);
    if (!_doctors.contains(d.name)) _doctors.add(d.name);
    notifyListeners();
  }

  Future<void> updateDoctor(Doctor d) async {
    final db = await DbHelper.instance.database;
    await db.update('doctors', d.toMap(), where: 'id = ?', whereArgs: [d.id]);
    int idx = _doctorMaster.indexWhere((it) => it.id == d.id);
    if (idx != -1) {
      String oldName = _doctorMaster[idx].name;
      _doctorMaster[idx] = d;
      int dIdx = _doctors.indexOf(oldName);
      if (dIdx != -1) _doctors[dIdx] = d.name;
    }
    notifyListeners();
  }

  Future<void> deleteDoctor(String id) async {
    final db = await DbHelper.instance.database;
    await db.delete('doctors', where: 'id = ?', whereArgs: [id]);
    int idx = _doctorMaster.indexWhere((it) => it.id == id);
    if (idx != -1) {
      String name = _doctorMaster[idx].name;
      _doctorMaster.removeAt(idx);
      _doctors.remove(name);
    }
    notifyListeners();
  }

  Future<void> _loadStaffFromDb(sql.Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS staff (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        role TEXT,
        code TEXT,
        is_active INTEGER DEFAULT 1
      )
    ''');

    List<Map<String, dynamic>> maps = await db.query('staff');
    if (maps.isEmpty) {
      final defaultStaff = [
        Staff(id: 'STF_1', name: 'Admin', role: 'Admin', code: 'STF01', phone: '', isActive: true),
        Staff(id: 'STF_2', name: 'Jiyad', role: 'Sales Agent', code: 'STF02', phone: '', isActive: true),
        Staff(id: 'STF_3', name: 'Suresh', role: 'Sales Agent', code: 'STF03', phone: '', isActive: true),
        Staff(id: 'STF_4', name: 'Ramesh', role: 'Sales Agent', code: 'STF04', phone: '', isActive: true),
        Staff(id: 'STF_5', name: 'Staff 1', role: 'Sales Agent', code: 'STF05', phone: '', isActive: true),
        Staff(id: 'STF_6', name: 'Staff 2', role: 'Sales Agent', code: 'STF06', phone: '', isActive: true),
      ];
      for (var s in defaultStaff) {
        await db.insert('staff', s.toMap(), conflictAlgorithm: sql.ConflictAlgorithm.ignore);
      }
      maps = await db.query('staff');
    }

    _staffMaster.clear();
    for (var m in maps) {
      _staffMaster.add(Staff.fromMap(m));
    }
  }

  Future<void> registerStaff(Staff s) async {
    final db = await DbHelper.instance.database;
    await db.insert('staff', s.toMap(), conflictAlgorithm: sql.ConflictAlgorithm.replace);
    int existingIdx = _staffMaster.indexWhere((it) => it.id == s.id);
    if (existingIdx != -1) {
      _staffMaster[existingIdx] = s;
    } else {
      _staffMaster.add(s);
    }
    notifyListeners();
  }

  Future<void> updateStaff(Staff s) async {
    final db = await DbHelper.instance.database;
    await db.update('staff', s.toMap(), where: 'id = ?', whereArgs: [s.id]);
    int idx = _staffMaster.indexWhere((it) => it.id == s.id);
    if (idx != -1) {
      _staffMaster[idx] = s;
    }
    notifyListeners();
  }

  Future<void> deleteStaff(String id) async {
    final db = await DbHelper.instance.database;
    await db.delete('staff', where: 'id = ?', whereArgs: [id]);
    _staffMaster.removeWhere((it) => it.id == id);
    notifyListeners();
  }

  Future<void> toggleStaffActive(String id, bool isActive) async {
    final db = await DbHelper.instance.database;
    await db.update('staff', {'is_active': isActive ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
    int idx = _staffMaster.indexWhere((it) => it.id == id);
    if (idx != -1) {
      _staffMaster[idx].isActive = isActive;
    }
    notifyListeners();
  }

  Future<void> addPatient(String name) async {
    if (!_patients.contains(name)) {
      _patients.add(name);
      final String id = "PAT_${DateTime.now().millisecondsSinceEpoch}_${name.hashCode}";
      _patientMaster.add(Patient(id: id, name: name));
      if (!kIsWeb) {
        final db = await DbHelper.instance.database;
        await db.insert('patients', {
          'id': id,
          'name': name,
          'mobile': '',
          'address': '',
          'email': '',
          'current_balance': 0.0,
          'is_active': 1,
        }, conflictAlgorithm: sql.ConflictAlgorithm.ignore);
      }
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> getFastBaseOrderBookAnalysis() async {
    try {
      final db = await DbHelper.instance.database;
      const String query = '''
        SELECT 
          p.id,
          p.name,
          p.rack_id as rack,
          IFNULL(p.category_id, 'General') as classification,
          IFNULL(p.generic_name, '') as content,
          IFNULL(p.mrp, 0.0) as mrp,
          IFNULL(p.purchase_rate, 0.0) as pRate,
          IFNULL(p.manufacturer_id, IFNULL(p.patent, '')) as brand,
          p.packing as packSize,
          p.reorder_level as minLevel,
          p.max_level as maxLevel,
          IFNULL(p.preferred_wholesale, '-') as preferred_wholesale,
          IFNULL(s.total_stock, 0.0) as currentBalance,
          0.0 as intervalSaleQty,
          '-' as lastSaleEntryNo,
          0.0 as lastSaleQty,
          0 as lastOrderType,
          '' as lastSaleDate,
          0.0 as maxSingleTxn4M,
          '' as firstPurchaseDate,
          '' as mappedName,
          IFNULL(p.preferred_wholesale, '-') as bestProfitWholesale,
          '-' as latestOffer,
          0.0 as rank
        FROM product_master p
        LEFT JOIN (
          SELECT product_id, SUM(current_stock) as total_stock
          FROM stock_batches
          GROUP BY product_id
        ) s ON p.id = s.product_id
        WHERE p.is_active = 1 OR s.total_stock > 0
        ORDER BY p.name ASC
      ''';

      final List<Map<String, dynamic>> rawProducts = await db.rawQuery(query);
      final rankingsMap = await getProductRankingsMap();

      return rawProducts.map((prod) {
        final item = Map<String, dynamic>.from(prod);
        final String pid = item['id']?.toString() ?? '';
        final String pname = item['name']?.toString().toUpperCase().trim() ?? '';
        final pr = rankingsMap[pid] ?? rankingsMap[pname];

        if (pr != null) {
          item['rank'] = pr.weightedScore;
          item['minLevel'] = pr.reOrderScore;
          item['maxLevel'] = pr.maxOrderLevel;
          item['warning'] = pr.warningScore;
        }
        return item;
      }).toList();
    } catch (e) {
      debugPrint("Error in getFastBaseOrderBookAnalysis: $e");
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getAdvancedOrderBookAnalysis({DateTime? fromDate, DateTime? toDate}) async {
    final db = await DbHelper.instance.database;
    final now = DateTime.now();
    final d4mDate = now.subtract(const Duration(days: 120));
    final d4mStart = d4mDate.toIso8601String();
    final d4mDay = DateFormat('yyyy-MM-dd').format(d4mDate);

    // 1. Parallel Light-Query Strategy (Same architecture as Product Ranking)
    const String baseProductsQuery = '''
      SELECT 
        p.id,
        p.name,
        p.rack_id as rack,
        IFNULL(p.category_id, 'General') as classification,
        IFNULL(p.generic_name, '') as content,
        IFNULL(p.mrp, 0.0) as mrp,
        IFNULL(p.purchase_rate, 0.0) as pRate,
        IFNULL(p.manufacturer_id, IFNULL(p.patent, '')) as brand,
        p.packing as packSize,
        p.reorder_level as minLevel,
        p.max_level as maxLevel,
        IFNULL(p.preferred_wholesale, '-') as preferred_wholesale,
        IFNULL(s.total_stock, 0.0) as currentBalance
      FROM product_master p
      LEFT JOIN (
        SELECT product_id, SUM(current_stock) as total_stock
        FROM stock_batches
        GROUP BY product_id
      ) s ON p.id = s.product_id
      WHERE p.is_active = 1 OR s.total_stock > 0
      ORDER BY p.name ASC
    ''';

    const String lastSalesQuery = '''
      WITH RankedLastSales AS (
        SELECT 
          si.product_id,
          si.qty as last_qty,
          sn.entry_no as last_entry,
          IFNULL(sn.order_type, 0) as last_order_type,
          sn.date as last_date,
          ROW_NUMBER() OVER (
            PARTITION BY si.product_id 
            ORDER BY (CASE WHEN sn.date LIKE '%/%' THEN substr(sn.date, 7, 4) || '-' || substr(sn.date, 4, 2) || '-' || substr(sn.date, 1, 2) ELSE substr(sn.date, 1, 10) END) DESC,
                     CAST(sn.entry_no AS INTEGER) DESC
          ) as rn
        FROM sales_items si
        JOIN sales_invoices sn ON si.invoice_no = sn.entry_no
        WHERE (sn.is_deleted = 0 OR sn.is_deleted IS NULL)
          AND si.product_id IS NOT NULL AND si.product_id != ''
      )
      SELECT product_id, last_qty, last_entry, last_order_type, last_date
      FROM RankedLastSales
      WHERE rn = 1
    ''';

    final String maxTxnQuery = '''
      WITH RankedLastSales AS (
        SELECT 
          si_l.product_id,
          sn_l.entry_no as last_entry,
          ROW_NUMBER() OVER (
            PARTITION BY si_l.product_id 
            ORDER BY (CASE WHEN sn_l.date LIKE '%/%' THEN substr(sn_l.date, 7, 4) || '-' || substr(sn_l.date, 4, 2) || '-' || substr(sn_l.date, 1, 2) ELSE substr(sn_l.date, 1, 10) END) DESC,
                     CAST(sn_l.entry_no AS INTEGER) DESC
          ) as rn
        FROM sales_items si_l
        JOIN sales_invoices sn_l ON si_l.invoice_no = sn_l.entry_no
        WHERE (sn_l.is_deleted = 0 OR sn_l.is_deleted IS NULL)
          AND si_l.product_id IS NOT NULL AND si_l.product_id != ''
      )
      SELECT 
        si.product_id, 
        MAX(CAST(si.qty AS REAL)) as max_qty
      FROM sales_items si
      JOIN sales_invoices sn ON si.invoice_no = sn.entry_no
      LEFT JOIN RankedLastSales rls ON si.product_id = rls.product_id AND rls.rn = 1
      WHERE (sn.is_deleted = 0 OR sn.is_deleted IS NULL)
        AND (
          sn.date >= '$d4mStart'
          OR (
            sn.date LIKE '%/%' 
            AND (substr(sn.date, 7, 4) || '-' || substr(sn.date, 4, 2) || '-' || substr(sn.date, 1, 2)) >= '$d4mDay'
          )
        )
        AND si.product_id IS NOT NULL AND si.product_id != ''
        AND (rls.last_entry IS NULL OR sn.entry_no != rls.last_entry)
      GROUP BY si.product_id
    ''';

    const String firstPurQuery = '''
      SELECT pi.product_id, MIN(pe.date) as first_pur_date
      FROM purchase_items pi
      JOIN purchase_entries pe ON pi.entry_no = pe.entry_no
      WHERE (pe.is_deleted = 0 OR pe.is_deleted IS NULL)
        AND pi.product_id IS NOT NULL AND pi.product_id != ''
      GROUP BY pi.product_id
    ''';

    const String mappingsQuery = '''
      SELECT 
        product_id, 
        GROUP_CONCAT(DISTINCT external_name) as mapped_name, 
        MAX(wholesaler_name) as mapped_wholesaler
      FROM ProductMappings
      WHERE TRIM(external_name) != '' OR TRIM(wholesaler_name) != ''
      GROUP BY product_id
    ''';

    String? intervalQuery;
    if (fromDate != null && toDate != null) {
      final fromStr = DateTime(fromDate.year, fromDate.month, fromDate.day, 0, 0, 0).toIso8601String();
      final toStr = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59).toIso8601String();
      final fromDay = DateFormat('yyyy-MM-dd').format(fromDate);
      final toDay = DateFormat('yyyy-MM-dd').format(toDate);

      intervalQuery = '''
        SELECT si.product_id, SUM(si.qty) as range_qty
        FROM sales_items si
        JOIN sales_invoices sn ON si.invoice_no = sn.entry_no
        WHERE (sn.is_deleted = 0 OR sn.is_deleted IS NULL)
          AND (
            (sn.date BETWEEN '$fromStr' AND '$toStr')
            OR (
              sn.date LIKE '%/%' 
              AND (substr(sn.date, 7, 4) || '-' || substr(sn.date, 4, 2) || '-' || substr(sn.date, 1, 2)) BETWEEN '$fromDay' AND '$toDay'
            )
          )
          AND si.product_id IS NOT NULL AND si.product_id != ''
        GROUP BY si.product_id
      ''';
    }

    // 2. Execute parallel high-speed queries simultaneously with safe catchError fallbacks
    final results = await Future.wait([
      db.rawQuery(baseProductsQuery).catchError((e) {
        debugPrint("Error in baseProductsQuery: $e");
        return <Map<String, dynamic>>[];
      }),
      db.rawQuery(lastSalesQuery).catchError((e) {
        debugPrint("Error in lastSalesQuery: $e");
        return <Map<String, dynamic>>[];
      }),
      db.rawQuery(maxTxnQuery).catchError((e) {
        debugPrint("Error in maxTxnQuery: $e");
        return <Map<String, dynamic>>[];
      }),
      db.rawQuery(firstPurQuery).catchError((e) {
        debugPrint("Error in firstPurQuery: $e");
        return <Map<String, dynamic>>[];
      }),
      db.rawQuery(mappingsQuery).catchError((e) {
        debugPrint("Error in mappingsQuery: $e");
        return <Map<String, dynamic>>[];
      }),
      intervalQuery != null
          ? db.rawQuery(intervalQuery).catchError((e) {
              debugPrint("Error in intervalQuery: $e");
              return <Map<String, dynamic>>[];
            })
          : Future.value(<Map<String, dynamic>>[]),
    ]);

    final List<Map<String, dynamic>> rawProducts = results[0];
    final Map<String, Map<String, dynamic>> lastSaleMap = {
      for (var r in results[1])
        if (r['product_id'] != null) r['product_id'].toString(): r
    };
    final Map<String, double> maxTxnMap = {
      for (var r in results[2])
        if (r['product_id'] != null) r['product_id'].toString(): (r['max_qty'] as num?)?.toDouble() ?? 0.0
    };
    final Map<String, String> firstPurMap = {
      for (var r in results[3])
        if (r['product_id'] != null) r['product_id'].toString(): r['first_pur_date']?.toString() ?? ''
    };
    final Map<String, Map<String, dynamic>> mappingsMap = {
      for (var r in results[4])
        if (r['product_id'] != null) r['product_id'].toString(): r
    };
    final Map<String, double> intervalMap = {
      for (var r in results[5])
        if (r['product_id'] != null) r['product_id'].toString(): (r['range_qty'] as num?)?.toDouble() ?? 0.0
    };

    final rankingsMap = await getProductRankingsMap();
    final List<Map<String, dynamic>> finalResults = [];

    for (var prod in rawProducts) {
      final String pid = prod['id']?.toString() ?? '';
      final String pname = prod['name']?.toString().toUpperCase().trim() ?? '';

      final lastSale = lastSaleMap[pid];
      final double maxSingle = maxTxnMap[pid] ?? 0.0;
      final String firstPur = firstPurMap[pid] ?? '';
      final mapping = mappingsMap[pid];
      final double intervalQty = intervalMap[pid] ?? 0.0;
      final pr = rankingsMap[pid] ?? rankingsMap[pname];

      final Map<String, dynamic> item = Map<String, dynamic>.from(prod);
      item['lastSaleEntryNo'] = lastSale?['last_entry']?.toString() ?? '-';
      item['lastSaleQty'] = (lastSale?['last_qty'] as num?)?.toDouble() ?? 0.0;
      item['lastOrderType'] = (lastSale?['last_order_type'] as num?)?.toInt() ?? 0;
      item['lastSaleDate'] = lastSale?['last_date']?.toString() ?? '';
      item['maxSingleTxn4M'] = maxSingle;
      item['firstPurchaseDate'] = firstPur;
      item['mappedName'] = mapping?['mapped_name']?.toString() ?? '';
      item['bestProfitWholesale'] = mapping?['mapped_wholesaler']?.toString() ?? prod['preferred_wholesale'] ?? '-';
      item['intervalSaleQty'] = intervalQty;
      item['latestOffer'] = '-';

      if (pr != null) {
        item['rank'] = pr.weightedScore;
        item['minLevel'] = pr.reOrderScore;
        item['maxLevel'] = pr.maxOrderLevel;
        item['warning'] = pr.warningScore;
      } else {
        item['rank'] = 0.0;
        item['minLevel'] = (prod['minLevel'] as num?)?.toDouble() ?? 0.0;
        item['maxLevel'] = (prod['maxLevel'] as num?)?.toDouble() ?? 0.0;
        item['warning'] = 0.0;
      }

      finalResults.add(item);
    }

    return finalResults;
  }

  Future<void> addDoctor(String name) async {
    if (!_doctors.contains(name)) {
      _doctors.add(name);
      final String id = "DOC_${DateTime.now().millisecondsSinceEpoch}_${name.hashCode}";
      _doctorMaster.add(Doctor(id: id, name: name));
      if (!kIsWeb) {
        final db = await DbHelper.instance.database;
        await db.insert('doctors', {
          'id': id,
          'name': name,
          'mobile': '',
          'specialization': '',
          'reg_no': '',
          'is_active': 1,
        }, conflictAlgorithm: sql.ConflictAlgorithm.ignore);
      }
      notifyListeners();
    }
  }

  Future<int> addPrescription(Prescription p) async {
    final db = await DbHelper.instance.database;
    int finalPresNo = p.prescriptionNo;
    String fy = p.financialYear.isEmpty ? _selectedFinancialYear : p.financialYear;

    await db.transaction((txn) async {
      // Generate new prescription number if it's 0 inside the transaction
      if (finalPresNo == 0) {
        final List<Map<String, dynamic>> result = await txn.rawQuery(
            'SELECT MAX(prescription_no) as max_no FROM prescriptions WHERE financial_year = ?', [fy]);
        int maxNo = (result.first['max_no'] as int?) ?? 0;
        finalPresNo = maxNo + 1;
      }

      await txn.insert('prescriptions', {
        'id': p.id,
        'prescription_no': finalPresNo,
        'patient_name': p.patientName,
        'doctor_name': p.doctorName,
        'disease_name': p.diseaseName,
        'mobile': p.mobile,
        'days': p.days,
        'date': p.date.toIso8601String(),
        'sale_entry_no': p.saleEntryNo,
        'is_active': p.isActive ? 1 : 0,
        'is_imported': p.isImported ? 1 : 0,
        'financial_year': fy,
      }, conflictAlgorithm: sql.ConflictAlgorithm.replace);

      await txn.delete('prescription_items',
          where: 'prescription_id = ?', whereArgs: [p.id]);
      for (var item in p.items) {
        await txn.insert('prescription_items', {
          'prescription_id': p.id,
          'name': item.name,
          'qty': item.qty,
        });
      }
    });

    final savedPres = Prescription(
      id: p.id,
      prescriptionNo: finalPresNo,
      patientName: p.patientName,
      doctorName: p.doctorName,
      diseaseName: p.diseaseName,
      mobile: p.mobile,
      days: p.days,
      date: p.date,
      saleEntryNo: p.saleEntryNo,
      isActive: p.isActive,
      isImported: p.isImported,
      items: p.items,
    );

    _prescriptions.removeWhere((existing) => existing.id == p.id);
    _prescriptions.insert(0, savedPres);
    notifyListeners();
    return finalPresNo;
  }

  Future<void> deletePrescription(String id) async {
    final db = await DbHelper.instance.database;
    await db.delete('prescriptions', where: 'id = ?', whereArgs: [id]);
    _prescriptions.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  Future<void> deleteMultiplePrescriptions(List<String> ids) async {
    final db = await DbHelper.instance.database;
    await db.transaction((txn) async {
      for (String id in ids) {
        await txn.delete('prescription_items', where: 'prescription_id = ?', whereArgs: [id]);
        await txn.delete('prescriptions', where: 'id = ?', whereArgs: [id]);
      }
    });
    _prescriptions.removeWhere((p) => ids.contains(p.id));
    notifyListeners();
  }

  Future<void> markPrescriptionImported(String id) async {
    final db = await DbHelper.instance.database;
    await db.update('prescriptions', {'is_imported': 1}, where: 'id = ?', whereArgs: [id]);
    final index = _prescriptions.indexWhere((p) => p.id == id);
    if (index != -1) {
      _prescriptions[index].isImported = true;
      notifyListeners();
    }
  }

  void addRack(String name, {bool isActive = true}) async {
    final cleanName = name.trim().toUpperCase();
    if (cleanName.isEmpty) return;
    if (!_racks.contains(cleanName)) {
      _racks.add(cleanName);
      _rackStatus[cleanName] = isActive;
      if (!kIsWeb) {
        final db = await DbHelper.instance.database;
        await db.insert('racks', {
          'id': cleanName,
          'name': cleanName,
          'is_active': isActive ? 1 : 0,
          'status_date': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: sql.ConflictAlgorithm.ignore);
      }
      notifyListeners();
    }
  }

  void updateRack(String oldName, String newName, {bool? isActive}) async {
    final cleanOld = oldName.trim().toUpperCase();
    final cleanNew = newName.trim().toUpperCase();
    if (cleanNew.isEmpty) return;

    int idx = _racks.indexOf(cleanOld);
    if (idx != -1) {
      if (cleanOld != cleanNew) _racks[idx] = cleanNew;
      if (isActive != null) _rackStatus[cleanNew] = isActive;

      if (!kIsWeb) {
        final db = await DbHelper.instance.database;
        await db.transaction((txn) async {
          Map<String, dynamic> update = {
            'id': cleanNew,
            'name': cleanNew,
            'status_date': DateTime.now().toIso8601String(),
          };
          if (isActive != null) update['is_active'] = isActive ? 1 : 0;

          await txn.update('racks', update, where: 'id = ?', whereArgs: [cleanOld]);
          if (cleanOld != cleanNew) {
            await txn.update('product_master', {'rack_id': cleanNew}, where: 'rack_id = ?', whereArgs: [cleanOld]);
          }
        });
      }
      notifyListeners();
    }
  }

  void toggleRackStatus(String name) async {
    final cleanName = name.trim().toUpperCase();
    if (_racks.contains(cleanName)) {
      bool newStatus = !isRackActive(cleanName);
      _rackStatus[cleanName] = newStatus;
      if (!kIsWeb) {
        final db = await DbHelper.instance.database;
        await db.update('racks', {
          'is_active': newStatus ? 1 : 0,
          'status_date': DateTime.now().toIso8601String(),
        }, where: 'id = ?', whereArgs: [cleanName]);
      }
      notifyListeners();
    }
  }

  void deleteRack(String name) async {
    final cleanName = name.trim().toUpperCase();
    if (_racks.remove(cleanName)) {
      if (!kIsWeb) {
        final db = await DbHelper.instance.database;
        await db.transaction((txn) async {
          // Get products currently in this rack to log detailed history
          final products = await txn.query('product_master', where: 'rack_id = ?', whereArgs: [cleanName]);

          await txn.delete('racks', where: 'id = ?', whereArgs: [cleanName]);
          await txn.update('product_master', {'rack_id': ''}, where: 'rack_id = ?', whereArgs: [cleanName]);

          final now = DateTime.now().toIso8601String();
          for (var p in products) {
            await txn.insert('rack_history', {
              'product_id': p['id'],
              'product_name': p['name'],
              'old_rack': cleanName,
              'new_rack': 'NONE (DELETED)',
              'change_date': now,
            });
          }

          if (products.isEmpty) {
            await txn.insert('rack_history', {
              'product_id': 'SYSTEM',
              'product_name': 'EMPTY RACK DELETED',
              'old_rack': cleanName,
              'new_rack': 'NONE',
              'change_date': now,
            });
          }
        });
      }
      notifyListeners();
    }
  }

  Future<void> exchangeRacks(String rackA, String rackB, {String? rackC}) async {
    final cleanA = rackA.trim().toUpperCase();
    final cleanB = rackB.trim().toUpperCase();
    final cleanC = rackC?.trim().toUpperCase();

    if (cleanA == cleanB) return;
    if (cleanC != null && (cleanA == cleanC || cleanB == cleanC)) return;

    if (!kIsWeb) {
      final db = await DbHelper.instance.database;
      await db.transaction((txn) async {
        final now = DateTime.now().toIso8601String();

        if (cleanC == null) {
          // TWO-WAY SWAP (A <-> B)
          final productsA = await txn.query('product_master', where: 'rack_id = ?', whereArgs: [cleanA]);
          final productsB = await txn.query('product_master', where: 'rack_id = ?', whereArgs: [cleanB]);

          const tempRack = "EXCHANGE_TEMP_999";
          await txn.update('product_master', {'rack_id': tempRack}, where: 'rack_id = ?', whereArgs: [cleanA]);
          await txn.update('product_master', {'rack_id': cleanA}, where: 'rack_id = ?', whereArgs: [cleanB]);
          await txn.update('product_master', {'rack_id': cleanB}, where: 'rack_id = ?', whereArgs: [tempRack]);

          for (var p in productsA) {
            await txn.insert('rack_history', {'product_id': p['id'], 'product_name': p['name'], 'old_rack': cleanA, 'new_rack': cleanB, 'change_date': now});
          }
          for (var p in productsB) {
            await txn.insert('rack_history', {'product_id': p['id'], 'product_name': p['name'], 'old_rack': cleanB, 'new_rack': cleanA, 'change_date': now});
          }
          await txn.insert('rack_history', {'product_id': 'SYSTEM', 'product_name': 'RACK SWAP', 'old_rack': cleanA, 'new_rack': cleanB, 'change_date': now});
        } else {
          // THREE-WAY ROTATION (A -> B, B -> C, C -> A)
          final productsA = await txn.query('product_master', where: 'rack_id = ?', whereArgs: [cleanA]);
          final productsB = await txn.query('product_master', where: 'rack_id = ?', whereArgs: [cleanB]);
          final productsC = await txn.query('product_master', where: 'rack_id = ?', whereArgs: [cleanC]);

          const tempRack = "EXCHANGE_TEMP_999";
          await txn.update('product_master', {'rack_id': tempRack}, where: 'rack_id = ?', whereArgs: [cleanA]);
          await txn.update('product_master', {'rack_id': cleanA}, where: 'rack_id = ?', whereArgs: [cleanC]);
          await txn.update('product_master', {'rack_id': cleanC}, where: 'rack_id = ?', whereArgs: [cleanB]);
          await txn.update('product_master', {'rack_id': cleanB}, where: 'rack_id = ?', whereArgs: [tempRack]);

          for (var p in productsA) {
            await txn.insert('rack_history', {'product_id': p['id'], 'product_name': p['name'], 'old_rack': cleanA, 'new_rack': cleanB, 'change_date': now});
          }
          for (var p in productsB) {
            await txn.insert('rack_history', {'product_id': p['id'], 'product_name': p['name'], 'old_rack': cleanB, 'new_rack': cleanC, 'change_date': now});
          }
          for (var p in productsC) {
            await txn.insert('rack_history', {'product_id': p['id'], 'product_name': p['name'], 'old_rack': cleanC, 'new_rack': cleanA, 'change_date': now});
          }
          await txn.insert('rack_history', {'product_id': 'SYSTEM', 'product_name': 'RACK ROTATION', 'old_rack': "$cleanA,$cleanB,$cleanC", 'new_rack': 'ROTATED', 'change_date': now});
        }
      });
      await loadFromDatabase();
    }
  }

  Future<void> deleteInactiveRacks(DateTime cutoffDate) async {
    if (!kIsWeb) {
      final db = await DbHelper.instance.database;
      await db.transaction((txn) async {
        final now = DateTime.now().toIso8601String();

        // Definition:
        // 1. Marked Inactive
        // 2. No stock in any associated product batches
        // 3. Status date is before or equal to cutoff date
        final List<Map<String, dynamic>> inactiveRacks = await txn.query(
            'racks',
            where: 'is_active = 0 AND status_date <= ?',
            whereArgs: [cutoffDate.toIso8601String()]
        );

        for (var r in inactiveRacks) {
          final rackName = r['id'] as String;

          // Check for total stock across all products in this rack
          final List<Map<String, dynamic>> stockResults = await txn.rawQuery('''
            SELECT SUM(b.current_stock) as total_stock
            FROM product_master p
            JOIN stock_batches b ON p.id = b.product_id
            WHERE p.rack_id = ?
          ''', [rackName]);

          int totalStock = (stockResults.first['total_stock'] as num?)?.toInt() ?? 0;

          if (totalStock == 0) {
            await txn.delete('racks', where: 'id = ?', whereArgs: [rackName]);
            await txn.update('product_master', {'rack_id': ''}, where: 'rack_id = ?', whereArgs: [rackName]);

            await txn.insert('rack_history', {
              'product_id': 'SYSTEM',
              'product_name': 'INACTIVE RACK DELETED',
              'old_rack': rackName,
              'new_rack': 'NONE',
              'change_date': now,
            });
          }
        }
      });
      await loadFromDatabase();
    }
  }

  Future<void> clearRackHistory(DateTime cutoffDate) async {
    if (!kIsWeb) {
      final db = await DbHelper.instance.database;
      await db.delete('rack_history',
          where: 'change_date < ?',
          whereArgs: [cutoffDate.toIso8601String()]);
      notifyListeners();
    }
  }

  Future<void> exportRacksToExcel(String filePath) async {
    var excel = Excel.createExcel();
    var sheet = excel['Racks'];
    excel.delete('Sheet1');
    sheet.appendRow([TextCellValue('Rack Name'), TextCellValue('Status')]);
    for (var rack in racks) {
      sheet.appendRow([TextCellValue(rack), TextCellValue(isRackActive(rack) ? 'Active' : 'Inactive')]);
    }
    var bytes = excel.save();
    if (bytes != null) {
      await File(filePath).writeAsBytes(bytes);
    }
  }

  Future<void> exportPurchaseReturnToExcel(String filePath, List<PurchaseReturnItem> items, {bool showSupplier = true, bool showInvNo = true, bool showEntryNo = false, String entryNoWithFY = ""}) async {
    var excel = Excel.createExcel();
    var sheet = excel['Purchase Return'];
    excel.delete('Sheet1');
    
    List<CellValue> header = [
      TextCellValue('Sl No'),
      TextCellValue('Product Name'),
      TextCellValue('Batch'),
      TextCellValue('Expiry'),
      TextCellValue('Qty'),
    ];
    if (showSupplier) header.add(TextCellValue('Supplier'));
    if (showInvNo) header.add(TextCellValue('Supplier Inv No'));
    if (showEntryNo) header.add(TextCellValue('Entry No'));
    header.addAll([
      TextCellValue('P.Rate'),
      TextCellValue('Total'),
      TextCellValue('Reason'),
    ]);
    sheet.appendRow(header);

    for (int i = 0; i < items.length; i++) {
      final it = items[i];
      List<CellValue> row = [
        IntCellValue(i + 1),
        TextCellValue(it.product.name),
        TextCellValue(it.product.batch),
        TextCellValue(it.product.expiry),
        IntCellValue(it.qty),
      ];
      if (showSupplier) row.add(TextCellValue(it.supplier));
      if (showInvNo) row.add(TextCellValue(it.supInvNo));
      if (showEntryNo) row.add(TextCellValue(entryNoWithFY));
      row.addAll([
        DoubleCellValue(it.pRate),
        DoubleCellValue(it.total),
        TextCellValue(it.reason),
      ]);
      sheet.appendRow(row);
    }
    var bytes = excel.save();
    if (bytes != null) {
      await File(filePath).writeAsBytes(bytes);
    }
  }

  Future<List<Map<String, dynamic>>> importFromExcel(String filePath) async {
    return await ExcelWorkerService.parseExcelFileInBackground(filePath);
  }

  Future<void> exportRackItemsToExcel(String filePath, {String? rackName}) async {
    var excel = Excel.createExcel();
    var sheet = excel['Rack Items'];
    excel.delete('Sheet1');
    sheet.appendRow([
      TextCellValue('Product Name'),
      TextCellValue('Category'),
      TextCellValue('Rack'),
      TextCellValue('Stock'),
      TextCellValue('MRP'),
    ]);

    final items = rackName != null
        ? _productMaster.where((p) => p.rack == rackName).toList()
        : _productMaster.where((p) => p.rack.isNotEmpty).toList();

    for (var p in items) {
      sheet.appendRow([
        TextCellValue(p.name),
        TextCellValue(p.category),
        TextCellValue(p.rack),
        IntCellValue(p.stock),
        DoubleCellValue(p.mrp),
      ]);
    }

    var bytes = excel.save();
    if (bytes != null) {
      await File(filePath).writeAsBytes(bytes);
    }
  }

  Future<void> exportGenericsToExcel(String filePath) async {
    var excel = Excel.createExcel();
    var sheet = excel['Generics'];
    excel.delete('Sheet1');
    sheet.appendRow([
      TextCellValue('Generic Name'),
      TextCellValue('Use'),
      TextCellValue('Status'),
    ]);
    for (var g in genericMaster) {
      sheet.appendRow([
        TextCellValue(g.name),
        TextCellValue(g.use),
        TextCellValue(g.isActive ? 'Active' : 'Inactive')
      ]);
    }
    var bytes = excel.save();
    if (bytes != null) {
      await File(filePath).writeAsBytes(bytes);
    }
  }

  Future<void> exportSalesToExcel(String filePath, {Function(double, String)? onProgress, String? financialYear}) async {
    var excel = Excel.createExcel();
    var sheet = excel['Sales'];
    excel.delete('Sheet1');
    
    sheet.appendRow([
      TextCellValue('Entry No'), 
      TextCellValue('Date'), 
      TextCellValue('Time'),
      TextCellValue('Patient'),
      TextCellValue('Mobile'),
      TextCellValue('Account'),
      TextCellValue('Agent'),
      TextCellValue('Product'), 
      TextCellValue('Packing'),
      TextCellValue('Batch'), 
      TextCellValue('Qty'), 
      TextCellValue('S.Rate'), 
      TextCellValue('MRP'), 
      TextCellValue('Disc%'),
      TextCellValue('Tax%'), 
      TextCellValue('Total'),
      TextCellValue('Profit')
    ]);

    final db = await DbHelper.instance.database;
    
    String? fy = (financialYear == null || financialYear == 'All Years' || financialYear.isEmpty) ? null : financialYear;
    String whereClause = fy != null 
        ? "financial_year = ? AND IFNULL(is_deleted, 0) = 0"
        : "(financial_year = ? OR financial_year IS NULL OR financial_year = '') AND IFNULL(is_deleted, 0) = 0";
    List<Object?> whereArgs = fy != null ? [fy] : [_selectedFinancialYear];

    final List<Map<String, dynamic>> allSaleMaps = await db.query(
      'sales_invoices',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'date DESC'
    );

    int total = allSaleMaps.length;
    int current = 0;

    Map<String, List<Map<String, dynamic>>> itemsMap = {};
    List<String> entryNos = allSaleMaps.map((s) => s['entry_no'].toString()).toList();
    
    for (int i = 0; i < entryNos.length; i += 500) {
      int end = (i + 500 < entryNos.length) ? i + 500 : entryNos.length;
      List<String> chunk = entryNos.sublist(i, end);
      if (chunk.isEmpty) continue;
      String placeholders = chunk.map((_) => '?').join(',');
      
      final List<Map<String, dynamic>> chunkItems = await db.rawQuery('''
        SELECT si.*, p.name as product_name 
        FROM sales_items si
        LEFT JOIN product_master p ON si.product_id = p.id
        WHERE si.invoice_no IN ($placeholders)
      ''', chunk);

      for (var item in chunkItems) {
        String invNo = item['invoice_no'].toString();
        itemsMap.putIfAbsent(invNo, () => []).add(item);
      }
    }

    for (var s in allSaleMaps) {
      current++;
      if (onProgress != null && (current % 20 == 0 || current == total)) {
        onProgress(current / total, "Processing Invoice $current of $total");
      }

      String entryNo = s['entry_no']?.toString() ?? "";
      DateTime date = DateTime.tryParse(s['date']?.toString() ?? "") ?? DateTime.now();
      String patient = s['patient'] ?? "General";
      String mobile = s['mobile'] ?? "";
      String customerAcc = s['customer_acc'] ?? "Cash";
      String agent = s['agent'] ?? "Admin";
      double grandTotal = (s['grand_total'] as num?)?.toDouble() ?? (s['total_amount'] as num?)?.toDouble() ?? 0.0;

      final List<Map<String, dynamic>> items = itemsMap[entryNo] ?? [];

      if (items.isEmpty) {
        sheet.appendRow([
          TextCellValue(entryNo),
          TextCellValue(DateFormat('dd/MM/yyyy').format(date)),
          TextCellValue(DateFormat('HH:mm').format(date)),
          TextCellValue(patient),
          TextCellValue(mobile),
          TextCellValue(customerAcc),
          TextCellValue(agent),
          TextCellValue(''), // Product
          TextCellValue(''), // Packing
          TextCellValue(''), // Batch
          const IntCellValue(0),   // Qty
          const DoubleCellValue(0.0), const DoubleCellValue(0.0), const DoubleCellValue(0.0), const DoubleCellValue(0.0), DoubleCellValue(grandTotal), const DoubleCellValue(0.0)
        ]);
      } else {
        for (var item in items) {
          double profit = (item['profit'] as num?)?.toDouble() ?? 0.0;
          sheet.appendRow([
            TextCellValue(entryNo),
            TextCellValue(DateFormat('dd/MM/yyyy').format(date)),
            TextCellValue(DateFormat('HH:mm').format(date)),
            TextCellValue(patient),
            TextCellValue(mobile),
            TextCellValue(customerAcc),
            TextCellValue(agent),
            TextCellValue(item['product_name'] ?? 'Unknown'),
            IntCellValue((item['packin'] as num?)?.toInt() ?? 1),
            TextCellValue(item['batch_number'] ?? ''),
            IntCellValue((item['qty'] as num?)?.toInt() ?? 0),
            DoubleCellValue((item['s_rate'] as num?)?.toDouble() ?? 0.0),
            DoubleCellValue((item['mrp'] as num?)?.toDouble() ?? 0.0),
            DoubleCellValue((item['disc_percent'] as num?)?.toDouble() ?? 0.0),
            DoubleCellValue((item['gst_percent'] as num?)?.toDouble() ?? 0.0),
            DoubleCellValue((item['total'] as num?)?.toDouble() ?? 0.0),
            DoubleCellValue(profit),
          ]);
        }
      }
      if (current % 100 == 0) await Future.delayed(Duration.zero);
    }

    if (onProgress != null) onProgress(0.99, "Saving Excel file...");
    var bytes = excel.save();
    if (bytes != null) {
      await File(filePath).writeAsBytes(bytes);
    }
  }

  Future<void> exportSinglePurchaseToExcel(String filePath, PurchaseEntry entry) async {
    var excel = Excel.createExcel();
    String sheetName = 'Purchase ${entry.entryNo.replaceAll('/', '_')}';
    if (sheetName.length > 31) sheetName = sheetName.substring(0, 31);
    var sheet = excel[sheetName];
    excel.delete('Sheet1');

    sheet.appendRow([TextCellValue('PURCHASE INVOICE ENTRY')]);
    sheet.appendRow([
      TextCellValue('Entry No:'), TextCellValue(entry.entryNo),
      TextCellValue('Date:'), TextCellValue(DateFormat('dd/MM/yyyy').format(entry.date)),
    ]);
    sheet.appendRow([
      TextCellValue('Supplier:'), TextCellValue(entry.supplierName),
      TextCellValue('Sup Inv No:'), TextCellValue(cleanInvoiceNo(entry.supInvNo)),
      TextCellValue('Sup Inv Date:'), TextCellValue(DateFormat('dd/MM/yyyy').format(entry.supInvDate)),
    ]);
    sheet.appendRow([]); // Blank row

    sheet.appendRow([
      TextCellValue('Sl No'),
      TextCellValue('Product Name'),
      TextCellValue('HSN Code'),
      TextCellValue('Batch'),
      TextCellValue('Expiry'),
      TextCellValue('Qty'),
      TextCellValue('Free Qty'),
      TextCellValue('Pack Size'),
      TextCellValue('P.Rate'),
      TextCellValue('MRP'),
      TextCellValue('Gross'),
      TextCellValue('Disc %'),
      TextCellValue('GST %'),
      TextCellValue('Total')
    ]);

    for (int i = 0; i < entry.items.length; i++) {
      final it = entry.items[i];
      sheet.appendRow([
        IntCellValue(i + 1),
        TextCellValue(it.productName),
        TextCellValue(it.hsnCode),
        TextCellValue(it.batch),
        TextCellValue(it.expiry),
        IntCellValue(it.qty),
        IntCellValue(it.fQty),
        IntCellValue(it.packin),
        DoubleCellValue(it.pRate),
        DoubleCellValue(it.mrp),
        DoubleCellValue(it.gross),
        DoubleCellValue(it.discPercent),
        DoubleCellValue(it.gstPercent),
        DoubleCellValue(it.total)
      ]);
    }

    sheet.appendRow([]);
    sheet.appendRow([TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue('Sub Total:'), DoubleCellValue(entry.subTotal)]);
    sheet.appendRow([TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue('Discount:'), DoubleCellValue(entry.discount)]);
    sheet.appendRow([TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue('Grand Total:'), DoubleCellValue(entry.grandTotal)]);

    var bytes = excel.save();
    if (bytes != null) {
      await File(filePath).writeAsBytes(bytes);
    }
  }

  Future<void> exportPurchaseToExcel(String filePath, {Function(double, String)? onProgress, String? financialYear}) async {
    var excel = Excel.createExcel();
    var sheet = excel['Purchases'];
    excel.delete('Sheet1');
    sheet.appendRow([
      TextCellValue('Entry No'), 
      TextCellValue('Date'), 
      TextCellValue('Time'),
      TextCellValue('Supplier'),
      TextCellValue('Invoice No'), 
      TextCellValue('Inv Date'), 
      TextCellValue('Done By'),
      TextCellValue('Product'),
      TextCellValue('Batch'),
      TextCellValue('Qty'),
      TextCellValue('Packing'),
      TextCellValue('P.Rate'),
      TextCellValue('MRP'),
      TextCellValue('Disc%'),
      TextCellValue('Tax%'),
      TextCellValue('Taxable Amount'),
      TextCellValue('Grand Total')
    ]);
    
    final db = await DbHelper.instance.database;
    
    String? fy = (financialYear == null || financialYear == 'All Years' || financialYear.isEmpty) ? null : financialYear;
    String whereClause = fy != null 
        ? "financial_year = ? AND IFNULL(is_deleted, 0) = 0"
        : "(financial_year = ? OR financial_year IS NULL OR financial_year = '') AND IFNULL(is_deleted, 0) = 0";
    List<Object?> whereArgs = fy != null ? [fy] : [_selectedFinancialYear];

    final List<Map<String, dynamic>> allPurMaps = await db.query(
      'purchase_entries',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'date DESC'
    );

    int total = allPurMaps.length;
    int current = 0;

    Map<String, List<Map<String, dynamic>>> itemsMap = {};
    List<String> entryNos = allPurMaps.map((p) => p['entry_no'].toString()).toList();
    
    for (int i = 0; i < entryNos.length; i += 500) {
      int end = (i + 500 < entryNos.length) ? i + 500 : entryNos.length;
      List<String> chunk = entryNos.sublist(i, end);
      if (chunk.isEmpty) continue;
      String placeholders = chunk.map((_) => '?').join(',');
      
      final List<Map<String, dynamic>> chunkItems = await db.rawQuery('''
        SELECT * FROM purchase_items 
        WHERE entry_no IN ($placeholders)
      ''', chunk);

      for (var item in chunkItems) {
        String entryNo = item['entry_no'].toString();
        itemsMap.putIfAbsent(entryNo, () => []).add(item);
      }
    }
    
    for (var p in allPurMaps) {
      current++;
      if (onProgress != null && (current % 20 == 0 || current == total)) {
        onProgress(current / total, "Processing Purchase $current of $total");
      }

      String entryNo = p['entry_no']?.toString() ?? "";
      DateTime date = DateTime.tryParse(p['date']?.toString() ?? "") ?? DateTime.now();
      String supplierName = p['supplier_name'] ?? "";
      String supInvNo = cleanInvoiceNo(p['sup_inv_no']);
      DateTime supInvDate = DateTime.tryParse(p['sup_inv_date']?.toString() ?? "") ?? date;
      String doneBy = p['done_by']?.toString() ?? "";
      double grandTotal = (p['grand_total'] as num?)?.toDouble() ?? 0.0;

      final List<Map<String, dynamic>> items = itemsMap[entryNo] ?? [];

      if (items.isEmpty) {
        sheet.appendRow([
          TextCellValue(entryNo),
          TextCellValue(DateFormat('dd/MM/yyyy').format(date)),
          TextCellValue(DateFormat('HH:mm').format(date)),
          TextCellValue(supplierName),
          TextCellValue(supInvNo),
          TextCellValue(DateFormat('dd/MM/yyyy').format(supInvDate)),
          TextCellValue(doneBy),
          TextCellValue(''), TextCellValue(''), const IntCellValue(0), const IntCellValue(1),
          const DoubleCellValue(0.0), const DoubleCellValue(0.0), const DoubleCellValue(0.0), const DoubleCellValue(0.0), const DoubleCellValue(0.0), DoubleCellValue(grandTotal)
        ]);
      } else {
        for (var item in items) {
          double netVal = (item['net'] as num?)?.toDouble() ?? 0.0;
          double itemTotal = (item['total'] as num?)?.toDouble() ?? 0.0;
          sheet.appendRow([
            TextCellValue(entryNo),
            TextCellValue(DateFormat('dd/MM/yyyy').format(date)),
            TextCellValue(DateFormat('HH:mm').format(date)),
            TextCellValue(supplierName),
            TextCellValue(supInvNo),
            TextCellValue(DateFormat('dd/MM/yyyy').format(supInvDate)),
            TextCellValue(doneBy),
            TextCellValue(item['product_name'] ?? 'Unknown'),
            TextCellValue(item['batch'] ?? ''),
            IntCellValue((item['qty'] as num?)?.toInt() ?? 0),
            IntCellValue((item['packin'] as num?)?.toInt() ?? 1),
            DoubleCellValue((item['p_rate'] as num?)?.toDouble() ?? 0.0),
            DoubleCellValue((item['mrp'] as num?)?.toDouble() ?? 0.0),
            DoubleCellValue((item['disc_percent'] as num?)?.toDouble() ?? 0.0),
            DoubleCellValue((item['gst_percent'] as num?)?.toDouble() ?? 0.0),
            DoubleCellValue(netVal),
            DoubleCellValue(itemTotal > 0 ? itemTotal : grandTotal),
          ]);
        }
      }
      if (current % 100 == 0) await Future.delayed(Duration.zero);
    }
    
    if (onProgress != null) onProgress(0.99, "Saving Excel file...");
    var bytes = excel.save();
    if (bytes != null) {
      await File(filePath).writeAsBytes(bytes);
    }
  }

  Future<void> exportSalesReturnsToExcel(String filePath, {Function(double, String)? onProgress, String? financialYear}) async {
    var excel = Excel.createExcel();
    var salesSheet = excel['Sales Returns'];
    excel.delete('Sheet1');
    salesSheet.appendRow([
      TextCellValue('Entry No'), TextCellValue('Date'), TextCellValue('Customer'),
      TextCellValue('Product'), TextCellValue('Pack'), TextCellValue('Total Amount'), 
      TextCellValue('Discount'), TextCellValue('dis%'), TextCellValue('gst%'), 
      TextCellValue('gst amt'), TextCellValue('disc %'), TextCellValue('Ref Invoice'), TextCellValue('Grand Total')
    ]);
    
    String? fy = (financialYear == null || financialYear == 'All Years' || financialYear.isEmpty) ? null : financialYear;
    final filteredReturns = fy != null ? _saleReturns.where((r) => r.financialYear == fy).toList() : _saleReturns;
    int total = filteredReturns.length;
    int current = 0;
    
    for (var r in filteredReturns) {
      if (r.items.isEmpty) {
        current++;
        salesSheet.appendRow([
          TextCellValue(r.entryNo),
          TextCellValue(DateFormat('dd/MM/yyyy').format(r.date)),
          TextCellValue(r.customerAcc),
          TextCellValue(''),
          TextCellValue(''),
          const DoubleCellValue(0.0),
          const DoubleCellValue(0.0),
          const DoubleCellValue(0.0),
          const DoubleCellValue(0.0),
          const DoubleCellValue(0.0),
          const DoubleCellValue(0.0),
          TextCellValue(r.originalInvoiceNo),
          DoubleCellValue(r.grandTotal)
        ]);
      } else {
        for (var item in r.items) {
          current++;
          salesSheet.appendRow([
            TextCellValue(r.entryNo),
            TextCellValue(DateFormat('dd/MM/yyyy').format(r.date)),
            TextCellValue(r.customerAcc),
            TextCellValue(item.product.name),
            TextCellValue(item.product.packSize.toString()),
            DoubleCellValue(item.total),
            DoubleCellValue(item.discAmt),
            DoubleCellValue(item.discPercent),
            DoubleCellValue(item.gstPercent),
            DoubleCellValue(item.gstAmt),
            DoubleCellValue(item.discPercent),
            TextCellValue(r.originalInvoiceNo),
            DoubleCellValue(r.grandTotal)
          ]);
        }
      }
      if (onProgress != null) onProgress(current / (total > 0 ? total : 1), "Processing Sales Return $current");
      if (current % 50 == 0) await Future.delayed(Duration.zero);
    }
    
    if (onProgress != null) onProgress(0.99, "Saving Excel file...");
    var bytes = excel.save();
    if (bytes != null) {
      await File(filePath).writeAsBytes(bytes);
    }
  }

  Future<void> exportSingleSaleReturnToExcel(SaleReturnInvoice r, String filePath) async {
    var excel = Excel.createExcel();
    var salesSheet = excel['Sales Return'];
    excel.delete('Sheet1');
    salesSheet.appendRow([
      TextCellValue('Return No'), TextCellValue(r.entryNo),
      TextCellValue('Date'), TextCellValue(DateFormat('dd/MM/yyyy').format(r.date)),
    ]);
    salesSheet.appendRow([
      TextCellValue('Customer'), TextCellValue(r.customerAcc),
      TextCellValue('Patient'), TextCellValue(r.patient),
    ]);
    salesSheet.appendRow([
      TextCellValue('Ref Invoice'), TextCellValue(r.originalInvoiceNo),
    ]);
    salesSheet.appendRow([]); // Empty row

    salesSheet.appendRow([
      TextCellValue('Sl No'), TextCellValue('Product'), TextCellValue('Batch'), 
      TextCellValue('Expiry'), TextCellValue('Qty'), TextCellValue('MRP'), 
      TextCellValue('S.Rate'), TextCellValue('Total')
    ]);

    for (int i = 0; i < r.items.length; i++) {
      var item = r.items[i];
      salesSheet.appendRow([
        IntCellValue(i + 1),
        TextCellValue(item.product.name),
        TextCellValue(item.product.batch),
        TextCellValue(item.product.expiry),
        IntCellValue(item.qty),
        DoubleCellValue(item.mrp),
        DoubleCellValue(item.sRate),
        DoubleCellValue(item.total)
      ]);
    }

    salesSheet.appendRow([]);
    salesSheet.appendRow([
      TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), 
      TextCellValue(''), TextCellValue(''), TextCellValue('Grand Total'), 
      DoubleCellValue(r.grandTotal)
    ]);

    var bytes = excel.save();
    if (bytes != null) {
      await File(filePath).writeAsBytes(bytes);
    }
  }

  Future<void> exportPurchaseReturnsToExcel(String filePath, {Function(double, String)? onProgress, String? financialYear}) async {
    var excel = Excel.createExcel();
    var purSheet = excel['Purchase Returns'];
    excel.delete('Sheet1');
    purSheet.appendRow([
      TextCellValue('Entry No'), TextCellValue('Date'), TextCellValue('Supplier'),
      TextCellValue('Product'), TextCellValue('Pack'), TextCellValue('Total Amount'), 
      TextCellValue('Discount'), TextCellValue('Ref Purchase'), TextCellValue('Grand Total')
    ]);
    
    String? fy = (financialYear == null || financialYear == 'All Years' || financialYear.isEmpty) ? null : financialYear;
    final filteredReturns = fy != null ? _purchaseReturns.where((r) => r.financialYear == fy).toList() : _purchaseReturns;
    int total = filteredReturns.length;
    int current = 0;
    
    for (var r in filteredReturns) {
      if (r.items.isEmpty) {
        current++;
        purSheet.appendRow([
          TextCellValue(r.entryNo),
          TextCellValue(DateFormat('dd/MM/yyyy').format(r.date)),
          TextCellValue(r.supplierName),
          TextCellValue(''),
          TextCellValue(''),
          const DoubleCellValue(0.0),
          const DoubleCellValue(0.0),
          TextCellValue(r.originalPurchaseNo),
          DoubleCellValue(r.grandTotal)
        ]);
      } else {
        for (var item in r.items) {
          current++;
          purSheet.appendRow([
            TextCellValue(r.entryNo),
            TextCellValue(DateFormat('dd/MM/yyyy').format(r.date)),
            TextCellValue(r.supplierName),
            TextCellValue(item.productName),
            TextCellValue(item.packin.toString()),
            DoubleCellValue(item.total),
            DoubleCellValue(item.discAmt),
            TextCellValue(r.originalPurchaseNo),
            DoubleCellValue(r.grandTotal)
          ]);
        }
      }
      if (onProgress != null) onProgress(current / (total > 0 ? total : 1), "Processing Purchase Return $current");
      if (current % 50 == 0) await Future.delayed(Duration.zero);
    }
    
    if (onProgress != null) onProgress(0.99, "Saving Excel file...");
    var bytes = excel.save();
    if (bytes != null) {
      await File(filePath).writeAsBytes(bytes);
    }
  }

  Future<void> exportReturnsToExcel(String filePath, {Function(double, String)? onProgress}) async {
    var excel = Excel.createExcel();
    var salesSheet = excel['Sales Returns'];
    excel.delete('Sheet1');
    salesSheet.appendRow([
      TextCellValue('Entry No'), TextCellValue('Date'), TextCellValue('Customer'),
      TextCellValue('Product'), TextCellValue('Pack'), TextCellValue('Total Amount'), 
      TextCellValue('Discount'), TextCellValue('Ref Invoice'), TextCellValue('Grand Total')
    ]);
    
    int total = _saleReturns.length + _purchaseReturns.length;
    int current = 0;
    
    for (var r in _saleReturns) {
      if (r.items.isEmpty) {
        current++;
        salesSheet.appendRow([
          TextCellValue(r.entryNo),
          TextCellValue(DateFormat('dd/MM/yyyy').format(r.date)),
          TextCellValue(r.customerAcc),
          TextCellValue(''),
          TextCellValue(''),
          const DoubleCellValue(0.0),
          const DoubleCellValue(0.0),
          TextCellValue(r.originalInvoiceNo),
          DoubleCellValue(r.grandTotal)
        ]);
      } else {
        for (var item in r.items) {
          current++;
          salesSheet.appendRow([
            TextCellValue(r.entryNo),
            TextCellValue(DateFormat('dd/MM/yyyy').format(r.date)),
            TextCellValue(r.customerAcc),
            TextCellValue(item.product.name),
            TextCellValue(item.product.packSize.toString()),
            DoubleCellValue(item.total),
            DoubleCellValue(item.discAmt),
            TextCellValue(r.originalInvoiceNo),
            DoubleCellValue(r.grandTotal)
          ]);
        }
      }
      if (onProgress != null) onProgress(current / (total > 0 ? total : 1), "Processing Sales Return $current");
      if (current % 50 == 0) await Future.delayed(Duration.zero);
    }

    var purSheet = excel['Purchase Returns'];
    purSheet.appendRow([
      TextCellValue('Entry No'), TextCellValue('Date'), TextCellValue('Supplier'),
      TextCellValue('Product'), TextCellValue('Pack'), TextCellValue('Total Amount'), 
      TextCellValue('Discount'), TextCellValue('Ref Purchase'), TextCellValue('Grand Total')
    ]);
    for (var r in _purchaseReturns) {
      if (r.items.isEmpty) {
        current++;
        purSheet.appendRow([
          TextCellValue(r.entryNo),
          TextCellValue(DateFormat('dd/MM/yyyy').format(r.date)),
          TextCellValue(r.supplierName),
          TextCellValue(''),
          TextCellValue(''),
          const DoubleCellValue(0.0),
          const DoubleCellValue(0.0),
          TextCellValue(r.originalPurchaseNo),
          DoubleCellValue(r.grandTotal)
        ]);
      } else {
        for (var item in r.items) {
          current++;
          purSheet.appendRow([
            TextCellValue(r.entryNo),
            TextCellValue(DateFormat('dd/MM/yyyy').format(r.date)),
            TextCellValue(r.supplierName),
            TextCellValue(item.productName),
            TextCellValue(item.packin.toString()),
            DoubleCellValue(item.total),
            DoubleCellValue(item.discAmt),
            TextCellValue(r.originalPurchaseNo),
            DoubleCellValue(r.grandTotal)
          ]);
        }
      }
      if (onProgress != null) onProgress(current / (total > 0 ? total : 1), "Processing Purchase Return $current");
      if (current % 50 == 0) await Future.delayed(Duration.zero);
    }

    if (onProgress != null) onProgress(0.99, "Saving Excel file...");
    var bytes = excel.save();
    if (bytes != null) {
      await File(filePath).writeAsBytes(bytes);
    }
  }

  Future<void> exportDamageToExcel(String filePath, {Function(double, String)? onProgress, String? financialYear}) async {
    var excel = Excel.createExcel();
    var sheet = excel['Damages & WriteOffs'];
    excel.delete('Sheet1');
    sheet.appendRow([
      TextCellValue('ID'), TextCellValue('Date'), TextCellValue('Product'),
      TextCellValue('Batch'), TextCellValue('Quantity'), TextCellValue('Reason'),
      TextCellValue('Loss Value')
    ]);
    
    String? fy = (financialYear == null || financialYear == 'All Years' || financialYear.isEmpty) ? null : financialYear;
    final filteredWriteOffs = fy != null ? _writeOffs.where((d) => d.financialYear == fy).toList() : _writeOffs;
    int total = filteredWriteOffs.length;
    int current = 0;
    
    for (var d in filteredWriteOffs) {
      current++;
      if (onProgress != null) onProgress(current / total, "Processing Damage Log $current");
      sheet.appendRow([
        TextCellValue(d.id),
        TextCellValue(DateFormat('dd/MM/yyyy').format(d.date)),
        TextCellValue(d.product.name),
        TextCellValue(d.product.batch),
        IntCellValue(d.quantity),
        TextCellValue(d.reason),
        DoubleCellValue(d.lossValue)
      ]);
      if (current % 50 == 0) await Future.delayed(Duration.zero);
    }
    
    if (onProgress != null) onProgress(0.99, "Saving Excel file...");
    var bytes = excel.save();
    if (bytes != null) {
      await File(filePath).writeAsBytes(bytes);
    }
  }

  Future<void> exportInventoryToExcel(String filePath, {Function(double, String)? onProgress, String? financialYear}) async {
    var excel = Excel.createExcel();
    var sheet = excel['Inventory'];
    excel.delete('Sheet1');
    sheet.appendRow([
      TextCellValue('Name'),
      TextCellValue('Packing'),
      TextCellValue('Stock'),
      TextCellValue('Batch'),
      TextCellValue('Expiry'),
      TextCellValue('MRP'),
      TextCellValue('L Cost'),
      TextCellValue('MRP Value'),
      TextCellValue('Supplier'),
      TextCellValue('Gst%'),
      TextCellValue('Category'),
      TextCellValue('Sub Category')
    ]);

    final db = await DbHelper.instance.database;

    String? fy = (financialYear == null || financialYear == 'All Years' || financialYear.isEmpty) ? null : financialYear;
    String whereClause = fy != null ? "WHERE b.financial_year = ?" : "";
    List<Object?> whereArgs = fy != null ? [fy] : [];

    final List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT 
        p.name,
        COALESCE(b.packing, p.packing, 1) as packing,
        COALESCE(b.current_stock, 0) as stock,
        COALESCE(b.batch_number, '') as batch,
        COALESCE(b.expiry_date, '') as expiry,
        COALESCE(b.mrp, p.mrp, 0.0) as mrp,
        COALESCE(b.landing_cost, b.purchase_rate, p.purchase_rate, 0.0) as l_cost,
        COALESCE(b.supplier_name, '') as supplier,
        COALESCE(b.gst_percent, p.gst_percent, 12.0) as gst_percent,
        COALESCE(p.category_id, '') as category,
        COALESCE(p.sub_category_id, '') as sub_category
      FROM stock_batches b
      JOIN product_master p ON b.product_id = p.id
      $whereClause
      ORDER BY p.name ASC
    ''', whereArgs);

    int total = results.length;
    int current = 0;

    for (var row in results) {
      current++;
      if (onProgress != null && (current % 50 == 0 || current == total)) {
        onProgress(current / (total == 0 ? 1 : total), "Processing Inventory $current of $total");
      }

      String name = row['name']?.toString() ?? "";
      int packing = (row['packing'] as num?)?.toInt() ?? 1;
      int stock = (row['stock'] as num?)?.toInt() ?? 0;
      String batch = row['batch']?.toString() ?? "";
      String expiry = row['expiry']?.toString() ?? "";
      double mrp = (row['mrp'] as num?)?.toDouble() ?? 0.0;
      double lCost = (row['l_cost'] as num?)?.toDouble() ?? 0.0;
      double mrpValue = stock * mrp;
      String supplier = row['supplier']?.toString() ?? "";
      double gst = (row['gst_percent'] as num?)?.toDouble() ?? 12.0;
      String category = row['category']?.toString() ?? "";
      String subCategory = row['sub_category']?.toString() ?? "";

      sheet.appendRow([
        TextCellValue(name),
        IntCellValue(packing),
        IntCellValue(stock),
        TextCellValue(batch),
        TextCellValue(expiry),
        DoubleCellValue(mrp),
        DoubleCellValue(lCost),
        DoubleCellValue(mrpValue),
        TextCellValue(supplier),
        DoubleCellValue(gst),
        TextCellValue(category),
        TextCellValue(subCategory)
      ]);
      if (current % 100 == 0) await Future.delayed(Duration.zero);
    }

    if (onProgress != null) onProgress(0.99, "Saving Excel file...");
    var bytes = excel.save();
    if (bytes != null) {
      await File(filePath).writeAsBytes(bytes);
    }
  }

  Future<void> exportProductMasterToExcel(String filePath, {Function(double, String)? onProgress}) async {
    var excel = Excel.createExcel();
    var sheet = excel['Product Master'];
    excel.delete('Sheet1');
    sheet.appendRow([
      TextCellValue('Name'),
      TextCellValue('Packing'),
      TextCellValue('RACK'),
      TextCellValue('hsncode'),
      TextCellValue('MRP'),
      TextCellValue('P.RATE'),
      TextCellValue('Patent'),
      TextCellValue('Generic Name'),
      TextCellValue('Gst'),
      TextCellValue('Category'),
      TextCellValue('Sub Category'),
      TextCellValue('Sdisc%'),
      TextCellValue('Schedule')
    ]);

    final db = await DbHelper.instance.database;
    final List<Map<String, dynamic>> results = await db.query('product_master', orderBy: 'name ASC');

    int total = results.length;
    int current = 0;

    for (var row in results) {
      current++;
      if (onProgress != null && (current % 50 == 0 || current == total)) {
        onProgress(current / (total == 0 ? 1 : total), "Processing Product $current of $total");
      }

      sheet.appendRow([
        TextCellValue(row['name']?.toString() ?? ""),
        IntCellValue((row['packing'] as num?)?.toInt() ?? 1),
        TextCellValue(row['rack_id']?.toString() ?? ""),
        TextCellValue(row['hsn_code']?.toString() ?? ""),
        DoubleCellValue((row['mrp'] as num?)?.toDouble() ?? 0.0),
        DoubleCellValue((row['purchase_rate'] as num?)?.toDouble() ?? 0.0),
        TextCellValue(row['patent']?.toString() ?? ""),
        TextCellValue(row['generic_name']?.toString() ?? ""),
        DoubleCellValue((row['gst_percent'] as num?)?.toDouble() ?? 12.0),
        TextCellValue(row['category_id']?.toString() ?? ""),
        TextCellValue(row['sub_category_id']?.toString() ?? ""),
        DoubleCellValue((row['s_disc_percent'] as num?)?.toDouble() ?? 0.0),
        TextCellValue(row['schedule']?.toString() ?? "H")
      ]);
      if (current % 100 == 0) await Future.delayed(Duration.zero);
    }

    if (onProgress != null) onProgress(0.99, "Saving Excel file...");
    var bytes = excel.save();
    if (bytes != null) {
      await File(filePath).writeAsBytes(bytes);
    }
  }

  Future<Map<String, dynamic>> deleteSalesRecords(String? fy) async {
    try {
      final db = await DbHelper.instance.database;
      await db.transaction((txn) async {
        if (fy == null || fy == 'All Years' || fy.isEmpty) {
          await txn.rawDelete('DELETE FROM sales_items');
          await txn.rawDelete('DELETE FROM sales_invoices');
          await txn.rawDelete("DELETE FROM voucher_sequences WHERE voucher_type = 'sales_invoices'");
        } else {
          await txn.rawDelete(
            'DELETE FROM sales_items WHERE invoice_no IN (SELECT entry_no FROM sales_invoices WHERE financial_year = ?)',
            [fy],
          );
          await txn.rawDelete('DELETE FROM sales_invoices WHERE financial_year = ?', [fy]);
          await txn.rawDelete("DELETE FROM voucher_sequences WHERE voucher_type = 'sales_invoices' AND financial_year = ?", [fy]);
        }
      });
      await loadFromDatabase();
      notifyListeners();
      return {'success': true, 'message': 'Sales records deleted successfully.'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete sales records: $e'};
    }
  }

  Future<Map<String, dynamic>> deletePurchaseRecords(String? fy) async {
    try {
      final db = await DbHelper.instance.database;
      await db.transaction((txn) async {
        if (fy == null || fy == 'All Years' || fy.isEmpty) {
          await txn.rawDelete('DELETE FROM purchase_items');
          await txn.rawDelete('DELETE FROM purchase_entries');
          await txn.rawDelete("DELETE FROM voucher_sequences WHERE voucher_type = 'purchase_entries'");
        } else {
          await txn.rawDelete(
            'DELETE FROM purchase_items WHERE entry_no IN (SELECT entry_no FROM purchase_entries WHERE financial_year = ?)',
            [fy],
          );
          await txn.rawDelete('DELETE FROM purchase_entries WHERE financial_year = ?', [fy]);
          await txn.rawDelete("DELETE FROM voucher_sequences WHERE voucher_type = 'purchase_entries' AND financial_year = ?", [fy]);
        }
      });
      await loadFromDatabase();
      notifyListeners();
      return {'success': true, 'message': 'Purchase records deleted successfully.'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete purchase records: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteSalesReturnsRecords(String? fy) async {
    try {
      final db = await DbHelper.instance.database;
      await db.transaction((txn) async {
        if (fy == null || fy == 'All Years' || fy.isEmpty) {
          await txn.rawDelete('DELETE FROM sales_return_items');
          await txn.rawDelete('DELETE FROM sales_return_invoices');
          await txn.rawDelete("DELETE FROM voucher_sequences WHERE voucher_type = 'sales_return_invoices'");
        } else {
          await txn.rawDelete(
            'DELETE FROM sales_return_items WHERE return_no IN (SELECT entry_no FROM sales_return_invoices WHERE financial_year = ?)',
            [fy],
          );
          await txn.rawDelete('DELETE FROM sales_return_invoices WHERE financial_year = ?', [fy]);
          await txn.rawDelete("DELETE FROM voucher_sequences WHERE voucher_type = 'sales_return_invoices' AND financial_year = ?", [fy]);
        }
      });
      await loadFromDatabase();
      notifyListeners();
      return {'success': true, 'message': 'Sales return records deleted successfully.'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete sales return records: $e'};
    }
  }

  Future<Map<String, dynamic>> deletePurchaseReturnsRecords(String? fy) async {
    try {
      final db = await DbHelper.instance.database;
      await db.transaction((txn) async {
        if (fy == null || fy == 'All Years' || fy.isEmpty) {
          await txn.rawDelete('DELETE FROM purchase_return_items');
          await txn.rawDelete('DELETE FROM purchase_return_entries');
          await txn.rawDelete("DELETE FROM voucher_sequences WHERE voucher_type = 'purchase_return_entries'");
        } else {
          await txn.rawDelete(
            'DELETE FROM purchase_return_items WHERE return_no IN (SELECT entry_no FROM purchase_return_entries WHERE financial_year = ?)',
            [fy],
          );
          await txn.rawDelete('DELETE FROM purchase_return_entries WHERE financial_year = ?', [fy]);
          await txn.rawDelete("DELETE FROM voucher_sequences WHERE voucher_type = 'purchase_return_entries' AND financial_year = ?", [fy]);
        }
      });
      await loadFromDatabase();
      notifyListeners();
      return {'success': true, 'message': 'Purchase return records deleted successfully.'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete purchase return records: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteDamageRecords(String? fy) async {
    try {
      final db = await DbHelper.instance.database;
      await db.transaction((txn) async {
        if (fy == null || fy == 'All Years' || fy.isEmpty) {
          await txn.rawDelete('DELETE FROM stock_write_offs');
          await txn.rawDelete("DELETE FROM voucher_sequences WHERE voucher_type = 'stock_write_offs'");
        } else {
          await txn.rawDelete('DELETE FROM stock_write_offs WHERE financial_year = ?', [fy]);
          await txn.rawDelete("DELETE FROM voucher_sequences WHERE voucher_type = 'stock_write_offs' AND financial_year = ?", [fy]);
        }
      });
      await loadFromDatabase();
      notifyListeners();
      return {'success': true, 'message': 'Damage records deleted successfully.'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete damage records: $e'};
    }
  }

  Future<Map<String, dynamic>> deleteInventoryRecords(String? fy) async {
    try {
      final db = await DbHelper.instance.database;
      await db.transaction((txn) async {
        if (fy == null || fy == 'All Years' || fy.isEmpty) {
          await txn.rawDelete('DELETE FROM stock_batches');
        } else {
          await txn.rawDelete('DELETE FROM stock_batches WHERE financial_year = ?', [fy]);
        }
      });
      await loadFromDatabase();
      notifyListeners();
      return {'success': true, 'message': 'Inventory records deleted successfully.'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete inventory records: $e'};
    }
  }

  Future<double> _calculateUnitsSoldForBatch(String productId, String batch, [sql.DatabaseExecutor? executor]) async {
    final dbExecutor = executor ?? (kIsWeb ? null : await DbHelper.instance.database);
    if (dbExecutor == null) return 0.0;

    final result = await dbExecutor.rawQuery('''
      SELECT 
        (SELECT COALESCE(SUM(COALESCE(si.qty, si.quantity, 0)), 0)
         FROM sales_items si
         LEFT JOIN sales_invoices s ON si.invoice_no = s.entry_no
         WHERE (si.product_id = ? OR (si.product_id IS NULL AND LOWER(TRIM(si.product_name)) = (SELECT LOWER(TRIM(name)) FROM product_master WHERE id = ?)))
           AND LOWER(TRIM(COALESCE(si.batch_number, ''))) = LOWER(TRIM(?))
           AND (s.is_deleted = 0 OR s.is_deleted IS NULL))
        -
        (SELECT COALESCE(SUM(COALESCE(sri.quantity, sri.qty, 0)), 0)
         FROM sales_return_items sri
         LEFT JOIN sales_return_invoices sr ON sri.return_no = sr.entry_no
         WHERE (sri.product_id = ? OR (sri.product_id IS NULL AND LOWER(TRIM(sri.product_name)) = (SELECT LOWER(TRIM(name)) FROM product_master WHERE id = ?)))
           AND LOWER(TRIM(COALESCE(sri.batch_number, ''))) = LOWER(TRIM(?))
           AND (sr.is_deleted = 0 OR sr.is_deleted IS NULL))
        AS net_sold
    ''', [productId, productId, batch, productId, productId, batch]);

    if (result.isNotEmpty) {
      double sold = (result.first['net_sold'] as num?)?.toDouble() ?? 0.0;
      return sold < 0 ? 0.0 : sold;
    }
    return 0.0;
  }

  Future<Map<String, dynamic>> deleteStockBatch(String productId, String batchNumber) async {
    try {
      final db = await DbHelper.instance.database;
      double totalSold = await _calculateUnitsSoldForBatch(productId, batchNumber, db);
      if (totalSold > 0) {
        return {
          'success': false,
          'message': 'Cannot delete stock batch! ($totalSold units already billed out for batch $batchNumber)',
        };
      }
      await db.delete(
        'stock_batches',
        where: 'product_id = ? AND batch_number = ?',
        whereArgs: [productId, batchNumber],
      );
      _products.removeWhere((p) => p.id == productId && p.batch.toUpperCase() == batchNumber.toUpperCase());
      await loadFromDatabase();
      notifyListeners();
      return {'success': true, 'message': 'Stock batch deleted successfully.'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete stock batch: $e'};
    }
  }

  /// Safely cleans up zero-stock batches that are older than 60 days from active index
  Future<Map<String, dynamic>> archiveZeroStockBatches() async {
    try {
      final db = await DbHelper.instance.database;
      final cutoffDate = DateTime.now().subtract(const Duration(days: 60)).toIso8601String().split('T')[0];
      
      int count = await db.delete(
        'stock_batches',
        where: 'current_stock <= 0 AND (expiry_date < ? OR expiry_date IS NULL OR expiry_date = "")',
        whereArgs: [cutoffDate],
      );

      _products.removeWhere((p) => p.stock <= 0 && (p.expiry.compareTo(cutoffDate) < 0 || p.expiry.isEmpty));
      invalidateSearchProductsCache();
      notifyListeners();

      return {
        'success': true,
        'message': 'Archived $count zero-stock batches successfully.',
        'count': count,
      };
    } catch (e) {
      debugPrint("Error archiving zero stock batches: $e");
      return {'success': false, 'message': 'Failed to archive zero-stock batches: $e', 'count': 0};
    }
  }

  Future<Map<String, dynamic>> deleteProductMasterRecords() async {
    try {
      final db = await DbHelper.instance.database;
      await db.transaction((txn) async {
        await txn.execute('PRAGMA foreign_keys = OFF;');
        await txn.rawDelete('DELETE FROM stock_batches');
        await txn.rawDelete('DELETE FROM product_master');
        await txn.execute('PRAGMA foreign_keys = ON;');
      });
      await loadFromDatabase();
      return {'success': true, 'message': 'Product master records deleted successfully.'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to delete product master records: $e'};
    }
  }

  Future<Map<String, dynamic>> validateAndImportFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return {'success': false, 'message': 'File not found.'};
    }

    String extension = filePath.split('.').last.toLowerCase();

    // 1. Check for unsupported or incompatible formats
    if (extension != 'xlsx' && extension != 'xls' && extension != 'csv') {
      return {
        'success': false, 
        'message': 'Unsupported file format (.$extension). Please upload a valid .xlsx, .xls, or .csv file.'
      };
    }

    try {
      // 2. Extra safety check for legacy Excel 97-2003 binary format if needed
      if (extension == 'xls') {
        final raf = await file.open();
        final startBytes = await raf.read(8);
        await raf.close();

        // Check for OLE2 compound file signature or corrupted header
        bool isBiff8 = startBytes.length >= 8 && startBytes[0] == 0xD0 && startBytes[1] == 0xCF && startBytes[2] == 0x11 && startBytes[3] == 0xE0;
        if (isBiff8) {
          return {
            'success': false,
            'message': 'Legacy Excel 97-2003 (.xls) format detected. Please open the file in Excel/Calc and "Save As" an .xlsx workbook before importing.'
          };
        }
      }

      // Proceed with normal import logic...
      return {'success': true, 'message': 'Format is valid.'};
    } catch (e) {
      return {
        'success': false, 
        'message': 'Format check failed: The file structure is corrupted or unreadable.'
      };
    }
  }

  Future<Map<String, dynamic>> importGenericsFromExcel(String filePath) async {
    final validation = await validateAndImportFile(filePath);
    if (!validation['success']) return validation;

    try {
      final rawRows = await ExcelWorkerService.parseExcelRawRowsInBackground(filePath);
      if (rawRows.length <= 1) {
        return {'success': false, 'message': 'No data found in file.'};
      }

      final db = await DbHelper.instance.database;
      int imported = 0;
      int updated = 0;

      final header = rawRows.first.map((e) => e.toLowerCase().trim()).toList();
      int idxName = _findIdx(header, ['generic name', 'name', 'generic']);
      int idxUse = _findIdx(header, ['use', 'medical use', 'usage']);
      int idxStatus = _findIdx(header, ['status', 'active']);

      const int chunkSize = 500;
      final dataRows = rawRows.sublist(1);

      for (int i = 0; i < dataRows.length; i += chunkSize) {
        final chunk = dataRows.skip(i).take(chunkSize).toList();

        await db.transaction((txn) async {
          for (var row in chunk) {
            String name = (idxName >= 0 && idxName < row.length ? row[idxName] : "").trim();
            if (name.isEmpty) continue;

            String use = (idxUse >= 0 && idxUse < row.length ? row[idxUse] : "").trim();
            String status = (idxStatus >= 0 && idxStatus < row.length ? row[idxStatus] : "").toLowerCase().trim();
            int isActive = (status == 'inactive' || status == '0') ? 0 : 1;

            final existing = await txn.query('generics', where: 'name = ?', whereArgs: [name]);
            if (existing.isNotEmpty) {
              await txn.update('generics', {
                'use': use.isNotEmpty ? use : (existing.first['use'] ?? ""),
                'is_active': isActive,
              }, where: 'name = ?', whereArgs: [name]);
              updated++;
            } else {
              await txn.insert('generics', {
                'id': "GEN_${DateTime.now().millisecondsSinceEpoch}_$name",
                'name': name,
                'use': use,
                'is_active': isActive,
              });
              imported++;
            }
          }
        });
        await Future.delayed(const Duration(milliseconds: 10));
      }

      await loadFromDatabase();
      return {'success': true, 'imported': imported, 'updated': updated};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> importRacksFromExcel(String filePath) async {
    final validation = await validateAndImportFile(filePath);
    if (!validation['success']) return validation;

    try {
      final rawRows = await ExcelWorkerService.parseExcelRawRowsInBackground(filePath);
      if (rawRows.length <= 1) {
        return {'success': false, 'message': 'No data found in file.'};
      }
      int imported = 0;
      final dataRows = rawRows.sublist(1);
      for (var row in dataRows) {
        if (row.isNotEmpty) {
          final name = row[0].trim().toUpperCase();
          if (name.isNotEmpty) {
            addRack(name);
            imported++;
          }
        }
      }
      return {'success': true, 'count': imported};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }



  void addManufacturer(String name) async {
    if (!_manufacturers.contains(name)) {
      _manufacturers.add(name);
      if (!kIsWeb) {
        final db = await DbHelper.instance.database;
        await db.insert('manufacturers', {'id': name, 'name': name}, conflictAlgorithm: sql.ConflictAlgorithm.ignore);
      }
      notifyListeners();
    }
  }

  void updateManufacturer(String oldName, String newName) async {
    int idx = _manufacturers.indexOf(oldName);
    if (idx != -1 && !_manufacturers.contains(newName)) {
      _manufacturers[idx] = newName;
      if (!kIsWeb) {
        final db = await DbHelper.instance.database;
        await db.update('manufacturers', {'id': newName, 'name': newName}, where: 'id = ?', whereArgs: [oldName]);
      }
      notifyListeners();
    }
  }

  void deleteManufacturer(String name) async {
    if (_manufacturers.remove(name)) {
      if (!kIsWeb) {
        final db = await DbHelper.instance.database;
        await db.delete('manufacturers', where: 'id = ?', whereArgs: [name]);
      }
      notifyListeners();
    }
  }

  Future<int> autoExtractAndRegisterGenerics({bool clearExisting = false}) async {
    if (kIsWeb) return 0;
    try {
      final db = await DbHelper.instance.database;

      if (clearExisting) {
        _generics.clear();
        await db.delete('generics');
        // Clean product_master where generic_name was mistakenly set to brand product name
        await db.rawUpdate("UPDATE product_master SET generic_name = '' WHERE UPPER(TRIM(generic_name)) = UPPER(TRIM(name))");
      }

      final List<Map<String, dynamic>> rows = await db.rawQuery(
        "SELECT DISTINCT TRIM(generic_name) as g_name, TRIM(name) as p_name FROM product_master WHERE generic_name IS NOT NULL AND TRIM(generic_name) != ''"
      );

      int addedCount = 0;
      int i = 0;
      for (var r in rows) {
        String gName = r['g_name'].toString().trim().toUpperCase();
        String pName = r['p_name'].toString().trim().toUpperCase();

        // Skip if generic_name is empty OR if generic_name matches brand product name
        if (gName.isEmpty || gName == pName) continue;

        if (!_generics.any((g) => g.name.toUpperCase() == gName)) {
          final id = "GEN_${DateTime.now().microsecondsSinceEpoch}_${i}_${gName.hashCode.abs()}";
          final gen = Generic(
            id: id,
            name: gName,
            use: "",
            isActive: true,
          );
          _generics.add(gen);
          await db.insert('generics', {
            'id': id,
            'name': gName,
            'use': "",
            'is_active': 1,
          }, conflictAlgorithm: sql.ConflictAlgorithm.ignore);
          addedCount++;
          i++;
        }
      }
      if (addedCount > 0 || clearExisting) {
        notifyListeners();
      }
      return addedCount;
    } catch (e) {
      debugPrint("Error auto extracting generics: $e");
      return 0;
    }
  }

  Future<void> clearAllGenerics() async {
    _generics.clear();
    if (!kIsWeb) {
      final db = await DbHelper.instance.database;
      await db.delete('generics');
      await db.rawUpdate("UPDATE product_master SET generic_name = '' WHERE UPPER(TRIM(generic_name)) = UPPER(TRIM(name))");
    }
    notifyListeners();
  }

  String resolveGenericName(String productName, {String productId = ""}) {
    final cleanName = productName.trim();
    if (cleanName.isEmpty) return "";

    // 1. Check if productMaster has a generic_name for this product
    for (var p in _productMaster) {
      if ((productId.isNotEmpty && p.id == productId) ||
          p.name.trim().toLowerCase() == cleanName.toLowerCase()) {
        if (p.genericName.trim().isNotEmpty) {
          return p.genericName.trim();
        }
      }
    }

    // 2. Check ProductMappings
    final pNameLower = cleanName.toLowerCase();
    for (var m in _productMappings) {
      if (m.productId == productId ||
          m.internalName.trim().toLowerCase() == pNameLower ||
          m.externalName.trim().toLowerCase() == pNameLower) {
        if (m.internalName.trim().isNotEmpty) {
          for (var p in _productMaster) {
            if (p.name.trim().toLowerCase() == m.internalName.trim().toLowerCase() && p.genericName.trim().isNotEmpty) {
              return p.genericName.trim();
            }
          }
        }
      }
    }

    // 3. Check generics master list (_generics)
    final pNameUpper = cleanName.toUpperCase();
    for (var g in _generics) {
      final gName = g.name.trim().toUpperCase();
      if (gName.isNotEmpty && gName.length >= 3) {
        if (pNameUpper.contains(gName) || gName.contains(pNameUpper)) {
          return g.name.trim();
        }
      }
    }

    return "";
  }

  Future<int> syncGenericNamesFromMappingsAndGenerics() async {
    if (kIsWeb) return 0;
    try {
      final db = await DbHelper.instance.database;

      // 1. Sync from ProductMappings
      int updatedFromMappings = await db.rawUpdate('''
        UPDATE product_master 
        SET generic_name = (
          SELECT pm_ref.generic_name FROM ProductMappings pm2 
          JOIN product_master pm_ref ON pm2.product_id = pm_ref.id
          WHERE (LOWER(TRIM(pm2.external_name)) = LOWER(TRIM(product_master.name)) 
              OR LOWER(TRIM(pm2.internal_name)) = LOWER(TRIM(product_master.name)))
            AND pm_ref.generic_name IS NOT NULL AND TRIM(pm_ref.generic_name) != '' 
          LIMIT 1
        )
        WHERE TRIM(IFNULL(generic_name, '')) = ''
          AND EXISTS (
            SELECT 1 FROM ProductMappings pm2 
            JOIN product_master pm_ref ON pm2.product_id = pm_ref.id
            WHERE (LOWER(TRIM(pm2.external_name)) = LOWER(TRIM(product_master.name)) 
                OR LOWER(TRIM(pm2.internal_name)) = LOWER(TRIM(product_master.name)))
              AND pm_ref.generic_name IS NOT NULL AND TRIM(pm_ref.generic_name) != ''
          )
      ''');

      // 2. Sync from generics table where generic name appears in product name
      final List<Map<String, dynamic>> genRows = await db.query('generics', where: "TRIM(IFNULL(name, '')) != ''");
      int updatedFromGenerics = 0;

      for (var g in genRows) {
        String gName = g['name']?.toString().trim() ?? '';
        if (gName.length < 3) continue;

        int count = await db.rawUpdate('''
          UPDATE product_master 
          SET generic_name = ? 
          WHERE TRIM(IFNULL(generic_name, '')) = '' 
            AND UPPER(name) LIKE ?
        ''', [gName, '%${gName.toUpperCase()}%']);
        updatedFromGenerics += count;
      }

      if (updatedFromMappings > 0 || updatedFromGenerics > 0) {
        for (var p in _productMaster) {
          if (p.genericName.trim().isEmpty) {
            String resolved = resolveGenericName(p.name, productId: p.id);
            if (resolved.isNotEmpty) {
              p.genericName = resolved;
            }
          }
        }
        for (var p in _products) {
          if (p.genericName.trim().isEmpty) {
            String resolved = resolveGenericName(p.name, productId: p.id);
            if (resolved.isNotEmpty) {
              p.genericName = resolved;
            }
          }
        }
        notifyListeners();
      }
      return updatedFromMappings + updatedFromGenerics;
    } catch (e) {
      debugPrint("Error syncing generic names: $e");
      return 0;
    }
  }

  void addGeneric(String name, {String use = "", bool isActive = true}) async {
    if (!_generics.any((g) => g.name.toLowerCase() == name.toLowerCase())) {
      final gen = Generic(
        id: "GEN_${DateTime.now().millisecondsSinceEpoch}_$name",
        name: name,
        use: use,
        isActive: isActive,
      );
      _generics.add(gen);
      if (!kIsWeb) {
        final db = await DbHelper.instance.database;
        await db.insert('generics', gen.toMap(), conflictAlgorithm: sql.ConflictAlgorithm.ignore);
        await syncGenericNamesFromMappingsAndGenerics();
      }
      notifyListeners();
    }
  }

  void updateGeneric(String oldName, String newName, {String? use, bool? isActive}) async {
    int idx = _generics.indexWhere((g) => g.name == oldName);
    if (idx != -1) {
      final gen = _generics[idx];
      gen.name = newName;
      if (use != null) gen.use = use;
      if (isActive != null) gen.isActive = isActive;

      if (!kIsWeb) {
        final db = await DbHelper.instance.database;
        await db.update('generics', gen.toMap(), where: 'id = ?', whereArgs: [gen.id]);
      }
      notifyListeners();
    }
  }

  void deleteGeneric(String name) async {
    final idx = _generics.indexWhere((g) => g.name == name);
    if (idx != -1) {
      final genId = _generics[idx].id;
      _generics.removeAt(idx);
      if (!kIsWeb) {
        final db = await DbHelper.instance.database;
        await db.delete('generics', where: 'id = ?', whereArgs: [genId]);
      }
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> importProductMasterFromExcel(String filePath, {Function(double, String)? onProgress, Map<String, int>? customMapping}) async {
    final validation = await validateAndImportFile(filePath);
    if (!validation['success']) return validation;

    try {
      final rawRows = await ExcelWorkerService.parseExcelRawRowsInBackground(filePath);
      if (rawRows.length <= 1) {
        return {'success': false, 'message': 'No data found in file.'};
      }

      final db = await DbHelper.instance.database;

      int imported = 0;
      int errors = 0;
      List<String> errorLogs = [];

      final List<Map<String, dynamic>> allExisting = await db.query('product_master', columns: ['id', 'name']);

      final Map<String, String> nameToId = {
        for (var p in allExisting) p['name'].toString().toLowerCase().trim(): p['id'].toString()
      };
      final Set<String> existingIds = {
        for (var p in allExisting) p['id'].toString()
      };

      final header = rawRows.first.map((e) => e.toLowerCase().trim()).toList();

      int idxId = customMapping?['id'] ?? _findIdx(header, ['product id', 'id', 'pid']);
      int idxName = customMapping?['name'] ?? _findIdx(header, ['product name', 'item name', 'particulars', 'item description', 'description', 'product', 'items', 'name']);
      int idxPack = customMapping?['packing'] ?? _findIdx(header, ['packing', 'pack', 'packsize', 'packng', 'packin', 'unit']);
      int idxRack = customMapping?['rack'] ?? _findIdx(header, ['rack', 'rackid', 'rack_id', 'location']);
      int idxHsn = customMapping?['hsncode'] ?? _findIdx(header, ['hsncode', 'hsn', 'hsn code', 'hcn', 'hcncode']);
      int idxMRP = customMapping?['mrp'] ?? _findIdx(header, ['mrp', 'm.r.p', 'item mrp', 'item_mrp']);
      int idxLCost = customMapping?['p_rate'] ?? _findIdx(header, ['p.rate', 'prate', 'p_rate', 'purchase rate', 'purchase_rate', 'l cost', 'lcost', 'cost price', 'landing cost']);
      int idxSPrice = customMapping?['s_price'] ?? _findIdx(header, ['s price', 's_price', 'sale price', 'sale rate', 's.price', 'srate', 'selling price', 'selling_price']);
      int idxCat = customMapping?['category'] ?? _findIdx(header, ['category', 'category_id', 'cat']);
      int idxSubCat = customMapping?['sub_category'] ?? _findIdx(header, ['subcategory', 'sub category', 'sub_category', 'subcatogory', 'sub cat']);
      int idxPatent = customMapping?['patent'] ?? _findIdx(header, ['patent', 'brand', 'patent name', 'company', 'mfr', 'manufacturer']);
      int idxContent = customMapping?['generic_name'] ?? _findIdx(header, ['generic name', 'generic', 'generic_name', 'content', 'composition', 'composition name']);
      
      int idxGst = customMapping?['gst'] ?? _findIdx(header, ['gst', 'gst%', 'tax', 'tax%', 'taxpercent', 'gst percent']);
      int idxSDisc = customMapping?['sdisc'] ?? _findIdx(header, ['sdisc%', 'sdisc', 's.disc', 's.disc%', 'sales disc', 'sales_discount', 'discount']);
      int idxSch = customMapping?['schedule'] ?? _findIdx(header, ['schedule', 'sch', 'shedule', 'drug class', 'drug type']);
      int idxReorder = customMapping?['reorder'] ?? _findIdx(header, ['reorder level', 'reorder', 'min stock', 'min level', 'reorder level']);
      int idxMax = customMapping?['max'] ?? _findIdx(header, ['max level', 'max', 'max level', 'max lev', 'max stock']);
      int idxStock = customMapping?['stock'] ?? _findIdx(header, ['stock', 'qty', 'current stock', 'quantity']);
      int idxBatch = customMapping?['batch'] ?? _findIdx(header, ['batch', 'batch_number', 'batch no']);
      int idxExp = customMapping?['expiry'] ?? _findIdx(header, ['expiry', 'exp', 'exp date', 'expiry date']);

      final dataRows = rawRows.sublist(1);
      final int totalRows = dataRows.length;
      const int chunkSize = 500; 
      final int totalParts = (totalRows / chunkSize).ceil();

      _cancelImport = false;

      String valRow(List<String> row, int idx) {
        if (idx < 0 || idx >= row.length) return "";
        return row[idx].trim();
      }

      int idSeed = DateTime.now().microsecondsSinceEpoch;

      for (int part = 0; part < totalParts; part++) {
        if (_cancelImport) {
          await loadFromDatabase();
          return {'success': false, 'message': 'Import cancelled by user after processing $imported items.'};
        }
        final int start = part * chunkSize;
        final int end = (start + chunkSize > totalRows) ? totalRows : start + chunkSize;
        final chunk = dataRows.sublist(start, end);

        await db.transaction((txn) async {
          final batch = txn.batch();
          for (int i = 0; i < chunk.length; i++) {
            final row = chunk[i];
            if (row.isEmpty) continue;

            if (onProgress != null && i % 50 == 0) {
              onProgress((start + i) / totalRows, "Part ${part + 1}/$totalParts");
            }

            String excelId = valRow(row, idxId);
            String name = valRow(row, idxName);
            if (!isValidProductName(name)) {
              String found = "";
              for (int col = 0; col < row.length; col++) {
                if (col == idxMRP || col == idxLCost || col == idxSPrice || col == idxPack || col == idxHsn || col == idxGst || col == idxReorder || col == idxMax) continue;
                String candidate = valRow(row, col);
                if (isValidProductName(candidate)) {
                  found = candidate;
                  break;
                }
              }
              if (found.isNotEmpty) {
                name = found;
              } else {
                errors++;
                errorLogs.add("Row ${start + i + 2}: Invalid or numeric product name '$name' skipped.");
                continue;
              }
            }
            String nameLower = name.toLowerCase();

            String rack = valRow(row, idxRack);
            String category = valRow(row, idxCat);
            String subCategory = valRow(row, idxSubCat);
            String patent = valRow(row, idxPatent);
            String manufacturer = patent;

            String content = valRow(row, idxContent);
            if (content.trim().toUpperCase() == name.trim().toUpperCase()) {
              content = "";
            }
            String hsn = valRow(row, idxHsn);
            int pack = _parse(valRow(row, idxPack)).toInt();
            if (pack <= 0) pack = 1;
            double mrp = _parse(valRow(row, idxMRP));
            double lCost = _parse(valRow(row, idxLCost));
            double sPrice = _parse(valRow(row, idxSPrice));
            if (sPrice == 0) sPrice = mrp;

            double gst = TaxCalculator.roundGstPercent(_parse(valRow(row, idxGst)));
            if (gst == 0) gst = 12.0;

            double sdisc = _parse(valRow(row, idxSDisc));
            String sch = valRow(row, idxSch);
            int reorder = _parse(valRow(row, idxReorder)).toInt();
            int maxL = _parse(valRow(row, idxMax)).toInt();

            String productId;
            bool exists = false;

            if (excelId.isNotEmpty && existingIds.contains(excelId)) {
              productId = excelId;
              exists = true;
            } else if (nameToId.containsKey(nameLower)) {
              productId = nameToId[nameLower]!;
              exists = true;
            } else {
              if (excelId.isNotEmpty) {
                productId = excelId;
              } else {
                do {
                  idSeed++;
                  productId = (idSeed % 10000000000).toString().padLeft(10, '0');
                } while (existingIds.contains(productId));
              }
            }

            if (exists) {
              batch.update('product_master', {
                'name': name,
                'rack_id': rack.isNotEmpty ? rack : null,
                'category_id': category.isNotEmpty ? category : null,
                'sub_category_id': subCategory.isNotEmpty ? subCategory : null,
                'manufacturer_id': manufacturer.isNotEmpty ? manufacturer : null,
                'patent': patent.isNotEmpty ? patent : null,
                'generic_name': content.isNotEmpty ? content : null,
                'hsn_code': hsn.isNotEmpty ? hsn : null,
                'packing': pack,
                'gst_percent': gst,
                's_disc_percent': sdisc,
                'schedule': sch,
                'reorder_level': reorder,
                'max_level': maxL,
                'mrp': mrp,
                'purchase_rate': lCost,
                'sale_rate': sPrice,
              }, where: 'id = ?', whereArgs: [productId]);
            } else {
              final newProd = {
                'id': productId,
                'name': name,
                'generic_name': content,
                'manufacturer_id': manufacturer,
                'patent': patent,
                'category_id': category,
                'sub_category_id': subCategory,
                'rack_id': rack,
                'hsn_code': hsn,
                'packing': pack,
                'gst_percent': gst,
                's_disc_percent': sdisc,
                'schedule': sch,
                'reorder_level': reorder,
                'max_level': maxL,
                'mrp': mrp,
                'purchase_rate': lCost,
                'sale_rate': sPrice,
                'is_active': 1,
              };
              batch.insert('product_master', newProd);
              nameToId[nameLower] = productId;
              existingIds.add(productId);
            }

            int stock = _parse(valRow(row, idxStock)).toInt();
            if (stock > 0) {
              String batchNum = valRow(row, idxBatch);
              if (batchNum.isEmpty) batchNum = "OPENING";
              String expRaw = valRow(row, idxExp);
              String exp = _normalizeExpiry(expRaw);

              batch.insert('stock_batches', {
                'product_id': productId,
                'batch_number': batchNum,
                'expiry_date': exp,
                'current_stock': stock,
                'purchase_rate': lCost,
                'landing_cost': lCost,
                'mrp': mrp,
                'sale_rate': sPrice,
                'packing': pack,
                'gst_percent': gst,
                'financial_year': _selectedFinancialYear,
              }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
            }

            imported++;
          }
          await batch.commit(noResult: true);
        });

        if (onProgress != null) {
          onProgress(1.0, "Part ${part + 1}/$totalParts");
        }
        await Future.delayed(const Duration(milliseconds: 10));
      }

      await loadFromDatabase();
      return {'success': true, 'imported': imported, 'errors': errors, 'logs': errorLogs};
    } catch (e) {
      return {'success': false, 'message': 'Import failed: $e'};
    }
  }


  Future<Map<String, dynamic>> importInventoryFromExcel(String filePath, {Function(double, String)? onProgress, Map<String, int>? customMapping}) async {
    final validation = await validateAndImportFile(filePath);
    if (!validation['success']) return validation;

    try {
      final rawRows = await ExcelWorkerService.parseExcelRawRowsInBackground(filePath);
      if (rawRows.length <= 1) {
        return {'success': false, 'message': 'No data found in file.'};
      }

      final db = await DbHelper.instance.database;

      int imported = 0;
      int errors = 0;
      List<String> errorLogs = [];
      List<PurchaseItem> unmappedItems = [];

      final List<Map<String, dynamic>> allExisting = await db.query('product_master', columns: ['id', 'name']);

      final Map<String, String> nameToId = {
        for (var p in allExisting) p['name'].toString().toLowerCase().trim(): p['id'].toString()
      };

      final header = rawRows.first.map((e) => e.toLowerCase().trim()).toList();

      int idxName = customMapping?['name'] ?? _findIdx(header, ['product name', 'item name', 'particulars', 'item description', 'description', 'product', 'items', 'name']);
      int idxStock = customMapping?['stock'] ?? _findIdx(header, ['stock', 'qty', 'current stock']);
      int idxBatch = customMapping?['batch'] ?? _findIdx(header, ['batch', 'batch_number', 'batch no']);
      int idxExp = customMapping?['expiry'] ?? _findIdx(header, ['expiry', 'exp', 'exp date', 'expiry date']);
      int idxMRP = customMapping?['mrp'] ?? _findIdx(header, ['mrp', 'm.r.p']);
      int idxLCost = customMapping?['l_cost'] ?? customMapping?['p_rate'] ?? _findIdx(header, ['p.rate', 'prate', 'purchase rate', 'l cost', 'lcost', 'landing cost']);
      int idxPack = customMapping?['packing'] ?? _findIdx(header, ['packing', 'pack', 'packsize', 'packng']);
      int idxSupplier = customMapping?['supplier'] ?? _findIdx(header, ['supplier', 'supplier name']);
      int idxGst = customMapping?['gst'] ?? _findIdx(header, ['gst', 'gst%', 'tax']);
      int idxCat = customMapping?['category'] ?? _findIdx(header, ['category', 'category_id', 'cat']);
      int idxSubCat = customMapping?['sub_category'] ?? _findIdx(header, ['subcategory', 'sub category', 'sub cat']);
      int idxPatent = customMapping?['patent'] ?? _findIdx(header, ['patent', 'brand', 'company']);
      int idxMfr = customMapping?['manufacturer'] ?? _findIdx(header, ['manufacturer', 'company', 'mfr', 'mfg']);
      int idxContent = customMapping?['generic_name'] ?? _findIdx(header, ['generic name', 'generic', 'generic_name', 'content', 'composition', 'composition name', 'salt', 'formula', 'drug_name', 'molecule', 'active_ingredient', 'generic name / composition', 'generic_name_composition']);

      final dataRows = rawRows.sublist(1);
      final int totalRows = dataRows.length;
      const int chunkSize = 500;
      final int totalParts = (totalRows / chunkSize).ceil();

      _cancelImport = false;

      String valRow(List<String> row, int idx) {
        if (idx < 0 || idx >= row.length) return "";
        return row[idx].trim();
      }

      for (int part = 0; part < totalParts; part++) {
        if (_cancelImport) {
          await loadFromDatabase();
          return {'success': false, 'message': 'Inventory Import cancelled by user after processing $imported items.'};
        }
        final int start = part * chunkSize;
        final int end = (start + chunkSize > totalRows) ? totalRows : start + chunkSize;
        final chunk = dataRows.sublist(start, end);

        await db.transaction((txn) async {
          final batch = txn.batch();
          for (int i = 0; i < chunk.length; i++) {
            final row = chunk[i];
            if (row.isEmpty) continue;

            if (onProgress != null && i % 50 == 0) {
              onProgress((start + i) / totalRows, "Part ${part + 1}/$totalParts");
            }

            String name = valRow(row, idxName);
            if (!isValidProductName(name)) {
              String found = "";
              for (int col = 0; col < row.length; col++) {
                if (col == idxBatch || col == idxExp || col == idxStock || col == idxMRP || col == idxLCost || col == idxPack) continue;
                String candidate = valRow(row, col);
                if (isValidProductName(candidate)) {
                  found = candidate;
                  break;
                }
              }
              if (found.isNotEmpty) {
                name = found;
              } else {
                errors++;
                errorLogs.add("Row ${start + i + 2}: Invalid or numeric product name '$name' skipped.");
                continue;
              }
            }
            String nameLower = name.toLowerCase();

            String batchNum = valRow(row, idxBatch);
            if (batchNum.isEmpty) batchNum = "OPENING";

            String expRaw = valRow(row, idxExp);
            String exp = _normalizeExpiry(expRaw);
            int stock = _parse(valRow(row, idxStock)).toInt();
            double mrp = _parse(valRow(row, idxMRP));
            double lCost = _parse(valRow(row, idxLCost));
            int pack = _parse(valRow(row, idxPack)).toInt();
            if (pack <= 0) pack = 1;
            String supplier = valRow(row, idxSupplier);
            double gst = TaxCalculator.roundGstPercent(_parse(valRow(row, idxGst)));
            if (gst == 0) gst = 12.0;
            String category = valRow(row, idxCat);
            String subCategory = valRow(row, idxSubCat);
            String patent = valRow(row, idxPatent);
            String manufacturer = valRow(row, idxMfr);
            if (manufacturer.isEmpty && patent.isNotEmpty) manufacturer = patent;
            String content = valRow(row, idxContent);

            if (nameToId.containsKey(nameLower)) {
              String productId = nameToId[nameLower]!;

              Map<String, dynamic> updateData = {
                'packing': pack,
                'gst_percent': gst,
              };
              if (category.isNotEmpty) updateData['category_id'] = category;
              if (subCategory.isNotEmpty) updateData['sub_category_id'] = subCategory;
              if (manufacturer.isNotEmpty) updateData['manufacturer_id'] = manufacturer;
              if (patent.isNotEmpty) updateData['patent'] = patent;
              if (content.isNotEmpty) updateData['generic_name'] = content;

              batch.update('product_master', updateData, where: 'id = ?', whereArgs: [productId]);

              batch.insert('stock_batches', {
                'product_id': productId,
                'batch_number': batchNum,
                'expiry_date': exp,
                'current_stock': stock,
                'purchase_rate': lCost,
                'landing_cost': lCost,
                'mrp': mrp,
                'sale_rate': mrp,
                'supplier_name': supplier,
                'packing': pack,
                'gst_percent': gst,
                'financial_year': _selectedFinancialYear,
              }, conflictAlgorithm: sql.ConflictAlgorithm.replace);

              imported++;
            } else {
              // Unmapped product -> collect for line-by-line product mapping dialog
              unmappedItems.add(PurchaseItem(
                id: "UNKNOWN",
                productName: name,
                externalName: name,
                batch: batchNum,
                expiry: exp,
                qty: stock,
                mrp: mrp,
                pRate: lCost,
                sRate: mrp,
                packin: pack,
                gstPercent: gst,
                supplier: supplier,
                category: category,
                subCategory: subCategory,
                manufacturer: manufacturer,
                patent: patent,
                hsnCode: content,
              ));
            }
          }
          await batch.commit(noResult: true);
        });

        if (onProgress != null) {
          onProgress(1.0, "Part ${part + 1}/$totalParts");
        }
        await Future.delayed(const Duration(milliseconds: 10));
      }

      await loadFromDatabase();
      return {
        'success': true,
        'imported': imported,
        'requiresMapping': unmappedItems.isNotEmpty,
        'unmappedItems': unmappedItems,
        'errors': errors,
        'logs': errorLogs,
      };
    } catch (e) {
      return {'success': false, 'message': 'Import failed: $e'};
    }
  }

  Future<void> commitMappedStockImport(List<PurchaseItem> mappedItems) async {
    if (mappedItems.isEmpty) return;
    final db = await DbHelper.instance.database;

    final List<Map<String, dynamic>> allExisting = await db.query('product_master', columns: ['id']);
    final Set<String> existingIds = {for (var p in allExisting) p['id'].toString()};

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (var item in mappedItems) {
        String productId = item.id;
        if (productId.isEmpty || productId == "UNKNOWN") {
          productId = generate10DigitId();
          while (existingIds.contains(productId)) {
            productId = generate10DigitId();
          }
          existingIds.add(productId);

          batch.insert('product_master', {
            'id': productId,
            'name': item.productName.trim(),
            'packing': item.packin,
            'gst_percent': item.gstPercent,
            'category_id': item.category,
            'sub_category_id': item.subCategory,
            'manufacturer_id': item.manufacturer,
            'patent': item.patent,
            'generic_name': item.genericName,
            'is_active': 1,
          });
        }

        int stockQty = item.qty;

        batch.insert('stock_batches', {
          'product_id': productId,
          'batch_number': item.batch.isNotEmpty ? item.batch : "OPENING",
          'expiry_date': item.expiry,
          'current_stock': stockQty,
          'purchase_rate': item.pRate,
          'landing_cost': item.pRate,
          'mrp': item.mrp,
          'sale_rate': item.sRate > 0 ? item.sRate : item.mrp,
          'supplier_name': item.supplier,
          'packing': item.packin,
          'gst_percent': item.gstPercent,
          'financial_year': _selectedFinancialYear,
        }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });

    await loadFromDatabase();
    notifyListeners();
  }

  /// Offloads heavy Excel/CSV supplier catalog decoding to background worker isolate,
  /// then performs chunked transactional insertion (500 rows per chunk) to prevent
  /// SQLite write lock saturation and UI freezing.
  Future<Map<String, dynamic>> processBulkImport(String filePath, {Function(double, String)? onProgress}) async {
    final validation = await validateAndImportFile(filePath);
    if (!validation['success']) return validation;

    try {
      // 1. Parse entirely in background isolate (Zero UI stutter)
      final rawRows = await ExcelWorkerService.parseExcelFileInBackground(filePath);
      if (rawRows.isEmpty) {
        return {'success': false, 'message': 'No data found in spreadsheet.'};
      }

      final db = await DbHelper.instance.database;
      int imported = 0;
      int updated = 0;
      const int chunkSize = 500;

      // Pre-load basic info for O(1) lookup
      final List<Map<String, dynamic>> allExisting = await db.query('product_master', columns: ['id', 'name']);
      final Map<String, String> nameToId = {
        for (var p in allExisting) p['name'].toString().toLowerCase().trim(): p['id'].toString()
      };
      final Set<String> existingIds = {
        for (var p in allExisting) p['id'].toString()
      };

      final int totalRows = rawRows.length;
      final int totalChunks = (totalRows / chunkSize).ceil();
      _cancelImport = false;

      // 2. Insert in partitioned transactions
      for (int i = 0; i < totalRows; i += chunkSize) {
        if (_cancelImport) {
          await loadFromDatabase();
          return {'success': false, 'message': 'Import cancelled by user after processing $imported items.'};
        }

        final chunk = rawRows.skip(i).take(chunkSize).toList();
        final currentChunkNum = (i / chunkSize).floor() + 1;

        if (onProgress != null) {
          onProgress(i / totalRows, "Processing batch $currentChunkNum/$totalChunks");
        }

        await db.transaction((txn) async {
          final batch = txn.batch();
          for (var row in chunk) {
            String getVal(List<String> keys) {
              final normalizedKeys = keys.map((k) => k.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')).toSet();
              for (var entry in row.entries) {
                if (entry.value != null) {
                  String kNorm = entry.key.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
                  if (normalizedKeys.contains(kNorm)) {
                    String val = entry.value.toString().trim();
                    if (val.isNotEmpty) return val;
                  }
                }
              }
              return "";
            }

            String excelId = getVal(['product id', 'id', 'pid']);
            String name = getVal(['name', 'product name', 'item name', 'product']);
            if (name.isEmpty) continue;

            String nameLower = name.toLowerCase();
            String rack = getVal(['rack', 'rackid', 'location']);
            String category = getVal(['category', 'category_id', 'cat']);
            String subCategory = getVal(['subcategory', 'sub category', 'subcat']);
            String patent = getVal(['patent', 'brand', 'company', 'mfr', 'manufacturer']);
            String content = getVal(['generic name', 'generic', 'generic_name', 'content', 'composition', 'composition name', 'salt', 'formula', 'drug_name', 'molecule', 'active_ingredient', 'generic name / composition', 'generic_name_composition']);
            String hsn = getVal(['hsncode', 'hsn', 'hsn code']);

            int pack = int.tryParse(getVal(['packing', 'pack', 'packsize', 'unit'])) ?? 1;
            if (pack <= 0) pack = 1;

            double mrp = double.tryParse(getVal(['mrp', 'm.r.p', 'item mrp'])) ?? 0.0;
            double purchaseRate = double.tryParse(getVal(['p.rate', 'prate', 'purchase rate', 'l cost', 'cost price'])) ?? 0.0;
            double saleRate = double.tryParse(getVal(['s price', 's_price', 'sale price', 'sale rate', 'srate', 'selling price'])) ?? mrp;
            double gst = double.tryParse(getVal(['gst', 'gst%', 'tax', 'tax%'])) ?? 12.0;

            String productId;
            bool exists = false;

            if (excelId.isNotEmpty && existingIds.contains(excelId)) {
              productId = excelId;
              exists = true;
            } else if (nameToId.containsKey(nameLower)) {
              productId = nameToId[nameLower]!;
              exists = true;
            } else {
              productId = excelId.isNotEmpty ? excelId : generate10DigitId();
              while (existingIds.contains(productId)) {
                productId = generate10DigitId();
              }
            }

            if (exists) {
              batch.update('product_master', {
                'name': name,
                'rack_id': rack.isNotEmpty ? rack : null,
                'category_id': category.isNotEmpty ? category : null,
                'sub_category_id': subCategory.isNotEmpty ? subCategory : null,
                'manufacturer_id': patent.isNotEmpty ? patent : null,
                'patent': patent.isNotEmpty ? patent : null,
                'generic_name': content.isNotEmpty ? content : null,
                'hsn_code': hsn.isNotEmpty ? hsn : null,
                'packing': pack,
                'gst_percent': gst,
                'mrp': mrp,
                'purchase_rate': purchaseRate,
                'sale_rate': saleRate,
              }, where: 'id = ?', whereArgs: [productId]);
              updated++;
            } else {
              batch.insert('product_master', {
                'id': productId,
                'name': name,
                'generic_name': content,
                'manufacturer_id': patent,
                'patent': patent,
                'category_id': category,
                'sub_category_id': subCategory,
                'rack_id': rack,
                'hsn_code': hsn,
                'packing': pack,
                'gst_percent': gst,
                'mrp': mrp,
                'purchase_rate': purchaseRate,
                'sale_rate': saleRate,
                'is_active': 1,
              });
              nameToId[nameLower] = productId;
              existingIds.add(productId);
              imported++;
            }
          }
          await batch.commit(noResult: true);
        });

        // Yield control back to the UI thread between chunks to maintain 60 FPS
        await Future.delayed(const Duration(milliseconds: 10));
      }

      await loadFromDatabase();
      if (onProgress != null) onProgress(1.0, "Bulk import completed");

      return {
        'success': true,
        'imported': imported,
        'updated': updated,
        'count': imported + updated,
      };
    } catch (e) {
      return {'success': false, 'message': 'Bulk import failed: $e'};
    }
  }


  Future<Map<String, dynamic>> importProductsFromExcel(String filePath) async {
    final validation = await validateAndImportFile(filePath);
    if (!validation['success']) return validation;

    try {
      final rawRows = await ExcelWorkerService.parseExcelRawRowsInBackground(filePath);
      if (rawRows.length <= 1) {
        return {'success': false, 'message': 'No data found in file.'};
      }
      final db = await DbHelper.instance.database;

      int imported = 0;
      int errors = 0;
      List<String> errorLogs = [];

      // Pre-load all existing products into memory for O(1) lookup
      final List<Map<String, dynamic>> allExisting = await db.query('product_master', columns: ['id', 'name', 'rack_id', 'category_id', 'hsn_code', 'packing']);
      final Map<String, Map<String, dynamic>> nameToProduct = {
        for (var p in allExisting) p['name'].toString().toLowerCase().trim(): Map.from(p)
      };

      final header = rawRows.first.map((e) => e.toLowerCase().trim()).toList();

      int idxName = _findIdx(header, ['name', 'product name', 'item name', 'product']);
      int idxRack = _findIdx(header, ['rack', 'location']);
      int idxCategory = _findIdx(header, ['category', 'category_id', 'cat']);
      int idxPatent = _findIdx(header, ['patent', 'brand', 'company', 'manufacturer', 'mfr']);
      int idxHsn = _findIdx(header, ['hsncode', 'hsn', 'hsn code']);
      int idxPack = _findIdx(header, ['packing', 'pack', 'packsize']);
      int idxPRate = _findIdx(header, ['p.rate', 'prate', 'purchase rate', 'l cost']);
      int idxMRP = _findIdx(header, ['mrp', 'm.r.p']);

      const int chunkSize = 500;
      final dataRows = rawRows.sublist(1);

      String valRow(List<String> row, int idx) {
        if (idx < 0 || idx >= row.length) return "";
        return row[idx].trim();
      }

      for (int i = 0; i < dataRows.length; i += chunkSize) {
        final chunk = dataRows.skip(i).take(chunkSize).toList();

        await db.transaction((txn) async {
          final batch = txn.batch();
          for (int j = 0; j < chunk.length; j++) {
            final row = chunk[j];
            if (row.isEmpty) continue;

            String name = valRow(row, idxName);
            if (name.isEmpty) {
              errors++;
              errorLogs.add("Row ${i + j + 1}: Name is empty");
              continue;
            }
            String nameLower = name.toLowerCase();

            String rack = valRow(row, idxRack);
            String category = valRow(row, idxCategory);
            String patent = valRow(row, idxPatent);
            String hsn = valRow(row, idxHsn);
            int pack = _parse(valRow(row, idxPack)).toInt();
            if (pack <= 0) pack = 1;
            double pRate = _parse(valRow(row, idxPRate));
            double mrp = _parse(valRow(row, idxMRP));

            String finalProdId;
            if (nameToProduct.containsKey(nameLower)) {
              final existing = nameToProduct[nameLower]!;
              finalProdId = existing['id'] as String;

              batch.update('product_master', {
                'rack_id': rack.isNotEmpty ? rack : existing['rack_id'],
                'category_id': category.isNotEmpty ? category : existing['category_id'],
                'manufacturer_id': patent.isNotEmpty ? patent : existing['manufacturer_id'],
                'hsn_code': hsn.isNotEmpty ? hsn : existing['hsn_code'],
                'packing': pack,
              }, where: 'id = ?', whereArgs: [finalProdId]);
            } else {
              finalProdId = generate10DigitId();
              final newProd = {
                'id': finalProdId,
                'name': name,
                'rack_id': rack,
                'category_id': category,
                'manufacturer_id': patent,
                'hsn_code': hsn,
                'packing': pack,
                'is_active': 1,
              };
              batch.insert('product_master', newProd);
              nameToProduct[nameLower] = newProd;
            }

            // Insert a default batch if P.Rate or MRP is provided
            if (pRate > 0 || mrp > 0) {
              batch.insert('stock_batches', {
                'product_id': finalProdId,
                'batch_number': "OPENING",
                'current_stock': 0,
                'purchase_rate': pRate,
                'mrp': mrp,
                'sale_rate': mrp,
              }, conflictAlgorithm: sql.ConflictAlgorithm.ignore);
            }

            imported++;
          }
          await batch.commit(noResult: true);
        });
        await Future.delayed(const Duration(milliseconds: 10));
      }

      await loadFromDatabase();
      return {
        'success': true,
        'imported': imported,
        'errors': errors,
        'logs': errorLogs,
      };
    } catch (e) {
      return {'success': false, 'message': 'Import failed: $e'};
    }
  }

  Future<Map<String, dynamic>> analyzeExcelForImport(String filePath) async {
    final validation = await validateAndImportFile(filePath);
    if (!validation['success']) return validation;

    try {
      return await ExcelWorkerService.analyzeExcelPreviewInBackground(filePath);
    } catch (e) {
      return {'success': false, 'message': 'Analysis failed: $e'};
    }
  }

  Future<Map<String, dynamic>> importSalesFromExcel(
    String filePath, {
    Function(double, String)? onProgress,
    Map<String, int>? customMapping,
    String? financialYear,
  }) async {
    final validation = await validateAndImportFile(filePath);
    if (!validation['success']) return validation;

    try {
      onProgress?.call(0.05, "Reading file in background isolate...");
      
      // 1. Offload heavy file decoding (XLSX or CSV) to a background worker isolate
      final rawRows = await ExcelWorkerService.parseExcelRawRowsInBackground(filePath);
      if (rawRows.length <= 1) {
        return {'success': false, 'message': 'No data rows found in file.'};
      }

      final db = await DbHelper.instance.database;

      // 2. Locate header row (handles metadata headers like 'Report Summery From...')
      int headerRowIdx = 0;
      for (int r = 0; r < rawRows.length && r < 6; r++) {
        final line = rawRows[r].map((e) => e.toLowerCase().trim()).join(' ');
        if (line.contains('entry no') || line.contains('invoice') || line.contains('product') || line.contains('date')) {
          headerRowIdx = r;
          break;
        }
      }

      final header = rawRows[headerRowIdx].map((e) => e.toLowerCase().trim()).toList();

      int idxInvoiceNo = customMapping?['invoice_no'] ?? _findIdx(header, ['entry no', 'invoice no', 'invoice', 'entry', 'bill no']);
      int idxDate = customMapping?['date'] ?? _findIdx(header, ['date', 'bill date', 'inv date', 'entry date', 'sales date', 'invoice date', 'trans date', 'txn date', 'dated', 'dt', 'billing date', 'date time', 'created at', 'creation date']);
      int idxTime = customMapping?['time'] ?? _findIdx(header, ['time']);
      int idxPatient = customMapping?['patient'] ?? _findIdx(header, ['patient', 'customer', 'customer acc', 'party']);
      int idxMobile = customMapping?['mobile'] ?? _findIdx(header, ['mobile', 'mobile no', 'phone', 'contact']);
      int idxAccount = customMapping?['account'] ?? _findIdx(header, ['account', 'customer acc', 'acc type', 'mode']);
      int idxAgent = customMapping?['agent'] ?? _findIdx(header, ['agent', 'sales agent', 'staff', 'ho id']);
      int idxDoctor = customMapping?['doctor'] ?? _findIdx(header, ['doctor', 'dr']);
      int idxProduct = customMapping?['product'] ?? _findIdx(header, ['product', 'product name', 'item', 'name', 'particulars']);
      int idxBatch = customMapping?['batch'] ?? _findIdx(header, ['batch', 'batch number', 'batch no']);
      int idxExp = _findIdx(header, ['expiary', 'expiry', 'exp', 'exp date']);
      int idxQty = customMapping?['qty'] ?? _findIdx(header, ['qty', 'quantity']);
      int idxPacking = customMapping?['packing'] ?? _findIdx(header, ['packing', 'pack', 'pck', 'packin']);
      int idxSRate = customMapping?['s_rate'] ?? _findIdx(header, ['s.rate', 'srate', 'sale rate', 'selling rate', 'rate']);
      int idxMRP = customMapping?['mrp'] ?? _findIdx(header, ['mrp', 'item mrp']);
      _findIdx(header, ['gross']);
      int idxDiscAmt = customMapping != null ? (customMapping['disc_amt'] ?? -1) : _findIdx(header, ['disc amount', 'disc amt', 'discount', 'disc']);
      int idxDiscPerc = customMapping != null ? (customMapping['disc_perc'] ?? -1) : _findIdx(header, ['disc %', 'discount %', 'disc percent']);
      int idxNet = customMapping?['net'] ?? _findIdx(header, ['net', 'taxable', 'taxable amount']);
      int idxTotal = customMapping?['total'] ?? _findIdx(header, ['total', 'grand total', 'amount']);
      int idxGSTAmt = customMapping != null ? (customMapping['gst_amt'] ?? -1) : _findIdx(header, ['gst_amt', 'gst amt', 'tax amt', 'tax']);
      int idxGSTPerc = customMapping != null ? (customMapping['gst_perc'] ?? -1) : _findIdx(header, ['gst %', 'tax %', 'gst percent']);
      int idxProfit = customMapping?['profit'] ?? _findIdx(header, ['profit', 'profit amt', 'margin']);

      // 3. Pre-load catalog into memory for O(1) hash lookups
      onProgress?.call(0.15, "Caching database catalog...");
      final List<Map<String, dynamic>> allProds = await db.query('product_master', columns: ['id', 'name']);
      final Map<String, String> nameToId = {
        for (var p in allProds) p['name'].toString().toLowerCase().trim(): p['id'].toString()
      };
      final Set<String> existingIds = {
        for (var p in allProds) p['id'].toString()
      };

      int idSeed = DateTime.now().microsecondsSinceEpoch;

      // 4. Group rows by invoice number in memory
      onProgress?.call(0.25, "Grouping invoices...");
      Map<String, List<Map<String, dynamic>>> invoiceGroups = {};
      int dataStart = headerRowIdx + 1;

      String getCell(List<String> r, int idx) {
        if (idx < 0 || idx >= r.length) return "";
        return r[idx].trim();
      }

      for (int i = dataStart; i < rawRows.length; i++) {
        final row = rawRows[i];
        if (row.isEmpty) continue;

        String invoiceNo = getCell(row, idxInvoiceNo);
        if (double.tryParse(invoiceNo) != null) {
          invoiceNo = double.parse(invoiceNo).toInt().toString();
        }
        if (invoiceNo.isEmpty) continue;

        String rawDate = getCell(row, idxDate);
        DateTime invoiceDate = _parseExcelDate(rawDate);

        String rawTime = getCell(row, idxTime);
        if (rawTime.isNotEmpty) {
          try {
            final parts = rawTime.split(RegExp(r'[:\s]'));
            if (parts.length >= 2) {
              int h = int.parse(parts[0]);
              int m = int.parse(parts[1]);
              int s = parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0;
              if (rawTime.toUpperCase().contains("PM") && h < 12) h += 12;
              if (rawTime.toUpperCase().contains("AM") && h == 12) h = 0;
              invoiceDate = DateTime(invoiceDate.year, invoiceDate.month, invoiceDate.day, h, m, s);
            }
          } catch (_) {}
        }

        double packMrp = _parse(getCell(row, idxMRP));
        double qty = _parse(getCell(row, idxQty));
        double discAmt = idxDiscAmt != -1 ? _parse(getCell(row, idxDiscAmt)) : 0.0;
        double gstAmt = idxGSTAmt != -1 ? _parse(getCell(row, idxGSTAmt)) : 0.0;
        double net = idxNet != -1 ? _parse(getCell(row, idxNet)) : 0.0;
        double totalVal = idxTotal != -1 ? _parse(getCell(row, idxTotal)) : 0.0;

        int packing = _parse(getCell(row, idxPacking)).toInt();
        if (packing <= 0) packing = 1;

        double unitSRate = 0.0;
        if (idxSRate != -1 && getCell(row, idxSRate).isNotEmpty) {
          double rawSRate = _parse(getCell(row, idxSRate));
          unitSRate = (rawSRate > 0 && packing > 1 && rawSRate >= packMrp) ? (rawSRate / packing) : rawSRate;
          if (unitSRate <= 0) unitSRate = packMrp > 0 ? (packMrp / packing) : 0.0;
        } else if (packMrp > 0) {
          unitSRate = packMrp / packing;
        } else if (totalVal > 0 && qty > 0) {
          unitSRate = totalVal / qty;
        } else if (net > 0 && qty > 0) {
          unitSRate = (net + discAmt - gstAmt) / qty;
        } else {
          unitSRate = 0.0;
        }

        if (packMrp <= 0) {
          packMrp = unitSRate > 0 ? unitSRate * packing : 0.0;
        }

        double gross = unitSRate * qty;
        if (gross <= 0 && totalVal > 0) gross = totalVal + discAmt;

        double discPerc = 0.0;
        if (idxDiscPerc != -1 && getCell(row, idxDiscPerc).isNotEmpty) {
          discPerc = _parse(getCell(row, idxDiscPerc));
        } else if (discAmt > 0 && gross > 0) {
          discPerc = (discAmt * 100) / gross;
        }

        if (discPerc > 0 && discAmt <= 0 && gross > 0) {
          discAmt = (gross * discPerc) / 100.0;
        }

        double taxable = gross - discAmt;
        if (taxable < 0) taxable = 0;

        double gstPerc = 0.0;
        if (idxGSTPerc != -1 && getCell(row, idxGSTPerc).isNotEmpty) {
          gstPerc = TaxCalculator.roundGstPercent(_parse(getCell(row, idxGSTPerc)));
        } else if (gstAmt > 0 && taxable > 0) {
          gstPerc = TaxCalculator.roundGstPercent((gstAmt * 100) / taxable);
        }

        int taxablePaise = TaxCalculator.toPaise(taxable);
        double calculatedGstAmt = gstAmt;
        double calculatedTotal = taxable + gstAmt;

        if (gstPerc > 0) {
          final taxRes = TaxCalculator.calculateInclusivePaise(taxablePaise, gstPerc);
          calculatedGstAmt = taxRes.gstAmount;
          calculatedTotal = taxRes.totalAmount;
        }

        if (totalVal <= 0) {
          totalVal = net > 0 ? net : calculatedTotal;
        }
        if (gstAmt <= 0 && gstPerc > 0) {
          gstAmt = calculatedGstAmt;
        }

        double profit = idxProfit != -1 ? _parse(getCell(row, idxProfit)) : 0.0;

        invoiceGroups.putIfAbsent(invoiceNo, () => []).add({
          'date': invoiceDate,
          'patient': getCell(row, idxPatient).isNotEmpty ? getCell(row, idxPatient) : 'General',
          'mobile': getCell(row, idxMobile),
          'account': getCell(row, idxAccount).isNotEmpty ? getCell(row, idxAccount) : 'Cash',
          'agent': getCell(row, idxAgent).isNotEmpty ? getCell(row, idxAgent) : 'Admin',
          'doctor': getCell(row, idxDoctor).isNotEmpty ? getCell(row, idxDoctor) : 'Unknown',
          'product': getCell(row, idxProduct),
          'batch': getCell(row, idxBatch),
          'expiry': _normalizeExpiry(getCell(row, idxExp)),
          'qty': qty.toInt(),
          'packing': packing,
          's_rate': unitSRate,
          'mrp': packMrp,
          'disc_perc': discPerc,
          'disc_amt': discAmt,
          'gst_perc': gstPerc,
          'gst_amt': gstAmt,
          'total': totalVal,
          'profit': profit,
        });
      }

      // 5. Chunked Batch Insertion
      final Set<String> targetFys = {};
      if (financialYear != null && financialYear != 'All Years' && financialYear.isNotEmpty) {
        targetFys.add(financialYear);
      } else {
        for (var entry in invoiceGroups.entries) {
          if (entry.value.isNotEmpty) {
            DateTime dt = entry.value.first['date'];
            targetFys.add(_getCalculatedFY(dt));
          }
        }
      }

      onProgress?.call(0.35, "Clearing old sales data for target financial year(s)...");
      if (targetFys.isNotEmpty) {
        for (var fy in targetFys) {
          final invoices = await db.query('sales_invoices', where: 'financial_year = ?', whereArgs: [fy], columns: ['entry_no']);
          for (var inv in invoices) {
            await db.delete('sales_items', where: 'invoice_no = ?', whereArgs: [inv['entry_no'].toString()]);
          }
          await db.delete('sales_invoices', where: 'financial_year = ?', whereArgs: [fy]);
        }
      } else {
        await db.delete('sales_items');
        await db.delete('sales_invoices');
      }
      
      onProgress?.call(0.36, "Writing invoices to local database...");
      int totalInvoices = invoiceGroups.length;
      int currentInv = 0;
      int importedInvoices = 0;
      int importedItems = 0;

      final invoiceEntries = invoiceGroups.entries.toList();
      const int batchChunkSize = 500;

      for (int bStart = 0; bStart < invoiceEntries.length; bStart += batchChunkSize) {
        final bEnd = (bStart + batchChunkSize < invoiceEntries.length) ? bStart + batchChunkSize : invoiceEntries.length;
        final chunk = invoiceEntries.sublist(bStart, bEnd);

        await db.transaction((txn) async {
          final batch = txn.batch();

          for (var entry in chunk) {
            currentInv++;
            String invoiceNo = entry.key;
            var rows = entry.value;
            if (rows.isEmpty) continue;

            DateTime invoiceDate = rows.first['date'];
            String patient = rows.first['patient'];
            String mobile = rows.first['mobile'];
            String account = rows.first['account'];
            String agent = rows.first['agent'];
            String doctor = rows.first['doctor'];

            double grandTotal = rows.fold(0.0, (sum, r) => sum + (r['total'] as double));

            batch.insert('sales_invoices', {
              'entry_no': invoiceNo,
              'invoice_no': invoiceNo,
              'date': invoiceDate.toIso8601String(),
              'customer_acc': account,
              'customer_name': patient,
              'patient': patient,
              'mobile': mobile,
              'agent': agent,
              'doctor': doctor,
              'sub_total': grandTotal,
              'total_amount': grandTotal,
              'grand_total': grandTotal,
              'rcvd_amt': grandTotal,
              'is_deleted': 0,
              'is_paid': 1,
              'financial_year': _getCalculatedFY(invoiceDate),
            }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
            importedInvoices++;

            batch.delete('sales_items', where: 'invoice_no = ?', whereArgs: [invoiceNo]);

            for (var r in rows) {
              final String prodName = r['product'].toString().trim();
              if (prodName.isEmpty) continue;

              String nameLower = prodName.toLowerCase();
              String prodId = nameToId[nameLower] ?? "";
              if (prodId.isEmpty) {
                do {
                  idSeed++;
                  prodId = (idSeed % 10000000000).toString().padLeft(10, '0');
                } while (existingIds.contains(prodId));

                batch.insert('product_master', {
                  'id': prodId,
                  'name': prodName,
                  'packing': r['packing'] ?? 1,
                  'is_active': 1,
                }, conflictAlgorithm: sql.ConflictAlgorithm.ignore);

                nameToId[nameLower] = prodId;
                existingIds.add(prodId);
              }

              final String batchNo = r['batch'].toString().trim().isEmpty ? "OPENING" : r['batch'].toString().trim();
              final int qty = r['qty'] as int;
              final double sRate = r['s_rate'] as double;
              final double mrp = r['mrp'] as double;
              final double net = r['total'] as double;
              final double discPerc = r['disc_perc'] as double;
              final double discAmt = r['disc_amt'] as double;
              final double gstPerc = r['gst_perc'] as double;
              final double gstAmt = r['gst_amt'] as double;
              final double profit = r['profit'] as double;

              batch.insert('sales_items', {
                'invoice_no': invoiceNo,
                'product_id': prodId,
                'product_name': prodName,
                'batch_number': batchNo,
                'expiry_date': r['expiry'] ?? '',
                'qty': qty,
                'quantity': qty,
                'packin': r['packing'] ?? 1,
                'packing': r['packing'] ?? 1,
                'mrp': mrp,
                's_rate': sRate,
                'sale_rate': sRate,
                'taxable_sp': sRate,
                'disc_percent': discPerc,
                'disc_amt': discAmt,
                'gst_percent': gstPerc,
                'tax_percent': gstPerc,
                'gst_amt': gstAmt,
                'cgst_amt': gstAmt / 2,
                'sgst_amt': gstAmt / 2,
                'total': net,
                'profit': profit,
              });

              importedItems++;
            }
          }
          await batch.commit(noResult: true);
        });

        if (onProgress != null) {
          double progress = 0.35 + ((currentInv / totalInvoices) * 0.60);
          onProgress(progress, "Imported $currentInv of $totalInvoices invoices");
        }
        await Future.delayed(const Duration(milliseconds: 10));
      }

      onProgress?.call(0.98, "Reloading database cache...");
      await loadFromDatabase();
      onProgress?.call(1.0, "Import complete!");

      final Set<String> importedYears = {};
      for (var group in invoiceGroups.values) {
        if (group.isNotEmpty) importedYears.add(_getCalculatedFY(group.first['date']));
      }

      return {
        'success': true,
        'invoices': importedInvoices,
        'items': importedItems,
        'years': importedYears.toList(),
        'currentFY': _selectedFinancialYear,
      };
    } catch (e) {
      debugPrint("Import Sales Error: $e");
      return {'success': false, 'message': 'Sales import failed: $e'};
    }
  }

  Future<Map<String, dynamic>> importPurchaseFromExcel(
    String filePath, {
    Function(double, String)? onProgress,
    Map<String, int>? customMapping,
    String? financialYear,
  }) async {
    final validation = await validateAndImportFile(filePath);
    if (!validation['success']) return validation;

    try {
      onProgress?.call(0.05, "Reading file in background isolate...");

      final rawRows = await ExcelWorkerService.parseExcelRawRowsInBackground(filePath);
      if (rawRows.length <= 1) {
        return {'success': false, 'message': 'No data rows found in file.'};
      }

      final db = await DbHelper.instance.database;

      int importedPurchases = 0;
      int importedItems = 0;

      Map<String, List<Map<String, dynamic>>> purchaseGroups = {};

      int headerRowIdx = 0;
      for (int r = 0; r < rawRows.length && r < 6; r++) {
        final line = rawRows[r].map((e) => e.toLowerCase().trim()).join(' ');
        if (line.contains('entry no') || line.contains('purchase') || line.contains('product') || line.contains('date') || line.contains('supplier')) {
          headerRowIdx = r;
          break;
        }
      }

      final header = rawRows[headerRowIdx].map((e) => e.toLowerCase().trim()).toList();

      int idxEntryNo = customMapping?['entry_no'] ?? _findIdx(header, ['entry no', 'purchase no', 'entry', 'sl no', 'slno']);
      int idxDate = customMapping?['date'] ?? _findIdx(header, ['date', 'inv date', 'bill date', 'entry date', 'purchase date', 'invoice date', 'trans date', 'txn date', 'dated', 'dt', 'p.date', 'pdate']);
      int idxTime = customMapping?['time'] ?? _findIdx(header, ['time']);
      int idxSupplier = customMapping?['supplier'] ?? _findIdx(header, ['supplier', 'vendor', 'party', 'account']);
      int idxInvNo = customMapping?['inv_no'] ?? _findIdx(header, ['invoice no', 'inv no', 'bill no', 'inv.no', 'bill#', 'inv number']);
      int idxInvDate = customMapping?['inv_date'] ?? _findIdx(header, ['inv date', 'bill date', 'invoice date', 'sup inv date', 'supplier inv date', 'p.date', 'pdate']);
      int idxDoneBy = customMapping?['done_by'] ?? _findIdx(header, ['done by', 'staff', 'entry by']);
      int idxProduct = customMapping?['product'] ?? _findIdx(header, ['product', 'product name', 'item', 'name', 'description']);
      int idxBatch = customMapping?['batch'] ?? _findIdx(header, ['batch', 'batch no', 'batch number']);
      int idxExp = customMapping?['expiry'] ?? _findIdx(header, ['expiry', 'exp', 'exp date', 'validity']);
      int idxQty = customMapping?['qty'] ?? _findIdx(header, ['qty', 'quantity', 'billed qty']);
      int idxFQty = customMapping?['f_qty'] ?? customMapping?['fqty'] ?? _findIdx(header, ['f.qty', 'free qty', 'fqty', 'free']);
      int idxPacking = customMapping?['packing'] ?? _findIdx(header, ['packing', 'pack', 'pck', 'pk']);
      int idxMRP = customMapping?['mrp'] ?? _findIdx(header, ['mrp', 'max price']);
      int idxPRate = customMapping?['p_rate'] ?? customMapping?['prate'] ?? _findIdx(header, ['p.rate', 'prate', 'purchase rate', 'cost', 'cost rate']);
      int idxNet = customMapping?['net'] ?? _findIdx(header, ['net', 'taxable', 'taxable value', 'taxable amount']);
      int idxTotal = customMapping?['total'] ?? _findIdx(header, ['total', 'grand total', 'amount', 'bill total']);
      int idxDiscPerc = customMapping != null ? (customMapping['disc_perc'] ?? -1) : _findIdx(header, ['disc %', 'discount %', 'disc percent']);
      int idxDiscAmt = customMapping != null ? (customMapping['disc_amt'] ?? -1) : _findIdx(header, ['disc amt', 'discount amt', 'discount value', 'disc val', 'discount', 'disc']);
      int idxGSTPerc = customMapping != null ? (customMapping['gst_perc'] ?? -1) : _findIdx(header, ['gst %', 'tax %', 'tax percent', 'gst percent', 'gst rate', 'tax rate']);
      int idxGSTAmt = customMapping != null ? (customMapping['gst_amt'] ?? -1) : _findIdx(header, ['gst amt', 'tax amt', 'gst value', 'tax value', 'tax', 'gst', 'gst_amt', 'total gst']);

      String valRow(List<String> row, int idx) {
        if (idx < 0 || idx >= row.length) return "";
        return row[idx].trim();
      }

      int totalRows = rawRows.length - (headerRowIdx + 1);
      _cancelImport = false;

      for (int i = headerRowIdx + 1; i < rawRows.length; i++) {
        if (_cancelImport) {
          return {'success': false, 'message': 'Purchase import cancelled by user.'};
        }
        final row = rawRows[i];
        if (row.isEmpty) continue;
        
        if (onProgress != null && i % 100 == 0) {
          onProgress(i / totalRows * 0.4, "Reading Row $i of $totalRows");
        }

        String entryNo = valRow(row, idxEntryNo);
        if (double.tryParse(entryNo) != null) {
          entryNo = double.parse(entryNo).toInt().toString();
        }

        String rawDate = valRow(row, idxDate);
        DateTime pDate = _parseExcelDate(rawDate);

        if (entryNo.isEmpty) {
          // Group by Date + Supplier + Invoice No if available
          String supplier = valRow(row, idxSupplier).toUpperCase();
          String invNo = valRow(row, idxInvNo).toUpperCase();
          String dateKey = "${pDate.day}${pDate.month}${pDate.year}";
          
          if (invNo.isEmpty) {
            // UNNAMED INVOICE: Treat every row as its own unique purchase 
            // so we don't accidentally merge 500 medicines into one bill
            entryNo = "UNIQUE-$i-$dateKey"; 
          } else {
            entryNo = "GRP-$dateKey-$supplier-$invNo";
          }
        }

        String fy = _getCalculatedFY(pDate);
        String groupKey = (entryNo.startsWith("GRP-") || entryNo.startsWith("UNIQUE-")) ? entryNo : "${fy}_$entryNo";

        // Merge Time if provided
        String rawTime = valRow(row, idxTime);
        if (rawTime.isNotEmpty) {
          try {
            if (double.tryParse(rawTime) != null) {
              double timeFrac = double.parse(rawTime);
              int totalSeconds = (timeFrac * 86400).round();
              int hours = totalSeconds ~/ 3600;
              int minutes = (totalSeconds % 3600) ~/ 60;
              int seconds = totalSeconds % 60;
              pDate = DateTime(pDate.year, pDate.month, pDate.day, hours, minutes, seconds);
            } else {
              List<String> parts = rawTime.split(RegExp(r'[:\s]'));
              if (parts.length >= 2) {
                int h = int.parse(parts[0]);
                int m = int.parse(parts[1]);
                int s = parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0;
                if (rawTime.toUpperCase().contains("PM") && h < 12) h += 12;
                if (rawTime.toUpperCase().contains("AM") && h == 12) h = 0;
                pDate = DateTime(pDate.year, pDate.month, pDate.day, h, m, s);
              }
            }
          } catch (e) {
            debugPrint("Time parsing failed for '$rawTime': $e");
          }
        }

        double pRate = _parse(valRow(row, idxPRate));
        double qty = _parse(valRow(row, idxQty));
        double fQty = _parse(valRow(row, idxFQty));
        double gross = pRate * qty;
        
        double discPerc = 0.0;
        if (idxDiscPerc != -1 && valRow(row, idxDiscPerc).isNotEmpty) {
          discPerc = _parse(valRow(row, idxDiscPerc));
        }

        double discAmt = 0.0;
        if (idxDiscAmt != -1 && valRow(row, idxDiscAmt).isNotEmpty) {
          discAmt = _parse(valRow(row, idxDiscAmt));
        }

        if (discPerc == 0.0 && discAmt > 0 && gross > 0) {
          discPerc = (discAmt * 100) / gross;
        } else if (discAmt == 0.0 && discPerc > 0 && gross > 0) {
          discAmt = (gross * discPerc) / 100;
        }

        double net = _parse(valRow(row, idxNet));
        double totalExcel = _parse(valRow(row, idxTotal));
        double gstAmt = 0.0;
        if (idxGSTAmt != -1 && valRow(row, idxGSTAmt).isNotEmpty) {
          gstAmt = _parse(valRow(row, idxGSTAmt));
        }
        
        double calculatedTaxable = gross - (gross * discPerc / 100);
        
        // Decide on the true Taxable Net
        if (net > 0) {
          // If net is much larger than calculated taxable, it's probably the grand total
          if (calculatedTaxable > 0 && net > (calculatedTaxable + 0.1)) {
            if (totalExcel <= 0) totalExcel = net; // Shift net to total
            net = calculatedTaxable; // Use calculated base
          }
        } else {
          // If Net column is missing, use calculated or derive from Total
          if (totalExcel > 0 && gstAmt > 0) {
            net = totalExcel - gstAmt;
          } else {
            net = calculatedTaxable;
          }
        }

        double gstPerc = 0.0;
        if (idxGSTPerc != -1 && valRow(row, idxGSTPerc).isNotEmpty) {
          gstPerc = TaxCalculator.roundGstPercent(_parse(valRow(row, idxGSTPerc)));
        } else if (gstAmt > 0 && net > 0) {
          // Back-calculate GST% using the clean taxable base
          gstPerc = TaxCalculator.roundGstPercent((gstAmt * 100) / net);
        }

        int packing = _parse(valRow(row, idxPacking)).toInt();
        if (packing <= 0) packing = 1;

        purchaseGroups.putIfAbsent(groupKey, () => []).add({
          'date': pDate,
          'supplier': valRow(row, idxSupplier),
          'doneBy': valRow(row, idxDoneBy),
          'invNo': valRow(row, idxInvNo),
          'invDate': valRow(row, idxInvDate),
          'product': valRow(row, idxProduct),
          'batch': valRow(row, idxBatch),
          'expiry': _normalizeExpiry(valRow(row, idxExp)),
          'qty': qty.toInt(),
          'f_qty': fQty.toInt(),
          'packing': packing,
          'mrp': _parse(valRow(row, idxMRP)),
          'p_rate': pRate,
          'disc_perc': discPerc,
          'gst_perc': gstPerc,
          'net': net,
        });
      }

      final List<Map<String, dynamic>> allProds = await db.query('product_master', columns: ['id', 'name', 'rack_id', 'hsn_code', 's_disc_percent']);
      final Map<String, Map<String, dynamic>> nameToProfile = {
        for (var p in allProds) p['name'].toString().toLowerCase().trim(): p
      };

      final Map<String, int> fyNextNo = {};

      final Set<String> targetFys = {};
      if (financialYear != null && financialYear != 'All Years' && financialYear.isNotEmpty) {
        targetFys.add(financialYear);
      } else {
        for (var entry in purchaseGroups.entries) {
          if (entry.value.isNotEmpty) {
            DateTime dt = entry.value.first['date'];
            targetFys.add(_getCalculatedFY(dt));
          }
        }
      }

      onProgress?.call(0.35, "Clearing old purchase data for target financial year(s)...");
      if (targetFys.isNotEmpty) {
        for (var fy in targetFys) {
          final entries = await db.query('purchase_entries', where: 'financial_year = ?', whereArgs: [fy], columns: ['entry_no']);
          for (var e in entries) {
            await db.delete('purchase_items', where: 'entry_no = ?', whereArgs: [e['entry_no'].toString()]);
          }
          await db.delete('purchase_entries', where: 'financial_year = ?', whereArgs: [fy]);
        }
      } else {
        await db.delete('purchase_items');
        await db.delete('purchase_entries');
      }

      await db.transaction((txn) async {
        int totalPurchases = purchaseGroups.length;
        int currentP = 0;
        
        for (var entry in purchaseGroups.entries) {
          currentP++;
          if (onProgress != null) {
            onProgress(0.4 + (currentP / totalPurchases * 0.6), "Importing Purchase $currentP of $totalPurchases");
          }
          
          String entryNo = entry.key;
          var rows = entry.value;
          if (rows.isEmpty) continue;

          DateTime pDate = rows.first['date'];
          String supplier = rows.first['supplier'];
          String doneBy = rows.first['doneBy'];
          String fy = _getCalculatedFY(pDate);

          // If entryNo is one of our generated GRP keys, replace it with a sequential numeric ID
          if (entryNo.startsWith("GRP-") || entryNo.startsWith("UNIQUE-")) {
            if (!fyNextNo.containsKey(fy)) {
              final List<Map<String, dynamic>> result = await txn.rawQuery(
                  'SELECT MAX(CAST(entry_no AS INTEGER)) as max_no FROM purchase_entries WHERE financial_year = ?', [fy]);
              fyNextNo[fy] = ((result.first['max_no'] as int?) ?? 0) + 1;
            }
            entryNo = fyNextNo[fy].toString();
            fyNextNo[fy] = fyNextNo[fy]! + 1;
          }

          double subTotal = 0.0;
          double discount = 0.0;
          double grandTotal = 0.0;
          
          for (var r in rows) {
            final double pRate = (r['p_rate'] as num?)?.toDouble() ?? 0.0;
            final int qty = (r['qty'] as num?)?.toInt() ?? 0;
            final double discPerc = (r['disc_perc'] as num?)?.toDouble() ?? 0.0;
            final double gstPerc = (r['gst_perc'] as num?)?.toDouble() ?? 0.0;
            
            double gross = pRate * qty;
            double discAmt = (gross * discPerc) / 100;
            double net = gross - discAmt;
            double gstAmt = (net * gstPerc) / 100;
            
            subTotal += gross;
            discount += discAmt;
            grandTotal += (net + gstAmt);
          }

          await txn.insert('purchase_entries', {
            'entry_no': entryNo,
            'date': pDate.toIso8601String(),
            'supplier_name': supplier,
            'done_by': doneBy,
            'sup_inv_no': rows.first['invNo'],
            'sup_inv_date': DateTime.tryParse(rows.first['invDate'] ?? "")?.toIso8601String() ?? pDate.toIso8601String(),
            'sub_total': subTotal,
            'discount': discount,
            'grand_total': grandTotal,
            'payment_status': 1,
            'paid_amount': grandTotal,
            'financial_year': _getCalculatedFY(pDate),
          }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
          importedPurchases++;

          await txn.delete('purchase_items', where: 'entry_no = ?', whereArgs: [entryNo]);

          for (var r in rows) {
            String prodName = r['product'].toString().trim();
            if (prodName.isEmpty) continue;

            var profile = nameToProfile[prodName.toLowerCase()];
            String prodId = profile != null ? profile['id'].toString() : "";

            if (prodId.isEmpty) {
              prodId = generate10DigitId();
              await txn.insert('product_master', {
                'id': prodId,
                'name': prodName,
                'packing': r['packing'] ?? 1,
                'is_active': 1,
              }, conflictAlgorithm: sql.ConflictAlgorithm.ignore);
              profile = {
                'id': prodId,
                'name': prodName,
                'rack_id': '',
                'hsn_code': '',
                's_disc_percent': 0.0
              };
              nameToProfile[prodName.toLowerCase()] = profile;
            }

            final double pRate = (r['p_rate'] as num?)?.toDouble() ?? 0.0;
            final int qty = (r['qty'] as num?)?.toInt() ?? 0;
            final int fQty = (r['f_qty'] as num?)?.toInt() ?? 0;
            final int packing = (r['packing'] as num?)?.toInt() ?? 1;
            final double discPerc = (r['disc_perc'] as num?)?.toDouble() ?? 0.0;
            final double gross = pRate * qty;
            final double discAmt = (gross * discPerc) / 100;
            final double net = gross - discAmt;
            final double gstPerc = (r['gst_perc'] as num?)?.toDouble() ?? 0.0;
            final double gstAmt = (net * gstPerc) / 100;
            final double total = net + gstAmt;
            
            double trueLandingCost = (qty + fQty) > 0 ? (total / (qty + fQty)) : pRate;

            final double mrp = (r['mrp'] as num?)?.toDouble() ?? 0.0;
            final double sDiscPercent = (profile?['s_disc_percent'] as num?)?.toDouble() ?? 0.0;
            final double sRate = mrp - (mrp * sDiscPercent / 100);

            // Update purchase_items with clean batch
            await txn.insert('purchase_items', {
              'entry_no': entryNo,
              'product_id': prodId,
              'product_name': prodName,
              'batch': r['batch'].toString().trim(),
              'expiry': r['expiry'],
              'qty': qty,
              'f_qty': fQty,
              'mrp': mrp,
              'p_rate': pRate,
              'gross': gross,
              'disc_percent': discPerc,
              'disc_amt': discAmt,
              'net': net,
              'gst_percent': gstPerc,
              'gst_amt': gstAmt,
              'total': total,
              'packin': packing,
              'l_cost': trueLandingCost,
              'rack': profile?['rack_id'] ?? "",
              'hsn_code': profile?['hsn_code'] ?? "",
              's_disc_percent': sDiscPercent,
              's_rate': sRate,
            });

            importedItems++;
          }
          if (currentP % 50 == 0) await Future.delayed(const Duration(milliseconds: 10));
        }
      });

      await loadFromDatabase();
      await syncVoucherSequences();
      
      final Set<String> importedYears = {};
      for (var group in purchaseGroups.values) {
         if (group.isNotEmpty) importedYears.add(_getCalculatedFY(group.first['date']));
      }

      return {
        'success': true, 
        'purchases': importedPurchases, 
        'items': importedItems,
        'years': importedYears.toList(),
        'currentFY': _selectedFinancialYear,
      };
    } catch (e) {
      return {'success': false, 'message': 'Purchase import failed: $e'};
    }
  }

  Future<Map<String, dynamic>> importSalesReturnsFromExcel(String filePath, {Function(double, String)? onProgress, Map<String, int>? customMapping}) async {
    return importReturnsFromExcel(filePath, onProgress: onProgress, customMapping: customMapping, forceSales: true);
  }

  Future<Map<String, dynamic>> importPurchaseReturnsFromExcel(String filePath, {Function(double, String)? onProgress, Map<String, int>? customMapping}) async {
    return importReturnsFromExcel(filePath, onProgress: onProgress, customMapping: customMapping, forcePurchase: true);
  }

  Future<Map<String, dynamic>> importReturnsFromExcel(
    String filePath, {
    Function(double, String)? onProgress,
    Map<String, int>? customMapping,
    bool forceSales = false,
    bool forcePurchase = false,
    String? financialYear,
  }) async {
    final validation = await validateAndImportFile(filePath);
    if (!validation['success']) return validation;

    try {
      onProgress?.call(0.05, "Reading file in background isolate...");

      final rawRows = await ExcelWorkerService.parseExcelRawRowsInBackground(filePath);
      if (rawRows.length <= 1) {
        return {'success': false, 'message': 'No data rows found in file.'};
      }

      final db = await DbHelper.instance.database;

      int importedReturns = 0;
      int importedItems = 0;
      Map<String, List<Map<String, dynamic>>> allGroups = {};

      int headerRowIdx = 0;
      for (int r = 0; r < rawRows.length && r < 6; r++) {
        final line = rawRows[r].map((e) => e.toLowerCase().trim()).join(' ');
        if (line.contains('entry no') || line.contains('return') || line.contains('product') || line.contains('date') || line.contains('customer') || line.contains('supplier')) {
          headerRowIdx = r;
          break;
        }
      }

      bool isSalesReturn = forceSales ? true : (forcePurchase ? false : true);
      final header = rawRows[headerRowIdx].map((e) => e.toLowerCase().trim()).toList();

      int idxEntryNo = customMapping?['entry_no'] ?? _findIdx(header, ['entry no', 'return no', 'entry']);
      int idxDate = customMapping?['date'] ?? _findIdx(header, ['date', 'bill date', 'inv date', 'entry date', 'return date', 'sales return date', 'purchase return date', 'invoice date', 'trans date', 'txn date', 'dated', 'dt', 'created at', 'creation date']);
      int idxAcc = customMapping?['customer'] ?? customMapping?['supplier'] ?? _findIdx(header, ['customer', 'supplier', 'acc']);
      int idxRef = customMapping?['ref_invoice'] ?? _findIdx(header, ['ref invoice', 'ref purchase', 'original invoice']);
      int idxProduct = customMapping?['product'] ?? _findIdx(header, ['product', 'item', 'name']);
      int idxPack = customMapping?['packing'] ?? _findIdx(header, ['pack', 'packing', 'pck']);
      int idxBatch = customMapping?['batch'] ?? _findIdx(header, ['batch']);
      int idxQty = customMapping?['qty'] ?? _findIdx(header, ['qty', 'quantity']);
      int idxTotal = customMapping?['grand_total'] ?? _findIdx(header, ['total', 'grand total', 'amount']);
      int idxItemTotal = customMapping?['net'] ?? _findIdx(header, ['item total', 'net total', 'total amount']);
      int idxDiscAmt = customMapping != null ? (customMapping['disc_amt'] ?? -1) : _findIdx(header, ['discount', 'disc amt', 'disc amount']);
      int idxDiscPer = customMapping != null ? (customMapping['disc_perc'] ?? -1) : _findIdx(header, ['dis%', 'disc %', 'discount %']);
      int idxGstPer = customMapping != null ? (customMapping['gst_perc'] ?? -1) : _findIdx(header, ['gst%', 'tax%', 'gst percent']);
      int idxGstAmt = customMapping != null ? (customMapping['gst_amt'] ?? -1) : _findIdx(header, ['gst amt', 'tax amt', 'gst amount']);
      int idxTime = _findIdx(header, ['time']);

      String valRow(List<String> row, int idx) {
        if (idx < 0 || idx >= row.length) return "";
        return row[idx].trim();
      }

      int totalRows = rawRows.length - (headerRowIdx + 1);
      _cancelImport = false;

      for (int i = headerRowIdx + 1; i < rawRows.length; i++) {
        if (_cancelImport) {
          return {'success': false, 'message': 'Returns import cancelled by user.'};
        }
        final row = rawRows[i];
        if (row.isEmpty) continue;
        if (onProgress != null && i % 100 == 0) onProgress(i / totalRows * 0.4, "Reading Row $i");

        String entryNo = valRow(row, idxEntryNo);
        if (double.tryParse(entryNo) != null) {
          entryNo = double.parse(entryNo).toInt().toString();
        }
        if (entryNo.isEmpty) continue;

        double itemTotal = _parse(valRow(row, idxItemTotal).isNotEmpty ? valRow(row, idxItemTotal) : valRow(row, idxTotal));
        double discAmt = _parse(valRow(row, idxDiscAmt));
        double discPer = _parse(valRow(row, idxDiscPer));
        double gstAmt = _parse(valRow(row, idxGstAmt));
        double gstPer = TaxCalculator.roundGstPercent(_parse(valRow(row, idxGstPer)));

        if (idxTime == -1) {
          if (gstAmt == 0 && gstPer > 0) {
            gstAmt = itemTotal - (itemTotal / (1 + (gstPer / 100)));
          } else if (gstPer == 0 && gstAmt > 0 && (itemTotal - gstAmt) > 0) {
            gstPer = TaxCalculator.roundGstPercent((gstAmt / (itemTotal - gstAmt)) * 100);
          }

          double net = itemTotal - gstAmt;
          if (discAmt == 0 && discPer > 0 && discPer < 100) {
            double gross = net / (1 - (discPer / 100));
            discAmt = gross - net;
          } else if (discPer == 0 && discAmt > 0) {
            double gross = net + discAmt;
            if (gross > 0) {
              discPer = (discAmt / gross) * 100;
            }
          }
        }

        allGroups.putIfAbsent(entryNo, () => []).add({
          'date': _parseExcelDate(valRow(row, idxDate)),
          'acc': valRow(row, idxAcc),
          'ref': valRow(row, idxRef),
          'product': valRow(row, idxProduct),
          'packing': valRow(row, idxPack),
          'batch': valRow(row, idxBatch),
          'qty': _parse(valRow(row, idxQty)).toInt(),
          'total': itemTotal,
          'disc_amt': discAmt,
          'gst_amt': gstAmt,
          'grand_total': _parse(valRow(row, idxTotal)),
          'isSales': isSalesReturn,
        });
      }

      final List<Map<String, dynamic>> allProds = await db.query('product_master', columns: ['id', 'name']);
      final Map<String, String> nameToId = {
        for (var p in allProds) p['name'].toString().toLowerCase().trim(): p['id'].toString()
      };

      final Set<String> targetFys = {};
      if (financialYear != null && financialYear != 'All Years' && financialYear.isNotEmpty) {
        targetFys.add(financialYear);
      } else {
        for (var entry in allGroups.entries) {
          if (entry.value.isNotEmpty) {
            DateTime dt = entry.value.first['date'];
            targetFys.add(_getCalculatedFY(dt));
          }
        }
      }

      if (onProgress != null) onProgress(0.35, "Clearing old returns data for target financial year(s)...");
      if (targetFys.isNotEmpty) {
        for (var fy in targetFys) {
          if (forceSales || !forcePurchase) {
            final invs = await db.query('sales_return_invoices', where: 'financial_year = ?', whereArgs: [fy], columns: ['entry_no']);
            for (var inv in invs) {
              await db.delete('sales_return_items', where: 'return_no = ?', whereArgs: [inv['entry_no'].toString()]);
            }
            await db.delete('sales_return_invoices', where: 'financial_year = ?', whereArgs: [fy]);
          }
          if (forcePurchase || !forceSales) {
            final entries = await db.query('purchase_return_entries', where: 'financial_year = ?', whereArgs: [fy], columns: ['entry_no']);
            for (var e in entries) {
              await db.delete('purchase_return_items', where: 'return_no = ?', whereArgs: [e['entry_no'].toString()]);
            }
            await db.delete('purchase_return_entries', where: 'financial_year = ?', whereArgs: [fy]);
          }
        }
      } else {
        if (forceSales) {
          await db.delete('sales_return_items');
          await db.delete('sales_return_invoices');
        } else if (forcePurchase) {
          await db.delete('purchase_return_items');
          await db.delete('purchase_return_entries');
        } else {
          await db.delete('sales_return_items');
          await db.delete('sales_return_invoices');
          await db.delete('purchase_return_items');
          await db.delete('purchase_return_entries');
        }
      }

      await db.transaction((txn) async {
        int totalGroups = allGroups.length;
        int currentG = 0;
        for (var entry in allGroups.entries) {
          currentG++;
          if (onProgress != null) onProgress(0.4 + (currentG / totalGroups * 0.6), "Importing Return $currentG");
          
          String entryNo = entry.key;
          var gRows = entry.value;
          bool isSalesReturn = gRows.first['isSales'];
          double grandTotal = gRows.fold(0.0, (sum, r) => sum + r['total']);

          if (isSalesReturn) {
            double totalDiscAmt = gRows.fold(0.0, (sum, r) => sum + (r['disc_amt'] ?? 0.0));
            double totalGstAmt = gRows.fold(0.0, (sum, r) => sum + (r['gst_amt'] ?? 0.0));

            // Ensure imported returns have original invoice linkage and are tagged:
            await txn.insert('sales_return_invoices', {
              'entry_no': entryNo,
              'date': gRows.first['date'].toIso8601String(),
              'customer_acc': gRows.first['acc'],
              'patient': gRows.first['acc'],
              'original_invoice_no': gRows.first['ref'],
              'discount': totalDiscAmt,
              'tax': totalGstAmt,
              'grand_total': grandTotal,
              'financial_year': _getCalculatedFY(gRows.first['date']),
              'is_deleted': 0,
              'is_imported': 1,
            }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
            
            await txn.delete('sales_return_items', where: 'return_no = ?', whereArgs: [entryNo]);
            for (var r in gRows) {
              String prodId = nameToId[r['product'].toString().toLowerCase()] ?? "";
              await txn.insert('sales_return_items', {
                'return_no': entryNo,
                'product_id': prodId,
                'product_name': r['product'],
                'batch_number': r['batch'],
                'quantity': r['qty'],
                'total': r['total'],
              });
              
              // DATA SYNC RULE: History imports do NOT affect live stock
              /*
              if (prodId.isNotEmpty) {
                int packing = (r['packing'] as num?)?.toInt() ?? 1;
                int totalQty = (r['qty'] as num).toInt() * packing;
                await txn.rawUpdate('UPDATE stock_batches SET current_stock = current_stock + ? WHERE product_id = ? AND batch_number = ?', 
                  [totalQty, prodId, r['batch']]);
              }
              */
              importedItems++;
            }
          } else {
            await txn.insert('purchase_return_entries', {
              'entry_no': entryNo,
              'date': gRows.first['date'].toIso8601String(),
              'supplier_name': gRows.first['acc'],
              'original_purchase_no': gRows.first['ref'],
              'grand_total': grandTotal,
              'financial_year': _getCalculatedFY(gRows.first['date']),
              'is_imported': 1,
            }, conflictAlgorithm: sql.ConflictAlgorithm.replace);
            
            await txn.delete('purchase_return_items', where: 'entry_no = ?', whereArgs: [entryNo]);
            for (var r in gRows) {
              await txn.insert('purchase_return_items', {
                'entry_no': entryNo, // Correct column name
                'product_name': r['product'],
                'batch': r['batch'],
                'qty': r['qty'],
                'total': r['total'],
              });

              // DATA SYNC RULE: History imports do NOT affect live stock
              /*
              if (prodId.isNotEmpty) {
                int packing = (r['packing'] as num?)?.toInt() ?? 1;
                int totalQty = (r['qty'] as num).toInt() * packing;
                await txn.rawUpdate('UPDATE stock_batches SET current_stock = current_stock - ? WHERE product_id = ? AND batch_number = ?', 
                  [totalQty, prodId, r['batch']]);
              }
              */
              importedItems++;
            }
          }
          importedReturns++;
          if (currentG % 50 == 0) await Future.delayed(const Duration(milliseconds: 10));
        }
      });

      await loadFromDatabase();
      
      final Set<String> importedYears = {};
      for (var group in allGroups.values) {
        if (group.isNotEmpty) importedYears.add(_getCalculatedFY(group.first['date']));
      }

      return {
        'success': true, 
        'returns': importedReturns, 
        'items': importedItems,
        'years': importedYears.toList(),
        'currentFY': _selectedFinancialYear,
      };
    } catch (e) {
      return {'success': false, 'message': 'Returns import failed: $e'};
    }
  }

  Future<Map<String, dynamic>> importDamageFromExcel(
    String filePath, {
    Function(double, String)? onProgress,
    Map<String, int>? customMapping,
    String? financialYear,
  }) async {
    final validation = await validateAndImportFile(filePath);
    if (!validation['success']) return validation;

    try {
      onProgress?.call(0.05, "Reading file in background isolate...");

      final rawRows = await ExcelWorkerService.parseExcelRawRowsInBackground(filePath);
      if (rawRows.length <= 1) {
        return {'success': false, 'message': 'No data rows found in file.'};
      }

      final db = await DbHelper.instance.database;

      if (financialYear != null && financialYear != 'All Years' && financialYear.isNotEmpty) {
        if (onProgress != null) onProgress(0.1, "Clearing old damage data for $financialYear...");
        await db.delete('stock_write_offs', where: 'financial_year = ?', whereArgs: [financialYear]);
      } else {
        if (onProgress != null) onProgress(0.1, "Clearing old damage data...");
        await db.delete('stock_write_offs');
      }

      int importedCount = 0;

      int headerRowIdx = 0;
      for (int r = 0; r < rawRows.length && r < 6; r++) {
        final line = rawRows[r].map((e) => e.toLowerCase().trim()).join(' ');
        if (line.contains('id') || line.contains('product') || line.contains('date') || line.contains('reason') || line.contains('batch')) {
          headerRowIdx = r;
          break;
        }
      }

      final header = rawRows[headerRowIdx].map((e) => e.toLowerCase().trim()).toList();

      int idxId = customMapping?['id'] ?? _findIdx(header, ['id', 'log id']);
      int idxDate = customMapping?['date'] ?? _findIdx(header, ['date', 'write off date', 'damage date', 'entry date', 'trans date', 'dated', 'dt', 'created at', 'creation date']);
      int idxProduct = customMapping?['product'] ?? _findIdx(header, ['product', 'item']);
      int idxBatch = customMapping?['batch'] ?? _findIdx(header, ['batch']);
      int idxQty = customMapping?['qty'] ?? _findIdx(header, ['quantity', 'qty']);
      int idxReason = customMapping?['reason'] ?? _findIdx(header, ['reason']);
      int idxLoss = customMapping?['loss_value'] ?? _findIdx(header, ['loss value', 'loss', 'amount']);

      String valRow(List<String> row, int idx) {
        if (idx < 0 || idx >= row.length) return "";
        return row[idx].trim();
      }

      final List<Map<String, dynamic>> allProds = await db.query('product_master', columns: ['id', 'name']);
      final Map<String, String> nameToId = {
        for (var p in allProds) p['name'].toString().toLowerCase().trim(): p['id'].toString()
      };

      final Set<String> importedYears = {};

      await db.transaction((txn) async {
        int totalRows = rawRows.length - (headerRowIdx + 1);
        for (int i = headerRowIdx + 1; i < rawRows.length; i++) {
          final row = rawRows[i];
          if (row.isEmpty) continue;
          if (onProgress != null && i % 100 == 0) {
            onProgress(i / totalRows, "Importing Damage Log $i of $totalRows");
          }

          String prodName = valRow(row, idxProduct);
          String prodId = nameToId[prodName.toLowerCase()] ?? "";
          String batchNum = valRow(row, idxBatch);
          int qty = _parse(valRow(row, idxQty)).toInt();
          DateTime woDate = _parseExcelDate(valRow(row, idxDate));
          String fy = _getCalculatedFY(woDate);
          importedYears.add(fy);

          await txn.insert('stock_write_offs', {
            'id': valRow(row, idxId).isNotEmpty ? valRow(row, idxId) : "DMG_${DateTime.now().millisecondsSinceEpoch}_$i",
            'date': woDate.toIso8601String(),
            'product_id': prodId,
            'batch_number': batchNum,
            'quantity': qty,
            'reason': valRow(row, idxReason),
            'loss_value': _parse(valRow(row, idxLoss)),
            'financial_year': fy,
          }, conflictAlgorithm: sql.ConflictAlgorithm.replace);

          importedCount++;
          if (i % 100 == 0) await Future.delayed(const Duration(milliseconds: 10));
        }
      });

      await loadFromDatabase();

      return {
        'success': true, 
        'count': importedCount,
        'years': importedYears.toList(),
        'currentFY': _selectedFinancialYear,
      };
    } catch (e) {
      return {'success': false, 'message': 'Damage import failed: $e'};
    }
  }

  DateTime _parseExcelDate(String rawDate) {
    if (rawDate.isEmpty) return DateTime.now();
    String cleaned = rawDate.trim();
    if (cleaned.isEmpty) return DateTime.now();

    // 0. Handle key-value named date strings (e.g. "year: 2026, month: 3, day: 15, hour: 10, minute: 30")
    if (cleaned.contains('year:') && cleaned.contains('month:') && cleaned.contains('day:')) {
      try {
        int? y, m, d, h = 0, min = 0, sec = 0;
        final matchY = RegExp(r'year:\s*(\d+)').firstMatch(cleaned);
        final matchM = RegExp(r'month:\s*(\d+)').firstMatch(cleaned);
        final matchD = RegExp(r'day:\s*(\d+)').firstMatch(cleaned);
        final matchH = RegExp(r'hour:\s*(\d+)').firstMatch(cleaned);
        final matchMin = RegExp(r'minute:\s*(\d+)').firstMatch(cleaned);
        final matchSec = RegExp(r'second:\s*(\d+)').firstMatch(cleaned);

        if (matchY != null) y = int.tryParse(matchY.group(1)!);
        if (matchM != null) m = int.tryParse(matchM.group(1)!);
        if (matchD != null) d = int.tryParse(matchD.group(1)!);
        if (matchH != null) h = int.tryParse(matchH.group(1)!);
        if (matchMin != null) min = int.tryParse(matchMin.group(1)!);
        if (matchSec != null) sec = int.tryParse(matchSec.group(1)!);

        if (y != null && m != null && d != null && y >= 1990 && y <= 2100 && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
          return DateTime(y, m, d, h ?? 0, min ?? 0, sec ?? 0);
        }
      } catch (_) {}
    }

    // 1. Direct ISO 8601 strings (e.g. "2026-09-06T14:30:00" or "2026-09-06 14:30:00")
    try {
      final direct = DateTime.tryParse(cleaned);
      if (direct != null && direct.year >= 1990 && direct.year <= 2100) {
        return direct;
      }
    } catch (_) {}

    // 2. Excel Serial Numbers (e.g., 45541 or 45541.625)
    final doubleVal = double.tryParse(cleaned.replaceAll(',', ''));
    if (doubleVal != null && doubleVal > 1000 && doubleVal < 100000) {
      int days = doubleVal.floor();
      double fraction = doubleVal - days;
      DateTime baseDate = DateTime(1899, 12, 30).add(Duration(days: days));
      int totalMillis = (fraction * 86400000).round();
      return baseDate.add(Duration(milliseconds: totalMillis));
    }

    // 3. Separate date part and time part if timestamp is included (e.g., "06/09/2026 02:30:00 PM" or "2026-09-06 14:30")
    String datePart = cleaned;
    String timePart = "";
    if (cleaned.contains(' ')) {
      final spaceIdx = cleaned.indexOf(' ');
      datePart = cleaned.substring(0, spaceIdx).trim();
      timePart = cleaned.substring(spaceIdx + 1).trim();
    }

    const monthNames = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
      'january': 1, 'february': 2, 'march': 3, 'april': 4, 'june': 6,
      'july': 7, 'august': 8, 'september': 9, 'october': 10, 'november': 11, 'december': 12
    };

    int year = DateTime.now().year;
    int month = DateTime.now().month;
    int day = DateTime.now().day;
    bool dateParsed = false;

    for (String sep in ['/', '-', '.', ' ']) {
      if (datePart.contains(sep)) {
        final pts = datePart.split(sep).where((p) => p.trim().isNotEmpty).toList();
        if (pts.length == 3) {
          String p1Str = pts[0].trim().toLowerCase();
          String p2Str = pts[1].trim().toLowerCase();
          String p3Str = pts[2].trim().toLowerCase();

          int? p1 = int.tryParse(p1Str) ?? monthNames[p1Str];
          int? p2 = int.tryParse(p2Str) ?? monthNames[p2Str];
          int? p3 = int.tryParse(p3Str) ?? monthNames[p3Str];

          if (p1 != null && p2 != null && p3 != null) {
            if (p1 > 31) {
              // YYYY-MM-DD format
              year = p1;
              month = p2;
              day = p3;
            } else if (p3 > 31 || p3Str.length == 4) {
              // DD/MM/YYYY or MM/DD/YYYY
              year = p3;
              if (p1 > 12) {
                day = p1;
                month = p2;
              } else if (p2 > 12) {
                month = p1;
                day = p2;
              } else {
                day = p1;
                month = p2;
              }
            } else {
              // 2-digit year format (e.g. 06/09/26)
              year = p3 < 100 ? 2000 + p3 : p3;
              if (p1 > 12) {
                day = p1;
                month = p2;
              } else if (p2 > 12) {
                month = p1;
                day = p2;
              } else {
                day = p1;
                month = p2;
              }
            }

            if (year >= 1990 && year <= 2100 && month >= 1 && month <= 12 && day >= 1 && day <= 31) {
              dateParsed = true;
              break;
            }
          }
        }
      }
    }

    if (!dateParsed) {
      final fallback = DateTime.tryParse(datePart);
      if (fallback != null) {
        year = fallback.year;
        month = fallback.month;
        day = fallback.day;
        dateParsed = true;
      }
    }

    if (!dateParsed) return DateTime.now();

    // Parse time part if available
    int hour = 0;
    int minute = 0;
    int second = 0;

    if (timePart.isNotEmpty) {
      try {
        final timeClean = timePart.toUpperCase();
        bool isPm = timeClean.contains('PM');
        bool isAm = timeClean.contains('AM');
        final digitsOnlyTime = timeClean.replaceAll(RegExp(r'[^0-9:]'), '').trim();
        final timeParts = digitsOnlyTime.split(':');

        if (timeParts.isNotEmpty) {
          hour = int.tryParse(timeParts[0]) ?? 0;
          if (timeParts.length > 1) minute = int.tryParse(timeParts[1]) ?? 0;
          if (timeParts.length > 2) second = int.tryParse(timeParts[2]) ?? 0;

          if (isPm && hour < 12) hour += 12;
          if (isAm && hour == 12) hour = 0;
        }
      } catch (_) {}
    }

    return DateTime(year, month, day, hour, minute, second);
  }




  Future<void> _loadImportMappings() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/import_mappings.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> json = jsonDecode(content);
        _importMappings.clear();
        for (var m in json) {
          final mapping = ImportMapping.fromJson(m);
          // Auto-migration: Remove HSN from Product Code (causes collisions)
          if (mapping.fieldMappings.containsKey('Product Code')) {
            mapping.fieldMappings['Product Code']!.removeWhere((k) => k.toLowerCase() == 'hsn' || k.toLowerCase() == 'hsn code');
          }
          // Ensure HSN field exists
          if (!mapping.fieldMappings.containsKey('HSN')) {
            mapping.fieldMappings['HSN'] = ['hsn', 'hsn code', 'hsn_code', 'hsncode'];
          }
          _importMappings.add(mapping);
        }
      } else {
        // Add some default mappings
        _importMappings.add(ImportMapping.defaultMapping());
        await _saveImportMappings();

      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error loading import mappings: $e");

    }

  }

  Future<void> _saveImportMappings() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/import_mappings.json');
      final String json = jsonEncode(_importMappings.map((m) => m.toJson()).toList());
      await file.writeAsString(json);
    } catch (e) {
      debugPrint("Error saving import mappings: $e");
    }
  }

  Future<void> saveMappingProfile(String name, Map<String, int> mapping, List<String> headers) async {
    // Convert current UI mapping (Field -> Index) to Profile mapping (Field -> Header Names)
    Map<String, List<String>> fieldMappings = {};
    mapping.forEach((field, index) {
      if (index < headers.length) {
        fieldMappings[field] = [headers[index]];
      }
    });

    final newMapping = ImportMapping(name: name, fieldMappings: fieldMappings);
    
    // Remove if exists with same name
    _importMappings.removeWhere((m) => m.name == name);
    _importMappings.add(newMapping);
    
    await _saveImportMappings();
    notifyListeners();
  }

  Future<void> deleteMappingProfile(String name) async {
    _importMappings.removeWhere((m) => m.name == name);
    await _saveImportMappings();
    notifyListeners();
  }

  Future<void> addImportMapping(ImportMapping mapping) async {
    _importMappings.add(mapping);

    // Save the format to local storage (using existing file-based persistence)
    await _saveImportMappings();

    notifyListeners();

  }

  Future<void> updateImportMapping(int index, ImportMapping mapping) async {
    if (index >= 0 && index < _importMappings.length) {
      _importMappings[index] = mapping;
      await _saveImportMappings();
      notifyListeners();

    }

  }

  Future<void> deleteImportMapping(int index) async {
    if (index >= 0 && index < _importMappings.length) {
      _importMappings.removeAt(index);
      await _saveImportMappings();
      notifyListeners();

    }

  }

  bool _isHsnCode(String code, [String? rawHsn]) {
    String clean = code.trim();
    if (clean.isEmpty) return false;
    if (rawHsn != null && rawHsn.trim().isNotEmpty && clean == rawHsn.trim()) return true;
    return RegExp(r'^(3001|3002|3003|3004|3005|3006|3004\d{2,4}|\d{4,8})$').hasMatch(clean);
  }

  Future<void> _loadProductMappings() async {
    try {
      final db = await DbHelper.instance.database;
      // Clean up any corrupted empty or non-product header mappings from SQLite DB
      await db.delete(
        'ProductMappings',
        where: "TRIM(IFNULL(external_name, '')) = '' AND TRIM(IFNULL(external_code, '')) = '' OR LOWER(external_name) LIKE '%sahakar%' OR LOWER(external_name) LIKE '%customer%' OR LOWER(external_name) LIKE '%grand total%' OR LOWER(external_name) LIKE '%sub total%'",
      );

      // Clean up any HSN codes saved as external_code to prevent catastrophic cross-item matching
      await db.rawUpdate(
        "UPDATE ProductMappings SET external_code = '' WHERE external_code = '30049099' OR (external_code GLOB '[0-9][0-9][0-9][0-9]*' AND LENGTH(external_code) BETWEEN 4 AND 8)",
      );

      final List<Map<String, dynamic>> maps = await db.query('ProductMappings');
      _productMappings.clear();
      _productMappings.addAll(
        maps
            .map((m) => ProductMapping.fromMap(m))
            .where((m) => m.externalName.trim().isNotEmpty || m.externalCode.trim().isNotEmpty),
      );
      await syncGenericNamesFromMappingsAndGenerics();
    } catch (e) {
      debugPrint("Error loading product mappings: $e");
    }
  }

  Future<void> saveProductMapping(ProductMapping mapping) async {
    if (mapping.externalName.trim().isEmpty && mapping.externalCode.trim().isEmpty) {
      debugPrint("Skipping save of invalid ProductMapping with empty externalName and externalCode");
      return;
    }

    try {
      final db = await DbHelper.instance.database;

      // Insert into SQLite so it remembers the unknown product forever
      await db.insert(
        'ProductMappings',
        mapping.toMap(),
        conflictAlgorithm: sql.ConflictAlgorithm.replace,
      );

      _productMappings.removeWhere((m) =>
          m.wholesalerName == mapping.wholesalerName &&
          m.externalName.trim() == mapping.externalName.trim() &&
          m.externalCode.trim() == mapping.externalCode.trim());
      _productMappings.add(mapping);
      notifyListeners();
    } catch (e) {
      debugPrint("Error saving product mapping: $e");
    }
  }

  String _normalizeMappingString(String s) {
    return s.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  ProductMapping? findProductMapping(String wholesaler, String externalName, [String externalCode = ""]) {
    if (externalName.trim().isEmpty && externalCode.trim().isEmpty) return null;

    String cleanWholesaler = wholesaler
        .replaceAll(' - PDF', '')
        .replaceAll(' - EXCEL', '')
        .trim()
        .toUpperCase();
    String cleanExternal = _normalizeMappingString(externalName);
    String cleanCode = externalCode.trim().toUpperCase();

    // 1. Primary pass: Match by Name FIRST
    if (cleanExternal.isNotEmpty) {
      for (var m in _productMappings) {
        String mWholesaler = m.wholesalerName
            .replaceAll(' - PDF', '')
            .replaceAll(' - EXCEL', '')
            .trim()
            .toUpperCase();

        bool wholesalerMatches = mWholesaler == cleanWholesaler ||
            mWholesaler.isEmpty ||
            cleanWholesaler == "GENERAL" ||
            cleanWholesaler == "DEFAULT" ||
            cleanWholesaler.isEmpty;

        if (!wholesalerMatches) continue;

        if (_normalizeMappingString(m.externalName) == cleanExternal) {
          return m;
        }
      }
    }

    // 2. Secondary pass: Match by Code (ONLY if cleanCode is non-empty and NOT an HSN code)
    if (cleanCode.isNotEmpty && !_isHsnCode(cleanCode)) {
      for (var m in _productMappings) {
        String mWholesaler = m.wholesalerName
            .replaceAll(' - PDF', '')
            .replaceAll(' - EXCEL', '')
            .trim()
            .toUpperCase();

        bool wholesalerMatches = mWholesaler == cleanWholesaler ||
            mWholesaler.isEmpty ||
            cleanWholesaler == "GENERAL" ||
            cleanWholesaler == "DEFAULT" ||
            cleanWholesaler.isEmpty;

        if (!wholesalerMatches) continue;

        if (m.externalCode.trim().toUpperCase() == cleanCode) {
          String mExtNorm = _normalizeMappingString(m.externalName);
          if (cleanExternal.isEmpty || mExtNorm.isEmpty || mExtNorm == cleanExternal) {
            return m;
          }
        }
      }
    }

    // 3. Tertiary pass: Alphanumeric fuzzy fallback on externalName
    String normAlpha(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    String alphaExternal = normAlpha(externalName);

    if (alphaExternal.length >= 3) {
      for (var m in _productMappings) {
        String mWholesaler = m.wholesalerName
            .replaceAll(' - PDF', '')
            .replaceAll(' - EXCEL', '')
            .trim()
            .toUpperCase();

        bool wholesalerMatches = mWholesaler == cleanWholesaler ||
            mWholesaler.isEmpty ||
            cleanWholesaler == "GENERAL" ||
            cleanWholesaler == "DEFAULT" ||
            cleanWholesaler.isEmpty;

        if (!wholesalerMatches) continue;

        if (normAlpha(m.externalName) == alphaExternal) {
          return m;
        }
      }
    }

    return null;
  }

  String? getMappedProduct(String wholesaler, String externalName, [String externalCode = ""]) {
    final mapping = findProductMapping(wholesaler, externalName, externalCode);
    if (mapping == null) return null;
    return mapping.internalName.trim().isNotEmpty ? mapping.internalName.trim() : null;
  }

  Future<void> deleteProductMapping(int? id, String wholesaler, String externalName, String externalCode) async {
    try {
      final db = await DbHelper.instance.database;
      if (id != null) {
        await db.delete('ProductMappings', where: 'id = ?', whereArgs: [id]);
      } else {
        await db.delete('ProductMappings',
            where: 'wholesaler_name = ? AND external_name = ? AND external_code = ?',
            whereArgs: [wholesaler, externalName, externalCode]);
      }
      _productMappings.removeWhere((m) =>
      (id != null && m.id == id) ||
          (m.wholesalerName == wholesaler && m.externalName == externalName && m.externalCode == externalCode)
      );
      notifyListeners();
    } catch (e) {
      debugPrint("Error deleting product mapping: $e");
    }
  }

  // ==========================================================
  // ⚡ LIGHTNING FAST FILE PARSING (BACKGROUND ISOLATES)
  // ==========================================================

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

  Future<List<PurchaseItem>> importPurchaseExcel(String filePath, {required ImportMapping mapping}) async {
    final validation = await validateAndImportFile(filePath);
    if (!validation['success']) {
      // Since this returns List, we could throw or return empty. 
      // Existing code uses try-catch, so we'll return empty list but log/debug message
      debugPrint("Import Validation Failed: ${validation['message']}");
      return [];
    }

    List<PurchaseItem> items = [];

    try {
      final file = File(filePath);
      List<List<dynamic>> rawRows = [];
      List<String> headers = [];

      String extension = filePath.split('.').last.toLowerCase();

      if (extension == 'xls') {
        final raf = await file.open();
        final startBytes = await raf.read(512);
        await raf.close();

        bool isBiff2 = startBytes.length >= 2 && startBytes[0] == 0x09 && startBytes[1] == 0x00;
        bool isBiff8 = startBytes.length >= 8 && startBytes[0] == 0xD0 && startBytes[1] == 0xCF && startBytes[2] == 0x11 && startBytes[3] == 0xE0;

        final bytes = await file.readAsBytes();

        if (isBiff2) {
          rawRows = await compute(_parseBiff2Isolate, bytes);
        } else if (isBiff8) {
          try {
            rawRows = await compute(_parseXlsxIsolate, bytes);
          } catch (_) {
            try {
              rawRows = await compute(_parseBiff2Isolate, bytes);
            } catch (_) {
              rawRows = await compute(_parseDisguisedXlsIsolate, bytes);
            }
          }
        } else {
          rawRows = await compute(_parseDisguisedXlsIsolate, bytes);
        }
      } else if (extension == 'xlsx') {
        final bytes = await file.readAsBytes();
        rawRows = await compute(_parseXlsxIsolate, bytes);
      } else if (extension == 'csv' || extension == 'txt') {
        rawRows = await compute(_parseCsvIsolate, filePath);
      }

      if (rawRows.isEmpty) return [];

      // Auto-scan first 10 rows to locate actual table header row
      int headerRowIdx = 0;
      for (int i = 0; i < rawRows.length && i < 10; i++) {
        final rowStr = rawRows[i].map((e) => e?.toString().toLowerCase().trim() ?? "").toList();
        if (rowStr.any((c) => c.contains('item') || c.contains('product') || c.contains('c2code') || c.contains('particulars') || c.contains('desc') || c.contains('batch'))) {
          headerRowIdx = i;
          break;
        }
      }

      headers = rawRows[headerRowIdx].map((e) => e?.toString().trim() ?? "").toList();
      rawRows = rawRows.sublist(headerRowIdx + 1);

      // ==========================================================
      // 2. ZERO-LATENCY IN-MEMORY LOOKUPS (Case-Insensitive & Normalized)
      // ==========================================================
      String cleanWholesalerName = mapping.name.replaceAll(' - PDF', '').replaceAll(' - EXCEL', '').trim().toUpperCase();

      // THE FIX: Load mappings for THIS wholesaler AND global fallbacks (blank wholesaler)
      final relevantMappings = _productMappings.where((m) {
        String baseName = m.wholesalerName.replaceAll(' - PDF', '').replaceAll(' - EXCEL', '').trim().toUpperCase();
        return baseName == cleanWholesalerName || baseName.isEmpty;
      }).toList();

      final codeToMappingMap = <String, ProductMapping>{};
      final nameToMappingMap = <String, ProductMapping>{};

      for (var m in relevantMappings) {
        if (m.externalCode.trim().isNotEmpty) {
          // Prefer specific wholesaler over blank if both exist
          if (!codeToMappingMap.containsKey(m.externalCode.trim().toUpperCase()) || m.wholesalerName.isNotEmpty) {
            codeToMappingMap[m.externalCode.trim().toUpperCase()] = m;
          }
        }
        if (m.externalName.trim().isNotEmpty) {
          if (!nameToMappingMap.containsKey(m.externalName.trim().toUpperCase()) || m.wholesalerName.isNotEmpty) {
            nameToMappingMap[m.externalName.trim().toUpperCase()] = m;
          }
        }
      }

      final productIdMap = {for (var p in _productMaster) p.id: p};
      final productNameMap = {for (var p in _productMaster) p.name.trim().toUpperCase(): p};

      for (var row in rawRows) {
        if (row.isEmpty) continue;

        String extract(String appField) {
          List<String> keywords = [];
          
          if (mapping.fieldMappings.containsKey(appField) &&
              mapping.fieldMappings[appField]!.isNotEmpty) {
            keywords.addAll(mapping.fieldMappings[appField]!);
          }
          
          final defaultKw = ImportMapping.defaultMapping().fieldMappings[appField];
          if (defaultKw != null) {
            for (var d in defaultKw) {
              if (!keywords.contains(d)) keywords.add(d);
            }
          }

          String normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

          // 1. First pass: Check for EXACT MATCH (case-insensitive & trimmed)
          for (var k in keywords) {
            String cleanK = k.trim().toLowerCase();
            if (cleanK.isEmpty) continue;
            int colIdx = headers.indexWhere((h) {
              String cleanH = h.trim().toLowerCase();
              if (appField == 'Mrp' && (cleanH.contains('vaton') || cleanH.contains('vat_on') || cleanH.contains('tax_on') || cleanH.contains('taxonsch'))) {
                return false; // Skip vatonmrp column
              }
              return cleanH == cleanK;
            });
            if (colIdx != -1 && colIdx < row.length) {
              String val = row[colIdx]?.toString().trim() ?? "";
              if (val.isNotEmpty) return val;
            }
          }

          // 2. Second pass: Check normalized match (ignoring symbols and spaces)
          for (var k in keywords) {
            String normK = normalize(k);
            if (normK.isEmpty) continue;
            int colIdx = headers.indexWhere((h) {
              String cleanH = h.trim().toLowerCase();
              if (appField == 'Mrp' && (cleanH.contains('vaton') || cleanH.contains('vat_on') || cleanH.contains('tax_on') || cleanH.contains('taxonsch'))) {
                return false;
              }
              return normalize(h) == normK;
            });
            if (colIdx != -1 && colIdx < row.length) {
              String val = row[colIdx]?.toString().trim() ?? "";
              if (val.isNotEmpty) return val;
            }
          }

          // 3. Third pass: Restricted substring match (Never allow "product" to match "customer/party/sahakar")
          for (var k in keywords) {
            String cleanK = k.trim().toLowerCase();
            if (cleanK.isEmpty) continue;
            int colIdx = headers.indexWhere((h) {
              String cleanH = h.trim().toLowerCase();
              if (appField == 'Mrp' && (cleanH.contains('vaton') || cleanH.contains('vat_on') || cleanH.contains('tax_on') || cleanH.contains('taxonsch') || cleanH.contains('discon'))) {
                return false; // Never match vatonmrp / taxonsch as MRP
              }
              if (appField == 'Product Code') {
                if (cleanH.contains('hsn')) {
                  return false; // Never extract HSN column as Product Code
                }
              }
              if (appField == 'Product') {
                if (cleanH.contains('party') || 
                    cleanH.contains('customer') || 
                    cleanH.contains('buyer') || 
                    cleanH.contains('sahakar') ||
                    cleanH.contains('consignee') ||
                    cleanH.contains('address') ||
                    cleanH.contains('code') || // <-- Prevent product matching code
                    cleanH.contains('id')) {   // <-- Prevent product matching id
                  return false;
                }
              }
              return cleanH.contains(cleanK);
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
        String rawHsnCode = extract('HSN');

        if (_isHsnCode(rawProductCode, rawHsnCode)) {
          rawProductCode = "";
        }

        // Discard header, buyer, summary, and totals rows
        String lowerCheck = rawProductName.toLowerCase();
        if (lowerCheck.contains('sahakar') ||
            lowerCheck.contains('customer') ||
            lowerCheck.contains('grand total') ||
            lowerCheck.contains('sub total') ||
            lowerCheck.contains('invoice total') ||
            lowerCheck.contains('round off') ||
            lowerCheck.contains('amount in words')) {
          continue;
        }

        // Clean leading price or serial garbage (e.g. "1327.55 ,PARACETAMOL" -> "PARACETAMOL")
        if (rawProductName.contains(',') && RegExp(r'^\d+(\.\d+)?\s*,').hasMatch(rawProductName)) {
          rawProductName = rawProductName.substring(rawProductName.indexOf(',') + 1).trim();
        }

        // Smart recovery: If rawProductName is empty or purely numeric, find actual text description from row
        if (rawProductName.isEmpty || double.tryParse(rawProductName.trim()) != null || RegExp(r'^\d+$').hasMatch(rawProductName.trim())) {
          if (rawProductCode.isNotEmpty && RegExp(r'[a-zA-Z]').hasMatch(rawProductCode.trim())) {
            String temp = rawProductName;
            rawProductName = rawProductCode;
            if (temp.isNotEmpty) rawProductCode = temp;
          } else {
            String bestText = "";
            for (int colI = 0; colI < row.length; colI++) {
              if (colI < headers.length) {
                String headerKey = headers[colI].trim().toLowerCase();
                // Skip columns that represent codes, IDs, amounts, rates, or quantities
                if (headerKey.contains('code') || headerKey.contains('id') || headerKey.contains('hsn') || 
                    headerKey.contains('batch') || headerKey.contains('mrp') || headerKey.contains('rate') || 
                    headerKey.contains('qty') || headerKey.contains('total') || headerKey.contains('amount') ||
                    headerKey.contains('disc') || headerKey.contains('gst')) {
                  continue; 
                }
              }
              String s = row[colI]?.toString().trim() ?? "";
              
              // RESTRICTIVE VALIDATION: A medicine name shouldn't be an address or contain prices/commas
              if (s.isNotEmpty && 
                  double.tryParse(s) == null && 
                  s.length < 45 && // Medicine names are concise; addresses/totals are long
                  !s.contains(',') && 
                  !s.toLowerCase().contains('sahakar') && 
                  !s.toLowerCase().contains('total') && 
                  RegExp(r'[a-zA-Z]').hasMatch(s)) {
                if (bestText.isEmpty || s.length > bestText.length) {
                  bestText = s;
                }
              }
            }
            if (bestText.isNotEmpty) {
              if (rawProductCode.isEmpty && rawProductName.isNotEmpty) rawProductCode = rawProductName;
              rawProductName = bestText;
            }
          }
        }

        rawProductName = _sanitizeProductName(rawProductName);

        if (rawProductName.isEmpty && rawProductCode.isEmpty && extract('Batch').isEmpty) continue;

        Product? matchedProduct;
        ProductMapping? foundMapping;

        // 1. Try match by External Name FIRST
        if (rawProductName.isNotEmpty) {
          foundMapping = nameToMappingMap[rawProductName.toUpperCase()];
        }

        // 2. Try match by Code ONLY if name match failed AND rawProductCode is NOT an HSN code
        if (foundMapping == null && rawProductCode.isNotEmpty && !_isHsnCode(rawProductCode, rawHsnCode)) {
          final candidateMapping = codeToMappingMap[rawProductCode.toUpperCase()];
          if (candidateMapping != null) {
            String candExtName = candidateMapping.externalName.trim().toUpperCase();
            if (candExtName.isEmpty || rawProductName.isEmpty || candExtName == rawProductName.toUpperCase()) {
              foundMapping = candidateMapping;
            }
          }
        }

        if (foundMapping != null) {
          // 3. Resolve internal product
          matchedProduct = productIdMap[foundMapping.productId];

          // 4. Fallback: Match by Internal Name if ID not found (handles re-indexing)
          if (matchedProduct == null && foundMapping.internalName.isNotEmpty) {
            matchedProduct = productNameMap[foundMapping.internalName.toUpperCase()];
          }

          // =====================================================
          // THE AUTO-HEALING ENGINE (PATCHES MISSING DATA SILENTLY)
          // =====================================================
          bool needsHeal = false;
          String updatedWholesaler = foundMapping.wholesalerName;
          String updatedCode = foundMapping.externalCode;
          String updatedProdId = foundMapping.productId;

          if (updatedWholesaler.isEmpty && cleanWholesalerName.isNotEmpty) {
            updatedWholesaler = cleanWholesalerName;
            needsHeal = true;
          }
          if (updatedCode.isEmpty && rawProductCode.isNotEmpty && !_isHsnCode(rawProductCode, rawHsnCode)) {
            updatedCode = rawProductCode;
            needsHeal = true;
          }
          if (updatedProdId.isEmpty && matchedProduct != null) {
            updatedProdId = matchedProduct.id;
            needsHeal = true;
          }

          if (needsHeal) {
            final patchedMapping = ProductMapping(
              id: foundMapping.id,
              wholesalerName: updatedWholesaler,
              externalCode: updatedCode,
              externalName: foundMapping.externalName,
              internalName: foundMapping.internalName,
              productId: updatedProdId,
            );

            // CODE MASTER FIX: Await the database write to prevent SQLite locking
            await saveProductMapping(patchedMapping);

            // Update RAM so we don't save the same thing twice in one loop
            foundMapping = patchedMapping;
            if (updatedCode.isNotEmpty) codeToMappingMap[updatedCode.toUpperCase()] = patchedMapping;
            if (patchedMapping.externalName.isNotEmpty) nameToMappingMap[patchedMapping.externalName.toUpperCase()] = patchedMapping;
          }
        }

        // 5. Last Resort: Direct match with master by Name
        if (matchedProduct == null && rawProductName.isNotEmpty) {
          matchedProduct = productNameMap[rawProductName.toUpperCase()];
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

        String finalName = matchedProduct?.name ??
            (foundMapping != null && foundMapping.internalName.trim().isNotEmpty
                ? foundMapping.internalName.trim()
                : rawProductName);
        if (finalName.isEmpty) finalName = rawProductCode.isNotEmpty ? "CODE: $rawProductCode" : "BATCH: ${extract('Batch')}";

        String finalId = matchedProduct?.id ??
            (foundMapping != null && foundMapping.productId.trim().isNotEmpty
                ? foundMapping.productId.trim()
                : "UNKNOWN");

        double discPercent = parseDouble(extract('DisPer'));
        double discAmt = parseDouble(extract('DisAmt'));
        double pRate = parseDouble(extract('Prate'));
        int qty = parseInt(extract('Qty'));
        double gross = pRate * qty;

        if (discPercent == 0.0 && discAmt > 0 && gross > 0) {
          discPercent = (discAmt * 100) / gross;
        } else if (discAmt == 0.0 && discPercent > 0 && gross > 0) {
          discAmt = (gross * discPercent) / 100;
        }

        double extractedMrp = parseDouble(extract('Mrp'));
        if (extractedMrp <= 0 && matchedProduct != null && matchedProduct.mrp > 0) {
          extractedMrp = matchedProduct.mrp;
        }

        items.add(PurchaseItem(
            id: finalId,
            productName: finalName,
            externalName: rawProductName,
            externalCode: rawProductCode,
            batch: extract('Batch'),
            expiry: _normalizeExpiry(extract('Exp')),
            qty: qty,
            fQty: parseInt(extract('Fqty')),
            pRate: pRate,
            mrp: extractedMrp,
            discPercent: discPercent,
            gstPercent: finalGstPercent > 0 ? finalGstPercent : (matchedProduct?.gstPercent ?? 12.0),
            sDiscPercent: (parseDouble(extract('Sdisc')) > 0) ? parseDouble(extract('Sdisc')) : (matchedProduct?.sDiscPercent ?? 0.0),
            packin: (parseInt(extract('Packing')) > 0) ? parseInt(extract('Packing')) : (matchedProduct?.packSize ?? 1),
            hsnCode: matchedProduct?.hsnCode ?? extract('HSN'),
            rack: matchedProduct?.rack ?? "",
            gross: gross, discAmt: discAmt, net: gross - discAmt, gstAmt: 0, total: 0, sRate: 0, lCost: 0
        ));
      }
      return items;
    } catch (e) {
      debugPrint("Import Error: $e");
      return [];
    }
  }

  Future<Map<String, dynamic>> getExcelDataForPreview(String filePath) async {
    try {
      String extension = filePath.split('.').last.toLowerCase();
      List<String> headers = [];
      final file = File(filePath);

      if (extension == 'xls') {
        final raf = await file.open();
        final startBytes = await raf.read(512);
        await raf.close();

        bool isBiff2 = startBytes.length >= 2 && startBytes[0] == 0x09 && startBytes[1] == 0x00;
        bool isBiff8 = startBytes.length >= 8 && startBytes[0] == 0xD0 && startBytes[1] == 0xCF && startBytes[2] == 0x11 && startBytes[3] == 0xE0;

        final bytes = await file.readAsBytes();

        if (isBiff2) {
          final rawRows = await compute(_parseBiff2Isolate, bytes);
          if (rawRows.isNotEmpty) headers = rawRows.first.map((e) => e.toString().trim()).toList();
        } else if (isBiff8) {
          return {'success': false, 'message': 'Legacy Excel 97-2003 format detected. Please save as .xlsx before uploading.'};
        } else {
          final rawRows = await compute(_parseDisguisedXlsIsolate, bytes);
          if (rawRows.isNotEmpty) headers = rawRows.first.map((e) => e.toString().trim()).toList();
        }
      } else if (extension == 'xlsx') {
        final bytes = await file.readAsBytes();
        final rawRows = await compute(_parseXlsxIsolate, bytes);
        if (rawRows.isNotEmpty) headers = rawRows.first.map((e) => e?.toString().trim() ?? "").toList();
      } else if (extension == 'csv') {
        final rawRows = await compute(_parseCsvIsolate, filePath);
        if (rawRows.isNotEmpty) headers = rawRows.first.map((e) => e.toString().trim()).toList();
      }

      if (headers.isEmpty) return {'success': false, 'message': 'No columns found or unsupported format.'};
      return {'success': true, 'header': headers};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // --- ⚡ BACKGROUND ISOLATE WORKERS (Stops UI Freezing) ---

  // THE MAGIC FIX: Reads old Wholesale software .xls directly in binary memory
  static List<List<dynamic>> _parseBiff2Isolate(Uint8List bytes) {
    ByteData bd = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
    int pos = 0;
    Map<int, Map<int, dynamic>> rows = {};
    int maxRow = -1;
    int maxCol = -1;

    while (pos + 4 <= bytes.length) {
      int opcode = bd.getUint16(pos, Endian.little);
      int length = bd.getUint16(pos + 2, Endian.little);
      pos += 4;
      if (pos + length > bytes.length) break;

      if (opcode == 0x0004 && length >= 8) { // LABEL Record
        int r = bd.getUint16(pos, Endian.little);
        int c = bd.getUint16(pos + 2, Endian.little);
        int strLen = bd.getUint8(pos + 7);
        if (8 + strLen <= length) {
          String val = String.fromCharCodes(bytes.sublist(pos + 8, pos + 8 + strLen));
          rows.putIfAbsent(r, () => {})[c] = val;
          if (r > maxRow) maxRow = r;
          if (c > maxCol) maxCol = c;
        }
      } else if (opcode == 0x0003 && length >= 15) { // NUMBER Record
        int r = bd.getUint16(pos, Endian.little);
        int c = bd.getUint16(pos + 2, Endian.little);
        double val = bd.getFloat64(pos + 7, Endian.little);
        rows.putIfAbsent(r, () => {})[c] = val;
        if (r > maxRow) maxRow = r;
        if (c > maxCol) maxCol = c;
      }
      pos += length;
    }

    List<List<dynamic>> table = [];
    for (int r = 0; r <= maxRow; r++) {
      List<dynamic> rowData = [];
      if (rows.containsKey(r)) {
        for (int c = 0; c <= maxCol; c++) {
          rowData.add(rows[r]![c] ?? "");
        }
      }
      if (rowData.isNotEmpty && rowData.any((e) => e.toString().trim().isNotEmpty)) {
        table.add(rowData);
      }
    }
    return table;
  }

  static List<List<dynamic>> _parseXlsxIsolate(Uint8List bytes) {
    var excel = Excel.decodeBytes(bytes);
    List<List<dynamic>> rows = [];
    if (excel.tables.isNotEmpty) {
      var table = excel.tables[excel.tables.keys.first];
      if (table != null && table.rows.isNotEmpty) {
        for (var r in table.rows) {
          rows.add(r.map((c) => cleanInvoiceNo(c?.value)).toList());
        }
      }
    }
    return rows;
  }

  static List<List<dynamic>> _parseCsvIsolate(String filePath) {
    final bytes = File(filePath).readAsBytesSync();
    String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      content = latin1.decode(bytes);
    }
    return _nativeCsvParse(content);
  }

  // ⚡ 100% PURE DART NATIVE PARSER (No external packages needed!)
  static List<List<dynamic>> _nativeCsvParse(String content) {
    String delimiter = content.contains('\t') ? '\t' : (content.contains(';') ? ';' : ',');
    List<List<dynamic>> rows = [];
    bool inQuotes = false;
    List<dynamic> currentRow = [];
    StringBuffer currentCell = StringBuffer();

    for (int i = 0; i < content.length; i++) {
      String char = content[i];
      if (char == '"') {
        inQuotes = !inQuotes; // Ignore delimiters inside quotes
      } else if (char == delimiter && !inQuotes) {
        currentRow.add(currentCell.toString().trim());
        currentCell.clear();
      } else if (char == '\n' && !inQuotes) {
        currentRow.add(currentCell.toString().trim());
        if (currentRow.any((e) => e.toString().isNotEmpty)) {
          rows.add(currentRow);
        }
        currentRow = [];
        currentCell.clear();
      } else if (char != '\r') {
        currentCell.write(char);
      }
    }
    // Add the very last row if file doesn't end with a newline
    if (currentCell.isNotEmpty || currentRow.isNotEmpty) {
      currentRow.add(currentCell.toString().trim());
      if (currentRow.any((e) => e.toString().isNotEmpty)) {
        rows.add(currentRow);
      }
    }
    return rows;
  }

  static List<List<dynamic>> _parseDisguisedXlsIsolate(Uint8List bytes) {
    String content;
    try { content = utf8.decode(bytes); } catch (_) { content = latin1.decode(bytes); }

    if (content.contains('<Workbook') && content.contains('<Worksheet')) {
      List<List<dynamic>> rows = [];
      final rowRegExp = RegExp(r'<Row.*?>([\s\S]*?)</Row>', caseSensitive: false);
      final cellRegExp = RegExp(r'<Cell.*?>[\s\S]*?<Data.*?>([\s\S]*?)</Data>[\s\S]*?</Cell>|<Cell.*?/>', caseSensitive: false);
      final htmlTagRegExp = RegExp(r'<[^>]*>');

      for (final rowMatch in rowRegExp.allMatches(content)) {
        String rowContent = rowMatch.group(1) ?? "";
        List<dynamic> rowData = [];
        for (final cellMatch in cellRegExp.allMatches(rowContent)) {
          String cellVal = cellMatch.group(1) ?? "";
          cellVal = cellVal.replaceAll(htmlTagRegExp, '').replaceAll('&nbsp;', ' ').trim();
          rowData.add(cellVal);
        }
        if (rowData.isNotEmpty) rows.add(rowData);
      }
      if (rows.isNotEmpty) return rows;
    }

    if (content.toLowerCase().contains('<table') && content.toLowerCase().contains('<tr')) {
      List<List<dynamic>> rows = [];
      final trRegExp = RegExp(r'<tr.*?>(.*?)</tr>', caseSensitive: false, dotAll: true);
      final tdRegExp = RegExp(r'<t[dh].*?>(.*?)</t[dh]>', caseSensitive: false, dotAll: true);
      final htmlTagRegExp = RegExp(r'<[^>]*>', multiLine: true);

      for (final trMatch in trRegExp.allMatches(content)) {
        String trContent = trMatch.group(1) ?? "";
        List<dynamic> rowData = [];
        for (final tdMatch in tdRegExp.allMatches(trContent)) {
          String cellContent = tdMatch.group(1) ?? "";
          cellContent = cellContent.replaceAll(htmlTagRegExp, '').replaceAll('&nbsp;', ' ').trim();
          rowData.add(cellContent);
        }
        if (rowData.isNotEmpty) rows.add(rowData);
      }
      return rows;
    }

    // Fallback to Native Parser
    return _nativeCsvParse(content);
  }

  // --- ⚡ ULTRA FAST EXPORT ISOLATES ---
  Future<Uint8List?> exportProductsToExcelBytes() async {
    try {
      final db = await DbHelper.instance.database;
      final List<Map<String, dynamic>> results = await db.rawQuery('''
        SELECT p.name, p.rack_id as rack, p.category_id as category, p.hsn_code as hsncode, 
               p.packing, b.purchase_rate as prate, b.mrp, b.current_stock as stock
        FROM product_master p
        LEFT JOIN stock_batches b ON p.id = b.product_id
      ''');
      return await compute(_generateProductsExcelIsolate, results);
    } catch (e) {
      debugPrint("Export Error: $e");
      return null;
    }
  }

  static Uint8List _generateProductsExcelIsolate(List<Map<String, dynamic>> results) {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Stock List'];
    excel.delete('Sheet1');

    sheetObject.appendRow([
      TextCellValue("Name"), TextCellValue("Rack"), TextCellValue("Category"),
      TextCellValue("hsncode"), TextCellValue("packing"), TextCellValue("P.Rate"),
      TextCellValue("MRP"), TextCellValue("Current Stock"),
    ]);

    for (var row in results) {
      sheetObject.appendRow([
        TextCellValue(row['name']?.toString() ?? ""), TextCellValue(row['rack']?.toString() ?? ""),
        TextCellValue(row['category']?.toString() ?? ""), TextCellValue(row['hsncode']?.toString() ?? ""),
        IntCellValue(row['packing'] ?? 1), DoubleCellValue(row['prate'] ?? 0.0),
        DoubleCellValue(row['mrp'] ?? 0.0), IntCellValue(row['stock'] ?? 0),
      ]);
    }
    return Uint8List.fromList(excel.encode()!);
  }

  Future<Uint8List?> exportProductMappingsToExcelBytes() async {
    if (_productMappings.isEmpty) return null;
    try {
      final mappingsList = _productMappings.map((m) => {
        'wholesaler': m.wholesalerName, 'code': m.externalCode,
        'externalName': m.externalName, 'internalName': m.internalName, 'productId': m.productId
      }).toList();

      return await compute(_generateMappingsExcelIsolate, mappingsList);
    } catch (e) {
      debugPrint("Export Mappings Error: $e");
      return null;
    }
  }

  static Uint8List _generateMappingsExcelIsolate(List<Map<String, dynamic>> data) {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Product Mappings'];
    excel.delete('Sheet1');

    sheetObject.appendRow([
      TextCellValue('Wholesaler'), TextCellValue('Wholesaler Stock Number'),
      TextCellValue('Wholesaler Stock Name'), TextCellValue('(Mapped) My Stock Name'), TextCellValue('Product ID')
    ]);

    for (var m in data) {
      sheetObject.appendRow([
        TextCellValue(m['wholesaler']), TextCellValue(m['code']),
        TextCellValue(m['externalName']), TextCellValue(m['internalName']), TextCellValue(m['productId'])
      ]);
    }
    return Uint8List.fromList(excel.encode()!);
  }

  double _parse(String s) {
    if (s.isEmpty) return 0.0;
    String cleaned = s.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  String _normalizeExpiry(String exp) {
    if (exp.isEmpty || exp == "0") return "--/--";
    
    // 1. Handle ISO or Date Strings (e.g. 2027-06-30T...)
    DateTime? dt = DateTime.tryParse(exp);
    
    // 2. Handle Excel Serial Numbers if parsing failed (e.g. 46569)
    if (dt == null) {
      double? d = double.tryParse(exp);
      if (d != null && d > 10000) { // Serial numbers for current dates are ~45000+
        dt = DateTime(1899, 12, 30).add(Duration(days: d.toInt()));
      }
    }

    if (dt != null) {
      String mm = dt.month.toString().padLeft(2, '0');
      String yy = dt.year.toString().substring(dt.year.toString().length - 2);
      return "$mm/$yy";
    }

    // 3. Fallback: Handle manual formats like DD/MM/YYYY or MM/YY
    if (exp.contains('/')) {
      List<String> parts = exp.split('/');
      if (parts.length == 3) {
        int m = int.tryParse(parts[1]) ?? 1;
        if (m < 1 || m > 12) m = 1;
        String mm = m.toString().padLeft(2, '0');
        String yy = parts[2].length > 2 ? parts[2].substring(parts[2].length - 2) : parts[2].padLeft(2, '0');
        return "$mm/$yy";
      } else if (parts.length == 2) {
        int m = int.tryParse(parts[0]) ?? 1;
        if (m < 1 || m > 12) m = 1;
        String mm = m.toString().padLeft(2, '0');
        String yy = parts[1].length > 2 ? parts[1].substring(parts[1].length - 2) : parts[1].padLeft(2, '0');
        return "$mm/$yy";
      }
    }
    
    return exp;
  }

  // Robust extraction of values from Excel CellValue objects
  String getCellValue(dynamic val) {
    if (val == null) return "";

    if (val is DateTime) {
      return "${val.year.toString().padLeft(4, '0')}-${val.month.toString().padLeft(2, '0')}-${val.day.toString().padLeft(2, '0')} ${val.hour.toString().padLeft(2, '0')}:${val.minute.toString().padLeft(2, '0')}:${val.second.toString().padLeft(2, '0')}";
    }

    try {
      dynamic v = val;
      final typeStr = v.runtimeType.toString();
      if (typeStr.contains('Date') || typeStr.contains('Time')) {
        int? y = v.year as int?;
        int? m = v.month as int?;
        int? d = v.day as int?;
        int h = (v.hour as int?) ?? 0;
        int min = (v.minute as int?) ?? 0;
        int sec = (v.second as int?) ?? 0;

        if (y != null && m != null && d != null && y > 1900) {
          return "${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')} ${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}";
        }
      }
    } catch (_) {}

    String s = val.toString().trim();
    if (s.isEmpty) return "";

    if (s.contains('year:') && s.contains('month:') && s.contains('day:')) {
      return s;
    }

    if (s.contains('(') && s.contains(')')) {
      int start = s.indexOf('(');
      int end = s.lastIndexOf(')');
      if (end > start) {
        String inner = s.substring(start + 1, end).trim();
        if (inner.contains('year:') && inner.contains('month:') && inner.contains('day:')) {
          return inner;
        }
        return inner;
      }
    }
    return s.trim();
  }

  bool isValidProductName(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty) return false;
    
    // 1. Reject purely numeric values (e.g., "37", "39", "45", "48", "5", "55", "75", "115", "120", "20.00")
    if (double.tryParse(name) != null) return false;
    
    // 2. Reject simple numbers with single unit/packing/dosage suffixes like "6P", "7S", "10T", "10S", "6MG", "10ML"
    final cleaned = name.toUpperCase().replaceAll(RegExp(r"\W"), "");
    if (RegExp(r'^\d+[A-Z]{1,3}$').hasMatch(cleaned)) return false;

    // 3. Reject common non-product string values or column headers accidentally parsed as names
    final lower = name.toLowerCase();
    if (lower.contains('rupee') || lower.contains('rupees') || lower == 'rs' || lower.startsWith('rs.')) return false;
    if (lower.contains('grand total') || lower.contains('sub total') || lower.contains('report summary')) return false;

    const invalidExactWords = {
      'mrp', 'rate', 'price', 'l.cost', 'lcost', 'cost', 'p.rate', 'prate', 's.rate', 'srate',
      'qty', 'stock', 'quantity', 'batch', 'expiry', 'exp', 'packing', 'pack', 'pck',
      's.no', 'sno', 'sl', 'sl.no', 'slno', 'serial', 'id', 'product id', 'code',
      'supplier', 'vendor', 'rupees', 'rs', 'particulars', 'item description', 'description'
    };
    if (invalidExactWords.contains(lower)) return false;

    // 4. Require at least two alphabetic characters in the product name
    int letterCount = 0;
    for (int i = 0; i < name.length; i++) {
      final code = name.codeUnitAt(i);
      if ((code >= 65 && code <= 90) || (code >= 97 && code <= 122)) {
        letterCount++;
      }
    }
    if (letterCount < 2) return false;

    return true;
  }

  Future<void> _autoCleanupInvalidProducts(sql.Database db) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('db_cleanup_done_v74') == true) {
        return; // Skip on boot: cleanup already completed once
      }

      final List<Map<String, dynamic>> allProds = await db.query('product_master', columns: ['id', 'name']);
      final List<String> invalidIds = [];

      for (int i = 0; i < allProds.length; i++) {
        final p = allProds[i];
        final String name = p['name']?.toString() ?? '';
        if (!isValidProductName(name)) {
          invalidIds.add(p['id'].toString());
        }
        if (i % 5000 == 0 && i > 0) {
          await Future.delayed(Duration.zero);
        }
      }

      if (invalidIds.isNotEmpty) {
        final salesProds = await db.rawQuery("SELECT DISTINCT product_id FROM sales_items WHERE product_id IS NOT NULL AND product_id != ''");
        final purchaseProds = await db.rawQuery("SELECT DISTINCT product_id FROM purchase_items WHERE product_id IS NOT NULL AND product_id != ''");

        final Set<String> activeProdIds = {
          for (var r in salesProds) r['product_id'].toString(),
          for (var r in purchaseProds) r['product_id'].toString(),
        };

        final List<String> toDelete = invalidIds.where((id) => !activeProdIds.contains(id)).toList();

        if (toDelete.isNotEmpty) {
          await db.transaction((txn) async {
            for (int i = 0; i < toDelete.length; i += 500) {
              final chunk = toDelete.sublist(i, (i + 500 < toDelete.length) ? i + 500 : toDelete.length);
              final placeholders = List.filled(chunk.length, '?').join(',');
              await txn.delete('stock_batches', where: 'product_id IN ($placeholders)', whereArgs: chunk);
              await txn.delete('product_master', where: 'id IN ($placeholders)', whereArgs: chunk);
            }
          });
        }
      }

      await prefs.setBool('db_cleanup_done_v74', true);
    } catch (e) {
      debugPrint("Auto-cleanup note: $e");
    }
  }

  Future<Map<String, dynamic>> cleanupInvalidProductsAndStock() async {
    final db = await DbHelper.instance.database;
    int deletedCount = 0;
    try {
      final List<Map<String, dynamic>> allProds = await db.query('product_master', columns: ['id', 'name']);
      final List<String> invalidIds = [];

      for (var p in allProds) {
        final String name = p['name']?.toString() ?? '';
        if (!isValidProductName(name)) {
          invalidIds.add(p['id'].toString());
        }
      }

      if (invalidIds.isNotEmpty) {
        final salesProds = await db.rawQuery("SELECT DISTINCT product_id FROM sales_items WHERE product_id IS NOT NULL AND product_id != ''");
        final purchaseProds = await db.rawQuery("SELECT DISTINCT product_id FROM purchase_items WHERE product_id IS NOT NULL AND product_id != ''");

        final Set<String> activeProdIds = {
          for (var r in salesProds) r['product_id'].toString(),
          for (var r in purchaseProds) r['product_id'].toString(),
        };

        final List<String> toDelete = invalidIds.where((id) => !activeProdIds.contains(id)).toList();

        if (toDelete.isNotEmpty) {
          await db.transaction((txn) async {
            for (int i = 0; i < toDelete.length; i += 500) {
              final chunk = toDelete.sublist(i, (i + 500 < toDelete.length) ? i + 500 : toDelete.length);
              final placeholders = List.filled(chunk.length, '?').join(',');
              await txn.delete('stock_batches', where: 'product_id IN ($placeholders)', whereArgs: chunk);
              await txn.delete('product_master', where: 'id IN ($placeholders)', whereArgs: chunk);
              deletedCount += chunk.length;
            }
          });
        }
      }

      await loadFromDatabase();
      notifyListeners();
      return {'success': true, 'deleted': deletedCount};
    } catch (e) {
      debugPrint("Error cleaning up invalid products: $e");
      return {'success': false, 'message': e.toString()};
    }
  }

  int _findIdx(List<String> header, List<String> keywords, [bool exact = false]) {
    // Normalization helper
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9%]'), '').trim();

    // PASS 1: Look for EXACT matches (normalized) first to avoid collisions
    for (var k in keywords) {
      String searchKey = norm(k);
      for (int i = 0; i < header.length; i++) {
        if (norm(header[i]) == searchKey) return i;
      }
    }

    if (exact) return -1;

    // PASS 2: Look for partial matches only if no exact match found
    for (var k in keywords) {
      String searchKey = norm(k);
      if (searchKey.isEmpty) continue;
      for (int i = 0; i < header.length; i++) {
        String h = norm(header[i]);
        if (searchKey == 'name' || searchKey == 'product' || searchKey == 'item') {
          if (h.contains('supplier') || h.contains('company') || h.contains('vendor') || 
              h.contains('generic') || h.contains('customer') || h.contains('doctor') || 
              h.contains('code') || h.contains('id')) {
            continue;
          }
        }
        if (h.contains(searchKey)) return i;
      }
    }
    return -1;
  }

  Future<void> loadStocksFromCSV() async {
    if (kIsWeb) return;
    isLoading = true;
    notifyListeners();
    try {
      final file = File(r'J:\PHARMACY\FULL STOCKS.csv');
      if (!await file.exists()) {
        errorMessage = "File NOT FOUND";
        isLoading = false;
        notifyListeners();
        return;
      }

      // Use compute to parse CSV in a background Isolate
      final List<Product> loadedProducts = await compute(_parseCSVIsolate, await file.readAsString());

      _products.clear();
      _products.addAll(loadedProducts);
      _rebuildSearchIndex();

      isLoading = false;
      notifyListeners();
    } catch (e) {
      errorMessage = e.toString();
      isLoading = false;
      notifyListeners();
    }
  }

  // Pure function for Isolate
  static List<Product> _parseCSVIsolate(String content) {
    final List<Product> products = [];
    final lines = content.split('\n');
    for (int i = 3; i < lines.length; i++) {
      final r = lines[i].split(',');
      if (r.length >= 26) {
        products.add(Product(
          id: "CSV_$i",
          name: r[3].toString(),
          stock: double.tryParse(r[10].toString())?.toInt() ?? 0,
          batch: r[8].toString(),
          expiry: r[9].toString(),
          mrp: double.tryParse(r[25].toString()) ?? 0.0,
          purchaseRate: double.tryParse(r[13].toString()) ?? 0.0,
          salePrice: double.tryParse(r[24].toString()) ?? 0.0,
          taxableSP: double.tryParse(r[24].toString()) ?? 0.0,
          packSize: double.tryParse(r[11].toString())?.toInt() ?? 1,
          manufacturer: r[2].toString(),
          rack: r[4].toString(),
          category: r[5].toString(),
        ));
      }
    }
    return products;
  }

  Future<String> saveSale(SaleInvoice sale) async {
    if (kIsWeb) return "";
    if (sale.customerAcc.trim().isEmpty) {
      throw "Account Name is mandatory. Cannot save sales invoice with blank Account Name.";
    }
    if (sale.patient.trim().isEmpty) {
      throw "Patient Name is mandatory. Cannot save sales invoice with blank Patient Name.";
    }
    if (sale.doctor.trim().isEmpty) {
      throw "Doctor Name is mandatory. Cannot save sales invoice with blank Doctor Name.";
    }

    String finalEntryNo = sale.entryNo;
    String fy = sale.financialYear.isEmpty ? _selectedFinancialYear : sale.financialYear;
    
    List<Map<String, dynamic>> existingOldItems = [];
    double oldGrandTotal = 0.0;
    DateTime? oldSaleDate;
    bool isEdit = false;

    try {
      List<Map<String, dynamic>> existingOldHeader = [];

      await executeSerializedTransaction((txn) async {
        if (finalEntryNo.isEmpty || finalEntryNo == "AUTO") {
          finalEntryNo = await _generateNextNoWithFY(txn, 'sales_invoices', 'entry_no', fy);
        }

        if (finalEntryNo.isNotEmpty && finalEntryNo != "AUTO") {
          existingOldItems = await txn.query('sales_items', where: 'invoice_no = ?', whereArgs: [finalEntryNo]);
          existingOldHeader = await txn.query('sales_invoices', where: 'entry_no = ?', whereArgs: [finalEntryNo]);
          if (existingOldHeader.isNotEmpty) {
            isEdit = true;
            if ((existingOldHeader.first['is_deleted'] as int?) == 1) {
              throw "Transaction Blocked: Invoice #$finalEntryNo is inactive or deleted.";
            }
            oldGrandTotal = (existingOldHeader.first['grand_total'] as num?)?.toDouble() ?? 0.0;
            oldSaleDate = DateTime.tryParse(existingOldHeader.first['date']?.toString() ?? '');
          }
        }

          // 1. Stock Integrity Pre-check
          Map<String, int> oldImpact = {};
          Map<String, int> newImpact = {};

          for (var old in existingOldItems) {
            int looseQty = (old['qty'] as num).toInt(); 
            oldImpact["${old['product_id']}|${old['batch_number']}"] = (oldImpact["${old['product_id']}|${old['batch_number']}"] ?? 0) - looseQty; 
          }
          for (var item in sale.items) {
            int looseQty = item.qty; // Safely using item.qty
            newImpact["${item.product.id}|${item.product.batch}"] = (newImpact["${item.product.id}|${item.product.batch}"] ?? 0) - looseQty; 
          }
          await _checkStockIntegrityBeforeEdit(txn: txn, oldImpact: oldImpact, newImpact: newImpact);

          // 2. Revert Old Stock in Database
          if (existingOldItems.isNotEmpty) {
            for (var oldItem in existingOldItems) {
              final pId = oldItem['product_id']?.toString() ?? '';
              final pBatch = oldItem['batch_number']?.toString() ?? '';
              final pQty = (oldItem['qty'] as num?)?.toInt() ?? 0;

              if (pId.isNotEmpty && pQty > 0) {
                await txn.rawUpdate(
                  'UPDATE stock_batches SET current_stock = current_stock + ? WHERE product_id = ? AND batch_number = ? COLLATE NOCASE',
                  [pQty, pId, pBatch]
                );
              }
            }
            await txn.delete('sales_items', where: 'invoice_no = ?', whereArgs: [finalEntryNo]);
          }

          // 3. Revert Old Patient Balance
          if (existingOldHeader.isNotEmpty) {
            double oldCredit = existingOldHeader.first['customer_acc'] != 'Cash' 
                ? (((existingOldHeader.first['grand_total'] as num?)?.toDouble() ?? 0.0) - ((existingOldHeader.first['rcvd_amt'] as num?)?.toDouble() ?? 0.0))
                : 0.0;
            String oldPatient = existingOldHeader.first['patient']?.toString() ?? '';
            if (oldPatient.isNotEmpty && oldCredit > 0) {
              await txn.rawUpdate('UPDATE patients SET current_balance = current_balance - ? WHERE name = ? COLLATE NOCASE', [oldCredit, oldPatient]);
            }
          }

          // 4. Save Invoice Header
          await txn.insert('sales_invoices', {
            'entry_no': finalEntryNo,
            'date': sale.date.toIso8601String(),
            'customer_acc': sale.customerAcc,
            'patient': sale.patient,
            'mobile': sale.mobile,
            'doctor': sale.doctor,
            'doctor_reg_no': sale.doctorRegNo,
            'special_order_json': sale.specialOrderJson,
            'tax_type': sale.taxType,
            'sub_total': sale.subTotal.asCurrency,
            'discount_percent': sale.discountPercent.asCurrency,
            'discount': sale.discount.asCurrency,
            'additional_discount': sale.additionalDiscount.asCurrency,
            'other_charge': sale.otherCharge.asCurrency,
            'rcvd_amt': sale.rcvdAmt.asCurrency,
            'round_off': sale.roundOff.asCurrency,
            'grand_total': sale.grandTotal.asCurrency,
            'agent': sale.agent,
            'expecting_date': sale.expectingDate,
            'special_customer_name': sale.specialCustomerName,
            'special_customer_phone': sale.specialCustomerPhone,
            'payment_remarks': sale.paymentRemarks,
            'secondary_acc': sale.secondaryAcc,
            'secondary_amt': sale.secondaryAmt.asCurrency,
            'sales_return_amt': sale.salesReturn.asCurrency,
            'is_paid': sale.isPaid ? 1 : 0,
            'days': sale.days,
            'financial_year': fy,
            'order_type': sale.orderType,
          }, conflictAlgorithm: sql.ConflictAlgorithm.replace);

          // 5. Insert Items & Apply Atomic DB Stock Deduction
          for (var item in sale.items) {
            await txn.insert('sales_items', {
              'invoice_no': finalEntryNo,
              'product_id': item.product.id,
              'product_name': item.product.name,
              'extra': item.extra,
              'batch_number': item.product.batch,
              'expiry_date': item.product.expiry,
              'qty': item.qty,
              'quantity': item.qty,
              'packin': item.packin,
              'mrp': item.product.mrp.asCurrency, 
              'purchase_rate': item.purchaseRate,
              'landing_cost': item.landingCost,
              'taxable_sp': item.taxableSP.asCurrency,
              's_rate': item.sRate.asCurrency,
              'sale_rate': item.product.salePrice.asCurrency, 
              'disc_percent': item.discPercent.asCurrency,
              'disc_amt': item.discAmt.asCurrency,
              'gst_percent': item.gstPercent.asCurrency,
              'tax_percent': item.gstPercent.asCurrency,
              'gst_amt': item.gstAmt.asCurrency,
              'cgst_amt': (sale.taxType == 'Interstate' ? 0.0 : item.cgstAmt).asCurrency,
              'sgst_amt': (sale.taxType == 'Interstate' ? 0.0 : item.sgstAmt).asCurrency,
              'igst_amt': (sale.taxType == 'Interstate' ? item.gstAmt : 0.0).asCurrency,
              'total': item.total.asCurrency,
              'profit': item.profit.asCurrency,
              'supplier_name': item.supplier,
            });

            int remainingQtyToDeduct = item.qty;

            // Fetch all physical matching rows for this product + batch ordered by rowid/rate
            final List<Map<String, dynamic>> matchingBatches = await txn.rawQuery('''
              SELECT rowid, current_stock 
              FROM stock_batches 
              WHERE product_id = ? AND batch_number = ? AND current_stock > 0 COLLATE NOCASE
              ORDER BY rowid ASC
            ''', [item.product.id, item.product.batch.trim()]);

            for (var bRow in matchingBatches) {
              if (remainingQtyToDeduct <= 0) break;
              int rowid = bRow['rowid'] as int;
              int availableInRow = (bRow['current_stock'] as num).toInt();

              int deductFromThisRow = (remainingQtyToDeduct <= availableInRow) 
                  ? remainingQtyToDeduct 
                  : availableInRow;

              final int affected = await txn.rawUpdate(
                'UPDATE stock_batches SET current_stock = current_stock - ? WHERE rowid = ? AND current_stock >= ?',
                [deductFromThisRow, rowid, deductFromThisRow]
              );

              if (affected == 0) {
                throw "Stock race condition on RowID $rowid during sale allocation.";
              }

              remainingQtyToDeduct -= deductFromThisRow;
            }

            if (remainingQtyToDeduct > 0) {
              final pRes = await txn.query('product_master', columns: ['name'], where: 'id = ?', whereArgs: [item.product.id]);
              String pName = pRes.isNotEmpty ? pRes.first['name'].toString() : item.product.name;
              throw "STOCK SHORTAGE!\n\nCould not fulfill $remainingQtyToDeduct loose units of '$pName' (Batch: ${item.product.batch}).";
            }
          }

          // 6. Apply New Patient Balance
          double newCredit = sale.customerAcc != "Cash" ? (sale.grandTotal - sale.rcvdAmt) : 0.0;
          if (sale.patient.isNotEmpty && newCredit > 0) {
            final int updatedRows = await txn.rawUpdate(
              'UPDATE patients SET current_balance = current_balance + ? WHERE name = ? COLLATE NOCASE', 
              [newCredit, sale.patient]
            );
            if (updatedRows == 0) {
              await txn.insert('patients', {
                'id': "PAT_${DateTime.now().millisecondsSinceEpoch}", 
                'name': sale.patient, 
                'mobile': sale.mobile, 
                'current_balance': newCredit, 
                'address': ''
              });
            }
          }
      });

      // -----------------------------------------------------------------
      // POST-COMMIT IN-MEMORY RECONCILIATION
      // -----------------------------------------------------------------
      // Re-add old items back into memory
      for (var old in existingOldItems) {
        String pId = old['product_id'].toString();
        String pBatch = old['batch_number'].toString();
        int q = (old['qty'] as num).toInt();

        int pIdx = _products.indexWhere((p) => p.id == pId && p.batch == pBatch);
        if (pIdx != -1) _products[pIdx].stock += q;

        int mIdx = _productMaster.indexWhere((p) => p.id == pId);
        if (mIdx != -1) _productMaster[mIdx].stock += q;
      }

      // Deduct new items from memory
      for (var item in sale.items) {
        int pIdx = _products.indexWhere((p) => p.id == item.product.id && p.batch == item.product.batch);
        if (pIdx != -1) {
          _products[pIdx].stock -= item.qty;
        } else {
          item.product.stock -= item.qty;
        }

        int mIdx = _productMaster.indexWhere((p) => p.id == item.product.id);
        if (mIdx != -1) {
          _productMaster[mIdx].stock -= item.qty;
        }
      }

      // Reconcile Cached Invoices & Dashboard Counters
      final updatedSale = SaleInvoice(
        entryNo: finalEntryNo,
        date: sale.date,
        customerAcc: sale.customerAcc,
        patient: sale.patient,
        mobile: sale.mobile,
        doctor: sale.doctor,
        doctorRegNo: sale.doctorRegNo,
        specialOrderJson: sale.specialOrderJson,
        taxType: sale.taxType,
        days: sale.days,
        items: sale.items,
        subTotal: sale.subTotal,
        discountPercent: sale.discountPercent,
        discount: sale.discount,
        additionalDiscount: sale.additionalDiscount,
        otherCharge: sale.otherCharge,
        rcvdAmt: sale.rcvdAmt,
        roundOff: sale.roundOff,
        grandTotal: sale.grandTotal,
        agent: sale.agent,
        expectingDate: sale.expectingDate,
        specialCustomerName: sale.specialCustomerName,
        specialCustomerPhone: sale.specialCustomerPhone,
        paymentRemarks: sale.paymentRemarks,
        secondaryAcc: sale.secondaryAcc,
        secondaryAmt: sale.secondaryAmt,
        financialYear: fy,
        salesReturn: sale.salesReturn,
        isDeleted: sale.isDeleted,
        isPaid: sale.isPaid,
      );

      final now = DateTime.now();
      bool wasMadeToday = oldSaleDate != null && 
          oldSaleDate!.year == now.year && 
          oldSaleDate!.month == now.month && 
          oldSaleDate!.day == now.day;
      bool isMadeToday = sale.date.year == now.year && 
          sale.date.month == now.month && 
          sale.date.day == now.day;

      int idx = _sales.indexWhere((s) => s.entryNo == finalEntryNo);
      if (idx != -1) {
        _sales[idx] = updatedSale;
      } else {
        _sales.insert(0, updatedSale);
      }

      if (isEdit) {
        if (wasMadeToday) {
          _todayRevenue += (updatedSale.grandTotal - oldGrandTotal);
        }
      } else if (isMadeToday) {
        _todayRevenue += updatedSale.grandTotal;
        _todaySalesCount += 1;
      }

      _sales.sort((a, b) => b.date.compareTo(a.date));
      if (_sales.length > 50) _sales.removeLast();

      _rebuildSearchIndex();
      await refreshSalesFrequency();

      notifyListeners();
      return finalEntryNo;
    } catch (e) {
      debugPrint("Save Sale Error: $e");
      rethrow;
    }
  }

  Future<String> savePurchase(PurchaseEntry purchase) async {
    if (kIsWeb) return "";
    String finalEntryNo = purchase.entryNo;
    String fy = purchase.financialYear.isEmpty ? _selectedFinancialYear : purchase.financialYear;
    List<Map<String, dynamic>> existingOldItems = [];
    try {
      List<Map<String, dynamic>> existingOldHeader = [];

      await executeSerializedTransaction((txn) async {
        if (finalEntryNo.isEmpty || finalEntryNo == "AUTO") {
          finalEntryNo = await _generateNextNoWithFY(txn, 'purchase_entries', 'entry_no', fy);
        }

        if (finalEntryNo.isNotEmpty && finalEntryNo != "AUTO") {
          existingOldItems = await txn.query('purchase_items', where: 'entry_no = ?', whereArgs: [finalEntryNo]);
          existingOldHeader = await txn.query('purchase_entries', where: 'entry_no = ?', whereArgs: [finalEntryNo]);
          if (existingOldHeader.isNotEmpty && (existingOldHeader.first['is_deleted'] as int?) == 1) {
            throw "Transaction Blocked: Purchase #${purchase.entryNo} is inactive or deleted.";
          }
        }

          // ================================================================
          // 1. NET-DELTA STOCK LOCK
          // ================================================================
          Map<String, int> netDelta = {};

          for (var old in existingOldItems) {
            String pId = old['product_id']?.toString() ?? "";
            if (pId.isEmpty) { 
              final mRes = await txn.query('product_master', columns: ['id'], where: 'name = ? COLLATE NOCASE', whereArgs: [old['product_name']]);
              if (mRes.isNotEmpty) pId = mRes.first['id'] as String;
            }
            if (pId.isNotEmpty) {
              int looseQty = ((old['qty'] as num).toInt() + (old['f_qty'] as num).toInt()) * ((old['packin'] as num).toInt());
              netDelta["$pId|${old['batch']}"] = (netDelta["$pId|${old['batch']}"] ?? 0) - looseQty; 
            }
          }

          for (var item in purchase.items) {
            String pId = item.id;
            if (pId.isEmpty || pId == "UNKNOWN") { 
              final mIdx = _productMaster.indexWhere((p) => p.name.toLowerCase() == item.productName.toLowerCase());
              if (mIdx != -1) pId = _productMaster[mIdx].id;
            }
            if (pId.isNotEmpty) {
              int looseQty = (item.qty + item.fQty) * item.packin;
              netDelta["$pId|${item.batch}"] = (netDelta["$pId|${item.batch}"] ?? 0) + looseQty; 
            }
          }

          for (var entry in netDelta.entries) {
            if (entry.value < 0) { 
              int requiredToRemove = entry.value.abs();
              String pId = entry.key.split('|')[0];
              String batch = entry.key.split('|')[1];

              await txn.rawUpdate('UPDATE stock_batches SET current_stock = current_stock WHERE product_id = ? AND batch_number = ?', [pId, batch]);
              final stockCheck = await txn.rawQuery('SELECT current_stock FROM stock_batches WHERE product_id = ? AND batch_number = ? COLLATE NOCASE', [pId, batch]);
              int liveStock = stockCheck.isNotEmpty ? (stockCheck.first['current_stock'] as num).toInt() : 0;

              if (liveStock < requiredToRemove) {
                final pNameRow = await txn.rawQuery('SELECT name FROM product_master WHERE id = ?', [pId]);
                String pName = pNameRow.isNotEmpty ? pNameRow.first['name']?.toString() ?? "Unknown" : "Unknown";
                int shortfall = requiredToRemove - liveStock;
                throw "EDIT BLOCKED!\n\nYou reduced the quantity of '$pName' (Batch: $batch), but $shortfall of those units have already been sold or moved.\n\nTo save this edit, you must first delete the sales where those units were consumed.";
              }
            }
          }

          // ================================================================
          // 2. REVERT OLD STOCK & LEDGER
          // ================================================================
          if (existingOldItems.isNotEmpty) {
            for (var old in existingOldItems) {
              String pId = old['product_id']?.toString() ?? "";
              if (pId.isEmpty) { 
                final mRes = await txn.query('product_master', columns: ['id'], where: 'name = ? COLLATE NOCASE', whereArgs: [old['product_name']]);
                if (mRes.isNotEmpty) pId = mRes.first['id'] as String;
              }
              if (pId.isNotEmpty) {
                int looseQty = ((old['qty'] as num).toInt() + (old['f_qty'] as num).toInt()) * ((old['packin'] as num).toInt());
                await txn.rawUpdate('UPDATE stock_batches SET current_stock = current_stock - ? WHERE product_id = ? AND batch_number = ? COLLATE NOCASE', [looseQty, pId, old['batch']]);
              }
            }
            await txn.delete('purchase_items', where: 'entry_no = ?', whereArgs: [finalEntryNo]);
          }

          if (existingOldHeader.isNotEmpty) {
            double oldGrandTotal = (existingOldHeader.first['grand_total'] as num?)?.toDouble() ?? 0.0;
            String oldSup = existingOldHeader.first['supplier_name'].toString();
            await txn.rawUpdate('UPDATE suppliers SET current_balance = current_balance - ? WHERE name = ? COLLATE NOCASE', [oldGrandTotal, oldSup]);
          }

          // ================================================================
          // 3. SAVE HEADER
          // ================================================================
          await txn.insert('purchase_entries', {
            'entry_no': finalEntryNo,
            'date': purchase.date.toIso8601String(),
            'supplier_name': purchase.supplierName,
            'sup_inv_no': cleanInvoiceNo(purchase.supInvNo),
            'sup_inv_date': purchase.supInvDate.toIso8601String(),
            'done_by': purchase.doneBy,
            'inv_total': purchase.invTotal,
            'remarks': purchase.remarks,
            'sub_total': purchase.subTotal,
            'discount': purchase.discount,
            'other_charge': purchase.otherCharge,
            'round_off': purchase.roundOff,
            'grand_total': purchase.grandTotal,
            'payment_status': purchase.paymentStatus,
            'payment_mode': purchase.paymentMode,
            'payment_remarks': purchase.paymentRemarks,
            'payment_date': purchase.paymentDate?.toIso8601String(),
            'paid_amount': purchase.paymentStatus == 1 ? purchase.grandTotal : 0.0,
            'days': purchase.days,
            'financial_year': fy,
          }, conflictAlgorithm: sql.ConflictAlgorithm.replace);

          // ================================================================
          // 4. INSERT NEW ITEMS & APPLY NEW LEDGER
          // ================================================================
          for (var item in purchase.items) {
            double netAmt = (item.pRate * item.qty) - item.discAmt;
            double totalAmt = netAmt + item.gstAmt;
            double strips = (item.qty + item.fQty).toDouble();
            double trueLandingCost = strips > 0 ? (totalAmt / strips) : item.pRate;
            if (trueLandingCost <= 0) trueLandingCost = item.pRate;

            String productId = item.id;
            if (productId.isEmpty || productId == "UNKNOWN") {
              final mRes = await txn.query('product_master', columns: ['id'], where: 'name = ? COLLATE NOCASE', whereArgs: [item.productName.trim()]);
              if (mRes.isNotEmpty) {
                productId = mRes.first['id'] as String;
              } else {
                productId = generateUniqueId();
                await txn.insert('product_master', {'id': productId, 'name': item.productName.trim(), 'packing': item.packin, 'is_active': 1});
              }
            }

            int looseQty = (item.qty + item.fQty) * item.packin;
            await txn.rawInsert('''
              INSERT INTO stock_batches (product_id, batch_number, expiry_date, current_stock, purchase_rate, landing_cost, mrp, sale_rate, packing, supplier_name, gst_percent, rack, is_active)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              ON CONFLICT(product_id, batch_number, expiry_date, purchase_rate, landing_cost, mrp, sale_rate, packing, supplier_name, gst_percent) 
              DO UPDATE SET current_stock = current_stock + excluded.current_stock,
                            rack = excluded.rack,
                            is_active = 1
            ''', [
              productId,
              item.batch.trim(),
              item.expiry,
              looseQty,
              item.pRate,
              trueLandingCost,
              item.mrp,
              item.sRate,
              item.packin,
              purchase.supplierName,
              item.gstPercent,
              item.rack,
              1,
            ]);

            await txn.insert('purchase_items', {
              'entry_no': finalEntryNo, 'product_id': productId, 'product_name': item.productName, 'extra': item.extra, 'batch': item.batch.trim(),
              'expiry': item.expiry, 'packin': item.packin, 'qty': item.qty, 'f_qty': item.fQty, 'mrp': item.mrp, 'p_rate': item.pRate, 'gross': item.gross,
              'disc_percent': item.discPercent, 'disc_amt': item.discAmt, 'net': item.net, 'gst_percent': item.gstPercent, 'gst_amt': item.gstAmt, 'total': item.total,
              'rack': item.rack, 'hsn_code': item.hsnCode, 's_disc_percent': item.sDiscPercent, 's_rate': item.sRate, 'l_cost': trueLandingCost,
            });

            await txn.rawUpdate('UPDATE product_master SET purchase_rate = ?, mrp = ?, sale_rate = ?, packing = ?, hsn_code = ? WHERE id = ?', [item.pRate, item.mrp, item.sRate, item.packin, item.hsnCode, productId]);
          }
          
          // 1. DO NOT DELETE ZERO STOCK ROWS! (Commented out or removed)
          // await txn.rawDelete('DELETE FROM stock_batches WHERE current_stock = 0');

          final int updatedRows = await txn.rawUpdate('UPDATE suppliers SET current_balance = current_balance + ? WHERE name = ? COLLATE NOCASE', [purchase.grandTotal, purchase.supplierName]);
          if (updatedRows == 0) {
            await txn.insert('suppliers', {'id': "SUP_${DateTime.now().millisecondsSinceEpoch}", 'name': purchase.supplierName, 'current_balance': purchase.grandTotal, 'phone': '', 'address': '', 'gst_in': '', 'dl_number': ''});
          }
      });

      // ---> THE FIX: Create a new object copy to bypass 'final' field restrictions <---
      final updatedPurchase = PurchaseEntry(
        entryNo: finalEntryNo,
        date: purchase.date,
        supplierName: purchase.supplierName,
        supInvNo: cleanInvoiceNo(purchase.supInvNo),
        supInvDate: purchase.supInvDate,
        doneBy: purchase.doneBy,
        invTotal: purchase.invTotal,
        remarks: purchase.remarks,
        days: purchase.days,
        items: purchase.items,
        subTotal: purchase.subTotal,
        discount: purchase.discount,
        otherCharge: purchase.otherCharge,
        roundOff: purchase.roundOff,
        grandTotal: purchase.grandTotal,
        financialYear: fy,
        paymentStatus: purchase.paymentStatus,
        paymentMode: purchase.paymentMode,
        paymentRemarks: purchase.paymentRemarks,
        paymentDate: purchase.paymentDate,
        paidAmount: purchase.paidAmount,
      );

      // --- POST-COMMIT IN-MEMORY STOCK SYNC ---
      // If Editing: First subtract the OLD purchase items from RAM
      if (existingOldItems.isNotEmpty) {
        for (var old in existingOldItems) {
          int oldPack = (old['packin'] as num?)?.toInt() ?? 1;
          int oldLoose = ((old['qty'] as num).toInt() + (old['f_qty'] as num).toInt()) * (oldPack > 0 ? oldPack : 1);
          String oldBatch = old['batch'].toString().trim().toUpperCase();
          String oldPId = old['product_id']?.toString() ?? "";

          int pIdx = _products.indexWhere((p) => 
            (p.id == oldPId || p.name.trim().toLowerCase() == old['product_name'].toString().trim().toLowerCase()) && 
            p.batch.trim().toUpperCase() == oldBatch
          );
          if (pIdx != -1) _products[pIdx].stock -= oldLoose;

          int mIdx = _productMaster.indexWhere((m) => 
            m.id == oldPId || m.name.trim().toLowerCase() == old['product_name'].toString().trim().toLowerCase()
          );
          if (mIdx != -1) _productMaster[mIdx].stock -= oldLoose;
        }
      }

      // Now add the NEW purchase items into RAM
      for (var item in purchase.items) {
        int looseAdded = (item.qty + item.fQty) * (item.packin > 0 ? item.packin : 1);
        String cleanBatchStr = item.batch.trim().toUpperCase();

        // 1. Update matching batch in _products
        int pIdx = _products.indexWhere((p) => 
          (p.id == item.id || p.name.trim().toLowerCase() == item.productName.trim().toLowerCase()) && 
          p.batch.trim().toUpperCase() == cleanBatchStr
        );

        if (pIdx != -1) {
          _products[pIdx].stock += looseAdded;
          _products[pIdx].purchaseRate = item.pRate;
          _products[pIdx].mrp = item.mrp;
          _products[pIdx].salePrice = item.sRate;
          _products[pIdx].landingCost = item.lCost;
        } else {
          _products.add(Product(
            id: item.id,
            name: item.productName,
            batch: item.batch.trim(),
            expiry: item.expiry,
            packSize: item.packin,
            stock: looseAdded,
            purchaseRate: item.pRate,
            landingCost: item.lCost,
            mrp: item.mrp,
            salePrice: item.sRate,
            gstPercent: item.gstPercent,
            rack: item.rack,
            supplier: purchase.supplierName,
          ));
        }

        // 2. Update overall stock in _productMaster
        int mIdx = _productMaster.indexWhere((m) => 
          m.id == item.id || m.name.trim().toLowerCase() == item.productName.trim().toLowerCase()
        );
        if (mIdx != -1) {
          _productMaster[mIdx].stock += looseAdded;
          _productMaster[mIdx].purchaseRate = item.pRate;
          _productMaster[mIdx].mrp = item.mrp;
          _productMaster[mIdx].salePrice = item.sRate;
        }
      }

      int idx = _purchases.indexWhere((p) => p.entryNo == finalEntryNo);
      if (idx != -1) {
        _purchases[idx] = updatedPurchase;
      } else {
        _purchases.insert(0, updatedPurchase);
        _todayPurchase += updatedPurchase.grandTotal;
        _todayPurchasesCount += 1;
      }
      _purchases.sort((a, b) => b.date.compareTo(a.date));
      if (_purchases.length > 50) _purchases.removeLast();

      _rebuildSearchIndex();
      notifyListeners();
      return finalEntryNo;
    } catch (e) {
      debugPrint("Save Purchase Error: $e");
      rethrow;
    }
  }


  Future<void> _checkStockIntegrityBeforeEdit({
    required sql.Transaction txn,
    required Map<String, int> oldImpact, // Stock added (+) or removed (-) by original entry
    required Map<String, int> newImpact, // Stock added (+) or removed (-) by new edited entry
  }) async {
    Map<String, int> netDelta = {};

    // 1. Revert the old impact
    oldImpact.forEach((key, value) {
      netDelta[key] = (netDelta[key] ?? 0) - value;
    });

    // 2. Apply the new impact
    newImpact.forEach((key, value) {
      netDelta[key] = (netDelta[key] ?? 0) + value;
    });

    // 3. Verify if the net result drops any stock below zero
    for (var entry in netDelta.entries) {
      if (entry.value < 0) { // We are trying to remove stock
        int requiredToRemove = entry.value.abs();
        String pId = entry.key.split('|')[0];
        String batch = entry.key.split('|')[1];

        // ---> THE RACE CONDITION FIX: Acquire a write lock on the row immediately <---
        await txn.rawUpdate(
            'UPDATE stock_batches SET current_stock = current_stock WHERE product_id = ? AND batch_number = ?',
            [pId, batch]
        );

        final stockCheck = await txn.rawQuery(
            'SELECT current_stock FROM stock_batches WHERE product_id = ? AND batch_number = ?',
            [pId, batch]
        );
        int liveStock = stockCheck.isNotEmpty ? (stockCheck.first['current_stock'] as num).toInt() : 0;

        // THE MASTER LOCK: Block the transaction and throw the popup
        if (liveStock < requiredToRemove) {
          final pNameRow = await txn.rawQuery('SELECT name FROM product_master WHERE id = ?', [pId]);
          String pName = pNameRow.isNotEmpty ? pNameRow.first['name']?.toString() ?? "Unknown Product" : "Unknown Product";
          int used = requiredToRemove - liveStock;

          // By throwing a String, Flutter drops the "Exception:" prefix in the UI popup
          throw "STOCK LOCK TRIGGERED!\n\nYou cannot save these changes for '$pName' (Batch: $batch).\n\nYour edit requires pulling $requiredToRemove loose units, but only $liveStock are currently available on the shelf.\n\nThe missing $used units have already been consumed elsewhere (Sales, Damages, or Adjustments).\n\nTo proceed, you must first reverse the entries where those $used units were used.";
        }
      }
    }
  }

  Future<String> _generateNextNoWithFY(sql.Transaction txn, String table, String column, String fy) async {
    String cleanColExpr = "CASE WHEN instr($column, '_') > 0 THEN substr($column, instr($column, '_') + 1) ELSE REPLACE(REPLACE(REPLACE($column, 'SRET-', ''), 'PRET-', ''), 'ADJ-', '') END";
    final List<Map<String, dynamic>> maxRes = await txn.rawQuery(
        "SELECT MAX(CAST($cleanColExpr AS INTEGER)) as max_no FROM $table WHERE financial_year = ?", [fy]);
    int maxInDb = (maxRes.first['max_no'] as num?)?.toInt() ?? 0;

    final List<Map<String, dynamic>> res = await txn.query(
      'voucher_sequences',
      where: 'voucher_type = ? AND financial_year = ?',
      whereArgs: [table, fy],
    );

    int lastSeq = 0;
    if (res.isNotEmpty) {
      lastSeq = (res.first['last_sequence'] as int? ?? 0);
    }

    int effectiveLast = maxInDb;
    if (res.isNotEmpty && maxInDb > 0) {
      effectiveLast = maxInDb > lastSeq ? maxInDb : lastSeq;
    }
    int nextSeq = effectiveLast + 1;

    if (res.isNotEmpty) {
      await txn.update(
        'voucher_sequences',
        {'last_sequence': nextSeq},
        where: 'voucher_type = ? AND financial_year = ?',
        whereArgs: [table, fy],
      );
    } else {
      await txn.insert('voucher_sequences', {
        'voucher_type': table,
        'financial_year': fy,
        'last_sequence': nextSeq,
      });
    }

    return nextSeq.toString();
  }


  Future<String> saveStockAdjustment(StockAdjustment adj, {bool isEdit = false}) async {
    final db = kIsWeb ? null : await DbHelper.instance.database;
    String finalEntryNo = adj.entryNo;
    String fy = adj.financialYear.isEmpty ? _selectedFinancialYear : adj.financialYear;
    try {
      if (db != null) {
        await db.transaction((txn) async {
          if (finalEntryNo.isEmpty || finalEntryNo == "AUTO") {
            finalEntryNo = await _generateNextNoWithFY(txn, 'stock_adjustments', 'entry_no', fy);
          }

          // Auto-resolve batch for any adjustment item missing batch number
          for (var item in adj.items) {
            if (item.product.batch.trim().isEmpty) {
              final availableBatch = _products.where((p) => p.id == item.product.id && p.stock > 0 && p.batch.isNotEmpty).firstOrNull
                  ?? _products.where((p) => p.id == item.product.id && p.batch.isNotEmpty).firstOrNull;
              if (availableBatch != null) {
                item.product.batch = availableBatch.batch;
                if (item.product.expiry.isEmpty) {
                  item.product.expiry = availableBatch.expiry;
                }
              }
            }
          }

          // --- NEW: UNIVERSAL PRE-FLIGHT STOCK CHECK ---
          Map<String, int> oldImpact = {};
          Map<String, int> newImpact = {};

          if (isEdit && finalEntryNo.isNotEmpty && finalEntryNo != "AUTO") {
            final List<Map<String, dynamic>> oldItems = await txn.query('stock_adjustment_items', where: 'adjustment_no = ?', whereArgs: [finalEntryNo]);
            for (var old in oldItems) {
              // Adjustments can be positive or negative
              int qty = (old['qty'] as num).toInt();
              oldImpact["${old['product_id']}|${old['batch_number']}"] = (oldImpact["${old['product_id']}|${old['batch_number']}"] ?? 0) + qty;
            }
          }
          for (var item in adj.items) {
            newImpact["${item.product.id}|${item.product.batch}"] = (newImpact["${item.product.id}|${item.product.batch}"] ?? 0) + item.qty;
          }
          await _checkStockIntegrityBeforeEdit(txn: txn, oldImpact: oldImpact, newImpact: newImpact);
          // ---------------------------------------------

          if (isEdit) {
            final List<Map<String, dynamic>> oldItems = await txn.query('stock_adjustment_items', where: 'adjustment_no = ?', whereArgs: [finalEntryNo]);
            for (var old in oldItems) {
              int qtyToRevert = (old['qty'] as num).toInt();
              // Reverting an adjustment means subtracting the variance that was previously added
              await txn.rawUpdate(
                  'UPDATE stock_batches SET current_stock = current_stock - ? WHERE product_id = ? AND batch_number = ?',
                  [qtyToRevert, old['product_id'], old['batch_number']]
              );

              final pIndex = _products.indexWhere((p) => p.id == old['product_id'] && p.batch == old['batch_number']);
              if (pIndex != -1) _products[pIndex].stock -= qtyToRevert;

              final mIndex = _productMaster.indexWhere((p) => p.id == old['product_id']);
              if (mIndex != -1) _productMaster[mIndex].stock -= qtyToRevert;
            }
            await txn.delete('stock_adjustment_items', where: 'adjustment_no = ?', whereArgs: [finalEntryNo]);
          }

          await txn.insert('stock_adjustments', {
            'entry_no': finalEntryNo,
            'date': adj.date.toIso8601String(),
            'done_by': adj.doneBy,
            'reason': adj.reason,
            'grand_total': adj.grandTotal,
            'financial_year': fy,
          }, conflictAlgorithm: sql.ConflictAlgorithm.replace);

          for (var item in adj.items) {
            if (item.qty < 0) {
              final List<Map<String, dynamic>> liveStockCheck = await txn.rawQuery(
                  'SELECT current_stock FROM stock_batches WHERE product_id = ? AND batch_number = ?',
                  [item.product.id, item.product.batch]
              );

              if (liveStockCheck.isEmpty) {
                throw Exception("Transaction Aborted: Batch ${item.product.batch} not found in database.");
              }

              int liveStock = (liveStockCheck.first['current_stock'] as num).toInt();

              if (liveStock + item.qty < 0) {
                throw Exception("Transaction Aborted: Cannot deduct ${item.qty.abs()} units of ${item.product.name}. Only $liveStock remaining.");
              }
            }

            await txn.insert('stock_adjustment_items', {
              'adjustment_no': finalEntryNo,
              'product_id': item.product.id,
              'batch_number': item.product.batch,
              'qty': item.qty,
              'purchase_rate': item.purchaseRate,
              'total': item.total,
            });

            if (item.qty < 0) {
              final int affected = await txn.rawUpdate(
                  'UPDATE stock_batches SET current_stock = current_stock + ? WHERE product_id = ? AND batch_number = ? AND current_stock >= ? COLLATE NOCASE',
                  [item.qty, item.product.id, item.product.batch, item.qty.abs()]
              );
              if (affected == 0) {
                throw "STOCK RACE CONDITION!\n\nUnits of '${item.product.name}' (Batch: ${item.product.batch}) were modified simultaneously.\n\nTransaction aborted.";
              }
            } else {
              // ATOMIC UPDATE OR INSERT FOR POSITIVE ADJUSTMENTS
              final int affected = await txn.rawUpdate(
                  'UPDATE stock_batches SET current_stock = current_stock + ? WHERE product_id = ? AND batch_number = ? COLLATE NOCASE',
                  [item.qty, item.product.id, item.product.batch]
              );

              // If the batch row was missing or previously deleted, re-insert it
              if (affected == 0) {
                await txn.insert('stock_batches', {
                  'product_id': item.product.id,
                  'batch_number': item.product.batch,
                  'expiry_date': item.product.expiry.isNotEmpty ? item.product.expiry : "--/--",
                  'current_stock': item.qty,
                  'purchase_rate': item.purchaseRate,
                  'landing_cost': item.purchaseRate,
                  'mrp': item.product.mrp,
                  'sale_rate': item.product.salePrice > 0 ? item.product.salePrice : item.product.mrp,
                  'packing': item.product.packSize > 0 ? item.product.packSize : 1,
                  'rack': item.product.rack,
                  'is_active': 1,
                });
              }
            }

            final pIndex = _products.indexWhere((p) => p.id == item.product.id && p.batch == item.product.batch);
            if (pIndex != -1) _products[pIndex].stock += item.qty;

            final mIndex = _productMaster.indexWhere((p) => p.id == item.product.id);
            if (mIndex != -1) _productMaster[mIndex].stock += item.qty;
          }
        });
      }

      final savedAdj = StockAdjustment(
        entryNo: finalEntryNo,
        date: adj.date,
        doneBy: adj.doneBy,
        reason: adj.reason,
        items: adj.items,
        grandTotal: adj.grandTotal,
        financialYear: fy,
      );

      // Always update the memory list to keep UI in sync
      int idx = _adjustments.indexWhere((a) => a.entryNo == finalEntryNo);
      if (idx != -1) {
        _adjustments[idx] = savedAdj;
      } else {
        _adjustments.insert(0, savedAdj);
      }

      notifyListeners();
      return finalEntryNo;
    } catch (e) {
      debugPrint("Save Stock Adjustment Error: $e");
      rethrow;
    }
  }

  Future<void> deleteStockAdjustment(String entryNo) async {
    final db = kIsWeb ? null : await DbHelper.instance.database;
    if (db == null) return;

    try {
      await db.transaction((txn) async {
        // 1. Idempotency Guard: Verify adjustment is still active
        final check = await txn.query(
          'stock_adjustments',
          columns: ['is_deleted'],
          where: 'entry_no = ?',
          whereArgs: [entryNo],
        );

        if (check.isEmpty || check.first['is_deleted'] == 1) return;

        final List<Map<String, dynamic>> items = await txn.query(
          'stock_adjustment_items', 
          where: 'adjustment_no = ?', 
          whereArgs: [entryNo]
        );

        // 2. Pre-flight check: If the adjustment originally ADDED stock (qty > 0),
        // deleting it requires REMOVING stock from the shelf. Verify stock exists.
        for (var item in items) {
          int qty = (item['qty'] as num).toInt();
          if (qty > 0) {
            final String pId = item['product_id'];
            final String batch = item['batch_number'];

            await txn.rawUpdate(
              'UPDATE stock_batches SET current_stock = current_stock WHERE product_id = ? AND batch_number = ?',
              [pId, batch]
            );

            final stockCheck = await txn.rawQuery(
              'SELECT current_stock FROM stock_batches WHERE product_id = ? AND batch_number = ?',
              [pId, batch]
            );
            int liveStock = stockCheck.isNotEmpty ? (stockCheck.first['current_stock'] as num).toInt() : 0;

            if (liveStock < qty) {
              final pNameRow = await txn.rawQuery('SELECT name FROM product_master WHERE id = ?', [pId]);
              String pName = pNameRow.isNotEmpty ? pNameRow.first['name']?.toString() ?? "Unknown Product" : "Unknown Product";
              int consumed = qty - liveStock;
              throw "DELETION BLOCKED!\n\nCannot delete Adjustment #$entryNo.\n\nThis adjustment added $qty units of '$pName' (Batch: $batch), but $consumed units have already been consumed.\n\nReverse the dependent sales first.";
            }
          }
        }

        // 3. Apply Reversal
        for (var item in items) {
          final String pId = item['product_id'];
          final String batch = item['batch_number'];
          final int qty = (item['qty'] as num).toInt();

          // If qty was positive (+10), subtract 10. If qty was negative (-10), add 10.
          if (qty > 0) {
            final int affected = await txn.rawUpdate(
              'UPDATE stock_batches SET current_stock = current_stock - ? WHERE product_id = ? AND batch_number = ? AND current_stock >= ? COLLATE NOCASE',
              [qty, pId, batch, qty]
            );
            if (affected == 0) throw "Stock race condition on adjustment deletion.";
          } else {
            await txn.rawUpdate(
              'UPDATE stock_batches SET current_stock = current_stock + ? WHERE product_id = ? AND batch_number = ? COLLATE NOCASE',
              [qty.abs(), pId, batch]
            );
          }

          // Sync in-memory lists
          final pIndex = _products.indexWhere((p) => p.id == pId && p.batch == batch);
          if (pIndex != -1) _products[pIndex].stock -= qty;
          final mIndex = _productMaster.indexWhere((p) => p.id == pId);
          if (mIndex != -1) _productMaster[mIndex].stock -= qty;
        }

        // 4. Mark as Deleted
        await txn.update('stock_adjustments', {'is_deleted': 1}, where: 'entry_no = ?', whereArgs: [entryNo]);
      });

      _adjustments.removeWhere((adj) => adj.entryNo == entryNo);
      notifyListeners();
    } catch (e) {
      debugPrint("Delete Stock Adjustment Error: $e");
      rethrow;
    }
  }

  Future<void> saveWriteOff(StockWriteOff writeOff) async {
    if (!kIsWeb) {
      final db = await DbHelper.instance.database;
      String fy = writeOff.financialYear.isEmpty ? _selectedFinancialYear : writeOff.financialYear;
      try {
        await db.transaction((txn) async {

          // 1. LIVE DB STOCK CHECK (THE STRICT LOCK)
          final List<Map<String, dynamic>> liveStockCheck = await txn.rawQuery(
              'SELECT current_stock FROM stock_batches WHERE product_id = ? AND batch_number = ?',
              [writeOff.product.id, writeOff.product.batch]
          );

          if (liveStockCheck.isEmpty) {
            throw Exception("Transaction Aborted: Batch ${writeOff.product.batch} not found in database.");
          }

          int liveStock = (liveStockCheck.first['current_stock'] as num).toInt();

          if (liveStock < writeOff.quantity) {
            throw Exception("Transaction Aborted: Cannot write-off ${writeOff.quantity} units of ${writeOff.product.name}. Only $liveStock remaining.");
          }

          // 2. EXECUTE WRITE OFF
          await txn.insert('stock_write_offs', {
            'id': writeOff.id,
            'date': writeOff.date.toIso8601String(),
            'product_id': writeOff.product.id,
            'batch_number': writeOff.product.batch,
            'quantity': writeOff.quantity,
            'reason': writeOff.reason,
            'loss_value': writeOff.lossValue,
            'financial_year': fy,
          });

          // 3. UPDATE DB STOCK (WITH MASTER LOCK)
          final int affected = await txn.rawUpdate(
              'UPDATE stock_batches SET current_stock = current_stock - ? WHERE product_id = ? AND batch_number = ? AND current_stock >= ? COLLATE NOCASE',
              [writeOff.quantity, writeOff.product.id, writeOff.product.batch, writeOff.quantity]
          );

          if (affected == 0) {
            throw "STOCK RACE CONDITION!\n\nSomeone else just sold or moved the units of '${writeOff.product.name}' (Batch: ${writeOff.product.batch}) at the same time.\n\nTransaction aborted.";
          }

          // 4. SYNC IN-MEMORY STATE
          final pIndex = _products.indexWhere((p) => p.id == writeOff.product.id && p.batch == writeOff.product.batch);
          if (pIndex != -1) _products[pIndex].stock -= writeOff.quantity;
          final mIndex = _productMaster.indexWhere((p) => p.id == writeOff.product.id);
          if (mIndex != -1) _productMaster[mIndex].stock -= writeOff.quantity;

        });

        _writeOffs.add(writeOff);
        notifyListeners();
      } catch (e) {
        debugPrint("Save Write-Off Error: $e");
        rethrow; // Throws back to UI to trigger the SnackBar error
      }
    }
  }

  Future<void> deleteWriteOff(String id) async {
    final db = kIsWeb ? null : await DbHelper.instance.database;
    if (db == null) return;

    try {
      await db.transaction((txn) async {
        // 1. Verify record exists
        final records = await txn.query(
          'stock_write_offs',
          where: 'id = ?',
          whereArgs: [id],
        );

        if (records.isEmpty) return;

        final row = records.first;
        final String productId = row['product_id']?.toString() ?? '';
        final String batch = row['batch_number']?.toString() ?? '';
        final int quantity = (row['quantity'] as num?)?.toInt() ?? 0;

        // 2. Restore stock to stock_batches
        if (productId.isNotEmpty && quantity > 0) {
          await txn.rawUpdate(
            'UPDATE stock_batches SET current_stock = current_stock + ? WHERE product_id = ? AND batch_number = ? COLLATE NOCASE',
            [quantity, productId, batch],
          );

          // 3. In-memory sync
          final pIdx = _products.indexWhere((p) => p.id == productId && p.batch.toUpperCase() == batch.toUpperCase());
          if (pIdx != -1) _products[pIdx].stock += quantity;

          final mIdx = _productMaster.indexWhere((p) => p.id == productId);
          if (mIdx != -1) _productMaster[mIdx].stock += quantity;
        }

        // 4. Delete row
        await txn.delete('stock_write_offs', where: 'id = ?', whereArgs: [id]);
      });

      _writeOffs.removeWhere((w) => w.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint("Delete Write-Off Error: $e");
      rethrow;
    }
  }

  Future<void> deleteSale(String entryNo) async {
    final db = kIsWeb ? null : await DbHelper.instance.database;
    if (db == null) return;

    try {
      await db.transaction((txn) async {
        // 1. Idempotency Check: Don't process if already deleted
        final check = await txn.query(
          'sales_invoices',
          columns: ['is_deleted', 'customer_acc', 'grand_total', 'rcvd_amt', 'patient'],
          where: 'entry_no = ? OR CAST(entry_no AS TEXT) = ?',
          whereArgs: [entryNo, entryNo],
        );

        if (check.isEmpty || check.first['is_deleted'] == 1) return;

        final inv = check.first;
        final String customerAcc = inv['customer_acc']?.toString() ?? "Cash";
        final String patientName = inv['patient']?.toString() ?? "";
        final double grandTotal = (inv['grand_total'] as num?)?.toDouble() ?? 0.0;
        final double rcvdAmt = (inv['rcvd_amt'] as num?)?.toDouble() ?? 0.0;
        final double unpaidCredit = grandTotal - rcvdAmt;

        // 2. Reverse Customer Ledger Balance if Credit Sale
        if (customerAcc.toUpperCase() != "CASH" && unpaidCredit > 0 && patientName.isNotEmpty) {
          await txn.rawUpdate(
            'UPDATE patients SET current_balance = current_balance - ? WHERE name = ? COLLATE NOCASE',
            [unpaidCredit, patientName],
          );
        }

        // 3. Restore Physical Shelf Stock
        final List<Map<String, dynamic>> items = await txn.query(
          'sales_items', 
          where: 'invoice_no = ? OR CAST(invoice_no AS TEXT) = ?', 
          whereArgs: [entryNo, entryNo]
        );

        for (var item in items) {
          int totalUnits = (item['qty'] as num?)?.toInt() ?? 0;
          String pId = item['product_id']?.toString() ?? '';
          String batch = item['batch_number']?.toString() ?? '';

          if (pId.isEmpty) {
            final prod = await txn.query('product_master', columns: ['id'], where: 'name = ? COLLATE NOCASE', whereArgs: [item['product_name']]);
            if (prod.isNotEmpty) pId = prod.first['id'].toString();
          }

          if (pId.isNotEmpty && totalUnits > 0) {
            final int affected = await txn.rawUpdate(
              'UPDATE stock_batches SET current_stock = current_stock + ? WHERE product_id = ? AND batch_number = ? COLLATE NOCASE',
              [totalUnits, pId, batch],
            );

            if (affected == 0 && batch.isNotEmpty) {
              await txn.insert('stock_batches', {
                'product_id': pId,
                'batch_number': batch,
                'current_stock': totalUnits,
                'mrp': (item['mrp'] as num?)?.toDouble() ?? 0.0,
                'purchase_rate': (item['purchase_rate'] as num?)?.toDouble() ?? 0.0,
                'expiry_date': item['expiry_date']?.toString() ?? '',
              });
            }

            // In-Memory sync
            final pIndex = _products.indexWhere((p) => p.id == pId && p.batch.toUpperCase() == batch.toUpperCase());
            if (pIndex != -1) _products[pIndex].stock += totalUnits;

            final mIndex = _productMaster.indexWhere((p) => p.id == pId);
            if (mIndex != -1) _productMaster[mIndex].stock += totalUnits;
          }
        }

        // 4. Mark Invoice as Deleted
        await txn.update('sales_invoices', {'is_deleted': 1}, where: 'entry_no = ? OR CAST(entry_no AS TEXT) = ?', whereArgs: [entryNo, entryNo]);
      });

      // Update in-memory cache
      int idx = _sales.indexWhere((s) => s.entryNo == entryNo || int.tryParse(s.entryNo) == int.tryParse(entryNo));
      if (idx != -1) {
        SaleInvoice s = _sales[idx];
        _sales[idx] = SaleInvoice(
          entryNo: s.entryNo, date: s.date, customerAcc: s.customerAcc,
          patient: s.patient, mobile: s.mobile, doctor: s.doctor,
          doctorRegNo: s.doctorRegNo, specialOrderJson: s.specialOrderJson,
          taxType: s.taxType, days: s.days, items: s.items,
          subTotal: s.subTotal, discountPercent: s.discountPercent,
          discount: s.discount, additionalDiscount: s.additionalDiscount,
          otherCharge: s.otherCharge, rcvdAmt: s.rcvdAmt, roundOff: s.roundOff,
          grandTotal: s.grandTotal, agent: s.agent, expectingDate: s.expectingDate,
          secondaryAcc: s.secondaryAcc, secondaryAmt: s.secondaryAmt,
          financialYear: s.financialYear, isPaid: s.isPaid, isDeleted: true,
        );
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Delete Sale Error: $e");
      rethrow;
    }
  }

  Future<void> deletePurchase(String entryNo) async {
    final db = kIsWeb ? null : await DbHelper.instance.database;
    if (db == null) return;
    try {
      await db.transaction((txn) async {
        // 1. Idempotency Check: Abort if already deleted
        final check = await txn.query(
          'purchase_entries',
          columns: ['is_deleted', 'supplier_name', 'grand_total', 'paid_amount', 'payment_status'],
          where: 'entry_no = ?',
          whereArgs: [entryNo],
        );
        if (check.isEmpty || check.first['is_deleted'] == 1) return;

        final purHeader = check.first;
        final String supplierName = purHeader['supplier_name']?.toString() ?? "";
        final double grandTotal = (purHeader['grand_total'] as num?)?.toDouble() ?? 0.0;

        final List<Map<String, dynamic>> items = await txn.query(
          'purchase_items', 
          where: 'entry_no = ?', 
          whereArgs: [entryNo]
        );
        
        // Safety check before committing database changes:
        final existingEntry = _purchases.firstWhere(
          (p) => p.entryNo == entryNo,
          orElse: () => PurchaseEntry(
            entryNo: entryNo,
            date: DateTime.now(),
            supplierName: supplierName,
            supInvNo: '',
            supInvDate: DateTime.now(),
            doneBy: '',
            invTotal: grandTotal,
            remarks: '',
            days: 0,
            items: items.map((i) => PurchaseItem(
              id: i['product_id']?.toString() ?? '',
              productName: i['product_name']?.toString() ?? '',
              batch: i['batch']?.toString() ?? '',
              packin: (i['packin'] as num?)?.toInt() ?? 1,
              qty: (i['qty'] as num?)?.toInt() ?? 0,
              fQty: (i['f_qty'] as num?)?.toInt() ?? 0,
            )).toList(),
            subTotal: 0,
            discount: 0,
            otherCharge: 0,
            roundOff: 0,
            grandTotal: grandTotal,
            financialYear: '',
          ),
        );

        final Map<String, PurchaseItem> itemMap = {};

        for (var oldItem in existingEntry.items) {
          String pId = oldItem.id;
          if (pId.isEmpty) {
            final prod = await txn.query('product_master', columns: ['id'], where: 'name = ? COLLATE NOCASE', whereArgs: [oldItem.productName]);
            if (prod.isNotEmpty) pId = prod.first['id'].toString();
          }
          // Check how many units of this specific product/batch have been sold since this purchase
          double totalSold = await _calculateUnitsSoldForBatch(pId.isNotEmpty ? pId : oldItem.id, oldItem.batch, txn);
          double newProposedQty = ((itemMap[oldItem.id]?.qty ?? 0) * (itemMap[oldItem.id]?.packin ?? 1)).toDouble();

          if (newProposedQty < totalSold) {
            throw Exception("Cannot reduce quantity below already sold units! ($totalSold units already billed out for batch ${oldItem.batch})");
          }
        }

        // 2. Pre-Flight Deletion Guard: Check consumed stock using direct product_id
        for (var item in items) {
          String productId = item['product_id']?.toString() ?? '';
          if (productId.isEmpty) {
            final prod = await txn.query('product_master', columns: ['id'], where: 'name = ? COLLATE NOCASE', whereArgs: [item['product_name']]);
            if (prod.isNotEmpty) productId = prod.first['id'].toString();
          }

          if (productId.isNotEmpty) {
            final int pPackin = (item['packin'] as num?)?.toInt() ?? 1;
            final int totalQty = ((item['qty'] as num).toInt() + (item['f_qty'] as num).toInt()) * (pPackin > 0 ? pPackin : 1);
            final String batch = item['batch']?.toString() ?? '';

            // Lock row and fetch live batch stock
            await txn.rawUpdate(
              'UPDATE stock_batches SET current_stock = current_stock WHERE product_id = ? AND batch_number = ?',
              [productId, batch]
            );

            final stockCheck = await txn.rawQuery(
              'SELECT current_stock FROM stock_batches WHERE product_id = ? AND batch_number = ? COLLATE NOCASE',
              [productId, batch]
            );
            int liveStock = stockCheck.isNotEmpty ? (stockCheck.first['current_stock'] as num).toInt() : 0;

            if (liveStock < totalQty) {
              int consumed = totalQty - liveStock;
              throw "DELETION BLOCKED!\n\nYou cannot delete Purchase #$entryNo.\n\nThis purchase added $totalQty units of '${item['product_name']}' (Batch: $batch) to the shelf, but $consumed of those units have already been sold, returned, or adjusted.\n\nTo delete this purchase, you must first delete the entries where those $consumed units were consumed.";
            }
          }
        }

        // 3. Revert Stock using verified product_id
        for (var item in items) {
          String productId = item['product_id']?.toString() ?? '';
          if (productId.isEmpty) {
            final prod = await txn.query('product_master', columns: ['id'], where: 'name = ? COLLATE NOCASE', whereArgs: [item['product_name']]);
            if (prod.isNotEmpty) productId = prod.first['id'].toString();
          }

          if (productId.isNotEmpty) {
            final int pPackin = (item['packin'] as num?)?.toInt() ?? 1;
            final int totalQty = ((item['qty'] as num).toInt() + (item['f_qty'] as num).toInt()) * (pPackin > 0 ? pPackin : 1);
            final String batch = item['batch']?.toString() ?? '';

            final int affected = await txn.rawUpdate(
              'UPDATE stock_batches SET current_stock = current_stock - ? WHERE product_id = ? AND batch_number = ? AND current_stock >= ? COLLATE NOCASE',
              [totalQty, productId, batch, totalQty]
            );

            if (affected == 0) {
              throw "STOCK RACE CONDITION!\n\nUnits of '${item['product_name']}' (Batch: $batch) were just sold or moved.\n\nTransaction aborted.";
            }

            await txn.rawDelete(
              'DELETE FROM stock_batches WHERE product_id = ? AND batch_number = ? AND current_stock = 0', 
              [productId, batch]
            );

            // In-Memory Reconcile
            final pIndex = _products.indexWhere((p) => p.id == productId && p.batch.toUpperCase() == batch.toUpperCase());
            if (pIndex != -1) {
              _products[pIndex].stock -= totalQty;
              if (_products[pIndex].stock <= 0) _products.removeAt(pIndex);
            }
            final mIndex = _productMaster.indexWhere((p) => p.id == productId);
            if (mIndex != -1) _productMaster[mIndex].stock -= totalQty;
          }
        }

        // 4. Reverse Supplier Balance
        if (supplierName.isNotEmpty && grandTotal > 0) {
          await txn.rawUpdate(
            'UPDATE suppliers SET current_balance = current_balance - ? WHERE name = ? COLLATE NOCASE',
            [grandTotal, supplierName],
          );
        }

        // 5. Mark as Deleted
        await txn.update('purchase_entries', {'is_deleted': 1}, where: 'entry_no = ?', whereArgs: [entryNo]);
      });

      _purchases.removeWhere((p) => p.entryNo == entryNo);
      _rebuildSearchIndex();
      await fetchAccounts();
      notifyListeners();
    } catch (e) { 
      debugPrint("Delete Purchase Error: $e"); 
      rethrow;
    }
  }

  // ---> BRAND NEW METHOD: Safely Deletes Sales Returns <---
  Future<void> deleteSaleReturn(String entryNo) async {
    final db = kIsWeb ? null : await DbHelper.instance.database;
    if (db == null) return;
    try {
      await db.transaction((txn) async {
        // 1. Idempotency Check: Abort if already deleted
        final check = await txn.query(
          'sales_return_invoices',
          columns: ['is_deleted', 'patient', 'grand_total', 'customer_acc', 'is_imported'],
          where: 'entry_no = ?',
          whereArgs: [entryNo],
        );
        if (check.isEmpty || check.first['is_deleted'] == 1) return;

        final returnHeader = check.first;
        final bool isImported = (returnHeader['is_imported'] as int?) == 1;
        final String patientName = returnHeader['patient']?.toString() ?? "";
        final double grandTotal = (returnHeader['grand_total'] as num?)?.toDouble() ?? 0.0;

        final List<Map<String, dynamic>> items = await txn.query(
          'sales_return_items', 
          where: 'return_no = ?', 
          whereArgs: [entryNo]
        );
        
        // 2. Pre-Flight Deletion Guard: Check if returned stock is still on the shelf
        if (!isImported) {
          for (var item in items) {
            final String productId = item['product_id']?.toString() ?? '';
            final String batch = item['batch_number']?.toString() ?? '';
            final int qty = (item['quantity'] as num?)?.toInt() ?? 0;

            if (productId.isNotEmpty && qty > 0) {
              await txn.rawUpdate(
                'UPDATE stock_batches SET current_stock = current_stock WHERE product_id = ? AND batch_number = ?',
                [productId, batch]
              );

              final stockCheck = await txn.rawQuery(
                'SELECT current_stock FROM stock_batches WHERE product_id = ? AND batch_number = ? COLLATE NOCASE',
                [productId, batch]
              );
              int liveStock = stockCheck.isNotEmpty ? (stockCheck.first['current_stock'] as num).toInt() : 0;

              if (liveStock < qty) {
                final pRes = await txn.query('product_master', columns: ['name'], where: 'id = ?', whereArgs: [productId]);
                String pName = pRes.isNotEmpty ? pRes.first['name'].toString() : "Unknown Product";
                int consumed = qty - liveStock;
                throw "DELETION BLOCKED!\n\nCannot delete Sales Return #$entryNo.\n\n$qty units of '$pName' (Batch: $batch) were returned, but $consumed units have already been sold or moved.\n\nYou must reverse the dependent sales before deleting this return.";
              }
            }
          }
        }

        // 3. Reverse Stock (Subtract returned units atomically)
        if (!isImported) {
          for (var item in items) {
            final String productId = item['product_id']?.toString() ?? '';
            final String batch = item['batch_number']?.toString() ?? '';
            final int qty = (item['quantity'] as num?)?.toInt() ?? 0;

            if (productId.isNotEmpty && qty > 0) {
              final int affected = await txn.rawUpdate(
                'UPDATE stock_batches SET current_stock = current_stock - ? WHERE product_id = ? AND batch_number = ? AND current_stock >= ? COLLATE NOCASE',
                [qty, productId, batch, qty]
              );

              if (affected == 0) {
                throw "STOCK RACE CONDITION!\n\nUnits returned under '$batch' were just sold.\n\nTransaction aborted.";
              }

              final pIndex = _products.indexWhere((p) => p.id == productId && p.batch.toUpperCase() == batch.toUpperCase());
              if (pIndex != -1) _products[pIndex].stock -= qty;
              final mIndex = _productMaster.indexWhere((p) => p.id == productId);
              if (mIndex != -1) _productMaster[mIndex].stock -= qty;
            }
          }
        }

        // 4. Reverse Patient/Customer Credit Balance
        if (patientName.isNotEmpty && grandTotal > 0) {
          await txn.rawUpdate(
            'UPDATE patients SET current_balance = current_balance + ? WHERE name = ? COLLATE NOCASE',
            [grandTotal, patientName],
          );
        }

        // 5. Mark as Deleted
        await txn.update('sales_return_invoices', {'is_deleted': 1}, where: 'entry_no = ?', whereArgs: [entryNo]);
      });
      
      _saleReturns.removeWhere((s) => s.entryNo == entryNo);
      _rebuildSearchIndex();
      notifyListeners();
    } catch (e) {
      debugPrint("Delete Sale Return Error: $e");
      rethrow;
    }
  }

  // ---> BRAND NEW METHOD: Safely Deletes Purchase Returns <---
  Future<void> deletePurchaseReturn(String entryNo) async {
    final db = kIsWeb ? null : await DbHelper.instance.database;
    if (db == null) return;
    try {
      await db.transaction((txn) async {
        // 1. Idempotency Check
        final check = await txn.query(
          'purchase_return_entries', 
          columns: ['is_deleted', 'supplier_name', 'grand_total', 'is_imported'],
          where: 'entry_no = ?', 
          whereArgs: [entryNo]
        );
        if (check.isEmpty || check.first['is_deleted'] == 1) return;

        final bool isImported = (check.first['is_imported'] as int?) == 1;
        final double grandTotal = (check.first['grand_total'] as num?)?.toDouble() ?? 0.0;
        final String supplierName = check.first['supplier_name']?.toString() ?? "";

        // 2. Restore Stock including Free Goods
        if (!isImported) {
          final List<Map<String, dynamic>> items = await txn.query(
            'purchase_return_items', 
            where: 'entry_no = ?', 
            whereArgs: [entryNo]
          );
          for (var item in items) {
            final mRes = await txn.query(
              'product_master', 
              columns: ['id'], 
              where: 'name = ? COLLATE NOCASE', 
              whereArgs: [item['product_name']]
            );
            if (mRes.isNotEmpty) {
              final String productId = mRes.first['id'].toString();
              int packin = (item['packin'] as num?)?.toInt() ?? 1;
              int looseQty = (item['loose_qty'] as num?)?.toInt() ?? 0;
              int qty = (item['qty'] as num?)?.toInt() ?? 0;
              int fQty = (item['f_qty'] as num?)?.toInt() ?? 0;

              // Restore (Billed + Free) * packin + Loose
              final int totalUnitsToRestore = ((qty + fQty) * (packin > 0 ? packin : 1)) + looseQty;

              await txn.rawUpdate(
                'UPDATE stock_batches SET current_stock = current_stock + ? WHERE product_id = ? AND batch_number = ? COLLATE NOCASE',
                [totalUnitsToRestore, productId, item['batch']]
              );

              final pIndex = _products.indexWhere((p) => p.id == productId && p.batch.toUpperCase() == item['batch'].toString().toUpperCase());
              if (pIndex != -1) _products[pIndex].stock += totalUnitsToRestore;
              final mIndex = _productMaster.indexWhere((p) => p.id == productId);
              if (mIndex != -1) _productMaster[mIndex].stock += totalUnitsToRestore;
            }
          }
        }

        // 3. Symmetrically Restore Supplier Balance
        if (supplierName.isNotEmpty && grandTotal > 0) {
          await txn.rawUpdate(
            'UPDATE suppliers SET current_balance = current_balance + ? WHERE name = ? COLLATE NOCASE',
            [grandTotal, supplierName]
          );
        }

        await txn.update('purchase_return_entries', {'is_deleted': 1}, where: 'entry_no = ?', whereArgs: [entryNo]);
      });
      
      _purchaseReturns.removeWhere((p) => p.entryNo == entryNo);
      notifyListeners();
    } catch (e) {
      debugPrint("Delete Purchase Return Error: $e");
      rethrow;
    }
  }


  String? canDeletePurchase(PurchaseEntry purchaseEntry) {
    // Accumulate total loose units per product+batch in this bill
    Map<String, int> billBatchTotals = {};
    Map<String, int> packinMap = {};

    for (var item in purchaseEntry.items) {
      String key = "${item.productName.toLowerCase().trim()}|${item.batch.toLowerCase().trim()}";
      int pack = item.packin > 0 ? item.packin : 1;
      int lineLoose = (item.qty + item.fQty) * pack;
      billBatchTotals[key] = (billBatchTotals[key] ?? 0) + lineLoose;
      packinMap[key] = pack;
    }

    for (var entry in billBatchTotals.entries) {
      final keyParts = entry.key.split('|');
      final pName = keyParts[0];
      final pBatch = keyParts[1];
      final totalLooseToSubtract = entry.value;
      final pack = packinMap[entry.key] ?? 1;

      final product = _products.firstWhere(
        (p) => p.name.toLowerCase().trim() == pName &&
               p.batch.toLowerCase().trim() == pBatch,
        orElse: () => Product(id: "", name: pName, batch: pBatch, stock: 0),
      );

      if (totalLooseToSubtract > product.stock) {
        int usedLoose = totalLooseToSubtract - product.stock;
        int minStrips = (usedLoose / pack).ceil();

        return "Delete Blocked!\n\nYou cannot delete this purchase because '${product.name}' (Batch: $pBatch) has actively been sold or adjusted.\n\n• Units consumed: $usedLoose loose units.\n• Minimum required: $minStrips strips.\n\nTo delete this, you must first delete the dependent Sales or Damage entries.";
      }
    }
    return null;
  }

  /// The Universal "Used Anywhere" Checker
  /// Returns TRUE if it is safe to remove the requested quantity.
  /// Returns FALSE if the quantity has already been used (sold, returned, damaged).
  bool canSafelyReduceStock(String id, String batch, int quantityBeingRemoved) {
    // 1. Find the current stock for this specific batch
    final product = _products.firstWhere(
          (p) => p.id == id && p.batch == batch,
      // If the item doesn't exist in inventory, assume stock is 0
      orElse: () => Product(id: id, name: "Unknown", batch: batch, stock: 0),
    );

    // 2. The Universal Equation
    if (quantityBeingRemoved > product.stock) {
      return false; // Action Blocked!
    }

    return true; // Safe to proceed!
  }

  String? validatePurchaseEdit(PurchaseEntry oldPurchase, List<PurchaseItem> updatedItems) {
    for (var oldItem in oldPurchase.items) {
      int oldTotalLooseQty = (oldItem.qty + oldItem.fQty) * oldItem.packin;

      // Find this exact item in the NEW updated list
      final matchingNewItems = updatedItems.where((newItem) =>
      newItem.productName.toLowerCase().trim() == oldItem.productName.toLowerCase().trim() &&
          newItem.batch.toLowerCase().trim() == oldItem.batch.toLowerCase().trim()
      );

      int newTotalLooseQty = 0;
      for(var match in matchingNewItems) {
        newTotalLooseQty += (match.qty + match.fQty) * match.packin;
      }

      int looseQuantityBeingRemoved = oldTotalLooseQty - newTotalLooseQty;

      if (looseQuantityBeingRemoved > 0) {
        final product = _products.firstWhere(
              (p) => p.name.toLowerCase().trim() == oldItem.productName.toLowerCase().trim() &&
              p.batch.toLowerCase().trim() == oldItem.batch.toLowerCase().trim(),
          orElse: () => Product(id: "", name: oldItem.productName, batch: oldItem.batch, stock: 0),
        );

        int currentBatchStock = product.stock;
        int looseUnitsAlreadyUsed = oldTotalLooseQty - currentBatchStock;

        // THE MASTER RULE: Block reduction below consumed amounts
        if (looseQuantityBeingRemoved > currentBatchStock) {
          int minStripsRequired = (looseUnitsAlreadyUsed / oldItem.packin).ceil();

          if (newTotalLooseQty == 0) {
            // Scenario: User tried to change the Batch or Product Name
            return "Edit Blocked!\n\nYou cannot remove or change the batch for '${oldItem.productName}'.\n\n• Units already consumed: $looseUnitsAlreadyUsed loose units.\n• You must keep Batch '${oldItem.batch}' with at least $minStripsRequired strips.\n\nTo change this, delete the dependent Sales or Damage entries first.";
          } else {
            // Scenario: User tried to reduce the Quantity
            return "Edit Blocked!\n\nYou cannot reduce '${oldItem.productName}' below $minStripsRequired strips.\n\n• Units already consumed: $looseUnitsAlreadyUsed loose units.\n\nTo reduce further, delete the dependent Sales or Damage entries first.";
          }
        }
      }
    }
    return null;
  }

  void updatePurchase(PurchaseEntry oldPur, PurchaseEntry newPur) async {
    final db = kIsWeb ? null : await DbHelper.instance.database;
    if (db == null) return;
    try {
      await db.transaction((txn) async {
        final existingEntry = oldPur;
        final itemMap = {for (var item in newPur.items) item.id: item};

        for (var oldItem in existingEntry.items) {
          String pId = oldItem.id;
          if (pId.isEmpty) {
            final prod = await txn.query('product_master', columns: ['id'], where: 'name = ? COLLATE NOCASE', whereArgs: [oldItem.productName]);
            if (prod.isNotEmpty) pId = prod.first['id'].toString();
          }
          // Check how many units of this specific product/batch have been sold since this purchase
          double totalSold = await _calculateUnitsSoldForBatch(pId.isNotEmpty ? pId : oldItem.id, oldItem.batch, txn);
          double newProposedQty = ((itemMap[oldItem.id]?.qty ?? 0) * (itemMap[oldItem.id]?.packin ?? 1)).toDouble();

          if (newProposedQty < totalSold) {
            throw Exception("Cannot reduce quantity below already sold units! ($totalSold units already billed out for batch ${oldItem.batch})");
          }
        }

        // 1. Reverse Stock
        for (var item in oldPur.items) {
          final List<Map<String, dynamic>> prod = await txn.query('product_master', columns: ['id'], where: 'name = ?', whereArgs: [item.productName]);
          if (prod.isNotEmpty) {
            int totalOldUnits = (item.qty + item.fQty) * (item.packin > 0 ? item.packin : 1);
            await txn.rawUpdate('UPDATE stock_batches SET current_stock = current_stock - ? WHERE product_id = ? AND batch_number = ?', [totalOldUnits, prod[0]['id'], item.batch]);
          }
        }
        // 2. Delete old
        await txn.delete('purchase_items', where: 'entry_no = ?', whereArgs: [oldPur.entryNo]);
        await txn.delete('purchase_entries', where: 'entry_no = ?', whereArgs: [oldPur.entryNo]);

        // 3. Save new
        await txn.insert('purchase_entries', {
          'entry_no': newPur.entryNo,
          'date': newPur.date.toIso8601String(),
          'supplier_name': newPur.supplierName,
          'sup_inv_no': cleanInvoiceNo(newPur.supInvNo),
          'sup_inv_date': newPur.supInvDate.toIso8601String(),
          'grand_total': newPur.grandTotal,
        });
        for (var item in newPur.items) {
          await txn.insert('purchase_items', {
            'entry_no': newPur.entryNo,
            'product_id': item.id,
            'product_name': item.productName,
            'batch': item.batch,
            'qty': item.qty,
            'f_qty': item.fQty,
            'packin': item.packin,
            'total': item.total,
          });
          // Update Stock again
          final List<Map<String, dynamic>> prod = await txn.query('product_master', columns: ['id'], where: 'name = ?', whereArgs: [item.productName]);
          if (prod.isNotEmpty) {
            int totalUnits = (item.qty + item.fQty) * (item.packin > 0 ? item.packin : 1);
            await txn.rawUpdate('UPDATE stock_batches SET current_stock = current_stock + ? WHERE product_id = ? AND batch_number = ?', [totalUnits, prod[0]['id'], item.batch]);
          }
        }
      });
      int idx = _purchases.indexWhere((p) => p.entryNo == oldPur.entryNo);
      if (idx != -1) _purchases[idx] = newPur;
      notifyListeners();
    } catch (e) { debugPrint("Update Purchase Error: $e"); }
  }

  void updateSale(SaleInvoice oldSale, SaleInvoice newSale) async {
    final db = kIsWeb ? null : await DbHelper.instance.database;
    if (db == null) return;
    try {
      await db.transaction((txn) async {
        // 1. Reverse old sale stock
        for (var item in oldSale.items) {
          int totalOldQty = item.qty;
          await txn.rawUpdate('UPDATE stock_batches SET current_stock = current_stock + ? WHERE product_id = ? AND batch_number = ?', [totalOldQty, item.product.id, item.product.batch]);
        }
        // 2. Delete old records
        await txn.delete('sales_items', where: 'invoice_no = ?', whereArgs: [oldSale.entryNo]);
        await txn.delete('sales_invoices', where: 'entry_no = ?', whereArgs: [oldSale.entryNo]);

        // 3. Save new sale (as in saveSale)
        await txn.insert('sales_invoices', {
          'entry_no': newSale.entryNo,
          'date': newSale.date.toIso8601String(),
          'customer_acc': newSale.customerAcc,
          'patient': newSale.patient,
          'mobile': newSale.mobile,
          'doctor': newSale.doctor,
          'tax_type': newSale.taxType,
          'sub_total': newSale.subTotal,
          'grand_total': newSale.grandTotal,
          // other fields...
        });
        for (var item in newSale.items) {
          await txn.insert('sales_items', {
            'invoice_no': newSale.entryNo,
            'product_id': item.product.id,
            'batch_number': item.product.batch,
            'qty': item.qty,
            'packin': item.packin,
            // other fields...
          });
          int totalSaleUnits = item.qty;
          await txn.rawUpdate('UPDATE stock_batches SET current_stock = current_stock - ? WHERE product_id = ? AND batch_number = ?', [totalSaleUnits, item.product.id, item.product.batch]);
        }
      });
      int idx = _sales.indexWhere((s) => s.entryNo == oldSale.entryNo);
      if (idx != -1) _sales[idx] = newSale;
      notifyListeners();
    } catch (e) { debugPrint("Update Sale Error: $e"); }
  }

  Future<String> saveSaleReturn(SaleReturnInvoice ret, {bool isEdit = false}) async {
    if (kIsWeb) return "";
    if (ret.customerAcc.trim().isEmpty) {
      throw "Account Name is mandatory. Cannot save sales return with blank Account Name.";
    }
    if (ret.patient.trim().isEmpty) {
      throw "Patient Name is mandatory. Cannot save sales return with blank Patient Name.";
    }
    if (ret.doctor.trim().isEmpty) {
      throw "Doctor Name is mandatory. Cannot save sales return with blank Doctor Name.";
    }

    String rawNo = ret.entryNo.trim();
    String finalEntryNo = rawNo;
    if (finalEntryNo.isNotEmpty && !finalEntryNo.startsWith("SRET-") && finalEntryNo != "AUTO" && finalEntryNo != "RET-1001") {
      finalEntryNo = "SRET-$finalEntryNo";
    }
    String fy = ret.financialYear.isEmpty ? _selectedFinancialYear : ret.financialYear;
    List<Map<String, dynamic>> existingOldItems = [];
    try {
      await executeSerializedTransaction((txn) async {
          // 1. In-Transaction Active Invoice & Quantity Guard
          if (ret.originalInvoiceNo.trim().isNotEmpty) {
            final List<Map<String, dynamic>> origInvoiceHeader = await txn.query(
              'sales_invoices',
              columns: ['is_deleted'],
              where: 'entry_no = ?',
              whereArgs: [ret.originalInvoiceNo.trim()],
            );

            if (origInvoiceHeader.isEmpty) {
              throw "Return Blocked: Original Invoice #${ret.originalInvoiceNo} was not found.";
            }

            if ((origInvoiceHeader.first['is_deleted'] as int?) == 1) {
              throw "Return Blocked: Original Invoice #${ret.originalInvoiceNo} has already been canceled/deleted.";
            }

            final List<Map<String, dynamic>> originalItems = await txn.query(
              'sales_items',
              where: 'invoice_no = ?',
              whereArgs: [ret.originalInvoiceNo.trim()]
            );

            if (originalItems.isEmpty) {
              throw "Return Blocked: Original Invoice #${ret.originalInvoiceNo} was not found.";
            }

            Map<String, int> soldQuantities = {};
            for (var orig in originalItems) {
              String key = "${orig['product_id']}|${orig['batch_number']?.toString().toUpperCase().trim()}";
              int qty = (orig['qty'] as num?)?.toInt() ?? 0;
              soldQuantities[key] = (soldQuantities[key] ?? 0) + qty;
            }

            String whereClause = 'original_invoice_no = ? AND is_deleted = 0';
            List<dynamic> whereArgs = [ret.originalInvoiceNo.trim()];

            if (isEdit) {
              whereClause += ' AND entry_no != ? AND entry_no != ?';
              whereArgs.add(finalEntryNo);
              whereArgs.add(rawNo);
            }

            final List<Map<String, dynamic>> prevReturnHeaders = await txn.query(
              'sales_return_invoices',
              columns: ['entry_no'],
              where: whereClause,
              whereArgs: whereArgs,
            );

            Map<String, int> alreadyReturned = {};
            for (var header in prevReturnHeaders) {
              final List<Map<String, dynamic>> prevItems = await txn.query(
                'sales_return_items',
                where: 'return_no = ?',
                whereArgs: [header['entry_no']]
              );
              for (var pItem in prevItems) {
                String key = "${pItem['product_id']}|${pItem['batch_number']?.toString().toUpperCase().trim()}";
                int qty = (pItem['quantity'] as num?)?.toInt() ?? (pItem['qty'] as num?)?.toInt() ?? 0;
                alreadyReturned[key] = (alreadyReturned[key] ?? 0) + qty;
              }
            }

            for (var retItem in ret.items) {
              String key = "${retItem.product.id}|${retItem.product.batch.toUpperCase().trim()}";
              if (!soldQuantities.containsKey(key)) {
                throw "Return Blocked: Item '${retItem.product.name}' (Batch: ${retItem.product.batch}) does not exist on Invoice #${ret.originalInvoiceNo}.";
              }

              int originallySold = soldQuantities[key] ?? 0;
              int previouslyReturned = alreadyReturned[key] ?? 0;
              int netAvailable = originallySold - previouslyReturned;

              if (retItem.qty > netAvailable) {
                if (previouslyReturned > 0) {
                  throw "Return Blocked: Returning ${retItem.qty} units of '${retItem.product.name}' (Batch: ${retItem.product.batch}) exceeds available balance ($netAvailable units remaining).\n\n"
                      "Originally Sold: $originallySold\n"
                      "Already Returned: $previouslyReturned\n"
                      "Remaining Available: $netAvailable";
                } else {
                  throw "Return Blocked: Returning ${retItem.qty} units exceeds available balance ($netAvailable units remaining from original sale of $originallySold).";
                }
              }
            }
          }
          if (finalEntryNo.isEmpty || finalEntryNo == "AUTO" || finalEntryNo == "RET-1001" || finalEntryNo == "SRET-") {
            finalEntryNo = "SRET-${await _generateNextNoWithFY(txn, 'sales_return_invoices', 'entry_no', fy)}";
          }

          // ================================================================
          // 1. REVERT OLD STOCK & LEDGER (PURE SQL)
          // ================================================================
          if (isEdit) {
            existingOldItems = await txn.query(
              'sales_return_items', 
              where: 'return_no = ? OR return_no = ?', 
              whereArgs: [finalEntryNo, rawNo]
            );
            for (var old in existingOldItems) {
              String pId = old['product_id']?.toString() ?? "";
              String bNo = old['batch_number']?.toString() ?? "";
              int oldQty = (old['quantity'] as num?)?.toInt() ?? (old['qty'] as num?)?.toInt() ?? 0;

              if (pId.isNotEmpty && oldQty > 0) {
                await txn.rawUpdate(
                  'UPDATE stock_batches SET current_stock = current_stock - ? WHERE product_id = ? AND batch_number = ? AND current_stock >= ? COLLATE NOCASE',
                  [oldQty, pId, bNo, oldQty]
                );
              }
            }
            
            final oldHeader = await txn.query(
              'sales_return_invoices', 
              columns: ['grand_total', 'patient'], 
              where: 'entry_no = ? OR entry_no = ?', 
              whereArgs: [finalEntryNo, rawNo]
            );
            if (oldHeader.isNotEmpty) {
              double oldGrandTotal = (oldHeader.first['grand_total'] as num?)?.toDouble() ?? 0.0;
              String oldPat = oldHeader.first['patient'].toString();
              if (oldPat.isNotEmpty) {
                 await txn.rawUpdate('UPDATE patients SET current_balance = current_balance + ? WHERE name = ? COLLATE NOCASE', [oldGrandTotal, oldPat]);
              }
            }
            await txn.delete('sales_return_items', where: 'return_no = ? OR return_no = ?', whereArgs: [finalEntryNo, rawNo]);
          }

          // ================================================================
          // 2. SAVE HEADER & APPLY NEW LEDGER
          // ================================================================
          await txn.insert('sales_return_invoices', {
            'entry_no': finalEntryNo,
            'date': ret.date.toIso8601String(),
            'customer_acc': ret.customerAcc,
            'patient': ret.patient,
            'doctor': ret.doctor,
            'original_invoice_no': ret.originalInvoiceNo,
            'sub_total': ret.subTotal,
            'discount': ret.discount,
            'round_off': ret.roundOff,
            'grand_total': ret.grandTotal,
            'narration': ret.narration,
            'gst_mode': ret.gstMode,
            'financial_year': fy,
          }, conflictAlgorithm: sql.ConflictAlgorithm.replace);

          if (ret.patient.isNotEmpty) {
            final int updatedRows = await txn.rawUpdate('UPDATE patients SET current_balance = current_balance - ? WHERE name = ? COLLATE NOCASE', [ret.grandTotal, ret.patient]);
            if (updatedRows == 0) {
              await txn.insert('patients', {'id': "PAT_${DateTime.now().millisecondsSinceEpoch}", 'name': ret.patient, 'mobile': '', 'current_balance': -ret.grandTotal, 'address': ''});
            }
          }

          // ================================================================
          // 3. INSERT ITEMS & ADD NEW STOCK
          // ================================================================
          for (var item in ret.items) {
            String pId = item.product.id.trim();
            if (pId.isEmpty || pId == "UNKNOWN") {
              final mRes = await txn.query('product_master', columns: ['id'], where: 'name = ? COLLATE NOCASE', whereArgs: [item.product.name.trim()]);
              if (mRes.isNotEmpty) {
                pId = mRes.first['id'].toString();
              }
            }

            await txn.insert('sales_return_items', {
              'return_no': finalEntryNo, 
              'product_id': pId, 
              'product_name': item.product.name, 
              'batch_number': item.product.batch, 
              'expiry_date': item.product.expiry, 
              'quantity': item.qty, 
              'mrp': item.product.mrp, 
              'sale_rate': item.product.salePrice, 
              'disc_percent': item.discPercent,
              'disc_amt': item.discAmt,
              'hsn_code': item.product.hsnCode,
              'total': item.total,
              'purchase_rate': item.purchaseRate,
              'landing_cost': item.landingCost,
              'supplier_name': item.supplier,
              'packing': item.packin,
              'gst_percent': item.gstPercent,
            });

            // Re-insert or Update the specific batch line
            final batchCheck = await txn.query('stock_batches', 
              where: 'product_id = ? AND batch_number = ? COLLATE NOCASE', 
              whereArgs: [pId, item.product.batch]
            );

            if (batchCheck.isNotEmpty) {
              await txn.rawUpdate(
                'UPDATE stock_batches SET current_stock = current_stock + ? WHERE product_id = ? AND batch_number = ? COLLATE NOCASE',
                [item.qty + item.fQty, pId, item.product.batch]
              );
            } else {
              await txn.insert('stock_batches', {
                'product_id': pId, 
                'batch_number': item.product.batch, 
                'expiry_date': item.product.expiry, 
                'current_stock': item.qty + item.fQty, 
                'purchase_rate': item.purchaseRate, 
                'landing_cost': item.landingCost,
                'mrp': item.product.mrp, 
                'sale_rate': item.product.salePrice, 
                'supplier_name': item.supplier, 
                'rack': item.product.rack, 
                'packing': item.packin,
                'gst_percent': item.gstPercent
              });
            }
          }
        });

      // -----------------------------------------------------------------
      // POST-COMMIT IN-MEMORY RECONCILIATION
      // -----------------------------------------------------------------
      // 1. Revert old return items from RAM if editing
      if (isEdit && existingOldItems.isNotEmpty) {
        for (var old in existingOldItems) {
          String pId = old['product_id']?.toString() ?? "";
          String bNo = old['batch_number']?.toString() ?? "";
          int oldQty = (old['quantity'] as num?)?.toInt() ?? (old['qty'] as num?)?.toInt() ?? 0;

          if (pId.isNotEmpty && oldQty > 0) {
            int pIdx = _products.indexWhere((p) =>
              p.id == pId && p.batch.trim().toUpperCase() == bNo.trim().toUpperCase()
            );
            if (pIdx != -1) {
              _products[pIdx].stock -= oldQty;
            }

            int mIdx = _productMaster.indexWhere((m) => m.id == pId);
            if (mIdx != -1) {
              _productMaster[mIdx].stock -= oldQty;
            }
          }
        }
      }

      // 2. Add new returned items to RAM
      for (var item in ret.items) {
        int returnedQty = item.qty + item.fQty;
        if (returnedQty <= 0) continue;

        String pId = item.product.id.trim();
        if (pId.isEmpty || pId == "UNKNOWN") {
          int mIdx = _productMaster.indexWhere((m) => m.name.trim().toLowerCase() == item.product.name.trim().toLowerCase() && m.name.trim().isNotEmpty);
          if (mIdx != -1) pId = _productMaster[mIdx].id;
        }
        String cleanBatchStr = item.product.batch.trim().toUpperCase();

        int pIdx = _products.indexWhere((p) =>
          (p.id == pId || (p.name.trim().toLowerCase() == item.product.name.trim().toLowerCase() && p.name.trim().isNotEmpty)) &&
          p.batch.trim().toUpperCase() == cleanBatchStr
        );

        if (pIdx != -1) {
          _products[pIdx].stock += returnedQty;
        } else {
          _products.add(Product(
            id: pId,
            name: item.product.name,
            batch: item.product.batch.trim(),
            expiry: item.product.expiry,
            packSize: item.packin > 0 ? item.packin : item.product.packSize,
            stock: returnedQty,
            purchaseRate: item.purchaseRate,
            landingCost: item.landingCost,
            mrp: item.product.mrp,
            salePrice: item.product.salePrice,
            gstPercent: item.gstPercent,
            rack: item.product.rack,
            supplier: item.supplier,
          ));
        }

        int mIdx = _productMaster.indexWhere((m) =>
          (m.id == pId && pId.isNotEmpty) || (m.name.trim().toLowerCase() == item.product.name.trim().toLowerCase() && m.name.trim().isNotEmpty)
        );
        if (mIdx != -1) {
          _productMaster[mIdx].stock += returnedQty;
        }
      }

      _rebuildSearchIndex();

      final updatedRet = SaleReturnInvoice(
        entryNo: finalEntryNo,
        date: ret.date,
        customerAcc: ret.customerAcc,
        patient: ret.patient,
        doctor: ret.doctor,
        originalInvoiceNo: ret.originalInvoiceNo,
        items: ret.items,
        subTotal: ret.subTotal,
        discount: ret.discount,
        roundOff: ret.roundOff,
        grandTotal: ret.grandTotal,
        narration: ret.narration,
        gstMode: ret.gstMode,
        financialYear: fy,
      );

      int idx = _saleReturns.indexWhere((s) => s.entryNo == finalEntryNo);
      if (idx != -1) {
        _saleReturns[idx] = updatedRet;
      } else {
        _saleReturns.insert(0, updatedRet);
      }
      _saleReturns.sort((a, b) => b.date.compareTo(a.date));
      if (_saleReturns.length > 50) _saleReturns.removeLast();

      notifyListeners();
      return finalEntryNo;
    } catch (e) {
      debugPrint("Save Sale Return Error: $e");
      rethrow; 
    }
  }

  Future<void> settleSalePayment(String entryNo, String paymentMode, String remarks) async {
    final db = await DbHelper.instance.database;
    await db.update('sales_invoices', {
      'customer_acc': paymentMode,
      'is_paid': 1,
      'payment_remarks': remarks
    }, where: 'entry_no = ?', whereArgs: [entryNo]);

    final idx = _sales.indexWhere((s) => s.entryNo == entryNo);
    if (idx != -1) {
      final s = _sales[idx];
      _sales[idx] = SaleInvoice(
        entryNo: s.entryNo,
        date: s.date,
        customerAcc: paymentMode,
        patient: s.patient,
        mobile: s.mobile,
        doctor: s.doctor,
        doctorRegNo: s.doctorRegNo,
        specialOrderJson: s.specialOrderJson,
        taxType: s.taxType,
        days: s.days,
        items: s.items,
        subTotal: s.subTotal,
        discountPercent: s.discountPercent,
        discount: s.discount,
        additionalDiscount: s.additionalDiscount,
        otherCharge: s.otherCharge,
        rcvdAmt: s.grandTotal, // Assume fully received on settlement
        secondaryAcc: s.secondaryAcc,
        secondaryAmt: s.secondaryAmt,
        roundOff: s.roundOff,
        grandTotal: s.grandTotal,
        agent: s.agent,
        expectingDate: s.expectingDate,
        paymentRemarks: remarks,
        financialYear: s.financialYear,
        isPaid: true,
        isDeleted: s.isDeleted,
      );
      notifyListeners();
    }
  }

  Future<String> savePurchaseReturn(PurchaseReturnEntry ret, {bool isEdit = false}) async {
    if (kIsWeb) return "";
    String finalEntryNo = ret.entryNo;
    String fy = ret.financialYear.isEmpty ? _selectedFinancialYear : ret.financialYear;
    
    try {
      await executeSerializedTransaction((txn) async {
        // --- STRICT PURCHASE RETURN QUANTITY VALIDATION AGAINST ORIGINAL PURCHASE ---
        if (ret.originalPurchaseNo.trim().isNotEmpty) {
          final List<Map<String, dynamic>> origItems = await txn.query(
            'purchase_items',
            where: 'entry_no = ?',
            whereArgs: [ret.originalPurchaseNo.trim()],
          );

          if (origItems.isNotEmpty) {
            Map<String, int> purchasedQuantities = {};
            for (var orig in origItems) {
              int pack = (orig['packin'] as num?)?.toInt() ?? 1;
              int qty = ((orig['qty'] as num?)?.toInt() ?? 0) + ((orig['f_qty'] as num?)?.toInt() ?? 0);
              String key = "${orig['product_name'].toString().toLowerCase().trim()}|${orig['batch'].toString().toLowerCase().trim()}";
              purchasedQuantities[key] = (purchasedQuantities[key] ?? 0) + (qty * (pack > 0 ? pack : 1));
            }

            // Sum prior returns excluding current one if editing
            String whereClause = 'original_purchase_no = ? AND IFNULL(is_deleted, 0) = 0';
            List<dynamic> whereArgs = [ret.originalPurchaseNo.trim()];
            if (isEdit && finalEntryNo.isNotEmpty) {
              whereClause += ' AND entry_no != ?';
              whereArgs.add(finalEntryNo);
            }

            final prevReturnHeaders = await txn.query('purchase_return_entries', columns: ['entry_no'], where: whereClause, whereArgs: whereArgs);
            Map<String, int> alreadyReturned = {};

            for (var header in prevReturnHeaders) {
              final prevItems = await txn.query('purchase_return_items', where: 'entry_no = ?', whereArgs: [header['entry_no']]);
              for (var pItem in prevItems) {
                int pack = (pItem['packin'] as num?)?.toInt() ?? 1;
                int units = (((pItem['qty'] as num?)?.toInt() ?? 0) * (pack > 0 ? pack : 1)) + ((pItem['loose_qty'] as num?)?.toInt() ?? 0);
                String key = "${pItem['product_name'].toString().toLowerCase().trim()}|${pItem['batch'].toString().toLowerCase().trim()}";
                alreadyReturned[key] = (alreadyReturned[key] ?? 0) + units;
              }
            }

            for (var item in ret.items) {
              String key = "${item.productName.toLowerCase().trim()}|${item.batch.toLowerCase().trim()}";
              if (purchasedQuantities.containsKey(key)) {
                int originallyPurchased = purchasedQuantities[key]!;
                int previouslyRet = alreadyReturned[key] ?? 0;
                int maxAvailable = originallyPurchased - previouslyRet;
                int requestedLoose = (item.qty * (item.packin > 0 ? item.packin : 1)) 
                    + item.looseQty 
                    + (item.fQty * (item.packin > 0 ? item.packin : 1)); // Includes Free Goods!

                if (requestedLoose > maxAvailable) {
                  throw "Return Blocked: Returning $requestedLoose units of '${item.productName}'.\n\n"
                      "Purchased on Bill #${ret.originalPurchaseNo}: $originallyPurchased\n"
                      "Already Returned: $previouslyRet\n"
                      "Maximum Allowable: $maxAvailable units.";
                }
              }
            }
          }
        }

        if (finalEntryNo.isEmpty || finalEntryNo == "AUTO" || finalEntryNo == "RET-1001") {
          finalEntryNo = "PRET-${await _generateNextNoWithFY(txn, 'purchase_return_entries', 'entry_no', fy)}";
        }

          // 1. If Edit, revert previous stock & revert supplier debt
          if (isEdit) {
            final oldHeader = await txn.query('purchase_return_entries', columns: ['grand_total', 'supplier_name'], where: 'entry_no = ?', whereArgs: [finalEntryNo]);
            if (oldHeader.isNotEmpty) {
              double oldGrandTotal = (oldHeader.first['grand_total'] as num?)?.toDouble() ?? 0.0;
              String oldSup = oldHeader.first['supplier_name']?.toString() ?? "";
              if (oldSup.isNotEmpty && oldGrandTotal > 0) {
                await txn.rawUpdate(
                  'UPDATE suppliers SET current_balance = current_balance + ? WHERE name = ? COLLATE NOCASE',
                  [oldGrandTotal, oldSup]
                );
              }
            }

            final List<Map<String, dynamic>> oldItems = await txn.query('purchase_return_items', where: 'entry_no = ?', whereArgs: [finalEntryNo]);
            for (var old in oldItems) {
              final String pName = old['product_name'] ?? "";
              final String batch = old['batch'] ?? "";
              final int qty = (old['qty'] as num?)?.toInt() ?? 0;
              final int lQty = (old['loose_qty'] as num?)?.toInt() ?? 0;
              final int fQty = (old['f_qty'] as num?)?.toInt() ?? 0;
              final int packin = (old['packin'] as num?)?.toInt() ?? 1;
              int totalUnitsToRestore = (qty * (packin > 0 ? packin : 1)) + lQty + (fQty * (packin > 0 ? packin : 1));

              final mRes = await txn.query('product_master', columns: ['id'], where: 'name = ? COLLATE NOCASE', whereArgs: [pName]);
              if (mRes.isNotEmpty) {
                final productId = mRes.first['id'].toString();
                await txn.rawUpdate(
                  'UPDATE stock_batches SET current_stock = current_stock + ? WHERE product_id = ? AND batch_number = ?',
                  [totalUnitsToRestore, productId, batch]
                );
                final pIndex = _products.indexWhere((p) => p.id == productId && p.batch == batch);
                if (pIndex != -1) _products[pIndex].stock += totalUnitsToRestore;
                final mIndex = _productMaster.indexWhere((p) => p.id == productId);
                if (mIndex != -1) _productMaster[mIndex].stock += totalUnitsToRestore;
              }
            }
            await txn.delete('purchase_return_items', where: 'entry_no = ?', whereArgs: [finalEntryNo]);
          }

          // 2. Insert Header
          await txn.insert('purchase_return_entries', {
            'entry_no': finalEntryNo,
            'date': ret.date.toIso8601String(),
            'supplier_name': ret.supplierName,
            'original_purchase_no': ret.originalPurchaseNo,
            'done_by': ret.doneBy,
            'gst_mode': ret.gstMode,
            'grand_total': ret.grandTotal,
            'financial_year': fy,
          }, conflictAlgorithm: sql.ConflictAlgorithm.replace);

          // 3. Deduct Shelf Stock with Atomic Verification
          for (var item in ret.items) {
            String productId = item.id;
            if (productId.isEmpty || productId == "UNKNOWN") {
              final mRes = await txn.query('product_master', columns: ['id'], where: 'name = ? COLLATE NOCASE', whereArgs: [item.productName.trim()]);
              if (mRes.isNotEmpty) productId = mRes.first['id'].toString();
            }

            if (productId.isEmpty) throw "Product '${item.productName}' not found in database master.";

            int requestedLooseQty = (item.qty * (item.packin > 0 ? item.packin : 1)) 
                + item.looseQty 
                + (item.fQty * (item.packin > 0 ? item.packin : 1)); // Includes Free Goods!

            await txn.insert('purchase_return_items', {
              'entry_no': finalEntryNo,
              'product_name': item.productName,
              'batch': item.batch,
              'expiry': item.expiry,
              'qty': item.qty,
              'loose_qty': item.looseQty,
              'f_qty': item.fQty,
              'unit': item.unit,
              'packin': item.packin,
              'mrp': item.mrp,
              'p_rate': item.pRate,
              's_rate': item.sRate,
              'disc_percent': item.discPercent,
              'gst_percent': item.gstPercent,
              'total': item.total,
              'reason': item.reason,
              'supplier': item.supplier,
              'sup_inv_no': cleanInvoiceNo(item.supInvNo),
              'hsn_code': item.hsnCode,
            });

            final int affected = await txn.rawUpdate(
              'UPDATE stock_batches SET current_stock = current_stock - ? WHERE product_id = ? AND batch_number = ? AND current_stock >= ? COLLATE NOCASE',
              [requestedLooseQty, productId, item.batch, requestedLooseQty]
            );

            if (affected == 0) {
              throw "STOCK LOCK TRIGGERED!\n\nCannot return $requestedLooseQty units of '${item.productName}'. Insufficient shelf stock available.";
            }

            final pIndex = _products.indexWhere((p) => p.id == productId && p.batch == item.batch);
            if (pIndex != -1) _products[pIndex].stock -= requestedLooseQty;
            final mIndex = _productMaster.indexWhere((p) => p.id == productId);
            if (mIndex != -1) _productMaster[mIndex].stock -= requestedLooseQty;
          }

          // 4. Reduce Supplier Outstanding Balance
          if (ret.supplierName.isNotEmpty && ret.grandTotal > 0) {
            final int updatedRows = await txn.rawUpdate(
              'UPDATE suppliers SET current_balance = current_balance - ? WHERE name = ? COLLATE NOCASE',
              [ret.grandTotal, ret.supplierName]
            );
            if (updatedRows == 0) {
              await txn.insert('suppliers', {
                'id': "SUP_RET_${DateTime.now().millisecondsSinceEpoch}",
                'name': ret.supplierName,
                'current_balance': -ret.grandTotal,
                'phone': '', 'address': '', 'gst_in': '', 'dl_number': '',
              });
            }
          }
      });

      final updatedRet = PurchaseReturnEntry(
        entryNo: finalEntryNo,
        date: ret.date,
        supplierName: ret.supplierName,
        originalPurchaseNo: ret.originalPurchaseNo,
        doneBy: ret.doneBy,
        items: ret.items,
        grandTotal: ret.grandTotal,
        financialYear: fy,
      );

      int idx = _purchaseReturns.indexWhere((p) => p.entryNo == finalEntryNo);
      if (idx != -1) {
        _purchaseReturns[idx] = updatedRet;
      } else {
        _purchaseReturns.insert(0, updatedRet);
      }
      _purchaseReturns.sort((a, b) => b.date.compareTo(a.date));
      if (_purchaseReturns.length > 50) _purchaseReturns.removeLast();

      _rebuildSearchIndex();
      notifyListeners();
      return finalEntryNo;
    } catch (e) {
      debugPrint("Save Purchase Return Error: $e");
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> navigateInvoice(String currentEntry, String direction, {bool isPurchase = false, bool isSaleReturn = false, bool isPurchaseReturn = false, bool isAdjustment = false}) async {
    final db = await DbHelper.instance.database;
    String table = 'sales_invoices';
    if (isPurchase) table = 'purchase_entries';
    if (isSaleReturn) table = 'sales_return_invoices';
    if (isPurchaseReturn) table = 'purchase_return_entries';
    if (isAdjustment) table = 'stock_adjustments';

    String currentNo = currentEntry.trim();
    String prefix = isSaleReturn ? "SRET-" : (isPurchaseReturn ? "PRET-" : (isAdjustment ? "ADJ-" : ""));
    
    if (prefix.isNotEmpty && currentNo.startsWith(prefix)) {
      currentNo = currentNo.substring(prefix.length);
    }
    if (currentNo.contains('_')) {
      currentNo = currentNo.substring(currentNo.indexOf('_') + 1);
    }

    String replaceStr = "CASE WHEN instr(entry_no, '_') > 0 THEN substr(entry_no, instr(entry_no, '_') + 1) ELSE ${prefix.isNotEmpty ? "REPLACE(entry_no, '$prefix', '')" : "entry_no"} END";
    String fyFilter = "(financial_year = ? OR financial_year IS NULL OR financial_year = '')";
    String isDelFilter = 'AND is_deleted = 0';

    if (direction == 'find') {
      // Step 1: Fast exact primary key or invoice_no match (O(1) indexed lookup)
      List<Map<String, dynamic>> res = await db.rawQuery(
        table == 'sales_invoices'
            ? "SELECT * FROM $table WHERE (entry_no = ? OR invoice_no = ?) $isDelFilter LIMIT 1"
            : "SELECT * FROM $table WHERE entry_no = ? $isDelFilter LIMIT 1",
        table == 'sales_invoices' ? [currentEntry, currentEntry] : [currentEntry]
      );
      if (res.isNotEmpty) return res.first;

      // Step 2: Fallback for entry numbers with financial year prefix (e.g. "2024-25_17876")
      if (currentNo.isNotEmpty) {
        res = await db.rawQuery(
          "SELECT * FROM $table WHERE entry_no LIKE ? $isDelFilter LIMIT 1",
          ["%_$currentNo"]
        );
        if (res.isNotEmpty) return res.first;
      }

      if (isPurchase) {
        res = await db.rawQuery("SELECT * FROM $table WHERE sup_inv_no = ? $isDelFilter LIMIT 1", [currentEntry]);
        if (res.isNotEmpty) return res.first;
      }

      return null;
    }

    Map<String, dynamic>? currentRecord;
    if (currentNo.isNotEmpty) {
      String curWhere = table == 'sales_invoices'
          ? "(entry_no = ? OR invoice_no = ? OR entry_no LIKE ?)"
          : "(entry_no = ? OR entry_no LIKE ?)";
      List<dynamic> curParams = table == 'sales_invoices'
          ? [currentEntry, currentEntry, "%_$currentNo"]
          : [currentEntry, "%_$currentNo"];

      final curList = await db.rawQuery(
        "SELECT rowid, entry_no, date, financial_year FROM $table WHERE $curWhere $isDelFilter LIMIT 1",
        curParams
      );
      if (curList.isNotEmpty) {
        currentRecord = curList.first;
      }
    }

    int? currentNum = int.tryParse(currentNo);
    int currentDbRowId = currentRecord != null ? (currentRecord['rowid'] as int? ?? 0) : 0;
    String currentDateStr = currentRecord != null ? (currentRecord['date']?.toString() ?? '') : '';

    if (currentRecord == null && currentNum == null && direction == 'prev') {
      final maxRes = await db.rawQuery("SELECT CAST($replaceStr AS INTEGER) as max_no FROM $table WHERE $fyFilter $isDelFilter ORDER BY max_no DESC LIMIT 1", [_selectedFinancialYear]);
      if (maxRes.isNotEmpty && maxRes.first['max_no'] != null) {
        currentNum = (maxRes.first['max_no'] as num).toInt() + 1;
      } else {
        final maxResAll = await db.rawQuery("SELECT CAST($replaceStr AS INTEGER) as max_no FROM $table WHERE 1=1 $isDelFilter ORDER BY max_no DESC LIMIT 1");
        if (maxResAll.isNotEmpty && maxResAll.first['max_no'] != null) {
          currentNum = (maxResAll.first['max_no'] as num).toInt() + 1;
        }
      }
    }

    List<Map<String, dynamic>> result = [];

    switch (direction) {
      case 'first':
        result = await db.rawQuery(
          "SELECT * FROM $table WHERE $fyFilter $isDelFilter ORDER BY CAST($replaceStr AS INTEGER) ASC, rowid ASC LIMIT 1",
          [_selectedFinancialYear]
        );
        if (result.isEmpty) {
          result = await db.rawQuery("SELECT * FROM $table WHERE 1=1 $isDelFilter ORDER BY CAST($replaceStr AS INTEGER) ASC, rowid ASC LIMIT 1");
        }
        break;

      case 'last':
        result = await db.rawQuery(
          "SELECT * FROM $table WHERE $fyFilter $isDelFilter ORDER BY CAST($replaceStr AS INTEGER) DESC, rowid DESC LIMIT 1",
          [_selectedFinancialYear]
        );
        if (result.isEmpty) {
          result = await db.rawQuery("SELECT * FROM $table WHERE 1=1 $isDelFilter ORDER BY CAST($replaceStr AS INTEGER) DESC, rowid DESC LIMIT 1");
        }
        break;

      case 'prev':
        if (currentNum != null && currentNum > 0) {
          result = await db.rawQuery(
            "SELECT * FROM $table WHERE $fyFilter AND (CAST($replaceStr AS INTEGER) < ? OR (CAST($replaceStr AS INTEGER) = ? AND rowid < ?)) $isDelFilter ORDER BY CAST($replaceStr AS INTEGER) DESC, rowid DESC LIMIT 1",
            [_selectedFinancialYear, currentNum, currentNum, currentDbRowId]
          );
        } else if (currentDbRowId > 0) {
          result = await db.rawQuery(
            "SELECT * FROM $table WHERE $fyFilter AND rowid < ? $isDelFilter ORDER BY rowid DESC LIMIT 1",
            [_selectedFinancialYear, currentDbRowId]
          );
        }

        if (result.isEmpty) {
          if (currentNum != null && currentNum > 0) {
            result = await db.rawQuery(
              "SELECT * FROM $table WHERE (CAST($replaceStr AS INTEGER) < ? OR (CAST($replaceStr AS INTEGER) = ? AND rowid < ?)) $isDelFilter ORDER BY date DESC, CAST($replaceStr AS INTEGER) DESC, rowid DESC LIMIT 1",
              [currentNum, currentNum, currentDbRowId]
            );
          }
          if (result.isEmpty && currentDbRowId > 0) {
            result = await db.rawQuery(
              "SELECT * FROM $table WHERE rowid < ? $isDelFilter ORDER BY rowid DESC LIMIT 1",
              [currentDbRowId]
            );
          }
          if (result.isEmpty && currentDateStr.isNotEmpty) {
            result = await db.rawQuery(
              "SELECT * FROM $table WHERE date < ? $isDelFilter ORDER BY date DESC, rowid DESC LIMIT 1",
              [currentDateStr]
            );
          }
        }
        break;

      case 'next':
        if (currentNum != null && currentNum > 0) {
          result = await db.rawQuery(
            "SELECT * FROM $table WHERE $fyFilter AND (CAST($replaceStr AS INTEGER) > ? OR (CAST($replaceStr AS INTEGER) = ? AND rowid > ?)) $isDelFilter ORDER BY CAST($replaceStr AS INTEGER) ASC, rowid ASC LIMIT 1",
            [_selectedFinancialYear, currentNum, currentNum, currentDbRowId]
          );
        } else if (currentDbRowId > 0) {
          result = await db.rawQuery(
            "SELECT * FROM $table WHERE $fyFilter AND rowid > ? $isDelFilter ORDER BY rowid ASC LIMIT 1",
            [_selectedFinancialYear, currentDbRowId]
          );
        }

        if (result.isEmpty) {
          if (currentNum != null && currentNum > 0) {
            result = await db.rawQuery(
              "SELECT * FROM $table WHERE (CAST($replaceStr AS INTEGER) > ? OR (CAST($replaceStr AS INTEGER) = ? AND rowid > ?)) $isDelFilter ORDER BY date ASC, CAST($replaceStr AS INTEGER) ASC, rowid ASC LIMIT 1",
              [currentNum, currentNum, currentDbRowId]
            );
          }
          if (result.isEmpty && currentDbRowId > 0) {
            result = await db.rawQuery(
              "SELECT * FROM $table WHERE rowid > ? $isDelFilter ORDER BY rowid ASC LIMIT 1",
              [currentDbRowId]
            );
          }
          if (result.isEmpty && currentDateStr.isNotEmpty) {
            result = await db.rawQuery(
              "SELECT * FROM $table WHERE date > ? $isDelFilter ORDER BY date ASC, rowid ASC LIMIT 1",
              [currentDateStr]
            );
          }
        }
        break;
    }

    if (result.isNotEmpty) {
      return result.first;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getInvoiceItems(String invoiceNo, {bool isPurchase = false, bool isSaleReturn = false, bool isPurchaseReturn = false}) async {
    final db = await DbHelper.instance.database;

    if (isPurchase) {
      return await db.rawQuery('''
        SELECT pi.*, p.rack_id as master_rack, p.hsn_code as master_hsn, p.s_disc_percent as master_s_disc
        FROM purchase_items pi
        LEFT JOIN product_master p ON pi.product_id = p.id
        WHERE pi.entry_no = ?
      ''', [invoiceNo]);
    }

    if (isPurchaseReturn) {
      return await db.query('purchase_return_items', where: 'entry_no = ?', whereArgs: [invoiceNo]);
    }

    if (isSaleReturn) {
      return await db.rawQuery('''
        SELECT ri.*, ri.quantity as qty, ri.expiry_date as expiry, p.name as master_product_name, p.hsn_code as master_hsn, p.gst_percent as master_gst, p.packing as master_packing,
               p.mrp as master_mrp, p.purchase_rate as master_prate, p.sale_rate as master_srate
        FROM sales_return_items ri
        LEFT JOIN product_master p ON ri.product_id = p.id
        WHERE ri.return_no = ? OR ri.return_no = ?
      ''', [invoiceNo, "SRET-$invoiceNo"]);
    }

    // Join sales_items with product_master to get the actual product names
    return await db.rawQuery('''
      SELECT s.*, p.name as product_name 
      FROM sales_items s
      LEFT JOIN product_master p ON s.product_id = p.id
      WHERE s.invoice_no = ?
    ''', [invoiceNo]);
  }

  Future<List<Map<String, dynamic>>> getProductPurchaseHistory(String productName, {String? productId}) async {
    final db = await DbHelper.instance.database;
    final cleanName = productName.trim();
    final cleanId = productId?.trim() ?? '';

    final hasId = cleanId.isNotEmpty;
    final String whereClause = hasId 
        ? "(i.product_id = ? OR (i.product_name IS NOT NULL AND i.product_name = ? COLLATE NOCASE))" 
        : "TRIM(i.product_name) = ? COLLATE NOCASE";
    final List<dynamic> whereArgs = hasId ? [cleanId, cleanName] : [cleanName];

    return await db.rawQuery('''
      SELECT e.entry_no, 
             e.date,
             e.supplier_name, 
             e.financial_year,
             i.qty, 
             i.f_qty,
             i.p_rate, i.mrp, i.s_rate, i.batch, i.expiry, 
             i.l_cost, i.disc_percent, i.packin
      FROM purchase_items i
      JOIN purchase_entries e ON i.entry_no = e.entry_no
      WHERE $whereClause
        AND IFNULL(e.is_deleted, 0) = 0
      ORDER BY e.date DESC, e.entry_no DESC
      LIMIT 30
    ''', whereArgs);
  }

  Future<Map<String, dynamic>> getBatchPurchaseMetadata(String productName, {String productId = "", String batch = ""}) async {
    final db = await DbHelper.instance.database;
    final cleanName = productName.trim();
    final cleanBatch = batch.trim();

    try {
      final List<Map<String, dynamic>> res = await db.rawQuery('''
        SELECT pe.supplier_name, 
               IFNULL(NULLIF(pe.sup_inv_no, ''), pe.entry_no) as inv_no, 
               pi.p_rate, 
               pi.mrp,
               pi.gst_percent,
               pi.disc_percent
        FROM purchase_items pi
        JOIN purchase_entries pe ON pi.entry_no = pe.entry_no
        WHERE (TRIM(pi.product_name) = ? COLLATE NOCASE 
               OR (pi.product_id IS NOT NULL AND pi.product_id != '' AND pi.product_id = ?))
          AND (? = '' OR TRIM(pi.batch) = ? COLLATE NOCASE)
          AND IFNULL(pe.is_deleted, 0) = 0
        ORDER BY pe.date DESC, CAST(pe.entry_no AS INTEGER) DESC
        LIMIT 1
      ''', [cleanName, productId, cleanBatch, cleanBatch]);

      if (res.isNotEmpty) {
        return {
          'supplier': res.first['supplier_name']?.toString() ?? '',
          'inv_no': res.first['inv_no']?.toString() ?? '',
          'p_rate': (res.first['p_rate'] as num?)?.toDouble() ?? 0.0,
          'mrp': (res.first['mrp'] as num?)?.toDouble() ?? 0.0,
          'gst_percent': (res.first['gst_percent'] as num?)?.toDouble() ?? 0.0,
          'disc_percent': (res.first['disc_percent'] as num?)?.toDouble() ?? 0.0,
        };
      }
    } catch (e) {
      debugPrint("Error fetching batch purchase metadata: $e");
    }
    return {};
  }

  Future<List<PurchaseReturnEntry>> fetchPurchaseReturnsInDateRange(DateTime from, DateTime to, {bool loadItems = true, int? limit, int? offset}) async {
    final db = await DbHelper.instance.database;
    final fromStr = DateTime(from.year, from.month, from.day, 0, 0, 0).toIso8601String();
    final toStr = DateTime(to.year, to.month, to.day, 23, 59, 59).toIso8601String();

    final List<Map<String, dynamic>> maps = await db.query(
        'purchase_return_entries',
        where: "date >= ? AND date <= ? AND (financial_year = ? OR financial_year IS NULL OR financial_year = '') AND IFNULL(is_deleted, 0) = 0",
        whereArgs: [fromStr, toStr, _selectedFinancialYear],
        orderBy: 'date DESC',
        limit: limit,
        offset: offset
    );

    Map<String, List<PurchaseItem>> itemsMap = {};
    if (loadItems && maps.isNotEmpty) {
      final List<String> ids = maps.map((m) => m['entry_no'].toString()).toList();
      final String inClause = ids.map((no) => "'$no'").join(',');
      final List<Map<String, dynamic>> itemsData = await db.rawQuery('SELECT * FROM purchase_return_items WHERE entry_no IN ($inClause)');

      for (var i in itemsData) {
        final en = i['entry_no'].toString();
        itemsMap.putIfAbsent(en, () => []).add(PurchaseItem(
          id: i['product_id']?.toString() ?? "",
          productName: i['product_name'] ?? "",
          batch: i['batch'] ?? "",
          expiry: i['expiry'] ?? "",
          packin: (i['packin'] as num?)?.toInt() ?? 1,
          qty: (i['qty'] as num?)?.toInt() ?? 0,
          fQty: (i['f_qty'] as num?)?.toInt() ?? 0,
          mrp: (i['mrp'] as num?)?.toDouble() ?? 0.0,
          pRate: (i['p_rate'] as num?)?.toDouble() ?? 0.0,
          total: (i['total'] as num?)?.toDouble() ?? 0.0,
          sRate: (i['s_rate'] as num?)?.toDouble() ?? 0.0,
          gstPercent: (i['gst_percent'] as num?)?.toDouble() ?? 0.0,
          discPercent: (i['disc_percent'] as num?)?.toDouble() ?? 0.0,
          reason: i['reason'] ?? "",
          supplier: i['supplier'] ?? "",
          hsnCode: i['hsn_code'] ?? "",
        ));
      }
    }

    return maps.map((p) {
      DateTime prDate = DateTime.parse(p['date']);
      return PurchaseReturnEntry(
        entryNo: p['entry_no']?.toString() ?? "",
        date: prDate,
        supplierName: p['supplier_name'] ?? "",
        originalPurchaseNo: p['original_purchase_no'] ?? "",
        doneBy: p['done_by'] ?? "",
        items: itemsMap[p['entry_no'].toString()] ?? [],
        grandTotal: (p['grand_total'] as num?)?.toDouble() ?? 0.0,
        financialYear: p['financial_year'] ?? _getCalculatedFY(prDate),
      );
    }).toList();
  }

  Future<List<SaleReturnInvoice>> fetchSaleReturnsInDateRange(DateTime from, DateTime to, {bool loadItems = true, int? limit, int? offset}) async {
    final db = await DbHelper.instance.database;
    final fromStr = DateTime(from.year, from.month, from.day, 0, 0, 0).toIso8601String();
    final toStr = DateTime(to.year, to.month, to.day, 23, 59, 59).toIso8601String();

    final List<Map<String, dynamic>> maps = await db.query(
        'sales_return_invoices',
        where: "date >= ? AND date <= ? AND (financial_year = ? OR financial_year IS NULL OR financial_year = '') AND IFNULL(is_deleted, 0) = 0",
        whereArgs: [fromStr, toStr, _selectedFinancialYear],
        orderBy: 'date DESC',
        limit: limit,
        offset: offset
    );

    Map<String, List<SaleItem>> itemsMap = {};
    if (loadItems && maps.isNotEmpty) {
      final List<String> ids = maps.map((m) => m['entry_no'].toString()).toList();
      final String inClause = ids.map((no) => "'$no'").join(',');
      final List<Map<String, dynamic>> itemsData = await db.rawQuery('SELECT * FROM sales_return_items WHERE return_no IN ($inClause)');

      for (var i in itemsData) {
        final en = i['return_no'].toString();
        final pId = i['product_id'] ?? "";
        final pBatch = i['batch_number'] ?? "";

        int qVal = (i['qty'] as num?)?.toInt() ?? (i['quantity'] as num?)?.toInt() ?? 0;
        int pVal = (i['packing'] as num?)?.toInt() ?? (i['packin'] as num?)?.toInt() ?? 1;
        double mrpVal = (i['mrp'] as num?)?.toDouble() ?? 0.0;
        double sRateVal = (i['sale_rate'] as num?)?.toDouble() ?? 0.0;
        double discPctVal = (i['disc_percent'] as num?)?.toDouble() ?? 0.0;
        double discAmtVal = (i['disc_amt'] as num?)?.toDouble() ?? 0.0;
        double gstPctVal = (i['gst_percent'] as num?)?.toDouble() ?? 12.0;

        itemsMap.putIfAbsent(en, () => []).add(SaleItem(
          product: Product(
            id: pId, 
            name: i['product_name'] ?? "Unknown", 
            batch: pBatch, 
            expiry: i['expiry_date'] ?? "",
            mrp: mrpVal,
            salePrice: sRateVal,
            purchaseRate: (i['purchase_rate'] as num?)?.toDouble() ?? 0.0,
            landingCost: (i['landing_cost'] as num?)?.toDouble() ?? 0.0,
            gstPercent: gstPctVal,
            packSize: pVal,
            hsnCode: i['hsn_code']?.toString() ?? "",
          ),
          qty: qVal,
          packin: pVal,
          mrp: mrpVal,
          sRate: sRateVal,
          taxableSP: sRateVal,
          discPercent: discPctVal,
          discAmt: discAmtVal,
          gstPercent: gstPctVal,
          total: (i['total'] as num?)?.toDouble() ?? 0.0,
          purchaseRate: (i['purchase_rate'] as num?)?.toDouble() ?? 0.0,
          landingCost: (i['landing_cost'] as num?)?.toDouble() ?? 0.0,
          supplier: i['supplier_name']?.toString() ?? "",
        ));
      }
    }

    return maps.map((s) {
      DateTime srDate = DateTime.parse(s['date']);
      return SaleReturnInvoice(
        entryNo: s['entry_no'],
        date: srDate,
        customerAcc: s['customer_acc'] ?? "Cash",
        patient: s['patient'] ?? "General",
        doctor: s['doctor'] ?? "Unknown",
        originalInvoiceNo: s['original_invoice_no'] ?? "",
        items: itemsMap[s['entry_no']] ?? [],
        subTotal: (s['sub_total'] as num?)?.toDouble() ?? 0.0,
        discount: (s['discount'] as num?)?.toDouble() ?? 0.0,
        roundOff: (s['round_off'] as num?)?.toDouble() ?? 0.0,
        grandTotal: (s['grand_total'] as num?)?.toDouble() ?? 0.0,
        narration: s['narration']?.toString() ?? "",
        gstMode: (s['gst_mode'] as int?) ?? 1,
        financialYear: s['financial_year'] ?? _getCalculatedFY(srDate),
      );
    }).toList();
  }

  Future<List<PurchaseEntry>> fetchPurchasesInDateRange(DateTime from, DateTime to, {bool loadItems = true, int? limit, int? offset}) async {
    final db = await DbHelper.instance.database;
    final fromStr = DateTime(from.year, from.month, from.day, 0, 0, 0).toIso8601String();
    final toStr = DateTime(to.year, to.month, to.day, 23, 59, 59).toIso8601String();

    final List<Map<String, dynamic>> maps = await db.query(
        'purchase_entries',
        where: "date >= ? AND date <= ? AND (financial_year = ? OR financial_year IS NULL OR financial_year = '') AND IFNULL(is_deleted, 0) = 0",
        whereArgs: [fromStr, toStr, _selectedFinancialYear],
        orderBy: 'date DESC',
        limit: limit,
        offset: offset
    );

    Map<String, List<PurchaseItem>> itemsMap = {};
    if (loadItems && maps.isNotEmpty) {
      final List<String> ids = maps.map((m) => m['entry_no'].toString()).toList();
      final String inClause = ids.map((no) => "'$no'").join(',');
      final List<Map<String, dynamic>> itemsData = await db.rawQuery('SELECT * FROM purchase_items WHERE entry_no IN ($inClause)');

      for (var i in itemsData) {
        final en = i['entry_no'].toString();
        itemsMap.putIfAbsent(en, () => []).add(PurchaseItem(
          id: i['product_id']?.toString() ?? "",
          productName: i['product_name'] ?? "",
          extra: i['extra'] ?? "",
          batch: i['batch'] ?? "",
          expiry: i['expiry'] ?? "",
          packin: (i['packin'] as num?)?.toInt() ?? 1,
          qty: (i['qty'] as num?)?.toInt() ?? 0,
          fQty: (i['f_qty'] as num?)?.toInt() ?? 0,
          mrp: (i['mrp'] as num?)?.toDouble() ?? 0.0,
          pRate: (i['p_rate'] as num?)?.toDouble() ?? 0.0,
          gross: (i['gross'] as num?)?.toDouble() ?? 0.0,
          discPercent: (i['disc_percent'] as num?)?.toDouble() ?? 0.0,
          discAmt: (i['disc_amt'] as num?)?.toDouble() ?? 0.0,
          net: (i['net'] as num?)?.toDouble() ?? 0.0,
          gstPercent: (i['gst_percent'] as num?)?.toDouble() ?? 0.0,
          gstAmt: (i['gst_amt'] as num?)?.toDouble() ?? 0.0,
          total: (i['total'] as num?)?.toDouble() ?? 0.0,
          sRate: (i['s_rate'] as num?)?.toDouble() ?? 0.0,
          lCost: (i['l_cost'] as num?)?.toDouble() ?? 0.0,
        ));
      }
    }

    return maps.map((p) {
      DateTime purDate = DateTime.parse(p['date']);
      return PurchaseEntry(
        entryNo: p['entry_no']?.toString() ?? "",
        date: purDate,
        supplierName: p['supplier_name'] ?? "",
        supInvNo: cleanInvoiceNo(p['sup_inv_no']),
        supInvDate: p['sup_inv_date'] != null ? (DateTime.tryParse(p['sup_inv_date']) ?? purDate) : purDate,
        doneBy: p['done_by'] ?? "",
        invTotal: (p['inv_total'] as num?)?.toDouble() ?? 0.0,
        remarks: p['remarks'] ?? "",
        days: (p['days'] as num?)?.toInt() ?? 0,
        items: itemsMap[p['entry_no'].toString()] ?? [],
        subTotal: (p['sub_total'] as num?)?.toDouble() ?? 0.0,
        discount: (p['discount'] as num?)?.toDouble() ?? 0.0,
        otherCharge: (p['other_charge'] as num?)?.toDouble() ?? 0.0,
        roundOff: (p['round_off'] as num?)?.toDouble() ?? 0.0,
        grandTotal: (p['grand_total'] as num?)?.toDouble() ?? 0.0,
        financialYear: p['financial_year'] ?? _getCalculatedFY(purDate),
        paymentStatus: p['payment_status'] ?? 0,
        paymentMode: p['payment_mode'],
        paymentRemarks: p['payment_remarks'],
        paymentDate: p['payment_date'] != null ? DateTime.tryParse(p['payment_date']) : null,
        paidAmount: (p['paid_amount'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();
  }

  Future<List<SaleInvoice>> fetchSalesInDateRange(DateTime from, DateTime to, {bool loadItems = true, int? limit, int? offset, bool includeDeleted = false}) async {
    final db = await DbHelper.instance.database;
    final fromStr = DateTime(from.year, from.month, from.day, 0, 0, 0).toIso8601String();
    final toStr = DateTime(to.year, to.month, to.day, 23, 59, 59).toIso8601String();
    final fromDay = DateFormat('yyyy-MM-dd').format(from);
    final toDay = DateFormat('yyyy-MM-dd').format(to);

    final String deletedClause = includeDeleted ? '' : 'AND (is_deleted = 0 OR is_deleted IS NULL)';

    // Handles both ISO strings ('2026-08-15...') and slash formats ('15/08/2026')
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT * FROM sales_invoices
      WHERE (customer_acc != 'Special Order')
        $deletedClause
        AND (
          (date BETWEEN ? AND ?)
          OR (
            date LIKE '%/%' 
            AND (substr(date, 7, 4) || '-' || substr(date, 4, 2) || '-' || substr(date, 1, 2)) BETWEEN ? AND ?
          )
          OR (date(date) BETWEEN ? AND ?)
        )
      ORDER BY date DESC, CAST(entry_no AS INTEGER) DESC
      ${limit != null ? 'LIMIT $limit' : ''}
      ${offset != null ? 'OFFSET $offset' : ''}
    ''', [fromStr, toStr, fromDay, toDay, fromDay, toDay]);

    Map<String, List<SaleItem>> itemsMap = {};
    if (loadItems && maps.isNotEmpty) {
      final List<String> ids = maps.map((m) => m['entry_no'].toString()).toList();
      final String inClause = ids.map((no) => "'$no'").join(',');
      final List<Map<String, dynamic>> itemsData = await db.rawQuery('''
        SELECT si.*, p.name as master_prod_name 
        FROM sales_items si
        LEFT JOIN product_master p ON si.product_id = p.id
        WHERE si.invoice_no IN ($inClause)
      ''');
      
      for (var m in itemsData) {
        final en = m['invoice_no'].toString();
        final pName = (m['product_name'] ?? m['master_prod_name'] ?? 'Unknown').toString();
        final pId = m['product_id']?.toString() ?? '';
        final bNo = m['batch_number']?.toString() ?? '';
        final expVal = m['expiry_date']?.toString() ?? '';
        final packVal = (m['packin'] as num?)?.toInt() ?? 1;
        final sRateVal = (m['s_rate'] as num?)?.toDouble() ?? (m['sale_rate'] as num?)?.toDouble() ?? 0.0;
        final taxSpVal = (m['taxable_sp'] as num?)?.toDouble() ?? sRateVal;

        itemsMap.putIfAbsent(en, () => []).add(SaleItem(
          product: Product(id: pId, name: pName, batch: bNo, expiry: expVal, packSize: packVal, salePrice: sRateVal),
          qty: (m['qty'] as num?)?.toInt() ?? 0,
          packin: packVal,
          mrp: (m['mrp'] as num?)?.toDouble() ?? 0.0,
          sRate: sRateVal,
          taxableSP: taxSpVal,
          discPercent: (m['disc_percent'] as num?)?.toDouble() ?? 0.0,
          discAmt: (m['disc_amt'] as num?)?.toDouble() ?? 0.0,
          gstPercent: (m['gst_percent'] as num?)?.toDouble() ?? 0.0,
          gstAmt: (m['gst_amt'] as num?)?.toDouble() ?? 0.0,
          cgstAmt: (m['cgst_amt'] as num?)?.toDouble() ?? 0.0,
          sgstAmt: (m['sgst_amt'] as num?)?.toDouble() ?? 0.0,
          igstAmt: (m['igst_amt'] as num?)?.toDouble() ?? 0.0,
          total: (m['total'] as num?)?.toDouble() ?? 0.0,
          purchaseRate: (m['purchase_rate'] as num?)?.toDouble() ?? 0.0,
          landingCost: (m['landing_cost'] as num?)?.toDouble() ?? 0.0,
          supplier: m['supplier_name']?.toString() ?? "",
        ));
      }
    }

    return maps.map((s) {
      DateTime parsedDate;
      try { 
        parsedDate = DateTime.parse(s['date']); 
      } catch (_) { 
        parsedDate = DateTime.tryParse(s['date'].toString().replaceAll('/', '-')) ?? DateTime.now(); 
      }

      return SaleInvoice(
        entryNo: s['entry_no']?.toString() ?? "",
        date: parsedDate,
        customerAcc: s['customer_acc'] ?? "Cash",
        patient: s['patient'] ?? "General",
        mobile: s['mobile'] ?? "",
        doctor: s['doctor'] ?? "Unknown",
        doctorRegNo: s['doctor_reg_no'] ?? "",
        specialOrderJson: s['special_order_json'] ?? "[]",
        taxType: s['tax_type'] ?? "Non Gst",
        days: s['days'] ?? 0,
        items: itemsMap[s['entry_no'].toString()] ?? [],
        subTotal: (s['sub_total'] as num?)?.toDouble() ?? (s['total_amount'] as num?)?.toDouble() ?? 0.0,
        discountPercent: (s['discount_percent'] as num?)?.toDouble() ?? 0.0,
        discount: (s['discount'] as num?)?.toDouble() ?? 0.0,
        additionalDiscount: (s['additional_discount'] as num?)?.toDouble() ?? 0.0,
        otherCharge: (s['other_charge'] as num?)?.toDouble() ?? 0.0,
        rcvdAmt: (s['rcvd_amt'] as num?)?.toDouble() ?? 0.0,
        roundOff: (s['round_off'] as num?)?.toDouble() ?? 0.0,
        grandTotal: (s['grand_total'] as num?)?.toDouble() ?? (s['total_amount'] as num?)?.toDouble() ?? 0.0,
        agent: s['agent'] ?? "Admin",
        expectingDate: s['expecting_date'] ?? "",
        specialCustomerName: s['special_customer_name'] ?? "",
        specialCustomerPhone: s['special_customer_phone'] ?? "",
        paymentRemarks: s['payment_remarks'] ?? "",
        secondaryAcc: s['secondary_acc'] ?? "",
        secondaryAmt: (s['secondary_amt'] as num?)?.toDouble() ?? 0.0,
        financialYear: s['financial_year'] ?? _getCalculatedFY(parsedDate),
        isDeleted: (s['is_deleted'] as int?) == 1,
        isPaid: (s['is_paid'] as int?) == 1,
      );
    }).toList();
  }

  Future<List<Map<String, dynamic>>> fetchPatientLedger(String patientName) async {
    final db = await DbHelper.instance.database;
    List<Map<String, dynamic>> ledger = [];

    // 1. Sales
    final List<Map<String, dynamic>> sales = await db.query(
        'sales_invoices',
        where: 'patient = ? AND is_deleted = 0',
        whereArgs: [patientName],
        orderBy: 'date ASC'
    );
    for (var s in sales) {
      DateTime dt = DateTime.tryParse(s['date'].toString()) ?? DateTime.now();
      ledger.add({
        'date': dt,
        'reference': s['entry_no'],
        'debit': (s['grand_total'] as num?)?.toDouble() ?? 0.0,
        'credit': 0.0,
        'type': 'SALE',
        'invoice': s['entry_no'],
      });

      double rcvd = (s['rcvd_amt'] as num?)?.toDouble() ?? 0.0;
      if (rcvd > 0) {
        ledger.add({
          'date': dt,
          'reference': "AUTO-${s['entry_no']}",
          'debit': 0.0,
          'credit': rcvd,
          'type': 'RECEIPT',
          'method': s['customer_acc'],
          'invoice': s['entry_no'],
          'remarks': "Immediate Payment - ${s['customer_acc']}",
        });
      }
    }

    // 2. Sales Returns
    final List<Map<String, dynamic>> returns = await db.query(
        'sales_return_invoices',
        where: 'patient = ? AND is_deleted = 0',
        whereArgs: [patientName],
        orderBy: 'date ASC'
    );
    for (var sr in returns) {
      DateTime dt = DateTime.tryParse(sr['date'].toString()) ?? DateTime.now();
      ledger.add({
        'date': dt,
        'reference': sr['entry_no'],
        'debit': 0.0,
        'credit': (sr['grand_total'] as num?)?.toDouble() ?? 0.0,
        'type': 'SALE RETURN',
        'invoice': sr['original_invoice_no'],
        'remarks': "Return against Inv ${sr['original_invoice_no']}",
      });
    }

    // 3. Manual Receipts
    final List<Map<String, dynamic>> payments = await db.query(
        'patient_payments',
        where: 'patient_name = ?',
        whereArgs: [patientName],
        orderBy: 'date ASC'
    );
    for (var pay in payments) {
      DateTime dt = DateTime.tryParse(pay['date'].toString()) ?? DateTime.now();
      ledger.add({
        'date': dt,
        'reference': pay['id'],
        'debit': 0.0,
        'credit': (pay['amount'] as num?)?.toDouble() ?? 0.0,
        'type': 'RECEIPT',
        'remarks': pay['remarks'],
        'method': pay['payment_method'],
        'invoice': pay['invoice_no'],
      });
    }

    ledger.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    return ledger;
  }


  Future<List<Map<String, dynamic>>> fetchSpecialOrders({DateTime? filterDate}) async {
    final db = await DbHelper.instance.database;
    String dateClause = "";
    List<dynamic> whereArgs = [];

    if (filterDate != null) {
      final dateStr = DateFormat('yyyy-MM-dd').format(filterDate);
      final fromStr = DateTime(filterDate.year, filterDate.month, filterDate.day, 0, 0, 0).toIso8601String();
      final toStr = DateTime(filterDate.year, filterDate.month, filterDate.day, 23, 59, 59).toIso8601String();

      dateClause = '''
        AND (
          (date BETWEEN ? AND ?)
          OR (
            date LIKE '%/%' 
            AND (substr(date, 7, 4) || '-' || substr(date, 4, 2) || '-' || substr(date, 1, 2)) = ?
          )
          OR (date(date) = ?)
        )
      ''';
      whereArgs.addAll([fromStr, toStr, dateStr, dateStr]);
    }

    return await db.rawQuery('''
      SELECT entry_no, date, agent, patient, mobile, special_order_json, 
             special_customer_name, special_customer_phone, expecting_date
      FROM sales_invoices
      WHERE (is_deleted = 0 OR is_deleted IS NULL)
        AND special_order_json IS NOT NULL 
        AND special_order_json != '[]'
        $dateClause
      ORDER BY date DESC
    ''', whereArgs);
  }

  // ==========================================
  // ORDER CONFIRMATION PROVIDER WRAPPERS
  // ==========================================

  Future<void> saveOrderConfirmation(OrderConfirmation order) async {
    await DbHelper.instance.saveOrderConfirmation(order);
    notifyListeners();
  }

  Future<List<OrderConfirmation>> fetchOrderConfirmations({
    DateTime? fromDate,
    DateTime? toDate,
    String? statusFilter,
    String? searchQuery,
  }) async {
    return await DbHelper.instance.fetchOrderConfirmations(
      fromDate: fromDate,
      toDate: toDate,
      statusFilter: statusFilter,
      searchQuery: searchQuery,
    );
  }

  Future<void> updateOrderConfirmationStatus(String orderId, String status, {String? receivedDate}) async {
    await DbHelper.instance.updateOrderConfirmationStatus(orderId, status, receivedDate: receivedDate);
    notifyListeners();
  }

  Future<void> updateOrderItemReceivedStatus({
    required int itemId,
    required int receivedQty,
    required String status,
    String? receivedDate,
  }) async {
    await DbHelper.instance.updateOrderItemReceivedStatus(
      itemId: itemId,
      receivedQty: receivedQty,
      status: status,
      receivedDate: receivedDate,
    );
    notifyListeners();
  }

  Future<void> deleteOrderConfirmation(String orderId) async {
    await DbHelper.instance.deleteOrderConfirmation(orderId);
    notifyListeners();
  }

  Future<List<Product>> getProducts() async => _products;
  Future<List<Supplier>> fetchSuppliers() async => _supplierMaster;

  Future<List<Map<String, dynamic>>> loadOrderListOptimized() async {
    final db = await DbHelper.instance.database;

    // 1. Fetch all orders in a single fast query
    final List<Map<String, dynamic>> orderRows = await db.rawQuery('''
      SELECT 
        o.id, 
        o.order_no, 
        o.date, 
        o.supplier_name, 
        o.status, 
        o.total_amount,
        o.total_items,
        COUNT(oi.id) as item_count,
        IFNULL(SUM(oi.qty), 0) as total_qty
      FROM orders o
      LEFT JOIN order_items oi ON oi.order_id = o.id
      GROUP BY o.id
      ORDER BY o.date DESC
    ''');

    return orderRows;
  }

  Future<List<Map<String, dynamic>>> loadActiveOrderProducts({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await DbHelper.instance.database;
    final todayStr = DateFormat('yyyy-MM-dd').format(endDate ?? DateTime.now());
    final startStr = startDate != null ? DateFormat('yyyy-MM-dd').format(startDate) : '';

    // Optimization: Focus ONLY on items with sales activity in the range as requested.
    // This significantly reduces the dataset and improves speed.
    final String query = '''
      SELECT 
        p.id,
        p.name,
        p.generic_name,
        p.packing as pack_size,
        p.mrp,
        p.purchase_rate,
        p.reorder_level,
        IFNULL(p.preferred_wholesale, '') as supplier_name,
        IFNULL(stk.total_stock, 0) as current_stock,
        IFNULL(sales_stat.total_sold, 0) as sales_qty,
        '' as last_pur_date
      FROM product_master p
      INNER JOIN (
        SELECT si.product_id
        FROM sales_items si
        JOIN sales_invoices sn ON si.invoice_no = sn.entry_no
        WHERE (sn.is_deleted = 0 OR sn.is_deleted IS NULL)
          AND sn.date <= '$todayStr'
          ${startStr.isNotEmpty ? "AND sn.date >= '$startStr'" : ""}
        GROUP BY si.product_id
      ) act ON p.id = act.product_id
      LEFT JOIN (
        SELECT product_id, SUM(current_stock) as total_stock 
        FROM stock_batches 
        WHERE current_stock > 0
        GROUP BY product_id
      ) stk ON p.id = stk.product_id
      LEFT JOIN (
        SELECT si.product_id, SUM(si.quantity) as total_sold 
        FROM sales_items si 
        JOIN sales_invoices sn ON si.invoice_no = sn.entry_no
        WHERE (sn.is_deleted = 0 OR sn.is_deleted IS NULL)
          AND sn.date <= '$todayStr'
          ${startStr.isNotEmpty ? "AND sn.date >= '$startStr'" : ""}
        GROUP BY si.product_id
      ) sales_stat ON p.id = sales_stat.product_id
      WHERE IFNULL(p.is_active, 1) = 1
      ORDER BY p.name ASC
    ''';

    return await db.rawQuery(query);
  }

  Future<void> deleteSpecialOrderItem(String entryNo, String productName) async {
    final db = await DbHelper.instance.database;
    final List<Map<String, dynamic>> maps = await db.query(
        'sales_invoices',
        columns: ['special_order_json'],
        where: 'entry_no = ?',
        whereArgs: [entryNo]
    );

    if (maps.isNotEmpty) {
      String jsonStr = maps.first['special_order_json'] ?? "[]";
      try {
        List<dynamic> list = jsonDecode(jsonStr);
        list.removeWhere((item) => item['name'] == productName);

        await db.update(
            'sales_invoices',
            {'special_order_json': jsonEncode(list)},
            where: 'entry_no = ?',
            whereArgs: [entryNo]
        );
        notifyListeners();
      } catch (e) {
        debugPrint("Error deleting special order item: $e");
      }
    }
  }

  Future<List<Map<String, dynamic>>> getProductSaleHistory(String productName, {String? productId}) async {
    final db = await DbHelper.instance.database;
    try {
      final cleanName = productName.trim();
      final cleanId = productId?.trim() ?? '';
      final hasId = cleanId.isNotEmpty;
      
      String whereClause;
      List<dynamic> whereArgs;

      if (hasId) {
        whereClause = "WHERE i.product_id = ? OR (p.name = ? COLLATE NOCASE OR i.product_name = ? COLLATE NOCASE)";
        whereArgs = [cleanId, cleanName, cleanName];
      } else {
        whereClause = "WHERE p.name = ? COLLATE NOCASE OR i.product_name = ? COLLATE NOCASE";
        whereArgs = [cleanName, cleanName];
      }

      // Fetch detailed sale history using item table's own data to survive stock batch deletions
      final List<Map<String, dynamic>> result = await db.rawQuery('''
        SELECT i.invoice_no as entry_no, e.date, e.financial_year, i.batch_number as batch, i.expiry_date as expiry, 
               i.qty, 0 as f_qty, i.mrp, i.s_rate, i.supplier_name, e.doctor, e.patient, i.disc_percent
        FROM sales_items i
        JOIN sales_invoices e ON i.invoice_no = e.entry_no
        LEFT JOIN product_master p ON i.product_id = p.id
        $whereClause
        ORDER BY e.date DESC, e.entry_no DESC
        LIMIT 30
      ''', whereArgs);
      return result;
    } catch (e) {
      debugPrint("Error fetching sales history: $e");
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getProductMovementAnalysis() async {
    final db = await DbHelper.instance.database;
    final now = DateTime.now();
    final date3m = now.subtract(const Duration(days: 90)).toIso8601String();
    final date1m = now.subtract(const Duration(days: 30)).toIso8601String();
    final date6m = now.subtract(const Duration(days: 180)).toIso8601String();
    final date1y = now.subtract(const Duration(days: 365)).toIso8601String();

    // This query calculates all requested metrics in one go per product
    return await db.rawQuery('''
      SELECT 
        p.id,
        p.name as productName,
        p.manufacturer_id as company,
        p.preferred_wholesale as preferredWholesale,
        p.lead_time as supplierLeadTimeDays,
        p.packing as packSize,
        IFNULL(SUM(b.current_stock), 0) as currentBalance,
        
        -- Last 30 Days Total
        IFNULL((SELECT SUM(si.quantity) 
                FROM sales_items si 
                JOIN sales_invoices sn ON si.invoice_no = sn.invoice_no 
                WHERE si.product_id = p.id AND sn.date >= ?), 0) as last30DaysSale,
        
        -- Max Daily Sale in last 30 days
        IFNULL((SELECT MAX(daily_total) FROM (
            SELECT SUM(si2.quantity) as daily_total
            FROM sales_items si2
            JOIN sales_invoices sn2 ON si2.invoice_no = sn2.invoice_no
            WHERE si2.product_id = p.id AND sn2.date >= ?
            GROUP BY date(sn2.date)
        )), 0) as maxDailySale,

        -- Last 3 Months Total
        IFNULL((SELECT SUM(si.quantity) 
                FROM sales_items si 
                JOIN sales_invoices sn ON si.invoice_no = sn.invoice_no 
                WHERE si.product_id = p.id AND sn.date >= ?), 0) as last3MonthsTotal,
        
        -- Max Sale in 3 Months (Individual Invoice Max)
        IFNULL((SELECT MAX(si.quantity) 
                FROM sales_items si 
                JOIN sales_invoices sn ON si.invoice_no = sn.invoice_no 
                WHERE si.product_id = p.id AND sn.date >= ?), 0) as maxSale3Months,
        
        -- Max Sale in 6 Months (Individual Invoice Max)
        IFNULL((SELECT MAX(si.quantity) 
                FROM sales_items si 
                JOIN sales_invoices sn ON si.invoice_no = sn.invoice_no 
                WHERE si.product_id = p.id AND sn.date >= ?), 0) as maxSale6Months,
        
        -- Total Sale in 1 Year
        IFNULL((SELECT SUM(si.quantity) 
                FROM sales_items si 
                JOIN sales_invoices sn ON si.invoice_no = sn.invoice_no 
                WHERE si.product_id = p.id AND sn.date >= ?), 0) as totalSale1Year,
        
        -- Sale Count in 1 Year (Number of Invoices)
        IFNULL((SELECT COUNT(DISTINCT si.invoice_no) 
                FROM sales_items si 
                JOIN sales_invoices sn ON si.invoice_no = sn.invoice_no 
                WHERE si.product_id = p.id AND sn.date >= ?), 0) as saleCount1Year
                
      FROM product_master p
      LEFT JOIN stock_batches b ON p.id = b.product_id
      GROUP BY p.id
      HAVING last3MonthsTotal > 0 OR totalSale1Year > 0 OR currentBalance < p.reorder_level OR last30DaysSale > 0
    ''', [date1m, date1m, date3m, date3m, date6m, date1y, date1y]);
  }

  Future<List<Map<String, dynamic>>> getInactiveRacksInfo({int minDays = 0}) async {
    final db = await DbHelper.instance.database;
    final cutoffDate = DateTime.now().subtract(Duration(days: minDays)).toIso8601String();

    return await db.rawQuery('''
      SELECT rack_name as name, 
             IFNULL(total_stock, 0) as total_stock, 
             last_entry_date,
             (SELECT GROUP_CONCAT(name, ', ') FROM (SELECT DISTINCT name FROM product_master WHERE rack_id = AllRacks.rack_name LIMIT 3)) as product_names
      FROM (
          SELECT name as rack_name FROM racks
          UNION
          SELECT DISTINCT rack_id FROM product_master WHERE rack_id != ''
      ) AllRacks
      LEFT JOIN (
          SELECT p.rack_id, SUM(b.current_stock) as total_stock
          FROM product_master p
          JOIN stock_batches b ON p.id = b.product_id
          GROUP BY p.rack_id
      ) Stocks ON AllRacks.rack_name = Stocks.rack_id
      LEFT JOIN (
          SELECT i.rack, MAX(e.date) as last_entry_date
          FROM purchase_items i
          JOIN purchase_entries e ON i.entry_no = e.entry_no
          GROUP BY i.rack
      ) Activity ON AllRacks.rack_name = Activity.rack
      WHERE IFNULL(total_stock, 0) = 0
      AND (last_entry_date IS NULL OR last_entry_date < ?)
      ORDER BY rack_name ASC
    ''', [cutoffDate]);
  }

  Future<List<Map<String, dynamic>>> getScheduleH1RegisterReport({
    DateTime? fromDate,
    DateTime? toDate,
    String? scheduleType,
    String? searchQuery,
  }) async {
    final db = await DbHelper.instance.database;

    String whereClause = "(s.is_deleted = 0 OR s.is_deleted IS NULL)";
    List<dynamic> args = [];

    if (fromDate != null) {
      whereClause += " AND date(s.date) >= date(?)";
      args.add(fromDate.toIso8601String());
    }
    if (toDate != null) {
      whereClause += " AND date(s.date) <= date(?)";
      args.add(toDate.toIso8601String());
    }

    if (scheduleType != null && scheduleType.isNotEmpty && scheduleType != 'ALL') {
      if (scheduleType == 'H1') {
        whereClause += " AND UPPER(IFNULL(pm.schedule, '')) LIKE '%H1%'";
      } else if (scheduleType == 'H') {
        whereClause += " AND UPPER(IFNULL(pm.schedule, '')) = 'H'";
      } else if (scheduleType == 'NRX') {
        whereClause += " AND (pm.is_nrx = 1 OR pm.is_controlled = 1 OR UPPER(IFNULL(pm.schedule, '')) LIKE '%NRX%')";
      }
    } else {
      whereClause += " AND (UPPER(IFNULL(pm.schedule, '')) LIKE '%H%' OR pm.is_nrx = 1 OR pm.is_controlled = 1)";
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      String q = "%${searchQuery.trim().toLowerCase()}%";
      whereClause += " AND (LOWER(s.patient) LIKE ? OR LOWER(s.doctor) LIKE ? OR LOWER(pm.name) LIKE ? OR LOWER(si.batch_number) LIKE ?)";
      args.addAll([q, q, q, q]);
    }

    final String sql = '''
      SELECT 
        s.entry_no,
        s.date,
        s.patient,
        s.mobile,
        s.doctor,
        s.doctor_reg_no,
        pm.name as product_name,
        IFNULL(pm.schedule, 'H') as schedule,
        IFNULL(pm.is_nrx, 0) as is_nrx,
        si.batch_number,
        si.expiry_date,
        si.qty,
        si.packin,
        si.mrp,
        si.s_rate,
        si.total
      FROM sales_invoices s
      JOIN sales_items si ON s.entry_no = si.invoice_no
      JOIN product_master pm ON si.product_id = pm.id
      WHERE $whereClause
      ORDER BY s.date DESC, s.entry_no DESC
    ''';

    return await db.rawQuery(sql, args);
  }

  Future<List<Map<String, dynamic>>> getReorderSuggestions({
    String? supplierFilter,
    String? categoryFilter,
    String? searchQuery,
  }) async {
    final db = await DbHelper.instance.database;

    String whereClause = "IFNULL(Stocks.total_stock, 0) <= pm.reorder_level AND (IFNULL(Stocks.total_stock, 0) > 0 OR pm.reorder_level > 0) AND pm.is_active = 1";
    List<dynamic> args = [];

    if (supplierFilter != null && supplierFilter.isNotEmpty && supplierFilter != 'ALL') {
      whereClause += " AND LOWER(IFNULL(pm.preferred_wholesale, '')) = ?";
      args.add(supplierFilter.toLowerCase().trim());
    }

    if (categoryFilter != null && categoryFilter.isNotEmpty && categoryFilter != 'ALL') {
      whereClause += " AND LOWER(IFNULL(pm.category_id, '')) = ?";
      args.add(categoryFilter.toLowerCase().trim());
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      whereClause += " AND (LOWER(pm.name) LIKE ? OR LOWER(pm.generic_name) LIKE ?)";
      String q = "%${searchQuery.trim().toLowerCase()}%";
      args.addAll([q, q]);
    }

    final String sql = '''
      SELECT 
        pm.id,
        pm.name as product_name,
        pm.generic_name,
        pm.hsn_code,
        pm.packing as packin,
        pm.category_id as category,
        pm.rack_id as rack,
        IFNULL(pm.preferred_wholesale, 'Unassigned') as supplier,
        pm.reorder_level,
        pm.max_level,
        pm.mrp,
        pm.purchase_rate,
        pm.sale_rate,
        pm.gst_percent,
        IFNULL(Stocks.total_stock, 0) as current_stock,
        CASE 
          WHEN (pm.max_level - IFNULL(Stocks.total_stock, 0)) > 0 
          THEN (pm.max_level - IFNULL(Stocks.total_stock, 0))
          ELSE pm.reorder_level
        END as suggested_qty
      FROM product_master pm
      LEFT JOIN (
        SELECT product_id, SUM(current_stock) as total_stock
        FROM stock_batches
        GROUP BY product_id
      ) Stocks ON pm.id = Stocks.product_id
      WHERE $whereClause
      ORDER BY supplier ASC, pm.name ASC
      LIMIT 200
    ''';

    return await db.rawQuery(sql, args);
  }

  Future<void> deleteMultipleRacks(List<String> names) async {
    final db = await DbHelper.instance.database;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      for (String name in names) {
        final products = await txn.query('product_master', where: 'rack_id = ?', whereArgs: [name]);
        await txn.delete('racks', where: 'id = ?', whereArgs: [name]);
        await txn.update('product_master', {'rack_id': ''}, where: 'rack_id = ?', whereArgs: [name]);

        for (var p in products) {
          await txn.insert('rack_history', {
            'product_id': p['id'],
            'product_name': p['name'],
            'old_rack': name,
            'new_rack': 'NONE (DELETED)',
            'change_date': now,
          });
        }
      }
    });
    _racks.removeWhere((r) => names.contains(r));
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getRackHistory(String rackName) async {
    final db = await DbHelper.instance.database;
    return await db.query('rack_history',
        where: 'old_rack = ? OR new_rack = ?',
        whereArgs: [rackName, rackName],
        orderBy: 'change_date DESC'
    );
  }

  Future<List<Map<String, dynamic>>> getAllRackHistory() async {
    final db = await DbHelper.instance.database;
    return await db.query('rack_history', orderBy: 'change_date DESC');
  }

  Future<List<Product>> searchProductsSql(String query, {bool includeGenerics = true, bool stockOnly = false, int limit = 50}) async {
    final cleanQ = Product.cleanProductName(query).toLowerCase();
    if (cleanQ.isEmpty) return [];

    try {
      final db = await DbHelper.instance.database;
      final String prefixPattern = '$cleanQ%';
      final String containsPattern = '%$cleanQ%';

      final String sql = '''
        SELECT 
          pm.id, pm.name, pm.generic_name, pm.hsn_code, pm.gst_percent, pm.packing,
          pm.mrp, pm.purchase_rate, pm.sale_rate, pm.rack_id, pm.category_id,
          pm.schedule, pm.patent, pm.reorder_level, pm.manufacturer_id,
          IFNULL(SUM(sb.current_stock), 0) as total_stock
        FROM product_master pm
        LEFT JOIN stock_batches sb ON pm.id = sb.product_id
        WHERE (pm.name LIKE ? ${includeGenerics ? 'OR pm.generic_name LIKE ?' : ''})
        ${stockOnly ? 'AND sb.current_stock > 0' : ''}
        GROUP BY pm.id
        ORDER BY 
          CASE WHEN LOWER(pm.name) LIKE ? THEN 1 ELSE 2 END,
          total_stock DESC,
          pm.name ASC
        LIMIT ?
      ''';

      final List<dynamic> args = includeGenerics 
          ? [containsPattern, containsPattern, prefixPattern, limit]
          : [containsPattern, prefixPattern, limit];

      final List<Map<String, dynamic>> rows = await db.rawQuery(sql, args);

      return rows.map((r) => Product(
        id: r['id'].toString(),
        name: r['name']?.toString() ?? 'UNKNOWN',
        genericName: r['generic_name']?.toString() ?? '',
        hsnCode: r['hsn_code']?.toString() ?? '',
        gstPercent: (r['gst_percent'] as num?)?.toDouble() ?? 12.0,
        packSize: (r['packing'] as num?)?.toInt() ?? 1,
        mrp: (r['mrp'] as num?)?.toDouble() ?? 0.0,
        purchaseRate: (r['purchase_rate'] as num?)?.toDouble() ?? 0.0,
        salePrice: (r['sale_rate'] as num?)?.toDouble() ?? 0.0,
        rack: r['rack_id']?.toString() ?? '',
        category: r['category_id']?.toString() ?? 'General',
        schedule: r['schedule']?.toString() ?? '',
        patent: r['patent']?.toString() ?? '',
        reorderLevel: (r['reorder_level'] as num?)?.toInt() ?? 10,
        manufacturer: r['manufacturer_id']?.toString() ?? '',
        stock: (r['total_stock'] as num?)?.toInt() ?? 0,
      )).toList();
    } catch (e) {
      debugPrint("SQL Search Error: $e");
      // Fallback to sync memory search
      return searchProducts(query, includeGenerics: includeGenerics, stockOnly: stockOnly);
    }
  }

  Map<String, int> _productSalesFrequency = {};

  Map<String, int> get productSalesFrequency => _productSalesFrequency;

  Future<void> refreshSalesFrequency() async {
    if (kIsWeb) return;
    try {
      final db = await DbHelper.instance.database;
      final results = await db.rawQuery('''
        SELECT product_id, COUNT(DISTINCT invoice_no) as freq 
        FROM sales_items 
        WHERE product_id IS NOT NULL AND product_id != ''
        GROUP BY product_id
      ''');
      final Map<String, int> map = {};
      for (var r in results) {
        final pid = r['product_id']?.toString() ?? '';
        final freq = (r['freq'] as num?)?.toInt() ?? 0;
        if (pid.isNotEmpty) {
          map[pid] = freq;
        }
      }
      _productSalesFrequency = map;
    } catch (e) {
      debugPrint("Error loading sales frequency: $e");
    }
  }

  bool isGenericProduct(Product p) {
    final cat = p.category.trim().toUpperCase();
    final pat = p.patent.trim().toUpperCase();
    return cat == "GEN" || cat.contains("GENERIC") || pat == "GENERIC" || pat.contains("GENERIC");
  }

  List<Product> searchProducts(String query, {bool includeGenerics = true, bool stockOnly = false, bool isSalesWindow = false}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];

    final cacheKey = "${q}_${includeGenerics}_${stockOnly}_$isSalesWindow";
    if (_searchCache.containsKey(cacheKey)) {
      return _searchCache[cacheKey]!;
    }

    final List<Product> startsMatches = [];
    final List<Product> containsMatches = [];

    for (int i = 0; i < _productMaster.length; i++) {
      final p = _productMaster[i];
      if (stockOnly && p.stock <= 0) continue;

      final nameLower = p.name.trim().toLowerCase();
      final aliasLower = p.alias.trim().toLowerCase();

      final bool isStart = nameLower.startsWith(q) ||
          (aliasLower.isNotEmpty && aliasLower.startsWith(q));

      if (isStart) {
        startsMatches.add(p);
      } else {
        final bool isContain = nameLower.contains(q) ||
            (includeGenerics && p.genericName.trim().toLowerCase().contains(q));
        if (isContain) {
          containsMatches.add(p);
        }
      }
    }

    int compareProducts(Product a, Product b, bool isStartA, bool isStartB) {
      // 1st Priority (PRIMARY UNIVERSAL RULE): Name/Alias STARTS WITH query alphabet comes first
      if (isStartA != isStartB) {
        return isStartA ? -1 : 1;
      }

      // 2nd Priority (SECONDARY RULE): Most QTY Available (Highest Stock Quantity first)
      final stockCmp = b.stock.compareTo(a.stock);
      if (stockCmp != 0) return stockCmp;

      // 3rd Priority (Other rules below):
      if (isSalesWindow) {
        // Generic medicines (must have stock > 0)
        final bool isGenA = (a.stock > 0) && isGenericProduct(a);
        final bool isGenB = (b.stock > 0) && isGenericProduct(b);
        if (isGenA != isGenB) {
          return isGenA ? -1 : 1; // Generic with stock > 0 comes first
        }
      }

      // Priority: Most time sold item (Sales transaction frequency count descending)
      final int freqA = _productSalesFrequency[a.id] ?? 0;
      final int freqB = _productSalesFrequency[b.id] ?? 0;
      final int freqCmp = freqB.compareTo(freqA);
      if (freqCmp != 0) return freqCmp;

      // Tie-breaker: Name alphabetical
      return a.name.trim().toLowerCase().compareTo(b.name.trim().toLowerCase());
    }

    startsMatches.sort((a, b) => compareProducts(a, b, true, true));
    containsMatches.sort((a, b) => compareProducts(a, b, false, false));

    final List<Product> results = [...startsMatches, ...containsMatches].take(100).toList();

    _searchCache[cacheKey] = results;
    if (_searchCache.length > 250) {
      _searchCache.remove(_searchCache.keys.first);
    }

    return results;
  }

  List<Product> consolidateBatches(List<Product> rawBatches) {
    if (rawBatches.isEmpty) return [];

    final Map<String, Product> consolidatedMap = {};
    for (var b in rawBatches) {
      final cleanBatchNum = b.batch.trim().toUpperCase();
      final cleanExp = b.expiry.trim();
      final mrpVal = b.mrp.toStringAsFixed(2);
      final lCostVal = b.landingCost.toStringAsFixed(2);
      final wRateVal = b.salePrice.toStringAsFixed(2);

      final groupKey = "${b.id}_${cleanBatchNum}_${cleanExp}_${mrpVal}_${lCostVal}_$wRateVal";

      if (consolidatedMap.containsKey(groupKey)) {
        consolidatedMap[groupKey]!.stock += b.stock;
      } else {
        consolidatedMap[groupKey] = Product(
          id: b.id,
          name: b.name,
          batch: b.batch,
          rack: b.rack,
          hsnCode: b.hsnCode,
          expiry: b.expiry,
          packSize: b.packSize,
          mrp: b.mrp,
          salePrice: b.salePrice,
          purchaseRate: b.purchaseRate,
          landingCost: b.landingCost,
          taxableSP: b.taxableSP,
          stock: b.stock,
          gstPercent: b.gstPercent,
          category: b.category,
          subCategory: b.subCategory,
          manufacturer: b.manufacturer,
          supplier: b.supplier,
          patent: b.patent,
          schedule: b.schedule,
          genericName: b.genericName,
          use: b.use,
          sDiscPercent: b.sDiscPercent,
          reorderLevel: b.reorderLevel,
          maxLevel: b.maxLevel,
          isControlled: b.isControlled,
          isBanned: b.isBanned,
          isNrx: b.isNrx,
          isActive: b.isActive,
          isDiscLocked: b.isDiscLocked,
          preferredWholesale: b.preferredWholesale,
          leadTime: b.leadTime,
        );
      }
    }

    return consolidatedMap.values.toList();
  }

  List<Product> getFEFOBatches(String productId) {
    final batches = _products.where((p) => p.id == productId && p.stock > 0).toList();
    batches.sort((a, b) {
      final dateA = _parseExpiry(a.expiry);
      final dateB = _parseExpiry(b.expiry);
      if (dateA == null) return 1;
      if (dateB == null) return -1;
      return dateA.compareTo(dateB);
    });
    return batches;
  }

  List<Product> getExpiringProducts(int months) {
    final now = DateTime.now();
    final limit = DateTime(now.year, now.month + months, now.day);
    return _products.where((p) {
      final expiryDate = _parseExpiry(p.expiry);
      if (expiryDate == null) return false;
      return expiryDate.isAfter(now) && expiryDate.isBefore(limit);
    }).toList();
  }

  List<Product> getExpiredProducts() {
    final now = DateTime.now();
    return _products.where((p) {
      final expiryDate = _parseExpiry(p.expiry);
      if (expiryDate == null) return false;
      return expiryDate.isBefore(now);
    }).toList();
  }

  /// ==========================================================
  /// FEFO ENGINE: FIRST-EXPIRE, FIRST-OUT AUTO-ALLOCATION
  /// ==========================================================
  Product? getAutoFefoBatch(String productName) {
    final today = DateTime.now();

    // Find all batches for this product that have stock AND are not expired
    final availableBatches = _products.where((p) {
      if (p.name.toLowerCase().trim() != productName.toLowerCase().trim() || p.stock <= 0) return false;
      final exp = _parseExpiry(p.expiry);
      return exp != null && !exp.isBefore(today); // Ignore expired stock
    }).toList();

    if (availableBatches.isEmpty) return null;

    // Sort strictly by nearest expiry date
    availableBatches.sort((a, b) {
      final expA = _parseExpiry(a.expiry) ?? DateTime(2099);
      final expB = _parseExpiry(b.expiry) ?? DateTime(2099);
      return expA.compareTo(expB);
    });

    // Return the batch that expires soonest
    return availableBatches.first;
  }

  DateTime? _parseExpiry(String expiry) {
    if (expiry.isEmpty) return null;
    try {
      final parts = expiry.split('/');
      if (parts.length == 2) {
        int month = int.parse(parts[0]);
        int year = int.parse(parts[1]);
        if (month < 1 || month > 12) return null; // Treat invalid month as invalid date
        if (year < 100) year += 2000;
        return DateTime(year, month + 1, 0);
      } else if (parts.length == 3) {
        int day = int.parse(parts[0]);
        int month = int.parse(parts[1]);
        int year = int.parse(parts[2]);
        if (month < 1 || month > 12) return null;
        if (year < 100) year += 2000;
        return DateTime(year, month, day);
      }
    } catch (_) {}
    return null;
  }

  Future<void> updatePurchasePayment(String entryNo, int status, {String? mode, String? remarks, DateTime? date, double? amount}) async {
    final db = kIsWeb ? null : await DbHelper.instance.database;
    if (db != null) {
      Map<String, dynamic> vals = {
        'payment_status': status,
        'payment_mode': mode,
        'payment_remarks': remarks,
        'payment_date': date?.toIso8601String(),
      };
      if (amount != null) vals['paid_amount'] = amount;
      await db.update('purchase_entries', vals, where: 'entry_no = ?', whereArgs: [entryNo]);
    }

    final idx = _purchases.indexWhere((p) => p.entryNo == entryNo);
    if (idx != -1) {
      _purchases[idx].paymentStatus = status;
      _purchases[idx].paymentMode = mode;
      _purchases[idx].paymentRemarks = remarks;
      _purchases[idx].paymentDate = date;
      if (amount != null) _purchases[idx].paidAmount = amount;
    }
    notifyListeners();
  }

  Future<void> addSupplierPayment(SupplierPayment payment) async {
    final db = kIsWeb ? null : await DbHelper.instance.database;
    if (db != null) {
      await db.transaction((txn) async {
        await txn.insert('supplier_payments', {
          'id': payment.id,
          'supplier_name': payment.supplierName,
          'date': payment.date.toIso8601String(),
          'amount': payment.amount,
          'invoice_no': payment.invoiceNo,
          'payment_method': payment.paymentMethod,
          'remarks': payment.remarks,
        });

        // Reduce supplier outstanding balance
        final int updatedRows = await txn.rawUpdate(
            'UPDATE suppliers SET current_balance = current_balance - ? WHERE name = ? COLLATE NOCASE',
            [payment.amount, payment.supplierName]
        );

        if (updatedRows == 0) {
          // New Supplier! Register them automatically
          final String newSupId = "SUP_PAY_${DateTime.now().millisecondsSinceEpoch}_${payment.supplierName.hashCode}";
          await txn.insert('suppliers', {
            'id': newSupId,
            'name': payment.supplierName,
            'current_balance': -payment.amount,
            'phone': '', 'address': '', 'gst_in': '', 'dl_number': '',
          });
          _autoRegisteredSupId = newSupId;
        }
      });
    }

    if (payment.supplierName.isNotEmpty && !_suppliers.contains(payment.supplierName)) {
      _suppliers.add(payment.supplierName);
      if (!_supplierMaster.any((s) => s.name.toLowerCase() == payment.supplierName.toLowerCase())) {
        _supplierMaster.add(Supplier(
          id: _autoRegisteredSupId ?? "SUP_PAY_MEM_${DateTime.now().millisecondsSinceEpoch}",
          name: payment.supplierName,
          currentBalance: -payment.amount,
        ));
      }
    }
    _autoRegisteredSupId = null; // Reset

    _supplierPayments.add(payment);
    notifyListeners();
  }

  Future<void> deleteSupplierPayment(String paymentId) async {
    final db = kIsWeb ? null : await DbHelper.instance.database;
    if (db != null) {
      // Find the payment to restore the balance
      final idx = _supplierPayments.indexWhere((p) => p.id == paymentId);
      if (idx != -1) {
        final payment = _supplierPayments[idx];
        await db.transaction((txn) async {
          await txn.delete('supplier_payments', where: 'id = ?', whereArgs: [paymentId]);
          // Reverse the balance
          await txn.rawUpdate(
            'UPDATE suppliers SET current_balance = current_balance + ? WHERE name = ? COLLATE NOCASE',
            [payment.amount, payment.supplierName]
          );
        });
      }
    }
    _supplierPayments.removeWhere((p) => p.id == paymentId);
    notifyListeners();
  }

  Future<void> updateSupplierPayment(SupplierPayment payment) async {
    final db = kIsWeb ? null : await DbHelper.instance.database;
    if (db != null) {
      await db.update('supplier_payments', {
        'supplier_name': payment.supplierName,
        'date': payment.date.toIso8601String(),
        'amount': payment.amount,
        'invoice_no': payment.invoiceNo,
        'payment_method': payment.paymentMethod,
        'remarks': payment.remarks,
      }, where: 'id = ?', whereArgs: [payment.id]);
    }
    final idx = _supplierPayments.indexWhere((p) => p.id == payment.id);
    if (idx != -1) {
      _supplierPayments[idx] = payment;
    }
    notifyListeners();
  }

  // =========================================================================
  // PATIENT / CUSTOMER PAYMENT ENGINE
  // =========================================================================
  final List<SupplierPayment> _patientPayments = []; // Using the same model structure for simplicity
  List<SupplierPayment> get patientPayments => _patientPayments;

  Future<void> addPatientPayment(SupplierPayment payment) async {
    final db = kIsWeb ? null : await DbHelper.instance.database;
    if (db != null) {
      await db.transaction((txn) async {
        await txn.insert('patient_payments', {
          'id': payment.id,
          'patient_name': payment.supplierName, // Reusing field name
          'date': payment.date.toIso8601String(),
          'amount': payment.amount,
          'invoice_no': payment.invoiceNo,
          'payment_method': payment.paymentMethod,
          'remarks': payment.remarks,
        });

        // Reduce patient outstanding balance
        final int updatedRows = await txn.rawUpdate(
            'UPDATE patients SET current_balance = current_balance - ? WHERE name = ? COLLATE NOCASE',
            [payment.amount, payment.supplierName]
        );

        if (updatedRows == 0) {
          // New Patient! Register them automatically
          final String newPatId = "PAT_PAY_${DateTime.now().millisecondsSinceEpoch}_${payment.supplierName.hashCode}";
          await txn.insert('patients', {
            'id': newPatId,
            'name': payment.supplierName,
            'mobile': '',
            'address': '',
            'current_balance': -payment.amount,
          });
        }
      });
    }

    if (payment.supplierName.isNotEmpty && !_patients.contains(payment.supplierName)) {
      _patients.add(payment.supplierName);
      if (!_patientMaster.any((p) => p.name.toLowerCase() == payment.supplierName.toLowerCase())) {
        _patientMaster.add(Patient(
          id: "PAT_PAY_MEM_${DateTime.now().millisecondsSinceEpoch}",
          name: payment.supplierName,
          currentBalance: -payment.amount,
        ));
      }
    }

    _patientPayments.add(payment);
    notifyListeners();
  }

  Future<void> deletePatientPayment(String paymentId) async {
    final db = kIsWeb ? null : await DbHelper.instance.database;
    if (db != null) {
      // Find the payment to restore the balance
      final payment = _patientPayments.firstWhere((p) => p.id == paymentId);
      
      await db.delete('patient_payments', where: 'id = ?', whereArgs: [paymentId]);
      
      // Reverse the balance
      await db.rawUpdate(
        'UPDATE patients SET current_balance = current_balance + ? WHERE name = ?', 
        [payment.amount, payment.supplierName]
      );
    }
    _patientPayments.removeWhere((p) => p.id == paymentId);
    notifyListeners();
  }

  Future<void> updatePatientPayment(SupplierPayment payment) async {
    final db = kIsWeb ? null : await DbHelper.instance.database;
    if (db != null) {
      // Find old payment to calculate difference
      final oldPayment = _patientPayments.firstWhere((p) => p.id == payment.id);
      double difference = payment.amount - oldPayment.amount;

      await db.update('patient_payments', {
        'patient_name': payment.supplierName,
        'date': payment.date.toIso8601String(),
        'amount': payment.amount,
        'invoice_no': payment.invoiceNo,
        'payment_method': payment.paymentMethod,
        'remarks': payment.remarks,
      }, where: 'id = ?', whereArgs: [payment.id]);

      // Adjust the balance by the difference
      await db.rawUpdate(
        'UPDATE patients SET current_balance = current_balance - ? WHERE name = ?', 
        [difference, payment.supplierName]
      );
    }
    final idx = _patientPayments.indexWhere((p) => p.id == payment.id);
    if (idx != -1) {
      _patientPayments[idx] = payment;
    }
    notifyListeners();
  }

  Future<void> addSupplierCreditNote(SupplierCreditNote cn) async {
    final db = kIsWeb ? null : await DbHelper.instance.database;
    if (db != null) {
      await db.transaction((txn) async {
        await txn.insert('supplier_credit_notes', {
          'id': cn.id,
          'supplier_name': cn.supplierName,
          'date': cn.date.toIso8601String(),
          'amount': cn.amount,
          'invoice_no': cn.invoiceNo,
          'remarks': cn.remarks,
        });

        // Reduce supplier outstanding balance
        final int updatedRows = await txn.rawUpdate(
            'UPDATE suppliers SET current_balance = current_balance - ? WHERE name = ? COLLATE NOCASE',
            [cn.amount, cn.supplierName]
        );

        if (updatedRows == 0) {
          // New Supplier! Register them automatically
          final String newSupId = "SUP_CN_${DateTime.now().millisecondsSinceEpoch}_${cn.supplierName.hashCode}";
          await txn.insert('suppliers', {
            'id': newSupId,
            'name': cn.supplierName,
            'current_balance': -cn.amount,
            'phone': '', 'address': '', 'gst_in': '', 'dl_number': '',
          });
        }
      });
    }

    if (cn.supplierName.isNotEmpty && !_suppliers.contains(cn.supplierName)) {
      _suppliers.add(cn.supplierName);
      if (!_supplierMaster.any((s) => s.name.toLowerCase() == cn.supplierName.toLowerCase())) {
        _supplierMaster.add(Supplier(
          id: "SUP_CN_MEM_${DateTime.now().millisecondsSinceEpoch}",
          name: cn.supplierName,
          currentBalance: -cn.amount,
        ));
      }
    }

    _supplierCreditNotes.add(cn);
    notifyListeners();
  }

  Future<void> deleteSupplierCreditNote(String id) async {
    final db = kIsWeb ? null : await DbHelper.instance.database;
    if (db != null) {
      final idx = _supplierCreditNotes.indexWhere((cn) => cn.id == id);
      if (idx != -1) {
        final cn = _supplierCreditNotes[idx];
        await db.transaction((txn) async {
          await txn.delete('supplier_credit_notes', where: 'id = ?', whereArgs: [id]);
          // Reverse the balance
          await txn.rawUpdate(
            'UPDATE suppliers SET current_balance = current_balance + ? WHERE name = ? COLLATE NOCASE',
            [cn.amount, cn.supplierName]
          );
        });
      }
    }
    _supplierCreditNotes.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  Future<void> updateSupplierCreditNote(SupplierCreditNote cn) async {
    final db = kIsWeb ? null : await DbHelper.instance.database;
    if (db != null) {
      await db.update('supplier_credit_notes', {
        'supplier_name': cn.supplierName,
        'date': cn.date.toIso8601String(),
        'amount': cn.amount,
        'invoice_no': cn.invoiceNo,
        'remarks': cn.remarks,
      }, where: 'id = ?', whereArgs: [cn.id]);
    }
    final idx = _supplierCreditNotes.indexWhere((p) => p.id == cn.id);
    if (idx != -1) {
      _supplierCreditNotes[idx] = cn;
    }
    notifyListeners();
  }

  // SALES DRAFT / AUTOSAVE LOGIC
  Future<void> saveSaleDraft(Map<String, dynamic> data) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/sale_draft.json');
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint("Error saving draft: $e");
    }
  }

  Future<Map<String, dynamic>?> loadSaleDraft() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/sale_draft.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        return jsonDecode(content);
      }
    } catch (e) {
      debugPrint("Error loading draft: $e");
    }
    return null;
  }

  Future<void> clearSaleDraft() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/sale_draft.json');
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint("Error clearing draft: $e");
    }
  }

  // PURCHASE DRAFT / AUTOSAVE LOGIC
  Future<void> savePurchaseDraft(Map<String, dynamic> data) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/purchase_draft.json');
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint("Error saving purchase draft: $e");
    }
  }

  Future<Map<String, dynamic>?> loadPurchaseDraft() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/purchase_draft.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        return jsonDecode(content);
      }
    } catch (e) {
      debugPrint("Error loading purchase draft: $e");
    }
    return null;
  }

  Future<void> clearPurchaseDraft() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/purchase_draft.json');
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint("Error clearing purchase draft: $e");
    }
  }

  // STOCK CHECKING DRAFT / AUTOSAVE LOGIC
  Future<void> saveStockCheckingDraft(Map<String, dynamic> data) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/stock_checking_draft.json');
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint("Error saving stock checking draft: $e");
    }
  }

  Future<Map<String, dynamic>?> loadStockCheckingDraft() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/stock_checking_draft.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        return jsonDecode(content);
      }
    } catch (e) {
      debugPrint("Error loading stock checking draft: $e");
    }
    return null;
  }

  Future<void> clearStockCheckingDraft() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/stock_checking_draft.json');
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint("Error clearing stock checking draft: $e");
    }
  }

  Future<List<StockLedgerItem>> getStockLedgerReport(DateTime fromDate, DateTime toDate) async {
    if (kIsWeb) return [];
    final db = await DbHelper.instance.database;
    final fromStr = fromDate.toIso8601String().split('T')[0];
    final toStr = toDate.toIso8601String().split('T')[0];

    final List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT 
          b.product_id, 
          b.batch_number,
          p.name as product_name,
          p.patent,
          p.packing,
          p.hsn_code,
          p.gst_percent,
          b.mrp,
          b.purchase_rate,
          b.supplier_name,
          
          SUM(CASE WHEN t.date < ? THEN t.qty * t.factor ELSE 0 END) as opening_stock,
          SUM(CASE WHEN t.date BETWEEN ? AND ? AND t.type = 'PUR' THEN t.qty ELSE 0 END) as purchase,
          SUM(CASE WHEN t.date BETWEEN ? AND ? AND t.type = 'SAL' THEN t.qty ELSE 0 END) as sales,
          SUM(CASE WHEN t.date BETWEEN ? AND ? AND t.type = 'SRET' THEN t.qty ELSE 0 END) as sale_return,
          SUM(CASE WHEN t.date BETWEEN ? AND ? AND t.type = 'PRET' THEN t.qty ELSE 0 END) as purchase_return,
          SUM(CASE WHEN t.date BETWEEN ? AND ? AND t.type = 'ADJ' THEN t.qty ELSE 0 END) as adjustment,
          SUM(CASE WHEN t.date BETWEEN ? AND ? AND t.type = 'DMG' THEN t.qty ELSE 0 END) as damage
      FROM stock_batches b
      JOIN product_master p ON b.product_id = p.id
      LEFT JOIN (
          -- 1. PURCHASES (With is_deleted Filter)
          SELECT pi.product_id, pi.batch, (pi.qty + pi.f_qty) * (CASE WHEN pi.packin > 0 THEN pi.packin ELSE 1 END) as qty, 1 as factor, 'PUR' as type, date(pe.date) as date
          FROM purchase_items pi 
          JOIN purchase_entries pe ON pi.entry_no = pe.entry_no
          WHERE IFNULL(pe.is_deleted, 0) = 0
          
          UNION ALL
          -- 2. SALES (With is_deleted Filter)
          SELECT si.product_id, si.batch_number as batch, si.qty, -1 as factor, 'SAL' as type, date(sv.date) as date
          FROM sales_items si
          JOIN sales_invoices sv ON si.invoice_no = sv.entry_no
          WHERE IFNULL(sv.is_deleted, 0) = 0
          
          UNION ALL
          -- 3. SALES RETURNS (With is_deleted Filter)
          SELECT sri.product_id, sri.batch_number as batch, sri.quantity as qty, 1 as factor, 'SRET' as type, date(srv.date) as date
          FROM sales_return_items sri
          JOIN sales_return_invoices srv ON sri.return_no = srv.entry_no
          WHERE IFNULL(srv.is_deleted, 0) = 0
          
          UNION ALL
          -- 4. PURCHASE RETURNS (With is_deleted Filter)
          SELECT pri_p.id as product_id, pri.batch, (pri.qty * (CASE WHEN pri.packin > 0 THEN pri.packin ELSE 1 END)) + pri.loose_qty as qty, -1 as factor, 'PRET' as type, date(prv.date) as date
          FROM purchase_return_items pri
          JOIN purchase_return_entries prv ON pri.entry_no = prv.entry_no
          LEFT JOIN product_master pri_p ON LOWER(TRIM(pri.product_name)) = LOWER(TRIM(pri_p.name))
          WHERE IFNULL(prv.is_deleted, 0) = 0
          
          UNION ALL
          -- 5. STOCK ADJUSTMENTS (With is_deleted Filter)
          SELECT sai.product_id, sai.batch_number as batch, sai.qty, 1 as factor, 
                 CASE WHEN UPPER(sa.reason) LIKE '%DAMAGE%' THEN 'DMG' ELSE 'ADJ' END as type, 
                 date(sa.date) as date
          FROM stock_adjustment_items sai
          JOIN stock_adjustments sa ON sai.adjustment_no = sa.entry_no
          WHERE IFNULL(sa.is_deleted, 0) = 0

          UNION ALL
          -- 6. STOCK WRITE OFFS / DAMAGES
          SELECT swo.product_id, swo.batch_number as batch, swo.quantity as qty, -1 as factor,
                 'DMG' as type, date(swo.date) as date
          FROM stock_write_offs swo
      ) t ON b.product_id = t.product_id AND b.batch_number = t.batch
      GROUP BY b.product_id, b.batch_number
      ORDER BY p.name ASC
    ''', [
      fromStr,
      fromStr, toStr,
      fromStr, toStr,
      fromStr, toStr,
      fromStr, toStr,
      fromStr, toStr,
      fromStr, toStr
    ]);

    return results.map((r) {
      int openStk = (r['opening_stock'] as num?)?.toInt() ?? 0;
      int pur = (r['purchase'] as num?)?.toInt() ?? 0;
      int sal = (r['sales'] as num?)?.toInt() ?? 0;
      int sRet = (r['sale_return'] as num?)?.toInt() ?? 0;
      int pRet = (r['purchase_return'] as num?)?.toInt() ?? 0;
      int adj = (r['adjustment'] as num?)?.toInt() ?? 0;
      int dmg = (r['damage'] as num?)?.toInt() ?? 0;

      int closing = openStk + pur - sal + sRet - pRet + adj - dmg;

      return StockLedgerItem(
        productName: r['product_name'] ?? '',
        patent: r['patent'] ?? '',
        packin: (r['packing'] as num?)?.toInt() ?? 1,
        batch: r['batch_number'] ?? '',
        hsnCode: r['hsn_code'] ?? '',
        gst: (r['gst_percent'] as num?)?.toDouble() ?? 0.0,
        mrp: (r['mrp'] as num?)?.toDouble() ?? 0.0,
        supplier: r['supplier_name'] ?? '',
        lCost: (r['purchase_rate'] as num?)?.toDouble() ?? 0.0,
        openingStock: openStk,
        purchase: pur,
        sales: sal,
        saleReturn: sRet,
        purchaseReturn: pRet,
        adjustment: adj,
        damage: dmg,
        closingStock: closing,
      );
    }).toList();
  }

  Future<List<ConsolidatedStockItem>> getConsolidatedStockForPeriod(DateTime fromDate, DateTime toDate) async {
    if (kIsWeb) {
      return _productMaster.map((p) => ConsolidatedStockItem(
        productId: p.id,
        productName: p.name,
        genericName: p.genericName,
        category: p.category,
        rack: p.rack,
        packSize: p.packSize,
        purchaseRate: p.purchaseRate,
        mrp: p.mrp,
        openingStock: p.stock,
        inwardQty: 0,
        outwardQty: 0,
        closingStock: p.stock,
        liveStock: p.stock,
      )).toList();
    }
    final db = await DbHelper.instance.database;
    final fromStr = DateFormat('yyyy-MM-dd').format(fromDate);
    final toStr = DateFormat('yyyy-MM-dd').format(toDate);

    final List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT 
          pm.id as product_id,
          pm.name as product_name,
          IFNULL(pm.generic_name, '') as generic_name,
          IFNULL(pm.category_id, '') as category,
          IFNULL(pm.rack_id, '') as rack,
          IFNULL(pm.packing, 1) as packing,
          IFNULL(pm.purchase_rate, 0.0) as purchase_rate,
          IFNULL(pm.mrp, 0.0) as mrp,
          IFNULL(sb.live_stock, 0) as live_stock,
          
          IFNULL(tx.in_period, 0) as in_period,
          IFNULL(tx.out_period, 0) as out_period,
          IFNULL(tx.in_since_from, 0) as in_since_from,
          IFNULL(tx.out_since_from, 0) as out_since_from,
          IFNULL(tx.in_after_to, 0) as in_after_to,
          IFNULL(tx.out_after_to, 0) as out_after_to

      FROM product_master pm

      LEFT JOIN (
          SELECT product_id, SUM(current_stock) as live_stock
          FROM stock_batches
          GROUP BY product_id
      ) sb ON pm.id = sb.product_id

      LEFT JOIN (
          SELECT 
              t.product_id,
              SUM(CASE WHEN date(t.date) BETWEEN ? AND ? AND t.is_in = 1 THEN t.qty ELSE 0 END) as in_period,
              SUM(CASE WHEN date(t.date) BETWEEN ? AND ? AND t.is_in = 0 THEN t.qty ELSE 0 END) as out_period,
              SUM(CASE WHEN date(t.date) >= ? AND t.is_in = 1 THEN t.qty ELSE 0 END) as in_since_from,
              SUM(CASE WHEN date(t.date) >= ? AND t.is_in = 0 THEN t.qty ELSE 0 END) as out_since_from,
              SUM(CASE WHEN date(t.date) > ? AND t.is_in = 1 THEN t.qty ELSE 0 END) as in_after_to,
              SUM(CASE WHEN date(t.date) > ? AND t.is_in = 0 THEN t.qty ELSE 0 END) as out_after_to
          FROM (
              -- 1. PURCHASES
              SELECT pi.product_id, (pi.qty + pi.f_qty) * (CASE WHEN pi.packin > 0 THEN pi.packin ELSE 1 END) as qty, 1 as is_in, pe.date
              FROM purchase_items pi 
              JOIN purchase_entries pe ON pi.entry_no = pe.entry_no 
              WHERE IFNULL(pe.is_deleted, 0) = 0
              
              UNION ALL
              -- 2. SALES
              SELECT si.product_id, si.qty, 0 as is_in, sv.date
              FROM sales_items si 
              JOIN sales_invoices sv ON si.invoice_no = sv.entry_no 
              WHERE IFNULL(sv.is_deleted, 0) = 0
              
              UNION ALL
              -- 3. SALES RETURNS
              SELECT sri.product_id, sri.quantity as qty, 1 as is_in, srv.date
              FROM sales_return_items sri 
              JOIN sales_return_invoices srv ON sri.return_no = srv.entry_no 
              WHERE IFNULL(srv.is_deleted, 0) = 0
              
              UNION ALL
              -- 4. PURCHASE RETURNS
              SELECT pri_p.id as product_id, (pri.qty * (CASE WHEN pri.packin > 0 THEN pri.packin ELSE 1 END)) + pri.loose_qty as qty, 0 as is_in, prv.date
              FROM purchase_return_items pri 
              JOIN purchase_return_entries prv ON pri.entry_no = prv.entry_no
              LEFT JOIN product_master pri_p ON LOWER(TRIM(pri.product_name)) = LOWER(TRIM(pri_p.name)) 
              WHERE IFNULL(prv.is_deleted, 0) = 0
              
              UNION ALL
              -- 5. STOCK ADJUSTMENTS
              SELECT sai.product_id, ABS(sai.qty) as qty, (CASE WHEN sai.qty >= 0 THEN 1 ELSE 0 END) as is_in, sa.date
              FROM stock_adjustment_items sai 
              JOIN stock_adjustments sa ON sai.adjustment_no = sa.entry_no 
              WHERE IFNULL(sa.is_deleted, 0) = 0
              
              UNION ALL
              -- 6. STOCK WRITE OFFS / DAMAGES
              SELECT swo.product_id, swo.quantity as qty, 0 as is_in, swo.date
              FROM stock_write_offs swo
          ) t
          GROUP BY t.product_id
      ) tx ON pm.id = tx.product_id

      ORDER BY pm.name ASC
    ''', [
      fromStr, toStr,
      fromStr, toStr,
      fromStr,
      fromStr,
      toStr,
      toStr,
    ]);

    return results.map((r) {
      int liveStock = (r['live_stock'] as num?)?.toInt() ?? 0;
      int inPeriod = (r['in_period'] as num?)?.toInt() ?? 0;
      int outPeriod = (r['out_period'] as num?)?.toInt() ?? 0;
      int inSinceFrom = (r['in_since_from'] as num?)?.toInt() ?? 0;
      int outSinceFrom = (r['out_since_from'] as num?)?.toInt() ?? 0;
      int inAfterTo = (r['in_after_to'] as num?)?.toInt() ?? 0;
      int outAfterTo = (r['out_after_to'] as num?)?.toInt() ?? 0;

      int openStock = liveStock - inSinceFrom + outSinceFrom;
      int closingStock = liveStock - inAfterTo + outAfterTo;

      return ConsolidatedStockItem(
        productId: r['product_id']?.toString() ?? '',
        productName: r['product_name']?.toString() ?? '',
        genericName: r['generic_name']?.toString() ?? '',
        category: r['category']?.toString() ?? '',
        rack: r['rack']?.toString() ?? '',
        packSize: (r['packing'] as num?)?.toInt() ?? 1,
        purchaseRate: (r['purchase_rate'] as num?)?.toDouble() ?? 0.0,
        mrp: (r['mrp'] as num?)?.toDouble() ?? 0.0,
        openingStock: openStock,
        inwardQty: inPeriod,
        outwardQty: outPeriod,
        closingStock: closingStock,
        liveStock: liveStock,
      );
    }).toList();
  }

  Future<Uint8List?> exportConsolidatedStockToExcelBytes(
    List<ConsolidatedStockItem> items,
    DateTime fromDate,
    DateTime toDate,
  ) async {
    try {
      final fromStr = DateFormat('dd/MM/yyyy').format(fromDate);
      final toStr = DateFormat('dd/MM/yyyy').format(toDate);
      final data = items.map((item) => {
        'name': item.productName,
        'rack': item.rack,
        'category': item.category,
        'pack': item.packSize,
        'opening': item.openingStock,
        'inward': item.inwardQty,
        'outward': item.outwardQty,
        'closing': item.closingStock,
        'pRate': item.purchaseRate,
        'mrp': item.mrp,
        'valuation': item.purchaseValuation,
        'mrpValuation': item.mrpValuation,
      }).toList();

      return await compute(_generateConsolidatedStockExcelIsolate, {
        'from': fromStr,
        'to': toStr,
        'items': data,
      });
    } catch (e) {
      debugPrint("Export Consolidated Stock Error: $e");
      return null;
    }
  }

  static Uint8List _generateConsolidatedStockExcelIsolate(Map<String, dynamic> params) {
    final String fromStr = params['from'] ?? '';
    final String toStr = params['to'] ?? '';
    final List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(params['items'] ?? []);

    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Consolidated Stock'];
    excel.delete('Sheet1');

    sheetObject.appendRow([
      TextCellValue("CONSOLIDATED STOCK POSITION REPORT"),
      TextCellValue("Period: $fromStr to $toStr"),
    ]);
    sheetObject.appendRow([]);

    sheetObject.appendRow([
      TextCellValue("SL"),
      TextCellValue("Product Name"),
      TextCellValue("Rack"),
      TextCellValue("Category"),
      TextCellValue("Pack"),
      TextCellValue("Opening Stock"),
      TextCellValue("Inward (+)"),
      TextCellValue("Outward (-)"),
      TextCellValue("Closing Stock"),
      TextCellValue("Purchase Rate (₹)"),
      TextCellValue("MRP (₹)"),
      TextCellValue("Stock Valuation (₹)"),
      TextCellValue("MRP Asset Value (₹)"),
    ]);

    for (int i = 0; i < items.length; i++) {
      final row = items[i];
      sheetObject.appendRow([
        IntCellValue(i + 1),
        TextCellValue(row['name']?.toString() ?? ""),
        TextCellValue(row['rack']?.toString() ?? ""),
        TextCellValue(row['category']?.toString() ?? ""),
        IntCellValue(row['pack'] ?? 1),
        IntCellValue(row['opening'] ?? 0),
        IntCellValue(row['inward'] ?? 0),
        IntCellValue(row['outward'] ?? 0),
        IntCellValue(row['closing'] ?? 0),
        DoubleCellValue((row['pRate'] as num?)?.toDouble() ?? 0.0),
        DoubleCellValue((row['mrp'] as num?)?.toDouble() ?? 0.0),
        DoubleCellValue((row['valuation'] as num?)?.toDouble() ?? 0.0),
        DoubleCellValue((row['mrpValuation'] as num?)?.toDouble() ?? 0.0),
      ]);
    }
    return Uint8List.fromList(excel.encode()!);
  }

  Future<Map<String, dynamic>> generateStockLedger(String productName, DateTime fromDate, DateTime toDate) async {
    final db = await DbHelper.instance.database;
    final fromStr = fromDate.toIso8601String().split('T')[0];
    final cleanName = productName.trim();

    // Get Product ID for robust matching
    final pRes = await db.query('product_master', columns: ['id'], where: 'name = ? COLLATE NOCASE', whereArgs: [cleanName]);
    String productId = pRes.isNotEmpty ? pRes.first['id'].toString() : '';

    // 1. Get ALL transactions for this product starting from the 'from' date
    // We need all transactions after 'from' to back-calculate opening balance from current live stock.
    final List<Map<String, dynamic>> results = await db.rawQuery('''
      SELECT * FROM (
          -- PURCHASES
          SELECT pe.date, 'PURCHASE' as type, pe.entry_no as ref_no, IFNULL(pi.batch, '') as batch, 
                 (IFNULL(pi.qty, 0) + IFNULL(pi.f_qty, 0)) * CASE WHEN IFNULL(pi.packin, 0) <= 0 THEN 1 ELSE pi.packin END as in_qty, 
                 0 as out_qty
          FROM purchase_items pi 
          JOIN purchase_entries pe ON pi.entry_no = pe.entry_no
          WHERE (TRIM(pi.product_name) = ? COLLATE NOCASE OR (? != '' AND pi.product_id = ?)) 
            AND IFNULL(pe.is_deleted, 0) = 0 
            AND date(pe.date) >= ?
          
          UNION ALL
          
          -- SALES
          SELECT sn.date, 'SALE' as type, sn.entry_no as ref_no, IFNULL(si.batch_number, '') as batch, 
                 0 as in_qty, IFNULL(si.qty, 0) as out_qty
          FROM sales_items si
          JOIN sales_invoices sn ON si.invoice_no = sn.entry_no
          WHERE (TRIM(si.product_name) = ? COLLATE NOCASE OR (? != '' AND si.product_id = ?)) 
            AND IFNULL(sn.is_deleted, 0) = 0 
            AND date(sn.date) >= ?
          
          UNION ALL
          
          -- SALES RETURNS
          SELECT srn.date, 'SALE RETURN' as type, srn.entry_no as ref_no, IFNULL(sri.batch_number, '') as batch, 
                 IFNULL(sri.quantity, 0) as in_qty, 0 as out_qty
          FROM sales_return_items sri
          JOIN sales_return_invoices srn ON sri.return_no = srn.entry_no
          WHERE (TRIM(sri.product_name) = ? COLLATE NOCASE OR (? != '' AND sri.product_id = ?)) 
            AND IFNULL(srn.is_deleted, 0) = 0 
            AND date(srn.date) >= ?
          
          UNION ALL
          
          -- PURCHASE RETURNS
          SELECT prn.date, 'PURCHASE RETURN' as type, prn.entry_no as ref_no, IFNULL(pri.batch, '') as batch, 
                 0 as in_qty, 
                 (IFNULL(pri.qty, 0) * CASE WHEN IFNULL(pm.packing, 0) <= 0 THEN 1 ELSE pm.packing END) + IFNULL(pri.loose_qty, 0) as out_qty
          FROM purchase_return_items pri
          JOIN purchase_return_entries prn ON pri.entry_no = prn.entry_no
          LEFT JOIN product_master pm ON TRIM(pri.product_name) = TRIM(pm.name)
          WHERE (TRIM(pri.product_name) = ? COLLATE NOCASE OR (? != '' AND pm.id = ?)) 
            AND IFNULL(prn.is_deleted, 0) = 0 
            AND date(prn.date) >= ?
          
          UNION ALL
          
          -- ADJUSTMENTS
          SELECT sa.date, 
                 CASE WHEN IFNULL(sai.qty, 0) > 0 THEN 'ADJUSTMENT (+)' ELSE 'ADJUSTMENT (-)' END as type,
                 sa.entry_no as ref_no, IFNULL(sai.batch_number, '') as batch,
                 CASE WHEN IFNULL(sai.qty, 0) > 0 THEN sai.qty ELSE 0 END as in_qty,
                 CASE WHEN IFNULL(sai.qty, 0) < 0 THEN ABS(sai.qty) ELSE 0 END as out_qty
          FROM stock_adjustment_items sai
          JOIN stock_adjustments sa ON sai.adjustment_no = sa.entry_no
          LEFT JOIN product_master pm ON sai.product_id = pm.id
          WHERE (TRIM(pm.name) = ? COLLATE NOCASE OR (? != '' AND sai.product_id = ?)) 
            AND IFNULL(sa.is_deleted, 0) = 0 
            AND date(sa.date) >= ?

          UNION ALL

          -- WRITE-OFFS / DAMAGES
          SELECT swo.date, 'DAMAGE / WRITE OFF' as type, swo.id as ref_no, IFNULL(swo.batch_number, '') as batch, 
                 0 as in_qty, IFNULL(swo.quantity, 0) as out_qty
          FROM stock_write_offs swo
          LEFT JOIN product_master pm ON swo.product_id = pm.id
          WHERE (TRIM(pm.name) = ? COLLATE NOCASE OR (? != '' AND swo.product_id = ?)) 
            AND date(swo.date) >= ?
      ) t ORDER BY date ASC
    ''', [
      cleanName, productId, productId, fromStr,
      cleanName, productId, productId, fromStr,
      cleanName, productId, productId, fromStr,
      cleanName, productId, productId, fromStr,
      cleanName, productId, productId, fromStr,
      cleanName, productId, productId, fromStr,
    ]);

    // 2. Get Current Stock of the product to back-calculate
    final List<Map<String, dynamic>> stockResult = await db.rawQuery('''
      SELECT SUM(current_stock) as total FROM stock_batches b
      JOIN product_master p ON b.product_id = p.id
      WHERE TRIM(p.name) = ? COLLATE NOCASE OR (? != '' AND p.id = ?)
    ''', [cleanName, productId, productId]);
    int currentStock = (stockResult.first['total'] as num?)?.toInt() ?? 0;

    // 3. Back-calculate Opening Balance at 'fromDate'
    int inwardsSinceFrom = 0;
    int outwardsSinceFrom = 0;

    for (var row in results) {
      inwardsSinceFrom += ((row['in_qty'] as num?) ?? 0).toInt();
      outwardsSinceFrom += ((row['out_qty'] as num?) ?? 0).toInt();
    }

    int openingBalance = currentStock - inwardsSinceFrom + outwardsSinceFrom;

    // 4. Build chronological ledger entries
    List<Map<String, dynamic>> entries = [];
    int runningBalance = openingBalance;

    for (var row in results) {
      DateTime? rowDate;
      if (row['date'] != null) {
        rowDate = DateTime.tryParse(row['date'].toString());
      }
      rowDate ??= DateTime.now();

      int inQty = ((row['in_qty'] as num?) ?? 0).toInt();
      int outQty = ((row['out_qty'] as num?) ?? 0).toInt();
      
      runningBalance = runningBalance + inQty - outQty;

      // Only include entries that fall within the requested date range
      final endOfToDate = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59, 999);
      if (!rowDate.isAfter(endOfToDate)) {
        entries.add({
          'date': DateFormat('dd/MM/yyyy HH:mm').format(rowDate),
          'type': row['type'],
          'ref_no': row['ref_no'],
          'batch': row['batch'],
          'in_qty': inQty,
          'out_qty': outQty,
          'balance': runningBalance,
        });
      }
    }

    int closingBalance = entries.isEmpty ? openingBalance : entries.last['balance'];

    return {
      'opening': openingBalance,
      'closing': closingBalance,
      'entries': entries.length > 20 ? entries.sublist(entries.length - 20) : entries,
    };
  }

  /// Fetches the last 20 stock movement transactions across purchases, sales, adjustments, and returns
  Future<List<Map<String, dynamic>>> get20RecentStockChanges() async {
    final db = await DbHelper.instance.database;
    try {
      final List<Map<String, dynamic>> result = await db.rawQuery('''
        SELECT * FROM (
            SELECT pe.date, 'PURCHASE' as type, pe.entry_no as ref_no, pi.product_name, IFNULL(pi.batch, '') as batch, 
                   (IFNULL(pi.qty, 0) + IFNULL(pi.f_qty, 0)) as in_qty, 0 as out_qty
            FROM purchase_items pi 
            JOIN purchase_entries pe ON pi.entry_no = pe.entry_no
            WHERE IFNULL(pe.is_deleted, 0) = 0
            
            UNION ALL
            
            SELECT sn.date, 'SALE' as type, sn.entry_no as ref_no, si.product_name, IFNULL(si.batch_number, '') as batch, 
                   0 as in_qty, IFNULL(si.qty, 0) as out_qty
            FROM sales_items si
            JOIN sales_invoices sn ON si.invoice_no = sn.entry_no
            WHERE IFNULL(sn.is_deleted, 0) = 0
            
            UNION ALL
            
            SELECT sa.date, 'ADJUSTMENT' as type, sa.entry_no as ref_no, sai.product_name, IFNULL(sai.batch_number, '') as batch,
                   CASE WHEN sai.adjusted_qty > 0 THEN sai.adjusted_qty ELSE 0 END as in_qty,
                   CASE WHEN sai.adjusted_qty < 0 THEN -sai.adjusted_qty ELSE 0 END as out_qty
            FROM stock_adjustment_items sai
            JOIN stock_adjustments sa ON sai.adjustment_no = sa.entry_no
            WHERE IFNULL(sa.is_deleted, 0) = 0

            UNION ALL
            
            SELECT srn.date, 'SALE RETURN' as type, srn.entry_no as ref_no, sri.product_name, IFNULL(sri.batch_number, '') as batch, 
                   IFNULL(sri.quantity, 0) as in_qty, 0 as out_qty
            FROM sales_return_items sri
            JOIN sales_return_invoices srn ON sri.return_no = srn.entry_no
            WHERE IFNULL(srn.is_deleted, 0) = 0
            
            UNION ALL
            
            SELECT prn.date, 'PURCHASE RETURN' as type, prn.entry_no as ref_no, pri.product_name, IFNULL(pri.batch, '') as batch, 
                   0 as in_qty, IFNULL(pri.qty, 0) as out_qty
            FROM purchase_return_items pri
            JOIN purchase_return_entries prn ON pri.entry_no = prn.entry_no
            WHERE IFNULL(prn.is_deleted, 0) = 0
        ) t 
        ORDER BY date DESC
        LIMIT 20
      ''');
      return result;
    } catch (e) {
      debugPrint("Error fetching 20 recent stock changes: $e");
      return [];
    }
  }

  /// Generates multi-product time-series graph points & metrics for visual stock movement analysis
  Future<Map<String, dynamic>> generateMultiProductMovementGraphData({
    required List<String> productNames,
    required DateTime fromDate,
    required DateTime toDate,
    String interval = 'Monthly',
  }) async {
    final db = await DbHelper.instance.database;

    final cleanProductNames = productNames.map((p) => p.trim()).where((p) => p.isNotEmpty).toSet().toList();

    if (cleanProductNames.isEmpty) {
      return {'buckets': <Map<String, dynamic>>[], 'productNames': <String>[], 'summaries': <String, Map<String, dynamic>>{}};
    }

    Map<String, List<Map<String, dynamic>>> productSales = {};

    for (var pName in cleanProductNames) {
      final pRes = await db.query('product_master', columns: ['id'], where: 'name = ? COLLATE NOCASE', whereArgs: [pName]);
      String productId = pRes.isNotEmpty ? pRes.first['id'].toString() : '';

      final fromStr = fromDate.toIso8601String().split('T')[0];
      final toStr = toDate.toIso8601String().split('T')[0];

      final salesData = await db.rawQuery('''
        SELECT sn.date, sn.entry_no as bill_no, si.qty as qty, si.total as amount
        FROM sales_items si
        JOIN sales_invoices sn ON si.invoice_no = sn.entry_no
        WHERE (TRIM(si.product_name) = ? COLLATE NOCASE OR (? != '' AND si.product_id = ?))
          AND IFNULL(sn.is_deleted, 0) = 0
          AND date(sn.date) >= ? AND date(sn.date) <= ?
      ''', [pName, productId, productId, fromStr, toStr]);

      productSales[pName] = salesData;
    }

    String getBucketKey(DateTime dt) {
      if (interval == 'Daily') return DateFormat('yyyy-MM-dd').format(dt);
      if (interval == 'Weekly') {
        final startOfWeek = dt.subtract(Duration(days: dt.weekday - 1));
        return DateFormat('yyyy-MM-dd').format(startOfWeek);
      }
      if (interval == 'Quarterly') {
        int q = ((dt.month - 1) ~/ 3) + 1;
        return "${dt.year}-Q$q";
      }
      return DateFormat('yyyy-MM').format(dt);
    }

    String getBucketLabel(DateTime dt) {
      if (interval == 'Daily') return DateFormat('dd/MM').format(dt);
      if (interval == 'Weekly') return "Wk ${DateFormat('dd/MM').format(dt)}";
      if (interval == 'Quarterly') {
        int q = ((dt.month - 1) ~/ 3) + 1;
        return "Q$q '${DateFormat('yy').format(dt)}";
      }
      return DateFormat('MMM yy').format(dt);
    }

    Map<String, Map<String, dynamic>> bucketMap = {};
    DateTime current = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final end = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);

    while (!current.isAfter(end)) {
      final key = getBucketKey(current);
      if (!bucketMap.containsKey(key)) {
        Map<String, int> productQty = {};
        Map<String, Set<String>> productBills = {};
        Map<String, double> productRev = {};

        for (var pName in cleanProductNames) {
          productQty[pName] = 0;
          productBills[pName] = <String>{};
          productRev[pName] = 0.0;
        }

        bucketMap[key] = {
          'key': key,
          'label': getBucketLabel(current),
          'date': current,
          'qty': productQty,
          'bills': productBills,
          'revenue': productRev,
        };
      }

      if (interval == 'Daily') {
        current = current.add(const Duration(days: 1));
      } else if (interval == 'Weekly') {
        current = current.add(const Duration(days: 7));
      } else if (interval == 'Quarterly') {
        current = DateTime(current.year, current.month + 3, 1);
      } else {
        current = DateTime(current.year, current.month + 1, 1);
      }
    }

    for (var pName in cleanProductNames) {
      final rows = productSales[pName] ?? [];
      for (var row in rows) {
        DateTime? dt = DateTime.tryParse(row['date'].toString());
        if (dt == null) continue;
        final key = getBucketKey(dt);
        if (bucketMap.containsKey(key)) {
          int q = ((row['qty'] as num?) ?? 0).toInt();
          double rev = ((row['amount'] as num?) ?? 0.0).toDouble();
          String billNo = row['bill_no'].toString();

          var bQty = bucketMap[key]!['qty'] as Map<String, int>;
          var bRev = bucketMap[key]!['revenue'] as Map<String, double>;
          var bBills = bucketMap[key]!['bills'] as Map<String, Set<String>>;

          bQty[pName] = (bQty[pName] ?? 0) + q;
          bRev[pName] = (bRev[pName] ?? 0.0) + rev;
          (bBills[pName] ??= <String>{}).add(billNo);
        }
      }
    }

    Map<String, Map<String, dynamic>> productSummaries = {};
    for (var pName in cleanProductNames) {
      productSummaries[pName] = {
        'productName': pName,
        'totalQty': 0,
        'totalBills': 0,
        'totalRevenue': 0.0,
        'peakQty': 0,
        'peakLabel': 'N/A',
        'firstNonZeroQty': 0,
      };
    }

    Map<String, Set<String>> allBillsMap = {};
    for (var pName in cleanProductNames) {
      allBillsMap[pName] = <String>{};
    }

    List<Map<String, dynamic>> timeBuckets = [];

    bucketMap.forEach((key, b) {
      Map<String, int> formattedQty = {};
      Map<String, int> formattedBills = {};
      Map<String, double> formattedRev = {};

      for (var pName in cleanProductNames) {
        int q = (b['qty'] as Map<String, int>)[pName] ?? 0;
        Set<String> bills = (b['bills'] as Map<String, Set<String>>)[pName] ?? {};
        double rev = (b['revenue'] as Map<String, double>)[pName] ?? 0.0;

        allBillsMap[pName]?.addAll(bills);

        formattedQty[pName] = q;
        formattedBills[pName] = bills.length;
        formattedRev[pName] = rev;

        var sum = productSummaries[pName]!;
        sum['totalQty'] = (sum['totalQty'] as int) + q;
        sum['totalRevenue'] = (sum['totalRevenue'] as double) + rev;

        if (q > (sum['peakQty'] as int)) {
          sum['peakQty'] = q;
          sum['peakLabel'] = b['label'] as String;
        }

        if ((sum['firstNonZeroQty'] as int) == 0 && q > 0) {
          sum['firstNonZeroQty'] = q;
        }
      }

      timeBuckets.add({
        'key': b['key'],
        'label': b['label'],
        'date': b['date'],
        'qty': formattedQty,
        'bills': formattedBills,
        'revenue': formattedRev,
      });
    });

    for (var pName in cleanProductNames) {
      productSummaries[pName]!['totalBills'] = allBillsMap[pName]?.length ?? 0;
    }

    return {
      'buckets': timeBuckets,
      'productNames': cleanProductNames,
      'summaries': productSummaries,
    };
  }

  /// Fetches period-over-period product movement comparison (Month A vs Month B)
  Future<List<Map<String, dynamic>>> getInventoryMovementScreenerData({
    required DateTime fromDateA,
    required DateTime toDateA,
    required DateTime fromDateB,
    required DateTime toDateB,
  }) async {
    final db = await DbHelper.instance.database;

    final fromStrA = fromDateA.toIso8601String().split('T')[0];
    final toStrA = toDateA.toIso8601String().split('T')[0];
    final fromStrB = fromDateB.toIso8601String().split('T')[0];
    final toStrB = toDateB.toIso8601String().split('T')[0];

    // Query sales quantity & bills summary for Period A vs Period B
    final List<Map<String, dynamic>> res = await db.rawQuery('''
      SELECT 
        TRIM(si.product_name) as name,
        SUM(CASE WHEN date(sn.date) >= ? AND date(sn.date) <= ? THEN si.qty ELSE 0 END) as qty_a,
        COUNT(DISTINCT CASE WHEN date(sn.date) >= ? AND date(sn.date) <= ? THEN sn.entry_no ELSE NULL END) as bills_a,
        SUM(CASE WHEN date(sn.date) >= ? AND date(sn.date) <= ? THEN si.qty ELSE 0 END) as qty_b,
        COUNT(DISTINCT CASE WHEN date(sn.date) >= ? AND date(sn.date) <= ? THEN sn.entry_no ELSE NULL END) as bills_b
      FROM sales_items si
      JOIN sales_invoices sn ON si.invoice_no = sn.entry_no
      WHERE IFNULL(sn.is_deleted, 0) = 0
        AND ((date(sn.date) >= ? AND date(sn.date) <= ?) OR (date(sn.date) >= ? AND date(sn.date) <= ?))
      GROUP BY TRIM(si.product_name)
      HAVING (qty_a > 0 OR qty_b > 0)
      ORDER BY qty_b DESC, qty_a DESC
    ''', [
      fromStrA, toStrA,
      fromStrA, toStrA,
      fromStrB, toStrB,
      fromStrB, toStrB,
      fromStrA, toStrA,
      fromStrB, toStrB,
    ]);

    return res.map((r) {
      int qA = ((r['qty_a'] as num?) ?? 0).toInt();
      int bA = ((r['bills_a'] as num?) ?? 0).toInt();
      int qB = ((r['qty_b'] as num?) ?? 0).toInt();
      int bB = ((r['bills_b'] as num?) ?? 0).toInt();

      double growth = 0.0;
      if (qA > 0) {
        growth = ((qB - qA) / qA) * 100.0;
      } else if (qB > 0) {
        growth = 100.0;
      }

      return {
        'productName': r['name'].toString(),
        'qtyA': qA,
        'billsA': bA,
        'qtyB': qB,
        'billsB': bB,
        'growthTrend': growth,
      };
    }).toList();
  }

  /// Generates time-series graph points & metrics for visual stock movement analysis
  Future<Map<String, dynamic>> generateStockMovementGraphData({
    required String primaryProductName,
    String? compareProductName,
    required DateTime fromDate,
    required DateTime toDate,
    String interval = 'Monthly',
  }) async {
    List<String> pList = [primaryProductName];
    if (compareProductName != null && compareProductName.trim().isNotEmpty) {
      pList.add(compareProductName.trim());
    }

    final multiData = await generateMultiProductMovementGraphData(
      productNames: pList,
      fromDate: fromDate,
      toDate: toDate,
      interval: interval,
    );

    final List<Map<String, dynamic>> buckets = List<Map<String, dynamic>>.from(multiData['buckets'] ?? []);
    final summaries = multiData['summaries'] as Map<String, Map<String, dynamic>>;

    List<Map<String, dynamic>> legacyBuckets = buckets.map((b) {
      final qMap = b['qty'] as Map<String, int>;
      final bMap = b['bills'] as Map<String, int>;
      final rMap = b['revenue'] as Map<String, double>;

      int pQ = qMap[primaryProductName.trim()] ?? 0;
      int pB = bMap[primaryProductName.trim()] ?? 0;
      double pR = rMap[primaryProductName.trim()] ?? 0.0;

      int cQ = (compareProductName != null) ? (qMap[compareProductName.trim()] ?? 0) : 0;
      int cB = (compareProductName != null) ? (bMap[compareProductName.trim()] ?? 0) : 0;
      double cR = (compareProductName != null) ? (rMap[compareProductName.trim()] ?? 0.0) : 0.0;

      return {
        'key': b['key'],
        'label': b['label'],
        'date': b['date'],
        'primaryQty': pQ,
        'primaryBills': pB,
        'primaryRevenue': pR,
        'compareQty': cQ,
        'compareBills': cB,
        'compareRevenue': cR,
      };
    }).toList();

    var pSum = summaries[primaryProductName.trim()] ?? {
      'productName': primaryProductName,
      'totalQty': 0,
      'totalBills': 0,
      'totalRevenue': 0.0,
      'peakQty': 0,
      'peakLabel': 'N/A',
      'growthTrend': 0.0,
    };
    pSum['growthTrend'] = 0.0;

    var cSum = (compareProductName != null && summaries.containsKey(compareProductName.trim()))
        ? summaries[compareProductName.trim()]
        : null;
    if (cSum != null) cSum['growthTrend'] = 0.0;

    return {
      'buckets': legacyBuckets,
      'primarySummary': pSum,
      'compareSummary': cSum,
      'multiData': multiData,
    };
  }


  // =========================================================================
  // BLUEPRINT SECTION 6A: AUTOMATED REORDER SYSTEM (Velocity * Lead Time)
  // =========================================================================
  Future<List<Map<String, dynamic>>> getAutomatedReorderList() async {
    final db = await DbHelper.instance.database;

    // Formula: Reorder Qty = (Max Sales Velocity * Lead Time) - Current Stock
    return await db.rawQuery('''
      SELECT 
        p.id, 
        p.name, 
        p.preferred_wholesale as supplier, 
        p.manufacturer_id as manufacturer, 
        p.lead_time, 
        IFNULL(b.current_stock, 0) as stock,
        IFNULL(Velocity.max_daily_qty, 0) as max_velocity,
        ((IFNULL(Velocity.max_daily_qty, 0) * p.lead_time) - IFNULL(b.current_stock, 0)) as suggested_reorder_qty
      FROM product_master p
      LEFT JOIN (
        SELECT product_id, SUM(current_stock) as current_stock 
        FROM stock_batches 
        GROUP BY product_id
      ) b ON p.id = b.product_id
      LEFT JOIN (
        SELECT si.product_id, MAX(daily_total) as max_daily_qty
        FROM (
          SELECT product_id, invoice_no, SUM(qty) as daily_total
          FROM sales_items
          GROUP BY product_id, invoice_no
        ) si
        JOIN sales_invoices sn ON si.invoice_no = sn.entry_no
        WHERE sn.date >= date('now', '-30 days')
        GROUP BY si.product_id
      ) Velocity ON p.id = Velocity.product_id
      WHERE suggested_reorder_qty > 0 OR IFNULL(b.current_stock, 0) <= p.reorder_level
      ORDER BY suggested_reorder_qty DESC
    ''');
  }

  // =========================================================================
  // BLUEPRINT SECTION 8: DAILY BUSINESS SUMMARY & COLLECTION SPLIT
  // =========================================================================
  Future<Map<String, dynamic>> getDailyBusinessSummary(DateTime targetDate) async {
    final db = await DbHelper.instance.database;
    String dStr = targetDate.toIso8601String().split('T')[0];

    final sales = await db.rawQuery('''
      SELECT 
        IFNULL(SUM(grand_total), 0) as net_sales,
        IFNULL(SUM(sub_total), 0) as gross_sales,
        IFNULL(SUM(discount + additional_discount), 0) as total_discount,
        IFNULL(SUM(CASE WHEN customer_acc = 'Cash' THEN rcvd_amt ELSE 0 END), 0) as cash_collection,
        IFNULL(SUM(CASE WHEN customer_acc = 'UPI' THEN rcvd_amt ELSE 0 END), 0) as upi_collection,
        IFNULL(SUM(CASE WHEN customer_acc = 'Card' THEN rcvd_amt ELSE 0 END), 0) as card_collection,
        IFNULL(SUM(CASE WHEN customer_acc = 'Credit' THEN (grand_total - rcvd_amt) ELSE 0 END), 0) as credit_sales
      FROM sales_invoices 
      WHERE date(date) = ? AND is_deleted = 0
    ''', [dStr]);

    final purchases = await db.rawQuery('''
      SELECT IFNULL(SUM(grand_total), 0) as total_purchases 
      FROM purchase_entries 
      WHERE date(date) = ?
    ''', [dStr]);

    // Calculate Gross Profit for the day (Sales Net - Landing Cost of items sold)
    final profit = await db.rawQuery('''
      SELECT IFNULL(SUM(si.profit), 0) as total_gross_profit
      FROM sales_items si
      JOIN sales_invoices sn ON si.invoice_no = sn.entry_no
      WHERE date(sn.date) = ? AND sn.is_deleted = 0
    ''', [dStr]);

    return {
      'sales': sales.isNotEmpty ? sales.first : {},
      'purchases': purchases.isNotEmpty ? purchases.first : {},
      'profit': profit.isNotEmpty ? profit.first : {},
    };
  }

  // =========================================================================
  // BLUEPRINT SECTION 5A: SUPPLIER AGING ANALYSIS (30/60/90 DAYS)
  // =========================================================================
  Future<List<Map<String, dynamic>>> getSupplierAgingReport() async {
    final db = await DbHelper.instance.database;
    return await db.rawQuery('''
      SELECT 
        supplier_name,
        SUM(CASE WHEN days_old <= 30 THEN balance ELSE 0 END) as "0_30_days",
        SUM(CASE WHEN days_old > 30 AND days_old <= 60 THEN balance ELSE 0 END) as "31_60_days",
        SUM(CASE WHEN days_old > 60 AND days_old <= 90 THEN balance ELSE 0 END) as "61_90_days",
        SUM(CASE WHEN days_old > 90 THEN balance ELSE 0 END) as "90_plus_days",
        SUM(balance) as total_outstanding
      FROM (
        SELECT 
          supplier_name, 
          (grand_total - paid_amount) as balance,
          CAST(julianday('now') - julianday(date) AS INTEGER) as days_old
        FROM purchase_entries 
        WHERE payment_status != 1 AND (grand_total - paid_amount) > 0
      ) 
      GROUP BY supplier_name
      ORDER BY total_outstanding DESC
    ''');
  }

  // =========================================================================
  // BLUEPRINT SECTION 4B: GSTR-3B & GSTR-1 TAX SUMMARY ENGINE
  // =========================================================================
  Future<Map<String, dynamic>> getGstSummary(DateTime fromDate, DateTime toDate) async {
    final db = await DbHelper.instance.database;
    String fromStr = fromDate.toIso8601String().split('T')[0];
    String toStr = toDate.toIso8601String().split('T')[0];

    // Outward Supplies (Sales - GSTR-1 Base)
    final outward = await db.rawQuery('''
      SELECT 
        IFNULL(SUM(si.taxable_sp * si.qty), 0) as taxable_value,
        IFNULL(SUM(CASE WHEN sn.tax_type = 'Gst' THEN si.gst_amt / 2 ELSE 0 END), 0) as cgst_collected,
        IFNULL(SUM(CASE WHEN sn.tax_type = 'Gst' THEN si.gst_amt / 2 ELSE 0 END), 0) as sgst_collected,
        IFNULL(SUM(CASE WHEN sn.tax_type = 'Interstate' THEN si.gst_amt ELSE 0 END), 0) as igst_collected
      FROM sales_items si
      JOIN sales_invoices sn ON si.invoice_no = sn.entry_no
      WHERE date(sn.date) BETWEEN ? AND ? AND sn.is_deleted = 0
    ''', [fromStr, toStr]);

    // Input Tax Credit (Purchases - GSTR-3B Base)
    final itc = await db.rawQuery('''
      SELECT 
        IFNULL(SUM(pi.net), 0) as taxable_value,
        IFNULL(SUM(CASE WHEN pe.tax_type != 'Interstate' THEN pi.gst_amt / 2 ELSE 0 END), 0) as cgst_itc,
        IFNULL(SUM(CASE WHEN pe.tax_type != 'Interstate' THEN pi.gst_amt / 2 ELSE 0 END), 0) as sgst_itc,
        IFNULL(SUM(CASE WHEN pe.tax_type = 'Interstate' THEN pi.gst_amt ELSE 0 END), 0) as igst_itc
      FROM purchase_items pi
      JOIN purchase_entries pe ON pi.entry_no = pe.entry_no
      WHERE date(pe.date) BETWEEN ? AND ?
    ''', [fromStr, toStr]);

    return {
      'outward': outward.isNotEmpty ? outward.first : {},
      'itc': itc.isNotEmpty ? itc.first : {},
    };
  }

  // =========================================================================
  // BLUEPRINT SECTION 4A: SCHEDULE H/H1/X DRUG CONTROLLER REGISTER
  // =========================================================================
  Future<List<Map<String, dynamic>>> getScheduleDrugRegister(DateTime fromDate, DateTime toDate, String scheduleType) async {
    final db = await DbHelper.instance.database;
    String fromStr = fromDate.toIso8601String().split('T')[0];
    String toStr = toDate.toIso8601String().split('T')[0];

    return await db.rawQuery('''
      SELECT 
        sn.date,
        sn.patient as patient_name,
        sn.mobile as patient_contact,
        sn.doctor as doctor_name,
        sn.doctor_reg_no,
        p.name as medicine_name,
        si.batch_number as batch_no,
        si.qty as sold_quantity
      FROM sales_items si
      JOIN sales_invoices sn ON si.invoice_no = sn.entry_no
      JOIN product_master p ON si.product_id = p.id
      WHERE date(sn.date) BETWEEN ? AND ? 
        AND sn.is_deleted = 0 
        AND p.schedule = ? COLLATE NOCASE
      ORDER BY sn.date ASC
    ''', [fromStr, toStr, scheduleType]);
  }

  // =========================================================================
  // AUTOMATED LOCAL DATABASE BACKUP & RESTORE ENGINE
  // =========================================================================
  Future<String> performManualBackup() async {
    try {
      final path = await DbHelper.instance.createLocalBackup();
      logAudit('DATABASE_BACKUP', 'Created manual database backup at $path');
      return path;
    } catch (e) {
      debugPrint("Backup Error: $e");
      rethrow;
    }
  }

  Future<String?> performAutoBackupIfNeeded({bool forceOnExit = false}) async {
    try {
      final path = await DbHelper.instance.performAutoBackupIfNeeded(forceOnExit: forceOnExit);
      if (path != null) {
        logAudit('DATABASE_AUTO_BACKUP', 'Automated database backup created at $path');
      }
      return path;
    } catch (e) {
      debugPrint("Auto Backup Error: $e");
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getAvailableBackups() async {
    return await DbHelper.instance.getAvailableBackups();
  }

  Future<bool> restoreFromBackup(File backupFile) async {
    isLoading = true;
    notifyListeners();
    try {
      final success = await DbHelper.instance.restoreBackupFile(backupFile);
      if (success) {
        await loadFromDatabase();
        await syncVoucherSequences();
        logAudit('DATABASE_RESTORE', 'Restored database from ${backupFile.path}');
      }
      return success;
    } catch (e) {
      debugPrint("Restore Error: $e");
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // =========================================================================
  // THE ENTERPRISE SECURITY & AUDIT ENGINE
  // =========================================================================

  Future<void> loadSecuritySettings() async {
    final prefs = await SharedPreferences.getInstance();
    // Default security toggles
    securityToggles['lock_previous_day_edits'] = prefs.getBool('lock_previous_day_edits') ?? true;
    securityToggles['require_pin_edit_today_sales'] = prefs.getBool('require_pin_edit_today_sales') ?? false;
    securityToggles['require_pin_delete_sales'] = prefs.getBool('require_pin_delete_sales') ?? false;
    securityToggles['require_pin_delete_purchases'] = prefs.getBool('require_pin_delete_purchases') ?? false;
    securityToggles['require_pin_discount_threshold'] = prefs.getBool('require_pin_discount_threshold') ?? false;
    securityToggles['require_pin_stock_adjustments'] = prefs.getBool('require_pin_stock_adjustments') ?? false;
    securityToggles['require_pin_add_agent_stock_check'] = prefs.getBool('require_pin_add_agent_stock_check') ?? true;
    securityToggles['require_pin_admin_stock_adjustment'] = prefs.getBool('require_pin_admin_stock_adjustment') ?? true;
    securityToggles['require_pin_write_off'] = prefs.getBool('require_pin_write_off') ?? false;
    securityToggles['require_pin_merge_products'] = prefs.getBool('require_pin_merge_products') ?? false;
    securityToggles['require_pin_change_rates'] = prefs.getBool('require_pin_change_rates') ?? false;
    securityToggles['require_pin_edit_master'] = prefs.getBool('require_pin_edit_master') ?? false;
    securityToggles['require_pin_financial_reports'] = prefs.getBool('require_pin_financial_reports') ?? false;
    securityToggles['require_pin_db_reset_imports'] = prefs.getBool('require_pin_db_reset_imports') ?? false;

    // Cryptographic PIN Hashing Migration & Loading
    String savedHash = prefs.getString('master_pin_hash') ?? "";
    String legacyPw = prefs.getString('master_pw') ?? "";

    if (savedHash.isEmpty && legacyPw.isNotEmpty) {
      savedHash = SecurityCrypto.hashPin(legacyPw);
      await prefs.setString('master_pin_hash', savedHash);
      await prefs.remove('master_pw');
    }

    masterPassword = savedHash; // Secure salted SHA-256 hash
    notifyListeners();
  }

  void updateSecurityToggle(String key, bool value) async {
    securityToggles[key] = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    notifyListeners();
  }

  String masterPassword = "";

  void setMasterPassword(String plainPin) async {
    final hash = SecurityCrypto.hashPin(plainPin);
    masterPassword = hash;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('master_pin_hash', hash);
    await prefs.remove('master_pw'); // Remove unhashed legacy password
    notifyListeners();
  }

  bool verifyMasterPin(String inputPin) {
    if (masterPassword.isEmpty) return false;
    return SecurityCrypto.verifyPin(inputPin, masterPassword);
  }

  bool isAdminSessionActive() => _adminSessionActive;

  void refreshAdminSession() {
    _adminSessionActive = true;
    _adminSessionTimer?.cancel();
    // Keeps the admin logged in for 5 minutes without needing PIN again
    _adminSessionTimer = Timer(const Duration(minutes: 5), () {
      _adminSessionActive = false;
    });
  }

  bool isEditLocked(DateTime documentDate) {
    if (securityToggles['lock_previous_day_edits'] == true) {
      DateTime today = DateTime.now();
      if (documentDate.year != today.year || documentDate.month != today.month || documentDate.day != today.day) {
        return true; // Locked because it's from a previous day
      }
    }
    if (securityToggles['require_pin_edit_today_sales'] == true) {
      return true; // Locked because ALL edits require PIN
    }
    return false;
  }

  Future<void> logAudit(String actionType, String description, {String userId = "Admin"}) async {
    if (kIsWeb) return;
    try {
      final db = await DbHelper.instance.database;
      await db.insert('system_audit_logs', {
        'timestamp': DateTime.now().toIso8601String(),
        'action_type': actionType,
        'description': description,
        'user_role': 'Admin',
        'user_id': userId,
      });
    } catch (e) {
      debugPrint("Audit Log Error: $e");
    }
  }


  Future<void> mergeProducts({required String keepProductId, required String deleteProductId}) async {
    isLoading = true;
    notifyListeners();
    try {
      await DbHelper.instance.mergeDuplicateProducts(keepProductId: keepProductId, deleteProductId: deleteProductId);
      await loadFromDatabase();
      errorMessage = "";
    } catch (e) {
      errorMessage = "Merge failed: $e";
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // =========================================================================
  // DYNAMIC 12-MONTH PRODUCT RANKING & AUTO-REORDER ENGINE
  // =========================================================================
  Future<List<ProductRanking>> getDynamicProductRanking(int monthsCount, {bool rollingMode = false}) async {
    final db = await DbHelper.instance.database;
    final now = DateTime.now();

    // 1. Generate monthly date intervals
    List<MonthlyStat> intervals = [];
    for (int i = 0; i < monthsCount; i++) {
      DateTime start;
      DateTime end;

      if (rollingMode) {
        end = now.subtract(Duration(days: i * 30));
        start = end.subtract(const Duration(days: 30));
      } else {
        DateTime monthAnchor = DateTime(now.year, now.month - i, 1);
        start = DateTime(monthAnchor.year, monthAnchor.month, 1);
        end = DateTime(monthAnchor.year, monthAnchor.month + 1, 0, 23, 59, 59, 999);
      }

      intervals.add(MonthlyStat(startDate: start, endDate: end));
    }

    if (intervals.isEmpty) return [];

    final totalStartDay = DateFormat('yyyy-MM-dd').format(intervals.last.startDate);
    final totalEndDay = DateFormat('yyyy-MM-dd').format(intervals.first.endDate);

    // 2. Individual Line-Item Pack Ratio Formula:
    // Calculates: (si.qty / each line's individual pack size)
    const String linePackRatio = '''
      (CAST(si.qty AS REAL) / IFNULL(NULLIF(COALESCE(NULLIF(si.packin, 0), NULLIF(si.packing, 0)), 0), 1))
    ''';

    final StringBuffer dynamicCols = StringBuffer();
    for (int i = 0; i < intervals.length; i++) {
      final startDay = DateFormat('yyyy-MM-dd').format(intervals[i].startDate);
      final endDay = DateFormat('yyyy-MM-dd').format(intervals[i].endDate);

      dynamicCols.write(''',
        IFNULL(SUM(CASE WHEN si.norm_date BETWEEN '$startDay' AND '$endDay' THEN $linePackRatio ELSE 0 END), 0.0) as qty_$i,
        IFNULL(MAX(CASE WHEN si.norm_date BETWEEN '$startDay' AND '$endDay' THEN $linePackRatio ELSE 0 END), 0.0) as peak_$i,
        COUNT(DISTINCT CASE WHEN si.norm_date BETWEEN '$startDay' AND '$endDay' THEN si.entry_no ELSE NULL END) as cnt_$i''');
    }

    // 3. High-Speed Date-Filtered Query without Correlated Subqueries
    final String query = '''
      SELECT 
        p.id,
        p.name,
        IFNULL(p.packing, 1) as packing,
        IFNULL(p.mrp, 0.0) as mrp,
        IFNULL(p.purchase_rate, 0.0) as purchase_rate,
        IFNULL(p.category_id, 'General') as category_id,
        IFNULL(p.rack_id, '') as rack_id,
        IFNULL(p.manufacturer_id, IFNULL(p.patent, '')) as manufacturer_id,
        IFNULL(p.patent, '') as patent,
        IFNULL(p.generic_name, '') as generic_name,
        IFNULL(p.preferred_wholesale, '-') as preferred_wholesale,
        IFNULL(p.reorder_level, 10) as reorder_level,
        IFNULL(p.max_level, 100) as max_level,
        IFNULL(p.is_active, 1) as is_active,
        sales.*
      FROM (
        SELECT 
          COALESCE(
            NULLIF(si.product_id, ''),
            (SELECT id FROM product_master pm WHERE LOWER(pm.name) = LOWER(si.product_name) LIMIT 1)
          ) as resolved_product_id
          ${dynamicCols.toString()}
          , SUM($linePackRatio) as total_period_units
        FROM (
          SELECT 
            si_raw.qty,
            si_raw.packin,
            si_raw.packing,
            si_raw.product_id,
            si_raw.product_name,
            sn_raw.entry_no,
            (CASE 
              WHEN sn_raw.date LIKE '%/%' THEN substr(sn_raw.date, 7, 4) || '-' || substr(sn_raw.date, 4, 2) || '-' || substr(sn_raw.date, 1, 2)
              ELSE substr(sn_raw.date, 1, 10)
            END) as norm_date
          FROM sales_items si_raw
          JOIN sales_invoices sn_raw ON si_raw.invoice_no = sn_raw.entry_no
          WHERE (sn_raw.is_deleted = 0 OR sn_raw.is_deleted IS NULL)
            AND (sn_raw.customer_acc != 'Special Order' OR sn_raw.customer_acc IS NULL)
            AND (
              (sn_raw.date >= '$totalStartDay' AND sn_raw.date <= '$totalEndDay 23:59:59')
              OR (
                sn_raw.date LIKE '%/%' AND 
                (substr(sn_raw.date, 7, 4) || '-' || substr(sn_raw.date, 4, 2) || '-' || substr(sn_raw.date, 1, 2)) BETWEEN '$totalStartDay' AND '$totalEndDay'
              )
            )
        ) si
        WHERE si.norm_date BETWEEN '$totalStartDay' AND '$totalEndDay'
        GROUP BY resolved_product_id
        HAVING total_period_units > 0 AND resolved_product_id IS NOT NULL AND resolved_product_id != ''
      ) sales
      JOIN product_master p ON p.id = sales.resolved_product_id
      GROUP BY p.id
      ORDER BY sales.total_period_units DESC, p.name ASC
    ''';

    // 4. Batch fetch auxiliary details in parallel with deduplication CTEs to eliminate multi-hundred-thousand row scans
    const stockQuery = '''
      SELECT product_id, SUM(current_stock) as total_stock 
      FROM stock_batches 
      WHERE current_stock > 0 
      GROUP BY product_id
    ''';

    const offerQuery = '''
      WITH RankedOffers AS (
        SELECT 
          pi_o.product_id, pi_o.qty, pi_o.f_qty, pi_o.disc_percent, pi_o.s_disc_percent,
          ROW_NUMBER() OVER (PARTITION BY pi_o.product_id ORDER BY pe_o.date DESC, CAST(pe_o.entry_no AS INTEGER) DESC) as rn
        FROM purchase_items pi_o
        JOIN purchase_entries pe_o ON pi_o.entry_no = pe_o.entry_no
        WHERE (pe_o.is_deleted = 0 OR pe_o.is_deleted IS NULL)
          AND (pi_o.f_qty > 0 OR pi_o.disc_percent > 0 OR pi_o.s_disc_percent > 0)
          AND pi_o.product_id IS NOT NULL AND pi_o.product_id != ''
      )
      SELECT product_id, qty, f_qty, disc_percent, s_disc_percent
      FROM RankedOffers
      WHERE rn = 1
    ''';

    const lastSaleQuery = '''
      WITH RankedLastSales AS (
        SELECT 
          si_l.product_id, 
          (CAST(si_l.qty AS REAL) / IFNULL(NULLIF(COALESCE(NULLIF(si_l.packin, 0), NULLIF(si_l.packing, 0)), 0), 1)) as last_qty,
          ROW_NUMBER() OVER (PARTITION BY si_l.product_id ORDER BY sn_l.date DESC, CAST(sn_l.entry_no AS INTEGER) DESC) as rn
        FROM sales_items si_l
        JOIN sales_invoices sn_l ON si_l.invoice_no = sn_l.entry_no
        WHERE (sn_l.is_deleted = 0 OR sn_l.is_deleted IS NULL)
          AND si_l.product_id IS NOT NULL AND si_l.product_id != ''
      )
      SELECT product_id, last_qty
      FROM RankedLastSales
      WHERE rn = 1
    ''';

    const supplierQuery = '''
      WITH RankedSuppliers AS (
        SELECT 
          pi_w.product_id, 
          pe_w.supplier_name,
          ROW_NUMBER() OVER (PARTITION BY pi_w.product_id ORDER BY pe_w.date DESC, CAST(pe_w.entry_no AS INTEGER) DESC) as rn
        FROM purchase_items pi_w
        JOIN purchase_entries pe_w ON pi_w.entry_no = pe_w.entry_no
        WHERE (pe_w.is_deleted = 0 OR pe_w.is_deleted IS NULL)
          AND pe_w.supplier_name IS NOT NULL AND pe_w.supplier_name != ''
          AND pi_w.product_id IS NOT NULL AND pi_w.product_id != ''
      )
      SELECT product_id, supplier_name
      FROM RankedSuppliers
      WHERE rn = 1
    ''';

    final String specialOrdersQuery = '''
      SELECT date, special_order_json 
      FROM sales_invoices 
      WHERE special_order_json IS NOT NULL 
        AND special_order_json != '[]' 
        AND (is_deleted = 0 OR is_deleted IS NULL)
        AND (
          (date BETWEEN '$totalStartDay' AND '$totalEndDay 23:59:59')
          OR (
            date LIKE '%/%' 
            AND (substr(date, 7, 4) || '-' || substr(date, 4, 2) || '-' || substr(date, 1, 2)) BETWEEN '$totalStartDay' AND '$totalEndDay'
          )
        )
    ''';

    final results = await Future.wait([
      db.rawQuery(query),
      db.rawQuery(stockQuery),
      db.rawQuery(offerQuery),
      db.rawQuery(lastSaleQuery),
      db.rawQuery(supplierQuery),
      db.rawQuery(specialOrdersQuery),
    ]);

    final List<Map<String, dynamic>> rows = results[0];
    final List<Map<String, dynamic>> stockRows = results[1];
    final List<Map<String, dynamic>> offerRows = results[2];
    final List<Map<String, dynamic>> lastSaleRows = results[3];
    final List<Map<String, dynamic>> supplierRows = results[4];
    final List<Map<String, dynamic>> specialOrdersRows = results[5];

    final Map<String, double> stockMap = {
      for (var r in stockRows) r['product_id']?.toString() ?? '': (r['total_stock'] as num?)?.toDouble() ?? 0.0
    };

    final Map<String, String> offerMap = {};
    for (var r in offerRows) {
      String pid = r['product_id']?.toString() ?? '';
      if (pid.isNotEmpty) {
        double fQty = (r['f_qty'] as num?)?.toDouble() ?? 0;
        double qty = (r['qty'] as num?)?.toDouble() ?? 0;
        double disc = (r['disc_percent'] as num?)?.toDouble() ?? 0;
        double sDisc = (r['s_disc_percent'] as num?)?.toDouble() ?? 0;
        if (fQty > 0) {
          offerMap[pid] = '${qty.toInt()}+${fQty.toInt()}';
        } else if (disc > 0) {
          offerMap[pid] = '${disc % 1 == 0 ? disc.toInt() : disc.toStringAsFixed(1)}% DISC';
        } else if (sDisc > 0) {
          offerMap[pid] = '${sDisc % 1 == 0 ? sDisc.toInt() : sDisc.toStringAsFixed(1)}% SDISC';
        }
      }
    }

    final Map<String, double> lastSaleMap = {};
    for (var r in lastSaleRows) {
      String pid = r['product_id']?.toString() ?? '';
      if (pid.isNotEmpty) {
        lastSaleMap[pid] = (r['last_qty'] as num?)?.toDouble() ?? 0.0;
      }
    }

    final Map<String, String> supplierMap = {};
    for (var r in supplierRows) {
      String pid = r['product_id']?.toString() ?? '';
      if (pid.isNotEmpty) {
        supplierMap[pid] = r['supplier_name']?.toString() ?? '-';
      }
    }

    // 5. Processing Special Orders (fetched concurrently)
    final Map<String, List<double>> specialQtyMap = {};
    for (var sRow in specialOrdersRows) {
      try {
        String dateStr = sRow['date']?.toString() ?? "";
        DateTime sDate = DateTime.tryParse(dateStr) ?? DateTime.now();
        List<dynamic> itemsList = jsonDecode(sRow['special_order_json']);

        for (var item in itemsList) {
          String pName = (item['name'] ?? "").toString().toLowerCase().trim();
          double qty = (item['qty'] as num?)?.toDouble() ?? 0.0;
          if (pName.isEmpty || qty <= 0) continue;

          specialQtyMap.putIfAbsent(pName, () => List.filled(intervals.length, 0.0));

          for (int i = 0; i < intervals.length; i++) {
            if (!sDate.isBefore(intervals[i].startDate) && !sDate.isAfter(intervals[i].endDate)) {
              specialQtyMap[pName]![i] += qty;
            }
          }
        }
      } catch (_) {}
    }

    // 6. Construct ProductRanking instances
    List<ProductRanking> rankings = [];
    for (var row in rows) {
      final String pid = row['id']?.toString() ?? '';
      final String pName = (row['name'] ?? '').toString();
      final String pNameLower = pName.toLowerCase().trim();
      final List<double>? pSpecials = specialQtyMap[pNameLower];

      List<MonthlyStat> stats = [];
      double totalSpecialForProd = 0.0;

      for (int i = 0; i < intervals.length; i++) {
        double specQty = (pSpecials != null && i < pSpecials.length) ? pSpecials[i] : 0.0;
        totalSpecialForProd += specQty;

        stats.add(MonthlyStat(
          startDate: intervals[i].startDate,
          endDate: intervals[i].endDate,
        )
          ..monthSale = (row['qty_$i'] as num?)?.toDouble() ?? 0.0
          ..higherSale = (row['peak_$i'] as num?)?.toDouble() ?? 0.0
          ..saleCount = (row['cnt_$i'] as num?)?.toInt() ?? 0
          ..specialOrderQty = specQty);
      }

      String prefSupplier = row['preferred_wholesale']?.toString() ?? '-';
      if (prefSupplier == '-' || prefSupplier.isEmpty) {
        prefSupplier = supplierMap[pid] ?? '-';
      }

      rankings.add(ProductRanking(
        id: pid,
        name: pName,
        pack: (row['packing'] as num?)?.toInt() ?? 1,
        isActive: (row['is_active'] as num?)?.toInt() == 1,
        patent: row['patent']?.toString() ?? '',
        category: row['category_id']?.toString() ?? 'General',
        rack: row['rack_id']?.toString() ?? '',
        mrp: (row['mrp'] as num?)?.toDouble() ?? 0.0,
        pRate: (row['purchase_rate'] as num?)?.toDouble() ?? 0.0,
        genericName: row['generic_name']?.toString() ?? '',
        preferredWholesale: prefSupplier,
        offer: offerMap[pid] ?? '',
        monthlyStats: stats,
        lastSaleQty: lastSaleMap[pid] ?? 0.0,
        currentStock: stockMap[pid] ?? 0.0,
      )..specialOrders = totalSpecialForProd);
    }

    return rankings;
  }

  /// Fetches a lightweight list of products with current stock and metadata for instant UI rendering.
  Future<List<ProductRanking>> getLightweightProductList({int monthsCount = 1}) async {
    final db = await DbHelper.instance.database;

    const query = '''
      SELECT 
        p.id,
        p.name,
        IFNULL(p.packing, 1) as packing,
        IFNULL(p.mrp, 0.0) as mrp,
        IFNULL(p.purchase_rate, 0.0) as purchase_rate,
        IFNULL(p.category_id, 'General') as category_id,
        IFNULL(p.rack_id, '') as rack_id,
        IFNULL(p.patent, '') as patent,
        IFNULL(p.generic_name, '') as generic_name,
        IFNULL(p.preferred_wholesale, '-') as preferred_wholesale,
        IFNULL(p.is_active, 1) as is_active,
        IFNULL(s.total_stock, 0.0) as total_stock
      FROM product_master p
      LEFT JOIN (
        SELECT product_id, SUM(current_stock) as total_stock
        FROM stock_batches
        WHERE current_stock > 0
        GROUP BY product_id
      ) s ON p.id = s.product_id
      WHERE p.is_active = 1 OR s.total_stock > 0
      ORDER BY p.name ASC
    ''';

    final List<Map<String, dynamic>> rows = await db.rawQuery(query);

    final now = DateTime.now();
    List<MonthlyStat> emptyStats = [];
    for (int i = 0; i < monthsCount; i++) {
      DateTime monthAnchor = DateTime(now.year, now.month - i, 1);
      emptyStats.add(MonthlyStat(
        startDate: DateTime(monthAnchor.year, monthAnchor.month, 1),
        endDate: DateTime(monthAnchor.year, monthAnchor.month + 1, 0, 23, 59, 59, 999),
      ));
    }

    return rows.map((row) {
      return ProductRanking(
        id: row['id']?.toString() ?? '',
        name: row['name']?.toString() ?? '',
        pack: (row['packing'] as num?)?.toInt() ?? 1,
        isActive: (row['is_active'] as num?)?.toInt() == 1,
        patent: row['patent']?.toString() ?? '',
        category: row['category_id']?.toString() ?? 'General',
        rack: row['rack_id']?.toString() ?? '',
        mrp: (row['mrp'] as num?)?.toDouble() ?? 0.0,
        pRate: (row['purchase_rate'] as num?)?.toDouble() ?? 0.0,
        genericName: row['generic_name']?.toString() ?? '',
        preferredWholesale: row['preferred_wholesale']?.toString() ?? '-',
        offer: '',
        monthlyStats: emptyStats.map((s) => MonthlyStat(startDate: s.startDate, endDate: s.endDate)).toList(),
        lastSaleQty: 0.0,
        currentStock: (row['total_stock'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();
  }

  Map<String, ProductRanking> _cachedRankingsMap = {};

  Map<String, ProductRanking> get cachedRankingsMap => _cachedRankingsMap;

  void updateCachedRankings(List<ProductRanking> rankings) {
    _cachedRankingsMap = {};
    for (var pr in rankings) {
      if (pr.id.isNotEmpty) _cachedRankingsMap[pr.id] = pr;
      if (pr.name.isNotEmpty) _cachedRankingsMap[pr.name.toUpperCase().trim()] = pr;
    }
    SharedPreferences.getInstance().then((prefs) {
      final encodedList = rankings.take(2000).map((r) => jsonEncode(r.toJson())).toList();
      prefs.setStringList('pr_cached_rankings_v2', encodedList);
    });
    notifyListeners();
  }

  Future<Map<String, ProductRanking>> getProductRankingsMap() async {
    if (_cachedRankingsMap.isNotEmpty) {
      return _cachedRankingsMap;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedList = prefs.getStringList('pr_cached_rankings_v2');
      final Map<String, ProductRanking> map = {};

      if (cachedList != null && cachedList.isNotEmpty) {
        for (var item in cachedList) {
          try {
            final pr = ProductRanking.fromJson(jsonDecode(item));
            if (pr.id.isNotEmpty) map[pr.id] = pr;
            if (pr.name.isNotEmpty) map[pr.name.toUpperCase().trim()] = pr;
          } catch (_) {}
        }
      }

      if (map.isNotEmpty) {
        _cachedRankingsMap = map;
        return _cachedRankingsMap;
      }

      final monthsVal = int.tryParse(prefs.getString('pr_months') ?? "1") ?? 1;
      final lightData = await getLightweightProductList(monthsCount: monthsVal);

      final rankFormula = prefs.getString('pr_formula_v2') ?? "=MAX(C,D,A)+B";
      final reOrderFormula = prefs.getString('pr_reorder_f') ?? "W";
      final warningFormula = prefs.getString('pr_warning_f') ?? "IF(Y <= F, F, 0)";
      final maxOrderFormula = prefs.getString('pr_maxorder_f') ?? "Y * 2";
      final mavgInterval = prefs.getInt('pr_mavg_int') ?? 0;
      final specialInterval = prefs.getInt('pr_spec_int') ?? 0;

      List<Map<String, dynamic>> reOrderRules = [];
      String? rulesJson = prefs.getString('pr_reorder_rules_v1');
      if (rulesJson != null) {
        try {
          reOrderRules = List<Map<String, dynamic>>.from(jsonDecode(rulesJson));
        } catch (_) {}
      }

      List<Map<String, dynamic>> maxOrderRules = [];
      String? maxRulesJson = prefs.getString('pr_maxorder_rules_v1');
      if (maxRulesJson != null) {
        try {
          maxOrderRules = List<Map<String, dynamic>>.from(jsonDecode(maxRulesJson));
        } catch (_) {}
      }

      List<Map<String, dynamic>> customMetricColumns = [];
      List<String>? savedColsJson = prefs.getStringList('pr_cols_dual_v8');
      if (savedColsJson != null) {
        for (var item in savedColsJson) {
          try {
            Map<String, dynamic> decoded = jsonDecode(item);
            customMetricColumns.add({
              'rank': decoded['rank']?.toString() ?? "1st HIGHER",
              'metric': decoded['metric']?.toString() ?? "TOTAL MONTH SALE",
              'interval': decoded['interval'] ?? 0,
              'minRank': (decoded['minRank'] as num?)?.toDouble() ?? 0.0,
            });
          } catch (_) {}
        }
      }

      ProductRankingCalculator.calculateRankings(
        rankings: lightData,
        rankFormula: rankFormula,
        reOrderFormula: reOrderFormula,
        reOrderRules: reOrderRules,
        warningFormula: warningFormula,
        maxOrderFormula: maxOrderFormula,
        maxOrderRules: maxOrderRules,
        customMetricColumns: customMetricColumns,
        mavgInterval: mavgInterval,
        specialInterval: specialInterval,
      );

      for (var pr in lightData) {
        if (pr.id.isNotEmpty) map[pr.id] = pr;
        if (pr.name.isNotEmpty) map[pr.name.toUpperCase().trim()] = pr;
      }

      _cachedRankingsMap = map;
      final encodedList = lightData.take(2000).map((r) => jsonEncode(r.toJson())).toList();
      await prefs.setStringList('pr_cached_rankings_v2', encodedList);
    } catch (e) {
      debugPrint("Error loading/calculating product rankings: $e");
    }

    return _cachedRankingsMap;
  }

  Future<Uint8List?> exportProductRankingToExcelBytes(
    List<ProductRanking> rankings,
    List<Map<String, dynamic>> customCols, {
    bool showFeatures = true,
    bool showMonths = true,
    bool showRanking = true,
    bool showOffers = true,
  }) async {
    var excel = Excel.createExcel();
    Sheet sheet = excel['Product Ranking'];
    excel.delete('Sheet1');

    List<CellValue> header = [
      TextCellValue('Name'),
      TextCellValue('Pack'),
    ];

    if (showFeatures) {
      header.addAll([
        TextCellValue('Rack'),
        TextCellValue('Category'),
        TextCellValue('Patent'),
        TextCellValue('MRP'),
        TextCellValue('P.Rate'),
      ]);
    }

    if (showOffers) {
      header.add(TextCellValue('Offer'));
    }

    if (showMonths && rankings.isNotEmpty) {
      for (int i = 0; i < rankings.first.monthlyStats.length; i++) {
        header.add(TextCellValue('M${i + 1} Sale Count'));
        header.add(TextCellValue('M${i + 1} Higher Sale'));
        header.add(TextCellValue('M${i + 1} Month Sale'));
      }
    }

    if (showRanking) {
      header.add(TextCellValue('Moving Average'));
      header.add(TextCellValue('Special Orders'));
      header.add(TextCellValue('Last Sale'));
      for (int i = 0; i < customCols.length; i++) {
        header.add(TextCellValue('Criteria ${String.fromCharCode(68 + i)}'));
      }
    }

    // ALWAYS INCLUDE RANK SCORE ("RANK" COLUMN) IN EXCEL EXPORT - NEVER HIDE THIS!
    header.add(TextCellValue('Rank Score'));

    if (showRanking) {
      header.add(TextCellValue('Warning'));
      header.add(TextCellValue('Reorder Level'));
      header.add(TextCellValue('Max Order Level'));
    }

    sheet.appendRow(header);

    for (var r in rankings) {
      List<CellValue> row = [
        TextCellValue(r.name),
        IntCellValue(r.pack),
      ];

      if (showFeatures) {
        row.addAll([
          TextCellValue(r.rack),
          TextCellValue(r.category),
          TextCellValue(r.patent),
          DoubleCellValue(r.mrp),
          DoubleCellValue(r.pRate),
        ]);
      }

      if (showOffers) {
        row.add(TextCellValue(r.offer));
      }

      if (showMonths && r.monthlyStats.isNotEmpty) {
        for (var m in r.monthlyStats) {
          row.add(IntCellValue(m.saleCount));
          row.add(DoubleCellValue(m.higherSale));
          row.add(DoubleCellValue(m.monthSale));
        }
      }

      if (showRanking) {
        row.add(DoubleCellValue(r.mavg));
        row.add(DoubleCellValue(r.specialOrders));
        row.add(DoubleCellValue(r.lastSaleQty));
        for (int i = 0; i < customCols.length; i++) {
          String letter = String.fromCharCode(68 + i);
          row.add(DoubleCellValue(r.customCriteria[letter] ?? 0.0));
        }
      }

      // ALWAYS INCLUDE RANK SCORE ("RANK" COLUMN)
      row.add(DoubleCellValue(r.weightedScore));

      if (showRanking) {
        row.add(DoubleCellValue(r.warningScore));
        row.add(DoubleCellValue(r.reOrderScore));
        row.add(DoubleCellValue(r.maxOrderLevel));
      }

      sheet.appendRow(row);
    }
    return Uint8List.fromList(excel.encode()!);
  }

  // =========================================================================
  // AUDIT EDIT HISTORY ENGINE
  // =========================================================================
  Future<void> logEditHistory({
    required String entryNo,
    required double oldTotal,
    required String oldItemsJson,
    String? newItemsJson,
    required String reason,
  }) async {
    if (kIsWeb) return;
    try {
      final db = await DbHelper.instance.database;
      await db.insert('edit_history_logs', {
        'original_entry_no': entryNo,
        'edit_timestamp': DateTime.now().toIso8601String(),
        'previous_grand_total': oldTotal,
        'previous_items_json': oldItemsJson,
        if (newItemsJson != null) 'new_items_json': newItemsJson,
        'reason_for_edit': reason,
      });
    } catch (e) {
      debugPrint("Edit Log Error: $e");
    }
  }

  Future<List<Map<String, dynamic>>> getCurrentInvoiceItems(String entryNo) async {
    if (kIsWeb) return [];
    try {
      final db = await DbHelper.instance.database;
      // Try sales_items first
      final salesRows = await db.query(
        'sales_items',
        where: 'invoice_no = ?',
        whereArgs: [entryNo],
      );
      if (salesRows.isNotEmpty) {
        return salesRows.map((r) => {
          'name': r['product_name'] ?? '',
          'batch': r['batch'] ?? '',
          'qty': r['qty'] ?? 0,
          'pack': r['pack'] ?? r['pack_size'] ?? '',
          's_rate': r['s_rate'] ?? r['rate'] ?? 0,
          'total': r['total'] ?? 0,
        }).toList();
      }

      // Next try purchase_items
      final purRows = await db.query(
        'purchase_items',
        where: 'entry_no = ?',
        whereArgs: [entryNo],
      );
      if (purRows.isNotEmpty) {
        return purRows.map((r) => {
          'name': r['product_name'] ?? '',
          'batch': r['batch'] ?? '',
          'qty': r['qty'] ?? 0,
          'pack': r['pack'] ?? r['pack_size'] ?? '',
          'p_rate': r['p_rate'] ?? r['rate'] ?? 0,
          'total': r['total'] ?? 0,
        }).toList();
      }
    } catch (e) {
      debugPrint("Error fetching current items for $entryNo: $e");
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getEditHistory(String entryNo) async {
    if (kIsWeb) return [];
    final db = await DbHelper.instance.database;
    return await db.query(
      'edit_history_logs',
      where: 'original_entry_no = ?',
      whereArgs: [entryNo],
      orderBy: 'edit_timestamp DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getEditedInvoices(String type, DateTime from, DateTime to, {bool editedOnly = false}) async {
    if (kIsWeb) return [];
    final db = await DbHelper.instance.database;
    final fromStr = DateTime(from.year, from.month, from.day, 0, 0, 0).toIso8601String();
    final toStr = DateTime(to.year, to.month, to.day, 23, 59, 59).toIso8601String();

    String table = 'sales_invoices';
    if (type == 'Purchase') {
      table = 'purchase_entries';
    } else if (type == 'Sale Return') {
      table = 'sales_return_invoices';
    } else if (type == 'Purchase Return') {
      table = 'purchase_return_entries';
    }

    String query = '''
      SELECT t.*, e.edit_timestamp, e.previous_grand_total, e.previous_items_json, e.reason_for_edit
      FROM $table t
      ${editedOnly ? 'INNER JOIN' : 'LEFT JOIN'} edit_history_logs e ON t.entry_no = e.original_entry_no
      WHERE t.date >= ? AND t.date <= ?
      ORDER BY t.date DESC
    ''';

    return await db.rawQuery(query, [fromStr, toStr]);
  }

  // =========================================================================
  // DRAFT WORKSPACE SESSIONS
  // =========================================================================
  Future<void> saveSalesDrafts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> drafts = _salesSessions.map((s) {
        return jsonEncode({
          'agent': s['agent'],
          'customerAcc': s['customerAcc'],
          'patient': s['patient'],
          'mobile': s['mobile'],
          'doctor': s['doctor'],
          'taxType': s['taxType'],
          'orderType': s['orderType'],
          'items': (s['items'] as List<SaleItem>).map((i) => i.toMap()).toList(),
        });
      }).toList();
      await prefs.setStringList('sales_workspaces_v2', drafts);

      // Save active session draft key for fast startup recovery
      int activeIdx = _activeSessionIdx.clamp(0, _salesSessions.length - 1);
      final activeData = _salesSessions[activeIdx];
      final activeDraftJson = jsonEncode({
        'agent': activeData['agent'],
        'customerAcc': activeData['customerAcc'],
        'patient': activeData['patient'],
        'mobile': activeData['mobile'],
        'doctor': activeData['doctor'],
        'taxType': activeData['taxType'],
        'orderType': activeData['orderType'],
        'items': (activeData['items'] as List<SaleItem>).map((i) => i.toMap()).toList(),
      });
      await prefs.setString('sales_active_workspace_draft', activeDraftJson);
    } catch (e) {
      debugPrint("Error saving sales drafts: $e");
    }
  }

  Future<void> loadSalesDrafts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final drafts = prefs.getStringList('sales_workspaces_v2');
      if (drafts != null && drafts.length == 3) {
        for (int i = 0; i < 3; i++) {
          final decoded = jsonDecode(drafts[i]) as Map<String, dynamic>;
          final rawItems = decoded['items'] as List<dynamic>? ?? [];
          _salesSessions[i] = {
            'agent': decoded['agent'] ?? '',
            'customerAcc': decoded['customerAcc'] ?? 'Cash',
            'patient': decoded['patient'] ?? 'P1',
            'mobile': decoded['mobile'] ?? '',
            'doctor': decoded['doctor'] ?? 'D1',
            'taxType': decoded['taxType'] ?? 2,
            'orderType': decoded['orderType'] ?? 0,
            'items': rawItems.map((m) => SaleItem.fromMap(m)).toList(),
          };
        }
      }

      // Recovery check for active workspace draft
      String? draftJson = prefs.getString('sales_active_workspace_draft');
      if (draftJson != null && draftJson.isNotEmpty) {
        Map<String, dynamic> data = jsonDecode(draftJson);
        final rawItems = data['items'] as List<dynamic>? ?? [];
        if (rawItems.isNotEmpty) {
          _salesSessions[0] = {
            'items': (data['items'] as List?)?.map((i) => SaleItem.fromMap(i)).toList() ?? [],
            'agent': data['agent'] ?? '',
            'customerAcc': data['customerAcc'] ?? 'Cash',
            'patient': data['patient'] ?? 'P1',
            'mobile': data['mobile'] ?? '',
            'doctor': data['doctor'] ?? 'D1',
            'taxType': data['taxType'] ?? 2,
            'orderType': data['orderType'] ?? 0,
          };
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint("Draft recovery error: $e");
    }
  }

  // =========================================================================
  // SMART DUPLICATE CHECKER
  // =========================================================================
  bool isDuplicateRecentEntry({
    required bool isPurchase,
    required List<dynamic> currentItems,
    required double currentTotal,
  }) {
    final list = isPurchase ? _purchases : _sales;
    if (list.isEmpty) return false;

    // Check top 3 most recent entries
    for (int i = 0; i < (list.length > 3 ? 3 : list.length); i++) {
      final dynamic recent = list[i];
      
      // 1. Check grand total match
      if ((recent.grandTotal - currentTotal).abs() > 0.05) continue;
      
      // 2. Check items match
      if (recent.items.length != currentItems.length) continue;
      
      bool allMatched = true;
      for (var cItem in currentItems) {
         bool found = recent.items.any((rItem) {
           if (isPurchase) {
             return rItem.productName == cItem.productName && rItem.qty == cItem.qty && (rItem.total - cItem.total).abs() <= 0.05;
           } else {
             return rItem.product.name == cItem.product.name && rItem.qty == cItem.qty && (rItem.total - cItem.total).abs() <= 0.05;
           }
         });
         if (!found) {
           allMatched = false;
           break;
         }
      }
      if (allMatched) return true;
    }
    return false;
  }
}

// --- PART 3: FINANCIAL PRECISION ENGINE ---
// This safely forces all floating-point math to exactly 2 decimal places
extension FinancialPrecision on double {
  double get asCurrency => (this * 100).roundToDouble() / 100;
}

class _PendingSyncTask {
  final SyncTask task;
  final Future<Map<String, dynamic>> Function(Function(double, String) onProgress) taskRunner;

  _PendingSyncTask({required this.task, required this.taskRunner});
}

class SyncTask {
  final String id;
  final String title;
  final String type; // 'Import', 'Export', 'Delete'
  double progress; // 0.0 to 1.0
  String status; // 'Pending', 'In Progress', 'Completed', 'Failed'
  String statusMessage;
  String? resultMessage;

  SyncTask({
    required this.id,
    required this.title,
    required this.type,
    this.progress = 0.0,
    this.status = 'Pending',
    this.statusMessage = 'Queued...',
    this.resultMessage,
  });
}

// PURE TOP-LEVEL FUNCTION FOR BACKGROUND ISOLATE
List<Product> parseMasterProductsIsolate(List<Map<String, dynamic>> rows) {
  final List<Product> list = [];
  for (int i = 0; i < rows.length; i++) {
    final row = rows[i];
    list.add(Product(
      id: row['id'].toString(),
      name: row['name'] ?? "UNKNOWN",
      hsnCode: row['hsn_code'] ?? "",
      rack: row['rack_id'] ?? "",
      category: row['category_id'] ?? "General",
      subCategory: row['sub_category_id'] ?? "",
      packSize: (row['packing'] as num?)?.toInt() ?? 1,
      mrp: (row['mrp'] as num?)?.toDouble() ?? 0.0,
      purchaseRate: (row['purchase_rate'] as num?)?.toDouble() ?? 0.0,
      salePrice: (row['sale_rate'] as num?)?.toDouble() ?? 0.0,
      gstPercent: TaxCalculator.roundGstPercent((row['gst_percent'] as num?)?.toDouble() ?? 12.0),
      sDiscPercent: (row['s_disc_percent'] as num?)?.toDouble() ?? 0.0,
      patent: row['patent'] ?? "",
      schedule: row['schedule'] ?? "",
      reorderLevel: (row['reorder_level'] as num?)?.toInt() ?? 10,
      maxLevel: (row['max_level'] as num?)?.toInt() ?? 100,
      manufacturer: row['manufacturer_id'] ?? "",
      genericName: row['generic_name'] ?? "",
      stock: 0,
    ));
  }
  return list;
}
