import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/models/erp_models.dart';

void main() {
  group('Product Stock Unit Tests', () {
    test('Product stock calculation and batch properties', () {
      final product = Product(
        id: 'P-101',
        name: 'Aspirin 75mg',
        batch: 'B123',
        expiry: '12/26',
        stock: 50,
        purchaseRate: 10.0,
        mrp: 15.0,
        salePrice: 14.0,
      );

      expect(product.id, equals('P-101'));
      expect(product.name, equals('Aspirin 75mg'));
      expect(product.batch, equals('B123'));
      expect(product.stock, equals(50));
      expect(product.purchaseRate, equals(10.0));
      expect(product.mrp, equals(15.0));
    });
  });
}
