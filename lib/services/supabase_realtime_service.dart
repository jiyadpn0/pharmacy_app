import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_logger.dart';
import 'server_config_service.dart';
import 'delta_sync_service.dart';
import 'app_notification_service.dart';

/// Real-time service utilizing Postgres changes (lightweight WebSocket payloads)
/// instead of .stream() full table scans.
class SupabaseRealtimeService {
  static final SupabaseRealtimeService instance = SupabaseRealtimeService._internal();
  SupabaseRealtimeService._internal();

  bool _isInitialized = false;
  final Map<String, RealtimeChannel> _activeChannels = {};
  Timer? _heartbeatTimer;

  void Function()? _cachedOnRealtimeEvent;
  void Function(String tableName, String eventType, List<Map<String, dynamic>> rows)? _cachedOnTableEvent;

  final Map<String, DateTime> _recentlyPushedKeys = {};
  final Map<String, List<Map<String, dynamic>>> _eventBuffers = {};
  final Map<String, Timer> _bufferTimers = {};

  void _enqueueRealtimeRow(
    String tableName,
    String eventTypeStr,
    Map<String, dynamic> rowRecord,
    void Function()? onRealtimeEvent,
    void Function(String tableName, String eventType, List<Map<String, dynamic>> rows)? onTableEvent,
  ) {
    if (ServerConfigService.instance.isWiping) return;
    final key = "$tableName|$eventTypeStr";
    _eventBuffers.putIfAbsent(key, () => []).add(rowRecord);

    final int batchDelayMs = (tableName == 'sales_invoices' ||
            tableName == 'sales_items' ||
            tableName == 'purchase_entries' ||
            tableName == 'purchase_items' ||
            tableName == 'sales_return_invoices' ||
            tableName == 'sales_return_items' ||
            tableName == 'purchase_return_entries' ||
            tableName == 'purchase_return_items' ||
            tableName == 'stock_adjustments' ||
            tableName == 'stock_batches' ||
            tableName == 'product_master')
        ? 300
        : 400;

    _bufferTimers[key]?.cancel();
    _bufferTimers[key] = Timer(Duration(milliseconds: batchDelayMs), () {
      final bufferedRows = _eventBuffers.remove(key) ?? [];
      _bufferTimers.remove(key);

      if (bufferedRows.isNotEmpty) {
        AppLogger.instance.supabase("⚡ Realtime [$tableName]: Batch $eventTypeStr received (${bufferedRows.length} rows)");
        if (onTableEvent != null) {
          onTableEvent(tableName, eventTypeStr, bufferedRows);
        }
        _emitWatchdogSummary(tableName, eventTypeStr, bufferedRows);
        onRealtimeEvent?.call();
      }
    });
  }

