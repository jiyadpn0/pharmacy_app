
enum PaymentMode { cash, card, upi, bank, split }
enum StockAdjustmentReason { damage, expiry, returnToSupplier, initialStock, correction }
enum BillType { credit, cash }
enum GstType { local, central, free }

extension NumPrecisionExtension on num {
  double get asCurrency => double.parse(toStringAsFixed(2));
}

class CompanyProfile {
  String name;
  String address;
  String phone;
  String email;
  String gstIn;
  String dlNumber;
  String tagline;

  CompanyProfile({
    this.name = "SAHAKAR MEDICALS & SURGICALS",
    this.address = "KALPETTA TOWN, WAYANAD",
    this.phone = "+91 0000000000",
    this.email = "sahakar@gmail.com",
    this.gstIn = "32AAAAA0000A1Z5",
    this.dlNumber = "DL/123/2024",
    this.tagline = "Professional Pharmacy Care",
  });
}

class ProductMaster {
  final String id;
  String name;
  String genericName;
  String manufacturerId;
  String categoryId;
  String rackId;
  String hsnCode;
  double gstPercent;
  String schedule;
  int reorderLevel;
  int maxLevel;
  String unit;
  int packing;
  String barcode;
  bool isControlled;
  bool isBanned;
  bool isNrx;
  bool isActive;
  String preferredWholesale;
  int leadTime;

  ProductMaster({
    required this.id,
    required this.name,
    this.genericName = "",
    this.manufacturerId = "",
    this.categoryId = "",
    this.rackId = "",
    this.hsnCode = "",
    this.gstPercent = 12.0,
    this.schedule = "H",
    this.reorderLevel = 10,
    this.maxLevel = 100,
    this.unit = "Strip",
    this.packing = 10,
    this.barcode = "",
    this.isControlled = false,
    this.isBanned = false,
    this.isNrx = false,
    this.isActive = true,
    this.preferredWholesale = "",
    this.leadTime = 2,
  });
}

class StockBatch {
  final String productId;
  final String batchNumber;
  DateTime expiryDate;
  DateTime mfgDate;
  int currentStock;
  double purchaseRate;
  double landingCost;
  double mrp;
  double saleRate;
  double wholesaleRate;
  int packing;
  String supplierName;
  double gstPercent;

  StockBatch({
    required this.productId,
    required this.batchNumber,
    required this.expiryDate,
    required this.mfgDate,
    this.currentStock = 0,
    this.purchaseRate = 0.0,
    this.landingCost = 0.0,
    this.mrp = 0.0,
    this.saleRate = 0.0,
    this.wholesaleRate = 0.0,
    this.packing = 1,
    this.supplierName = "",
    this.gstPercent = 12.0,
  });

  int get mrpPaise => (mrp * 100).round();
  int get saleRatePaise => (saleRate * 100).round();
  int get purchaseRatePaise => (purchaseRate * 100).round();
  int get landingCostPaise => (landingCost * 100).round();

  String get compositeKey => "$productId|$batchNumber|${expiryDate.month}/${expiryDate.year}|$mrp|$packing";
}

class Product {
  final String id;
  String name;
  String batch;
  String rack;
  String hsnCode;
  String expiry;
  int packSize;
  double mrp;
  double salePrice;
  double purchaseRate;
  double landingCost;
  double taxableSP;
  int stock;
  double gstPercent;
  String category;
  String subCategory;
  String manufacturer;
  String supplier;
  String patent;

  int get mrpPaise => (mrp * 100).round();
  int get salePricePaise => (salePrice * 100).round();
  int get purchaseRatePaise => (purchaseRate * 100).round();
  int get landingCostPaise => (landingCost * 100).round();
  int get taxableSPPaise => (taxableSP * 100).round();
  String schedule;
  String genericName;
  String use;
  double sDiscPercent;
  int reorderLevel;
  int maxLevel;
  bool isControlled;
  bool isBanned;
  bool isNrx;
  bool isActive;
  bool isDiscLocked;
  String preferredWholesale;
  int leadTime;
  String alias;

  static String cleanProductName(String input) {
    if (input.isEmpty) return "";
    String cleaned = input.trim();
    while ((cleaned.startsWith("'") && cleaned.endsWith("'")) ||
        (cleaned.startsWith('"') && cleaned.endsWith('"'))) {
      if (cleaned.length <= 1) break;
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }
    while (cleaned.startsWith("'") || cleaned.startsWith('"')) {
      if (cleaned.length <= 1) break;
      cleaned = cleaned.substring(1).trim();
    }
    while (cleaned.endsWith("'") || cleaned.endsWith('"')) {
      if (cleaned.length <= 1) break;
      cleaned = cleaned.substring(0, cleaned.length - 1).trim();
    }
    return cleaned;
  }

