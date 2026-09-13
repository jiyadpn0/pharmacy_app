import 'package:flutter/material.dart';
import '../models/erp_models.dart';

import '../screens/product_merge_screen.dart';
import '../screens/stock_adjustment_batch_screen.dart';
import '../screens/stock_adjustment_batch_report_screen.dart';


import '../screens/dashboard_screen.dart';
import '../screens/sales_screen.dart';
import '../screens/purchase_screen.dart';
import '../screens/stock_list_screen.dart';
import '../screens/sales_report_screen.dart';
import '../screens/purchase_report_screen.dart';
import '../screens/master/patient_registration_screen.dart';
import '../screens/master/product_registration_screen.dart';
import '../screens/master/category_registration_screen.dart';
import '../screens/master/manufacturer_registration_screen.dart';
import '../screens/master/generic_registration_screen.dart';
import '../screens/master/doctor_registration_screen.dart';
import '../screens/master/staff_registration_screen.dart';
import '../screens/master/rack_registration_screen.dart';
import '../screens/master/tax_registration_screen.dart';
import '../screens/master/ledger_registration_screen.dart';
import '../screens/master/account_registration_screen.dart';
import '../screens/master/prescription_registration_screen.dart';
import '../screens/master/product_import_screen.dart';
import '../screens/reports/daily_report_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/damage_entry_screen.dart';
import '../screens/stock_checking_screen.dart';
import '../screens/lists/supplier_list_screen.dart';
import '../screens/lists/patient_list_screen.dart';
import '../screens/expiry_check_screen.dart';
import '../screens/sales_return_screen.dart';
import '../screens/purchase_return_screen.dart';
import '../screens/lists/stock_list_report_screen.dart';
import '../screens/payment_entry_screen.dart';
import '../screens/reports/stock_ledger_screen.dart';
import '../screens/consolidate_stock_screen.dart';
import '../screens/reports/product_mapping_report_screen.dart';
import '../screens/reports/product_ranking_screen.dart';
import '../screens/customer_ledger_screen.dart';
import '../screens/gst_report_screen.dart';
import '../screens/sales_return_report_screen.dart';
import '../screens/purchase_return_report_screen.dart';
import '../screens/reports/schedule_h1_register_screen.dart';
import '../screens/reports/reorder_assistant_screen.dart';
import '../screens/reports/order_book_screen.dart';
import '../screens/order_confirmation_screen.dart';

class TabItem {
  final String title;
  final Widget content;
  final bool closable;
  Offset position;
  Size size;
  bool isMaximized;

  TabItem({
    required this.title,
    required this.content,
    this.closable = true,
    this.position = const Offset(50, 50),
    this.size = const Size(1200, 700),
    this.isMaximized = true,
  });
}

class AppProvider extends ChangeNotifier {
  final List<TabItem> _openTabs = [];
  int _activeTabIndex = 0;
  String _statusMessage = "";
  bool _isDarkMode = false;

  List<TabItem> get openTabs => _openTabs;
  int get activeTabIndex => _activeTabIndex;
  String get statusMessage => _statusMessage;
  bool get isDarkMode => _isDarkMode;

