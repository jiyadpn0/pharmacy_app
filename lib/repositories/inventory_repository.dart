import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import '../models/erp_models.dart';

class InventoryRepository {
  InventoryRepository();

  Future<Database> get _db async => await DbHelper.instance.database;

  /// Fetches total stock asset valuation at landing cost
  Future<double> getTotalPurchaseValuation() async {
    final db = await _db;
    const query = '''
      SELECT IFNULL(SUM(b.current_stock * (
        CASE 
          WHEN IFNULL(b.landing_cost, 0.0) > 0 THEN b.landing_cost 
          ELSE IFNULL(b.purchase_rate, 0.0) 
        END / CASE WHEN IFNULL(p.packing, 1) > 0 THEN p.packing ELSE 1 END
      )), 0.0) as total_val
      FROM stock_batches b
      JOIN product_master p ON b.product_id = p.id
      WHERE b.current_stock > 0
    ''';

    final result = await db.rawQuery(query);
    if (result.isNotEmpty && result.first['total_val'] != null) {
      return (result.first['total_val'] as num).toDouble();
    }
    return 0.0;
  }

  static Future<double> getTotalInventoryValuation() async {
    return await InventoryRepository().getTotalPurchaseValuation();
  }

  static Future<List<Product>> getFefoBatches(String productId) async {
    final db = await DbHelper.instance.database;
    const query = '''
      SELECT product_id, batch_number, expiry_date, current_stock, purchase_rate, mrp
      FROM stock_batches
      WHERE product_id = ? AND current_stock > 0
      ORDER BY expiry_date ASC
    ''';

    final rows = await db.rawQuery(query, [productId]);
    List<Product> products = [];
    for (var r in rows) {
      products.add(Product(
        id: r['product_id']?.toString() ?? '',
        name: r['batch_number']?.toString() ?? '',
        stock: (r['current_stock'] as num?)?.toInt() ?? 0,
        mrp: (r['mrp'] as num?)?.toDouble() ?? 0.0,
        purchaseRate: (r['purchase_rate'] as num?)?.toDouble() ?? 0.0,
      ));
    }
    return products;
  }

  Future<int> archiveZeroStockBatches() async {
    final db = await _db;
    return await db.delete('stock_batches', where: 'current_stock <= 0');
  }

  Future<void> updateBatchStock(String productId, String batchNumber, int newStock) async {
    final db = await _db;
    await db.update(
      'stock_batches',
      {'current_stock': newStock},
      where: 'product_id = ? AND batch_number = ?',
      whereArgs: [productId, batchNumber],
    );
  }
}