  Product({
    required this.id,
    required String name,
    this.batch = "",
    this.rack = "",
    this.hsnCode = "",
    this.expiry = "",
    this.packSize = 1,
    this.mrp = 0.0,
    this.salePrice = 0.0,
    this.purchaseRate = 0.0,
    this.landingCost = 0.0,
    this.taxableSP = 0.0,
    this.stock = 0,
    this.gstPercent = 12.0,
    this.category = "General",
    this.subCategory = "",
    this.manufacturer = "",
    this.supplier = "",
    this.patent = "",
    this.schedule = "",
    String genericName = "",
    this.use = "",
    this.sDiscPercent = 0.0,
    this.reorderLevel = 10,
    this.maxLevel = 100,
    this.isControlled = false,
    this.isBanned = false,
    this.isNrx = false,
    this.isActive = true,
    this.isDiscLocked = false,
    this.preferredWholesale = "",
    this.leadTime = 2,
    this.alias = "",
  })  : name = cleanProductName(name),
        genericName = cleanProductName(genericName);

  Product clone() {
    return Product(
      id: id,
      name: name,
      batch: batch,
      rack: rack,
      hsnCode: hsnCode,
      expiry: expiry,
      packSize: packSize,
      mrp: mrp,
      salePrice: salePrice,
      purchaseRate: purchaseRate,
      landingCost: landingCost,
      taxableSP: taxableSP,
      stock: stock,
      gstPercent: gstPercent,
      category: category,
      subCategory: subCategory,
      manufacturer: manufacturer,
      supplier: supplier,
      patent: patent,
      schedule: schedule,
      genericName: genericName,
      use: use,
      sDiscPercent: sDiscPercent,
      reorderLevel: reorderLevel,
      maxLevel: maxLevel,
      isControlled: isControlled,
      isBanned: isBanned,
      isNrx: isNrx,
      isActive: isActive,
      isDiscLocked: isDiscLocked,
      preferredWholesale: preferredWholesale,
      leadTime: leadTime,
      alias: alias,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'batch': batch,
      'expiry': expiry,
      'packing': packSize,
      'mrp': mrp,
      'sale_price': salePrice,
      'purchase_rate': purchaseRate,
      'landing_cost': landingCost,
      'gst_percent': gstPercent,
      'rack_id': rack,
      'category_id': category,
      'manufacturer_id': manufacturer,
      'generic_name': genericName,
      'stock': stock,
      'preferred_wholesale': preferredWholesale,
      'supplier': supplier,
      'alias': alias,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id']?.toString() ?? "",
      name: map['name']?.toString() ?? "",
      batch: map['batch']?.toString() ?? map['batch_number']?.toString() ?? "",
      expiry: map['expiry']?.toString() ?? map['expiry_date']?.toString() ?? "",
      packSize: map['packing'] is int ? map['packing'] : (map['packing'] != null ? int.tryParse(map['packing'].toString()) ?? 1 : 1),
      mrp: (map['mrp'] ?? 0.0).toDouble(),
      salePrice: (map['sale_price'] ?? map['sale_rate'] ?? 0.0).toDouble(),
      purchaseRate: (map['purchase_rate'] ?? 0.0).toDouble(),
      landingCost: (map['landing_cost'] ?? 0.0).toDouble(),
      taxableSP: (map['taxable_sp'] ?? 0.0).toDouble(),
      stock: map['stock'] is int ? map['stock'] : (map['current_stock'] is int ? map['current_stock'] : (map['stock'] ?? map['current_stock'] ?? 0)),
      gstPercent: (map['gst_percent'] ?? 12.0).toDouble(),
      rack: map['rack_id']?.toString() ?? map['rack']?.toString() ?? "",
      category: map['category_id']?.toString() ?? map['category']?.toString() ?? "General",
      subCategory: map['sub_category_id']?.toString() ?? map['sub_category']?.toString() ?? "",
      manufacturer: map['manufacturer_id']?.toString() ?? map['manufacturer']?.toString() ?? "",
      supplier: map['supplier']?.toString() ?? map['supplier_name']?.toString() ?? "",
      patent: map['patent']?.toString() ?? "",
      schedule: map['schedule']?.toString() ?? "",
      genericName: map['generic_name']?.toString() ?? "",
      use: map['use']?.toString() ?? "",
      sDiscPercent: (map['s_disc_percent'] ?? 0.0).toDouble(),
      reorderLevel: map['reorder_level'] is int ? map['reorder_level'] : 10,
      maxLevel: map['max_level'] is int ? map['max_level'] : 100,
      isControlled: map['is_controlled'] == 1 || map['is_controlled'] == true,
      isBanned: map['is_banned'] == 1 || map['is_banned'] == true,
      isNrx: map['is_nrx'] == 1 || map['is_nrx'] == true,
      isActive: map['is_active'] == null ? true : (map['is_active'] == 1 || map['is_active'] == true),
      isDiscLocked: map['is_disc_locked'] == 1 || map['is_disc_locked'] == true,
      preferredWholesale: map['preferred_wholesale']?.toString() ?? "",
      leadTime: map['lead_time'] is int ? map['lead_time'] : 2,
      alias: map['alias']?.toString() ?? "",
    );
  }

