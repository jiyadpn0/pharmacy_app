import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart' as sql;
import '../database/db_helper.dart';
import '../utils/app_logger.dart';
import 'server_config_service.dart';
import 'supabase_sync_service.dart';

/// Models a durable local outbox item for transactional stock-changing operations.
class StockOutboxEntry {
  final String id;
  final String idempotencyKey;
  final String operationType; // 'SALE', 'PURCHASE', 'SALES_RETURN', 'PURCHASE_RETURN', 'ADJUSTMENT', 'WRITE_OFF', 'VOID_SALE', 'VOID_PURCHASE'
  final String referenceNo;
  final String branchId;
  final String terminalId;
  final String? userId;
  final Map<String, dynamic> payload;
  String status; // 'pending', 'in_flight', 'accepted', 'rejected', 'retryable'
  String? errorMessage;
  final DateTime createdAt;
  DateTime updatedAt;
  int retryCount;
  DateTime? lastAttemptAt;

  StockOutboxEntry({
    required this.id,
    required this.idempotencyKey,
    required this.operationType,
    required this.referenceNo,
    required this.branchId,
    required this.terminalId,
    this.userId,
    required this.payload,
    this.status = 'pending',
    this.errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.retryCount = 0,
    this.lastAttemptAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'idempotency_key': idempotencyKey,
      'operation_type': operationType,
      'reference_no': referenceNo,
      'branch_id': branchId,
      'terminal_id': terminalId,
      'user_id': userId ?? 'Admin',
      'payload': jsonEncode(payload),
      'status': status,
      'error_message': errorMessage,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'retry_count': retryCount,
      'last_attempt_at': lastAttemptAt?.toIso8601String(),
    };
  }

  factory StockOutboxEntry.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> p;
    try {
      final raw = map['payload'];
      if (raw is Map) {
        p = Map<String, dynamic>.from(raw);
      } else if (raw is String) {
        p = jsonDecode(raw) as Map<String, dynamic>;
      } else {
        p = {};
      }
    } catch (_) {
      p = {};
    }

    return StockOutboxEntry(
      id: map['id']?.toString() ?? '',
      idempotencyKey: map['idempotency_key']?.toString() ?? '',
      operationType: map['operation_type']?.toString() ?? '',
      referenceNo: map['reference_no']?.toString() ?? '',
      branchId: map['branch_id']?.toString() ?? 'MAIN_STORE',
      terminalId: map['terminal_id']?.toString() ?? 'POS-01',
      userId: map['user_id']?.toString(),
      payload: p,
      status: map['status']?.toString() ?? 'pending',
      errorMessage: map['error_message']?.toString(),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? DateTime.now(),
      retryCount: (map['retry_count'] as num?)?.toInt() ?? 0,
      lastAttemptAt: map['last_attempt_at'] != null ? DateTime.tryParse(map['last_attempt_at'].toString()) : null,
    );
  }
}

/// Durable, idempotent outbox coordinator managing local-to-cloud stock operations.
/// Guarantees at-least-once delivery with server-side atomic execution and exact-once application.
class StockOutboxService extends ChangeNotifier {
  static final StockOutboxService instance = StockOutboxService._internal();
  StockOutboxService._internal();

