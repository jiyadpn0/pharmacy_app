import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' as sql;
import '../database/db_helper.dart';
import '../models/erp_models.dart';
import '../repositories/stock_repository.dart';
import '../utils/pack_unit_converter.dart';

/// Model representing a single batch line allocation result.
class BatchAllocationResult {
  final BatchMaster batch;
  final int allocatedLooseQty;
  final int fullPacksAllocated;
  final int looseUnitsAllocated;

  BatchAllocationResult({
    required this.batch,
    required this.allocatedLooseQty,
    required this.fullPacksAllocated,
    required this.looseUnitsAllocated,
  });

  double get purchaseRate => batch.purchaseRate;
  double get mrp => batch.mrp;
  double get saleRate => batch.saleRate;
  String get batchNumber => batch.batchNumber;
  String get expiryDate => batch.expiryDate;
  String get batchId => batch.batchId;
}

/// Service providing ACID-compliant stock movement operations, FEFO batch allocations, and stock safety locks.
class StockService {
  static final StockService instance = StockService._();
  StockService._();
  factory StockService() => instance;

  final StockRepository _repository = StockRepository.instance;

  /// Process Stock Addition (Purchase, Sales Return, Stock Adjustment (+)).
  /// Guarantees that a batch is created or found and a ledger entry is recorded atomically.
  Future<BatchMaster> processStockIn({
    required String productId,
    required String batchNumber,
    required String expiryDate,
    required int totalLooseQty,
    required String voucherType, // 'PURCHASE', 'SALES_RETURN', 'ADJUSTMENT_IN', 'OPENING_STOCK'
    required String voucherNo,
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
    String remarks = '',
    String userId = 'Admin',
    String financialYear = '',
    sql.Transaction? txn,
  }) async {
    if (totalLooseQty <= 0) {
      throw ArgumentError("Stock In quantity must be greater than 0.");
    }

    Future<BatchMaster> executeInTxn(sql.Transaction activeTxn) async {
      final batch = await _repository.findOrCreateBatch(
        productId: productId,
        batchNumber: batchNumber,
        expiryDate: expiryDate,
        mfgDate: mfgDate,
        supplierId: supplierId,
        supplierName: supplierName,
        packing: packing,
        purchaseRate: purchaseRate,
        landingCost: landingCost,
        mrp: mrp,
        saleRate: saleRate,
        gstPercent: gstPercent,
        rack: rack,
        txn: activeTxn,
      );

      final ledgerEntry = StockLedgerEntry(
        batchId: batch.batchId,
        productId: productId,
        voucherType: voucherType,
        voucherNo: voucherNo,
        qtyIn: totalLooseQty,
        qtyOut: 0,
        purchaseRate: purchaseRate > 0 ? purchaseRate : batch.purchaseRate,
        mrp: mrp > 0 ? mrp : batch.mrp,
        supplierName: supplierName.isNotEmpty ? supplierName : batch.supplierName,
        remarks: remarks,
        userId: userId,
        financialYear: financialYear,
      );

      await _repository.recordLedgerMovement(ledgerEntry, txn: activeTxn);
      final int updatedLiveStock = await _repository.getLiveStockForBatch(batch.batchId, txn: activeTxn);
      return BatchMaster.fromMap(batch.toMap(), currentLooseStock: updatedLiveStock);
    }

    if (txn != null) {
      return await executeInTxn(txn);
    } else {
      final db = await DbHelper.instance.database;
      BatchMaster? resultBatch;
      await db.transaction((activeTxn) async {
        resultBatch = await executeInTxn(activeTxn);
      });
      return resultBatch!;
    }
  }

  /// Process Stock Outflow (Sales, Purchase Return, Damage, Stock Adjustment (-)).
  /// Enforces Strict Stock Availability Lock. Throws exception if stock is insufficient.
  Future<void> processStockOut({
    required String batchId,
    required String productId,
    required int totalLooseQty,
    required String voucherType, // 'SALE', 'PURCHASE_RETURN', 'DAMAGE', 'ADJUSTMENT_OUT'
    required String voucherNo,
    double purchaseRate = 0.0,
    double mrp = 0.0,
    String supplierName = '',
    String remarks = '',
    String userId = 'Admin',
    String financialYear = '',
    bool allowNegative = false,
    sql.Transaction? txn,
  }) async {
    if (totalLooseQty <= 0) {
      throw ArgumentError("Stock Out quantity must be greater than 0.");
    }

    Future<void> executeOutTxn(sql.Transaction activeTxn) async {
      final int liveStock = await _repository.getLiveStockForBatch(batchId, txn: activeTxn);

      if (!allowNegative && liveStock < totalLooseQty) {
        final batch = await _repository.getBatchById(batchId, txn: activeTxn);
        final String bName = batch?.batchNumber ?? batchId;
        final int shortfall = totalLooseQty - liveStock;
        throw Exception(
          "STOCK SHORTFALL WARNING!\n\n"
          "Cannot deduct $totalLooseQty units from Batch '$bName'.\n"
          "Available Stock: $liveStock loose units.\n"
          "Shortfall: $shortfall loose units."
        );
      }

      final ledgerEntry = StockLedgerEntry(
        batchId: batchId,
        productId: productId,
        voucherType: voucherType,
        voucherNo: voucherNo,
        qtyIn: 0,
        qtyOut: totalLooseQty,
        purchaseRate: purchaseRate,
        mrp: mrp,
        supplierName: supplierName,
        remarks: remarks,
        userId: userId,
        financialYear: financialYear,
      );

      await _repository.recordLedgerMovement(ledgerEntry, txn: activeTxn);
    }

    if (txn != null) {
      await executeOutTxn(txn);
    } else {
      final db = await DbHelper.instance.database;
      await db.transaction((activeTxn) async {
        await executeOutTxn(activeTxn);
      });
    }
  }

  /// Automatically allocates required quantity across available batches in store.
  /// Handles multi-batch line splitting when stock spans across multiple batches.
  Future<List<BatchAllocationResult>> allocateAvailableBatches({
    required String productId,
    required int requiredLooseQty,
    sql.Transaction? txn,
  }) async {
    if (requiredLooseQty <= 0) return [];

    final List<BatchMaster> availableBatches = await _repository.getAvailableBatchesForProduct(productId, txn: txn);
    List<BatchAllocationResult> allocations = [];
    int remainingToAllocate = requiredLooseQty;

    for (var batch in availableBatches) {
      if (remainingToAllocate <= 0) break;
      int availableInBatch = batch.currentLooseStock;
      if (availableInBatch <= 0) continue;

      int allocateFromThisBatch = (remainingToAllocate <= availableInBatch)
          ? remainingToAllocate
          : availableInBatch;

      final breakdown = PackUnitConverter.toPackBreakdown(
        totalLooseUnits: allocateFromThisBatch,
        packing: batch.packing,
      );

      allocations.add(BatchAllocationResult(
        batch: batch,
        allocatedLooseQty: allocateFromThisBatch,
        fullPacksAllocated: breakdown.fullPacks,
        looseUnitsAllocated: breakdown.looseUnits,
      ));

      remainingToAllocate -= allocateFromThisBatch;
    }

    if (remainingToAllocate > 0) {
      final int totalAvailable = requiredLooseQty - remainingToAllocate;
      debugPrint("FEFO Allocation Note: Product $productId requested $requiredLooseQty, but only $totalAvailable was allocated across active batches.");
    }

    return allocations;
  }
}