  Map<String, dynamic> toMasterMap() {
    return {
      'id': id,
      'name': cleanProductName(name),
      'generic_name': cleanProductName(genericName),
      'manufacturer_id': manufacturer,
      'category_id': category,
      'sub_category_id': subCategory,
      'rack_id': rack,
      'hsn_code': hsnCode,
      'gst_percent': gstPercent,
      's_disc_percent': sDiscPercent,
      'schedule': schedule,
      'reorder_level': reorderLevel,
      'max_level': maxLevel,
      'packing': packSize,
      'mrp': mrp,
      'purchase_rate': purchaseRate,
      'sale_rate': salePrice,
      'patent': patent,
      'is_controlled': isControlled ? 1 : 0,
      'is_banned': isBanned ? 1 : 0,
      'is_nrx': isNrx ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'is_disc_locked': isDiscLocked ? 1 : 0,
      'preferred_wholesale': preferredWholesale,
      'lead_time': leadTime,
      'alias': alias,
    };
  }
}

class SaleItem {
  final String uuid;
  Product product;
  String extra;
  int qty;
  int looseQty;
  int fQty;
  int packin;
  double mrp;
  double taxableSP;
  double sRate;
  double discPercent;
  double discAmt;
  double gstPercent;
  double gstAmt;
  double cgstAmt;
  double sgstAmt;
  double igstAmt;
  double total;
  double profit;
  double purchaseRate;
  double landingCost;
  String supplier;

  int get mrpPaise => (mrp * 100).round();
  int get taxableSPPaise => (taxableSP * 100).round();
  int get sRatePaise => (sRate * 100).round();
  int get discAmtPaise => (discAmt * 100).round();
  int get gstAmtPaise => (gstAmt * 100).round();
  int get cgstAmtPaise => (cgstAmt * 100).round();
  int get sgstAmtPaise => (sgstAmt * 100).round();
  int get igstAmtPaise => (igstAmt * 100).round();
  int get totalPaise => (total * 100).round();
  int get profitPaise => (profit * 100).round();
  int get purchaseRatePaise => (purchaseRate * 100).round();
  int get landingCostPaise => (landingCost * 100).round();

  SaleItem({
    String? uuid,
    required this.product,
    this.extra = "",
    this.qty = 0,
    this.looseQty = 0,
    this.fQty = 0,
    this.packin = 1,
    this.mrp = 0.0,
    this.taxableSP = 0.0,
    this.sRate = 0.0,
    this.discPercent = 0.0,
    this.discAmt = 0.0,
    this.gstPercent = 0.0,
    this.gstAmt = 0.0,
    this.cgstAmt = 0.0,
    this.sgstAmt = 0.0,
    this.igstAmt = 0.0,
    this.total = 0.0,
    this.profit = 0.0,
    this.purchaseRate = 0.0,
    this.landingCost = 0.0,
    this.supplier = "",
  }) : uuid = uuid ?? DateTime.now().microsecondsSinceEpoch.toString();

  SaleItem clone() {
    return SaleItem(
      uuid: uuid,
      product: product.clone(),
      extra: extra,
      qty: qty,
      looseQty: looseQty,
      fQty: fQty,
      packin: packin,
      mrp: mrp,
      taxableSP: taxableSP,
      sRate: sRate,
      discPercent: discPercent,
      discAmt: discAmt,
      gstPercent: gstPercent,
      gstAmt: gstAmt,
      cgstAmt: cgstAmt,
      sgstAmt: sgstAmt,
      igstAmt: igstAmt,
      total: total,
      profit: profit,
      purchaseRate: purchaseRate,
      landingCost: landingCost,
      supplier: supplier,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uuid': uuid,
      'product': product.toMap(),
      'extra': extra,
      'qty': qty,
      'looseQty': looseQty,
      'fQty': fQty,
      'packin': packin,
      'mrp': mrp,
      'taxableSP': taxableSP,
      'sRate': sRate,
      'discPercent': discPercent,
      'discAmt': discAmt,
      'gstPercent': gstPercent,
      'gstAmt': gstAmt,
      'cgstAmt': cgstAmt,
      'sgstAmt': sgstAmt,
      'total': total,
      'profit': profit,
      'purchaseRate': purchaseRate,
      'landingCost': landingCost,
      'supplier': supplier,
    };
  }

  factory SaleItem.fromMap(Map<String, dynamic> map) {
    return SaleItem(
      uuid: map['uuid'],
      product: Product.fromMap(map['product']),
      extra: map['extra'] ?? "",
      qty: map['qty'] ?? 0,
      looseQty: map['looseQty'] ?? 0,
      fQty: map['fQty'] ?? 0,
      packin: map['packin'] ?? 1,
      mrp: (map['mrp'] ?? 0.0).toDouble(),
      taxableSP: (map['taxableSP'] ?? 0.0).toDouble(),
      sRate: (map['sRate'] ?? 0.0).toDouble(),
      discPercent: (map['discPercent'] ?? 0.0).toDouble(),
      discAmt: (map['discAmt'] ?? 0.0).toDouble(),
      gstPercent: (map['gstPercent'] ?? 0.0).toDouble(),
      gstAmt: (map['gstAmt'] ?? 0.0).toDouble(),
      cgstAmt: (map['cgstAmt'] ?? 0.0).toDouble(),
      sgstAmt: (map['sgstAmt'] ?? 0.0).toDouble(),
      total: (map['total'] ?? 0.0).toDouble(),
      profit: (map['profit'] ?? 0.0).toDouble(),
      purchaseRate: (map['purchaseRate'] ?? 0.0).toDouble(),
      landingCost: (map['landingCost'] ?? 0.0).toDouble(),
      supplier: map['supplier'] ?? "",
    );
  }
}

