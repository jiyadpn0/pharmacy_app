import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';

enum ExpiryRiskLevel { expired, critical30, warning60, safe }

class ExpiryBatchItem {
  final String productId;
  final String productName;
  final String batchNumber;
  final String expiryDateStr;
  final DateTime? expiryDate;
  final double currentStock;
  final String supplierName;
  final ExpiryRiskLevel riskLevel;
  final bool isQuarantined;

  ExpiryBatchItem({
    required this.productId,
    required this.productName,
    required this.batchNumber,
    required this.expiryDateStr,
    this.expiryDate,
    required this.currentStock,
    required this.supplierName,
    required this.riskLevel,
    this.isQuarantined = false,
  });
}

class ExpiryAlertService {
  static final ExpiryAlertService instance = ExpiryAlertService._internal();
  ExpiryAlertService._internal();

  /// Gets the configured quarantine threshold in days (default: 60)
  Future<int> getQuarantineThresholdDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('expiry_quarantine_threshold_days') ?? 60;
  }

  /// Sets the configured quarantine threshold in days
  Future<void> setQuarantineThresholdDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('expiry_quarantine_threshold_days', days);
  }

  /// Fetches expiring inventory batches categorized by 30/60/90-day risk windows
  Future<List<ExpiryBatchItem>> getExpiringBatches({int? daysThreshold}) async {
    final db = await DbHelper.instance.database;
    final now = DateTime.now();
    final threshold = daysThreshold ?? await getQuarantineThresholdDays();

    const query = '''
      SELECT 
        sb.product_id,
        p.name as product_name,
        sb.batch_number,
        sb.expiry_date,
        sb.current_stock,
        sb.supplier_name
      FROM stock_batches sb
      JOIN product_master p ON sb.product_id = p.id
      WHERE sb.current_stock > 0 AND sb.expiry_date IS NOT NULL AND sb.expiry_date != ''
    ''';

    final rows = await db.rawQuery(query);
    List<ExpiryBatchItem> results = [];

    for (var r in rows) {
      final expStr = r['expiry_date']?.toString() ?? '';
      DateTime? expDate = DateTime.tryParse(expStr);

      if (expDate == null) continue;

      final differenceInDays = expDate.difference(now).inDays;

      if (differenceInDays <= threshold) {
        ExpiryRiskLevel risk;
        if (differenceInDays <= 0) {
          risk = ExpiryRiskLevel.expired;
        } else if (differenceInDays <= 30) {
          risk = ExpiryRiskLevel.critical30;
        } else if (differenceInDays <= 60) {
          risk = ExpiryRiskLevel.warning60;
        } else {
          risk = ExpiryRiskLevel.safe;
        }

        final isQuarantined = differenceInDays <= threshold;

        results.add(ExpiryBatchItem(
          productId: r['product_id']?.toString() ?? '',
          productName: r['product_name']?.toString() ?? 'Unknown',
          batchNumber: r['batch_number']?.toString() ?? '',
          expiryDateStr: expStr,
          expiryDate: expDate,
          currentStock: (r['current_stock'] as num?)?.toDouble() ?? 0.0,
          supplierName: r['supplier_name']?.toString() ?? 'Unassigned',
          riskLevel: risk,
          isQuarantined: isQuarantined,
        ));
      }
    }

    results.sort((a, b) => (a.expiryDate ?? now).compareTo(b.expiryDate ?? now));
    return results;
  }
}
