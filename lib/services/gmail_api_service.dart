import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:path_provider/path_provider.dart';
import 'google_auth_client.dart';
import 'desktop_google_auth_service.dart';

class EmailAttachmentInfo {
  final String attachmentId;
  final String filename;
  final String mimeType;
  final int size;

  EmailAttachmentInfo({
    required this.attachmentId,
    required this.filename,
    required this.mimeType,
    required this.size,
  });
}

class EmailHeaderInfo {
  final String id;
  final String threadId;
  final String snippet;
  final String subject;
  final String from;
  final String date;
  final List<EmailAttachmentInfo> attachments;

  EmailHeaderInfo({
    required this.id,
    required this.threadId,
    required this.snippet,
    required this.subject,
    required this.from,
    required this.date,
    required this.attachments,
  });
}

class EmailDetailInfo extends EmailHeaderInfo {
  final String body;

  EmailDetailInfo({
    required super.id,
    required super.threadId,
    required super.snippet,
    required super.subject,
    required super.from,
    required super.date,
    required super.attachments,
    required this.body,
  });
}

class GmailApiService {
  /// Download an email attachment file with silent auto-token-refresh
  static Future<File?> downloadEmailAttachment({
    required Map<String, String> authHeaders,
    String? refreshToken,
    void Function(Map<String, String>)? onTokenRefreshed,
    required String messageId,
    required EmailAttachmentInfo attachment,
  }) async {
    Map<String, String> currentHeaders = Map.from(authHeaders);

    Future<File?> runDownload(Map<String, String> headers) async {
      final client = GoogleAuthClient(headers);
      final gmailApi = gmail.GmailApi(client);

      try {
        List<int>? bytes;

        if (attachment.attachmentId.trim().isNotEmpty) {
          try {
            final response = await gmailApi.users.messages.attachments.get(
              'me',
              messageId,
              attachment.attachmentId,
            );

            if (response.data != null && response.data!.isNotEmpty) {
              bytes = _decodeBase64ToBytes(response.data!);
            }
          } catch (e) {
            debugPrint("Direct attachment download error: $e");
          }
        }

        // Fallback: If direct attachment fetch failed or attachmentId was empty, fetch full message payload
        if (bytes == null || bytes.isEmpty) {
          try {
            final fullMsg = await gmailApi.users.messages.get('me', messageId, format: 'full');
            bytes = _extractAttachmentBytesFromMessagePart(fullMsg.payload, attachment.filename);
          } catch (e) {
            debugPrint("Full message payload attachment fetch error: $e");
          }
        }

        if (bytes == null || bytes.isEmpty) return null;

        final safeFilename = attachment.filename.replaceAll(RegExp(r'[^\w\.-]'), '_');
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/$safeFilename';

        final file = File(filePath);
        await file.writeAsBytes(bytes);
        return file;
      } finally {
        client.close();
      }
    }

    try {
      return await runDownload(currentHeaders);
    } catch (e) {
      if ((e.toString().contains('401') || e.toString().contains('invalid authentication credentials')) &&
          refreshToken != null &&
          refreshToken.isNotEmpty) {
        final newAccessToken = await DesktopGoogleAuthService.refreshAccessToken(refreshToken);
        if (newAccessToken != null && newAccessToken.isNotEmpty) {
          final newHeaders = {'Authorization': 'Bearer $newAccessToken'};
          if (onTokenRefreshed != null) {
            onTokenRefreshed(newHeaders);
          }
          return await runDownload(newHeaders);
        }
      }
      rethrow;
    }
  }

