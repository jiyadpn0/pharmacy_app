import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../services/server_config_service.dart';

enum LogLevel { info, warning, error, debug }

class LogEntry {
  final int id;
  final DateTime timestamp;
  final String category;
  final LogLevel level;
  final String message;
  final String? details;
  final String? error;
  final String? stackTrace;

  LogEntry({
    required this.id,
    required this.timestamp,
    required this.category,
    required this.level,
    required this.message,
    this.details,
    this.error,
    this.stackTrace,
  });

  String get timeFormatted {
    final y = timestamp.year;
    final mo = timestamp.month.toString().padLeft(2, '0');
    final d = timestamp.day.toString().padLeft(2, '0');
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return "$y-$mo-$d $h:$m:$s.$ms";
  }

  String get levelTag {
    switch (level) {
      case LogLevel.error:
        return "ERROR";
      case LogLevel.warning:
        return "WARN";
      case LogLevel.debug:
        return "DEBUG";
      case LogLevel.info:
        return "INFO";
    }
  }

  String toFullString() {
    final sb = StringBuffer();
    sb.write("[$timeFormatted] [#$id] [$levelTag] [$category] $message");
    if (details != null && details!.isNotEmpty) {
      sb.write("\n  Details: $details");
    }
    if (error != null && error!.isNotEmpty) {
      sb.write("\n  Error: $error");
    }
    if (stackTrace != null && stackTrace!.isNotEmpty) {
      sb.write("\n  Stack: $stackTrace");
    }
    return sb.toString();
  }
}

class AppLogger extends ChangeNotifier {
  static final AppLogger _instance = AppLogger._internal();
  static AppLogger get instance => _instance;

  AppLogger._internal() {
    _initFileLogging();
  }

  static const int maxMemoryLogs = 5000;
  final List<LogEntry> _logs = [];
  int _counter = 0;
  bool _hasNewErrors = false;
  File? _logFile;
  IOSink? _fileSink;

  List<LogEntry> get logs => List.unmodifiable(_logs);
  bool get hasNewErrors => _hasNewErrors;

  void markErrorsAsSeen() {
    if (_hasNewErrors) {
      _hasNewErrors = false;
      notifyListeners();
    }
  }

  Future<void> _initFileLogging() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final logDir = Directory("${dir.path}${Platform.pathSeparator}logs");
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      _logFile = File("${logDir.path}${Platform.pathSeparator}app_session.log");
      // Clean up log files older than 7 days to preserve disk space
      _cleanupOldLogFiles(logDir);

