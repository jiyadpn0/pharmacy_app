import 'dart:math' as math;

/// Strategy used to calculate the recommended reorder quantity
enum ReorderAlgorithm {
  /// Simple Min-Max: If Stock <= ReorderLevel, Order = (MaxLevel - Stock)
  minMax,

  /// Product Ranking Score based: Rank - (Stock in packs)
  rankingScore,

  /// Enterprise Safety Stock & Lead-Time Demand (ROP):
  /// Demand = (Avg Daily Sales * Lead Time) + Safety Stock
  enterpriseRop,

  /// Dynamic hybrid: Uses highest confidence between Sales Velocity and Ranking
  dynamicHybrid,
}

/// Status of a product recommendation in buy planning
enum BuyPlanPriority {
  critical, // Out of stock or negative stock
  urgent,   // Below safety stock / reorder level
  moderate, // Approaching reorder level
  excess,   // Stock exceeds max level
  normal,   // Adequate stock
}

/// A normalized, strongly typed buy planning recommendation item
class BuyPlanItem {
  final String productId;
  final String productName;
  final String genericName;
  final String brand;
  final String category;
  final String rack;
  final int packSize;
  final double mrp;
  final double purchaseRate;
  final String preferredWholesale;
  final String bestProfitWholesale;
  final String latestOffer;

  // Inventory & Sales metrics
  final double currentStock;
  final double minLevel;
  final double maxLevel;
  final double rankScore;
  final double warningScore;
  final int supplierLeadTimeDays;

  // Sales Velocity
  final double last30DaysSale;
  final double intervalSaleQty;
  final double maxSingleTxn4M;
  final double totalSale1Year;
  final String lastSaleDate;
  final String lastSaleEntryNo;
  final double lastSaleQty;
  final int lastOrderType;
  final String firstPurchaseDate;
  final String mappedName;

  // Calculated fields
  final int suggestedOrderPacks;
  final int suggestedOrderUnits;
  final double projectedCost;
  final BuyPlanPriority priority;
  final String calculationReason;

  const BuyPlanItem({
    required this.productId,
    required this.productName,
    this.genericName = '',
    this.brand = '',
    this.category = 'General',
    this.rack = '',
    this.packSize = 1,
    this.mrp = 0.0,
    this.purchaseRate = 0.0,
    this.preferredWholesale = '-',
    this.bestProfitWholesale = '-',
    this.latestOffer = '-',
    this.currentStock = 0.0,
    this.minLevel = 0.0,
    this.maxLevel = 0.0,
    this.rankScore = 0.0,
    this.warningScore = 0.0,
    this.supplierLeadTimeDays = 2,
    this.last30DaysSale = 0.0,
    this.intervalSaleQty = 0.0,
    this.maxSingleTxn4M = 0.0,
    this.totalSale1Year = 0.0,
    this.lastSaleDate = '',
    this.lastSaleEntryNo = '-',
    this.lastSaleQty = 0.0,
    this.lastOrderType = 0,
    this.firstPurchaseDate = '',
    this.mappedName = '',
    required this.suggestedOrderPacks,
    required this.suggestedOrderUnits,
    required this.projectedCost,
    required this.priority,
    required this.calculationReason,
  });

  /// Stock expressed in packs (boxes/strips)
  double get stockInPacks => packSize > 0 ? currentStock / packSize : currentStock;

  /// Whether this item needs to be ordered
  bool get needsReorder => suggestedOrderPacks > 0;

  Map<String, dynamic> toMap() {
    return {
      'id': productId,
      'name': productName,
      'content': genericName,
      'brand': brand,
      'classification': category,
      'rack': rack,
      'packSize': packSize,
      'mrp': mrp,
      'pRate': purchaseRate,
      'preferred_wholesale': preferredWholesale,
      'bestProfitWholesale': bestProfitWholesale,
      'latestOffer': latestOffer,
      'currentBalance': currentStock,
      'minLevel': minLevel,
      'maxLevel': maxLevel,
      'rank': rankScore,
      'warning': warningScore,
      'leadTime': supplierLeadTimeDays,
      'sales_30d': last30DaysSale,
      'intervalSaleQty': intervalSaleQty,
      'maxSingleTxn4M': maxSingleTxn4M,
      'totalSale1Y': totalSale1Year,
      'lastSaleDate': lastSaleDate,
      'lastSaleEntryNo': lastSaleEntryNo,
      'lastSaleQty': lastSaleQty,
      'lastOrderType': lastOrderType,
      'firstPurchaseDate': firstPurchaseDate,
      'mappedName': mappedName,
      'suggested_packs': suggestedOrderPacks,
      'suggested_units': suggestedOrderUnits,
      'projected_cost': projectedCost,
      'priority': priority.name,
      'reason': calculationReason,
    };
  }
}

