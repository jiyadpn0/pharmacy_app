import 'dart:math';

class TaxResult {
  final double taxableAmount;
  final double gstAmount;
  final double totalAmount;
  final int taxablePaise;
  final int gstPaise;
  final int totalPaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;

  const TaxResult({
    required this.taxableAmount,
    required this.gstAmount,
    required this.totalAmount,
    this.taxablePaise = 0,
    this.gstPaise = 0,
    this.totalPaise = 0,
    this.cgstPaise = 0,
    this.sgstPaise = 0,
    this.igstPaise = 0,
  });

  factory TaxResult.fromPaise({
    required int taxablePaise,
    required int gstPaise,
    required int totalPaise,
    int? cgstPaise,
    int? sgstPaise,
    int? igstPaise,
  }) {
    final int cPaise = cgstPaise ?? (gstPaise ~/ 2);
    final int sPaise = sgstPaise ?? (gstPaise - cPaise);
    final int iPaise = igstPaise ?? 0;

    return TaxResult(
      taxableAmount: taxablePaise / 100.0,
      gstAmount: gstPaise / 100.0,
      totalAmount: totalPaise / 100.0,
      taxablePaise: taxablePaise,
      gstPaise: gstPaise,
      totalPaise: totalPaise,
      cgstPaise: cPaise,
      sgstPaise: sPaise,
      igstPaise: iPaise,
    );
  }

  @override
  String toString() => 'Taxable: $taxableAmount ($taxablePaise p), GST: $gstAmount ($gstPaise p), Total: $totalAmount ($totalPaise p)';
}

class TaxCalculator {
  /// Converts rupees (double) to integer paise cleanly
  static int toPaise(double rupees) => (rupees * 100).round();

  /// Converts paise to rupees string with fixed 2 decimal places
  static String toRupeesString(int paise) => (paise / 100.0).toStringAsFixed(2);

  /// Applies explicit half-up integer math rather than relying on floating-point epsilon paddings.
  static double round(double value, [int places = 2]) {
    final double mod = pow(10.0, places).toDouble();
    return (value * mod).round() / mod;
  }

  /// Rounds GST percentage to whole number if it is within 0.1% upside or downside.
  /// E.g., 17.99 -> 18.0, 4.99 -> 5.0, 5.01 -> 5.0, 5.03 -> 5.0, 18.00 -> 18.0.
  static double roundGstPercent(double gst) {
    if (gst <= 0) return 0.0;
    final double rounded = gst.roundToDouble();
    if ((gst - rounded).abs() <= 0.101) {
      return rounded;
    }
    return gst;
  }

  /// Calculates line-item TaxAmount in integer paise using explicit half-up integer math:
  /// TaxAmount = (BaseValue * GSTPercent) / 100
  static int calculateTaxAmountPaise(int baseValuePaise, double gstPercent) {
    final double effectiveGst = roundGstPercent(gstPercent);
    if (effectiveGst <= 0 || baseValuePaise <= 0) return 0;
    return ((baseValuePaise * effectiveGst) / 100.0).round();
  }

  /// Calculates TAX from an INCLUSIVE total in integer paise using explicit half-up integer rounding.
  /// Formula: Taxable = Total / (1 + (Rate / 100))
  /// GST = Total - Taxable
  static TaxResult calculateInclusivePaise(int totalPaise, double gstPercent) {
    final double effectiveGst = roundGstPercent(gstPercent);
    if (effectiveGst <= 0 || totalPaise <= 0) {
      return TaxResult.fromPaise(
        taxablePaise: totalPaise,
        gstPaise: 0,
        totalPaise: totalPaise,
      );
    }

    final int taxablePaise = ((totalPaise * 100.0) / (100.0 + effectiveGst)).round();
    final int gstPaise = totalPaise - taxablePaise;
    final int cgstPaise = (gstPaise / 2.0).round();
    final int sgstPaise = gstPaise - cgstPaise;

    return TaxResult.fromPaise(
      taxablePaise: taxablePaise,
      gstPaise: gstPaise,
      totalPaise: totalPaise,
      cgstPaise: cgstPaise,
      sgstPaise: sgstPaise,
    );
  }

  /// Calculates TAX for an EXCLUSIVE taxable amount in integer paise using explicit half-up integer rounding.
  /// Formula: GST = Taxable * (Rate / 100)
  /// Total = Taxable + GST
  static TaxResult calculateExclusivePaise(int taxablePaise, double gstPercent) {
    final double effectiveGst = roundGstPercent(gstPercent);
    if (effectiveGst <= 0 || taxablePaise <= 0) {
      return TaxResult.fromPaise(
        taxablePaise: taxablePaise,
        gstPaise: 0,
        totalPaise: taxablePaise,
      );
    }

    final int gstPaise = ((taxablePaise * effectiveGst) / 100.0).round();
    final int totalPaise = taxablePaise + gstPaise;
    final int cgstPaise = (gstPaise / 2.0).round();
    final int sgstPaise = gstPaise - cgstPaise;

    return TaxResult.fromPaise(
      taxablePaise: taxablePaise,
      gstPaise: gstPaise,
      totalPaise: totalPaise,
      cgstPaise: cgstPaise,
      sgstPaise: sgstPaise,
    );
  }

  /// Calculates TAX from an INCLUSIVE total (e.g. MRP).
  /// Uses Integer Paise Model internally to eliminate rounding drift.
  static TaxResult calculateInclusive(double totalAmount, double gstPercent) {
    final int totalPaise = toPaise(totalAmount);
    return calculateInclusivePaise(totalPaise, gstPercent);
  }

  /// Calculates TAX for an EXCLUSIVE taxable amount (e.g. Purchase Rate).
  /// Uses Integer Paise Model internally to eliminate rounding drift.
  static TaxResult calculateExclusive(double taxableAmount, double gstPercent) {
    final int taxablePaise = toPaise(taxableAmount);
    return calculateExclusivePaise(taxablePaise, gstPercent);
  }
}