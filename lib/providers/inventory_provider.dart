import 'package:flutter/foundation.dart';
import '../models/erp_models.dart';
import '../repositories/inventory_repository.dart';

class InventoryProvider extends ChangeNotifier {
  final InventoryRepository _repo;

  InventoryProvider({InventoryRepository? repo})
      : _repo = repo ?? InventoryRepository();

  double _totalInventoryValuation = 0.0;
  bool _isProcessing = false;

  double get totalInventoryValuation => _totalInventoryValuation;
  bool get isProcessing => _isProcessing;

  Future<void> refreshInventoryValuation() async {
    try {
      _totalInventoryValuation = await InventoryRepository.getTotalInventoryValuation();
      notifyListeners();
    } catch (e) {
      debugPrint("Error refreshing inventory valuation: $e");
    }
  }

  Future<List<Product>> getFefoBatches(String productId) async {
    return await InventoryRepository.getFefoBatches(productId);
  }

  Future<int> archiveZeroStockBatches() async {
    _isProcessing = true;
    notifyListeners();

    try {
      final count = await _repo.archiveZeroStockBatches();
      await refreshInventoryValuation();
      return count;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> updateBatchStock(String productId, String batchNumber, int newStock) async {
    await _repo.updateBatchStock(productId, batchNumber, newStock);
    notifyListeners();
  }
}
