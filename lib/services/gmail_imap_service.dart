import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'gmail_api_service.dart';

class GmailImapService {
  GmailImapService._internal();
  static final GmailImapService instance = GmailImapService._internal();

  /// Clean App Password by stripping spaces
  static String cleanAppPassword(String rawPassword) {
    return rawPassword.replaceAll(' ', '').trim();
  }

  /// Test IMAP SSL authentication for a given Gmail address and 16-char App Password
  Future<bool> testConnection(String email, String appPassword) async {
    final cleanEmail = email.trim();
    final cleanPassword = cleanAppPassword(appPassword);

    if (cleanEmail.isEmpty || cleanPassword.isEmpty) {
      throw Exception('Email address and 16-character App Password are required.');
    }

    SecureSocket? socket;
    try {
      socket = await SecureSocket.connect('imap.gmail.com', 993, timeout: const Duration(seconds: 10));
      final session = _ImapSession(socket);
      await session.readBanner();

      final loginOk = await session.sendCommand('LOGIN "$cleanEmail" "$cleanPassword"');
      await session.sendCommand('LOGOUT');
      await session.close();

      if (!loginOk) {
        throw Exception(
          'Authentication Failed: Invalid App Password. Ensure 2-Step Verification is ON and generate a 16-character App Password at myaccount.google.com/apppasswords',
        );
      }
      return true;
    } catch (e) {
      if (socket != null) {
        try {
          socket.destroy();
        } catch (_) {}
      }

      final errStr = e.toString();
      if (errStr.contains('AUTHENTICATIONFAILED') || errStr.contains('Invalid credentials')) {
        throw Exception(
          'Authentication Failed: Invalid App Password. Ensure 2-Step Verification is ON and generate a 16-character App Password at myaccount.google.com/apppasswords',
        );
      }
      if (e is SocketException || errStr.contains('Failed host lookup') || errStr.contains('11001')) {
        throw Exception('No Internet Connection: Unable to connect to imap.gmail.com.');
      }
      rethrow;
    }
  }

  /// Stream/Fetch recent emails with PDF, Excel, or CSV invoice attachments directly via IMAP SSL
  Stream<List<EmailHeaderInfo>> fetchRecentSupplierInvoicesStream({
    required String email,
    required String appPassword,
    int maxResults = 50,
    int chunkSize = 10,
  }) async* {
    final cleanEmail = email.trim();
    final cleanPassword = cleanAppPassword(appPassword);

    if (cleanEmail.isEmpty || cleanPassword.isEmpty) {
      throw Exception('Gmail address and App Password are required.');
    }

    SecureSocket? socket;
    try {
      socket = await SecureSocket.connect('imap.gmail.com', 993, timeout: const Duration(seconds: 12));
      final session = _ImapSession(socket);
      await session.readBanner();

      final loginOk = await session.sendCommand('LOGIN "$cleanEmail" "$cleanPassword"');
      if (!loginOk) {
        await session.close();
        throw Exception(
          'Gmail Login Failed: Please check your 16-character App Password at myaccount.google.com/apppasswords',
        );
      }

      await session.sendCommand('SELECT INBOX');

      final searchResponse = await session.sendCommandWithData('SEARCH ALL');
      final msgNumbers = _parseSearchNumbers(searchResponse);

      if (msgNumbers.isEmpty) {
        await session.sendCommand('LOGOUT');
        await session.close();
        return;
      }

      msgNumbers.sort((a, b) => b.compareTo(a)); // Newest first
      final targetIds = msgNumbers.take(maxResults).toList();

      for (int i = 0; i < targetIds.length; i += chunkSize) {
        final end = i + chunkSize > targetIds.length ? targetIds.length : i + chunkSize;
        final chunk = targetIds.sublist(i, end);

        final rangeStr = chunk.join(',');
        final fetchResponse = await session.sendCommandWithData('FETCH $rangeStr (BODY.PEEK[HEADER.FIELDS (SUBJECT FROM DATE)] BODYSTRUCTURE)');

        final parsedChunk = _parseFetchHeadersResponse(fetchResponse);

        if (parsedChunk.isNotEmpty) {
          yield parsedChunk;
        }
      }

      await session.sendCommand('LOGOUT');
      await session.close();
    } catch (e) {
      if (socket != null) {
        try {
          socket.destroy();
        } catch (_) {}
      }
      if (e is SocketException || e.toString().contains('Failed host lookup') || e.toString().contains('11001')) {
        throw Exception('No Internet Connection: Unable to connect to imap.gmail.com.');
      }
      rethrow;
    }
  }