class SaleInvoice {
  final String entryNo;
  final DateTime date;
  final String customerAcc;
  final String patient;
  final String mobile;
  final String doctor;
  final String doctorRegNo;
  final String specialOrderJson;
  final String taxType;
  final int days;
  final List<SaleItem> items;
  final double subTotal;
  final double discountPercent;
  final double discount;
  final double additionalDiscount;
  final double otherCharge;
  final double rcvdAmt;
  final double roundOff;
  final double grandTotal;
  final String agent;
  final String expectingDate;
  final String specialCustomerName;
  final String specialCustomerPhone;
  final String paymentRemarks;
  final String secondaryAcc;
  final double secondaryAmt;
  final String financialYear;
  final double salesReturn;
  final bool isPaid;
  final bool isDeleted;
  final int orderType; // 0 = NORMAL, 1 = SPECIAL ORDER, 2 = ONE TIME ORDER

  int get subTotalPaise => (subTotal * 100).round();
  int get discountPaise => (discount * 100).round();
  int get additionalDiscountPaise => (additionalDiscount * 100).round();
  int get otherChargePaise => (otherCharge * 100).round();
  int get rcvdAmtPaise => (rcvdAmt * 100).round();
  int get roundOffPaise => (roundOff * 100).round();
  int get grandTotalPaise => (grandTotal * 100).round();
  int get salesReturnPaise => (salesReturn * 100).round();

  SaleInvoice({
    required this.entryNo,
    required this.date,
    required this.customerAcc,
    required this.patient,
    this.mobile = "",
    required this.doctor,
    this.doctorRegNo = "",
    this.specialOrderJson = "[]",
    this.taxType = "Non Gst",
    this.days = 0,
    required this.items,
    this.subTotal = 0.0,
    this.discountPercent = 0.0,
    this.discount = 0.0,
    this.additionalDiscount = 0.0,
    this.otherCharge = 0.0,
    this.rcvdAmt = 0.0,
    this.roundOff = 0.0,
    this.grandTotal = 0.0,
    this.agent = "Admin",
    this.expectingDate = "",
    this.specialCustomerName = "",
    this.specialCustomerPhone = "",
    this.paymentRemarks = "",
    this.secondaryAcc = "",
    this.secondaryAmt = 0.0,
    this.financialYear = "",
    this.salesReturn = 0.0,
    this.isPaid = true,
    this.isDeleted = false,
    this.orderType = 0,
  });
}

class PurchaseItem {
  String id;
  String productName;
  String externalName;
  String extra;
  String batch;
  String rack;
  String hsnCode;
  String expiry;
  String externalCode;
  int packin;
  int qty;
  int looseQty;
  int fQty;
  double mrp;
  double pRate;
  double gross;
  double discPercent;
  double discAmt;
  double net;
  double gstPercent;
  double gstAmt;
  double total;
  double sDiscPercent;
  double sDiscAmt;
  double cdPercent;
  double cdAmt;
  double sRate;
  double lCost;
  String unit;
  String reason;
  String supplier;
  String supInvNo;
  String patent;
  String genericName;
  String category;
  String subCategory;
  String manufacturer;

  int get mrpPaise => (mrp * 100).round();
  int get pRatePaise => (pRate * 100).round();
  int get grossPaise => (gross * 100).round();
  int get discAmtPaise => (discAmt * 100).round();
  int get netPaise => (net * 100).round();
  int get gstAmtPaise => (gstAmt * 100).round();
  int get totalPaise => (total * 100).round();
  int get sDiscAmtPaise => (sDiscAmt * 100).round();
  int get cdAmtPaise => (cdAmt * 100).round();
  int get sRatePaise => (sRate * 100).round();
  int get lCostPaise => (lCost * 100).round();

  PurchaseItem({
    this.id = "",
    this.productName = "",
    this.externalName = "",
    this.extra = "",
    this.batch = "",
    this.rack = "",
    this.hsnCode = "",
    this.expiry = "",
    this.externalCode = "",
    this.packin = 1,
    this.qty = 0,
    this.looseQty = 0,
    this.fQty = 0,
    this.mrp = 0.0,
    this.pRate = 0.0,
    this.gross = 0.0,
    this.discPercent = 0.0,
    this.discAmt = 0.0,
    this.net = 0.0,
    this.gstPercent = 0.0,
    this.gstAmt = 0.0,
    this.total = 0.0,
    this.sDiscPercent = 0.0,
    this.sDiscAmt = 0.0,
    this.cdPercent = 0.0,
    this.cdAmt = 0.0,
    this.sRate = 0.0,
    this.lCost = 0.0,
    this.unit = "BULK",
    this.reason = "",
    this.supplier = "",
    this.supInvNo = "",
    this.patent = "",
    this.genericName = "",
    this.category = "",
    this.subCategory = "",
    this.manufacturer = "",
  });
}

