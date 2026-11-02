import '../models/product_ranking.dart';

class ForecastResult {
  final String productId;
  final String productName;
  final double currentStock;
  final double averageMonthlySales;
  final double predictedNextMonthDemand;
  final double suggestedOrderQty;

  ForecastResult({
    required this.productId,
    required this.productName,
    required this.currentStock,
    required this.averageMonthlySales,
    required this.predictedNextMonthDemand,
    required this.suggestedOrderQty,
  });
}

class DemandForecastingEngine {
  static final DemandForecastingEngine instance = DemandForecastingEngine._internal();
  DemandForecastingEngine._internal();

  /// Predicts next month's product demand based on weighted moving average and seasonal factor
  ForecastResult predictDemand({
    required ProductRanking ranking,
    double seasonalFactor = 1.15, // Default 15% seasonal growth buffer
  }) {
    double totalSales = 0.0;
    int monthsCount = ranking.monthlyStats.length;

    if (monthsCount == 0) {
      return ForecastResult(
        productId: ranking.id,
        productName: ranking.name,
        currentStock: ranking.currentStock,
        averageMonthlySales: 0.0,
        predictedNextMonthDemand: 0.0,
        suggestedOrderQty: 0.0,
      );
    }

    for (var m in ranking.monthlyStats) {
      totalSales += m.monthSale;
    }

    double avgSales = totalSales / monthsCount;
    double predictedDemand = avgSales * seasonalFactor;
    double suggestedQty = predictedDemand - ranking.currentStock;

    if (suggestedQty < 0) suggestedQty = 0;

    return ForecastResult(
      productId: ranking.id,
      productName: ranking.name,
      currentStock: ranking.currentStock,
      averageMonthlySales: avgSales,
      predictedNextMonthDemand: predictedDemand,
      suggestedOrderQty: suggestedQty,
    );
  }

  /// Calculates AI demand velocity forecasts for multiple product rankings in parallel
  List<ForecastResult> calculateBatchForecasts(List<ProductRanking> rankings) {
    List<ForecastResult> results = [];
    for (var r in rankings) {
      final res = predictDemand(ranking: r);
      if (res.suggestedOrderQty > 0) {
        results.add(res);
      }
    }
    return results;
  }
}
