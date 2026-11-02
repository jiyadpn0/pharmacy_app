import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import '../models/erp_models.dart';
import '../services/supabase_sync_service.dart';
import '../utils/app_logger.dart';

/// Provider handling sales invoice processing, draft saving, sale returns, and sales transactions.
class SalesProvider extends ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  final String _searchQuery = '';
  String get searchQuery => _searchQuery;

  final List<SaleInvoice> _recentSales = [];
  List<SaleInvoice> get recentSales => List.unmodifiable(_recentSales);

  /// Generates the next sequential Sales Entry Number (e.g., INV-2026-0001)
  Future<String> getNextSaleEntryNo() async {
    final db = await DbHelper.instance.database;
    final String currentYear = DateTime.now().year.toString();

    final result = await db.rawQuery('''
      SELECT entry_no FROM sales_invoices 
      WHERE entry_no LIKE 'INV-$currentYear-%' 
      ORDER BY id DESC LIMIT 1
    ''');

    if (result.isEmpty) {
      return "INV-$currentYear-0001";
    }

    final lastNo = result.first['entry_no'].toString();
    final parts = lastNo.split('-');
    if (parts.length == 3) {
      final seq = int.tryParse(parts[2]) ?? 0;
      final nextSeq = (seq + 1).toString().padLeft(4, '0');
      return "INV-$currentYear-$nextSeq";
    }

    return "INV-$currentYear-0001";
  }

  /// Generates the next sequential Sale Return Entry Number (e.g., SR-2026-0001)
  Future<String> getNextSaleReturnEntryNo() async {
    final db = await DbHelper.instance.database;
    final String currentYear = DateTime.now().year.toString();

    final result = await db.rawQuery('''
      SELECT return_no FROM sales_returns 
      WHERE return_no LIKE 'SR-$currentYear-%' 
      ORDER BY id DESC LIMIT 1
    ''');

    if (result.isEmpty) {
      return "SR-$currentYear-0001";
    }

    final lastNo = result.first['return_no'].toString();
    final parts = lastNo.split('-');
    if (parts.length == 3) {
      final seq = int.tryParse(parts[2]) ?? 0;
      final nextSeq = (seq + 1).toString().padLeft(4, '0');
      return "SR-$currentYear-$nextSeq";
    }

    return "SR-$currentYear-0001";
  }

  /// Fetches a specific Sales Invoice by ID/EntryNo
  Future<SaleInvoice?> getSaleInvoiceById(String invoiceNo) async {
    final db = await DbHelper.instance.database;
    final rows = await db.query(
      'sales_invoices',
      where: 'entry_no = ? AND is_deleted = 0',
      whereArgs: [invoiceNo],
    );

    if (rows.isEmpty) return null;
    final invoiceMap = Map<String, dynamic>.from(rows.first);

    final itemRows = await db.query(
      'sales_items',
      where: 'invoice_no = ?',
      whereArgs: [invoiceNo],
    );

    List<SaleItem> items = [];
    for (var r in itemRows) {
      final itemMap = Map<String, dynamic>.from(r);
      items.add(SaleItem.fromMap(itemMap));
    }

    invoiceMap['items'] = items;
    return SaleInvoice.fromMap(invoiceMap);
  }

  /// Fetches Sales Invoices within a given date range
  Future<List<SaleInvoice>> fetchSalesInDateRange(
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
      'sales_invoices',
      where: 'date BETWEEN ? AND ? AND is_deleted = 0',
      whereArgs: [fromStr, toStr],
      orderBy: 'date DESC',
      limit: limit,
      offset: offset,
    );

    List<SaleInvoice> list = [];
    for (var r in rows) {
      final map = Map<String, dynamic>.from(r);
      if (loadItems) {
        final itemRows = await db.query(
          'sales_items',
          where: 'invoice_no = ?',
          whereArgs: [map['entry_no']],
        );
        map['items'] = itemRows.map((ir) => SaleItem.fromMap(ir)).toList();
      }
      list.add(SaleInvoice.fromMap(map));
    }

    return list;
  }

  /// Fetches Sale Returns within a given date range
  Future<List<SaleReturnInvoice>> fetchSaleReturnsInDateRange(
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
      'sales_returns',
      where: 'date BETWEEN ? AND ?',
      whereArgs: [fromStr, toStr],
      orderBy: 'date DESC',
      limit: limit,
      offset: offset,
    );

    List<SaleReturnInvoice> list = [];
    for (var r in rows) {
      final map = Map<String, dynamic>.from(r);
      if (loadItems) {
        final itemRows = await db.query(
          'sales_return_items',
          where: 'return_no = ?',
          whereArgs: [map['return_no']],
        );
        map['items'] = itemRows.map((ir) => SaleItem.fromMap(ir)).toList();
      }
      list.add(SaleReturnInvoice.fromMap(map));
    }

    return list;
  }

  /// Saves a sale invoice locally with atomic transaction locking
  Future<String> saveSale(SaleInvoice sale, {bool isEditMode = false}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final db = await DbHelper.instance.database;
      return await db.transaction((txn) async {
        if (sale.entryNo.isEmpty) {
          sale.entryNo = await getNextSaleEntryNo();
        }

        final invoiceMap = sale.toMap();
        if (isEditMode) {
          await txn.update(
            'sales_invoices',
            invoiceMap,
            where: 'entry_no = ?',
            whereArgs: [sale.entryNo],
          );
          await txn.delete(
            'sales_items',
            where: 'invoice_no = ?',
            whereArgs: [sale.entryNo],
          );
        } else {
          await txn.insert('sales_invoices', invoiceMap);
        }

        for (var item in sale.items) {
          final itemMap = item.toMap();
          itemMap['invoice_no'] = sale.entryNo;
          await txn.insert('sales_items', itemMap);
        }

        AppLogger.instance.info('SALES', 'Sale ${sale.entryNo} saved successfully (Edit: $isEditMode)');
        return sale.entryNo;
      });
    } catch (e, stack) {
      AppLogger.instance.error('SALES', 'Failed to save sale ${sale.entryNo}', error: e, stackTrace: stack);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Online-first save for sales invoices (syncs to Supabase if connected)
  Future<String> saveSaleOnlineFirst(SaleInvoice sale, {bool isEditMode = false}) async {
    final entryNo = await saveSale(sale, isEditMode: isEditMode);
    try {
      SupabaseSyncService.instance.triggerInstantSync();
    } catch (e) {
      AppLogger.instance.warn('SALES_SYNC', 'Background sync trigger deferred: $e');
    }
    return entryNo;
  }

  /// Soft deletes a sales invoice
  Future<void> deleteSale(String entryNo) async {
    final db = await DbHelper.instance.database;
    await db.update(
      'sales_invoices',
      {'is_deleted': 1},
      where: 'entry_no = ?',
      whereArgs: [entryNo],
    );
    notifyListeners();
  }

  /// Settles payment status on a sales invoice
  Future<void> settleSalePayment(String entryNo, String paymentMode, String remarks) async {
    final db = await DbHelper.instance.database;
    await db.update(
      'sales_invoices',
      {
        'payment_mode': paymentMode,
        'remarks': remarks,
        'payment_status': 'PAID',
      },
      where: 'entry_no = ?',
      whereArgs: [entryNo],
    );
    notifyListeners();
  }

  /// Saves or updates a sale draft in local storage
  Future<void> saveSaleDraft(Map<String, dynamic> data) async {
    final db = await DbHelper.instance.database;
    await db.insert(
      'sale_drafts',
      {
        'id': 'current_draft',
        'data': jsonEncode(data),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Loads current sale draft if exists
  Future<Map<String, dynamic>?> loadSaleDraft() async {
    final db = await DbHelper.instance.database;
    final rows = await db.query('sale_drafts', where: 'id = ?', whereArgs: ['current_draft']);
    if (rows.isNotEmpty && rows.first['data'] != null) {
      try {
        return jsonDecode(rows.first['data'].toString()) as Map<String, dynamic>;
      } catch (_) {}
    }
    return null;
  }

  /// Clears active sale draft
  Future<void> clearSaleDraft() async {
    final db = await DbHelper.instance.database;
    await db.delete('sale_drafts', where: 'id = ?', whereArgs: ['current_draft']);
  }
}