class PurchaseEntry {
  final String entryNo;
  final DateTime date;
  final String supplierName;
  final String supInvNo;
  final DateTime supInvDate;
  final String doneBy;
  final double invTotal;
  final String remarks;
  final int days;
  final List<PurchaseItem> items;
  final double subTotal;
  final double discount;
  final double otherCharge;
  final double roundOff;
  final double grandTotal;
  final String financialYear;
  final bool isDeleted;
  int paymentStatus;
  String? paymentMode;
  String? paymentRemarks;
  DateTime? paymentDate;
  double paidAmount;

  int get invTotalPaise => (invTotal * 100).round();
  int get subTotalPaise => (subTotal * 100).round();
  int get discountPaise => (discount * 100).round();
  int get otherChargePaise => (otherCharge * 100).round();
  int get roundOffPaise => (roundOff * 100).round();
  int get grandTotalPaise => (grandTotal * 100).round();
  int get paidAmountPaise => (paidAmount * 100).round();

  PurchaseEntry({
    required this.entryNo,
    required this.date,
    required this.supplierName,
    required this.supInvNo,
    required this.supInvDate,
    this.doneBy = "",
    this.invTotal = 0.0,
    this.remarks = "",
    this.days = 0,
    required this.items,
    this.subTotal = 0.0,
    this.discount = 0.0,
    this.otherCharge = 0.0,
    this.roundOff = 0.0,
    this.grandTotal = 0.0,
    this.financialYear = "",
    this.isDeleted = false,
    this.paymentStatus = 0,
    this.paymentMode,
    this.paymentRemarks,
    this.paymentDate,
    this.paidAmount = 0.0,
  });
}

class ImportMapping {
  String name;
  Map<String, List<String>> fieldMappings;

  ImportMapping({required this.name, required this.fieldMappings});

  Map<String, dynamic> toJson() => {
    'name': name,
    'fieldMappings': fieldMappings,
  };

  factory ImportMapping.fromJson(Map<String, dynamic> json) => ImportMapping(
    name: json['name'],
    fieldMappings: Map<String, List<String>>.from(json['fieldMappings'].map((k, v) => MapEntry(k, List<String>.from(v)))),
  );

  static ImportMapping defaultMapping() => ImportMapping(
    name: "Default",
    fieldMappings: {
      'Product Code': ['c2code', 'itemcode', 'code', 'productcode', 'pcode', 'item_code', 'prod_code'],
      'HSN': ['hsn', 'hsn code', 'hsn_code', 'hsncode'],
      'Product': ['product', 'item', 'name', 'particulars', 'itemname', 'pname', 'product name', 'item name', 'description', 'desc'],
      'Batch': ['batch', 'batchno', 'batch no', 'batch no.', 'batch_no', 'batch_number'],
      'Exp': ['exp', 'expiry', 'expdate', 'exp. date', 'exp_date', 'expiry_date', 'expyear', 'expmonth'],
      'Qty': ['qty', 'quantity', 'invqty', 'inv_qty', 'billing_qty', 'billed_qty', 'qty_billed'],
      'Fqty': ['fqty', 'free', 'f.qty', 'f_qty', 'free qty', 'free_quantity', 'invscqty', 'scqty', 'sch_qty'],
      'Prate': ['prate', 'p.rate', 'p_rate', 'purchase rate', 'rate', 'cost', 'ptr', 'pur_rate', 'salerate', 'sale_rate', 'sal_rate', 'srate', 'netrate', 'net_rate', 'traderate', 'trade_rate', 'costrate', 'cost_rate', 'p_price', 'purprice', 'pprice', 'buy_rate', 'buyrate'],
      'Mrp': ['itemmrp', 'vatmrp', 'mrp', 'm.r.p.', 'm.r.p', 'item_mrp', 'max_retail_price', 'max retail price', 'mrp_val', 'mrpval', 'retail_mrp', 'retailmrp', 'retail_price', 'retailprice', 'salemrp', 'sale_mrp', 'mrp_rate', 'mrprate', 'mrp_amount', 'mrpamt'],
      'TaxPer (Total)': ['taxper', 'gst', 'gst%', 'tax%', 'tax percent', 'tax_rate', 'gst_rate', 'vatper', 'tsper'],
      'CGST': ['cgst', 'cgst%', 'cgstper', 'cgst_per'],
      'SGST': ['sgst', 'sgst%', 'sgstper', 'sgst_per'],
      'Sdisc': ['sdisc', 'special discount', 'scheme discount', 's_disc', 's.disc', 'invscdis'],
      'Packing': ['packing', 'pack', 'packin', 'unit', 'pack_size', 'packing_size'],
      'DisPer': ['disper', 'disc%', 'discount%', 'invdisc', 'disc. %', 'trade_disc', 'disc_percent', 'schper', 'sch_per', 'scheme_disc'],
      'DisAmt': ['disamt', 'disc amt', 'discount amt', 'disc amount', 'discount value', 'disc val', 'disc', 'discount'],
    },
  );
}

class ProductMapping {
  final int? id;
  final String wholesalerName;
  final String externalCode;
  final String externalName;
  final String internalName;
  final String productId;