  void _emitWatchdogSummary(String tableName, String eventTypeStr, List<Map<String, dynamic>> bufferedRows) {
    try {
      if (bufferedRows.isEmpty) return;
      final firstRow = bufferedRows.first;
      String pcName = (firstRow['terminal_id'] ?? firstRow['branch_id'] ?? 'Cloud Server').toString().trim();
      if (pcName.isEmpty || pcName == 'MAIN_STORE') pcName = 'Cloud Server';

      final String opType = eventTypeStr == 'DELETE'
          ? 'DELETE'
          : (eventTypeStr == 'UPDATE'
              ? (tableName.contains('stock') ? 'STOCK_CHANGE' : 'EDIT')
              : 'ADDITION');

      final String actionLabel = opType == 'DELETE' ? 'deleted' : (opType == 'EDIT' ? 'edited' : (opType == 'STOCK_CHANGE' ? 'adjusted' : 'added'));

      if (tableName == 'sales_invoices') {
        final cnt = bufferedRows.length;
        if (cnt > 3) {
          final countStr = NumberFormat('#,##,##0').format(cnt);
          AppNotificationService.instance.addWatchdogLog(
            title: 'Sales Import',
            message: '$countStr sales invoices $actionLabel - $pcName',
            terminalName: pcName,
            actionRoute: 'sales',
            badgeColorValue: 0xFF2E7D32,
            operationType: opType == 'ADDITION' ? 'IMPORT' : opType,
          );
        } else {
          final entryNo = (firstRow['entry_no'] ?? firstRow['invoice_no'] ?? '').toString().trim();
          final displayNo = entryNo.isNotEmpty ? '#$entryNo ' : '';
          AppNotificationService.instance.addWatchdogLog(
            title: 'Sales Entry',
            message: 'Sale Entry ${displayNo}$actionLabel - $pcName',
            terminalName: pcName,
            actionRoute: 'sales',
            badgeColorValue: opType == 'DELETE' ? 0xFFD32F2F : (opType == 'EDIT' ? 0xFF1976D2 : 0xFF2E7D32),
            actionPayload: {'type': 'sales', 'entryNo': entryNo},
            operationType: opType,
          );
        }
      } else if (tableName == 'purchase_entries') {
        final cnt = bufferedRows.length;
        if (cnt > 3) {
          final countStr = NumberFormat('#,##,##0').format(cnt);
          AppNotificationService.instance.addWatchdogLog(
            title: 'Purchase Import',
            message: '$countStr purchase entries $actionLabel - $pcName',
            terminalName: pcName,
            actionRoute: 'purchases',
            badgeColorValue: 0xFF1565C0,
            operationType: opType == 'ADDITION' ? 'IMPORT' : opType,
          );
        } else {
          final entryNo = (firstRow['entry_no'] ?? firstRow['purchase_no'] ?? '').toString().trim();
          final displayNo = entryNo.isNotEmpty ? '#$entryNo ' : '';
          AppNotificationService.instance.addWatchdogLog(
            title: 'Purchase Entry',
            message: 'Purchase Entry ${displayNo}$actionLabel - $pcName',
            terminalName: pcName,
            actionRoute: 'purchases',
            badgeColorValue: opType == 'DELETE' ? 0xFFD32F2F : 0xFF1565C0,
            actionPayload: {'type': 'purchases', 'entryNo': entryNo},
            operationType: opType,
          );
        }
      } else if (tableName == 'sales_return_invoices' || tableName == 'purchase_return_entries') {
        final cnt = bufferedRows.length;
        if (cnt > 3) {
          final countStr = NumberFormat('#,##,##0').format(cnt);
          AppNotificationService.instance.addWatchdogLog(
            title: 'Returns Import',
            message: '$countStr return invoices $actionLabel - $pcName',
            terminalName: pcName,
            actionRoute: tableName == 'sales_return_invoices' ? 'sales_returns' : 'purchase_returns',
            badgeColorValue: 0xFFC62828,
            operationType: opType == 'ADDITION' ? 'IMPORT' : opType,
          );
        } else {
          final entryNo = (firstRow['entry_no'] ?? '').toString().trim();
          final displayNo = entryNo.isNotEmpty ? '#$entryNo ' : '';
          final isSaleReturn = tableName == 'sales_return_invoices';
          AppNotificationService.instance.addWatchdogLog(
            title: isSaleReturn ? 'Sales Return' : 'Purchase Return',
            message: '${isSaleReturn ? "Sales Return" : "Purchase Return"} ${displayNo}$actionLabel - $pcName',
            terminalName: pcName,
            actionRoute: isSaleReturn ? 'sales_returns' : 'purchase_returns',
            badgeColorValue: 0xFFC62828,
            operationType: opType,
          );
        }
      } else if (tableName == 'product_master') {
        final cnt = bufferedRows.length;
        final countStr = NumberFormat('#,##,##0').format(cnt);
        AppNotificationService.instance.addWatchdogLog(
          title: 'Product Catalog',
          message: '$countStr product${cnt > 1 ? "s" : ""} $actionLabel - $pcName',
          terminalName: pcName,
          badgeColorValue: 0xFF6A1B9A,
          operationType: opType == 'ADDITION' ? 'IMPORT' : opType,
        );
      } else if (tableName == 'stock_batches') {
        final cnt = bufferedRows.length;
        final countStr = NumberFormat('#,##,##0').format(cnt);
        AppNotificationService.instance.addWatchdogLog(
          title: 'Stock Batches',
          message: '$countStr stock batch${cnt > 1 ? "es" : ""} adjusted - $pcName',
          terminalName: pcName,
          badgeColorValue: 0xFFEF6C00,
          operationType: 'STOCK_CHANGE',
        );
      } else if (tableName == 'stock_adjustments') {
        AppNotificationService.instance.addWatchdogLog(
          title: 'Stock Adjustment',
          message: 'Stock adjustment entry $actionLabel - $pcName',
          terminalName: pcName,
          badgeColorValue: 0xFFEF6C00,
          operationType: 'STOCK_CHANGE',
        );
      }
    } catch (e) {
      debugPrint('Watchdog emission error: $e');
    }
  }

  /// Marks a specific key (e.g. batch key, invoice entry_no, product ID) as recently pushed by this device
  /// to suppress self-echoes from child tables that lack a terminal_id column.
  void markKeyRecentlyPushed(String key) {
    if (key.trim().isEmpty) return;
    final cleanKey = key.trim().toLowerCase();
    _recentlyPushedKeys[cleanKey] = DateTime.now();
    _cleanupExpiredPushedKeys();
  }