  /// Download an attachment file directly from IMAP email
  Future<File?> downloadAttachment({
    required String email,
    required String appPassword,
    required String messageId,
    required EmailAttachmentInfo attachment,
  }) async {
    final cleanEmail = email.trim();
    final cleanPassword = cleanAppPassword(appPassword);

    if (cleanEmail.isEmpty || cleanPassword.isEmpty) return null;

    SecureSocket? socket;
    try {
      socket = await SecureSocket.connect('imap.gmail.com', 993, timeout: const Duration(seconds: 15));
      final session = _ImapSession(socket);
      await session.readBanner();

      final loginOk = await session.sendCommand('LOGIN "$cleanEmail" "$cleanPassword"');
      if (!loginOk) {
        await session.close();
        return null;
      }

      await session.sendCommand('SELECT INBOX');

      int seqNum = int.tryParse(messageId.split('_').first) ?? 1;
      String bodyData = await session.sendCommandWithData('FETCH $seqNum BODY[]');
      List<int> attachmentBytes = _extractAttachmentBytesFromRawMime(bodyData, attachment.filename);

      if (attachmentBytes.isEmpty) {
        final searchResp = await session.sendCommandWithData('SEARCH TEXT "${attachment.filename}"');
        final nums = _parseSearchNumbers(searchResp);
        if (nums.isNotEmpty) {
          seqNum = nums.first;
          bodyData = await session.sendCommandWithData('FETCH $seqNum BODY[]');
          attachmentBytes = _extractAttachmentBytesFromRawMime(bodyData, attachment.filename);
        }
      }

      await session.sendCommand('LOGOUT');
      await session.close();

      if (attachmentBytes.isEmpty) {
        debugPrint("Could not extract valid attachment bytes for: ${attachment.filename}");
        return null;
      }

      final safeFilename = attachment.filename.replaceAll(RegExp(r'[^\w\.-]'), '_');
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/$safeFilename';
      final file = File(filePath);

      await file.writeAsBytes(attachmentBytes);
      return file;
    } catch (e) {
      debugPrint("IMAP attachment download error: $e");
      if (socket != null) {
        try {
          socket.destroy();
        } catch (_) {}
      }
    }
    return null;
  }

  static List<int> _parseSearchNumbers(String response) {
    List<int> nums = [];
    final lines = response.split('\r\n');
    for (var l in lines) {
      if (l.toUpperCase().startsWith('* SEARCH')) {
        final parts = l.split(' ');
        for (var p in parts) {
          final val = int.tryParse(p);
          if (val != null) nums.add(val);
        }
      }
    }
    return nums;
  }

