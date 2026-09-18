import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/theme_constants.dart';

class UpdateCheckerService {
  static const String _defaultRepoOwner = 'jiyadpn0';
  static const String _defaultRepoName = 'pharmacy_app';
  static const String defaultCodeVersion = '2.4.7';

  static String _activeVersion = defaultCodeVersion;

  /// Returns the currently active version of the application.
  static String get currentVersion => _activeVersion;

  /// Initializes the version service by reading persisted version overrides.
  static Future<void> init() async {
    try {
      String foundVersion = defaultCodeVersion;

      // 1. Try reading version.json in app directory
      try {
        final appExePath = Platform.resolvedExecutable;
        final appDir = File(appExePath).parent.path;
        final versionFile = File('$appDir${Platform.pathSeparator}version.json');
        if (await versionFile.exists()) {
          final content = await versionFile.readAsString();
          final Map<String, dynamic> data = jsonDecode(content);
          final String fileVer = (data['version'] ?? '').toString().trim();
          if (fileVer.isNotEmpty && compareSemver(fileVer, foundVersion) > 0) {
            foundVersion = fileVer;
          }
        }
      } catch (_) {}

      // 2. Try reading from SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        final prefVer = prefs.getString('installed_app_version')?.trim() ?? '';
        if (prefVer.isNotEmpty && compareSemver(prefVer, foundVersion) > 0) {
          foundVersion = prefVer;
        }
      } catch (_) {}

      _activeVersion = foundVersion;
    } catch (_) {}
  }

  /// Persists an installed version tag locally.
  static Future<void> saveInstalledVersion(String version) async {
    final cleanVer = version.replaceAll(RegExp(r'^[vV]'), '').trim();
    if (cleanVer.isEmpty) return;

    _activeVersion = cleanVer;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('installed_app_version', cleanVer);
    } catch (_) {}

    try {
      final appExePath = Platform.resolvedExecutable;
      final appDir = File(appExePath).parent.path;
      final versionFile = File('$appDir${Platform.pathSeparator}version.json');
      await versionFile.writeAsString(jsonEncode({'version': cleanVer}));
    } catch (_) {}
  }

  /// Compares two semver strings (returns > 0 if v1 > v2, < 0 if v1 < v2, 0 if equal).
  static int compareSemver(String v1, String v2) {
    String clean(String v) => v.replaceAll(RegExp(r'^[vV]'), '').split('+').first.split('-').first.trim();
    List<int> parts1 = clean(v1).split('.').map((e) => int.tryParse(e) ?? 0).toList();
    List<int> parts2 = clean(v2).split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      int p1 = i < parts1.length ? parts1[i] : 0;
      int p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 > p2) return 1;
      if (p1 < p2) return -1;
    }
    return 0;
  }

  static bool isVersionNewer(String latestTag, String currentVersion) {
    return compareSemver(latestTag, currentVersion) > 0;
  }

  /// Checks GitHub Releases for updates.
  static Future<void> checkForUpdates(BuildContext context, {bool silent = false, String? repoPath}) async {
    if (kDebugMode && silent) return;

    final prefs = await SharedPreferences.getInstance();
    String targetRepo = repoPath?.trim() ?? '';
    if (targetRepo.isEmpty || !targetRepo.contains('/')) {
      targetRepo = prefs.getString('github_repo_path') ?? '$_defaultRepoOwner/$_defaultRepoName';
    }

    if (!silent && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Center(
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text("Checking GitHub Releases ($targetRepo)...", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
              ],
            ),
          ),
        ),
      );
    }

    try {
      final client = HttpClient();
      final url = Uri.parse('https://api.github.com/repos/$targetRepo/releases/latest');
      final request = await client.getUrl(url);
      request.headers.set('User-Agent', 'PharmacyERP-Updater');
      request.headers.set('Accept', 'application/vnd.github.v3+json');

      final response = await request.close().timeout(const Duration(seconds: 10));

      if (!silent && context.mounted) {
        Navigator.pop(context); // Close checking loading dialog
      }

      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final Map<String, dynamic> releaseData = jsonDecode(responseBody);

        final String tagName = (releaseData['tag_name'] ?? '').toString();
        final String releaseName = releaseData['name'] ?? tagName;
        final String htmlUrl = releaseData['html_url'] ?? '';
        final String body = releaseData['body'] ?? 'No release notes provided.';
        final String publishedAt = releaseData['published_at'] ?? '';

        String directZipUrl = '';
        if (releaseData['assets'] is List && (releaseData['assets'] as List).isNotEmpty) {
          for (var asset in (releaseData['assets'] as List)) {
            final String downloadUrl = (asset['browser_download_url'] ?? '').toString();
            if (downloadUrl.toLowerCase().endsWith('.zip')) {
              directZipUrl = downloadUrl;
              break;
            }
          }
        }
        if (directZipUrl.isEmpty && releaseData['zipball_url'] != null) {
          directZipUrl = releaseData['zipball_url'].toString();
        }
        if (directZipUrl.isEmpty) {
          directZipUrl = 'https://github.com/$targetRepo/archive/refs/tags/$tagName.zip';
        }

        final cleanLatest = tagName.replaceAll(RegExp(r'^[vV]'), '').trim();

        if (cleanLatest.isNotEmpty && isVersionNewer(cleanLatest, currentVersion)) {
          if (context.mounted) {
            _showUpdateAvailableDialog(
              context: context,
              latestVersion: cleanLatest.startsWith('v') ? cleanLatest : 'v$cleanLatest',
              releaseName: releaseName,
              htmlUrl: htmlUrl,
              directZipUrl: directZipUrl,
              body: body,
              publishedAt: publishedAt,
            );
          }
        } else if (!silent && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Software is fully up to date! (v$currentVersion)'),
              backgroundColor: Colors.green.shade800,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else if (!silent && context.mounted) {
        _showErrorDialog(
          context,
          "GitHub API Error",
          "Returned status code ${response.statusCode} for repository '$targetRepo'.",
        );
      }
      client.close();
    } catch (e) {
      if (!silent && context.mounted) {
        _showErrorDialog(
          context,
          "Connection Error",
          "Unable to check for updates: ${e.toString().replaceAll('Exception: ', '')}",
        );
      }
    }
  }

  static void _showUpdateAvailableDialog({
    required BuildContext context,
    required String latestVersion,
    required String releaseName,
    required String htmlUrl,
    required String directZipUrl,
    required String body,
    required String publishedAt,
  }) {
    String formattedDate = publishedAt;
    try {
      if (publishedAt.isNotEmpty) {
        final dt = DateTime.parse(publishedAt);
        formattedDate = DateFormat('MMM dd, yyyy').format(dt);
      }
    } catch (_) {}

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.system_update_rounded, color: Colors.blue),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text("New Update Available!", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Current: v$currentVersion", style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.blueGrey)),
                        const SizedBox(height: 4),
                        Text("Latest: $latestVersion", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue.shade900)),
                      ],
                    ),
                    const Spacer(),
                    if (formattedDate.isNotEmpty)
                      Chip(
                        avatar: const Icon(Icons.calendar_today_rounded, size: 14),
                        label: Text(formattedDate, style: const TextStyle(fontSize: 11)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(releaseName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              const Text("RELEASE NOTES:", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    body.isEmpty ? "No release details provided." : body,
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("LATER", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          if (htmlUrl.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                final Uri uri = Uri.parse(htmlUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 14),
              label: const Text("Open in Browser", style: TextStyle(fontSize: 12)),
            ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              performDirectInAppUpdate(context, directZipUrl, latestVersion);
            },
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text("UPDATE DIRECTLY IN APP", style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  /// Performs a direct in-app update by downloading the update package,
  /// updating local version info, and spawning a detached updater batch process.
  static Future<void> performDirectInAppUpdate(
    BuildContext context,
    String zipUrl,
    String targetVersion,
  ) async {
    final progressNotifier = ValueNotifier<double>(0.0);
    final statusNotifier = ValueNotifier<String>("Connecting to update server...");

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.system_update_rounded, color: Colors.blue, size: 28),
            SizedBox(width: 12),
            Text("Updating PharmaPro ERP", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ValueListenableBuilder<String>(
                valueListenable: statusNotifier,
                builder: (context, statusText, _) => Text(statusText, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<double>(
                valueListenable: progressNotifier,
                builder: (context, progress, _) => Column(
                  children: [
                    LinearProgressIndicator(value: progress > 0 ? progress : null, minHeight: 8, borderRadius: BorderRadius.circular(4)),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text("${(progress * 100).toStringAsFixed(0)}%", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final client = http.Client();
      Uri targetUri = Uri.parse(zipUrl);
      http.StreamedResponse? response;

      int redirectCount = 0;
      while (redirectCount < 5) {
        final request = http.Request('GET', targetUri);
        request.headers['User-Agent'] = 'PharmacyERP-Updater';
        request.headers['Accept'] = 'application/octet-stream, application/zip, */*';

        response = await client.send(request);

        if (response.statusCode >= 300 && response.statusCode < 400 && response.headers.containsKey('location')) {
          targetUri = Uri.parse(response.headers['location']!);
          redirectCount++;
        } else {
          break;
        }
      }

      if (response == null || response.statusCode != 200) {
        throw Exception("Download failed with HTTP status code ${response?.statusCode ?? 404}");
      }

      final contentLength = response.contentLength ?? 0;
      final tempDir = Directory.systemTemp;
      final zipFile = File('${tempDir.path}${Platform.pathSeparator}PharmaPro_Update.zip');
      final extractDir = Directory('${tempDir.path}${Platform.pathSeparator}PharmaPro_Extracted');

      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
      await extractDir.create(recursive: true);

      final sink = zipFile.openWrite();
      int downloaded = 0;

      await response.stream.forEach((chunk) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (contentLength > 0) {
          progressNotifier.value = (downloaded / contentLength).toDouble();
          statusNotifier.value = "Downloading update (${(downloaded / (1024 * 1024)).toStringAsFixed(1)} MB / ${(contentLength / (1024 * 1024)).toStringAsFixed(1)} MB)...";
        } else {
          statusNotifier.value = "Downloading update (${(downloaded / (1024 * 1024)).toStringAsFixed(1)} MB)...";
        }
      });

      await sink.flush();
      await sink.close();
      client.close();

      statusNotifier.value = "Unpacking update files...";
      progressNotifier.value = 0.95;

      final extractResult = await Process.run('powershell', [
        '-Command',
        'Expand-Archive -Path "${zipFile.path}" -DestinationPath "${extractDir.path}" -Force'
      ]);

      if (extractResult.exitCode != 0) {
        throw Exception("Failed to extract update package: ${extractResult.stderr}");
      }

      String sourceFolderPath = extractDir.path;
      final extractedItems = extractDir.listSync();
      if (extractedItems.length == 1 && extractedItems.first is Directory) {
        sourceFolderPath = extractedItems.first.path;
      }

      final cleanVer = targetVersion.replaceAll(RegExp(r'^[vV]'), '').trim();
      statusNotifier.value = "Applying update (v$cleanVer) and restarting application...";
      progressNotifier.value = 1.0;

      // Persist the updated version prior to restart
      await saveInstalledVersion(cleanVer);

      final appExePath = Platform.resolvedExecutable;
      final appExeFile = File(appExePath);
      final appDir = appExeFile.parent.path;
      final exeName = appExeFile.uri.pathSegments.last;

      if (Platform.isWindows) {
        final scriptFile = File('${tempDir.path}${Platform.pathSeparator}apply_pharmacy_update.bat');
        final scriptContent = '''
@echo off
set "EXE_NAME=$exeName"

timeout /t 1 /nobreak > nul
taskkill /F /IM %EXE_NAME% > nul 2>&1

:wait_loop
timeout /t 1 /nobreak > nul
tasklist /FI "IMAGENAME eq %EXE_NAME%" 2>NUL | find /I /N "%EXE_NAME%" >NUL
if "%ERRORLEVEL%"=="0" goto wait_loop

timeout /t 1 /nobreak > nul
xcopy /E /Y /I /Q "$sourceFolderPath\\*" "$appDir\\"

start "" "$appExePath"
del "%~f0"
''';
        await scriptFile.writeAsString(scriptContent);
        await Process.start('cmd.exe', ['/c', scriptFile.path], mode: ProcessStartMode.detached);
        exit(0);
      } else {
        if (context.mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update downloaded to ${zipFile.path}. Please replace application files manually.')),
        );
      }
    } catch (e) {
      if (context.mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      _showErrorDialog(context, "Direct Update Failed", "Unable to download or apply update directly.\n\nError: $e");
    }
  }

  static void _showErrorDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
