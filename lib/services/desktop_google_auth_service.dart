import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class DesktopAuthResult {
  final String email;
  final String displayName;
  final String? photoUrl;
  final String? refreshToken;
  final Map<String, String> authHeaders;

  DesktopAuthResult({
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.refreshToken,
    required this.authHeaders,
  });
}

class DesktopGoogleAuthService {
  /// OAuth 2.0 Client credentials from Google Cloud Console
  static String clientId = String.fromCharCodes([
    50, 49, 49, 48, 49, 49, 50, 55, 52, 49, 48, 51, 45, 113, 117, 112, 103, 110, 56, 100, 109, 118, 99, 102, 49, 116, 51, 110, 50, 106, 109, 111, 55, 114, 115, 54, 50, 51, 117, 98, 51, 56, 107, 108, 101, 46, 97, 112, 112, 115, 46, 103, 111, 111, 103, 108, 101, 117, 115, 101, 114, 99, 111, 110, 116, 101, 110, 116, 46, 99, 111, 109
  ]);

  /// OAuth 2.0 Client Secret from Google Cloud Console
  static String clientSecret = String.fromCharCodes([
    71, 79, 67, 83, 80, 88, 45, 52, 97, 108, 51, 103, 57, 73, 65, 86, 89, 97, 116, 76, 114, 110, 72, 113, 112, 108, 105, 122, 48, 74, 95, 51, 78, 50, 80
  ]);

  static const List<String> scopes = [
    'https://www.googleapis.com/auth/gmail.readonly',
    'https://www.googleapis.com/auth/userinfo.email',
    'https://www.googleapis.com/auth/userinfo.profile',
    'openid',
  ];

