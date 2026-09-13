import 'package:flutter/material.dart';
import '../models/erp_models.dart';
import '../utils/tax_calculator.dart';

class SalesController extends ChangeNotifier {
  // --- INVOICE STATE ---
  String entryNo = "";
  DateTime date = DateTime.now();
  String customerAcc = "Cash";
  String patient = "P1";
  String mobile = "";
  String doctor = "D1";
  String doctorRegNo = "";
  int gstType = 1; // 1 = GST, 2 = Non-GST
  int orderType = 0; // 0 = Normal, 1 = Special, 2 = One Time
  
  List<SaleItem> items = [];
  
  // --- FINANCIAL TOTALS ---
  double subTotal = 0.0;
  double footerDiscPct = 0.0;
  double footerDiscAmt = 0.0;
  double otherChargePct = 0.0;
  double otherChargeAmt = 0.0;
  double salesReturn = 0.0;
  double roundOff = 0.0;
  double grandTotal = 0.0;
  double rcvdAmt = 0.0;
  double balance = 0.0;

  // --- EDIT & DIRTY STATE TRACKING ---
  bool isExistingEntry = false;
  bool isDeleted = false;
  bool isDirty = false; // Tracks if the user made changes

  // Snapshot of the original invoice for safe "Undo" and abandoning edits
  SaleInvoice? _originalSnapshot;
  SaleInvoice? get originalSnapshot => _originalSnapshot;

  /// Initializes a new, clean bill.
  void initNewBill(String newEntryNo) {
    entryNo = newEntryNo;
    date = DateTime.now();
    customerAcc = "Cash";
    patient = "P1";
    mobile = "";
    doctor = "D1";
    doctorRegNo = "";
    gstType = 1;
    orderType = 0;
    
    items.clear();
    
    subTotal = 0.0;
    footerDiscPct = 0.0;
    footerDiscAmt = 0.0;
    otherChargePct = 0.0;
    otherChargeAmt = 0.0;
    salesReturn = 0.0;
    roundOff = 0.0;
    grandTotal = 0.0;
    rcvdAmt = 0.0;
    balance = 0.0;

    isExistingEntry = false;
    isDeleted = false;
    isDirty = false;
    _originalSnapshot = null;
    notifyListeners();
  }

  /// Loads an existing invoice SAFELY (Fixes the "Edit without saving" bug)
  void loadExistingInvoice(SaleInvoice invoice) {
    _originalSnapshot = invoice; // Keep a safe backup in memory
    
    entryNo = invoice.entryNo;
    date = invoice.date;
    customerAcc = invoice.customerAcc;
    patient = invoice.patient;
    mobile = invoice.mobile;
    doctor = invoice.doctor;
    doctorRegNo = invoice.doctorRegNo;
    gstType = invoice.taxType == "Gst" ? 1 : 2;
    
    // Deep copy the items so we don't accidentally modify the RAM cache
    items = invoice.items.map((it) => it.clone()).toList();
    
    subTotal = invoice.subTotal;
    footerDiscAmt = invoice.discount;
    footerDiscPct = invoice.discountPercent;
    otherChargeAmt = invoice.otherCharge;
    salesReturn = invoice.salesReturn;
    roundOff = invoice.roundOff;
    grandTotal = invoice.grandTotal;
    rcvdAmt = invoice.rcvdAmt;
    
    isExistingEntry = true;
    isDeleted = invoice.isDeleted;
    isDirty = false; // Freshly loaded, no edits made yet

    calculateFooter(); // Ensure math is perfectly synced
  }

  /// Marks the current session as modified
  void markDirty() {
    if (isExistingEntry && !isDirty) {
      isDirty = true;
      notifyListeners();
    }
  }