  bool _isRecentlyPushed(String key) {
    if (key.trim().isEmpty) return false;
    _cleanupExpiredPushedKeys();
    final cleanKey = key.trim().toLowerCase();
    final timestamp = _recentlyPushedKeys[cleanKey];
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp).inSeconds < 60;
  }

  void _cleanupExpiredPushedKeys() {
    final now = DateTime.now();
    _recentlyPushedKeys.removeWhere((_, time) => now.difference(time).inSeconds >= 60);
  }

  Future<void> initialize() async {
    startHeartbeat();

    if (_isInitialized) return;

    final config = ServerConfigService.instance;
    final url = config.supabaseUrl.trim();
    final key = config.supabaseAnonKey.trim();

    if (url.isEmpty || key.isEmpty) {
      debugPrint('SupabaseRealtimeService: Skipped initialization - missing URL or Key.');
      return;
    }

    try {
      await Supabase.initialize(
        url: url,
        publishableKey: key,
      );
      _isInitialized = true;
      debugPrint('SupabaseRealtimeService: Successfully initialized Supabase Client.');
    } catch (e) {
      debugPrint('SupabaseRealtimeService init error: $e');
    }
  }

  /// Ensures active WebSocket channel subscriptions exist upon network reconnection.
  Future<void> ensureRealtimeListenersActive() async {
    if (!_isInitialized) {
      await initialize();
    }
    if (_isInitialized && _cachedOnRealtimeEvent != null) {
      debugPrint('SupabaseRealtimeService: Restoring WebSocket channels after reconnect...');
      startAllRealtimeListeners(
        onRealtimeEvent: _cachedOnRealtimeEvent!,
        onTableEvent: _cachedOnTableEvent,
      );
      // Trigger incremental catch-up delta sync after reconnect to recover any missed events within 15-20s
      unawaited(DeltaSyncService.instance.triggerReconnectionCatchupSync());
    }
  }

  void startHeartbeat() {
    _heartbeatTimer?.cancel();
    _sendHeartbeatPing();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _sendHeartbeatPing();
    });
  }

  Future<void> _sendHeartbeatPing() async {
    final config = ServerConfigService.instance;
    final url = ServerConfigService.cleanServerUrl(config.supabaseUrl);
    final key = config.supabaseAnonKey.trim();
    if (url.isEmpty || key.isEmpty) return;

    final terminalId = config.terminalId;
    final branchId = config.storeBranchId;
    final machineId = config.machineUuid;
    final nowStr = DateTime.now().toIso8601String();

    final pingPayload = {
      'machine_id': machineId,
      'branch_id': branchId,
      'terminal_id': terminalId,
      'app_version': '3.3.7',
      'last_seen_at': nowStr,
    };

    // 1. Try Supabase Client SDK if initialized
    if (_isInitialized) {
      try {
        await Supabase.instance.client.from('active_computers').upsert(
          pingPayload,
          onConflict: 'machine_id',
        );
        unawaited(config.verifyDistinctTerminalId());
        return;
      } catch (_) {}
    }

    // 2. Fallback direct HTTP REST POST
    try {
      final uri = Uri.parse('$url/rest/v1/active_computers?on_conflict=machine_id');
      final headers = Map<String, String>.from(config.restHeaders);
      headers['Prefer'] = 'resolution=merge-duplicates';

      final res = await http.post(
        uri,
        headers: headers,
        body: jsonEncode(pingPayload),
      ).timeout(const Duration(seconds: 5));

      // Fallback for legacy schema where PK was terminal_id
      if (res.statusCode >= 400) {
        final legacyUri = Uri.parse('$url/rest/v1/active_computers?on_conflict=terminal_id');
        await http.post(
          legacyUri,
          headers: headers,
          body: jsonEncode({
            'terminal_id': terminalId,
            'last_seen_at': nowStr,
          }),
        ).timeout(const Duration(seconds: 5));
      }

      unawaited(config.verifyDistinctTerminalId());
    } catch (e) {
      debugPrint('Supabase heartbeat ping notice: $e');
    }
  }

  /// Listens to INSERT, UPDATE, and DELETE events across core ERP tables
  bool _isPaused = false;
  bool get isPaused => _isPaused;

  /// Temporarily pauses Realtime WebSocket listeners (e.g. during bulk catalog/product imports)
  /// to prevent high WebSocket echo overhead and UI stuttering.
  void pauseSubscriptions() {
    _isPaused = true;
    disposeAllChannelsOnly();
    debugPrint('SupabaseRealtimeService: Realtime subscriptions paused.');
  }

  /// Resumes Realtime WebSocket listeners after bulk operations complete.
  void resumeSubscriptions() {
    _isPaused = false;
    debugPrint('SupabaseRealtimeService: Resuming realtime subscriptions...');
    if (_cachedOnRealtimeEvent != null) {
      startAllRealtimeListeners(
        onRealtimeEvent: _cachedOnRealtimeEvent!,
        onTableEvent: _cachedOnTableEvent,
      );
    }
  }

  /// Listens to INSERT, UPDATE, and DELETE events across core ERP tables
  /// without fetching full table dumps from the disk.
  void startAllRealtimeListeners({
    void Function()? onRealtimeEvent,
    void Function(String tableName, String eventType, List<Map<String, dynamic>> rows)? onTableEvent,
  }) {
    if (onRealtimeEvent != null) {
      _cachedOnRealtimeEvent = onRealtimeEvent;
    }
    if (onTableEvent != null) {
      _cachedOnTableEvent = onTableEvent;
    }

    if (_isPaused) {
      debugPrint('SupabaseRealtimeService: Cannot start listeners - Subscriptions are currently paused.');
      return;
    }

    if (!_isInitialized) {
      debugPrint('SupabaseRealtimeService: Cannot start listeners - Not initialized.');
      return;
    }

    // Clean up existing channels first to prevent duplicate callbacks or channel memory leaks
    disposeAllChannelsOnly();

    final tables = [
      'sales_invoices',
      'sales_items',
      'purchase_entries',
      'purchase_items',
      'product_master',
      'stock_batches',
      'stock_ledger',
      'stock_adjustments',
      'sales_return_invoices',
      'sales_return_items',
      'purchase_return_entries',
      'purchase_return_items',
    ];

    try {
      final config = ServerConfigService.instance;
      final localTerminalId = config.terminalId.trim();
      final currentBranch = config.storeBranchId.trim();

      for (var tableName in tables) {
        final channel = Supabase.instance.client.channel('rt-$tableName');
        channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: tableName,
          filter: (tableName != 'product_master')
              ? PostgresChangeFilter(
                  type: PostgresChangeFilterType.eq,
                  column: 'branch_id',
                  value: currentBranch,
                )
              : null,
          callback: (payload) {
            if (_isPaused) return;

            final rowRecord = payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord;
            if (rowRecord.isEmpty) return;

            // 0. Strict branch isolation filter check
            final rowBranch = rowRecord['branch_id']?.toString().trim() ?? '';
            if (rowBranch.isNotEmpty && currentBranch.isNotEmpty && rowBranch != currentBranch) {
              return; // Ignore other store branches
            }

            // 1. Direct terminal_id filter check
            final senderTerminal = rowRecord['terminal_id']?.toString().trim() ?? '';
            if (senderTerminal.isNotEmpty && localTerminalId.isNotEmpty && senderTerminal == localTerminalId) {
              return; // Ignore self-generated header updates
            }

            // 2. Document Entry/Invoice self-echo check for child and transaction tables
            final invNo = (rowRecord['invoice_no'] ?? rowRecord['entry_no'] ?? rowRecord['purchase_no'] ?? '').toString().trim();
            if (invNo.isNotEmpty && _isRecentlyPushed(invNo)) {
              return; // Ignore recently pushed transaction entries
            }

            // 3. Stock batch / Product ID self-echo check
            final pId = (rowRecord['product_id'] ?? rowRecord['id'] ?? '').toString().trim();
            final bNo = (rowRecord['batch_number'] ?? rowRecord['batch'] ?? '').toString().trim();
            if (pId.isNotEmpty) {
              if (_isRecentlyPushed(pId)) return;
              if (bNo.isNotEmpty && _isRecentlyPushed("${pId}_$bNo")) return;
            }

            final eventTypeStr = payload.eventType.name.toUpperCase();
            _enqueueRealtimeRow(tableName, eventTypeStr, rowRecord, _cachedOnRealtimeEvent, _cachedOnTableEvent);
          },
        ).subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            AppLogger.instance.supabase("Realtime channel active for '$tableName'");
          } else if (error != null) {
            final errStr = error.toString();
            if (!errStr.contains('1006') && !errStr.contains('going away')) {
              AppLogger.instance.error("REALTIME", "Realtime subscription notice [$tableName]", error: error);
            }
          }
        });

        _activeChannels[tableName] = channel;
      }

      // Automatically fetch today's activity logs to populate Watchdog feed for late-starting PCs
      unawaited(AppNotificationService.instance.fetchTodaysWatchdogLogsFromCloud());
    } catch (e) {
      debugPrint('SupabaseRealtimeService listener error: $e');
    }
  }

  void stopListening(String tableName) {
    if (_activeChannels.containsKey(tableName)) {
      final ch = _activeChannels.remove(tableName);
      if (ch != null) {
        try {
          Supabase.instance.client.removeChannel(ch);
        } catch (_) {}
      }
    }
  }

  void disposeAllChannelsOnly() {
    if (_activeChannels.isNotEmpty) {
      for (var entry in _activeChannels.entries) {
        try {
          Supabase.instance.client.removeChannel(entry.value);
        } catch (_) {}
      }
      _activeChannels.clear();
      debugPrint('SupabaseRealtimeService: Active realtime channels unsubscribed.');
    }
  }

  void disposeAll() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    disposeAllChannelsOnly();
  }
}
