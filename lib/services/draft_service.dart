import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';

/// High-performance local draft service for crash & power-cut auto-recovery.
/// Auto-saves active billing UI forms to SQLite without blocking UI execution.
class DraftService {
  static final DraftService instance = DraftService._init();
  DraftService._init();

  static const String salesDraftKey = 'active_sales_bill_draft';
  static const String purchaseDraftKey = 'active_purchase_entry_draft';
  static const String salesReturnDraftKey = 'active_sales_return_draft';

  /// Saves a form draft asynchronously to local SQLite database
  Future<void> saveDraft({
    required String draftKey,
    required String formType,
    required Map<String, dynamic> data,
  }) async {
    try {
      final db = await DbHelper.instance.database;
      final now = DateTime.now().toIso8601String();
      final jsonStr = jsonEncode(data);

      await db.insert(
        'draft_bills',
        {
          'draft_key': draftKey,
          'form_type': formType,
          'data_json': jsonStr,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint("DraftService: Draft '$draftKey' saved successfully.");
    } catch (e) {
      debugPrint("DraftService saveDraft Error: $e");
    }
  }

  /// Retrieves a saved draft by key from local SQLite database
  Future<Map<String, dynamic>?> getDraft(String draftKey) async {
    try {
      final db = await DbHelper.instance.database;
      final res = await db.query(
        'draft_bills',
        where: 'draft_key = ?',
        whereArgs: [draftKey],
        limit: 1,
      );

      if (res.isNotEmpty && res.first['data_json'] != null) {
        final jsonStr = res.first['data_json'] as String;
        return jsonDecode(jsonStr) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint("DraftService getDraft Error: $e");
    }
    return null;
  }

  /// Clears/deletes a saved draft after bill is successfully saved or cleared
  Future<void> clearDraft(String draftKey) async {
    try {
      final db = await DbHelper.instance.database;
      await db.delete(
        'draft_bills',
        where: 'draft_key = ?',
        whereArgs: [draftKey],
      );
      debugPrint("DraftService: Draft '$draftKey' cleared.");
    } catch (e) {
      debugPrint("DraftService clearDraft Error: $e");
    }
  }

  /// Checks if an active unsaved draft exists for a given form key
  Future<bool> hasDraft(String draftKey) async {
    try {
      final db = await DbHelper.instance.database;
      final res = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM draft_bills WHERE draft_key = ?',
        [draftKey],
      );
      if (res.isNotEmpty) {
        final count = Sqflite.firstIntValue(res) ?? 0;
        return count > 0;
      }
    } catch (e) {
      debugPrint("DraftService hasDraft Error: $e");
    }
    return false;
  }
}
