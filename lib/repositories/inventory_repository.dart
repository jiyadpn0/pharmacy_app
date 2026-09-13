import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import '../providers/pharmacy_provider.dart';

class InventoryRepository {
  /// Fetches active stock batches for a product sorted by FEFO (First-Expire, First-Out)
  static Future<List<Product>> getFefoBatches(
    String productId, {
    PharmacyProvider? pharmacyProvider,
  }) async {
    if (kIsWeb) {
      if (pharmacyProvider == null) return [];
      return pharmacyProvider.productMaster
          .where((p) => (p.id == productId || p.name == productId) && p.stock > 0)
          .toList();
    }

    try {
      final db = await DbHelper.instance.database;

      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT b.*, p.name, p.hsn_code, p.category_id, p.packing, p.schedule, p.patent, p.generic_name
        FROM stock_batches b
        JOIN product_master p ON b.product_id = p.id
        WHERE b.product_id = ? AND b.current_stock > 0
        ORDER BY 
          CASE 
            WHEN b.expiry_date LIKE '%/%' THEN 
              (substr(b.expiry_date, 4, 2) || '-' || substr(b.expiry_date, 1, 2) || '-01')
            ELSE '2099-12-31' 
          END ASC
      ''', [productId]);

      return maps.map((map) => Product.fromMap(map)).toList();
    } catch (e) {
      debugPrint("Error fetching FEFO batches for product $productId: $e");
      if (pharmacyProvider != null) {
        return pharmacyProvider.productMaster
            .where((p) => (p.id == productId || p.name == productId) && p.stock > 0)
            .toList();
      }
      return [];
    }
  }

  /// Calculates total inventory valuation server-side without loading raw lists into RAM
  static Future<double> getTotalInventoryValuation({
    PharmacyProvider? pharmacyProvider,
  }) async {
    if (kIsWeb) {
      if (pharmacyProvider == null) return 0.0;
      double total = 0.0;
      for (var p in pharmacyProvider.productMaster) {
        if (p.stock > 0) {
          final pack = p.packSize > 0 ? p.packSize : 1;
          total += (p.stock / pack) * p.purchaseRate;
        }
      }
      return total;
    }

    try {
      final db = await DbHelper.instance.database;
      final result = await db.rawQuery('''
        SELECT SUM((CAST(b.current_stock AS REAL) / NULLIF(b.packing, 0)) * b.purchase_rate) as total_val
        FROM stock_batches b
        WHERE b.current_stock > 0
      ''');

      return (result.first['total_val'] as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      debugPrint("Error calculating total inventory valuation: $e");
      if (pharmacyProvider != null) {
        double total = 0.0;
        for (var p in pharmacyProvider.productMaster) {
          if (p.stock > 0) {
            final pack = p.packSize > 0 ? p.packSize : 1;
            total += (p.stock / pack) * p.purchaseRate;
          }
        }
        return total;
      }
      return 0.0;
    }
  }
}