  /// Exact Row Math isolated from UI using Fixed-Point Integer Paise Model
  void calculateItem(int rowIndex, {bool isDiscAmtFocused = false, bool isGstAmtFocused = false}) {
    if (rowIndex < 0 || rowIndex >= items.length) return;
    
    final item = items[rowIndex];
    double pack = (item.packin > 0) ? item.packin.toDouble() : 1.0;

    // Unit Selling Rate in paise
    if (item.sRate <= 0) {
      item.sRate = item.product.salePrice > 0 ? (item.product.salePrice / pack) : item.mrp;
    }
    int sRatePaise = (item.sRate * 100).round();

    int grossPaise = sRatePaise * item.qty;

    // Discount Sync in Paise
    if (isDiscAmtFocused) {
      int discAmtPaise = (item.discAmt * 100).round();
      if (grossPaise > 0) {
        item.discPercent = TaxCalculator.round((discAmtPaise * 100.0) / grossPaise);
      } else {
        item.discPercent = 0.0;
      }
    } else {
      if (item.discPercent > 0) {
        int discAmtPaise = ((grossPaise * item.discPercent) / 100.0).round();
        item.discAmt = discAmtPaise / 100.0;
      } else {
        item.discAmt = 0.0;
      }
    }

    int discAmtPaise = (item.discAmt * 100).round();
    int netTaxablePaise = grossPaise - discAmtPaise;
    if (netTaxablePaise < 0) netTaxablePaise = 0;

    // GST Calculation using Integer Paise Model
    if (gstType == 1 && item.gstPercent > 0) {
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

    // Profit Calculation in Paise
    double effectivePackLCost = item.product.landingCost > 0 
        ? item.product.landingCost 
        : (item.product.purchaseRate > 0 ? item.product.purchaseRate : item.purchaseRate);

    int landingCostPaise = effectivePackLCost > 0 ? ((effectivePackLCost / pack) * 100).round() : 0;
    item.landingCost = landingCostPaise / 100.0;
    int totalCostPaise = landingCostPaise * (item.qty + item.fQty);
    int totalPaise = (item.total * 100).round();
    int profitPaise = totalPaise - totalCostPaise;
    item.profit = profitPaise / 100.0;

    markDirty();
    calculateFooter();
  }

  /// Footer Math isolated from UI using Fixed-Point Integer Paise Model
  void calculateFooter({bool isDiscAmtFocused = false, bool isOtherAmtFocused = false}) {
    int newSubTotalPaise = items.fold(0, (s, i) => s + (i.total * 100).round());

    // Footer Discount Math in Paise
    if (isDiscAmtFocused) {
      int footerDiscAmtPaise = (footerDiscAmt * 100).round();
      if (newSubTotalPaise > 0) {
        footerDiscPct = (footerDiscAmtPaise * 100.0) / newSubTotalPaise;
      } else {
        footerDiscPct = 0.0;
      }
    } else {
      int footerDiscAmtPaise = ((newSubTotalPaise * footerDiscPct) / 100.0).round();
      footerDiscAmt = footerDiscAmtPaise / 100.0;
    }

    // Other Charges Math in Paise
    if (isOtherAmtFocused) {
      int otherChargeAmtPaise = (otherChargeAmt * 100).round();
      if (newSubTotalPaise > 0) {
        otherChargePct = (otherChargeAmtPaise * 100.0) / newSubTotalPaise;
      } else {
        otherChargePct = 0.0;
      }
    } else {
      int otherChargeAmtPaise = ((newSubTotalPaise * otherChargePct) / 100.0).round();
      otherChargeAmt = otherChargeAmtPaise / 100.0;
    }

    int footerDiscAmtPaise = (footerDiscAmt * 100).round();
    int otherChargeAmtPaise = (otherChargeAmt * 100).round();
    int salesReturnPaise = (salesReturn * 100).round();

    int finalValPaise = newSubTotalPaise - footerDiscAmtPaise + otherChargeAmtPaise - salesReturnPaise;
    
    // Round Off to nearest rupee (100 paise)
    int roundedGrandTotalPaise = ((finalValPaise / 100.0).round()) * 100;
    int roundOffPaise = roundedGrandTotalPaise - finalValPaise;
    
    subTotal = newSubTotalPaise / 100.0;
    roundOff = roundOffPaise / 100.0;
    grandTotal = roundedGrandTotalPaise / 100.0;
    
    int rcvdAmtPaise = (rcvdAmt * 100).round();
    if (rcvdAmtPaise > 0) {
      balance = (rcvdAmtPaise - roundedGrandTotalPaise) / 100.0;
    } else {
      balance = 0.0;
    }

    notifyListeners();
  }
}
