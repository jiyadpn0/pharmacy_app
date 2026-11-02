import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'server_config_service.dart';

enum NotificationType {
  stock,    // Expiry & Reorder alerts
  backup,   // Auto-backup & Cloud Sync alerts
  security, // PIN, Audit, & System update alerts
  watchdog  // Multi-PC Live Activity Stream
}

class AppNotification {
  final String id;
  final String title;
  final String message;
  final NotificationType type;
  final DateTime timestamp;
  bool isRead;
  final String? actionRoute;
  final String? terminalName;
  final int? badgeColorValue;
  final Map<String, dynamic>? actionPayload;
  final String? operationType; // ADDITION, EDIT, DELETE, STOCK_CHANGE, IMPORT, EXPORT
  late final String formattedDateTime;

  AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.timestamp,
    this.isRead = false,
    this.actionRoute,
    this.terminalName,
    this.badgeColorValue,
    this.actionPayload,
    this.operationType,
  }) {
    formattedDateTime = DateFormat('dd/MM/yyyy • hh:mm a').format(timestamp);
  }

  String get detectedOperationType {
    if (operationType != null && operationType!.trim().isNotEmpty) {
      return operationType!.trim().toUpperCase();
    }
    final msgLower = '$message $title'.toLowerCase();
    if (msgLower.contains('import')) return 'IMPORT';
    if (msgLower.contains('export')) return 'EXPORT';
    if (msgLower.contains('delete') || msgLower.contains('remove') || msgLower.contains('wipe')) return 'DELETE';
    if (msgLower.contains('edit') || msgLower.contains('update') || msgLower.contains('modify')) return 'EDIT';
    if (msgLower.contains('stock') || msgLower.contains('batch') || msgLower.contains('adjust')) return 'STOCK_CHANGE';
    return 'ADDITION';
  }

  String get detectedCategory {
    final msgLower = '$message $title'.toLowerCase();
    if (msgLower.contains('import')) return 'IMPORTS';
    if (msgLower.contains('export')) return 'EXPORTS';
    if (msgLower.contains('sale')) return 'SALES';
    if (msgLower.contains('purchase')) return 'PURCHASES';
    if (msgLower.contains('product') || msgLower.contains('catalog')) return 'CATALOG';
    if (msgLower.contains('stock') || msgLower.contains('batch')) return 'STOCK';
    if (msgLower.contains('return')) return 'RETURNS';
    return 'SYSTEM';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'type': type.name,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
      'actionRoute': actionRoute,
      'terminalName': terminalName,
      'badgeColorValue': badgeColorValue,
      'actionPayload': actionPayload,
      'operationType': operationType,
    };
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      type: NotificationType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => NotificationType.watchdog,
      ),
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      isRead: json['isRead'] ?? false,
      actionRoute: json['actionRoute'],
      terminalName: json['terminalName'],
      badgeColorValue: json['badgeColorValue'],
      actionPayload: json['actionPayload'] != null
          ? Map<String, dynamic>.from(json['actionPayload'])
          : null,
      operationType: json['operationType'],
    );
  }
}

class AppNotificationService extends ChangeNotifier {
  AppNotificationService._internal() {
    initPreferences();
  }
  static final AppNotificationService instance = AppNotificationService._internal();

  final List<AppNotification> _notifications = [];
  bool _isNotificationLockEnabled = false;

  final StreamController<AppNotification> _watchdogStreamController =
      StreamController<AppNotification>.broadcast();

  Stream<AppNotification> get watchdogStream => _watchdogStreamController.stream;

  bool get isNotificationLockEnabled => _isNotificationLockEnabled;
  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  static bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  void _purgeNonTodayWatchdogLogs() {
    _notifications.removeWhere((n) => n.type == NotificationType.watchdog && !_isToday(n.timestamp));
  }

