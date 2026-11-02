import 'package:sqflite/sqflite.dart' as sql;
import '../database/db_helper.dart';
import '../models/erp_models.dart';

/// Repository responsible for direct SQLite queries on [batch_master] and [stock_ledger].
class StockRepository {
  static final StockRepository instance = StockRepository._();
  StockRepository._();
  factory StockRepository() => instance;

  Future<sql.Database> get _db async => await DbHelper.instance.database;

  /// Calculates current live stock in loose units for a given [batchId].
  /// Live Stock = SUM(qty_in) - SUM(qty_out) from stock_ledger.
  Future<int> getLiveStockForBatch(String batchId, {sql.Transaction? txn}) async {
    if (batchId.isEmpty) return 0;
    final executor = txn ?? await _db;

    final result = await executor.rawQuery('''
      SELECT IFNULL(SUM(qty_in), 0) - IFNULL(SUM(qty_out), 0) as live_stock
      FROM stock_ledger
      WHERE batch_id = ?
    ''', [batchId]);

    if (result.isNotEmpty && result.first['live_stock'] != null) {
      return (result.first['live_stock'] as num).toInt();
    }
    return 0;
  }

  /// Fetches a [BatchMaster] by its unique [batchId].
  Future<BatchMaster?> getBatchById(String batchId, {sql.Transaction? txn}) async {
    if (batchId.isEmpty) return null;
    final executor = txn ?? await _db;

    final rows = await executor.query(
      'batch_master',
      where: 'batch_id = ?',
      whereArgs: [batchId],
      limit: 1,
    );

    if (rows.isNotEmpty) {
      final int stock = await getLiveStockForBatch(batchId, txn: txn);
      return BatchMaster.fromMap(rows.first, currentLooseStock: stock);
    }
    return null;
  }

  /// Finds an existing batch matching [productId], [batchNumber], and optional [expiryDate], [purchaseRate], [mrp].
  /// If not found, creates a new [batch_master] entry with a unique [batch_id].
  Future<BatchMaster> findOrCreateBatch({
    required String productId,
    required String batchNumber,
    required String expiryDate,
    String mfgDate = '',
    String supplierId = '',
    String supplierName = '',
    int packing = 1,
    double purchaseRate = 0.0,
    double landingCost = 0.0,
    double mrp = 0.0,
    double saleRate = 0.0,
    double gstPercent = 12.0,
    String rack = '',
    sql.Transaction? txn,
  }) async {
    final executor = txn ?? await _db;
    final String cleanBatch = batchNumber.trim();
    final String cleanProdId = productId.trim();

    // Check for existing matching batch
    final existing = await executor.rawQuery('''
      SELECT * FROM batch_master
      WHERE product_id = ? 
        AND LOWER(TRIM(batch_number)) = LOWER(TRIM(?))
        AND (expiry_date = ? OR expiry_date = '' OR ? = '')
        AND ABS(purchase_rate - ?) < 0.01
        AND ABS(mrp - ?) < 0.01
      ORDER BY created_at DESC LIMIT 1
    ''', [cleanProdId, cleanBatch, expiryDate, expiryDate, purchaseRate, mrp]);

    if (existing.isNotEmpty) {
      final String existingId = existing.first['batch_id'].toString();
      final int stock = await getLiveStockForBatch(existingId, txn: txn);
      return BatchMaster.fromMap(existing.first, currentLooseStock: stock);
    }

    // Secondary fallback matching by product_id + batch_number
    final existingBatchOnly = await executor.rawQuery('''
      SELECT * FROM batch_master
      WHERE product_id = ? 
        AND LOWER(TRIM(batch_number)) = LOWER(TRIM(?))
      ORDER BY created_at DESC LIMIT 1
    ''', [cleanProdId, cleanBatch]);

    if (existingBatchOnly.isNotEmpty) {
      final String existingId = existingBatchOnly.first['batch_id'].toString();
      final int stock = await getLiveStockForBatch(existingId, txn: txn);
      return BatchMaster.fromMap(existingBatchOnly.first, currentLooseStock: stock);
    }

    // Create a new batch
    final String newBatchId = "BAT_${DateTime.now().microsecondsSinceEpoch}";
    final newBatch = BatchMaster(
      batchId: newBatchId,
      productId: cleanProdId,
      batchNumber: cleanBatch,
      expiryDate: expiryDate,
      mfgDate: mfgDate,
      supplierId: supplierId,
      supplierName: supplierName,
      packing: packing > 0 ? packing : 1,
      purchaseRate: purchaseRate,
      landingCost: landingCost > 0 ? landingCost : purchaseRate,
      mrp: mrp,
      saleRate: saleRate > 0 ? saleRate : mrp,
      gstPercent: gstPercent,
      rack: rack,
    );

    await executor.insert('batch_master', newBatch.toMap());
    return newBatch;
  }

