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
  /// Extracts 2-digit Indian state code from a GSTIN if present (e.g. "32AAAAA0000A1Z5" -> "32")
  static String getStateCode(String gstin) {
    final clean = gstin.trim();
    if (clean.length >= 2 && RegExp(r'^\d{2}').hasMatch(clean.substring(0, 2))) {
      return clean.substring(0, 2);
    }
    return "";
  }

  /// Determines whether a transaction is Interstate based on Supplier & Store GSTIN state codes
  static bool isInterstate(String companyGstin, String supplierGstin) {
    final companyState = getStateCode(companyGstin);
    final supplierState = getStateCode(supplierGstin);
    if (companyState.isNotEmpty && supplierState.isNotEmpty && companyState != supplierState) {
      return true;
    }
    return false;
  }

  /// Converts rupees (double) to integer paise cleanly
  static int toPaise(double rupees) => (rupees * 100).round();

  /// Converts paise to rupees string with fixed 2 decimal places
  static String toRupeesString(int paise) => (paise / 100.0).toStringAsFixed(2);

  /// Applies explicit half-up integer math rather than relying on floating-point epsilon paddings.
  static double round(double value, [int places = 2]) {
    final double mod = pow(10.0, places).toDouble();
    return (value * mod).round() / mod;
  }

  /// Rounds GST percentage to whole number if it is within near-integer floating point epsilon (0.01%).
  /// E.g., 17.99 -> 18.0, 4.99 -> 5.0, 18.00 -> 18.0, while preserving valid fractional rates like 12.1%, 5.05%.
  static double roundGstPercent(double gst) {
    if (gst <= 0) return 0.0;
    final double rounded = gst.roundToDouble();
    if ((gst - rounded).abs() <= 0.0101) {
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

  /// Calculates diluted landed cost per pack/strip including free quantity and tax
  static double calculateLandedCostPerPack({
    required double purchaseRate,
    required int qty,
    required int fQty,
    required double discPercent,
    required double gstPercent,
  }) {
    int totalPacks = qty + fQty;
    if (totalPacks <= 0) return purchaseRate;

    double gross = purchaseRate * qty;
    double discAmt = (gross * discPercent) / 100.0;
    double taxable = gross - discAmt;
    if (taxable < 0) taxable = 0.0;
    
    double gstAmt = (taxable * roundGstPercent(gstPercent)) / 100.0;
    double lineTotal = taxable + gstAmt;

    return lineTotal / totalPacks;
  }

  /// Calculates unit landed cost per individual tablet/loose unit
  static double calculateLooseUnitCost({
    required double landingCostPerPack,
    required int packSize,
  }) {
    int pSize = packSize > 0 ? packSize : 1;
    int basePaise = toPaise(landingCostPerPack);
    return ((basePaise / pSize).round()) / 100.0;
  }
}