  void toggleDarkMode() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }

  void setDarkMode(bool val) {
    if (_isDarkMode != val) {
      _isDarkMode = val;
      notifyListeners();
    }
  }

  void setStatusMessage(String msg) {
    if (_statusMessage != msg) {
      _statusMessage = msg;
      notifyListeners();
    }
  }

  AppProvider() {
    _openTabs.add(TabItem(
      title: 'Home',
      content: const KeyedSubtree(key: ValueKey('Home'), child: DashboardScreen()),

      closable: false,
    ));
  }

  // Window openers
  void openSales({String? invoiceNo}) => addTab("SALES ENTRY", SalesScreen(initialInvoiceNo: invoiceNo));
  void openPurchase({String? entryNo}) => addTab("PURCHASE ENTRY", LocalPurchaseScreen(initialInvoiceNo: entryNo));
  void openEditedInvoices() => openSettings(tab: "Edited Invoices");
  void openSales3() => addTab("SALES ENGINE PRO", const SalesScreen());
  void openPurchaseHistory() => addTab("PURCHASE HISTORY", const PurchaseReportScreen());
  void openAllStockDetails() => addTab("INVENTORY", const StockListScreen());
  void openInventory() => addTab("INVENTORY", const StockListReportScreen());
  void openProductMasterList() => openAllStockDetails();
  void openOrderBook() => addTab("Order Book", const SpecialOrdersScreen(initialView: 1));
  void openOrderConfirmation() => addTab("Order Confirmation", const OrderConfirmationScreen());
  void openSpecialOrders() => addTab("Special Orders", const SpecialOrdersScreen(initialView: 0));
  void openProductRanking() => addTab("Product Ranking", const ProductRankingScreen());
  void openSalesReport() => addTab("SALES ANALYSIS", const SalesReportScreen());
  void openScheduleH1Register() => addTab("SCHEDULE H1 REGISTER", const ScheduleH1RegisterScreen());
  void openReorderAssistant() => addTab("REORDER ASSISTANT", const ReorderAssistantScreen());
  void openSalesReturnReport() => addTab("SALES RETURN ANALYSIS", const SalesReturnReportScreen());
  void openGstReport() => addTab("GST FILING REPORT", const GstReportScreen());
  void openPurchaseReport() => addTab("PURCHASE ANALYSIS", const PurchaseReportScreen());
  void openPurchaseReturnReport() => addTab("PURCHASE RETURN ANALYSIS", const PurchaseReturnReportScreen());
  void openProductRegistration({String? initialName}) {
    int existingIdx = _openTabs.indexWhere((t) =>
      t.title == "Product Registration" || t.title == "PRODUCT REGISTRATION"
    );
    if (existingIdx != -1) {
      if (initialName == null || initialName.trim().isEmpty) {
        focusTab(existingIdx);
        return;
      }
      _openTabs.removeAt(existingIdx);
    }
    addTab("PRODUCT REGISTRATION", ProductRegistrationScreen(initialName: initialName));
  }
  void openPatientRegistration({Patient? patient}) => addTab("Patient Registration", PatientRegistrationScreen(initialPatient: patient));
  void openDoctorRegistration() => addTab("Doctor Registration", const DoctorRegistrationScreen());
  void openStaffManagement() => addTab("STAFF MASTER", const StaffRegistrationScreen());
  void openCategoryRegistration() => addTab("Category Registration", const CategoryRegistrationScreen());
  void openGenericRegistration() => addTab("Generic Registration", const GenericRegistrationScreen());
  void openRackRegistration() => addTab("Rack Registration", const RackRegistrationScreen());
  void openTaxRegistration() => addTab("Tax Registration", const TaxRegistrationScreen());
  void openManufacturerRegistration() => addTab("Manufacturer Registration", const ManufacturerRegistrationScreen());
  void openAccountRegistration() => addTab("ACCOUNT MASTER", const AccountRegistrationScreen());
  void openLedgerRegistration() => addTab("Ledger Registration", const LedgerRegistrationScreen());
  void openPrescriptionRegistration() => addTab("Prescription Registration", const PrescriptionRegistrationScreen());
  void openStockManagement() => addTab("Stock Management", const StockManagementScreen());
  void openPurchaseReturn({String? entryNo, List<Product>? initialExpiredItems}) =>
      addTab("PURCHASE RETURN", PurchaseReturnScreen(initialEntryNo: entryNo, initialExpiredItems: initialExpiredItems));
  void openSalesReturn({String? entryNo}) => addTab("SALES RETURN", SalesReturnScreen(initialReturnNo: entryNo));
  void openPayment() => addTab("Payment", const PaymentEntryScreen());
  void openReceipt() => addTab("Receipt", const CustomerLedgerScreen());
  void openStockMaintenance() => openAllStockDetails();
  void openStockAdjustment() => addTab("Damage Entry", const DamageEntryScreen(initialReason: "damage"));
  void openStockAdjustmentBatch() => addTab("Stock Adjustment (Batch)", const StockAdjustmentBatchScreen());
  void openStockChecking() => addTab("Stock Checking", const StockCheckingScreen());
  void openStockAdjustmentBatchReport() => addTab("Stock Adjustment Report", const StockAdjustmentBatchReportScreen());
  void openStockLedger() => addTab("Stock Ledger", const StockLedgerScreen());
  void openProductMappingReport() => addTab("Product Mapping Manager", const ProductMappingReportScreen());
  void openSupplierRegistration() => addTab("Supplier Registration", const SupplierListScreen());
  void openSupplierList() => addTab("Supplier List", const SupplierListScreen());
  void openPatientList() => addTab("Patient List", const PatientListScreen());
  void openCustomerLedger({String? patientName}) => addTab("Customer Ledger", CustomerLedgerScreen(initialPatient: patientName));
  void openDoctorList() => addTab("Doctor Registration", const DoctorRegistrationScreen());
  void openExpiryList() => addTab("Expiry List", const ExpiryCheckScreen());
  void openDailyReport() => addTab("Daily Report", const DailyReportScreen());
  void openConsolidateStock() => addTab("Consolidate Stock Position", const ConsolidateStockScreen());
  void openDamageEntry() => addTab("Damage Entry", const DamageEntryScreen(initialReason: "damage"));
  void openSettings({String? tab}) => addTab("Settings", SettingsScreen(initialTab: tab));
  void openSecuritySettings() => openSettings(tab: "Security & Backup");
  void openProductMerge() => addTab("Merge Products", const ProductMergeScreen());

  void addTab(String baseTitle, Widget content) {
    // If exact tab already exists, focus it instead of duplicating endlessly
    int existingIdx = _openTabs.indexWhere((t) => t.title == baseTitle);
    if (existingIdx != -1 && baseTitle != "SALES ENTRY" && baseTitle != "PURCHASE ENTRY") {
      focusTab(existingIdx);
      return;
    }

    int count = _openTabs.where((t) => t.title.startsWith(baseTitle)).length;
    String finalTitle = count == 0 ? baseTitle : "$baseTitle ${count + 1}";

    // Safe tab limit management: Close inactive non-transaction tabs first
    if (_openTabs.length >= 12) {
      int closeIdx = _openTabs.indexWhere((t) => 
        t.closable && 
        !t.title.contains("SALES") && 
        !t.title.contains("PURCHASE")
      );
      if (closeIdx != -1) {
        _openTabs.removeAt(closeIdx);
      } else if (_openTabs.length >= 15) {
        _openTabs.removeAt(1); // Failsafe only if memory exceeds 15 full tabs
      }
    }

    _openTabs.add(TabItem(
      title: finalTitle,
      content: KeyedSubtree(key: ValueKey(finalTitle), child: content),
      position: Offset(50.0 + (_openTabs.length * 20), 50.0 + (_openTabs.length * 20)),
      isMaximized: true,
    ));

    _activeTabIndex = _openTabs.length - 1;
    notifyListeners();
  }

  void updateWindowPosition(int index, Offset pos) {
    if (index >= 0 && index < _openTabs.length) {
      _openTabs[index].position = pos;
      notifyListeners();
    }
  }

  void updateWindowSize(int index, Size size) {
    if (index >= 0 && index < _openTabs.length) {
      _openTabs[index].size = size;
      notifyListeners();
    }
  }

  void toggleWindowMaximize(int index) {
    if (index >= 0 && index < _openTabs.length) {
      _openTabs[index].isMaximized = !_openTabs[index].isMaximized;
      notifyListeners();
    }
  }

  void focusTab(int index) {
    if (index >= 0 && index < _openTabs.length) {
      if (_activeTabIndex != index) {
        _activeTabIndex = index;
        notifyListeners();
      }
    }
  }

  void setTabIndex(int index) {
    _activeTabIndex = index;
    _statusMessage = "";
    notifyListeners();
  }

  void switchToSalesTab() {
    int idx = _openTabs.indexWhere((t) => t.title.startsWith("SALES ENTRY"));
    if (idx != -1) {
      setTabIndex(idx);
    } else {
      openSales();
    }
  }

  void closeTab(int index) {
    if (index == 0) return;
    _openTabs.removeAt(index);
    if (_activeTabIndex >= _openTabs.length) {
      _activeTabIndex = _openTabs.length - 1;
    }
    _statusMessage = "";
    notifyListeners();
  }

  void reorderTabs(int oldIndex, int newIndex) {
    if (oldIndex == 0) return;
    if (newIndex == 0) newIndex = 1;

    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    final TabItem item = _openTabs.removeAt(oldIndex);
    _openTabs.insert(newIndex, item);

    if (_activeTabIndex == oldIndex) {
      _activeTabIndex = newIndex;
    } else if (_activeTabIndex > oldIndex && _activeTabIndex <= newIndex) {
      _activeTabIndex--;
    } else if (_activeTabIndex < oldIndex && _activeTabIndex >= newIndex) {
      _activeTabIndex++;
    }

    notifyListeners();
  }
}