  /// Returns all active available batches for a product ordered by FEFO (First-Expiry-First-Out).
  /// Only returns batches with positive live stock (> 0).
  Future<List<BatchMaster>> getAvailableBatchesForProduct(String productId, {sql.Transaction? txn}) async {
    if (productId.isEmpty) return [];
    final executor = txn ?? await _db;

    final rows = await executor.rawQuery('''
      SELECT bm.*, 
             (IFNULL(SUM(sl.qty_in), 0) - IFNULL(SUM(sl.qty_out), 0)) as live_stock
      FROM batch_master bm
      LEFT JOIN stock_ledger sl ON bm.batch_id = sl.batch_id
      WHERE bm.product_id = ? AND bm.is_active = 1
      GROUP BY bm.batch_id
      HAVING live_stock > 0
      ORDER BY 
        CASE 
          WHEN bm.expiry_date LIKE '%/%' THEN 
            CAST((CASE WHEN length(substr(bm.expiry_date, instr(bm.expiry_date, '/') + 1)) <= 2 
                       THEN '20' || substr(bm.expiry_date, instr(bm.expiry_date, '/') + 1) 
                       ELSE substr(bm.expiry_date, instr(bm.expiry_date, '/') + 1) END) AS INTEGER) * 100 
            + CAST(substr(bm.expiry_date, 1, instr(bm.expiry_date, '/') - 1) AS INTEGER)
          ELSE 999999 
        END ASC,
        bm.expiry_date ASC
    ''', [productId]);

    List<BatchMaster> batches = [];
    for (var r in rows) {
      int liveStock = (r['live_stock'] as num?)?.toInt() ?? 0;
      batches.add(BatchMaster.fromMap(r, currentLooseStock: liveStock));
    }
    return batches;
  }

  /// Inserts an immutable movement entry into [stock_ledger].
  Future<int> recordLedgerMovement(StockLedgerEntry entry, {sql.Transaction? txn}) async {
    final executor = txn ?? await _db;
    return await executor.insert('stock_ledger', entry.toMap());
  }

  /// Fetches complete movement history for a batch from birth to end.
  Future<List<StockLedgerEntry>> getBatchLedgerHistory(String batchId) async {
    if (batchId.isEmpty) return [];
    final db = await _db;

    final rows = await db.query(
      'stock_ledger',
      where: 'batch_id = ?',
      whereArgs: [batchId],
      orderBy: 'timestamp ASC, ledger_id ASC',
    );

    return rows.map((r) => StockLedgerEntry.fromMap(r)).toList();
  }

  /// Returns total consolidated live stock across all batches for a given [productId].
  Future<int> getProductConsolidatedStock(String productId, {sql.Transaction? txn}) async {
    if (productId.isEmpty) return 0;
    final executor = txn ?? await _db;

    final result = await executor.rawQuery('''
      SELECT IFNULL(SUM(qty_in), 0) - IFNULL(SUM(qty_out), 0) as total_stock
      FROM stock_ledger
      WHERE product_id = ?
    ''', [productId]);

    if (result.isNotEmpty && result.first['total_stock'] != null) {
      return (result.first['total_stock'] as num).toInt();
    }
    return 0;
  }
}
