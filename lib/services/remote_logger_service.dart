import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RemoteLoggerService {
  RemoteLoggerService._();
  static final RemoteLoggerService instance = RemoteLoggerService._();

  static const String _defaultRepoOwner = 'jiyadpn0';
  static const String _defaultRepoName = 'pharmacy_app';
  static const String _cacheKey = 'offline_error_logs_v2';
  
  /// Retention Policy: Automatically purge cached logs older than 7 days
  static const int maxCacheRetentionDays = 7;

  bool _isSyncing = false;
  String _activeScreen = 'Main App';
  final List<String> _breadcrumbs = [];

  /// Tracks the active screen name.
  void setCurrentScreen(String screenName) {
    _activeScreen = screenName;
    addBreadcrumb('Navigated to $screenName');
  }

  /// Adds a user action breadcrumb (keeps last 8 actions for context).
  void addBreadcrumb(String action) {
    final time = DateTime.now().toIso8601String().split('T').last.substring(0, 8);
    _breadcrumbs.add('[$time] $action');
    if (_breadcrumbs.length > 8) {
      _breadcrumbs.removeAt(0);
    }
  }

  /// Initializes the logger, cleans up expired cache files (> 7 days), and syncs.
  Future<void> init() async {
    await _purgeExpiredLogs();
    syncOfflineLogs();
  }

  /// Log an error with message, stacktrace, screen, and breadcrumb context.
  Future<void> logError(
    dynamic error, {
    StackTrace? stackTrace,
    String? library,
    String? context,
  }) async {
    try {
      final String timeStr = DateTime.now().toIso8601String();
      final String osName = Platform.operatingSystem;
      final String osVersion = Platform.operatingSystemVersion;

      final Map<String, dynamic> logEntry = {
        'timestamp': timeStr,
        'os': '$osName ($osVersion)',
        'activeScreen': _activeScreen,
        'breadcrumbs': List<String>.from(_breadcrumbs),
        'error': error.toString(),
        'library': library ?? 'Flutter Engine',
        'context': context ?? 'User Action / Nav',
        'stackTrace': stackTrace?.toString().split('\n').take(25).join('\n') ?? '',
      };

      // Synchronously/immediately persist log locally before any potential app freeze
      await _cacheLogLocally(logEntry);
      
      // Attempt async background sync to GitHub
      syncOfflineLogs();
    } catch (e) {
      debugPrint('RemoteLogger error recording failed: $e');
    }
  }

  /// Automatically purges any cached error logs older than [maxCacheRetentionDays] (7 days).
  Future<void> _purgeExpiredLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> logs = prefs.getStringList(_cacheKey) ?? [];
      if (logs.isEmpty) return;

      final now = DateTime.now();
      List<String> validLogs = [];

      for (String rawJson in logs) {
        try {
          final Map<String, dynamic> entry = jsonDecode(rawJson);
          if (entry['timestamp'] != null) {
            final DateTime logTime = DateTime.parse(entry['timestamp']);
            final int ageDays = now.difference(logTime).inDays;
            if (ageDays < maxCacheRetentionDays) {
              validLogs.add(rawJson);
            }
          }
        } catch (_) {
          // Drop corrupted entries
        }
      }

      await prefs.setStringList(_cacheKey, validLogs);
    } catch (e) {
      debugPrint('Error purging expired logs: $e');
    }
  }

  /// Caches the log entry locally to SharedPreferences & backup disk file with auto-purge.
  Future<void> _cacheLogLocally(Map<String, dynamic> logEntry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> logs = prefs.getStringList(_cacheKey) ?? [];
      logs.add(jsonEncode(logEntry));

      // Limit local cache count to last 40 entries
      if (logs.length > 40) {
        logs = logs.sublist(logs.length - 40);
      }
      await prefs.setStringList(_cacheKey, logs);

      // Backup copy to local app support directory
      final Directory appDir = await getApplicationSupportDirectory();
      final File backupFile = File('${appDir.path}${Platform.pathSeparator}error_logs.json');
      await backupFile.writeAsString(jsonEncode(logs));
    } catch (e) {
      debugPrint('Failed to cache error log locally: $e');
    }
  }

  /// Attempts to upload cached error logs to GitHub Issues.
  Future<void> syncOfflineLogs() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      await _purgeExpiredLogs();

      final prefs = await SharedPreferences.getInstance();
      List<String> logs = prefs.getStringList(_cacheKey) ?? [];
      if (logs.isEmpty) {
        _isSyncing = false;
        return;
      }

      List<String> remainingLogs = [];

      for (String rawJson in logs) {
        try {
          final Map<String, dynamic> entry = jsonDecode(rawJson);
          bool success = await _postIssueToGitHub(entry);
          if (!success) {
            remainingLogs.add(rawJson);
          }
        } catch (_) {
          // Drop unparseable entries
        }
      }

      await prefs.setStringList(_cacheKey, remainingLogs);
    } catch (e) {
      debugPrint('Error during log sync: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Posts structured issue report to GitHub Issues with token support.
  Future<bool> _postIssueToGitHub(Map<String, dynamic> log) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String customRepo = prefs.getString('github_repo_path') ?? '$_defaultRepoOwner/$_defaultRepoName';
      final String? token = prefs.getString('github_token');

      List<String> repoParts = customRepo.split('/');
      String owner = repoParts.length == 2 ? repoParts[0].trim() : _defaultRepoOwner;
      String repo = repoParts.length == 2 ? repoParts[1].trim() : _defaultRepoName;

      final String screen = log['activeScreen'] ?? 'Unknown Screen';
      final String issueTitle = '🚨 [$screen Crash] ${log['error'].toString().take(55)}';
      
      final List<dynamic> breadcrumbs = log['breadcrumbs'] ?? [];
      final String breadcrumbText = breadcrumbs.isEmpty 
          ? 'No recent actions recorded' 
          : breadcrumbs.join('\n');

      final String issueBody = '''
### 🚨 Automated Client Crash Report
- **Active Screen:** `${log['activeScreen']}`
- **Timestamp:** `${log['timestamp']}`
- **OS / Platform:** `${log['os']}`
- **Context / Library:** `${log['context']} (${log['library']})`

#### 👣 Recent User Action Trail (Breadcrumbs):
```text
$breadcrumbText
```

#### ❌ Error Details:
```text
${log['error']}
```

#### 📜 Stack Trace:
```text
${log['stackTrace']}
```
''';

      final Uri url = Uri.parse('https://api.github.com/repos/$owner/$repo/issues');
      
      final Map<String, String> headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/vnd.github+json',
      };

      if (token != null && token.trim().isNotEmpty) {
        headers['Authorization'] = 'Bearer ${token.trim()}';
      }

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({
          'title': issueTitle,
          'body': issueBody,
          'labels': ['bug', 'automated-report', 'client-crash'],
        }),
      );

      return response.statusCode == 201 || response.statusCode == 200;
    } catch (_) {
      return false; // Retries automatically on next connection
    }
  }
}

extension _StringTruncate on String {
  String take(int n) => length <= n ? this : '${substring(0, n)}...';
}