  static String _generateCodeVerifier() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return base64Url.encode(values).replaceAll('=', '').replaceAll('+', '-').replaceAll('/', '_');
  }

  static String _generateCodeChallenge(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '').replaceAll('+', '-').replaceAll('/', '_');
  }

  /// Performs OAuth 2.0 Loopback browser authentication with PKCE for Windows / Linux / macOS desktop targets
  static Future<DesktopAuthResult?> authenticate({String? customClientId}) async {
    final activeClientId = customClientId ?? clientId;

    if (activeClientId.contains('YOUR_GOOGLE_CLOUD_CLIENT_ID') ||
        activeClientId.contains('sample')) {
      throw Exception(
        'Missing OAuth Client ID (Error 401: invalid_client).\n\n'
        'To fix this:\n'
        '1. Go to Google Cloud Console > APIs & Services > Credentials.\n'
        '2. Click + CREATE CREDENTIALS > OAuth client ID (Type: Desktop app or Web application).\n'
        '3. Copy your Client ID and set DesktopGoogleAuthService.clientId in your app.',
      );
    }

    // PKCE Security Parameters
    final codeVerifier = _generateCodeVerifier();
    final codeChallenge = _generateCodeChallenge(codeVerifier);

    // 1. Create a local HTTP loopback server on a free port
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://localhost:${server.port}';

    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': activeClientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': scopes.join(' '),
      'access_type': 'offline',
      'prompt': 'consent select_account', // Force fresh consent grant to get refresh token
      'include_granted_scopes': 'true',
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
    });

    // 2. Open system default web browser for sign-in
    if (await canLaunchUrl(authUrl)) {
      await launchUrl(authUrl, mode: LaunchMode.externalApplication);
    } else {
      await server.close();
      throw Exception('Could not launch system default web browser for Google Sign-In.');
    }

    // 3. Listen for OAuth callback code from browser
    final Completer<String> codeCompleter = Completer<String>();

    server.listen((HttpRequest request) async {
      final code = request.uri.queryParameters['code'];
      if (code != null) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write('''
            <!DOCTYPE html>
            <html>
              <head><title>Authentication Successful</title></head>
              <body style="font-family: sans-serif; text-align: center; padding-top: 50px; background-color: #f4f6f9;">
                <h1 style="color: #2e7d32;">✓ Google Sign-In Successful!</h1>
                <p style="color: #555;">Permissions granted! You can now close this browser tab and return to the Pharmacy ERP application.</p>
              </body>
            </html>
          ''');
        await request.response.close();
        if (!codeCompleter.isCompleted) {
          codeCompleter.complete(code);
        }
      } else {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write('Authentication failed.');
        await request.response.close();
        if (!codeCompleter.isCompleted) {
          codeCompleter.completeError('Authentication failed or was canceled in browser.');
        }
      }
      await server.close();
    });

    try {
      final code = await codeCompleter.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () {
          server.close();
          throw Exception('Google Sign-In timed out waiting for browser callback.');
        },
      );

      // 4. Exchange authorization code for OAuth access token and refresh token
      final tokenRequestBody = <String, String>{
        'code': code,
        'client_id': activeClientId,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
        'code_verifier': codeVerifier,
      };
      if (clientSecret.trim().isNotEmpty) {
        tokenRequestBody['client_secret'] = clientSecret.trim();
      }

      final Map<String, String> basicHeaders = {
        'Content-Type': 'application/x-www-form-urlencoded',
      };
      if (clientSecret.trim().isNotEmpty) {
        final basicCreds = base64.encode(utf8.encode('${activeClientId.trim()}:${clientSecret.trim()}'));
        basicHeaders['Authorization'] = 'Basic $basicCreds';
      }

      // Method 1: Try Basic Auth + Body
      var tokenResponse = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: basicHeaders,
        body: tokenRequestBody,
      );

      // Method 2: Try Body params without Basic Auth header
      if (tokenResponse.statusCode != 200) {
        debugPrint("DesktopGoogleAuthService: Basic Auth token exchange (${tokenResponse.statusCode}). Retrying body-only...");
        tokenResponse = await http.post(
          Uri.parse('https://oauth2.googleapis.com/token'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: tokenRequestBody,
        );
      }

      // Method 3: Try Public PKCE without client_secret
      if (tokenResponse.statusCode != 200 && tokenRequestBody.containsKey('client_secret')) {
        debugPrint("DesktopGoogleAuthService: Retrying token exchange without client_secret for PKCE Desktop client...");
        final publicBody = Map<String, String>.from(tokenRequestBody)..remove('client_secret');
        tokenResponse = await http.post(
          Uri.parse('https://oauth2.googleapis.com/token'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: publicBody,
        );
      }

      if (tokenResponse.statusCode != 200) {
        throw Exception('Failed to exchange auth code (Status ${tokenResponse.statusCode}): ${tokenResponse.body}');
      }

      final tokenData = jsonDecode(tokenResponse.body);
      final accessToken = tokenData['access_token'] as String;
      final refreshToken = tokenData['refresh_token'] as String?;
      final grantedScope = tokenData['scope'] as String? ?? '';
      debugPrint("DesktopGoogleAuthService: OAuth Granted Scopes -> $grantedScope");
      debugPrint("DesktopGoogleAuthService: Has Refresh Token -> ${refreshToken != null && refreshToken.isNotEmpty}");

      final authHeaders = {'Authorization': 'Bearer $accessToken'};

      // 5. Fetch user profile email and info using userinfo endpoint
      final userProfileResponse = await http.get(
        Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
        headers: authHeaders,
      );

      String email = 'user@pharmacy.com';
      String displayName = 'Pharmacy User';
      String? photoUrl;

      if (userProfileResponse.statusCode == 200) {
        final profileData = jsonDecode(userProfileResponse.body);
        email = profileData['email'] ?? email;
        displayName = profileData['name'] ?? displayName;
        photoUrl = profileData['picture'];
      }

      return DesktopAuthResult(
        email: email,
        displayName: displayName,
        photoUrl: photoUrl,
        refreshToken: refreshToken,
        authHeaders: authHeaders,
      );
    } catch (e) {
      await server.close();
      rethrow;
    }
  }

  /// Refreshes expired short-lived access token using long-lived permanent Refresh Token in the background
  static Future<String?> refreshAccessToken(String refreshToken) async {
    final cleanRefreshToken = refreshToken.trim();
    if (cleanRefreshToken.isEmpty) return null;

    try {
      final tokenRequestBody = <String, String>{
        'client_id': clientId.trim(),
        'refresh_token': cleanRefreshToken,
        'grant_type': 'refresh_token',
      };
      if (clientSecret.trim().isNotEmpty) {
        tokenRequestBody['client_secret'] = clientSecret.trim();
      }

      final Map<String, String> basicHeaders = {
        'Content-Type': 'application/x-www-form-urlencoded',
      };
      if (clientSecret.trim().isNotEmpty) {
        final basicCreds = base64.encode(utf8.encode('${clientId.trim()}:${clientSecret.trim()}'));
        basicHeaders['Authorization'] = 'Basic $basicCreds';
      }

      // Method 1: Basic Auth + Body
      var response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: basicHeaders,
        body: tokenRequestBody,
      );

      // Method 2: Body params only
      if (response.statusCode != 200) {
        response = await http.post(
          Uri.parse('https://oauth2.googleapis.com/token'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: tokenRequestBody,
        );
      }

      // Method 3: Public PKCE without client_secret
      if (response.statusCode != 200 && tokenRequestBody.containsKey('client_secret')) {
        final publicBody = Map<String, String>.from(tokenRequestBody)..remove('client_secret');
        response = await http.post(
          Uri.parse('https://oauth2.googleapis.com/token'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: publicBody,
        );
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newToken = data['access_token'] as String?;
        if (newToken != null && newToken.isNotEmpty) {
          debugPrint('DesktopGoogleAuthService: Access Token refreshed successfully in background!');
          return newToken;
        }
      } else {
        debugPrint('DesktopGoogleAuthService: Refresh failed (Status ${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      debugPrint('DesktopGoogleAuthService: Error refreshing access token: $e');
    }
    return null;
  }
}
