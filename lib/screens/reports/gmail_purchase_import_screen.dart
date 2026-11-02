import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/pharmacy_email_account.dart';
import '../../providers/gmail_account_provider.dart';
import '../../providers/app_provider.dart';
import '../../providers/pharmacy_provider.dart';
import '../../services/gmail_api_service.dart';
import '../../services/gmail_imap_service.dart';
import '../../database/db_helper.dart';

class ParsedInvoiceRow {
  final String emailId;
  final String wholesaleName;
  final String invoiceNumber;
  final String invoiceDate;
  final double totalAmount;
  final List<EmailAttachmentInfo> attachments;
  final EmailHeaderInfo rawEmail;
  bool isAlreadyImported;

  ParsedInvoiceRow({
    required this.emailId,
    required this.wholesaleName,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.totalAmount,
    required this.attachments,
    required this.rawEmail,
    this.isAlreadyImported = false,
  });

  DateTime get parsedDateTime {
    String dtStr = rawEmail.date.trim().isNotEmpty ? rawEmail.date : invoiceDate;
    return _parseEmailDateTime(dtStr);
  }
}

DateTime _parseEmailDateTime(String rawDateStr) {
  if (rawDateStr.trim().isEmpty) {
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String str = rawDateStr.trim();

  DateTime? parsed = DateTime.tryParse(str);
  if (parsed != null) return parsed;

  try {
    if (str.contains(',')) {
      final parts = str.split(',');
      if (parts.length > 1) {
        str = parts.sublist(1).join(',').trim();
      }
    }

    const monthMap = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
    };

    final tokens = str.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    int? day;
    int? month;
    int? year;
    int hour = 0;
    int minute = 0;
    int second = 0;

    for (var token in tokens) {
      final clean = token.toLowerCase().replaceAll(RegExp(r'[^a-z0-9:]'), '');
      if (clean.isEmpty) continue;

      if (monthMap.containsKey(clean)) {
        month = monthMap[clean];
        continue;
      }

      if (clean.contains(':')) {
        final timeParts = clean.split(':');
        if (timeParts.length >= 2) {
          hour = int.tryParse(timeParts[0]) ?? 0;
          minute = int.tryParse(timeParts[1]) ?? 0;
          if (timeParts.length >= 3) {
            second = int.tryParse(timeParts[2]) ?? 0;
          }
        }
        continue;
      }

      final numVal = int.tryParse(clean);
      if (numVal != null) {
        if (numVal > 1000) {
          year = numVal;
        } else if (numVal >= 1 && numVal <= 31 && day == null) {
          day = numVal;
        } else if (numVal >= 1 && numVal <= 12 && month == null) {
          month = numVal;
        }
      }
    }

    if (year != null && month != null && day != null) {
      return DateTime(year, month, day, hour, minute, second);
    }
  } catch (_) {}

  return DateTime.fromMillisecondsSinceEpoch(0);
}

enum ImportColumnType { text, numeric, date }

class GmailPurchaseImportScreen extends StatefulWidget {
  final List<PharmacyProfile> profiles;

  const GmailPurchaseImportScreen({super.key, required this.profiles});

  @override
  State<GmailPurchaseImportScreen> createState() => _GmailPurchaseImportScreenState();
}

class _GmailPurchaseImportScreenState extends State<GmailPurchaseImportScreen> {
  static const String _defaultQuery = 'has:attachment';

  final ScrollController _horizontalScrollCtrl = ScrollController();
  final ScrollController _verticalScrollCtrl = ScrollController();

  final TextEditingController _emailCtrl = TextEditingController(text: 'sahakarmedicalskpt@gmail.com');
  final TextEditingController _appPasswordCtrl = TextEditingController();

  List<ParsedInvoiceRow> _allParsedRows = [];
  bool _isLoading = false;
  String? _error;
  bool _isConnectingAppPassword = false;
  bool _obscureAppPassword = true;
  bool _showGuide = false;

