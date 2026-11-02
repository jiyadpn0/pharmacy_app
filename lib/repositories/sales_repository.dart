import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';

class SalesRepository {
  static final SalesRepository instance = SalesRepository._internal();
  SalesRepository._internal();

  Future<Database> get _db async => await DbHelper.instance.database;

  /// Fetches total sales count for a given date range
  Future<double> getTotalSalesAmount(DateTime fromDate, DateTime toDate) async {
    final db = await _db;
    final fromStr = fromDate.toIso8601String().split('T')[0];
    final toStr = toDate.toIso8601String().split('T')[0];

    const query = '''
      SELECT SUM(IFNULL(grand_total, IFNULL(total_amount, 0.0))) as total
      FROM sales_invoices
      WHERE date >= ? AND date <= ? AND (is_deleted = 0 OR is_deleted IS NULL)
    ''';

    final result = await db.rawQuery(query, [fromStr, toStr]);
    if (result.isNotEmpty && result.first['total'] != null) {
      return (result.first['total'] as num).toDouble();
    }
    return 0.0;
  }
}