  ProductMapping({
    this.id,
    required this.wholesalerName,
    this.externalCode = "",
    required this.externalName,
    required this.internalName,
    required this.productId,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'wholesaler_name': wholesalerName,
    'external_code': externalCode,
    'external_name': externalName,
    'internal_name': internalName,
    'product_id': productId,
  };

  factory ProductMapping.fromMap(Map<String, dynamic> map) => ProductMapping(
    id: map['id'],
    wholesalerName: map['wholesaler_name'],
    externalCode: map['external_code'] ?? "",
    externalName: map['external_name'],
    internalName: map['internal_name'] ?? "",
    productId: map['product_id'],
  );
}

class SaleReturnInvoice {
  final String entryNo;
  final DateTime date;
  final String customerAcc;
  final String patient;
  final String doctor;
  final String originalInvoiceNo;
  final List<SaleItem> items;
  final double subTotal;
  final double discount;
  final double roundOff;
  final double grandTotal;
  final String narration;
  final int gstMode;
  final String financialYear;
  final bool isDeleted;

  SaleReturnInvoice({
    required this.entryNo,
    required this.date,
    required this.customerAcc,
    required this.patient,
    required this.doctor,
    required this.originalInvoiceNo,
    required this.items,
    this.subTotal = 0.0,
    this.discount = 0.0,
    this.roundOff = 0.0,
    this.grandTotal = 0.0,
    this.narration = "",
    this.gstMode = 1,
    this.financialYear = "",
    this.isDeleted = false,
  });
}

class PurchaseReturnEntry {
  final String entryNo;
  final DateTime date;
  final String supplierName;
  final String originalPurchaseNo;
  final String doneBy;
  final int gstMode;
  final List<PurchaseItem> items;
  final double grandTotal;
  final String financialYear;

  PurchaseReturnEntry({
    required this.entryNo,
    required this.date,
    required this.supplierName,
    this.originalPurchaseNo = "",
    this.doneBy = "",
    this.gstMode = 1,
    required this.items,
    this.grandTotal = 0.0,
    this.financialYear = "",
  });
}

class Supplier {
  final String id;
  String name;
  String address;
  String phone;
  String gstIn;
  String dlNumber;
  double currentBalance;

  Supplier({
    required this.id,
    required this.name,
    this.address = "",
    this.phone = "",
    this.gstIn = "",
    this.dlNumber = "",
    this.currentBalance = 0.0,
  });
}

class Patient {
  final String id;
  String name;
  String mobile;
  String address;
  String email;
  bool isActive;
  double currentBalance;

  Patient({
    required this.id,
    required this.name,
    this.mobile = "",
    this.address = "",
    this.email = "",
    this.isActive = true,
    this.currentBalance = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'mobile': mobile,
      'address': address,
      'email': email,
      'is_active': isActive ? 1 : 0,
      'current_balance': currentBalance,
    };
  }

  factory Patient.fromMap(Map<String, dynamic> map) {
    return Patient(
      id: map['id'],
      name: map['name'],
      mobile: map['mobile'] ?? "",
      address: map['address'] ?? "",
      email: map['email'] ?? "",
      isActive: map['is_active'] == 1,
      currentBalance: (map['current_balance'] ?? 0.0).toDouble(),
    );
  }
}

class Doctor {
  final String id;
  String name;
  String mobile;
  String specialization;
  String regNo;
  bool isActive;

  Doctor({
    required this.id,
    required this.name,
    this.mobile = "",
    this.specialization = "",
    this.regNo = "",
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'mobile': mobile,
      'specialization': specialization,
      'reg_no': regNo,
      'is_active': isActive ? 1 : 0,
    };
  }

  factory Doctor.fromMap(Map<String, dynamic> map) {
    return Doctor(
      id: map['id'],
      name: map['name'],
      mobile: map['mobile'] ?? "",
      specialization: map['specialization'] ?? "",
      regNo: map['reg_no'] ?? "",
      isActive: map['is_active'] == null ? true : map['is_active'] == 1,
    );
  }
}

class SupplierPayment {
  final String id;
  final String supplierName;
  final DateTime date;
  final double amount;
  final String invoiceNo;
  final String paymentMethod;
  final String remarks;

  SupplierPayment({
    required this.id,
    required this.supplierName,
    required this.date,
    required this.amount,
    this.invoiceNo = "",
    this.paymentMethod = "CASH",
    this.remarks = "",
  });
}

class SupplierCreditNote {
  final String id;
  final String supplierName;
  final DateTime date;
  final double amount;
  final String invoiceNo;
  final String remarks;

  SupplierCreditNote({
    required this.id,
    required this.supplierName,
    required this.date,
    required this.amount,
    this.invoiceNo = "",
    this.remarks = "",
  });
}

class Generic {
  final String id;
  String name;
  String use;
  bool isActive;

  Generic({
    required this.id,
    required this.name,
    this.use = "",
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'use': use,
      'is_active': isActive ? 1 : 0,
    };
  }