  Future<void> _saveWatchdogLogsToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final watchdogList = _notifications
          .where((n) => n.type == NotificationType.watchdog && _isToday(n.timestamp))
          .map((n) => jsonEncode(n.toJson()))
          .toList();
      await prefs.setStringList('watchdog_logs_today', watchdogList);
    } catch (_) {}
  }

  Future<void> initPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isNotificationLockEnabled = prefs.getBool('lock_notifications_with_pin') ?? false;

      // Restore today's saved watchdog logs
      final savedLogs = prefs.getStringList('watchdog_logs_today');
      if (savedLogs != null && savedLogs.isNotEmpty) {
        for (final rawJson in savedLogs) {
          try {
            final map = jsonDecode(rawJson);
            final notif = AppNotification.fromJson(map);
            if (_isToday(notif.timestamp)) {
              if (!_notifications.any((n) => n.id == notif.id)) {
                _notifications.add(notif);
              }
            }
          } catch (_) {}
        }
        _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        await _saveWatchdogLogsToPrefs();
      }
      notifyListeners();

      // Catch up with cloud entries for today
      fetchTodaysWatchdogLogsFromCloud();
    } catch (_) {}
  }

  Future<void> setNotificationLockEnabled(bool enabled) async {
    _isNotificationLockEnabled = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('lock_notifications_with_pin', enabled);
    } catch (_) {}
  }

  List<AppNotification> getNotificationsByType(NotificationType? type) {
    _purgeNonTodayWatchdogLogs();
    if (type == null) return _notifications;
    return _notifications.where((n) => n.type == type).toList();
  }

  void addNotification({
    required String title,
    required String message,
    required NotificationType type,
    String? actionRoute,
  }) {
    final now = DateTime.now();

    // 1. Purge notifications older than 1 month (30 days) or max 500 items
    _notifications.removeWhere((n) => now.difference(n.timestamp).inDays > 30);
    if (_notifications.length >= 500) {
      _notifications.removeRange(480, _notifications.length);
    }

    // 2. Prevent exact duplicates within 5 minutes
    final bool isDuplicate = _notifications.any((n) =>
        n.title == title &&
        n.message == message &&
        now.difference(n.timestamp).inMinutes < 5);

    if (isDuplicate) return;

    final notification = AppNotification(
      id: "NOTIF_${now.microsecondsSinceEpoch}",
      title: title,
      message: message,
      type: type,
      timestamp: now,
      actionRoute: actionRoute,
    );

    _notifications.insert(0, notification);
    notifyListeners();
  }

  /// Adds a clean 1-line event summary to the Multi-PC Watchdog Activity Feed for TODAY.
  void addWatchdogLog({
    required String title,
    required String message,
    required String terminalName,
    String? actionRoute,
    int? badgeColorValue,
    Map<String, dynamic>? actionPayload,
    String? operationType,
  }) {
    final now = DateTime.now();

    _purgeNonTodayWatchdogLogs();

    if (_notifications.length >= 500) {
      _notifications.removeRange(480, _notifications.length);
    }

    // Combine consecutive Bulk Imports, Exports, and Catalog/Stock batch syncs from the same terminal within 30 seconds
    final bool isBulkOp = (title.contains('Import') || title == 'Product Catalog' || title == 'Stock Batches' || operationType == 'IMPORT' || operationType == 'EXPORT');
    if (isBulkOp && _notifications.isNotEmpty) {
      final top = _notifications.first;
      if (top.type == NotificationType.watchdog &&
          top.title == title &&
          top.terminalName == terminalName &&
          now.difference(top.timestamp).inSeconds < 30) {

        final RegExp reg = RegExp(r'([\d,]+)\s+(product|stock batch|sales invoice|purchase entri|return invoice|item|record)');
        final matchTop = reg.firstMatch(top.message);
        final matchNew = reg.firstMatch(message);

        if (matchTop != null && matchNew != null) {
          final int oldCount = int.tryParse(matchTop.group(1)!.replaceAll(',', '')) ?? 0;
          final int newCount = int.tryParse(matchNew.group(1)!.replaceAll(',', '')) ?? 0;
          final int combined = oldCount + newCount;
          final String countStr = NumberFormat('#,##,##0').format(combined);

          final String noun = matchTop.group(2) ?? 'product';
          final String pluralNoun = noun.endsWith('s') ? noun : (noun == 'purchase entri' ? 'purchase entries' : '${noun}s');

          final RegExp actionReg = RegExp(r'\s+(added|edited|imported|exported|adjusted|synced)\s+-');
          final String actionVerb = actionReg.firstMatch(top.message)?.group(1) ?? (operationType == 'IMPORT' ? 'imported' : 'added');
          final String updatedMsg = '$countStr $pluralNoun $actionVerb - $terminalName';

          _notifications[0] = AppNotification(
            id: top.id,
            title: title,
            message: updatedMsg,
            type: NotificationType.watchdog,
            timestamp: now,
            actionRoute: actionRoute,
            terminalName: terminalName,
            badgeColorValue: badgeColorValue,
            actionPayload: actionPayload,
            operationType: operationType,
          );
          _saveWatchdogLogsToPrefs();
          _watchdogStreamController.add(_notifications[0]);
          notifyListeners();
          return;
        }
      }
    }

    // Prevent identical duplicate watchdog logs within 3 seconds
    final bool isDuplicate = _notifications.any((n) =>
        n.type == NotificationType.watchdog &&
        n.title == title &&
        n.message == message &&
        now.difference(n.timestamp).inSeconds < 3);

    if (isDuplicate) return;

    final notification = AppNotification(
      id: "WDOG_${now.microsecondsSinceEpoch}",
      title: title,
      message: message,
      type: NotificationType.watchdog,
      timestamp: now,
      actionRoute: actionRoute,
      terminalName: terminalName,
      badgeColorValue: badgeColorValue,
      actionPayload: actionPayload,
      operationType: operationType,
    );

    _notifications.insert(0, notification);
    _saveWatchdogLogsToPrefs();
    _watchdogStreamController.add(notification);
    notifyListeners();
  }

  /// Fetches today's activity entries from Supabase to catch up when opening a PC later in the day.
  Future<void> fetchTodaysWatchdogLogsFromCloud() async {
    try {
      final config = ServerConfigService.instance;
      if (!config.isConnected) return;
      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
      if (cleanUrl.isEmpty) return;

      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
      final headers = config.restHeaders;

      bool addedNew = false;

      // 1. Sales Invoices today
      final salesUri = Uri.parse('$cleanUrl/rest/v1/sales_invoices?created_at=gte.$startOfDay&select=entry_no,terminal_id,created_at&order=created_at.desc&limit=50');
      final salesRes = await http.get(salesUri, headers: headers).timeout(const Duration(seconds: 3));
      if (salesRes.statusCode == 200) {
        final List rows = jsonDecode(salesRes.body);
        for (var r in rows) {
          final entryNo = (r['entry_no'] ?? '').toString().trim();
          final pcName = (r['terminal_id'] ?? 'Cloud Server').toString().trim();
          final dt = DateTime.tryParse(r['created_at'] ?? '') ?? DateTime.now();
          if (_isToday(dt)) {
            final id = 'WDOG_SALE_$entryNo';
            final title = 'Sales Entry';
            final msg = 'Sale Entry ${entryNo.isNotEmpty ? "#$entryNo " : ""}added - $pcName';
            if (!_notifications.any((n) => n.id == id || (n.title == title && n.message == msg))) {
              _notifications.add(AppNotification(
                id: id,
                title: title,
                message: msg,
                type: NotificationType.watchdog,
                timestamp: dt,
                terminalName: pcName,
                actionRoute: 'sales',
                badgeColorValue: 0xFF2E7D32,
              ));
              addedNew = true;
            }
          }
        }
      }

      // 2. Purchase Entries today
      final purUri = Uri.parse('$cleanUrl/rest/v1/purchase_entries?created_at=gte.$startOfDay&select=entry_no,terminal_id,created_at&order=created_at.desc&limit=50');
      final purRes = await http.get(purUri, headers: headers).timeout(const Duration(seconds: 3));
      if (purRes.statusCode == 200) {
        final List rows = jsonDecode(purRes.body);
        for (var r in rows) {
          final entryNo = (r['entry_no'] ?? '').toString().trim();
          final pcName = (r['terminal_id'] ?? 'Cloud Server').toString().trim();
          final dt = DateTime.tryParse(r['created_at'] ?? '') ?? DateTime.now();
          if (_isToday(dt)) {
            final id = 'WDOG_PUR_$entryNo';
            final title = 'Purchase Entry';
            final msg = 'Purchase Entry ${entryNo.isNotEmpty ? "#$entryNo " : ""}added - $pcName';
            if (!_notifications.any((n) => n.id == id || (n.title == title && n.message == msg))) {
              _notifications.add(AppNotification(
                id: id,
                title: title,
                message: msg,
                type: NotificationType.watchdog,
                timestamp: dt,
                terminalName: pcName,
                actionRoute: 'purchases',
                badgeColorValue: 0xFF1565C0,
              ));
              addedNew = true;
            }
          }
        }
      }

      if (addedNew) {
        _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        await _saveWatchdogLogsToPrefs();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('fetchTodaysWatchdogLogsFromCloud error: $e');
    }
  }

  void markAsRead(String id) {
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx != -1) {
      _notifications[idx].isRead = true;
      _saveWatchdogLogsToPrefs();
      notifyListeners();
    }
  }

  void markAllAsRead() {
    for (var n in _notifications) {
      n.isRead = true;
    }
    _saveWatchdogLogsToPrefs();
    notifyListeners();
  }

  void clearAll() {
    _notifications.clear();
    _saveWatchdogLogsToPrefs();
    notifyListeners();
  }
}