  // Filtering & Sorting State
  final Map<String, String> _columnFilters = {};
  final Map<String, String> _columnConditions = {};
  String? _sortColumnKey = 'date';
  bool _isAscending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSupplierEmails();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_allParsedRows.isNotEmpty) {
      _refreshImportedStatusesFromDb();
    }
  }

  @override
  void dispose() {
    _horizontalScrollCtrl.dispose();
    _verticalScrollCtrl.dispose();
    _emailCtrl.dispose();
    _appPasswordCtrl.dispose();
    super.dispose();
  }

  /// Query SQLite database to find all supplier invoice numbers that have already been imported
  Future<Set<String>> _fetchImportedInvoiceNumbersFromDb() async {
    Set<String> set = {};
    try {
      final db = await DbHelper.instance.database;
      final results = await db.rawQuery(
        "SELECT DISTINCT sup_inv_no FROM purchase_entries WHERE sup_inv_no IS NOT NULL AND sup_inv_no != ''",
      );

      for (var r in results) {
        String? invNo = r['sup_inv_no']?.toString().trim();
        if (invNo != null && invNo.isNotEmpty) {
          String clean = invNo.toLowerCase();
          set.add(clean);
          set.add(clean.replaceAll(RegExp(r'[^a-zA-Z0-9]'), ''));
        }
      }
    } catch (e) {
      debugPrint("Error fetching imported invoice numbers from DB: $e");
    }
    return set;
  }

  /// Mark rows as imported if their invoice number exists in SQLite database
  void _updateImportedStatusFromDb(List<ParsedInvoiceRow> rows, Set<String> importedNumbers) {
    for (var r in rows) {
      String cleanInv = r.invoiceNumber.trim().toLowerCase();
      String strippedInv = cleanInv.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');

      if (importedNumbers.contains(cleanInv) || importedNumbers.contains(strippedInv)) {
        r.isAlreadyImported = true;
      }
    }
  }

  Future<void> _refreshImportedStatusesFromDb() async {
    final importedNumbers = await _fetchImportedInvoiceNumbersFromDb();
    if (!mounted) return;

    for (var r in _allParsedRows) {
      r.isAlreadyImported = false;
    }

    _updateImportedStatusFromDb(_allParsedRows, importedNumbers);
    setState(() {});
  }

  /// Save extracted invoice rows to local persistent cache
  Future<void> _saveInvoicesToCache(String profileId, List<ParsedInvoiceRow> rows) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<Map<String, dynamic>> jsonList = rows.map((r) => {
        'emailId': r.emailId,
        'wholesaleName': r.wholesaleName,
        'invoiceNumber': r.invoiceNumber,
        'invoiceDate': r.invoiceDate,
        'totalAmount': r.totalAmount,
        'isAlreadyImported': r.isAlreadyImported,
        'attachments': r.attachments.map((a) => {
          'attachmentId': a.attachmentId,
          'filename': a.filename,
          'mimeType': a.mimeType,
          'size': a.size,
        }).toList(),
        'rawEmail': {
          'id': r.rawEmail.id,
          'threadId': r.rawEmail.threadId,
          'snippet': r.rawEmail.snippet,
          'subject': r.rawEmail.subject,
          'from': r.rawEmail.from,
          'date': r.rawEmail.date,
        },
      }).toList();

      final encoded = jsonEncode(jsonList);
      await prefs.setString('gmail_invoices_cache_$profileId', encoded);
      await prefs.setString('gmail_invoices_cache_global', encoded);
      await prefs.setInt('gmail_invoices_timestamp_$profileId', DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint("Error saving invoice cache: $e");
    }
  }

  /// Restore cached invoices from local storage permanently until user clicks Refresh
  Future<bool> _loadInvoicesFromCache(String profileId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? jsonStr = prefs.getString('gmail_invoices_cache_$profileId');
      jsonStr ??= prefs.getString('gmail_invoices_cache_global');

      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> decodedList = jsonDecode(jsonStr);
        if (decodedList.isNotEmpty) {
          final importedNumbers = await _fetchImportedInvoiceNumbersFromDb();

          List<ParsedInvoiceRow> restoredRows = decodedList.map((item) {
            final map = Map<String, dynamic>.from(item);
            final attList = (map['attachments'] as List<dynamic>? ?? []).map((a) {
              final attMap = Map<String, dynamic>.from(a);
              return EmailAttachmentInfo(
                attachmentId: attMap['attachmentId'] ?? '',
                filename: attMap['filename'] ?? '',
                mimeType: attMap['mimeType'] ?? '',
                size: attMap['size'] ?? 0,
              );
            }).toList();

            final rawMap = Map<String, dynamic>.from(map['rawEmail'] ?? {});
            final rawEmail = EmailHeaderInfo(
              id: rawMap['id'] ?? map['emailId'],
              threadId: rawMap['threadId'] ?? '',
              snippet: rawMap['snippet'] ?? '',
              subject: rawMap['subject'] ?? '',
              from: rawMap['from'] ?? map['wholesaleName'],
              date: rawMap['date'] ?? map['invoiceDate'],
              attachments: attList,
            );

            return ParsedInvoiceRow(
              emailId: map['emailId'] ?? '',
              wholesaleName: map['wholesaleName'] ?? '',
              invoiceNumber: map['invoiceNumber'] ?? '',
              invoiceDate: map['invoiceDate'] ?? '',
              totalAmount: (map['totalAmount'] as num?)?.toDouble() ?? 0.0,
              attachments: attList,
              rawEmail: rawEmail,
              isAlreadyImported: map['isAlreadyImported'] ?? false,
            );
          }).toList();

          bool hasAnyAttachment = restoredRows.any((r) => r.attachments.isNotEmpty);
          if (!hasAnyAttachment) {
            debugPrint("Stale local cache with 0 attachments detected. Forcing fresh Gmail fetch...");
            return false;
          }

          _updateImportedStatusFromDb(restoredRows, importedNumbers);
          restoredRows.sort((a, b) => b.parsedDateTime.compareTo(a.parsedDateTime));

          if (!mounted) return true;
          setState(() {
            _allParsedRows = restoredRows;
            _isLoading = false;
            _error = null;
          });
          return true; // Loaded permanently from local cache!
        }
      }
    } catch (e) {
      debugPrint("Error loading invoice cache: $e");
    }
    return false;
  }

  Future<void> _loadSupplierEmails({bool forceRefresh = false}) async {
    final accountProvider = Provider.of<GmailAccountProvider>(context, listen: false);
    final activeAccount = accountProvider.activeAccount;

    // 1. If not forcing a refresh, load previous data instantly from local cache
    if (!forceRefresh) {
      String targetProfile = activeAccount?.profileId ?? 'default';
      bool cached = await _loadInvoicesFromCache(targetProfile);
      if (cached && _allParsedRows.isNotEmpty) {
        return; // Display previous data permanently!
      }
    }

    if (activeAccount == null) {
      if (_allParsedRows.isEmpty) {
        setState(() {
          _allParsedRows = [];
          _error = null;
        });
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final importedNumbers = await _fetchImportedInvoiceNumbersFromDb();
    List<ParsedInvoiceRow> accumulatedRows = [];

    try {
      final stream = activeAccount.isAppPasswordMode
          ? GmailImapService.instance.fetchRecentSupplierInvoicesStream(
              email: activeAccount.email,
              appPassword: activeAccount.appPassword!,
              maxResults: 50,
              chunkSize: 10,
            )
          : GmailApiService.fetchRecentEmailsStream(
              authHeaders: activeAccount.authHeaders,
              refreshToken: activeAccount.refreshToken,
              onTokenRefreshed: (newHeaders) {
                activeAccount.authHeaders = newHeaders;
                accountProvider.updateAuthHeadersForProfile(activeAccount.profileId, newHeaders);
              },
              maxResults: 50,
              chunkSize: 10,
              query: _defaultQuery,
            );

      await for (final batch in stream) {
        if (!mounted) return;

        final parsedBatch = _parseEmailsToInvoiceRows(batch);
        _updateImportedStatusFromDb(parsedBatch, importedNumbers);
        accumulatedRows.addAll(parsedBatch);
        accumulatedRows.sort((a, b) => b.parsedDateTime.compareTo(a.parsedDateTime));

        setState(() {
          _allParsedRows = List.from(accumulatedRows);
          _isLoading = false;
        });
      }

      if (accumulatedRows.isNotEmpty) {
        await _saveInvoicesToCache(activeAccount.profileId, accumulatedRows);
      } else if (mounted) {
        setState(() {
          _allParsedRows = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().contains('401') || e.toString().contains('invalid authentication credentials')
              ? "Gmail session expired. Click Re-connect Google Account below."
              : "Error fetching emails: $e";
          _isLoading = false;
        });
      }
    }
  }

  /// Parses each email into distinct invoice rows with accurate invoice numbers
  List<ParsedInvoiceRow> _parseEmailsToInvoiceRows(List<EmailHeaderInfo> emails) {
    List<ParsedInvoiceRow> rows = [];
    PharmacyProvider? provider;
    try {
      if (mounted) provider = Provider.of<PharmacyProvider>(context, listen: false);
    } catch (_) {}

    for (var email in emails) {
      final lowerFrom = email.from.toLowerCase();
      if (lowerFrom.contains('no-reply@accounts.google.com') ||
          lowerFrom.contains('accounts@firefox.com') ||
          lowerFrom.contains('notifications@github.com')) {
        continue;
      }

      String wholesaleName = _extractWholesaleName(email.from, provider);
      String invoiceDate = _extractFormattedDate(email.date);
      double totalAmount = _extractTotalAmount(email.snippet);
      List<String> invoiceNumbers = _extractAllInvoiceNumbers(email.subject, email.snippet);

      if (invoiceNumbers.isEmpty) {
        invoiceNumbers = [_extractFallbackInvNo(email.subject, email.id)];
      }

      for (var invNo in invoiceNumbers) {
        rows.add(ParsedInvoiceRow(
          emailId: email.id,
          wholesaleName: wholesaleName,
          invoiceNumber: invNo,
          invoiceDate: invoiceDate,
          totalAmount: totalAmount,
          attachments: email.attachments,
          rawEmail: email,
        ));
      }
    }

    return rows;
  }

  String _extractWholesaleName(String fromHeader, [PharmacyProvider? provider]) {
    String rawName = fromHeader;
    if (fromHeader.contains('<')) {
      String name = fromHeader.split('<').first.trim();
      name = name.replaceAll('"', '').replaceAll("'", '');
      if (name.isNotEmpty) rawName = name;
    } else {
      rawName = fromHeader.trim();
    }
    if (rawName.isEmpty) rawName = 'Unknown Wholesale';

    // Match against Format Manager formats if available
    if (provider != null && provider.importMappings.isNotEmpty) {
      String cleanTarget = rawName
          .replaceAll(' - EXCEL', '')
          .replaceAll(' - PDF', '')
          .replaceAll(' - excel', '')
          .replaceAll(' - pdf', '')
          .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '')
          .trim()
          .toLowerCase();

      final targetTokens = cleanTarget
          .split(RegExp(r'\s+'))
          .where((t) => t.length > 2 && t != 'private' && t != 'limited' && t != 'ltd' && t != 'pvt')
          .toList();

      for (var m in provider.importMappings) {
        String cleanM = m.name
            .replaceAll(' - EXCEL', '')
            .replaceAll(' - PDF', '')
            .replaceAll(' - excel', '')
            .replaceAll(' - pdf', '')
            .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '')
            .trim()
            .toLowerCase();

        final mTokens = cleanM
            .split(RegExp(r'\s+'))
            .where((t) => t.length > 2 && t != 'private' && t != 'limited' && t != 'ltd' && t != 'pvt')
            .toList();

        if (cleanTarget == cleanM || cleanTarget.contains(cleanM) || cleanM.contains(cleanTarget)) {
          return m.name
              .replaceAll(' - EXCEL', '')
              .replaceAll(' - PDF', '')
              .replaceAll(' - excel', '')
              .replaceAll(' - pdf', '')
              .trim();
        }

        if (targetTokens.isNotEmpty && mTokens.isNotEmpty) {
          if (targetTokens.first == mTokens.first) {
            if (targetTokens.length == 1 || mTokens.length == 1 || targetTokens[1] == mTokens[1]) {
              return m.name
                  .replaceAll(' - EXCEL', '')
                  .replaceAll(' - PDF', '')
                  .replaceAll(' - excel', '')
                  .replaceAll(' - pdf', '')
                  .trim();
            }
          }
        }
      }
    }

    return rawName;
  }

  List<String> _extractAllInvoiceNumbers(String subject, String snippet) {
    List<String> list = [];
    final text = '$subject\n$snippet';

    final invRegex = RegExp(
      r'(?:Invoice|Inv|Bill)\s*(?:No|#|\.|:)?\s*[:=]?\s*([0-9A-Za-z,/\s-]+)',
      caseSensitive: false,
    );

    final match = invRegex.firstMatch(text);
    if (match != null && match.group(1) != null) {
      String rawInvoices = match.group(1)!.trim();
      if (rawInvoices.toLowerCase().contains('for') ||
          rawInvoices.toLowerCase().contains('has') ||
          rawInvoices.contains('\n')) {
        rawInvoices = rawInvoices.split(RegExp(r'\s+')).first;
      }

      List<String> parts = rawInvoices.split(',');
      for (var p in parts) {
        String cleaned = p.trim().replaceAll(RegExp(r'[^A-Za-z0-9/-]'), '');
        if (cleaned.length >= 4) {
          list.add(cleaned);
        }
      }
    }

    return list;
  }

  String _extractFallbackInvNo(String subject, String emailId) {
    final numRegex = RegExp(r'[0-9]{6,}');
    final match = numRegex.firstMatch(subject);
    if (match != null) {
      return match.group(0)!;
    }
    return 'INV-${emailId.substring(0, 6)}';
  }

  String _extractFormattedDate(String dateHeader) {
    try {
      if (dateHeader.contains(',')) {
        List<String> parts = dateHeader.split(',');
        if (parts.length > 1) {
          String rest = parts[1].trim();
          List<String> tokens = rest.split(' ');
          if (tokens.length >= 3) {
            return '${tokens[0]} ${tokens[1]} ${tokens[2]}';
          }
        }
      }
    } catch (_) {}
    return dateHeader.length > 11 ? dateHeader.substring(0, 11) : dateHeader;
  }

  double _extractTotalAmount(String snippet) {
    final amountRegex = RegExp(
      r'(?:Total Amount of|Total Amount|Amount of|Rs\.|INR|₹)\s*[:=]?\s*(?:Rs\.|INR|₹)?\s*([0-9]+(?:\.[0-9]{2})?)',
      caseSensitive: false,
    );
    final match = amountRegex.firstMatch(snippet);
    if (match != null && match.group(1) != null) {
      return double.tryParse(match.group(1)!) ?? 0.0;
    }
    return 0.0;
  }

  /// Real-time column filtering and sorting engine
  List<ParsedInvoiceRow> _getFilteredAndSortedRows() {
    List<ParsedInvoiceRow> result = List.from(_allParsedRows);

    result = result.where((row) {
      bool matches = true;

      _columnFilters.forEach((key, filterValue) {
        if (filterValue.trim().isEmpty) return;
        final val = filterValue.trim().toLowerCase();
        final condition = _columnConditions[key] ?? (key == 'amount' ? 'Equals' : 'Contains');

        if (key == 'wholesale') {
          final cell = row.wholesaleName.toLowerCase();
          if (condition == 'Equals' && cell != val) {
            matches = false;
          } else if (condition == 'Contains' && !cell.contains(val)) {
            matches = false;
          } else if (condition == 'Begins With' && !cell.startsWith(val)) {
            matches = false;
          } else if (condition == 'Ends With' && !cell.endsWith(val)) {
            matches = false;
          }
        } else if (key == 'invNo') {
          final cell = row.invoiceNumber.toLowerCase();
          if (condition == 'Equals' && cell != val) {
            matches = false;
          } else if (condition == 'Contains' && !cell.contains(val)) {
            matches = false;
          } else if (condition == 'Begins With' && !cell.startsWith(val)) {
            matches = false;
          } else if (condition == 'Ends With' && !cell.endsWith(val)) {
            matches = false;
          }
        } else if (key == 'date') {
          final cell = row.invoiceDate.toLowerCase();
          if (!cell.contains(val)) {
            matches = false;
          }
        } else if (key == 'amount') {
          double? filterNum = double.tryParse(val);
          if (filterNum != null) {
            if (condition == 'Equals' && (row.totalAmount - filterNum).abs() > 0.01) {
              matches = false;
            } else if (condition == 'Greater Than' && row.totalAmount <= filterNum) {
              matches = false;
            } else if (condition == 'Less Than' && row.totalAmount >= filterNum) {
              matches = false;
            }
          }
        }
      });

      return matches;
    }).toList();

    if (_sortColumnKey != null) {
      result.sort((a, b) {
        int cmp = 0;
        if (_sortColumnKey == 'wholesale') {
          cmp = a.wholesaleName.compareTo(b.wholesaleName);
        } else if (_sortColumnKey == 'invNo') {
          cmp = a.invoiceNumber.compareTo(b.invoiceNumber);
        } else if (_sortColumnKey == 'date') {
          cmp = a.parsedDateTime.compareTo(b.parsedDateTime);
          if (cmp == 0) {
            cmp = a.invoiceNumber.compareTo(b.invoiceNumber);
          }
        } else if (_sortColumnKey == 'amount') {
          cmp = a.totalAmount.compareTo(b.totalAmount);
        }
        return _isAscending ? cmp : -cmp;
      });
    }

    return result;
  }

  void _onSortColumn(String key) {
    setState(() {
      if (_sortColumnKey == key) {
        _isAscending = !_isAscending;
      } else {
        _sortColumnKey = key;
        _isAscending = key == 'date' ? false : true;
      }
    });
  }

  void _showConditionMenu(TapDownDetails details, String columnKey, ImportColumnType type) async {
    List<String> items = [];
    if (type == ImportColumnType.text) {
      items = ['Contains', 'Equals', 'Begins With', 'Ends With'];
    } else if (type == ImportColumnType.numeric) {
      items = ['Equals', 'Greater Than', 'Less Than'];
    } else {
      items = ['Contains', 'Equals'];
    }

    final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(details.globalPosition.dx, details.globalPosition.dy + 10, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: items
          .map((e) => PopupMenuItem(
                value: e,
                height: 30,
                child: Text(e, style: const TextStyle(fontSize: 11)),
              ))
          .toList(),
    );

    if (result != null) {
      setState(() {
        _columnConditions[columnKey] = result;
      });
    }
  }

  String _getCleanFilename(String filename) {
    String clean = filename.trim();
    if (clean.toLowerCase().startsWith('import ')) {
      clean = clean.substring(7).trim();
    }
    return clean;
  }

  Future<void> _importAttachmentToPurchase(
    ParsedInvoiceRow row,
    EmailAttachmentInfo attachment,
  ) async {
    final accountProvider = Provider.of<GmailAccountProvider>(context, listen: false);
    final activeAccount = accountProvider.activeAccount;
    if (activeAccount == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Downloading Invoice Attachment...'),
          ],
        ),
      ),
    );

    File? downloadedFile;
    try {
      if (activeAccount.isAppPasswordMode) {
        downloadedFile = await GmailImapService.instance.downloadAttachment(
          email: activeAccount.email,
          appPassword: activeAccount.appPassword!,
          messageId: row.emailId,
          attachment: attachment,
        );
      } else {
        downloadedFile = await GmailApiService.downloadEmailAttachment(
          authHeaders: activeAccount.authHeaders,
          refreshToken: activeAccount.refreshToken,
          onTokenRefreshed: (Map<String, String> newHeaders) {
            activeAccount.authHeaders = newHeaders;
          },
          messageId: row.emailId,
          attachment: attachment,
        );
      }
    } catch (e) {
      debugPrint("Download attachment error: $e");
    }

    if (!mounted) return;
    Navigator.pop(context);

    if (downloadedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to download invoice attachment.')),
      );
      return;
    }

    final app = Provider.of<AppProvider>(context, listen: false);
    app.openPurchaseWithImportFile(
      filePath: downloadedFile.path,
      supplierName: row.wholesaleName,
      invoiceNo: row.invoiceNumber,
      invDate: row.invoiceDate,
    );
  }

  Future<void> _confirmAndSignOut(
    BuildContext context,
    GmailAccountProvider provider,
  ) async {
    final profileId = provider.activeProfileId;
    if (profileId == null) return;
    final messenger = ScaffoldMessenger.of(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.red),
            SizedBox(width: 8),
            Text('Sign Out from Gmail?'),
          ],
        ),
        content: Text(
          'Are you sure you want to log out from ${provider.activeAccount?.email ?? "this account"}?\n\nYou will need to connect your Google account again to fetch new invoices.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await provider.signOutProfile(profileId);
      if (!mounted) return;
      setState(() {
        _allParsedRows.clear();
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Successfully logged out from Gmail.')),
      );
    }
  }

  Future<void> _handleConnectAppPassword(GmailAccountProvider provider, String profileId) async {
    final email = _emailCtrl.text.trim();
    final password = _appPasswordCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your Gmail address and 16-character App Password.')),
      );
      return;
    }

    setState(() {
      _isConnectingAppPassword = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    final bool success = await provider.connectWithAppPassword(
      profileId: profileId,
      email: email,
      appPassword: password,
    );

    if (!mounted) return;
    setState(() {
      _isConnectingAppPassword = false;
    });

    if (success) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('⚡ Connected to Gmail successfully via App Password (Permanent Connection)!'),
          backgroundColor: Colors.green,
        ),
      );
      _loadSupplierEmails(forceRefresh: true);
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Failed to connect. Check App Password.'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  Widget _buildConnectedProfileChip(
    BuildContext context,
    GmailAccountProvider provider,
    PharmacyEmailAccount account,
  ) {
    final String initial = (account.displayName.isNotEmpty
            ? account.displayName[0]
            : (account.email.isNotEmpty ? account.email[0] : 'G'))
        .toUpperCase();

    return PopupMenuButton<String>(
      tooltip: 'Linked Account: ${account.email}',
      offset: const Offset(0, 42),
      onSelected: (value) async {
        if (value == 'switch') {
          final profileId = provider.activeProfileId ?? 'default';
          await provider.signOutProfile(profileId);
          if (mounted) setState(() => _allParsedRows.clear());
        } else if (value == 'signout') {
          await _confirmAndSignOut(context, provider);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                account.displayName.isNotEmpty ? account.displayName : 'Gmail Linked',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
              ),
              Text(
                account.email,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    account.isAppPasswordMode ? 'Permanent App Password Mode' : 'OAuth Synced',
                    style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'switch',
          child: Row(
            children: [
              Icon(Icons.swap_horiz, size: 18, color: Colors.blue),
              SizedBox(width: 8),
              Text('Re-configure Credentials', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'signout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('Sign Out / Logout', style: TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.green.shade400, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withAlpha(20),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (account.photoUrl != null && account.photoUrl!.isNotEmpty)
              CircleAvatar(
                radius: 12,
                backgroundImage: NetworkImage(account.photoUrl!),
                backgroundColor: Colors.transparent,
              )
            else
              CircleAvatar(
                radius: 12,
                backgroundColor: Colors.green.shade700,
                child: Text(
                  initial,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'CONNECTED',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                Text(
                  account.email,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade900,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 18, color: Colors.green.shade800),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayRows = _getFilteredAndSortedRows();

    return Consumer<GmailAccountProvider>(
      builder: (context, provider, child) {
        final activeAccount = provider.activeAccount;
        final currentProfile = widget.profiles.firstWhere(
          (p) => p.id == provider.activeProfileId,
          orElse: () => widget.profiles.isNotEmpty
              ? widget.profiles.first
              : PharmacyProfile(id: 'default', name: 'Main Pharmacy'),
        );

        return Scaffold(
          appBar: AppBar(
            title: const Text('Import Purchase Entries from Gmail'),
            actions: [
              if (activeAccount != null) ...[
                _buildConnectedProfileChip(context, provider, activeAccount),
                const SizedBox(width: 8),
              ],
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => _loadSupplierEmails(forceRefresh: true),
                tooltip: 'Refresh from Gmail',
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
            children: [
              _buildHeader(context, provider, currentProfile, activeAccount),
              const Divider(height: 1),
              Expanded(
                child: activeAccount == null
                    ? _buildUnlinkedState(context, provider, currentProfile)
                    : _buildFrozenHeaderInvoiceTable(displayRows),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    GmailAccountProvider provider,
    PharmacyProfile currentProfile,
    PharmacyEmailAccount? activeAccount,
  ) {
    if (widget.profiles.isEmpty) return const SizedBox.shrink();

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(102),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          const Icon(Icons.storefront, color: Colors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButton<String>(
              value: provider.activeProfileId ?? widget.profiles.first.id,
              isExpanded: true,
              underline: const SizedBox(),
              items: widget.profiles.map((profile) {
                final isLinked = provider.accounts.containsKey(profile.id);
                return DropdownMenuItem<String>(
                  value: profile.id,
                  child: Text(
                    '${profile.name} ${isLinked ? "(Connected)" : "(Unlinked)"}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                );
              }).toList(),
              onChanged: (profileId) {
                if (profileId != null) {
                  provider.switchActiveProfile(profileId);
                  _loadSupplierEmails();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnlinkedState(
    BuildContext context,
    GmailAccountProvider provider,
    PharmacyProfile profile,
  ) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 580),
          padding: const EdgeInsets.all(28.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.blue.shade200, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withAlpha(15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.mark_email_unread_rounded, size: 48, color: Colors.blue.shade700),
              ),
              const SizedBox(height: 16),
              Text(
                'Connect Gmail Account for ${profile.name}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Import purchase invoice emails permanently with a 16-character Google App Password (Zero Google Cloud setup required!).',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
              const SizedBox(height: 24),

              // Email Input Field
              TextField(
                controller: _emailCtrl,
                decoration: InputDecoration(
                  labelText: 'Gmail Address',
                  hintText: 'sahakarmedicalskpt@gmail.com',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),

              // App Password Input Field
              TextField(
                controller: _appPasswordCtrl,
                obscureText: _obscureAppPassword,
                decoration: InputDecoration(
                  labelText: 'Google App Password (16 Characters)',
                  hintText: 'xxxx xxxx xxxx xxxx',
                  prefixIcon: const Icon(Icons.key_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureAppPassword ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                    onPressed: () => setState(() => _obscureAppPassword = !_obscureAppPassword),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 20),

              // Connect Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _isConnectingAppPassword
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.flash_on_rounded),
                  label: Text(
                    _isConnectingAppPassword ? 'Verifying Gmail Credentials...' : '⚡ SAVE & CONNECT GMAIL PERMANENTLY',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  onPressed: _isConnectingAppPassword
                      ? null
                      : () => _handleConnectAppPassword(provider, profile.id),
                ),
              ),

              const SizedBox(height: 16),

              // Toggle Guide Button
              TextButton.icon(
                icon: Icon(_showGuide ? Icons.expand_less : Icons.help_outline, size: 18),
                label: Text(
                  _showGuide ? 'Hide Setup Instructions' : 'How to get a 16-character App Password (60 Seconds)',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
                onPressed: () => setState(() => _showGuide = !_showGuide),
              ),

              if (_showGuide) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '3 Simple Steps to Create a Google App Password:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                      ),
                      const SizedBox(height: 8),
                      const Text('1. Open myaccount.google.com/apppasswords in your browser.'),
                      const SizedBox(height: 4),
                      const Text('2. Type "Pharmacy ERP" as App Name and click Create.'),
                      const SizedBox(height: 4),
                      const Text('3. Copy the 16-letter password shown (e.g. abcd efgh ijkl mnop) and paste it above!'),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.open_in_new, size: 14),
                        label: const Text('Open Google App Passwords Page', style: TextStyle(fontSize: 11.5)),
                        onPressed: () => launchUrl(
                          Uri.parse('https://myaccount.google.com/apppasswords'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Frozen Header Table with Reordered Columns, Orange Full-Line Imported Highlights & Zero Overflow Constraints
  Widget _buildFrozenHeaderInvoiceTable(List<ParsedInvoiceRow> displayRows) {
    if (_isLoading && _allParsedRows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_allParsedRows.isEmpty && _error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 580),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade300, width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange.shade800),
                const SizedBox(height: 12),
                Text(
                  'Gmail Connection Notice',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange.shade900),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: Colors.orange.shade900),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry Connection'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _loadSupplierEmails(forceRefresh: true),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_allParsedRows.isEmpty) {
      return const Center(child: Text('No invoice rows extracted from Gmail.', style: TextStyle(fontSize: 15)));
    }

    const double col1Width = 360; // Wholesale Name
    const double col2Width = 180; // Invoice Date
    const double col3Width = 240; // Invoice Number
    const double col4Width = 180; // Total Amount
    const double col5Width = 600; // Attachments & Actions
    const double totalTableWidth = col1Width + col2Width + col3Width + col4Width + col5Width + 30;

    return Card(
      margin: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null && _allParsedRows.isNotEmpty)
            Container(
              color: Colors.orange.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade900, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Showing cached invoices. Live refresh notice: $_error',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade900, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => setState(() => _error = null),
                  ),
                ],
              ),
            ),

          // Table Title Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(90),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.table_chart, color: Colors.blue, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Extracted Invoices (${displayRows.length} Showing of ${_allParsedRows.length} Rows)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                if (_columnFilters.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Reset Header Filters', style: TextStyle(fontSize: 13)),
                    onPressed: () {
                      setState(() {
                        _columnFilters.clear();
                        _columnConditions.clear();
                      });
                    },
                  ),
              ],
            ),
          ),

          // Dual-Axis Scrollable Body with Fixed Header Row
          Expanded(
            child: Scrollbar(
              controller: _horizontalScrollCtrl,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _horizontalScrollCtrl,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: totalTableWidth,
                  child: Column(
                    children: [
                      // 1. FROZEN / STICKY HEADER ROW
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(70),
                          border: Border(bottom: BorderSide(color: Colors.grey.shade400, width: 2)),
                        ),
                        child: Row(
                          children: [
                            // Col 1: Wholesale Name
                            _buildInlineFilterHeaderCell(
                              title: 'WHOLESALE / SUPPLIER NAME',
                              columnKey: 'wholesale',
                              type: ImportColumnType.text,
                              width: col1Width,
                              alignCenter: false,
                            ),

                            // Col 2: Invoice Date (Centered)
                            _buildInlineFilterHeaderCell(
                              title: 'INVOICE DATE',
                              columnKey: 'date',
                              type: ImportColumnType.date,
                              hintText: 'dd/mm/yyyy',
                              width: col2Width,
                              alignCenter: true,
                            ),

                            // Col 3: Invoice Number (Centered)
                            _buildInlineFilterHeaderCell(
                              title: 'INVOICE NUMBER',
                              columnKey: 'invNo',
                              type: ImportColumnType.text,
                              width: col3Width,
                              alignCenter: true,
                            ),

                            // Col 4: Total Amount (Centered)
                            _buildInlineFilterHeaderCell(
                              title: 'TOTAL AMOUNT',
                              columnKey: 'amount',
                              type: ImportColumnType.numeric,
                              width: col4Width,
                              alignCenter: true,
                            ),

                            // Col 5: Attachments & Actions
                            Container(
                              width: col5Width,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              child: const Text(
                                'ATTACHMENTS & ACTIONS',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 2. VERTICALLY SCROLLABLE DATA ROWS
                      Expanded(
                        child: displayRows.isEmpty
                            ? const Center(
                                child: Text(
                                  'No matching rows found for active filters.',
                                  style: TextStyle(fontSize: 14, color: Colors.grey),
                                ),
                              )
                            : Scrollbar(
                                controller: _verticalScrollCtrl,
                                thumbVisibility: true,
                                child: ListView.separated(
                                  controller: _verticalScrollCtrl,
                                  itemCount: displayRows.length,
                                  separatorBuilder: (ctx, i) => Divider(height: 1, color: Colors.grey.shade300),
                                  itemBuilder: (context, index) {
                                    final row = displayRows[index];
                                    final isImported = row.isAlreadyImported;

                                    return Container(
                                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 0),
                                      decoration: BoxDecoration(
                                        color: isImported
                                            ? const Color(0xFFFFF3E0)
                                            : (index % 2 == 0 ? Colors.white : Colors.grey.shade50),
                                        border: isImported
                                            ? Border(
                                                left: BorderSide(color: Colors.orange.shade800, width: 4),
                                                bottom: BorderSide(color: Colors.orange.shade200, width: 1),
                                              )
                                            : null,
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          // Col 1: Wholesale Name + IMPORTED Tag
                                          Container(
                                            width: col1Width,
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  isImported ? Icons.check_circle_rounded : Icons.business,
                                                  size: 18,
                                                  color: isImported ? Colors.orange.shade900 : Colors.blue,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        row.wholesaleName,
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 14.5,
                                                          color: isImported ? Colors.orange.shade900 : Colors.black87,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                        maxLines: 2,
                                                      ),
                                                      if (isImported) ...[
                                                        const SizedBox(height: 2),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(
                                                              horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: Colors.orange.shade800,
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: const Text(
                                                            'IMPORTED',
                                                            style: TextStyle(
                                                              color: Colors.white,
                                                              fontSize: 9.5,
                                                              fontWeight: FontWeight.bold,
                                                              letterSpacing: 0.5,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          // Col 2: Invoice Date
                                          Container(
                                            width: col2Width,
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                            alignment: Alignment.center,
                                            child: Text(
                                              row.invoiceDate,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: isImported ? FontWeight.bold : FontWeight.w500,
                                                color: isImported ? Colors.orange.shade900 : Colors.black87,
                                              ),
                                            ),
                                          ),

                                          // Col 3: Invoice Number
                                          Container(
                                            width: col3Width,
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                            alignment: Alignment.center,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: isImported ? Colors.orange.shade100 : Colors.blue.shade50,
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: isImported ? Colors.orange.shade700 : Colors.blue.shade300,
                                                  width: isImported ? 1.5 : 1,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (isImported) ...[
                                                    Icon(Icons.check_circle_rounded,
                                                        size: 14, color: Colors.orange.shade900),
                                                    const SizedBox(width: 4),
                                                  ],
                                                  Flexible(
                                                    child: Text(
                                                      row.invoiceNumber,
                                                      textAlign: TextAlign.center,
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        color: isImported ? Colors.orange.shade900 : Colors.blue,
                                                        fontSize: 14,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),

                                          // Col 4: Total Amount
                                          Container(
                                            width: col4Width,
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                            alignment: Alignment.center,
                                            child: Text(
                                              row.totalAmount > 0
                                                  ? '₹${row.totalAmount.toStringAsFixed(2)}'
                                                  : 'Check File',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                                color: isImported
                                                    ? Colors.orange.shade900
                                                    : (row.totalAmount > 0
                                                        ? Colors.green.shade800
                                                        : Colors.grey.shade700),
                                              ),
                                            ),
                                          ),

                                          // Col 5: Attachments & Actions
                                          Container(
                                            width: col5Width,
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            child: () {
                                              final validAttachments = row.attachments.where((att) => att.filename.trim().isNotEmpty).toList();

                                              if (validAttachments.isEmpty) {
                                                return const Text('No File',
                                                    style: TextStyle(color: Colors.grey, fontSize: 13));
                                              }

                                              return Wrap(
                                                spacing: 8,
                                                runSpacing: 6,
                                                children: validAttachments.map((att) {
                                                  final lower = att.filename.toLowerCase();
                                                  final isPdf = lower.endsWith('.pdf');
                                                  final isExcel = lower.endsWith('.xlsx') || lower.endsWith('.xls') || lower.endsWith('.csv');
                                                  final cleanName = _getCleanFilename(att.filename);

                                                  Color bgColor = isPdf
                                                      ? Colors.red.shade50
                                                      : (isExcel ? Colors.green.shade50 : Colors.blue.shade50);
                                                  Color borderColor = isPdf
                                                      ? Colors.red.shade300
                                                      : (isExcel ? Colors.green.shade300 : Colors.blue.shade300);
                                                  Color textColor = isPdf
                                                      ? Colors.red.shade900
                                                      : (isExcel ? Colors.green.shade900 : Colors.blue.shade900);
                                                  IconData iconData = isPdf
                                                      ? Icons.picture_as_pdf
                                                      : (isExcel ? Icons.table_chart : Icons.insert_drive_file);

                                                  if (isImported) {
                                                    bgColor = Colors.orange.shade100;
                                                    borderColor = Colors.orange.shade600;
                                                    textColor = Colors.orange.shade900;
                                                    iconData = Icons.check_circle_rounded;
                                                  }

                                                  return InkWell(
                                                    onTap: () => _importAttachmentToPurchase(row, att),
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                      decoration: BoxDecoration(
                                                        color: bgColor,
                                                        borderRadius: BorderRadius.circular(16),
                                                        border: Border.all(color: borderColor),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(iconData, size: 16, color: textColor),
                                                          const SizedBox(width: 6),
                                                          Flexible(
                                                            child: Text(
                                                              cleanName,
                                                              style: TextStyle(
                                                                fontSize: 12.5,
                                                                fontWeight: FontWeight.bold,
                                                                color: textColor,
                                                              ),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                              );
                                            }(),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 2-Row Header Cell with Title + Funnel Icon (Row 1) and Inline Quick Filter Box (Row 2)
  Widget _buildInlineFilterHeaderCell({
    required String title,
    required String columnKey,
    required ImportColumnType type,
    String? hintText,
    required double width,
    bool alignCenter = false,
  }) {
    final isSorted = _sortColumnKey == columnKey;
    final currentCondition = _columnConditions[columnKey] ?? (type == ImportColumnType.numeric ? 'Equals' : 'Contains');

    String symbol = '=';
    if (currentCondition == 'Contains') {
      symbol = 'inc';
    } else if (currentCondition == 'Equals') {
      symbol = '=';
    } else if (currentCondition == 'Begins With') {
      symbol = 'A..';
    } else if (currentCondition == 'Ends With') {
      symbol = '..Z';
    } else if (currentCondition == 'Greater Than') {
      symbol = '>';
    } else if (currentCondition == 'Less Than') {
      symbol = '<';
    }

    return Container(
      width: width,
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: alignCenter ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Column Title + Sort Indicator + Funnel Filter Icon
          InkWell(
            onTap: () => _onSortColumn(columnKey),
            child: Row(
              mainAxisAlignment: alignCenter ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: isSorted ? Colors.blue.shade900 : Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSorted)
                  Icon(
                    _isAscending ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 13,
                    color: Colors.blue.shade900,
                  ),
                const SizedBox(width: 4),
                Icon(
                  Icons.filter_alt_outlined,
                  size: 15,
                  color: _columnFilters.containsKey(columnKey) ? Colors.blue : Colors.grey.shade600,
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // Row 2: Inline Quick Filter Input Box
          Container(
            height: 26,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _columnFilters.containsKey(columnKey) ? Colors.blue : Colors.grey.shade300,
              ),
            ),
            child: Row(
              children: [
                // Condition Symbol Button e.g. "inc" or "=" (Click to open condition popup menu)
                GestureDetector(
                  onTapDown: (details) => _showConditionMenu(details, columnKey, type),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    color: Colors.grey.shade100,
                    alignment: Alignment.center,
                    child: Text(
                      symbol,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                // TextField for inline filtering
                Expanded(
                  child: TextField(
                    textAlign: alignCenter ? TextAlign.center : TextAlign.left,
                    style: const TextStyle(fontSize: 11),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      border: InputBorder.none,
                      hintText: hintText ?? "",
                      hintStyle: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                    onChanged: (val) {
                      setState(() {
                        if (val.trim().isEmpty) {
                          _columnFilters.remove(columnKey);
                        } else {
                          _columnFilters[columnKey] = val;
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