  factory Generic.fromMap(Map<String, dynamic> map) {
    return Generic(
      id: map['id'],
      name: map['name'],
      use: map['use'] ?? "",
      isActive: map['is_active'] == null ? true : map['is_active'] == 1,
    );
  }
}

class PurchaseReturnItem {
  final String uuid;
  Product product;
  String hsncode = "";
  String supplier = "";
  String supInvNo = "";
  String supInvDate = "";
  int qty = 0;
  int looseQty = 0;
  int fQty = 0;
  String unit = "BULK";
  int packin = 1;
  double mrp = 0.0;
  double pRate = 0.0;
  double sRate = 0.0;
  double gross = 0.0;
  double discPercent = 0.0;
  double discAmt = 0.0;
  double net = 0.0;
  double gstPercent = 0.0;
  double gstAmt = 0.0;
  double total = 0.0;
  String reason = "";

  PurchaseReturnItem({String? uuid, required this.product}) : uuid = uuid ?? DateTime.now().microsecondsSinceEpoch.toString();

  PurchaseReturnItem clone() {
    return PurchaseReturnItem(uuid: uuid, product: product.clone())
      ..hsncode = hsncode
      ..supplier = supplier
      ..supInvNo = supInvNo
      ..supInvDate = supInvDate
      ..qty = qty
      ..looseQty = looseQty
      ..fQty = fQty
      ..unit = unit
      ..packin = packin
      ..mrp = mrp
      ..pRate = pRate
      ..sRate = sRate
      ..gross = gross
      ..discPercent = discPercent
      ..discAmt = discAmt
      ..net = net
      ..gstPercent = gstPercent
      ..gstAmt = gstAmt
      ..total = total
      ..reason = reason;
  }
}

class Prescription {
  final String id;
  int prescriptionNo;
  String patientName;
  String doctorName;
  String diseaseName;
  String mobile;
  int days;
  DateTime date;
  String saleEntryNo;
  bool isActive;
  bool isImported;
  String financialYear;
  List<PrescriptionItem> items;

  Prescription({
    required this.id,
    this.prescriptionNo = 0,
    required this.patientName,
    this.doctorName = "",
    this.diseaseName = "",
    this.mobile = "",
    required this.days,
    required this.date,
    this.saleEntryNo = "",
    this.isActive = true,
    this.isImported = false,
    this.financialYear = "",
    this.items = const [],
  });
}

class PrescriptionItem {
  String name;
  double qty;

  PrescriptionItem({required this.name, this.qty = 0});
}

class StockAdjustment {
  final String entryNo;
  final DateTime date;
  final String doneBy;
  final String reason;
  final List<StockAdjustmentItem> items;
  final double grandTotal;
  final String financialYear;

  StockAdjustment({
    required this.entryNo,
    required this.date,
    this.doneBy = "",
    this.reason = "",
    required this.items,
    this.grandTotal = 0.0,
    this.financialYear = "",
  });
}

class StockAdjustmentItem {
  final Product product;
  final int qty;
  final double purchaseRate;
  final double total;

  StockAdjustmentItem({
    required this.product,
    required this.qty,
    required this.purchaseRate,
    required this.total,
  });
}

class StockWriteOff {
  final String id;
  final DateTime date;
  final Product product;
  final int quantity;
  final String reason;
  final double lossValue;
  final String financialYear;

  StockWriteOff({
    required this.id,
    required this.date,
    required this.product,
    required this.quantity,
    required this.reason,
    required this.lossValue,
    this.financialYear = "",
  });
}

class StockLedgerItem {
  final String productName;
  final String patent;
  final int packin;
  final String batch;
  final String hsnCode;
  final double gst;
  final double mrp;
  final String supplier;
  final double lCost;

  int openingStock;
  int purchase;
  int damage;
  int saleReturn;
  int sales;
  int b2bSales;
  int purchaseReturn;
  int adjustment;
  int closingStock;

  StockLedgerItem({
    required this.productName,
    this.patent = "",
    this.packin = 1,
    this.batch = "",
    this.hsnCode = "",
    this.gst = 0.0,
    this.mrp = 0.0,
    this.supplier = "",
    this.lCost = 0.0,
    this.openingStock = 0,
    this.purchase = 0,
    this.damage = 0,
    this.saleReturn = 0,
    this.sales = 0,
    this.b2bSales = 0,
    this.purchaseReturn = 0,
    this.adjustment = 0,
    this.closingStock = 0,
  });

  double get mrpValue {
    double ps = packin == 0 ? 1 : packin.toDouble();
    return closingStock * (mrp / ps);
  }

  double get lCostValue {
    double ps = packin == 0 ? 1 : packin.toDouble();
    return closingStock * (lCost / ps);
  }
}

class ConsolidatedStockItem {
  final String productId;
  final String productName;
  final String genericName;
  final String category;
  final String rack;
  final int packSize;
  final double purchaseRate;
  final double mrp;
  final int openingStock;
  final int inwardQty;
  final int outwardQty;
  final int closingStock;
  final int liveStock;

  ConsolidatedStockItem({
    required this.productId,
    required this.productName,
    this.genericName = '',
    this.category = '',
    this.rack = '',
    this.packSize = 1,
    this.purchaseRate = 0.0,
    this.mrp = 0.0,
    this.openingStock = 0,
    this.inwardQty = 0,
    this.outwardQty = 0,
    this.closingStock = 0,
    this.liveStock = 0,
  });

