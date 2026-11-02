import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../database/db_helper.dart';

class FdaAuditLogScreen extends StatefulWidget {
  const FdaAuditLogScreen({super.key});

  @override
  State<FdaAuditLogScreen> createState() => _FdaAuditLogScreenState();
}

class _FdaAuditLogScreenState extends State<FdaAuditLogScreen> {
  List<Map<String, dynamic>> _logs = [];
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchAuditLogs();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchAuditLogs() async {
    setState(() => _isLoading = true);
    final db = await DbHelper.instance.database;

    try {
      final rows = await db.query(
        'system_audit_logs',
        orderBy: 'id DESC',
        limit: 500,
      );

      setState(() {
        _logs = List<Map<String, dynamic>>.from(rows);
      });
    } catch (e) {
      debugPrint("Error loading audit logs: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredLogs {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return _logs;

    return _logs.where((l) {
      final action = (l['action_type']?.toString() ?? '').toLowerCase();
      final desc = (l['description']?.toString() ?? '').toLowerCase();
      final user = (l['user_id']?.toString() ?? '').toLowerCase();

      return action.contains(query) || desc.contains(query) || user.contains(query);
    }).toList();
  }

  void _printAuditLogPdf() async {
    final activeLogs = _filteredLogs;
    if (activeLogs.isEmpty) return;

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context ctx) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("FDA & REGULATORY SYSTEM AUDIT TRAIL LOG", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text("Date: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}", style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ["ID", "Timestamp", "Action", "Description", "User"],
            data: activeLogs.map((l) => [
              l['id']?.toString() ?? '',
              l['timestamp']?.toString() ?? '',
              l['action_type']?.toString() ?? '',
              l['description']?.toString() ?? '',
              l['user_id']?.toString() ?? 'Admin',
            ]).toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: "FDA_Audit_Trail_Log.pdf",
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1E2638) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("FDA & Statutory Audit Trail Inspector", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded),
            tooltip: "Export Audit Log PDF",
            onPressed: _printAuditLogPdf,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: "Refresh Logs",
            onPressed: _fetchAuditLogs,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Search Control Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 20, color: Colors.blueGrey),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: const InputDecoration(
                        hintText: "Search audit logs by action, description, or user ID...",
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  Text(
                    "Total Logs: ${_filteredLogs.length}",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredLogs.isEmpty
                      ? const Center(child: Text("No statutory audit logs found.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)))
                      : Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: ListView.separated(
                            itemCount: _filteredLogs.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final l = _filteredLogs[i];
                              final action = l['action_type']?.toString() ?? 'EVENT';
                              final desc = l['description']?.toString() ?? '';
                              final ts = l['timestamp']?.toString() ?? '';
                              final user = l['user_id']?.toString() ?? 'Admin';

                              return ListTile(
                                dense: true,
                                leading: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.blueGrey.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(action, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                ),
                                title: Text(desc, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                subtitle: Text("User: $user | Time: $ts", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