  /// Stream email chunks (e.g. 10 at a time) progressively in parallel
  static Stream<List<EmailHeaderInfo>> fetchRecentEmailsStream({
    required Map<String, String> authHeaders,
    String? refreshToken,
    Function(Map<String, String>)? onTokenRefreshed,
    int maxResults = 50,
    int chunkSize = 10,
    String query = 'has:attachment (invoice OR purchase OR bill OR supplier)',
  }) async* {
    Map<String, String> currentHeaders = Map.from(authHeaders);

    Stream<List<EmailHeaderInfo>> runStream(Map<String, String> headers) async* {
      final client = GoogleAuthClient(headers);
      final gmailApi = gmail.GmailApi(client);

      try {
        final listResponse = await gmailApi.users.messages.list(
          'me',
          maxResults: maxResults,
          q: query,
        );

        final messages = listResponse.messages ?? [];
        if (messages.isEmpty) return;

        for (int i = 0; i < messages.length; i += chunkSize) {
          final chunk = messages.sublist(
            i,
            i + chunkSize > messages.length ? messages.length : i + chunkSize,
          );

          final chunkResults = await Future.wait(
            chunk.map((msg) async {
              if (msg.id == null) return null;
              try {
                final fullMsg = await gmailApi.users.messages.get(
                  'me',
                  msg.id!,
                  format: 'full',
                );

                final msgHeaders = fullMsg.payload?.headers ?? [];
                String subject = _getHeader(msgHeaders, 'Subject') ?? '(No Subject)';
                String from = _getHeader(msgHeaders, 'From') ?? 'Unknown';
                String date = _getHeader(msgHeaders, 'Date') ?? '';

                List<EmailAttachmentInfo> attachments = _extractAttachments(fullMsg.payload);

                return EmailHeaderInfo(
                  id: msg.id!,
                  threadId: fullMsg.threadId ?? '',
                  snippet: fullMsg.snippet ?? '',
                  subject: subject,
                  from: from,
                  date: date,
                  attachments: attachments,
                );
              } catch (_) {
                return null;
              }
            }),
          );

          final batch = chunkResults.whereType<EmailHeaderInfo>().toList();
          if (batch.isNotEmpty) {
            yield batch;
          }
        }
      } finally {
        client.close();
      }
    }

    try {
      yield* runStream(currentHeaders);
    } catch (e) {
      if ((e.toString().contains('401') || e.toString().contains('invalid authentication credentials')) &&
          refreshToken != null &&
          refreshToken.isNotEmpty) {
        final newAccessToken = await DesktopGoogleAuthService.refreshAccessToken(refreshToken);
        if (newAccessToken != null && newAccessToken.isNotEmpty) {
          final newHeaders = {'Authorization': 'Bearer $newAccessToken'};
          if (onTokenRefreshed != null) {
            onTokenRefreshed(newHeaders);
          }
          yield* runStream(newHeaders);
          return;
        }
      }

      if (e is SocketException ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('11001')) {
        throw Exception(
          'No Internet Connection: Unable to connect to Google servers. Please check your connection and try again.',
        );
      }
      rethrow;
    }
  }

  /// Fetch list of recent supplier/invoice emails with attachments (with silent auto-token-refresh)
  static Future<List<EmailHeaderInfo>> fetchRecentEmails({
    required Map<String, String> authHeaders,
    String? refreshToken,
    Function(Map<String, String>)? onTokenRefreshed,
    int maxResults = 50,
    String query = 'has:attachment (invoice OR purchase OR bill OR supplier)',
  }) async {
    List<EmailHeaderInfo> emailList = [];
    await for (final batch in fetchRecentEmailsStream(
      authHeaders: authHeaders,
      refreshToken: refreshToken,
      onTokenRefreshed: onTokenRefreshed,
      maxResults: maxResults,
      query: query,
    )) {
      emailList.addAll(batch);
    }
    return emailList;
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

  static List<EmailAttachmentInfo> _extractAttachments(gmail.MessagePart? payload) {
    List<EmailAttachmentInfo> list = [];
    if (payload == null) return list;

    void processPart(gmail.MessagePart part) {
      String? filename = part.filename;
      String? attachmentId = part.body?.attachmentId;

      if (filename != null && filename.trim().isNotEmpty) {
        String cleanFilename = filename.trim();
        String attId = (attachmentId != null && attachmentId.isNotEmpty)
            ? attachmentId
            : (part.partId ?? '');

        list.add(EmailAttachmentInfo(
          attachmentId: attId,
          filename: cleanFilename,
          mimeType: part.mimeType ?? 'application/octet-stream',
          size: part.body?.size ?? 0,
        ));
      }

      if (part.parts != null) {
        for (var sub in part.parts!) {
          processPart(sub);
        }
      }
    }

    processPart(payload);
    return list;
  }

  static List<int>? _extractAttachmentBytesFromMessagePart(gmail.MessagePart? part, String targetFilename) {
    if (part == null) return null;

    final cleanTarget = targetFilename.toLowerCase().trim();
    final cleanFn = (part.filename ?? '').toLowerCase().trim();

    if (cleanFn.isNotEmpty && (cleanFn == cleanTarget || cleanFn.contains(cleanTarget) || cleanTarget.contains(cleanFn))) {
      if (part.body?.data != null && part.body!.data!.isNotEmpty) {
        return _decodeBase64ToBytes(part.body!.data!);
      }
    }

    if (part.parts != null) {
      for (var sub in part.parts!) {
        final res = _extractAttachmentBytesFromMessagePart(sub, targetFilename);
        if (res != null && res.isNotEmpty) return res;
      }
    }
    return null;
  }

  static List<int> _decodeBase64ToBytes(String data) {
    String normalized = data.replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    return base64.decode(normalized);
  }
}
