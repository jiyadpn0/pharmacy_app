import 'dart:math';

/// Immutable model representing the breakdown of stock into full packs and loose units.
class PackBreakdown {
  final int fullPacks;
  final int looseUnits;
  final int totalLooseUnits;
  final int packing;

  const PackBreakdown({
    required this.fullPacks,
    required this.looseUnits,
    required this.totalLooseUnits,
    required this.packing,
  });

  @override
  String toString() => '$fullPacks Packs, $looseUnits Loose (Total: $totalLooseUnits)';
}

/// Helper class for all Full Pack ↔ Loose Unit conversions in Pharmacy ERP.
/// Ensures zero mathematical errors between Strips/Boxes and Tablets/Loose pieces.
class PackUnitConverter {
  /// Converts Full Packs, Loose Units, and Free Packs into total atomic Loose Units.
  static int toTotalLooseUnits({
    required int fullPacks,
    required int looseUnits,
    int freePacks = 0,
    required int packing,
  }) {
    final int safePack = packing > 0 ? packing : 1;
    final int safeFull = max(0, fullPacks);
    final int safeFree = max(0, freePacks);
    final int safeLoose = max(0, looseUnits);

    return ((safeFull + safeFree) * safePack) + safeLoose;
  }

  /// Converts Total Loose Units back into Full Packs + Loose Units breakdown.
  static PackBreakdown toPackBreakdown({
    required int totalLooseUnits,
    required int packing,
  }) {
    final int safePack = packing > 0 ? packing : 1;
    final int safeTotal = max(0, totalLooseUnits);

    final int full = safeTotal ~/ safePack;
    final int loose = safeTotal % safePack;

    return PackBreakdown(
      fullPacks: full,
      looseUnits: loose,
      totalLooseUnits: safeTotal,
      packing: safePack,
    );
  }

  /// Calculates exact price per single Loose Unit (e.g. Price per Tablet from Price per Strip).
  static double ratePerLooseUnit({
    required double packRate,
    required int packing,
  }) {
    final int safePack = packing > 0 ? packing : 1;
    if (packRate <= 0) return 0.0;
    return packRate / safePack;
  }

  /// Calculates Price per Full Pack from Price per Loose Unit.
  static double packRateFromLooseRate({
    required double looseRate,
    required int packing,
  }) {
    final int safePack = packing > 0 ? packing : 1;
    if (looseRate <= 0) return 0.0;
    return looseRate * safePack;
  }

  /// Formats user-friendly stock string across all UI screens.
  /// Example:
  ///   packing = 10, total = 24 -> "2 Strips, 4 Tabs (24 Tabs)"
  ///   packing = 10, total = 20 -> "2 Strips (20 Tabs)"
  ///   packing = 1,  total = 24 -> "24 Tabs"
  static String formatStockDisplay({
    required int totalLooseUnits,
    required int packing,
    String packUnit = 'Strip',
    String looseUnit = 'Tab',
  }) {
    final int safePack = packing > 0 ? packing : 1;
    if (safePack <= 1) {
      return '$totalLooseUnits $looseUnit${totalLooseUnits == 1 ? '' : 's'}';
    }

    final breakdown = toPackBreakdown(totalLooseUnits: totalLooseUnits, packing: safePack);
    final int full = breakdown.fullPacks;
    final int loose = breakdown.looseUnits;

    final String pUnitStr = '$full $packUnit${full == 1 ? '' : 's'}';
    final String lUnitStr = '$loose $looseUnit${loose == 1 ? '' : 's'}';

    if (full > 0 && loose > 0) {
      return '$pUnitStr, $lUnitStr ($totalLooseUnits $looseUnit${totalLooseUnits == 1 ? '' : 's'})';
    } else if (full > 0) {
      return '$pUnitStr ($totalLooseUnits $looseUnit${totalLooseUnits == 1 ? '' : 's'})';
    } else {
      return '$lUnitStr ($totalLooseUnits $looseUnit${totalLooseUnits == 1 ? '' : 's'})';
    }
  }
}
