import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_sync_service.dart';
import 'supabase_realtime_service.dart';
import 'delta_sync_service.dart';
import '../utils/app_logger.dart';

enum ServerConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

enum AppSyncMode {
  offline,
  lanOnly,
  hybridCloud,
  pureCloud,
}

class ServerConfigService extends ChangeNotifier {
  ServerConfigService._internal();
  static final ServerConfigService instance = ServerConfigService._internal();

  static const String _keyServerMode = 'server_mode_enabled';
  static const String _keySupabaseUrl = 'supabase_server_url';
  static const String _keySupabaseAnonKey = 'supabase_anon_key';
  static const String _keyStoreBranchId = 'store_branch_id';
  static const String _keyTerminalId = 'terminal_id';
  static const String _keyPruningTimerYears = 'cloud_data_pruning_timer_years';
  static const String _keyAutoSync = 'auto_sync_enabled';
  static const String _keySyncMode = 'app_sync_mode';
  static const String _keyLanSync = 'lan_sync_enabled';
  static const String _keyBgSyncOnSave = 'bg_sync_on_save';
  static const String _keyLastKnownEpoch = 'last_known_database_epoch';

  static const String _keyMachineUuid = 'machine_unique_uuid';
  static const String _keyTerminalConfigured = 'terminal_id_configured';

  static const String _defaultSupabaseUrl = 'https://megmcfgqaosmqzvlirbt.supabase.co';
  static const String _defaultSupabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1lZ21jZmdxYW9zbXF6dmxpcmJ0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE4MTI4NzgsImV4cCI6MjEwNzM4ODg3OH0.GfO9G4-OUBS3t6j_VcCt6aRBsIMu_tXMVSzENPLsPIo';

  bool _isServerModeEnabled = true;
  bool _isLanSyncEnabled = true;
  bool _bgSyncOnSave = true;
  AppSyncMode _syncMode = AppSyncMode.hybridCloud;
  String _supabaseUrl = _defaultSupabaseUrl;
  String _supabaseAnonKey = _defaultSupabaseAnonKey;
  String _storeBranchId = 'MAIN_STORE';
  String _terminalId = 'POS-01';
  String _machineUuid = '';
  bool _isTerminalConfigured = false;
  String _lastKnownEpoch = '';
  int _cloudDataPruningTimerYears = 3;
  bool _autoSyncEnabled = true;
  bool _isWiping = false;
  ServerConnectionStatus _status = ServerConnectionStatus.disconnected;
  String _lastErrorMessage = '';

  bool get isServerModeEnabled => _isServerModeEnabled;
  bool get isLanSyncEnabled => _isLanSyncEnabled;
  bool get bgSyncOnSave => _bgSyncOnSave;
  String get lastKnownEpoch => _lastKnownEpoch;
  AppSyncMode get syncMode => _syncMode;
  bool get isPureCloud => _syncMode == AppSyncMode.pureCloud;
  String get supabaseUrl => _supabaseUrl;
  String get supabaseAnonKey => _supabaseAnonKey;
  String get storeBranchId => _storeBranchId;
  String get terminalId => _terminalId;
  String get machineUuid => _machineUuid;
  bool get isTerminalConfigured => _isTerminalConfigured;
  bool get isWiping => _isWiping;

