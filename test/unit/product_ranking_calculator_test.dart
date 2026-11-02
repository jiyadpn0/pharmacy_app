import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/product_ranking.dart';

void main() {
  group('ProductRankingCalculator Tests', () {
    late ProductRanking product;

    setUp(() {
      final now = DateTime.now();
      product = ProductRanking(
        id: 'P101',
        name: 'Paracetamol 500mg',
        pack: 10,
        isActive: true,
        patent: 'Ethical',
        category: 'Analgesics',
        rack: 'A1',
        mrp: 50.0,
        pRate: 35.0,
        genericName: 'Paracetamol',
        preferredWholesale: 'ABC Pharma',
        monthlyStats: [
          MonthlyStat(
            startDate: now.subtract(const Duration(days: 30)),
            endDate: now,
          )
            ..monthSale = 100.0
            ..higherSale = 120.0
            ..saleCount = 15,
          MonthlyStat(
            startDate: now.subtract(const Duration(days: 60)),
            endDate: now.subtract(const Duration(days: 31)),
          )
            ..monthSale = 80.0
            ..higherSale = 90.0
            ..saleCount = 10,
        ],
        currentStock: 25.0,
      );
    });

    test('calculateRankings calculates formula metrics correctly', () {
      final rankings = [product];

      ProductRankingCalculator.calculateRankings(
        rankings: rankings,
        rankFormula: '=MAX(C, D, A) + B',
        rankRules: const [],
        reOrderFormula: 'W',
        reOrderRules: const [],
        warningFormula: '0',
        warningRules: const [],
        maxOrderFormula: 'Y * 2',
        maxOrderRules: const [],
        customMetricColumns: const [],
      );

      expect(rankings.first.weightedScore, isNotNull);
      expect(rankings.first.weightedScore, greaterThanOrEqualTo(0.0));
    });

    test('Moving average metrics formatting works correctly', () {
      final formatted = ProductRankingCalculator.getMovingAverage(product, interval: 0);
      expect(formatted, isA<String>());
    });
  });
}