  static List<EmailHeaderInfo> _parseFetchHeadersResponse(String rawResponse) {
    List<EmailHeaderInfo> list = [];
    final msgBlocks = rawResponse.split(RegExp(r'\* \d+ FETCH'));

    for (var block in msgBlocks) {
      if (block.trim().isEmpty) continue;

      String subject = '(No Subject)';
      String from = 'Unknown Sender';
      String date = '';

      final lines = block.split('\r\n');
      for (var l in lines) {
        final lower = l.toLowerCase();
        if (lower.startsWith('subject:')) {
          subject = l.substring(8).trim();
        } else if (lower.startsWith('from:')) {
          from = l.substring(5).trim();
        } else if (lower.startsWith('date:')) {
          date = l.substring(5).trim();
        }
      }

      final lowerFrom = from.toLowerCase();
      if (lowerFrom.contains('no-reply@accounts.google.com') ||
          lowerFrom.contains('accounts@firefox.com') ||
          lowerFrom.contains('notifications@github.com')) {
        continue;
      }

      final matchSeq = RegExp(r'^\s*(\d+)').firstMatch(block);
      final seqId = matchSeq != null ? matchSeq.group(1)! : '${DateTime.now().millisecondsSinceEpoch}';

      // Extract all actual filenames from BODYSTRUCTURE / MIME headers
      List<EmailAttachmentInfo> attachments = [];
      final filenameRegex = RegExp(
        r'["\s=]([a-zA-Z0-9_.-]+\.(?:pdf|xlsx|xls|csv|zip|txt|doc|docx))["\s\);]',
        caseSensitive: false,
      );

      final matches = filenameRegex.allMatches(block);
      Set<String> seenFilenames = {};

      for (var m in matches) {
        if (m.group(1) != null) {
          String cleanFn = m.group(1)!.trim().replaceAll('"', '').replaceAll("'", '');
          if (cleanFn.isNotEmpty && !seenFilenames.contains(cleanFn.toLowerCase())) {
            seenFilenames.add(cleanFn.toLowerCase());

            String mimeType = 'application/octet-stream';
            final lower = cleanFn.toLowerCase();
            if (lower.endsWith('.pdf')) {
              mimeType = 'application/pdf';
            } else if (lower.endsWith('.xlsx')) {
              mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
            } else if (lower.endsWith('.xls')) {
              mimeType = 'application/vnd.ms-excel';
            } else if (lower.endsWith('.csv')) {
              mimeType = 'text/csv';
            }

            attachments.add(EmailAttachmentInfo(
              attachmentId: '${seqId}_$cleanFn',
              filename: cleanFn,
              mimeType: mimeType,
              size: 0,
            ));
          }
        }
      }

      // If no filename was found in BODYSTRUCTURE, check subject or create fallback with clean subject
      if (attachments.isEmpty) {
        String cleanSubject = subject.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
        String fallbackFilename = '$cleanSubject.pdf';

        final lowerSub = subject.toLowerCase();
        if (lowerSub.contains('.xlsx') || lowerSub.contains('excel')) {
          fallbackFilename = '$cleanSubject.xlsx';
        } else if (lowerSub.contains('.csv')) {
          fallbackFilename = '$cleanSubject.csv';
        } else if (lowerSub.contains('.xls')) {
          fallbackFilename = '$cleanSubject.xls';
        }

        attachments.add(EmailAttachmentInfo(
          attachmentId: '${seqId}_invoice',
          filename: fallbackFilename,
          mimeType: fallbackFilename.endsWith('.xlsx')
              ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
              : (fallbackFilename.endsWith('.csv') ? 'text/csv' : 'application/pdf'),
          size: 0,
        ));
      }

      list.add(EmailHeaderInfo(
        id: seqId,
        threadId: seqId,
        snippet: subject,
        subject: subject,
        from: from,
        date: date,
        attachments: attachments,
      ));
    }

    return list;
  }

