import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/erp_models.dart';

void main() {
  group('Product Search Deduplication Tests', () {
    test('Deduplicates multiple catalog entries with identical normalized identity', () {
      final p1 = Product(
        id: "1",
        name: "DOLO 650MG TAB",
        packSize: 15,
        stock: 0,
        isActive: true,
        genericName: "",
      );
      final p2 = Product(
        id: "2",
        name: "DOLO 650MG TAB",
        packSize: 15,
        stock: 50,
        isActive: true,
        genericName: "PARACETAMOL 650MG",
      );
      final p3 = Product(
        id: "3",
        name: "Dolo 650mg Tab",
        packSize: 15,
        stock: 10,
        isActive: false,
        genericName: "",
      );

      final rawList = [p1, p2, p3];
      final deduplicated = Product.deduplicateProducts(rawList);

      expect(deduplicated.length, equals(1));
      expect(deduplicated.first.id, equals("2"));
      expect(deduplicated.first.name, equals("DOLO 650MG TAB"));
      expect(deduplicated.first.genericName, equals("PARACETAMOL 650MG"));
      expect(deduplicated.first.stock, equals(60)); // Aggregated stock 50 + 10 = 60
    });

    test('Deduplicates spacing variations in strength formatting', () {
      final p1 = Product(
        id: "10",
        name: "DOLO 650 MG TAB",
        packSize: 15,
        stock: 10,
        isActive: true,
      );
      final p2 = Product(
        id: "11",
        name: "DOLO 650MG TAB",
        packSize: 15,
        stock: 20,
        isActive: true,
      );

      final deduplicated = Product.deduplicateProducts([p1, p2]);
      expect(deduplicated.length, equals(1));
      expect(deduplicated.first.stock, equals(30));
    });

    test('Does NOT collapse products that differ in strength', () {
      final p650 = Product(
        id: "1",
        name: "DOLO 650MG TAB",
        packSize: 15,
        stock: 20,
        isActive: true,
      );
      final p500 = Product(
        id: "2",
        name: "DOLO 500MG TAB",
        packSize: 15,
        stock: 30,
        isActive: true,
      );

      final deduplicated = Product.deduplicateProducts([p650, p500]);
      expect(deduplicated.length, equals(2));
      expect(deduplicated[0].name, equals("DOLO 650MG TAB"));
      expect(deduplicated[1].name, equals("DOLO 500MG TAB"));
    });

    test('Does NOT collapse products that differ in pack size', () {
      final pack15 = Product(
        id: "1",
        name: "DOLO 650MG TAB",
        packSize: 15,
        stock: 20,
        isActive: true,
      );
      final pack10 = Product(
        id: "2",
        name: "DOLO 650MG TAB",
        packSize: 10,
        stock: 15,
        isActive: true,
      );

      final deduplicated = Product.deduplicateProducts([pack15, pack10]);
      expect(deduplicated.length, equals(2));
      expect(deduplicated[0].packSize, equals(15));
      expect(deduplicated[1].packSize, equals(10));
    });

    test('Prefers active products with live stock and generic information', () {
      final inactiveWithStock = Product(
        id: "101",
        name: "AZITHRAL 500MG TAB",
        packSize: 5,
        stock: 100,
        isActive: false,
        genericName: "AZITHROMYCIN 500MG",
      );
      final activeWithStockAndGeneric = Product(
        id: "102",
        name: "AZITHRAL 500MG TAB",
        packSize: 5,
        stock: 40,
        isActive: true,
        genericName: "AZITHROMYCIN 500MG",
      );
      final activeNoStockNoGeneric = Product(
        id: "103",
        name: "AZITHRAL 500MG TAB",
        packSize: 5,
        stock: 0,
        isActive: true,
        genericName: "",
      );

      final deduplicated = Product.deduplicateProducts([
        inactiveWithStock,
        activeNoStockNoGeneric,
        activeWithStockAndGeneric,
      ]);

      expect(deduplicated.length, equals(1));
      expect(deduplicated.first.id, equals("102"));
    });

    test('Ensures exact match check works correctly for CREATE NEW MEDICINE', () {
      final p1 = Product(
        id: "1",
        name: "DOLO 650MG TAB",
        packSize: 15,
        stock: 20,
        isActive: true,
      );

      final results = Product.deduplicateProducts([p1]);

      // Query "DOLO 650" - not an exact match for "DOLO 650MG TAB"
      const queryNoExact = "DOLO 650";
      final cleanQ1 = Product.cleanProductName(queryNoExact).toLowerCase();
      final bool hasExact1 = results.any((p) =>
          p.id != "NEW" && Product.cleanProductName(p.name).toLowerCase() == cleanQ1);
      expect(hasExact1, isFalse);

      // Query "DOLO 650MG TAB" - exact match exists
      const queryExact = "DOLO 650MG TAB";
      final cleanQ2 = Product.cleanProductName(queryExact).toLowerCase();
      final bool hasExact2 = results.any((p) =>
          p.id != "NEW" && Product.cleanProductName(p.name).toLowerCase() == cleanQ2);
      expect(hasExact2, isTrue);
    });
  });
}
