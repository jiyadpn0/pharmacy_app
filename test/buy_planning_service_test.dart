import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/buy_planning_models.dart';

void main() {
  group('BuyPlanningEngine Tests', () {
    test('roundToPack rounds up when remainder >= 0.1', () {
      expect(BuyPlanningEngine.roundToPack(0.0), 0);
      expect(BuyPlanningEngine.roundToPack(1.0), 1);
      expect(BuyPlanningEngine.roundToPack(1.05), 1);
      expect(BuyPlanningEngine.roundToPack(1.1), 2);
      expect(BuyPlanningEngine.roundToPack(2.45), 3);
    });

    test('Min-Max algorithm replenishment test', () {
      final raw = {
        'id': 'PROD_1',
        'name': 'Paracetamol 500mg',
        'packSize': 10,
        'currentBalance': 20.0, // 2 packs
        'minLevel': 5.0, // 5 packs
        'maxLevel': 15.0, // 15 packs
      };

      final item = BuyPlanningEngine.calculate(
        raw: raw,
        algorithm: ReorderAlgorithm.minMax,
      );

      // Deficit = 15 - 2 = 13 packs
      expect(item.suggestedOrderPacks, 13);
      expect(item.suggestedOrderUnits, 130);
      expect(item.priority, BuyPlanPriority.urgent);
    });

    test('Zero stock moving item triggers critical priority and order', () {
      final raw = {
        'id': 'PROD_2',
        'name': 'Amoxicillin 625mg',
        'packSize': 10,
        'currentBalance': 0.0,
        'minLevel': 5.0,
        'maxLevel': 10.0,
        'sales_30d': 60.0, // moving item
      };

      final item = BuyPlanningEngine.calculate(
        raw: raw,
        algorithm: ReorderAlgorithm.dynamicHybrid,
      );

      expect(item.priority, BuyPlanPriority.critical);
      expect(item.suggestedOrderPacks > 0, true);
    });
  });
}
