import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/email_item.dart';
import 'desktop_google_auth_service.dart';
import 'google_auth_client.dart';

class UserAuthInfo {
  final String email;
  final String displayName;
  final String? photoUrl;
  final String? refreshToken;
  Map<String, String> authHeaders;

  UserAuthInfo({
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.refreshToken,
    required this.authHeaders,
  });
}

class GmailService {
  GmailService();
  static final GmailService instance = GmailService();

  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/gmail.readonly',
  ];

  static const String _keyEmail = 'gmail_session_email';
  static const String _keyDisplayName = 'gmail_session_display_name';
  static const String _keyPhotoUrl = 'gmail_session_photo_url';
  static const String _keyHeadersJson = 'gmail_session_headers_json';
  static const String _keyAccountsJson = 'pharmacy_email_accounts_json';
  static const String _keyActiveProfileId = 'pharmacy_active_profile_id';

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: _scopes);

  UserAuthInfo? _currentUser;
  UserAuthInfo? get currentUser => _currentUser;

  bool get isDesktopPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// Default query filter to show ONLY supplier invoices, bills, and orders, ignoring system emails
  static const String defaultSupplierFilterQuery =
      '(invoice OR bill OR purchase OR order OR supplier OR medicine OR pharma) -from:no-reply@accounts.google.com -from:accounts@firefox.com';

  /// Save logged in user session to local persistent storage
  Future<void> _saveSession(UserAuthInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmail, info.email);
    await prefs.setString(_keyDisplayName, info.displayName);
    if (info.photoUrl != null) {
      await prefs.setString(_keyPhotoUrl, info.photoUrl!);
    } else {
      await prefs.remove(_keyPhotoUrl);
    }
    if (info.refreshToken != null && info.refreshToken!.isNotEmpty) {
      await prefs.setString('gmail_session_refresh_token', info.refreshToken!);
    }
    await prefs.setString(_keyHeadersJson, jsonEncode(info.authHeaders));
  }

  /// Clear persistent login session from storage
  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyDisplayName);
    await prefs.remove(_keyPhotoUrl);
    await prefs.remove(_keyHeadersJson);
    await prefs.remove('gmail_session_refresh_token');
  }

  /// Automatically restore persistent sign-in session on app startup
  Future<UserAuthInfo?> signInSilently() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Try single session keys
      String? savedEmail = prefs.getString(_keyEmail);
      String? savedDisplayName = prefs.getString(_keyDisplayName);
      String? savedPhotoUrl = prefs.getString(_keyPhotoUrl);
      String? savedHeadersJson = prefs.getString(_keyHeadersJson);
      String? savedRefreshToken = prefs.getString('gmail_session_refresh_token') ??
          prefs.getString('gmail_refresh_token_global');

      // 2. Try multi-account provider keys if single session keys are empty
      if (savedEmail == null || savedHeadersJson == null) {
        final activeId = prefs.getString(_keyActiveProfileId);
        final accountsJson = prefs.getString(_keyAccountsJson);

        if (accountsJson != null) {
          final Map<String, dynamic> rawMap = jsonDecode(accountsJson);
          String? targetKey = activeId;
          if (targetKey == null || !rawMap.containsKey(targetKey)) {
            if (rawMap.isNotEmpty) targetKey = rawMap.keys.first;
          }

          if (targetKey != null && rawMap.containsKey(targetKey)) {
            final accMap = Map<String, dynamic>.from(rawMap[targetKey]);
            savedEmail = accMap['email'];
            savedDisplayName = accMap['displayName'];
            savedPhotoUrl = accMap['photoUrl'];
            savedRefreshToken ??= accMap['refreshToken']?.toString();
            final Map<String, dynamic> headersRaw =
                Map<String, dynamic>.from(accMap['authHeaders'] ?? {});
            savedHeadersJson = jsonEncode(headersRaw);
          }
        }
      }

      if (savedEmail != null && savedHeadersJson != null) {
        final Map<String, dynamic> decodedMap = jsonDecode(savedHeadersJson);
        final Map<String, String> headers =
            decodedMap.map((k, v) => MapEntry(k.toString(), v.toString()));

        _currentUser = UserAuthInfo(
          email: savedEmail,
          displayName: savedDisplayName ?? savedEmail,
          photoUrl: savedPhotoUrl,
          refreshToken: savedRefreshToken,
          authHeaders: headers,
        );

        // Attempt silent background token refresh if refresh token is available
        if (savedRefreshToken != null && savedRefreshToken.isNotEmpty) {
          final newToken = await DesktopGoogleAuthService.refreshAccessToken(savedRefreshToken);
          if (newToken != null && newToken.isNotEmpty) {
            _currentUser!.authHeaders = {'Authorization': 'Bearer $newToken'};
            await _saveSession(_currentUser!);
          }
        }

        return _currentUser;
      }

      // Mobile / Web fallback silent sign in
      if (!isDesktopPlatform) {
        final account = await _googleSignIn.signInSilently();
        if (account != null) {
          final headers = await account.authHeaders;
          _currentUser = UserAuthInfo(
            email: account.email,
            displayName: account.displayName ?? account.email,
            photoUrl: account.photoUrl,
            authHeaders: headers,
          );
          await _saveSession(_currentUser!);
          return _currentUser;
        }
      }
    } catch (e) {
      debugPrint("Silent Sign-In Error: $e");
    }
    return null;
  }

  /// Sign in with Google and persist session permanently
  Future<UserAuthInfo?> signIn() async {
    if (isDesktopPlatform) {
      // Desktop OAuth Browser Loopback Flow
      try {
        final desktopResult = await DesktopGoogleAuthService.authenticate();
        if (desktopResult == null) return null;

        _currentUser = UserAuthInfo(
          email: desktopResult.email,
          displayName: desktopResult.displayName,
          photoUrl: desktopResult.photoUrl,
          refreshToken: desktopResult.refreshToken,
          authHeaders: desktopResult.authHeaders,
        );
        await _saveSession(_currentUser!);
        return _currentUser;
      } catch (e) {
        throw Exception('Desktop Google Sign-In Error: $e');
      }
    } else {
      // Mobile / Web Native Google Sign-In Flow
      try {
        final account = await _googleSignIn.signIn();
        if (account == null) return null;

        final headers = await account.authHeaders;
        _currentUser = UserAuthInfo(
          email: account.email,
          displayName: account.displayName ?? account.email,
          photoUrl: account.photoUrl,
          authHeaders: headers,
        );
        await _saveSession(_currentUser!);
        return _currentUser;
      } on PlatformException catch (e) {
        if (e.code == '10' || e.message?.contains('DEVELOPER_ERROR') == true) {
          throw Exception(
            'Google OAuth Setup Error (Code 10): Ensure SHA-1 fingerprint and Package Name are added under OAuth Client IDs in Google Cloud Console.',
          );
        } else if (e.code == '12500' || e.code == 'sign_in_failed') {
          throw Exception(
            'Sign-In Failed (Code 12500): Check Google Cloud Console OAuth Consent Screen status and test users list.',
          );
        } else if (e.code == 'sign_in_canceled') {
          return null;
        }
        throw Exception('Google Sign-In Error [${e.code}]: ${e.message}');
      } catch (e) {
        throw Exception('Unexpected Authentication Error: $e');
      }
    }
  }

  /// Sign out current Google user and clear saved session
  Future<void> signOut() async {
    if (!isDesktopPlatform) {
      await _googleSignIn.signOut();
    }
    await _clearSession();
    _currentUser = null;
  }

  /// Fetch email messages with filtering (shows supplier/invoice emails only by default)
  Future<List<EmailItem>> fetchRecentEmails({
    int maxResults = 50,
    String? query = defaultSupplierFilterQuery,
  }) async {
    if (_currentUser == null) {
      // Try restoring from persistent session
      final restored = await signInSilently();
      if (restored == null) {
        throw Exception('User is not signed in.');
      }
    }

    try {
      final client = GoogleAuthClient(_currentUser!.authHeaders);
      final gmailApi = gmail.GmailApi(client);

      try {
        final listResponse = await gmailApi.users.messages.list(
          'me',
          maxResults: maxResults,
          q: query,
        );

        final messages = listResponse.messages ?? [];
        List<EmailItem> emailList = [];
        int chunkSize = 10;

        for (int i = 0; i < messages.length; i += chunkSize) {
          final chunk = messages.sublist(
            i,
            i + chunkSize > messages.length ? messages.length : i + chunkSize,
          );

          final chunkResults = await Future.wait(
            chunk.map((msg) async {
              if (msg.id == null) return null;
              try {
                final fullMessage = await gmailApi.users.messages.get(
                  'me',
                  msg.id!,
                  format: 'metadata',
                  metadataHeaders: ['Subject', 'From', 'Date'],
                );

                final headers = fullMessage.payload?.headers ?? [];
                String subject = _getHeader(headers, 'Subject') ?? '(No Subject)';
                String from = _getHeader(headers, 'From') ?? 'Unknown Sender';
                String date = _getHeader(headers, 'Date') ?? '';

                final lowerFrom = from.toLowerCase();
                if (lowerFrom.contains('accounts@firefox.com') ||
                    lowerFrom.contains('no-reply@accounts.google.com')) {
                  return null;
                }

                return EmailItem(
                  id: msg.id!,
                  threadId: fullMessage.threadId ?? '',
                  snippet: fullMessage.snippet ?? '',
                  subject: subject,
                  from: from,
                  date: date,
                );
              } catch (_) {
                return null;
              }
            }),
          );

          for (var item in chunkResults) {
            if (item != null) emailList.add(item);
          }
        }

        return emailList;
      } finally {
        client.close();
      }
    } on SocketException catch (_) {
      throw Exception(
        'No Internet Connection: Unable to connect to Google servers. Please check your connection and try again.',
      );
    } on gmail.DetailedApiRequestError catch (e) {
      if (e.status == 401) {
        if (_currentUser?.refreshToken != null && _currentUser!.refreshToken!.isNotEmpty) {
          final newToken = await DesktopGoogleAuthService.refreshAccessToken(_currentUser!.refreshToken!);
          if (newToken != null && newToken.isNotEmpty) {
            _currentUser!.authHeaders = {'Authorization': 'Bearer $newToken'};
            await _saveSession(_currentUser!);
            return fetchRecentEmails(maxResults: maxResults, query: query);
          }
        }
        // Token expired and refresh token unavailable/revoked - clear session
        await _clearSession();
        _currentUser = null;
        throw Exception('Session expired. Please sign in again.');
      } else if (e.status == 403) {
        throw Exception(
          'Gmail API Access Forbidden (403): Ensure the Gmail API is enabled in Google Cloud Console and the gmail.readonly scope is granted.',
        );
      }
      throw Exception('Gmail API Error (${e.status}): ${e.message}');
    } catch (e) {
      if (e.toString().contains('Failed host lookup') ||
          e.toString().contains('SocketException')) {
        throw Exception(
          'No Internet Connection: Unable to connect to Google servers. Please check your connection and try again.',
        );
      }
      throw Exception('Failed to fetch emails: $e');
    }
  }

  static String? _getHeader(List<gmail.MessagePartHeader> headers, String name) {
    try {
      return headers
          .firstWhere((h) => h.name?.toLowerCase() == name.toLowerCase())
          .value;
    } catch (_) {
      return null;
    }
  }
}