  double get purchaseValuation => (closingStock / (packSize > 0 ? packSize : 1)) * purchaseRate;
  double get mrpValuation => (closingStock / (packSize > 0 ? packSize : 1)) * mrp;
}

class Account {
  final String id;
  String name;
  String type; // e.g., Cash, Bank, UPI
  double balance;
  bool isActive;
  String color; // Hex string, e.g., '0xFF4CAF50'

  Account({
    required this.id,
    required this.name,
    this.type = "Cash",
    this.balance = 0.0,
    this.isActive = true,
    this.color = '0xFF94A3B8', // Default Slate
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'balance': balance,
      'is_active': isActive ? 1 : 0,
      'color': color,
    };
  }

  factory Account.fromMap(Map<String, dynamic> map) {
    return Account(
      id: map['id'],
      name: map['name'],
      type: map['type'] ?? "Cash",
      balance: (map['balance'] ?? 0.0).toDouble(),
      isActive: map['is_active'] == 1,
      color: map['color'] ?? '0xFF94A3B8',
    );
  }
}

class OrderConfirmationItem {
  final int? id;
  final String orderId;
  final String productId;
  String productName;
  String company;
  int orderQty;
  int receivedQty;
  double unitPrice;
  int packSize;
  String status; // 'PENDING', 'RECEIVED', 'PARTIAL'
  String? receivedDate;

  OrderConfirmationItem({
    this.id,
    required this.orderId,
    this.productId = "",
    required this.productName,
    this.company = "",
    this.orderQty = 0,
    this.receivedQty = 0,
    this.unitPrice = 0.0,
    this.packSize = 1,
    this.status = 'PENDING',
    this.receivedDate,
  });

  double get totalPrice => orderQty * unitPrice;

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'order_id': orderId,
    'product_id': productId,
    'product_name': productName,
    'company': company,
    'order_qty': orderQty,
    'received_qty': receivedQty,
    'unit_price': unitPrice,
    'pack_size': packSize,
    'status': status,
    'received_date': receivedDate,
  };

  factory OrderConfirmationItem.fromMap(Map<String, dynamic> map) => OrderConfirmationItem(
    id: map['id'],
    orderId: map['order_id'] ?? "",
    productId: map['product_id'] ?? "",
    productName: map['product_name'] ?? "",
    company: map['company'] ?? "",
    orderQty: (map['order_qty'] as num?)?.toInt() ?? 0,
    receivedQty: (map['received_qty'] as num?)?.toInt() ?? 0,
    unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0.0,
    packSize: (map['pack_size'] as num?)?.toInt() ?? 1,
    status: map['status'] ?? 'PENDING',
    receivedDate: map['received_date'],
  );
}

class OrderConfirmation {
  final String orderId;
  final DateTime orderDate;
  final String supplierName;
  final int totalItems;
  final double totalAmount;
  String status; // 'PENDING', 'RECEIVED', 'PARTIAL', 'CANCELLED'
  String? expectedDeliveryDate;
  String? receivedDate;
  String notes;
  final DateTime createdAt;
  List<OrderConfirmationItem> items;

  OrderConfirmation({
    required this.orderId,
    required this.orderDate,
    required this.supplierName,
    this.totalItems = 0,
    this.totalAmount = 0.0,
    this.status = 'PENDING',
    this.expectedDeliveryDate,
    this.receivedDate,
    this.notes = "",
    required this.createdAt,
    this.items = const [],
  });

  Map<String, dynamic> toMap() => {
    'order_id': orderId,
    'order_date': orderDate.toIso8601String(),
    'supplier_name': supplierName,
    'total_items': totalItems,
    'total_amount': totalAmount,
    'status': status,
    'expected_delivery_date': expectedDeliveryDate,
    'received_date': receivedDate,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
  };

  factory OrderConfirmation.fromMap(Map<String, dynamic> map, {List<OrderConfirmationItem> items = const []}) {
    return OrderConfirmation(
      orderId: map['order_id'] ?? "",
      orderDate: DateTime.tryParse(map['order_date'] ?? "") ?? DateTime.now(),
      supplierName: map['supplier_name'] ?? "",
      totalItems: (map['total_items'] as num?)?.toInt() ?? 0,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0.0,
      status: map['status'] ?? 'PENDING',
      expectedDeliveryDate: map['expected_delivery_date'],
      receivedDate: map['received_date'],
      notes: map['notes'] ?? "",
      createdAt: DateTime.tryParse(map['created_at'] ?? "") ?? DateTime.now(),
      items: items,
    );
  }
}

class Staff {
  final String id;
  String name;
  String phone;
  String role;
  String code;
  bool isActive;

  Staff({
    required this.id,
    required this.name,
    this.phone = "",
    this.role = "Sales Agent",
    this.code = "",
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'role': role,
      'code': code,
      'is_active': isActive ? 1 : 0,
    };
  }

  factory Staff.fromMap(Map<String, dynamic> map) {
    return Staff(
      id: map['id']?.toString() ?? "",
      name: map['name']?.toString() ?? "",
      phone: map['phone']?.toString() ?? "",
      role: map['role']?.toString() ?? "Sales Agent",
      code: map['code']?.toString() ?? "",
      isActive: map['is_active'] == null ? true : map['is_active'] == 1,
    );
  }
}