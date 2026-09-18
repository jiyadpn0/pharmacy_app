import 'package:flutter_test/flutter_test.dart';
import 'package:pharmacy_app/utils/tax_calculator.dart';

void main() {
  group('TaxCalculator Unit Tests', () {
    test('toPaise correctly converts rupees to paise', () {
      expect(TaxCalculator.toPaise(100.0), equals(10000));
      expect(TaxCalculator.toPaise(10.50), equals(1050));
      expect(TaxCalculator.toPaise(0.05), equals(5));
      expect(TaxCalculator.toPaise(0.0), equals(0));
    });

    test('toRupeesString formats paise with 2 decimal places', () {
      expect(TaxCalculator.toRupeesString(10000), equals('100.00'));
      expect(TaxCalculator.toRupeesString(1050), equals('10.50'));
      expect(TaxCalculator.toRupeesString(5), equals('0.05'));
    });

    test('roundGstPercent normalizes near-integer GST rates', () {
      expect(TaxCalculator.roundGstPercent(17.99), equals(18.0));
      expect(TaxCalculator.roundGstPercent(4.99), equals(5.0));
      expect(TaxCalculator.roundGstPercent(12.0), equals(12.0));
      expect(TaxCalculator.roundGstPercent(0.0), equals(0.0));
    });

    test('calculateInclusive calculates GST from total MRP correctly', () {
      // For Rs. 112 inclusive at 12% GST: Taxable = 100, GST = 12
      final res = TaxCalculator.calculateInclusive(112.0, 12.0);
      expect(res.taxableAmount, equals(100.0));
      expect(res.gstAmount, equals(12.0));
      expect(res.totalAmount, equals(112.0));
      expect(res.cgstPaise, equals(600)); // 6 Rs
      expect(res.sgstPaise, equals(600)); // 6 Rs
    });

    test('calculateExclusive calculates GST on top of taxable rate correctly', () {
      // For Rs. 100 taxable at 18% GST: Taxable = 100, GST = 18, Total = 118
      final res = TaxCalculator.calculateExclusive(100.0, 18.0);
      expect(res.taxableAmount, equals(100.0));
      expect(res.gstAmount, equals(18.0));
      expect(res.totalAmount, equals(118.0));
      expect(res.cgstPaise, equals(900)); // 9 Rs
      expect(res.sgstPaise, equals(900)); // 9 Rs
    });

    test('Handles 0 GST gracefully', () {
      final res = TaxCalculator.calculateInclusive(100.0, 0.0);
      expect(res.taxableAmount, equals(100.0));
      expect(res.gstAmount, equals(0.0));
      expect(res.totalAmount, equals(100.0));
    });
  });
}
