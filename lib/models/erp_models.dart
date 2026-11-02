
enum PaymentMode { cash, card, upi, bank, split }
enum StockAdjustmentReason { damage, expiry, returnToSupplier, initialStock, correction }
enum BillType { credit, cash }
enum GstType { local, central, free }

extension NumPrecisionExtension on num {
  double get asCurrency => double.parse(toStringAsFixed(2));
}

/// Helper to safely extract double from JSON map across single/multiple keys
double _dbl(Map<String, dynamic> m, List<String> keys, [double def = 0.0]) {
  for (final k in keys) {
    final v = m[k];
    if (v == null) continue;
    if (v is num) return v.toDouble();
    if (v is String) {
      final parsed = double.tryParse(v);
      if (parsed != null) return parsed;
    }
  }
  return def;
}

/// Helper to safely extract int from JSON map across single/multiple keys
int _integer(Map<String, dynamic> m, List<String> keys, [int def = 0]) {
  for (final k in keys) {
    final v = m[k];
    if (v == null) continue;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final parsed = int.tryParse(v);
      if (parsed != null) return parsed;
    }
  }
  return def;
}

class CompanyProfile {
  String name;
  String address;
  String phone;
  String email;
  String gstIn;
  String dlNumber;
  String tagline;
  String upiVpaId;
  String upiPayeeName;

  CompanyProfile({
    this.name = "SAHAKAR MEDICALS & SURGICALS",
    this.address = "KALPETTA TOWN, WAYANAD",
    this.phone = "+91 0000000000",
    this.email = "sahakar@gmail.com",
    this.gstIn = "32AAAAA0000A1Z5",
    this.dlNumber = "DL/123/2024",
    this.tagline = "Professional Pharmacy Care",
    this.upiVpaId = "sahakarmedicals@upi",
    this.upiPayeeName = "Sahakar Medicals",
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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'generic_name': genericName,
      'manufacturer_id': manufacturerId,
      'category_id': categoryId,
      'rack_id': rackId,
      'hsn_code': hsnCode,
      'gst_percent': gstPercent,
      'schedule': schedule,
      'reorder_level': reorderLevel,
      'max_level': maxLevel,
      'unit': unit,
      'packing': packing,
      'barcode': barcode,
      'is_controlled': isControlled ? 1 : 0,
      'is_banned': isBanned ? 1 : 0,
      'is_nrx': isNrx ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'preferred_wholesale': preferredWholesale,
      'lead_time': leadTime,
    };
  }

  Map<String, dynamic> toJson() => toMap();

  factory ProductMaster.fromMap(Map<String, dynamic> map) {
    return ProductMaster(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? map['product_name']?.toString() ?? '',
      genericName: map['generic_name']?.toString() ?? map['genericName']?.toString() ?? '',
      manufacturerId: map['manufacturer_id']?.toString() ?? map['manufacturerId']?.toString() ?? '',
      categoryId: map['category_id']?.toString() ?? map['categoryId']?.toString() ?? '',
      rackId: map['rack_id']?.toString() ?? map['rackId']?.toString() ?? '',
      hsnCode: map['hsn_code']?.toString() ?? map['hsnCode']?.toString() ?? '',
      gstPercent: _dbl(map, ['gst_percent', 'gstPercent'], 12.0),
      schedule: map['schedule']?.toString() ?? 'H',
      reorderLevel: _integer(map, ['reorder_level', 'reorderLevel'], 10),
      maxLevel: _integer(map, ['max_level', 'maxLevel'], 100),
      unit: map['unit']?.toString() ?? 'Strip',
      packing: _integer(map, ['packing', 'packSize'], 10),
      barcode: map['barcode']?.toString() ?? '',
      isControlled: map['is_controlled'] == 1 || map['is_controlled'] == true || map['isControlled'] == true,
      isBanned: map['is_banned'] == 1 || map['is_banned'] == true || map['isBanned'] == true,
      isNrx: map['is_nrx'] == 1 || map['is_nrx'] == true || map['isNrx'] == true,
      isActive: map['is_active'] == null || map['is_active'] == 1 || map['is_active'] == true || map['isActive'] == true,
      preferredWholesale: map['preferred_wholesale']?.toString() ?? map['preferredWholesale']?.toString() ?? '',
      leadTime: _integer(map, ['lead_time', 'leadTime'], 2),
    );
  }

