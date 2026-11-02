import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pharmacy_email_account.dart';
import '../services/desktop_google_auth_service.dart';
import '../services/gmail_imap_service.dart';

class GmailAccountProvider extends ChangeNotifier {
  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/gmail.readonly',
  ];

  static const String _keyAccountsJson = 'pharmacy_email_accounts_json';
  static const String _keyActiveProfileId = 'pharmacy_active_profile_id';

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: _scopes);

  // Map of profileId -> PharmacyEmailAccount
  final Map<String, PharmacyEmailAccount> _accounts = {};
  String? _activeProfileId;
  bool _isLoading = false;
  String? _errorMessage;

  GmailAccountProvider() {
    _loadSavedAccounts();
  }

  Map<String, PharmacyEmailAccount> get accounts => _accounts;
  String? get activeProfileId => _activeProfileId;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  PharmacyEmailAccount? get activeAccount =>
      _activeProfileId != null ? _accounts[_activeProfileId] : null;

  bool get isDesktopPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// Load permanently saved accounts from storage
  Future<void> _loadSavedAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _activeProfileId = prefs.getString(_keyActiveProfileId);
      final jsonStr = prefs.getString(_keyAccountsJson);

      if (jsonStr != null) {
        final Map<String, dynamic> rawMap = jsonDecode(jsonStr);
        rawMap.forEach((profileId, data) {
          final accountMap = Map<String, dynamic>.from(data);
          final headersRaw = Map<String, dynamic>.from(accountMap['authHeaders'] ?? {});
          final headers = headersRaw.map((k, v) => MapEntry(k.toString(), v.toString()));

          String? savedRefreshToken = accountMap['refreshToken']?.toString();
          if (savedRefreshToken == null || savedRefreshToken.isEmpty) {
            savedRefreshToken = prefs.getString('gmail_refresh_token_$profileId') ??
                prefs.getString('gmail_refresh_token_global') ??
                prefs.getString('gmail_session_refresh_token');
          }

          String? savedAppPassword = accountMap['appPassword']?.toString() ??
              prefs.getString('gmail_app_password_$profileId') ??
              prefs.getString('gmail_app_password_global');

          _accounts[profileId] = PharmacyEmailAccount(
            profileId: profileId,
            email: accountMap['email'] ?? prefs.getString('gmail_app_email_$profileId') ?? '',
            displayName: accountMap['displayName'] ?? '',
            photoUrl: accountMap['photoUrl'],
            refreshToken: savedRefreshToken,
            appPassword: savedAppPassword,
            authHeaders: headers,
          );
        });
      }

      if (_activeProfileId == null && _accounts.isNotEmpty) {
        _activeProfileId = _accounts.keys.first;
      }
      notifyListeners();

      // Proactive background silent refresh on launch for OAuth accounts
      refreshAccessTokenForActiveAccount();
    } catch (e) {
      debugPrint("Error loading saved email accounts: $e");
    }
  }

  /// Save account map and active profile ID to persistent storage
  Future<void> _saveAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_activeProfileId != null) {
        await prefs.setString(_keyActiveProfileId, _activeProfileId!);
      } else {
        await prefs.remove(_keyActiveProfileId);
      }

      Map<String, dynamic> exportMap = {};
      _accounts.forEach((profileId, account) {
        exportMap[profileId] = {
          'profileId': account.profileId,
          'email': account.email,
          'displayName': account.displayName,
          'photoUrl': account.photoUrl,
          'refreshToken': account.refreshToken,
          'appPassword': account.appPassword,
          'authHeaders': account.authHeaders,
        };
        if (account.refreshToken != null && account.refreshToken!.isNotEmpty) {
          prefs.setString('gmail_refresh_token_$profileId', account.refreshToken!);
          prefs.setString('gmail_refresh_token_global', account.refreshToken!);
          prefs.setString('gmail_session_refresh_token', account.refreshToken!);
        }
        if (account.appPassword != null && account.appPassword!.isNotEmpty) {
          prefs.setString('gmail_app_email_$profileId', account.email);
          prefs.setString('gmail_app_password_$profileId', account.appPassword!);
          prefs.setString('gmail_app_email_global', account.email);
          prefs.setString('gmail_app_password_global', account.appPassword!);
        }
      });

      await prefs.setString(_keyAccountsJson, jsonEncode(exportMap));

      if (activeAccount != null) {
        await prefs.setString('gmail_session_email', activeAccount!.email);
        await prefs.setString('gmail_session_display_name', activeAccount!.displayName);
        if (activeAccount!.photoUrl != null) {
          await prefs.setString('gmail_session_photo_url', activeAccount!.photoUrl!);
        }
        if (activeAccount!.refreshToken != null && activeAccount!.refreshToken!.isNotEmpty) {
          await prefs.setString('gmail_session_refresh_token', activeAccount!.refreshToken!);
        }
        await prefs.setString('gmail_session_headers_json', jsonEncode(activeAccount!.authHeaders));
      }
    } catch (e) {
      debugPrint("Error saving email accounts: $e");
    }
  }

  /// Updates auth headers and persists immediately to storage
  Future<void> updateAuthHeadersForProfile(String profileId, Map<String, String> newHeaders) async {
    final account = _accounts[profileId];
    if (account != null) {
      account.authHeaders = Map.from(newHeaders);
      await _saveAccounts();
      notifyListeners();
    }
  }

  /// Refreshes expired access token in the background using permanent Refresh Token
  Future<bool> refreshAccessTokenForActiveAccount({bool force = false}) async {
    final account = activeAccount;
    if (account == null) return false;

    // If access token was issued/refreshed less than 45 mins ago and force is false, skip network call
    if (!force &&
        account.lastTokenRefreshTime != null &&
        DateTime.now().difference(account.lastTokenRefreshTime!).inMinutes < 45) {
      return true;
    }

    if (account.refreshToken == null || account.refreshToken!.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      account.refreshToken = prefs.getString('gmail_refresh_token_${account.profileId}') ??
          prefs.getString('gmail_refresh_token_global') ??
          prefs.getString('gmail_session_refresh_token');
    }

    if (account.refreshToken == null || account.refreshToken!.isEmpty) {
      debugPrint("GmailAccountProvider: No refresh token available for ${account.email}");
      return false;
    }

    try {
      final newAccessToken =
          await DesktopGoogleAuthService.refreshAccessToken(account.refreshToken!);
      if (newAccessToken != null && newAccessToken.isNotEmpty) {
        account.authHeaders = {'Authorization': 'Bearer $newAccessToken'};
        account.lastTokenRefreshTime = DateTime.now();
        await _saveAccounts();
        notifyListeners();
        debugPrint("GmailAccountProvider: Refreshed token successfully for ${account.email}");
        return true;
      }
    } catch (e) {
      debugPrint("GmailAccountProvider: Error refreshing background token: $e");
    }
    return false;
  }

  /// Sign in a Google account and link it to a specific pharmacy profile ID
  Future<bool> signInAccountForProfile(String profileId) async {
    _setLoading(true);
    _errorMessage = null;

    try {
      if (isDesktopPlatform) {
        // Desktop Browser Loopback OAuth Flow
        final result = await DesktopGoogleAuthService.authenticate();
        if (result == null) {
          _setLoading(false);
          return false;
        }

        final existingToken = _accounts[profileId]?.refreshToken;
        final finalRefreshToken = (result.refreshToken != null && result.refreshToken!.isNotEmpty)
            ? result.refreshToken
            : existingToken;

        _accounts[profileId] = PharmacyEmailAccount(
          profileId: profileId,
          email: result.email,
          displayName: result.displayName,
          photoUrl: result.photoUrl,
          refreshToken: finalRefreshToken,
          authHeaders: result.authHeaders,
          lastTokenRefreshTime: DateTime.now(),
        );

        if (finalRefreshToken != null && finalRefreshToken.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('gmail_refresh_token_$profileId', finalRefreshToken);
          await prefs.setString('gmail_refresh_token_global', finalRefreshToken);
        }
      } else {
        // Mobile / Web Native Google Sign-In Flow
        await _googleSignIn.signOut();
        final account = await _googleSignIn.signIn();
        if (account == null) {
          _setLoading(false);
          return false;
        }

        final authHeaders = await account.authHeaders;

        _accounts[profileId] = PharmacyEmailAccount(
          profileId: profileId,
          email: account.email,
          displayName: account.displayName ?? account.email,
          photoUrl: account.photoUrl,
          authHeaders: authHeaders,
        );
      }

      _activeProfileId = profileId;
      await _saveAccounts();
      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = "Sign-In Failed: $e";
      _setLoading(false);
      return false;
    }
  }

  /// Connect or save Gmail using a 16-character App Password directly (IMAP/SSL)
  Future<bool> connectWithAppPassword({
    required String profileId,
    required String email,
    required String appPassword,
  }) async {
    _setLoading(true);
    _errorMessage = null;

    try {
      final isOk = await GmailImapService.instance.testConnection(email, appPassword);
      if (!isOk) {
        _errorMessage = "Invalid App Password or Email Address.";
        _setLoading(false);
        return false;
      }

      final cleanEmail = email.trim();
      final cleanPassword = GmailImapService.cleanAppPassword(appPassword);

      _accounts[profileId] = PharmacyEmailAccount(
        profileId: profileId,
        email: cleanEmail,
        displayName: cleanEmail.contains('@') ? cleanEmail.split('@').first : cleanEmail,
        appPassword: cleanPassword,
        authHeaders: {},
      );

      _activeProfileId = profileId;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('gmail_app_email_$profileId', cleanEmail);
      await prefs.setString('gmail_app_password_$profileId', cleanPassword);
      await prefs.setString('gmail_app_email_global', cleanEmail);
      await prefs.setString('gmail_app_password_global', cleanPassword);

      await _saveAccounts();
      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      _setLoading(false);
      return false;
    }
  }

  /// Switch active inbox to another signed-in pharmacy profile
  void switchActiveProfile(String profileId) {
    if (_accounts.containsKey(profileId)) {
      _activeProfileId = profileId;
      _saveAccounts();
      notifyListeners();
    }
  }

  /// Sign out a specific pharmacy profile email account
  Future<void> signOutProfile(String profileId) async {
    if (_accounts.containsKey(profileId)) {
      _accounts.remove(profileId);
      if (_activeProfileId == profileId) {
        _activeProfileId = _accounts.keys.isNotEmpty ? _accounts.keys.first : null;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('gmail_refresh_token_$profileId');
      await prefs.remove('gmail_app_email_$profileId');
      await prefs.remove('gmail_app_password_$profileId');
      await prefs.remove('gmail_invoices_cache_$profileId');
      await prefs.remove('gmail_invoices_timestamp_$profileId');

      if (_accounts.isEmpty) {
        await prefs.remove('gmail_refresh_token_global');
        await prefs.remove('gmail_session_refresh_token');
        await prefs.remove('gmail_app_email_global');
        await prefs.remove('gmail_app_password_global');
        await prefs.remove('gmail_session_email');
        await prefs.remove('gmail_session_display_name');
        await prefs.remove('gmail_session_photo_url');
        await prefs.remove('gmail_session_headers_json');
        await prefs.remove('gmail_invoices_cache_global');
      }

      await _saveAccounts();
      notifyListeners();
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