/// Helper calculation engine for professional reorder logic
class BuyPlanningEngine {
  /// Enterprise Reorder Calculator
  /// Converts loose units, packs, lead time demand, and safety stock into full-pack order requirements
  static BuyPlanItem calculate({
    required Map<String, dynamic> raw,
    ReorderAlgorithm algorithm = ReorderAlgorithm.dynamicHybrid,
  }) {
    final String pid = (raw['id'] ?? '').toString();
    final String name = (raw['name'] ?? '').toString();
    final String generic = (raw['content'] ?? raw['generic_name'] ?? '').toString();
    final String brand = (raw['brand'] ?? raw['manufacturer_id'] ?? '').toString();
    final String category = (raw['classification'] ?? raw['category_id'] ?? 'General').toString();
    final String rack = (raw['rack'] ?? raw['rack_id'] ?? '').toString();

    final int packSize = math.max(1, (raw['packSize'] as num?)?.toInt() ?? (raw['packing'] as num?)?.toInt() ?? 1);
    final double mrp = (raw['mrp'] as num?)?.toDouble() ?? 0.0;
    final double pRate = (raw['pRate'] as num?)?.toDouble() ?? (raw['purchase_rate'] as num?)?.toDouble() ?? 0.0;

    final String prefWholesale = (raw['preferred_wholesale'] ?? raw['supplier'] ?? '-').toString();
    final String bestWholesale = (raw['bestProfitWholesale'] ?? prefWholesale).toString();
    final String latestOffer = (raw['latestOffer'] ?? '-').toString();

    final double currentStock = (raw['currentBalance'] as num?)?.toDouble() ?? (raw['current_stock'] as num?)?.toDouble() ?? (raw['stock'] as num?)?.toDouble() ?? 0.0;
    final double minLevel = (raw['minLevel'] as num?)?.toDouble() ?? (raw['reorder_level'] as num?)?.toDouble() ?? 0.0;
    final double maxLevel = (raw['maxLevel'] as num?)?.toDouble() ?? (raw['max_level'] as num?)?.toDouble() ?? 0.0;
    final double rankScore = (raw['rank'] as num?)?.toDouble() ?? 0.0;
    final double warningScore = (raw['warning'] as num?)?.toDouble() ?? 0.0;

    final int leadTime = math.max(1, (raw['leadTime'] as num?)?.toInt() ?? (raw['lead_time'] as num?)?.toInt() ?? 2);
    final double last30d = (raw['sales_30d'] as num?)?.toDouble() ?? (raw['last30DaysSale'] as num?)?.toDouble() ?? (raw['intervalSaleQty'] as num?)?.toDouble() ?? 0.0;
    final double intervalQty = (raw['intervalSaleQty'] as num?)?.toDouble() ?? 0.0;
    final double maxSingleTxn = (raw['maxSingleTxn4M'] as num?)?.toDouble() ?? 0.0;
    final double total1Y = (raw['totalSale1Y'] as num?)?.toDouble() ?? (raw['totalSale1Year'] as num?)?.toDouble() ?? 0.0;

    final String lastSaleDate = (raw['lastSaleDate'] ?? '').toString();
    final String lastSaleEntryNo = (raw['lastSaleEntryNo'] ?? '-').toString();
    final double lastSaleQty = (raw['lastSaleQty'] as num?)?.toDouble() ?? 0.0;
    final int lastOrderType = (raw['lastOrderType'] as num?)?.toInt() ?? 0;
    final String firstPurDate = (raw['firstPurchaseDate'] ?? '').toString();
    final String mappedName = (raw['mappedName'] ?? '').toString();

    // 1. Determine stock in pack increments
    final double stockInPacks = currentStock / packSize;
    final double effectiveMin = minLevel > 0 ? minLevel : (rankScore > 0 ? rankScore : 0.0);

    int orderPacks = 0;
    String reason = 'Stock is healthy';
    BuyPlanPriority priority = BuyPlanPriority.normal;

    if (currentStock <= 0) {
      priority = BuyPlanPriority.critical;
    } else if (effectiveMin > 0 && stockInPacks <= effectiveMin) {
      priority = BuyPlanPriority.urgent;
    } else if (maxLevel > 0 && stockInPacks > maxLevel) {
      priority = BuyPlanPriority.excess;
    }

    // 2. Compute Reorder Quantity based on selected algorithm
    switch (algorithm) {
      case ReorderAlgorithm.minMax:
        if (effectiveMin > 0 && stockInPacks <= effectiveMin) {
          double target = maxLevel > effectiveMin ? maxLevel : (effectiveMin * 2.0);
          double needed = target - stockInPacks;
          orderPacks = roundToPack(needed);
          reason = 'Min-Max replenishment: target $target packs';
        }
        break;

      case ReorderAlgorithm.rankingScore:
        if (stockInPacks <= effectiveMin && (rankScore > 0 || minLevel > 0)) {
          double rawDeficit = (rankScore > 0 ? rankScore : effectiveMin) - stockInPacks;
          orderPacks = roundToPack(rawDeficit);
          reason = 'Product ranking score demand: $rankScore';
        }
        break;

      case ReorderAlgorithm.enterpriseRop:
        final avgDaily = last30d / 30.0;
        final maxDaily = maxSingleTxn > 0 ? maxSingleTxn : (avgDaily * 2.0);
        final leadDemand = avgDaily * leadTime;
        final safetyStock = math.max(0.0, (maxDaily * (leadTime + 1)) - leadDemand);
        final rop = leadDemand + safetyStock;

        if (currentStock <= rop) {
          final targetStockUnits = last30d + safetyStock;
          final neededUnits = math.max(0.0, targetStockUnits - currentStock);
          orderPacks = (neededUnits / packSize).ceil();
          reason = 'ROP triggered (Stock $currentStock <= ROP ${rop.toStringAsFixed(1)})';
        }
        break;

      case ReorderAlgorithm.dynamicHybrid:
        // Hybrid: Use Ranking Score when configured, otherwise Enterprise ROP, or Min-Max fallback
        if (rankScore > 0 && stockInPacks <= effectiveMin) {
          double rawDeficit = rankScore - stockInPacks;
          orderPacks = roundToPack(rawDeficit);
          reason = 'Rank-based demand: $rankScore';
        } else if (last30d > 0) {
          final avgDaily = last30d / 30.0;
          final maxDaily = maxSingleTxn > 0 ? maxSingleTxn : (avgDaily * 1.5);
          final leadDemand = avgDaily * leadTime;
          final safetyStock = math.max(0.0, (maxDaily * (leadTime + 1)) - leadDemand);
          final rop = leadDemand + safetyStock;

          if (currentStock <= rop) {
            final targetStockUnits = (avgDaily * 30.0) + safetyStock;
            final neededUnits = math.max(0.0, targetStockUnits - currentStock);
            orderPacks = (neededUnits / packSize).ceil();
            reason = 'Sales velocity & lead time (ROP: ${rop.toStringAsFixed(1)})';
          }
        } else if (effectiveMin > 0 && stockInPacks <= effectiveMin) {
          double target = maxLevel > effectiveMin ? maxLevel : (effectiveMin * 1.5);
          double needed = target - stockInPacks;
          orderPacks = roundToPack(needed);
          reason = 'Minimum stock threshold reached';
        }
        break;
    }

    if (orderPacks <= 0 && priority == BuyPlanPriority.critical && last30d > 0) {
      orderPacks = 1; // Order at least 1 pack for out of stock moving items
      reason = 'Critical zero-stock minimum order';
    }

    final int orderUnits = orderPacks * packSize;
    final double projectedCost = orderPacks * pRate;

    return BuyPlanItem(
      productId: pid,
      productName: name,
      genericName: generic,
      brand: brand,
      category: category,
      rack: rack,
      packSize: packSize,
      mrp: mrp,
      purchaseRate: pRate,
      preferredWholesale: prefWholesale,
      bestProfitWholesale: bestWholesale,
      latestOffer: latestOffer,
      currentStock: currentStock,
      minLevel: minLevel,
      maxLevel: maxLevel,
      rankScore: rankScore,
      warningScore: warningScore,
      supplierLeadTimeDays: leadTime,
      last30DaysSale: last30d,
      intervalSaleQty: intervalQty,
      maxSingleTxn4M: maxSingleTxn,
      totalSale1Year: total1Y,
      lastSaleDate: lastSaleDate,
      lastSaleEntryNo: lastSaleEntryNo,
      lastSaleQty: lastSaleQty,
      lastOrderType: lastOrderType,
      firstPurchaseDate: firstPurDate,
      mappedName: mappedName,
      suggestedOrderPacks: orderPacks,
      suggestedOrderUnits: orderUnits,
      projectedCost: projectedCost,
      priority: priority,
      calculationReason: reason,
    );
  }

  /// Professional pack rounding:
  /// Any fractional requirement >= 0.1 rounds up to the next full pack/strip
  static int roundToPack(double rawValue) {
    if (rawValue <= 0 || rawValue.isNaN || rawValue.isInfinite) return 0;
    int floorVal = rawValue.floor();
    double remainder = rawValue - floorVal;
    return remainder >= 0.09999 ? floorVal + 1 : floorVal;
  }
}