  factory ProductMaster.fromJson(Map<String, dynamic> json) => ProductMaster.fromMap(json);
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

  Map<String, dynamic> toMap() {
    return {
      'product_id': productId,
      'batch_number': batchNumber,
      'expiry_date': expiryDate.toIso8601String(),
      'mfg_date': mfgDate.toIso8601String(),
      'current_stock': currentStock,
      'purchase_rate': purchaseRate,
      'landing_cost': landingCost,
      'mrp': mrp,
      'sale_rate': saleRate,
      'wholesale_rate': wholesaleRate,
      'packing': packing,
      'supplier_name': supplierName,
      'gst_percent': gstPercent,
    };
  }

  Map<String, dynamic> toJson() => toMap();

  factory StockBatch.fromMap(Map<String, dynamic> map) {
    return StockBatch(
      productId: map['product_id']?.toString() ?? map['productId']?.toString() ?? '',
      batchNumber: map['batch_number']?.toString() ?? map['batchNumber']?.toString() ?? map['batch']?.toString() ?? '',
      expiryDate: DateTime.tryParse(map['expiry_date']?.toString() ?? map['expiryDate']?.toString() ?? map['expiry']?.toString() ?? '') ?? DateTime.now(),
      mfgDate: DateTime.tryParse(map['mfg_date']?.toString() ?? map['mfgDate']?.toString() ?? '') ?? DateTime.now(),
      currentStock: _integer(map, ['current_stock', 'currentStock', 'current_quantity', 'stock']),
      purchaseRate: _dbl(map, ['purchase_rate', 'purchaseRate']),
      landingCost: _dbl(map, ['landing_cost', 'landingCost']),
      mrp: _dbl(map, ['mrp']),
      saleRate: _dbl(map, ['sale_rate', 'saleRate', 'selling_rate']),
      wholesaleRate: _dbl(map, ['wholesale_rate', 'wholesaleRate']),
      packing: _integer(map, ['packing'], 1),
      supplierName: map['supplier_name']?.toString() ?? map['supplierName']?.toString() ?? '',
      gstPercent: _dbl(map, ['gst_percent', 'gstPercent'], 12.0),
    );
  }

  factory StockBatch.fromJson(Map<String, dynamic> json) => StockBatch.fromMap(json);
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

  double get pRate => purchaseRate;
  set pRate(double val) => purchaseRate = val;
  double get sRate => salePrice;
  set sRate(double val) => salePrice = val;

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
  String? lastMovedDate;