  static List<int> _extractAttachmentBytesFromRawMime(String mimeText, String targetFilename) {
    try {
      final cleanTarget = targetFilename.toLowerCase().trim();
      final targetExt = cleanTarget.contains('.') ? cleanTarget.split('.').last : '';

      // 1. Try splitting by MIME boundaries
      final boundaryMatch = RegExp(r'boundary="?([^"\r\n;]+)"?', caseSensitive: false).firstMatch(mimeText);
      List<String> parts = [];
      if (boundaryMatch != null && boundaryMatch.group(1) != null) {
        final boundary = boundaryMatch.group(1)!;
        parts = mimeText.split('--$boundary');
      } else {
        parts = mimeText.split(RegExp(r'\r?\n--'));
      }

      for (var p in parts) {
        final lowerP = p.toLowerCase();
        bool isCandidate = lowerP.contains(cleanTarget) ||
            (targetExt.isNotEmpty && lowerP.contains('.$targetExt')) ||
            lowerP.contains('content-disposition: attachment') ||
            lowerP.contains('base64');

        if (isCandidate) {
          int doubleNewline = p.indexOf('\r\n\r\n');
          if (doubleNewline == -1) doubleNewline = p.indexOf('\n\n');

          if (doubleNewline != -1) {
            String rawBase64 = p.substring(doubleNewline + 2).trim();
            if (rawBase64.contains('\r\n--')) {
              rawBase64 = rawBase64.split('\r\n--').first;
            } else if (rawBase64.contains('\n--')) {
              rawBase64 = rawBase64.split('\n--').first;
            }
            if (rawBase64.contains('A') && rawBase64.contains(' OK ')) {
              final okIdx = rawBase64.indexOf(RegExp(r'A\d+\s+OK', caseSensitive: false));
              if (okIdx != -1) rawBase64 = rawBase64.substring(0, okIdx);
            }

            rawBase64 = rawBase64.replaceAll(RegExp(r'\s+'), '').trim();

            try {
              final bytes = base64.decode(rawBase64);
              if (bytes.length > 30) {
                if (targetExt == 'pdf' && bytes.length > 4 && bytes[0] == 0x25 && bytes[1] == 0x50) {
                  return bytes;
                }
                if (targetExt == 'xlsx' && bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
                  return bytes;
                }
                if (targetExt == 'xls' || targetExt == 'csv' || bytes.length > 100) {
                  return bytes;
                }
              }
            } catch (_) {}
          }
        }
      }

      // 2. Global search for base64 blocks following Content-Transfer-Encoding: base64
      final base64Regex = RegExp(
        r'Content-Transfer-Encoding:\s*base64[\s\S]*?\r?\n\r?\n([A-Za-z0-9+/=\r\n\s]{100,})',
        caseSensitive: false,
      );

      for (var match in base64Regex.allMatches(mimeText)) {
        if (match.group(1) != null) {
          String raw = match.group(1)!.replaceAll(RegExp(r'\s+'), '').trim();
          try {
            final bytes = base64.decode(raw);
            if (bytes.length > 30) {
              if (targetExt == 'pdf' && bytes.length > 4 && bytes[0] == 0x25 && bytes[1] == 0x50) {
                return bytes;
              }
              if (targetExt == 'xlsx' && bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
                return bytes;
              }
              if (targetExt == 'xls' || targetExt == 'csv' || bytes.length > 100) {
                return bytes;
              }
            }
          } catch (_) {}
        }
      }

      // 3. Fallback for PDF: JVBERi0 is base64 for %PDF-
      if (targetExt == 'pdf' || cleanTarget.contains('pdf')) {
        final pdfMatch = RegExp(r'(JVBERi0[A-Za-z0-9+/=\r\n\s]{100,})').firstMatch(mimeText);
        if (pdfMatch != null && pdfMatch.group(1) != null) {
          String raw = pdfMatch.group(1)!.replaceAll(RegExp(r'\s+'), '').trim();
          try {
            final bytes = base64.decode(raw);
            if (bytes.length > 4 && bytes[0] == 0x25 && bytes[1] == 0x50) {
              return bytes;
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint("Error extracting base64 attachment: $e");
    }
    return [];
  }
}

class _ImapSession {
  final SecureSocket _socket;
  int _tagCounter = 1;
  late StreamSubscription _subscription;
  final StringBuffer _buffer = StringBuffer();
  Completer<String>? _currentCompleter;
  String? _currentTag;

  _ImapSession(this._socket) {
    _subscription = _socket.listen(
      (data) {
        final text = utf8.decode(data, allowMalformed: true);
        _buffer.write(text);
        final currentText = _buffer.toString();

        if (_currentTag != null) {
          if (currentText.contains('${_currentTag!} OK') ||
              currentText.contains('${_currentTag!} NO') ||
              currentText.contains('${_currentTag!} BAD')) {
            if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
              _currentCompleter!.complete(currentText);
            }
          }
        } else {
          if (currentText.contains('* OK') || currentText.contains('* PREAUTH')) {
            if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
              _currentCompleter!.complete(currentText);
            }
          }
        }
      },
      onError: (err) {
        if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
          _currentCompleter!.completeError(err);
        }
      },
      onDone: () {
        if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
          _currentCompleter!.complete(_buffer.toString());
        }
      },
    );
  }

  Future<void> readBanner({Duration timeout = const Duration(seconds: 10)}) async {
    _currentTag = null;
    _buffer.clear();
    _currentCompleter = Completer<String>();
    try {
      await _currentCompleter!.future.timeout(timeout, onTimeout: () => _buffer.toString());
    } finally {
      _buffer.clear();
      _currentCompleter = null;
    }
  }

  Future<bool> sendCommand(String command) async {
    final tag = 'A$_tagCounter';
    _tagCounter++;
    _currentTag = tag;
    _buffer.clear();
    _currentCompleter = Completer<String>();

    _socket.write('$tag $command\r\n');

    try {
      final response = await _currentCompleter!.future.timeout(const Duration(seconds: 10), onTimeout: () => '');
      return response.contains('$tag OK');
    } finally {
      _currentTag = null;
      _currentCompleter = null;
    }
  }

  Future<String> sendCommandWithData(String command) async {
    final tag = 'A$_tagCounter';
    _tagCounter++;
    _currentTag = tag;
    _buffer.clear();
    _currentCompleter = Completer<String>();

    _socket.write('$tag $command\r\n');

    try {
      return await _currentCompleter!.future.timeout(const Duration(seconds: 12), onTimeout: () => _buffer.toString());
    } finally {
      _currentTag = null;
      _currentCompleter = null;
    }
  }

  Future<void> close() async {
    try {
      await _subscription.cancel();
      await _socket.close();
    } catch (_) {}
  }
}