      final todayStr = DateFormat('yyyy_MM_dd').format(DateTime.now());
      _logFile = File("${logDir.path}${Platform.pathSeparator}pharma_log_$todayStr.txt");
      _fileSink = _logFile!.openWrite(mode: FileMode.append);
      _fileSink?.writeln("\n==================================================");
      _fileSink?.writeln("SESSION STARTED AT ${DateTime.now().toIso8601String()}");
      _fileSink?.writeln("==================================================");
    } catch (e) {
      debugPrint("AppLogger failed to initialize file sink: $e");
    }
  }

  Future<void> _cleanupOldLogFiles(Directory logDir) async {
    try {
      final now = DateTime.now();
      final files = await logDir.list().toList();
      for (final entity in files) {
        if (entity is File && entity.path.contains('pharma_log_')) {
          final stat = await entity.stat();
          if (now.difference(stat.modified).inDays >= 7) {
            await entity.delete();
            debugPrint("AppLogger: Cleaned up old log file: ${entity.path}");
          }
        }
      }
    } catch (_) {}
  }

  void _pushErrorToCloud(LogEntry entry) {
    unawaited(() async {
      try {
        if (!ServerConfigService.instance.isConnected) return;
        final config = ServerConfigService.instance;
        final uri = Uri.parse('${config.supabaseUrl}/rest/v1/app_error_logs');
        await http.post(
          uri,
          headers: config.restHeaders,
          body: jsonEncode({
            'terminal_id': config.terminalId,
            'branch_id': config.storeBranchId,
            'category': entry.category,
            'message': entry.message,
            'error_details': entry.error ?? entry.details ?? '',
            'stack_trace': entry.stackTrace ?? '',
            'created_at': entry.timestamp.toUtc().toIso8601String(),
          }),
        ).timeout(const Duration(seconds: 4));
      } catch (_) {}
    }());
  }

  String _maskSensitiveData(String input) {
    if (input.isEmpty) return input;
    var masked = input;
    // Regex matches common authorization tokens, passwords, keys in JSON/Text
    final sensitivePatterns = [
      RegExp(r'(password|pass|access_token|refresh_token|apikey|secret|service_role|bearer)["\s:=]+([^\s,{}"]+)', caseSensitive: false),
    ];
    for (final pattern in sensitivePatterns) {
      masked = masked.replaceAllMapped(pattern, (match) {
        final key = match.group(1);
        return '$key: "***MASKED***"';
      });
    }
    return masked;
  }

  void log(
    String category,
    String message, {
    String? details,
    LogLevel level = LogLevel.info,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _counter++;
    final maskedMessage = _maskSensitiveData(message);
    final maskedDetails = details != null ? _maskSensitiveData(details) : null;
    final maskedError = error != null ? _maskSensitiveData(error.toString()) : null;
    final cleanStack = stackTrace?.toString();

    final entry = LogEntry(
      id: _counter,
      timestamp: DateTime.now(),
      category: category.toUpperCase(),
      level: level,
      message: maskedMessage,
      details: maskedDetails,
      error: maskedError,
      stackTrace: cleanStack,
    );

    if (_logs.length >= maxMemoryLogs) {
      _logs.removeAt(0);
    }
    _logs.add(entry);

    if (level == LogLevel.error) {
      _hasNewErrors = true;
      // Asynchronously send critical error telemetry to Supabase Cloud
      _pushErrorToCloud(entry);
    }

    // Write to persistent disk log file
    try {
      _fileSink?.writeln(entry.toFullString());
    } catch (_) {}

    // Print to stdout in debug mode
    if (kDebugMode) {
      debugPrint("LOG [#${entry.id}] [${entry.category}] $maskedMessage");
    }

    // Safely notify listeners without throwing "Build scheduled during frame" exception
    if (WidgetsBinding.instance.schedulerPhase != SchedulerPhase.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  // Convenience Methods
  void info(String category, String message, {String? details}) =>
      log(category, message, details: details, level: LogLevel.info);

  void warn(String category, String message, {String? details}) =>
      log(category, message, details: details, level: LogLevel.warning);

  void error(String category, String message, {Object? error, StackTrace? stackTrace, String? details}) =>
      log(category, message, details: details, level: LogLevel.error, error: error, stackTrace: stackTrace);

  void supabase(String message, {String? details, LogLevel level = LogLevel.info, Object? error}) =>
      log("SUPABASE", message, details: details, level: level, error: error);

  void sqlite(String message, {String? details, LogLevel level = LogLevel.info, Object? error}) =>
      log("SQLITE", message, details: details, level: level, error: error);

  void network(String message, {String? details, LogLevel level = LogLevel.info}) =>
      log("NETWORK", message, details: details, level: level);

  void performance(String message, Duration duration) =>
      log("PERFORMANCE", "$message (took ${duration.inMilliseconds}ms)");

  void sequence(String category, String message, {String? details}) =>
      log(category, message, details: details, level: LogLevel.info);

  void clear() {
    _logs.clear();
    _hasNewErrors = false;
    notifyListeners();
  }

  Future<void> copyAllToClipboard([List<LogEntry>? targetLogs]) async {
    final listToCopy = targetLogs ?? _logs;
    final text = listToCopy.map((e) => e.toFullString()).join("\n--------------------------------------------------\n");
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<String?> exportToFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File("${dir.path}${Platform.pathSeparator}pharmacy_app_logs_${DateTime.now().millisecondsSinceEpoch}.txt");
      final content = _logs.map((e) => e.toFullString()).join("\n\n");
      await file.writeAsString(content);
      return file.path;
    } catch (e) {
      error("SYSTEM", "Failed to export logs to file: $e");
      return null;
    }
  }

  @override
  void dispose() {
    _fileSink?.close();
    super.dispose();
  }
}