  bool _isDraining = false;
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);
  final ValueNotifier<int> rejectedCount = ValueNotifier<int>(0);

  bool get isDraining => _isDraining;

  /// Generates a stable unique idempotency key for any stock operation.
  static String generateIdempotencyKey({
    required String branchId,
    required String terminalId,
    required String operationType,
    required String referenceNo,
    int? timestampMicros,
  }) {
    final cleanBranch = branchId.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final cleanTerm = terminalId.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final cleanOp = operationType.trim().toUpperCase();
    final cleanRef = referenceNo.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final ts = timestampMicros ?? DateTime.now().microsecondsSinceEpoch;
    return 'IDEMP_${cleanBranch}_${cleanTerm}_${cleanOp}_${cleanRef}_$ts';
  }

  /// Queues a stock operation safely into the durable local SQLite outbox.
  Future<StockOutboxEntry> queueOperation({
    required String operationType,
    required String referenceNo,
    required Map<String, dynamic> payload,
    String? idempotencyKey,
    String? userId,
    sql.DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await DbHelper.instance.database;
    final config = ServerConfigService.instance;
    final branchId = config.storeBranchId;
    final terminalId = config.terminalId;

    final idemp = idempotencyKey ??
        generateIdempotencyKey(
          branchId: branchId,
          terminalId: terminalId,
          operationType: operationType,
          referenceNo: referenceNo,
        );

    final entry = StockOutboxEntry(
      id: "OUTBOX_${DateTime.now().microsecondsSinceEpoch}",
      idempotencyKey: idemp,
      operationType: operationType.toUpperCase(),
      referenceNo: referenceNo,
      branchId: branchId,
      terminalId: terminalId,
      userId: userId ?? 'Admin',
      payload: payload,
      status: 'pending',
    );

    await db.insert('stock_outbox', entry.toMap(), conflictAlgorithm: sql.ConflictAlgorithm.replace);
    await refreshCounts();

    // Trigger immediate background drain if server is connected
    if (config.isServerModeEnabled && config.isConnected) {
      unawaited(drainOutbox());
    }

    return entry;
  }

  /// Refreshes reactive pending and rejected outbox counts.
  Future<void> refreshCounts() async {
    try {
      final db = await DbHelper.instance.database;
      final pRes = await db.rawQuery("SELECT COUNT(*) as cnt FROM stock_outbox WHERE status IN ('pending', 'retryable', 'in_flight')");
      final rRes = await db.rawQuery("SELECT COUNT(*) as cnt FROM stock_outbox WHERE status = 'rejected'");

      pendingCount.value = (pRes.isNotEmpty && pRes.first['cnt'] != null) ? (pRes.first['cnt'] as num).toInt() : 0;
      rejectedCount.value = (rRes.isNotEmpty && rRes.first['cnt'] != null) ? (rRes.first['cnt'] as num).toInt() : 0;
      notifyListeners();
    } catch (_) {}
  }

  /// Retrieves rejected outbox entries for user review and audit alerting.
  Future<List<StockOutboxEntry>> getRejectedEntries() async {
    try {
      final db = await DbHelper.instance.database;
      final rows = await db.query(
        'stock_outbox',
        where: "status = 'rejected'",
        orderBy: 'created_at DESC',
        limit: 50,
      );
      return rows.map((r) => StockOutboxEntry.fromMap(r)).toList();
    } catch (e) {
      debugPrint("Error fetching rejected outbox entries: $e");
      return [];
    }
  }

  /// Gets current outbox status for a specific entry.
  Future<String> getStatusForEntry(String operationType, String referenceNo) async {
    try {
      final db = await DbHelper.instance.database;
      final rows = await db.query(
        'stock_outbox',
        columns: ['status'],
        where: 'operation_type = ? AND reference_no = ?',
        whereArgs: [operationType.toUpperCase(), referenceNo],
        orderBy: 'created_at DESC',
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return rows.first['status']?.toString() ?? 'unknown';
      }
      return 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  /// Drains pending and retryable items from the outbox in strict FIFO order.
  Future<bool> drainOutbox() async {
    if (_isDraining) return false;
    final config = ServerConfigService.instance;
    if (!config.isServerModeEnabled || !config.isConnected || config.isWiping) return false;

    _isDraining = true;
    try {
      final db = await DbHelper.instance.database;
      final rows = await db.query(
        'stock_outbox',
        where: "status IN ('pending', 'retryable')",
        orderBy: 'created_at ASC',
        limit: 20,
      );

      if (rows.isEmpty) {
        await refreshCounts();
        return true;
      }

      AppLogger.instance.supabase("⚡ Draining Stock Outbox: ${rows.length} pending operations queued.");

      for (var row in rows) {
        final entry = StockOutboxEntry.fromMap(row);

        // Mark in-flight
        await db.update(
          'stock_outbox',
          {
            'status': 'in_flight',
            'last_attempt_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [entry.id],
        );

        final result = await _dispatchRpc(entry);

        if (result['success'] == true) {
          // Operation accepted by server
          await db.update(
            'stock_outbox',
            {
              'status': 'accepted',
              'error_message': null,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [entry.id],
          );

          // Mark local records synced
          await _markLocalEntrySynced(db, entry);
          AppLogger.instance.supabase("✅ Outbox operation ${entry.operationType} (#${entry.referenceNo}) accepted by server.");
        } else if (result['is_business_rejection'] == true) {
          // Rejected by server due to validation or insufficient stock
          final msg = result['message']?.toString() ?? 'Server rejected stock operation';
          await db.update(
            'stock_outbox',
            {
              'status': 'rejected',
              'error_message': msg,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [entry.id],
          );
          AppLogger.instance.error(
            'OUTBOX_REJECTION',
            "❌ Server REJECTED ${entry.operationType} #${entry.referenceNo}: $msg",
          );

          // Trigger local stock refresh from server to resolve discrepancy
          unawaited(reconcileLocalStockFromCloud());
        } else {
          // Network error or timeout: mark retryable with exponential retry counter
          await db.update(
            'stock_outbox',
            {
              'status': 'retryable',
              'retry_count': entry.retryCount + 1,
              'error_message': result['message']?.toString() ?? 'Network timeout / connection error',
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [entry.id],
          );
          AppLogger.instance.warn(
            'OUTBOX',
            "⚠️ Outbox operation ${entry.operationType} (#${entry.referenceNo}) failed (attempt ${entry.retryCount + 1}). Retrying later.",
          );
        }
      }

      await refreshCounts();
      return true;
    } catch (e, stack) {
      AppLogger.instance.error('OUTBOX', "Error during drainOutbox: $e", error: e, stackTrace: stack);
      return false;
    } finally {
      _isDraining = false;
      await refreshCounts();
    }
  }

  /// Dispatches the outbox entry to the authoritative server RPC.
  Future<Map<String, dynamic>> _dispatchRpc(StockOutboxEntry entry) async {
    final config = ServerConfigService.instance;
    final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
    if (cleanUrl.isEmpty || config.supabaseAnonKey.isEmpty) {
      return {'success': false, 'message': 'Missing Supabase server credentials'};
    }

    String rpcName = '';
    Map<String, dynamic> rpcPayload = {};

    switch (entry.operationType) {
      case 'SALE':
        rpcName = 'fn_process_sale_atomic';
        rpcPayload = {
          'p_invoice': entry.payload['header'] ?? entry.payload,
          'p_items': entry.payload['items'] ?? [],
          'p_idempotency_key': entry.idempotencyKey,
        };
        break;
      case 'PURCHASE':
        rpcName = 'fn_process_purchase_atomic';
        rpcPayload = {
          'p_purchase': entry.payload['header'] ?? entry.payload,
          'p_items': entry.payload['items'] ?? [],
          'p_idempotency_key': entry.idempotencyKey,
        };
        break;
      case 'SALES_RETURN':
        rpcName = 'fn_process_sales_return_atomic';
        rpcPayload = {
          'p_return': entry.payload['header'] ?? entry.payload,
          'p_items': entry.payload['items'] ?? [],
          'p_idempotency_key': entry.idempotencyKey,
        };
        break;
      case 'PURCHASE_RETURN':
        rpcName = 'fn_process_purchase_return_atomic';
        rpcPayload = {
          'p_return': entry.payload['header'] ?? entry.payload,
          'p_items': entry.payload['items'] ?? [],
          'p_idempotency_key': entry.idempotencyKey,
        };
        break;
      case 'ADJUSTMENT':
        rpcName = 'fn_process_stock_adjustment_atomic';
        rpcPayload = {
          'p_adjustment': entry.payload['header'] ?? entry.payload,
          'p_items': entry.payload['items'] ?? [],
          'p_idempotency_key': entry.idempotencyKey,
        };
        break;
      case 'WRITE_OFF':
        rpcName = 'fn_process_stock_write_off_atomic';
        rpcPayload = {
          'p_write_off': entry.payload,
          'p_idempotency_key': entry.idempotencyKey,
        };
        break;
      case 'VOID_SALE':
        rpcName = 'fn_void_sale_atomic';
        rpcPayload = {
          'p_entry_no': entry.referenceNo,
          'p_branch_id': entry.branchId,
          'p_terminal_id': entry.terminalId,
          'p_idempotency_key': entry.idempotencyKey,
        };
        break;
      case 'VOID_PURCHASE':
        rpcName = 'fn_void_purchase_atomic';
        rpcPayload = {
          'p_entry_no': entry.referenceNo,
          'p_branch_id': entry.branchId,
          'p_terminal_id': entry.terminalId,
          'p_idempotency_key': entry.idempotencyKey,
        };
        break;
      default:
        return {'success': false, 'is_business_rejection': true, 'message': 'Unknown operation type: ${entry.operationType}'};
    }

    try {
      final uri = Uri.parse('$cleanUrl/rest/v1/rpc/$rpcName');
      final response = await http
          .post(
            uri,
            headers: config.restHeaders,
            body: jsonEncode(rpcPayload),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          if (decoded['success'] == true) {
            return {'success': true, 'data': decoded};
          } else {
            // Server returned business rejection
            return {
              'success': false,
              'is_business_rejection': true,
              'reason': decoded['reason'],
              'message': decoded['message'] ?? 'Server rejected operation',
              'data': decoded,
            };
          }
        }
        return {'success': true, 'data': decoded};
      } else if (response.statusCode == 404) {
        // RPC function not yet deployed on server
        return {
          'success': false,
          'is_business_rejection': false,
          'message': "RPC function '$rpcName' not found on server (HTTP 404). Please apply migration script.",
        };
      } else {
        return {
          'success': false,
          'is_business_rejection': false,
          'message': "HTTP ${response.statusCode}: ${response.body}",
        };
      }
    } catch (e) {
      return {'success': false, 'is_business_rejection': false, 'message': e.toString()};
    }
  }

  /// Marks corresponding local transaction record as cloud synced.
  Future<void> _markLocalEntrySynced(sql.Database db, StockOutboxEntry entry) async {
    try {
      switch (entry.operationType) {
        case 'SALE':
        case 'VOID_SALE':
          await db.rawUpdate(
            'UPDATE sales_invoices SET is_synced = 1, is_cloud_synced = 1 WHERE entry_no = ? OR invoice_no = ?',
            [entry.referenceNo, entry.referenceNo],
          );
          await db.rawUpdate(
            'UPDATE sales_items SET is_synced = 1, is_cloud_synced = 1 WHERE invoice_no = ?',
            [entry.referenceNo],
          );
          break;
        case 'PURCHASE':
        case 'VOID_PURCHASE':
          await db.rawUpdate(
            'UPDATE purchase_entries SET is_synced = 1, is_cloud_synced = 1 WHERE entry_no = ?',
            [entry.referenceNo],
          );
          await db.rawUpdate(
            'UPDATE purchase_items SET is_synced = 1, is_cloud_synced = 1 WHERE entry_no = ?',
            [entry.referenceNo],
          );
          break;
        case 'SALES_RETURN':
          await db.rawUpdate(
            'UPDATE sales_return_invoices SET is_synced = 1 WHERE entry_no = ?',
            [entry.referenceNo],
          );
          break;
        case 'PURCHASE_RETURN':
          await db.rawUpdate(
            'UPDATE purchase_return_entries SET is_synced = 1 WHERE entry_no = ?',
            [entry.referenceNo],
          );
          break;
        case 'ADJUSTMENT':
          await db.rawUpdate(
            'UPDATE stock_adjustments SET is_synced = 1 WHERE entry_no = ?',
            [entry.referenceNo],
          );
          break;
        case 'WRITE_OFF':
          await db.rawUpdate(
            'UPDATE stock_write_offs SET is_synced = 1 WHERE id = ?',
            [entry.referenceNo],
          );
          break;
      }
    } catch (_) {}
  }

  /// Reconciles local SQLite stock from authoritative cloud server state.
  Future<void> reconcileLocalStockFromCloud({String? productId, String? batchNumber}) async {
    final config = ServerConfigService.instance;
    if (!config.isServerModeEnabled || !config.isConnected) return;
    try {
      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
      final branchId = config.storeBranchId;

      String query = '$cleanUrl/rest/v1/stock_batches?branch_id=eq.$branchId&select=*';
      if (productId != null && productId.isNotEmpty) {
        query += '&product_id=eq.$productId';
      }
      if (batchNumber != null && batchNumber.isNotEmpty) {
        query += '&batch_number=eq.$batchNumber';
      }

      final uri = Uri.parse(query);
      final response = await http.get(uri, headers: config.restHeaders).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List list = jsonDecode(response.body) as List;
        final db = await DbHelper.instance.database;

        await db.transaction((txn) async {
          for (var item in list) {
            if (item is Map<String, dynamic>) {
              final pId = item['product_id']?.toString() ?? '';
              final bNo = item['batch_number']?.toString() ?? '';
              final qty = (item['current_quantity'] as num?)?.toInt() ?? 0;
              final exp = item['expiry_date']?.toString() ?? '';
              final mrp = (item['mrp'] as num?)?.toDouble() ?? 0.0;
              final pRate = (item['purchase_rate'] as num?)?.toDouble() ?? 0.0;
              final sRate = (item['selling_rate'] as num?)?.toDouble() ?? mrp;
              final pack = (item['packing'] as num?)?.toInt() ?? 1;

              if (pId.isNotEmpty && bNo.isNotEmpty) {
                final updated = await txn.rawUpdate(
                  'UPDATE stock_batches SET current_stock = ?, mrp = ?, sale_rate = ?, purchase_rate = ?, is_synced = 1, updated_at = ? WHERE product_id = ? AND LOWER(TRIM(batch_number)) = LOWER(TRIM(?))',
                  [qty, mrp, sRate, pRate, DateTime.now().toUtc().toIso8601String(), pId, bNo],
                );

                if (updated == 0) {
                  await txn.insert('stock_batches', {
                    'product_id': pId,
                    'batch_number': bNo,
                    'expiry_date': exp,
                    'current_stock': qty,
                    'mrp': mrp,
                    'sale_rate': sRate,
                    'purchase_rate': pRate,
                    'packing': pack,
                    'is_active': 1,
                  });
                }
              }
            }
          }
        });
        AppLogger.instance.supabase("🔄 Reconciled local stock from authoritative server state (${list.length} batches).");
      }
    } catch (e) {
      debugPrint("Error reconciling local stock from cloud: $e");
    }
  }
}
