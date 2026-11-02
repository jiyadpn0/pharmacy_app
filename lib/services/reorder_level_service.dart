import '../models/product_ranking.dart';

class ReorderThreshold {
  final String productId;
  final String productName;
  final double currentStock;
  final double calculatedMinLevel;
  final double calculatedMaxLevel;
  final bool isReorderSuggested;

  ReorderThreshold({
    required this.productId,
    required this.productName,
    required this.currentStock,
    required this.calculatedMinLevel,
    required this.calculatedMaxLevel,
    required this.isReorderSuggested,
  });
}

class ReorderLevelService {
  static final ReorderLevelService instance = ReorderLevelService._internal();
  ReorderLevelService._internal();

  /// Calculates dynamic Minimum and Maximum re-order thresholds based on 30/90-day sales velocity
  ReorderThreshold calculateDynamicReorder(ProductRanking ranking) {
    double total30DaySales = 0.0;
    if (ranking.monthlyStats.isNotEmpty) {
      total30DaySales = ranking.monthlyStats.first.monthSale;
    }

    // Lead time buffer (7 days) + Safety stock buffer (15 days)
    double dailySales = total30DaySales / 30.0;
    double minLevel = (dailySales * 15.0).ceilToDouble(); // 15 days safety stock
    double maxLevel = (dailySales * 45.0).ceilToDouble(); // 45 days max stock

    if (minLevel < 1.0) minLevel = 1.0;
    if (maxLevel < minLevel) maxLevel = minLevel * 2;

    bool needsOrder = ranking.currentStock <= minLevel;

    return ReorderThreshold(
      productId: ranking.id,
      productName: ranking.name,
      currentStock: ranking.currentStock,
      calculatedMinLevel: minLevel,
      calculatedMaxLevel: maxLevel,
      isReorderSuggested: needsOrder,
    );
  }
}
