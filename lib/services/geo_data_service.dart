import '../models/stock_geo_data.dart';

class GeoDataService {
  final StockGeoDistribution stockGeoDistribution;

  GeoDataService({StockGeoDistribution? distribution})
      : stockGeoDistribution = distribution ?? StockGeoDistribution();

  Map<String, double> getDistrictPercentageMap({
    required String stateName,
    required GeoMetricType metric,
    required TimePeriod period,
  }) {
    return stockGeoDistribution.getDistrictPercentageMap(
      stateName: stateName,
      metric: metric,
      period: period,
    );
  }
}