  Future<void> setTerminalId(String id) async {
    _terminalId = id.trim().toUpperCase();
    _isTerminalConfigured = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyTerminalId, _terminalId);
      await prefs.setBool(_keyTerminalConfigured, true);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setStoreBranchId(String branchId) async {
    _storeBranchId = branchId.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyStoreBranchId, _storeBranchId);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setLastKnownEpoch(String epoch) async {
    _lastKnownEpoch = epoch;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLastKnownEpoch, epoch);
    } catch (e) {
      debugPrint('Error saving lastKnownEpoch: $e');
    }
  }

  Future<void> setBgSyncOnSave(bool enabled) async {
    _bgSyncOnSave = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyBgSyncOnSave, enabled);
    } catch (e) {
      debugPrint('Error saving bgSyncOnSave: $e');
    }
    notifyListeners();
  }

  void setWiping(bool value) {
    _isWiping = value;
    if (value) {
      _status = ServerConnectionStatus.connected;
      _lastErrorMessage = '';
      notifyListeners();
    }
  }

  /// Formatted entry prefix derived from terminal ID (e.g., T1-, T2-, T3-).
  /// Ensures PC 1, PC 2, and PC 3 never generate overlapping invoice numbers.
  String get terminalPrefix {
    final cleanId = _terminalId.replaceAll(RegExp(r'[^0-9]'), '');
    final numId = int.tryParse(cleanId);
    if (numId != null) return 'T$numId-';

    final upper = _terminalId.trim().toUpperCase();
    if (upper.contains('PC2') || upper.contains('PC-2') || upper.contains('TERM2') || upper.contains('TERMINAL2')) return 'T2-';
    if (upper.contains('PC3') || upper.contains('PC-3') || upper.contains('TERM3') || upper.contains('TERMINAL3')) return 'T3-';
    if (upper.contains('PC1') || upper.contains('PC-1') || upper.contains('TERM1') || upper.contains('TERMINAL1')) return 'T1-';

    final trimmed = upper.replaceAll(RegExp(r'[^A-Z0-9-]'), '');
    return trimmed.isNotEmpty ? '$trimmed-' : 'T1-';
  }

  String? _duplicateTerminalWarning;
  String? get duplicateTerminalWarning => _duplicateTerminalWarning;

  /// Verifies that other active computers on Supabase do not share the exact same Terminal ID / Terminal Prefix.
  /// Reports a setup issue if duplicate terminal configuration is detected.
  Future<String?> verifyDistinctTerminalId() async {
    final cleanUrl = cleanServerUrl(_supabaseUrl);
    if (cleanUrl.isEmpty || _supabaseAnonKey.isEmpty) return null;

    if (_terminalId.trim().isEmpty) {
      _duplicateTerminalWarning = "SETUP ISSUE: Terminal ID is missing! Each PC must have a unique Terminal ID.";
      notifyListeners();
      return _duplicateTerminalWarning;
    }

    try {
      final uri = Uri.parse('$cleanUrl/rest/v1/active_computers?branch_id=eq.$_storeBranchId&select=machine_id,terminal_id,last_seen_at');
      final response = await http.get(uri, headers: restHeaders).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List list = jsonDecode(response.body) as List;
        final currentTerm = _terminalId.trim().toUpperCase();
        final currentPref = terminalPrefix.toUpperCase();
        final now = DateTime.now();

        for (var item in list) {
          final otherMachine = item['machine_id']?.toString().trim() ?? '';
          if (otherMachine.isNotEmpty && otherMachine == _machineUuid) continue;

          final lastSeenStr = item['last_seen_at']?.toString() ?? '';
          final lastSeen = DateTime.tryParse(lastSeenStr);
          if (lastSeen != null && now.difference(lastSeen).inMinutes > 10) continue;

          final otherTerm = item['terminal_id']?.toString().trim().toUpperCase() ?? '';
          if (otherTerm.isEmpty) continue;

          // 1. Exact Duplicate Terminal ID Check
          if (otherTerm == currentTerm) {
            _duplicateTerminalWarning = "CRITICAL SETUP CONFLICT: Another computer ($otherMachine) is actively using the identical Terminal ID '$_terminalId' in branch '$_storeBranchId'. Please assign a distinct Terminal ID (e.g. POS-02) in Server Settings.";
            notifyListeners();
            return _duplicateTerminalWarning;
          }

          // 2. Overlapping Sequence Prefix Check
          final cleanOther = otherTerm.replaceAll(RegExp(r'[^0-9]'), '');
          final numOther = int.tryParse(cleanOther);
          final otherPref = numOther != null ? 'T$numOther-' : (cleanOther.isNotEmpty ? 'T$cleanOther-' : '$otherTerm-');

          if (otherPref == currentPref) {
            _duplicateTerminalWarning = "SETUP ISSUE DETECTED: Both PCs share terminal sequence prefix '$currentPref' (This PC: '$_terminalId', Other PC: '$otherTerm'). Please assign distinct Terminal IDs (e.g. POS-01 and POS-02) in Server Settings.";
            notifyListeners();
            return _duplicateTerminalWarning;
          }
        }
      }

      if (!_isTerminalConfigured && _terminalId == 'POS-01') {
        _duplicateTerminalWarning = "NOTICE: Terminal ID is using default 'POS-01'. If multiple PCs are running, ensure other computers use distinct IDs (e.g., POS-02).";
        notifyListeners();
        return _duplicateTerminalWarning;
      }

      _duplicateTerminalWarning = null;
    } catch (e) {
      debugPrint('verifyDistinctTerminalId notice: $e');
    }
    notifyListeners();
    return _duplicateTerminalWarning;
  }

  int get cloudDataPruningTimerYears => _cloudDataPruningTimerYears;
  bool get autoSyncEnabled => _autoSyncEnabled;
  ServerConnectionStatus get status => _status;
  String get lastErrorMessage => _lastErrorMessage;
  bool get isConnected => _status == ServerConnectionStatus.connected;

  /// Standard HTTP headers for Supabase REST API requests
  Map<String, String> get restHeaders {
    return {
      'apikey': _supabaseAnonKey.trim(),
      'Authorization': 'Bearer ${_supabaseAnonKey.trim()}',
      'Content-Type': 'application/json',
      'Prefer': 'resolution=merge-duplicates',
      'Accept-Encoding': 'gzip, deflate',
    };
  }

  static String cleanServerUrl(String rawUrl) {
    var clean = rawUrl.trim();
    while (clean.endsWith('/') || clean.endsWith('.')) {
      clean = clean.substring(0, clean.length - 1).trim();
    }
    // Remove accidentally pasted paths like /rest/v1 or /auth/v1
    if (clean.toLowerCase().endsWith('/rest/v1')) {
      clean = clean.substring(0, clean.length - 8).trim();
    } else if (clean.toLowerCase().endsWith('/auth/v1')) {
      clean = clean.substring(0, clean.length - 8).trim();
    }
    while (clean.endsWith('/') || clean.endsWith('.')) {
      clean = clean.substring(0, clean.length - 1).trim();
    }
    if (clean.toLowerCase().endsWith('.supabase.c')) {
      clean = '${clean}o';
    }
    return clean;
  }

  /// Initializes persisted server configurations on app launch and auto-connects if enabled.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _supabaseUrl = cleanServerUrl(prefs.getString(_keySupabaseUrl) ?? _defaultSupabaseUrl);
      _supabaseAnonKey = prefs.getString(_keySupabaseAnonKey) ?? _defaultSupabaseAnonKey;
      if (_supabaseUrl.isEmpty) _supabaseUrl = _defaultSupabaseUrl;
      if (_supabaseAnonKey.isEmpty) _supabaseAnonKey = _defaultSupabaseAnonKey;
      _storeBranchId = prefs.getString(_keyStoreBranchId) ?? 'MAIN_STORE';
      _machineUuid = prefs.getString(_keyMachineUuid) ?? '';
      if (_machineUuid.isEmpty) {
        _machineUuid = 'MACH_${DateTime.now().millisecondsSinceEpoch}_${(100000 + DateTime.now().microsecond % 900000)}';
        await prefs.setString(_keyMachineUuid, _machineUuid);
      }
      _isTerminalConfigured = prefs.getBool(_keyTerminalConfigured) ?? false;
      var savedTerminal = prefs.getString(_keyTerminalId) ?? '';
      if (savedTerminal.isEmpty) {
        savedTerminal = 'POS-01';
        await prefs.setString(_keyTerminalId, savedTerminal);
      }
      _terminalId = savedTerminal;

      _cloudDataPruningTimerYears = prefs.getInt(_keyPruningTimerYears) ?? 3;
      _autoSyncEnabled = prefs.getBool(_keyAutoSync) ?? true;
      _isLanSyncEnabled = prefs.getBool(_keyLanSync) ?? true;
      _bgSyncOnSave = prefs.getBool(_keyBgSyncOnSave) ?? true;
      _lastKnownEpoch = prefs.getString(_keyLastKnownEpoch) ?? '';

      // Always auto-enable Server Mode on startup whenever credentials exist
      _isServerModeEnabled = _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;
      await prefs.setBool(_keyServerMode, _isServerModeEnabled);

      // Restore saved sync mode if valid
      final savedSyncIdx = prefs.getInt(_keySyncMode);
      if (savedSyncIdx != null && savedSyncIdx >= 0 && savedSyncIdx < AppSyncMode.values.length) {
        _syncMode = AppSyncMode.values[savedSyncIdx];
      } else {
        _syncMode = _isServerModeEnabled ? AppSyncMode.hybridCloud : (_isLanSyncEnabled ? AppSyncMode.lanOnly : AppSyncMode.offline);
      }

      if (_supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
        _status = ServerConnectionStatus.connecting;
        notifyListeners();

        // Auto connect on software startup with Server Mode enabled
        unawaited(connectServer(
          url: _supabaseUrl,
          anonKey: _supabaseAnonKey,
          branchId: _storeBranchId,
          enableMode: true,
          silent: false,
        ));
      } else {
        _status = ServerConnectionStatus.disconnected;
        notifyListeners();
      }
      _startConnectionWatchdog();
    } catch (e) {
      debugPrint('ServerConfigService init error: $e');
      _status = ServerConnectionStatus.error;
      _lastErrorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Sets the sync architecture mode (Offline, LAN Only, Hybrid Cloud, Pure Cloud Live)
  Future<void> setSyncMode(AppSyncMode mode) async {
    _syncMode = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keySyncMode, mode.index);

      switch (mode) {
        case AppSyncMode.offline:
          _isLanSyncEnabled = false;
          _isServerModeEnabled = false;
          await prefs.setBool(_keyLanSync, false);
          await prefs.setBool(_keyServerMode, false);
          _status = ServerConnectionStatus.disconnected;
          break;
        case AppSyncMode.lanOnly:
          _isLanSyncEnabled = true;
          _isServerModeEnabled = false;
          await prefs.setBool(_keyLanSync, true);
          await prefs.setBool(_keyServerMode, false);
          _status = ServerConnectionStatus.disconnected;
          break;
        case AppSyncMode.hybridCloud:
        case AppSyncMode.pureCloud:
          _isLanSyncEnabled = true;
          _isServerModeEnabled = true;
          await prefs.setBool(_keyLanSync, true);
          await prefs.setBool(_keyServerMode, true);
          if (_supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
            unawaited(connectServer(
              url: _supabaseUrl,
              anonKey: _supabaseAnonKey,
              branchId: _storeBranchId,
              enableMode: true,
              silent: true,
            ));
          }
          break;
      }
    } catch (e) {
      debugPrint('Error setting sync mode: $e');
    }
    notifyListeners();
  }

  /// Toggles LAN UDP broadcast local sync.
  Future<void> setLanSyncEnabled(bool enabled) async {
    _isLanSyncEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyLanSync, enabled);
      _updateSyncModeFromToggles();
    } catch (e) {
      debugPrint('Error saving LAN sync setting: $e');
    }
    notifyListeners();
  }

  void _updateSyncModeFromToggles() {
    if (_isServerModeEnabled && _isLanSyncEnabled) {
      _syncMode = AppSyncMode.hybridCloud;
    } else if (_isLanSyncEnabled) {
      _syncMode = AppSyncMode.lanOnly;
    } else {
      _syncMode = AppSyncMode.offline;
    }
  }

  Timer? _reconnectWatchdogTimer;

  void _startConnectionWatchdog() {
    _reconnectWatchdogTimer?.cancel();

    // Quick startup retries at 5s and 15s if initial connection attempt didn't succeed immediately
    for (var delaySeconds in [5, 15]) {
      Future.delayed(Duration(seconds: delaySeconds), () async {
        if (_isWiping || !_isServerModeEnabled) return;
        if (_supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
          if (_status != ServerConnectionStatus.connected) {
            final isAlive = await testConnection(_supabaseUrl, _supabaseAnonKey);
            if (isAlive) {
              _status = ServerConnectionStatus.connected;
              _lastErrorMessage = '';
              notifyListeners();
              SupabaseSyncService.instance.initRealtimeListeners();
              unawaited(SupabaseRealtimeService.instance.ensureRealtimeListenersActive());
              SupabaseSyncService.instance.triggerInstantSync();
              unawaited(DeltaSyncService.instance.triggerReconnectionCatchupSync());
            }
          }
        }
      });
    }

    _reconnectWatchdogTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_isWiping || !_isServerModeEnabled) return;
      if (_supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
        if (_status != ServerConnectionStatus.connected) {
          final isAlive = await testConnection(_supabaseUrl, _supabaseAnonKey);
          if (isAlive) {
            _status = ServerConnectionStatus.connected;
            _lastErrorMessage = '';
            notifyListeners();
            SupabaseSyncService.instance.initRealtimeListeners();
            unawaited(SupabaseRealtimeService.instance.ensureRealtimeListenersActive());
            SupabaseSyncService.instance.triggerInstantSync();
            unawaited(DeltaSyncService.instance.triggerReconnectionCatchupSync());
          }
        }
      }
    });
  }

  /// Sets the cloud data retention / pruning timer in years (0 = disabled/keep all).
  Future<void> setCloudDataPruningTimerYears(int years) async {
    _cloudDataPruningTimerYears = years;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyPruningTimerYears, years);
    } catch (e) {
      debugPrint('Error saving pruning timer: $e');
    }
    notifyListeners();
  }

  /// Sets whether automatic background cloud sync is enabled.
  Future<void> setAutoSyncEnabled(bool enabled) async {
    _autoSyncEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAutoSync, enabled);
    } catch (e) {
      debugPrint('Error saving auto sync setting: $e');
    }
    notifyListeners();
  }

  /// Sets the terminal identifier for this computer (e.g., POS-01, POS-02).
  Future<void> setTerminalId(String terminalId) async {
    _terminalId = terminalId.trim().isEmpty ? 'POS-01' : terminalId.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyTerminalId, _terminalId);
    } catch (e) {
      debugPrint('Error saving terminal ID: $e');
    }
    notifyListeners();
  }

  /// Saves settings and connects or reconnects to the specified Supabase instance dynamically.
  Future<bool> connectServer({
    required String url,
    required String anonKey,
    String branchId = 'MAIN_STORE',
    required bool enableMode,
    bool silent = false,
  }) async {
    _status = ServerConnectionStatus.connecting;
    _lastErrorMessage = '';
    if (!silent) notifyListeners();

    final cleanUrl = cleanServerUrl(url);
    final cleanKey = anonKey.trim();
    final cleanBranch = branchId.trim().isEmpty ? 'MAIN_STORE' : branchId.trim();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyServerMode, enableMode);
      await prefs.setString(_keySupabaseUrl, cleanUrl);
      await prefs.setString(_keySupabaseAnonKey, cleanKey);
      await prefs.setString(_keyStoreBranchId, cleanBranch);

      _isServerModeEnabled = enableMode;
      _supabaseUrl = cleanUrl;
      _supabaseAnonKey = cleanKey;
      _storeBranchId = cleanBranch;

      if (!enableMode || cleanUrl.isEmpty || cleanKey.isEmpty) {
        _status = ServerConnectionStatus.disconnected;
        notifyListeners();
        return true;
      }

      // Verify connection via quick REST ping
      final bool isAlive = await testConnection(cleanUrl, cleanKey);
      if (isAlive) {
        _status = ServerConnectionStatus.connected;
        _lastErrorMessage = '';
        AppLogger.instance.supabase("SERVER CONNECTED successfully. Branch: $_storeBranchId, URL: $cleanUrl");
      } else {
        _status = ServerConnectionStatus.error;
        _lastErrorMessage = 'Server reached, but returned invalid response.';
        AppLogger.instance.supabase("SERVER DISCONNECTED / ERROR: Invalid ping response from $cleanUrl", level: LogLevel.error);
      }
    } catch (e) {
      _status = ServerConnectionStatus.error;
      _lastErrorMessage = 'Failed to connect: $e';
      AppLogger.instance.supabase("SERVER DISCONNECTED / CONNECTION ERROR", details: e.toString(), level: LogLevel.error);
      debugPrint('Supabase connection error: $e');
    }

    notifyListeners();
    return _status == ServerConnectionStatus.connected;
  }

  /// Disables server mode and returns the application to local-only standalone operation.
  Future<void> disableServerMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyServerMode, false);
    _isServerModeEnabled = false;
    _status = ServerConnectionStatus.disconnected;
    _lastErrorMessage = '';
    notifyListeners();
  }

  /// Tests connection latency and health for a given Supabase URL and Key.
  Future<bool> testConnection(String url, String anonKey) async {
    if (_isWiping) return true;
    _lastErrorMessage = '';
    final cleanUrl = cleanServerUrl(url);
    final cleanKey = anonKey.trim();

    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      const newMsg = 'Invalid URL format (must start with https://)';
      if (_status != ServerConnectionStatus.error || _lastErrorMessage != newMsg) {
        _lastErrorMessage = newMsg;
        _status = ServerConnectionStatus.error;
        notifyListeners();
      }
      return false;
    }

    if (cleanKey.isEmpty) {
      const newMsg = 'API Key is missing. Please enter your Supabase anon key.';
      if (_status != ServerConnectionStatus.error || _lastErrorMessage != newMsg) {
        _lastErrorMessage = newMsg;
        _status = ServerConnectionStatus.error;
        notifyListeners();
      }
      return false;
    }

    try {
      // Ping Supabase Gateway auth settings endpoint to verify URL reachability and API key validity
      // without depending on business table RLS permissions
      var uri = Uri.parse('$cleanUrl/auth/v1/settings');
      var res = await http.get(uri, headers: {
        'apikey': cleanKey,
        'Authorization': 'Bearer $cleanKey',
      }).timeout(const Duration(seconds: 10));

      debugPrint('Supabase connection check status code: ${res.statusCode}');

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (_status != ServerConnectionStatus.connected || _lastErrorMessage.isNotEmpty) {
          _status = ServerConnectionStatus.connected;
          _lastErrorMessage = '';
          notifyListeners();
        }
        return true;
      }

      // Fallback check to table REST endpoint if GoTrue auth service is disabled or self-hosted
      if (res.statusCode == 404) {
        final tableUri = Uri.parse('$cleanUrl/rest/v1/sales_invoices?select=entry_no&limit=1');
        final tableRes = await http.get(tableUri, headers: {
          'apikey': cleanKey,
          'Authorization': 'Bearer $cleanKey',
        }).timeout(const Duration(seconds: 10));

        if (tableRes.statusCode >= 200 && tableRes.statusCode < 300) {
          if (_status != ServerConnectionStatus.connected || _lastErrorMessage.isNotEmpty) {
            _status = ServerConnectionStatus.connected;
            _lastErrorMessage = '';
            notifyListeners();
          }
          return true;
        }
      }

      String newError = 'HTTP ${res.statusCode}: Connection failed.';
      if (res.statusCode == 401 || res.statusCode == 403) {
        if (res.body.contains('permission denied') || res.body.contains('42501')) {
          newError = 'Database Permission Error (42501): The "anon" role lacks permissions on Supabase.';
        } else if (res.body.contains('relation') && res.body.contains('does not exist')) {
          newError = 'Database Tables Missing: Schema not created on Supabase.';
        } else {
          newError = 'HTTP ${res.statusCode} Unauthorized: Invalid API Key. Please verify your Supabase anon key.';
        }
      } else if (res.statusCode == 404) {
        newError = 'HTTP 404: Incorrect Supabase URL or project path.';
      } else if (res.statusCode >= 500) {
        newError = 'HTTP ${res.statusCode}: Server or database error/starting up.';
      }

      if (_status != ServerConnectionStatus.error || _lastErrorMessage != newError) {
        _status = ServerConnectionStatus.error;
        _lastErrorMessage = newError;
        notifyListeners();
      }
      return false;
    } catch (e) {
      debugPrint('Supabase connection attempt error: $e');
      String newError = 'Connection Failed: $e';
      if (e.toString().contains('11001') || e.toString().contains('Failed host lookup') || e.toString().contains('SocketException')) {
        newError = 'Offline Mode: Unable to resolve host or no Internet connection.';
      } else if (e is TimeoutException) {
        newError = 'Connection Timeout: Server did not respond in time.';
      }

      if (_status != ServerConnectionStatus.error || _lastErrorMessage != newError) {
        _status = ServerConnectionStatus.error;
        _lastErrorMessage = newError;
        notifyListeners();
      }
      return false;
    }
  }
}
