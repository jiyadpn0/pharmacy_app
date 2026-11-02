import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/db_helper.dart';
import '../services/supabase_sync_service.dart';
import '../utils/app_logger.dart';

/// Provider handling purchase invoices, inward goods receipts (GRN), purchase returns, and supplier purchase records.
class PurchaseProvider extends ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Generates the next sequential Purchase Entry Number (e.g., PUR-2026-0001)
  Future<String> getNextPurchaseEntryNo() async {
    final db = await DbHelper.instance.database;
    final String currentYear = DateTime.now().year.toString();

    final result = await db.rawQuery('''
      SELECT entry_no FROM purchase_entries 
      WHERE entry_no LIKE 'PUR-$currentYear-%' 
      ORDER BY id DESC LIMIT 1
    ''');

    if (result.isEmpty) {
      return "PUR-$currentYear-0001";
    }

    final lastNo = result.first['entry_no'].toString();
    final parts = lastNo.split('-');
    if (parts.length == 3) {
      final seq = int.tryParse(parts[2]) ?? 0;
      final nextSeq = (seq + 1).toString().padLeft(4, '0');
      return "PUR-$currentYear-$nextSeq";
    }

    return "PUR-$currentYear-0001";
  }

  /// Generates the next sequential Purchase Return Entry Number (e.g., PR-2026-0001)
  Future<String> getNextPurchaseReturnEntryNo() async {
    final db = await DbHelper.instance.database;
    final String currentYear = DateTime.now().year.toString();

    final result = await db.rawQuery('''
      SELECT entry_no FROM purchase_returns 
      WHERE entry_no LIKE 'PR-$currentYear-%' 
      ORDER BY id DESC LIMIT 1
    ''');

    if (result.isEmpty) {
      return "PR-$currentYear-0001";
    }

    final lastNo = result.first['entry_no'].toString();
    final parts = lastNo.split('-');
    if (parts.length == 3) {
      final seq = int.tryParse(parts[2]) ?? 0;
      final nextSeq = (seq + 1).toString().padLeft(4, '0');
      return "PR-$currentYear-$nextSeq";
    }

    return "PR-$currentYear-0001";
  }

  /// Fetches Purchase Entries within a given date range
  Future<List<Map<String, dynamic>>> fetchPurchasesInDateRange(
    DateTime from,
    DateTime to, {
    bool loadItems = true,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await DbHelper.instance.database;
    String fromStr = DateFormat('yyyy-MM-dd 00:00:00').format(from);
    String toStr = DateFormat('yyyy-MM-dd 23:59:59').format(to);

    final rows = await db.query(
      'purchase_entries',
      where: 'date BETWEEN ? AND ?',
      whereArgs: [fromStr, toStr],
      orderBy: 'date DESC',
      limit: limit,
      offset: offset,
    );

    List<Map<String, dynamic>> list = [];
    for (var r in rows) {
      final map = Map<String, dynamic>.from(r);
      if (loadItems) {
        final itemRows = await db.query(
          'purchase_items',
          where: 'entry_no = ?',
          whereArgs: [map['entry_no']],
        );
        map['items'] = itemRows;
      }
      list.add(map);
    }

    return list;
  }

  /// Fetches Purchase Returns within a given date range
  Future<List<Map<String, dynamic>>> fetchPurchaseReturnsInDateRange(
    DateTime from,
    DateTime to, {
    bool loadItems = true,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await DbHelper.instance.database;
    String fromStr = DateFormat('yyyy-MM-dd 00:00:00').format(from);
    String toStr = DateFormat('yyyy-MM-dd 23:59:59').format(to);

    final rows = await db.query(
      'purchase_returns',
      where: 'date BETWEEN ? AND ?',
      whereArgs: [fromStr, toStr],
      orderBy: 'date DESC',
      limit: limit,
      offset: offset,
    );

    List<Map<String, dynamic>> list = [];
    for (var r in rows) {
      final map = Map<String, dynamic>.from(r);
      if (loadItems) {
        final itemRows = await db.query(
          'purchase_return_items',
          where: 'entry_no = ?',
          whereArgs: [map['entry_no']],
        );
        map['items'] = itemRows;
      }
      list.add(map);
    }

    return list;
  }

  /// Saves a purchase inward invoice with atomic database transaction
  Future<String> savePurchase(Map<String, dynamic> purchaseData, List<Map<String, dynamic>> items, {bool isEditMode = false}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final db = await DbHelper.instance.database;
      return await db.transaction((txn) async {
        String entryNo = purchaseData['entry_no']?.toString() ?? '';
        if (entryNo.isEmpty) {
          entryNo = await getNextPurchaseEntryNo();
          purchaseData['entry_no'] = entryNo;
        }

        if (isEditMode) {
          await txn.update(
            'purchase_entries',
            purchaseData,
            where: 'entry_no = ?',
            whereArgs: [entryNo],
          );
          await txn.delete(
            'purchase_items',
            where: 'entry_no = ?',
            whereArgs: [entryNo],
          );
        } else {
          await txn.insert('purchase_entries', purchaseData);
        }

        for (var item in items) {
          final itemMap = Map<String, dynamic>.from(item);
          itemMap['entry_no'] = entryNo;
          await txn.insert('purchase_items', itemMap);
        }

        AppLogger.instance.info('PURCHASE', 'Purchase invoice $entryNo saved successfully');
        try {
          SupabaseSyncService.instance.triggerInstantSync();
        } catch (_) {}
        return entryNo;
      });
    } catch (e, stack) {
      AppLogger.instance.error('PURCHASE', 'Failed to save purchase entry', error: e, stackTrace: stack);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
