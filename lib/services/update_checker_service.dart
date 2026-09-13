import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class UpdateCheckerService {
  static const String _repoOwner = 'jiyadpn0';
  static const String _repoName = 'pharmacy_app';
  static const String currentVersion = '1.0.0';

  /// Checks GitHub Releases for a newer version tag.
  static Future<void> checkForUpdates(BuildContext context, {bool silent = false}) async {
    try {
      final Uri url = Uri.parse('https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest');
      final response = await http.get(url, headers: {'Accept': 'application/vnd.github+json'});

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final String latestTag = (data['tag_name'] ?? '').toString().replaceAll('v', '').trim();
        final String htmlUrl = (data['html_url'] ?? '').toString();
        final String releaseNotes = (data['body'] ?? '').toString();

        if (latestTag.isNotEmpty && _isVersionNewer(currentVersion, latestTag)) {
          if (context.mounted) {
            _showUpdateDialog(context, latestTag, releaseNotes, htmlUrl);
          }
        } else if (!silent && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('You are on the latest version (v$currentVersion).'),
              backgroundColor: Colors.green.shade800,
            ),
          );
        }
      }
    } catch (_) {
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to check for updates.')),
        );
      }
    }
  }

  static bool _isVersionNewer(String current, String latest) {
    try {
      List<int> currParts = current.split('+').first.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      List<int> lateParts = latest.split('+').first.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (int i = 0; i < 3; i++) {
        int c = i < currParts.length ? currParts[i] : 0;
        int l = i < lateParts.length ? lateParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
    } catch (_) {}
    return false;
  }

  static void _showUpdateDialog(BuildContext context, String latestTag, String releaseNotes, String downloadUrl) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.system_update_rounded, color: Colors.blueAccent, size: 28),
            const SizedBox(width: 12),
            const Text(
              'Software Update Available!',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A new version (v$latestTag) of PharmaPro ERP is ready for download.',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            if (releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('What\'s New:', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Text(
                  releaseNotes,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final Uri uri = Uri.parse(downloadUrl.isNotEmpty ? downloadUrl : 'https://github.com/jiyadpn0/pharmacy_app/releases');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Download Update'),
          ),
        ],
      ),
    );
  }
}
