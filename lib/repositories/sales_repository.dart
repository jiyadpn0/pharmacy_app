import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import '../providers/pharmacy_provider.dart';

class SalesRepository {
  /// Fetches a paginated slice of sales invoices with server-side sorting
  static Future<List<SaleInvoice>> getPagedSalesInvoices({
    int limit = 50,
    int offset = 0,
    PharmacyProvider? pharmacyProvider,
  }) async {
    if (kIsWeb) {
      if (pharmacyProvider == null) return [];
      var list = pharmacyProvider.sales.where((s) => !s.isDeleted).toList();
      if (offset >= list.length) return [];
      return list.skip(offset).take(limit).toList();
    }

    try {
      final db = await DbHelper.instance.database;
      final List<Map<String, dynamic>> maps = await db.query(
        'sales_invoices',
        where: 'IFNULL(is_deleted, 0) = 0',
        orderBy: 'date DESC',
        limit: limit,
        offset: offset,
      );

      return maps.map((map) => SaleInvoice(
        entryNo: map['entry_no']?.toString() ?? '',
        date: DateTime.tryParse(map['date']?.toString() ?? '') ?? DateTime.now(),
        customerAcc: map['customer_acc']?.toString() ?? 'Cash',
        patient: map['patient']?.toString() ?? 'General',
        mobile: map['mobile']?.toString() ?? '',
        doctor: map['doctor']?.toString() ?? 'Unknown',
        grandTotal: (map['grand_total'] as num?)?.toDouble() ?? 0.0,
        items: [], // Loaded lazily on demand
      )).toList();
    } catch (e) {
      debugPrint("Error fetching paged sales invoices: $e");
      if (pharmacyProvider != null) {
        var list = pharmacyProvider.sales.where((s) => !s.isDeleted).toList();
        if (offset >= list.length) return [];
        return list.skip(offset).take(limit).toList();
      }
      return [];
    }
  }
}