  late final String nameLower = name.trim().toLowerCase();
  late final String aliasLower = alias.trim().toLowerCase();
  late final String idLower = id.trim().toLowerCase();
  late final String hsnLower = hsnCode.trim().toLowerCase();
  late final String genericLower = genericName.trim().toLowerCase();

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
    double salePrice = 0.0,
    double purchaseRate = 0.0,
    double? pRate,
    double? sRate,
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
    this.lastMovedDate,
  })  : salePrice = sRate ?? salePrice,
        purchaseRate = pRate ?? purchaseRate,
        name = cleanProductName(name),
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
      lastMovedDate: lastMovedDate,
    );
  }

  Product copyWith({
    String? id,
    String? name,
    String? batch,
    String? rack,
    String? hsnCode,
    String? expiry,
    int? packSize,
    double? mrp,
    double? salePrice,
    double? purchaseRate,
    double? landingCost,
    double? taxableSP,
    int? stock,
    double? gstPercent,
    String? category,
    String? subCategory,
    String? manufacturer,
    String? supplier,
    String? patent,
    String? schedule,
    String? genericName,
    String? use,
    double? sDiscPercent,
    int? reorderLevel,
    int? maxLevel,
    bool? isControlled,
    bool? isBanned,
    bool? isNrx,
    bool? isActive,
    bool? isDiscLocked,
    String? preferredWholesale,
    int? leadTime,
    String? alias,
    String? lastMovedDate,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      batch: batch ?? this.batch,
      rack: rack ?? this.rack,
      hsnCode: hsnCode ?? this.hsnCode,
      expiry: expiry ?? this.expiry,
      packSize: packSize ?? this.packSize,
      mrp: mrp ?? this.mrp,
      salePrice: salePrice ?? this.salePrice,
      purchaseRate: purchaseRate ?? this.purchaseRate,
      landingCost: landingCost ?? this.landingCost,
      taxableSP: taxableSP ?? this.taxableSP,
      stock: stock ?? this.stock,
      gstPercent: gstPercent ?? this.gstPercent,
      category: category ?? this.category,
      subCategory: subCategory ?? this.subCategory,
      manufacturer: manufacturer ?? this.manufacturer,
      supplier: supplier ?? this.supplier,
      patent: patent ?? this.patent,
      schedule: schedule ?? this.schedule,
      genericName: genericName ?? this.genericName,
      use: use ?? this.use,
      sDiscPercent: sDiscPercent ?? this.sDiscPercent,
      reorderLevel: reorderLevel ?? this.reorderLevel,
      maxLevel: maxLevel ?? this.maxLevel,
      isControlled: isControlled ?? this.isControlled,
      isBanned: isBanned ?? this.isBanned,
      isNrx: isNrx ?? this.isNrx,
      isActive: isActive ?? this.isActive,
      isDiscLocked: isDiscLocked ?? this.isDiscLocked,
      preferredWholesale: preferredWholesale ?? this.preferredWholesale,
      leadTime: leadTime ?? this.leadTime,
      alias: alias ?? this.alias,
      lastMovedDate: lastMovedDate ?? this.lastMovedDate,
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
      id: map['id']?.toString() ?? map['product_id']?.toString() ?? "",
      name: map['name']?.toString() ?? map['product_name']?.toString() ?? map['item_name']?.toString() ?? "",
      batch: map['batch']?.toString() ?? map['batch_number']?.toString() ?? "",
      expiry: map['expiry']?.toString() ?? map['expiry_date']?.toString() ?? "",
      packSize: map['packing'] is int
          ? map['packing']
          : (map['packing'] != null
              ? int.tryParse(map['packing'].toString()) ?? (map['packin'] is int ? map['packin'] : 1)
              : (map['packin'] is int ? map['packin'] : (int.tryParse(map['packin']?.toString() ?? '') ?? 1))),
      mrp: _dbl(map, ['mrp']),
      salePrice: _dbl(map, ['sale_price', 'sale_rate', 's_rate', 'sRate']),
      purchaseRate: _dbl(map, ['purchase_rate', 'purchaseRate', 'p_rate']),
      landingCost: _dbl(map, ['landing_cost', 'landingCost']),
      taxableSP: _dbl(map, ['taxable_sp', 'taxableSP']),
      stock: map['stock'] is int ? map['stock'] : (map['current_stock'] is int ? map['current_stock'] : (map['stock'] ?? map['current_stock'] ?? 0)),
      gstPercent: _dbl(map, ['gst_percent', 'gstPercent', 'tax_percent'], 12.0),
      rack: map['rack_id']?.toString() ?? map['rack']?.toString() ?? "",
      category: map['category_id']?.toString() ?? map['category']?.toString() ?? "General",
      subCategory: map['sub_category_id']?.toString() ?? map['sub_category']?.toString() ?? "",
      manufacturer: map['manufacturer_id']?.toString() ?? map['manufacturer']?.toString() ?? "",
      supplier: map['supplier']?.toString() ?? map['supplier_name']?.toString() ?? "",
      patent: map['patent']?.toString() ?? "",
      schedule: map['schedule']?.toString() ?? "",
      genericName: map['generic_name']?.toString() ?? "",
      use: map['use']?.toString() ?? "",
      sDiscPercent: _dbl(map, ['s_disc_percent', 'disc_percent']),
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
      'is_synced': 0,
      'updated_at': DateTime.now().toIso8601String(),
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
  double? dailyDosage;
  double? originalExportQty;

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
    this.dailyDosage,
    this.originalExportQty,
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
      dailyDosage: dailyDosage,
      originalExportQty: originalExportQty,
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

  Map<String, dynamic> toSqlMap() {
    return {
      'product_id': product.id,
      'product_name': product.name,
      'extra': extra,
      'batch_number': product.batch,
      'expiry_date': product.expiry,
      'qty': qty,
      'quantity': qty,
      'packin': packin > 0 ? packin : product.packSize,
      'packing': packin > 0 ? packin : product.packSize,
      'mrp': mrp,
      'purchase_rate': purchaseRate,
      'landing_cost': landingCost > 0 ? landingCost : purchaseRate,
      's_rate': sRate,
      'sale_rate': sRate,
      'disc_percent': discPercent,
      'disc_amt': discAmt,
      'gst_percent': gstPercent,
      'gst_amt': gstAmt,
      'cgst_amt': cgstAmt,
      'sgst_amt': sgstAmt,
      'igst_amt': igstAmt,
      'total': total,
      'profit': profit,
      'supplier_name': supplier,
      'rack': product.rack,
    };
  }

  factory SaleItem.fromMap(Map<String, dynamic> map) {
    Product resolvedProduct;
    if (map['product'] is Map) {
      resolvedProduct = Product.fromMap(Map<String, dynamic>.from(map['product'] as Map));
    } else {
      resolvedProduct = Product(
        id: map['product_id']?.toString() ?? '',
        name: map['product_name']?.toString() ?? 'Unknown',
        batch: map['batch_number']?.toString() ?? map['batch']?.toString() ?? '',
        expiry: map['expiry_date']?.toString() ?? map['expiry']?.toString() ?? '',
        packSize: _integer(map, ['packing', 'packin'], 1),
        mrp: _dbl(map, ['mrp']),
        salePrice: _dbl(map, ['s_rate', 'unit_price']),
        purchaseRate: _dbl(map, ['purchase_rate', 'p_rate']),
        landingCost: _dbl(map, ['landing_cost', 'l_cost']),
        gstPercent: _dbl(map, ['gst_percent', 'tax_percent'], 12.0),
        supplier: map['supplier_name']?.toString() ?? map['supplier']?.toString() ?? '',
        rack: map['rack']?.toString() ?? '',
      );
    }

    return SaleItem(
      uuid: map['uuid']?.toString(),
      product: resolvedProduct,
      extra: map['extra']?.toString() ?? "",
      qty: _integer(map, ['qty', 'quantity']),
      looseQty: _integer(map, ['looseQty']),
      fQty: _integer(map, ['fQty', 'f_qty']),
      packin: _integer(map, ['packin', 'packing'], 1),
      mrp: _dbl(map, ['mrp']),
      taxableSP: _dbl(map, ['taxableSP', 'taxable_sp']),
      sRate: _dbl(map, ['sRate', 's_rate', 'unit_price']),
      discPercent: _dbl(map, ['discPercent', 'disc_percent']),
      discAmt: _dbl(map, ['discAmt', 'disc_amt']),
      gstPercent: _dbl(map, ['gstPercent', 'gst_percent', 'tax_percent']),
      gstAmt: _dbl(map, ['gstAmt', 'gst_amt']),
      cgstAmt: _dbl(map, ['cgstAmt', 'cgst_amt']),
      sgstAmt: _dbl(map, ['sgstAmt', 'sgst_amt']),
      igstAmt: _dbl(map, ['igstAmt', 'igst_amt']),
      total: _dbl(map, ['total', 'total_amount']),
      profit: _dbl(map, ['profit']),
      purchaseRate: _dbl(map, ['purchaseRate', 'purchase_rate']),
      landingCost: _dbl(map, ['landingCost', 'landing_cost']),
      supplier: map['supplier']?.toString() ?? map['supplier_name']?.toString() ?? "",
    );
  }
}

class SaleInvoice {
  String entryNo;
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

  String get invoiceNo => entryNo;
  set invoiceNo(String v) => entryNo = v;

  Map<String, dynamic> toMap() {
    return {
      'entry_no': entryNo,
      'date': date.toIso8601String(),
      'customer_acc': customerAcc,
      'patient': patient,
      'mobile': mobile,
      'doctor': doctor,
      'doctor_reg_no': doctorRegNo,
      'special_order_json': specialOrderJson,
      'tax_type': taxType,
      'days': days,
      'sub_total': subTotal,
      'discount_percent': discountPercent,
      'discount': discount,
      'additional_discount': additionalDiscount,
      'other_charge': otherCharge,
      'rcvd_amt': rcvdAmt,
      'round_off': roundOff,
      'grand_total': grandTotal,
      'agent': agent,
      'expecting_date': expectingDate,
      'special_customer_name': specialCustomerName,
      'special_customer_phone': specialCustomerPhone,
      'payment_remarks': paymentRemarks,
      'secondary_acc': secondaryAcc,
      'secondary_amt': secondaryAmt,
      'financial_year': financialYear,
      'sales_return_amt': salesReturn,
      'is_paid': isPaid ? 1 : 0,
      'is_deleted': isDeleted ? 1 : 0,
      'order_type': orderType,
    };
  }

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

  factory SaleInvoice.fromMap(Map<String, dynamic> map) {
    List<SaleItem> itemsList = [];
    if (map['items'] != null && map['items'] is List) {
      itemsList = (map['items'] as List).map((i) {
        if (i is SaleItem) return i;
        if (i is Map) return SaleItem.fromMap(Map<String, dynamic>.from(i));
        return null;
      }).whereType<SaleItem>().toList();
    }

    DateTime parsedDate;
    if (map['date'] != null) {
      parsedDate = DateTime.tryParse(map['date'].toString()) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return SaleInvoice(
      entryNo: (map['entry_no'] ?? map['entryNo'] ?? '').toString(),
      date: parsedDate,
      customerAcc: (map['customer_acc'] ?? map['customerAcc'] ?? '').toString(),
      patient: (map['patient'] ?? '').toString(),
      mobile: (map['mobile'] ?? '').toString(),
      doctor: (map['doctor'] ?? '').toString(),
      doctorRegNo: (map['doctor_reg_no'] ?? map['doctorRegNo'] ?? '').toString(),
      specialOrderJson: (map['special_order_json'] ?? map['specialOrderJson'] ?? '[]').toString(),
      taxType: (map['tax_type'] ?? map['taxType'] ?? 'Non Gst').toString(),
      days: int.tryParse((map['days'] ?? 0).toString()) ?? 0,
      items: itemsList,
      subTotal: double.tryParse((map['sub_total'] ?? map['subTotal'] ?? 0).toString()) ?? 0.0,
      discountPercent: double.tryParse((map['discount_percent'] ?? map['discountPercent'] ?? 0).toString()) ?? 0.0,
      discount: double.tryParse((map['discount'] ?? 0).toString()) ?? 0.0,
      additionalDiscount: double.tryParse((map['additional_discount'] ?? map['additionalDiscount'] ?? 0).toString()) ?? 0.0,
      otherCharge: double.tryParse((map['other_charge'] ?? map['otherCharge'] ?? 0).toString()) ?? 0.0,
      rcvdAmt: double.tryParse((map['rcvd_amt'] ?? map['rcvdAmt'] ?? 0).toString()) ?? 0.0,
      roundOff: double.tryParse((map['round_off'] ?? map['roundOff'] ?? 0).toString()) ?? 0.0,
      grandTotal: double.tryParse((map['grand_total'] ?? map['grandTotal'] ?? 0).toString()) ?? 0.0,
      agent: (map['agent'] ?? 'Admin').toString(),
      expectingDate: (map['expecting_date'] ?? map['expectingDate'] ?? '').toString(),
      specialCustomerName: (map['special_customer_name'] ?? map['specialCustomerName'] ?? '').toString(),
      specialCustomerPhone: (map['special_customer_phone'] ?? map['specialCustomerPhone'] ?? '').toString(),
      paymentRemarks: (map['payment_remarks'] ?? map['paymentRemarks'] ?? '').toString(),
      secondaryAcc: (map['secondary_acc'] ?? map['secondaryAcc'] ?? '').toString(),
      secondaryAmt: double.tryParse((map['secondary_amt'] ?? map['secondaryAmt'] ?? 0).toString()) ?? 0.0,
      financialYear: (map['financial_year'] ?? map['financialYear'] ?? '').toString(),
      salesReturn: double.tryParse((map['sales_return_amt'] ?? map['salesReturn'] ?? 0).toString()) ?? 0.0,
      isPaid: (map['is_paid'] == 1 || map['is_paid'] == true || map['isPaid'] == true),
      isDeleted: (map['is_deleted'] == 1 || map['is_deleted'] == true || map['isDeleted'] == true),
      orderType: int.tryParse((map['order_type'] ?? map['orderType'] ?? 0).toString()) ?? 0,
    );
  }
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

  double cgstAmt;
  double sgstAmt;
  double igstAmt;

  int get mrpPaise => (mrp * 100).round();
  int get pRatePaise => (pRate * 100).round();
  int get grossPaise => (gross * 100).round();
  int get discAmtPaise => (discAmt * 100).round();
  int get netPaise => (net * 100).round();
  int get gstAmtPaise => (gstAmt * 100).round();
  int get cgstAmtPaise => (cgstAmt * 100).round();
  int get sgstAmtPaise => (sgstAmt * 100).round();
  int get igstAmtPaise => (igstAmt * 100).round();
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
    this.cgstAmt = 0.0,
    this.sgstAmt = 0.0,
    this.igstAmt = 0.0,
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

  Map<String, dynamic> toMap() {
    return {
      'product_id': id,
      'product_name': productName,
      'extra': extra,
      'batch': batch,
      'expiry': expiry,
      'packin': packin,
      'qty': qty,
      'f_qty': fQty,
      'mrp': mrp,
      'p_rate': pRate,
      'gross': gross,
      'disc_percent': discPercent,
      'disc_amt': discAmt,
      'net': net,
      'gst_percent': gstPercent,
      'gst_amt': gstAmt,
      'total': total,
      'rack': rack,
      'hsn_code': hsnCode,
      's_disc_percent': sDiscPercent,
      's_rate': sRate,
      'l_cost': lCost,
    };
  }
}

class PurchaseEntry {
  String entryNo;
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
  String financialYear;
  final bool isDeleted;
  final String taxType;
  int paymentStatus;
  String? paymentMode;
  String? paymentRemarks;
  DateTime? paymentDate;
  double paidAmount;

  Map<String, dynamic> toMap() {
    return {
      'entry_no': entryNo,
      'date': date.toIso8601String(),
      'supplier_name': supplierName,
      'sup_inv_no': supInvNo,
      'sup_inv_date': supInvDate.toIso8601String(),
      'done_by': doneBy,
      'inv_total': invTotal,
      'remarks': remarks,
      'sub_total': subTotal,
      'discount': discount,
      'other_charge': otherCharge,
      'round_off': roundOff,
      'grand_total': grandTotal,
      'payment_status': paymentStatus,
      'payment_mode': paymentMode,
      'payment_remarks': paymentRemarks,
      'payment_date': paymentDate?.toIso8601String(),
      'paid_amount': paidAmount,
      'days': days,
      'financial_year': financialYear,
      'tax_type': taxType,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

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
    this.taxType = "Gst",
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

  factory SaleReturnInvoice.fromMap(Map<String, dynamic> map) {
    List<SaleItem> itemsList = [];
    if (map['items'] != null && map['items'] is List) {
      itemsList = (map['items'] as List).map((i) {
        if (i is SaleItem) return i;
        if (i is Map) return SaleItem.fromMap(Map<String, dynamic>.from(i));
        return null;
      }).whereType<SaleItem>().toList();
    }

    DateTime parsedDate;
    if (map['date'] != null) {
      parsedDate = DateTime.tryParse(map['date'].toString()) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return SaleReturnInvoice(
      entryNo: (map['return_no'] ?? map['entry_no'] ?? map['entryNo'] ?? '').toString(),
      date: parsedDate,
      customerAcc: (map['customer_acc'] ?? map['customerAcc'] ?? '').toString(),
      patient: (map['patient'] ?? '').toString(),
      doctor: (map['doctor'] ?? '').toString(),
      originalInvoiceNo: (map['original_invoice_no'] ?? map['originalInvoiceNo'] ?? '').toString(),
      items: itemsList,
      subTotal: double.tryParse((map['sub_total'] ?? map['subTotal'] ?? 0).toString()) ?? 0.0,
      discount: double.tryParse((map['discount'] ?? 0).toString()) ?? 0.0,
      roundOff: double.tryParse((map['round_off'] ?? map['roundOff'] ?? 0).toString()) ?? 0.0,
      grandTotal: double.tryParse((map['grand_total'] ?? map['grandTotal'] ?? 0).toString()) ?? 0.0,
      narration: (map['narration'] ?? '').toString(),
      gstMode: int.tryParse((map['gst_mode'] ?? map['gstMode'] ?? 1).toString()) ?? 1,
      financialYear: (map['financial_year'] ?? map['financialYear'] ?? '').toString(),
      isDeleted: (map['is_deleted'] == 1 || map['is_deleted'] == true || map['isDeleted'] == true),
    );
  }
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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'phone': phone,
      'gst_in': gstIn,
      'dl_number': dlNumber,
      'current_balance': currentBalance,
    };
  }

  factory Supplier.fromMap(Map<String, dynamic> map) {
    return Supplier(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      address: map['address']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      gstIn: map['gst_in']?.toString() ?? '',
      dlNumber: map['dl_number']?.toString() ?? '',
      currentBalance: _dbl(map, ['current_balance']),
    );
  }
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

class WholesaleStockItem {
  final String productId;
  final String productName;
  final String genericName;
  final String companyName;
  final String categoryName;
  final String wholesaleName;
  final String batchNumber;
  final String expiryDate;
  final int currentStock;
  final double purchaseRate;
  final double mrp;
  final double saleRate;
  final String rack;
  final String unit;
  final int packing;
  final String lastPurchaseDate;
  final String lastInvNo;
  final int totalPurchasedQty;
  final int rank;

  WholesaleStockItem({
    required this.productId,
    required this.productName,
    required this.genericName,
    required this.companyName,
    required this.categoryName,
    required this.wholesaleName,
    required this.batchNumber,
    required this.expiryDate,
    required this.currentStock,
    required this.purchaseRate,
    required this.mrp,
    required this.saleRate,
    required this.rack,
    required this.unit,
    required this.packing,
    this.lastPurchaseDate = "-",
    this.lastInvNo = "-",
    this.totalPurchasedQty = 0,
    this.rank = 0,
  });

  double get purchaseValuation {
    double ps = packing > 0 ? packing.toDouble() : 1.0;
    return currentStock * (purchaseRate / ps);
  }
  double get mrpValuation {
    double ps = packing > 0 ? packing.toDouble() : 1.0;
    return currentStock * (mrp / ps);
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
  final bool isDeleted;

  StockAdjustment({
    required this.entryNo,
    required this.date,
    this.doneBy = "",
    this.reason = "",
    required this.items,
    this.grandTotal = 0.0,
    this.financialYear = "",
    this.isDeleted = false,
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
    double ps = packin > 0 ? packin.toDouble() : 1.0;
    return closingStock * (mrp / ps);
  }

  double get lCostValue {
    double ps = packin > 0 ? packin.toDouble() : 1.0;
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
    orderQty: _integer(map, ['order_qty']),
    receivedQty: _integer(map, ['received_qty']),
    unitPrice: _dbl(map, ['unit_price']),
    packSize: _integer(map, ['pack_size'], 1),
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
      totalItems: _integer(map, ['total_items']),
      totalAmount: _dbl(map, ['total_amount']),
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

enum WholesalerMatchStatus {
  exactPurchase,       // 🟢 GREEN: Exact product purchased from wholesaler before
  brandVariantPurchase,// 🟧 ORANGE: Same brand family purchased from wholesaler before
  directoryMatch,      // 🟡 YELLOW: Wholesaler carries Patent/Company & Category
  none,
}

class WholesalerAvailabilityResult {
  final String wholesalerName;
  final WholesalerMatchStatus status;
  final String matchReason;
  final String matchedDetail;
  final int purchaseCount;

  WholesalerAvailabilityResult({
    required this.wholesalerName,
    required this.status,
    required this.matchReason,
    this.matchedDetail = '',
    this.purchaseCount = 0,
  });
}

class BatchMaster {
  final String batchId;
  final String productId;
  final String batchNumber;
  final String expiryDate;
  final String mfgDate;
  final String supplierId;
  final String supplierName;
  final int packing;
  final double purchaseRate;
  final double landingCost;
  final double mrp;
  final double saleRate;
  final double gstPercent;
  final String rack;
  final String createdAt;
  final bool isActive;
  final int currentLooseStock;

  BatchMaster({
    required this.batchId,
    required this.productId,
    required this.batchNumber,
    required this.expiryDate,
    this.mfgDate = '',
    this.supplierId = '',
    this.supplierName = '',
    this.packing = 1,
    this.purchaseRate = 0.0,
    this.landingCost = 0.0,
    this.mrp = 0.0,
    this.saleRate = 0.0,
    this.gstPercent = 12.0,
    this.rack = '',
    String? createdAt,
    this.isActive = true,
    this.currentLooseStock = 0,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() {
    return {
      'batch_id': batchId,
      'product_id': productId,
      'batch_number': batchNumber,
      'expiry_date': expiryDate,
      'mfg_date': mfgDate,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'packing': packing > 0 ? packing : 1,
      'purchase_rate': purchaseRate,
      'landing_cost': landingCost,
      'mrp': mrp,
      'sale_rate': saleRate,
      'gst_percent': gstPercent,
      'rack': rack,
      'created_at': createdAt,
      'is_active': isActive ? 1 : 0,
    };
  }

  factory BatchMaster.fromMap(Map<String, dynamic> map, {int currentLooseStock = 0}) {
    return BatchMaster(
      batchId: map['batch_id']?.toString() ?? '',
      productId: map['product_id']?.toString() ?? '',
      batchNumber: map['batch_number']?.toString() ?? '',
      expiryDate: map['expiry_date']?.toString() ?? '',
      mfgDate: map['mfg_date']?.toString() ?? '',
      supplierId: map['supplier_id']?.toString() ?? '',
      supplierName: map['supplier_name']?.toString() ?? '',
      packing: _integer(map, ['packing'], 1),
      purchaseRate: _dbl(map, ['purchase_rate']),
      landingCost: _dbl(map, ['landing_cost']),
      mrp: _dbl(map, ['mrp']),
      saleRate: _dbl(map, ['sale_rate']),
      gstPercent: _dbl(map, ['gst_percent'], 12.0),
      rack: map['rack']?.toString() ?? '',
      createdAt: map['created_at']?.toString(),
      isActive: map['is_active'] == null ? true : map['is_active'] == 1,
      currentLooseStock: currentLooseStock,
    );
  }
}

class StockLedgerEntry {
  final int? ledgerId;
  final String timestamp;
  final String batchId;
  final String productId;
  final String voucherType; // 'PURCHASE', 'SALE', 'SALES_RETURN', 'PURCHASE_RETURN', 'DAMAGE', 'ADJUSTMENT'
  final String voucherNo;
  final int qtyIn;  // Loose units added
  final int qtyOut; // Loose units deducted
  final double purchaseRate;
  final double mrp;
  final String supplierName;
  final String remarks;
  final String userId;
  final String financialYear;

  StockLedgerEntry({
    this.ledgerId,
    String? timestamp,
    required this.batchId,
    required this.productId,
    required this.voucherType,
    required this.voucherNo,
    this.qtyIn = 0,
    this.qtyOut = 0,
    this.purchaseRate = 0.0,
    this.mrp = 0.0,
    this.supplierName = '',
    this.remarks = '',
    this.userId = 'Admin',
    this.financialYear = '',
  }) : timestamp = timestamp ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() {
    return {
      if (ledgerId != null) 'ledger_id': ledgerId,
      'timestamp': timestamp,
      'batch_id': batchId,
      'product_id': productId,
      'voucher_type': voucherType,
      'voucher_no': voucherNo,
      'qty_in': qtyIn,
      'qty_out': qtyOut,
      'purchase_rate': purchaseRate,
      'mrp': mrp,
      'supplier_name': supplierName,
      'remarks': remarks,
      'user_id': userId,
      'financial_year': financialYear,
    };
  }

  factory StockLedgerEntry.fromMap(Map<String, dynamic> map) {
    return StockLedgerEntry(
      ledgerId: map['ledger_id'] as int?,
      timestamp: map['timestamp']?.toString(),
      batchId: map['batch_id']?.toString() ?? '',
      productId: map['product_id']?.toString() ?? '',
      voucherType: map['voucher_type']?.toString() ?? '',
      voucherNo: map['voucher_no']?.toString() ?? '',
      qtyIn: _integer(map, ['qty_in']),
      qtyOut: _integer(map, ['qty_out']),
      purchaseRate: _dbl(map, ['purchase_rate']),
      mrp: _dbl(map, ['mrp']),
      supplierName: map['supplier_name']?.toString() ?? '',
      remarks: map['remarks']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? 'Admin',
      financialYear: map['financial_year']?.toString() ?? '',
    );
  }
}

