import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import '../providers/pharmacy_provider.dart';
import '../services/delta_sync_service.dart';
import '../services/server_config_service.dart';
import '../services/supabase_sync_service.dart';

class LiveSystemCountsDialog extends StatefulWidget {
  const LiveSystemCountsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => const LiveSystemCountsDialog(),
    );
  }

  @override
  State<LiveSystemCountsDialog> createState() => _LiveSystemCountsDialogState();
}

class _LiveSystemCountsDialogState extends State<LiveSystemCountsDialog> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _fetchCounts();
  }

  Future<int> _fetchLocalCount(Database db, String query) async {
    try {
      final res = await db.rawQuery(query).timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () => [],
      );
      if (res.isNotEmpty) {
        return res.first['cnt'] as int? ?? 0;
      }
    } catch (e) {
      debugPrint('Error fetching local count ($query): $e');
    }
    return 0;
  }

  Future<int> _fetchServerCount(String endpoint, {String? queryFilter}) async {
    try {
      final config = ServerConfigService.instance;
      if (!config.isConnected || config.supabaseUrl.isEmpty || config.supabaseAnonKey.isEmpty) return -1;

      final cleanUrl = ServerConfigService.cleanServerUrl(config.supabaseUrl);
      final headers = {
        'apikey': config.supabaseAnonKey.trim(),
        'Authorization': 'Bearer ${config.supabaseAnonKey.trim()}',
      };

      final filterParam = (queryFilter != null && queryFilter.isNotEmpty) ? '&$queryFilter' : '';
      final pkCol = (endpoint == 'sales_invoices' || endpoint == 'purchase_entries' || endpoint == 'sales_return_invoices' || endpoint == 'purchase_return_entries' || endpoint == 'stock_adjustments') ? 'entry_no' : 'id';
      final exactHeaders = Map<String, String>.from(headers)..['Prefer'] = 'count=exact';
      final exactUri = Uri.parse('$cleanUrl/rest/v1/$endpoint?select=$pkCol$filterParam&limit=1');
      var res = await http.get(exactUri, headers: exactHeaders).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200 || res.statusCode == 206) {
        final contentRange = res.headers['content-range'] ?? '';
        if (contentRange.contains('/')) {
          final totalStr = contentRange.split('/').last.trim();
          final cnt = int.tryParse(totalStr);
          if (cnt != null && cnt >= 0) return cnt;
        }
      }

      final fallbackHeaders = Map<String, String>.from(headers)
        ..['Prefer'] = 'count=estimated'
        ..['Range'] = '0-0';
      final fallbackUri = Uri.parse('$cleanUrl/rest/v1/$endpoint?select=$pkCol');
      final fallbackRes = await http.get(fallbackUri, headers: fallbackHeaders).timeout(const Duration(seconds: 4));
      if (fallbackRes.statusCode == 200 || fallbackRes.statusCode == 206) {
        final contentRange = fallbackRes.headers['content-range'] ?? '';
        if (contentRange.contains('/')) {
          final totalStr = contentRange.split('/').last.trim();
          final cnt = int.tryParse(totalStr);
          if (cnt != null && cnt >= 0) return cnt;
        }
      }
    } catch (_) {}
    return -1;
  }

  Future<void> _fetchCounts() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // 1. Immediately catch up any missing cloud transactions into local SQLite before counting
      try {
        await SupabaseSyncService.instance.syncAllPendingCloudRecords().timeout(const Duration(seconds: 2));
      } catch (_) {}
      unawaited(SupabaseSyncService.instance.reconcileCloudSyncedEntries().catchError((_) {}));
      unawaited(DeltaSyncService.instance.triggerBackgroundSync());
      final db = await DbHelper.instance.database;

      final localCounts = await Future.wait([
        _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM product_master'),
        _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM stock_batches'),
        _fetchLocalCount(db, "SELECT COUNT(DISTINCT CASE WHEN instr(entry_no, '_') > 0 THEN substr(entry_no, instr(entry_no, '_') + 1) ELSE entry_no END) as cnt FROM sales_invoices WHERE (customer_acc IS NULL OR customer_acc != 'Special Order') AND (entry_no IS NOT NULL AND entry_no != '') AND (is_deleted = 1 OR grand_total > 0 OR sub_total > 0 OR total_amount > 0)"),
        _fetchLocalCount(db, "SELECT COUNT(DISTINCT CASE WHEN instr(entry_no, '_') > 0 THEN substr(entry_no, instr(entry_no, '_') + 1) ELSE entry_no END) as cnt FROM purchase_entries WHERE (entry_no IS NOT NULL AND entry_no != '') AND (is_deleted = 1 OR grand_total > 0 OR inv_total > 0 OR sub_total > 0)"),
        _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM sales_return_invoices WHERE (is_deleted = 0 OR is_deleted IS NULL)'),
        _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM purchase_return_entries WHERE (is_deleted = 0 OR is_deleted IS NULL)'),
        _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM stock_adjustments'),
        _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM stock_write_offs'),
        _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM patients'),
        _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM suppliers'),
        _fetchLocalCount(db, 'SELECT COUNT(*) as cnt FROM doctors'),
      ]).timeout(
        const Duration(seconds: 4),
        onTimeout: () => List.filled(11, 0),
      );

      final serverCounts = await Future.wait([
        _fetchServerCount('product_master'),
        _fetchServerCount('stock_batches'),
        _fetchServerCount('sales_invoices', queryFilter: 'entry_no=not.is.null'),
        _fetchServerCount('purchase_entries', queryFilter: 'entry_no=not.is.null'),
        _fetchServerCount('sales_return_invoices'),
        _fetchServerCount('purchase_return_entries'),
        _fetchServerCount('stock_adjustments'),
        _fetchServerCount('stock_write_offs'),
        _fetchServerCount('patients'),
        _fetchServerCount('suppliers'),
        _fetchServerCount('doctors'),
      ]).timeout(
        const Duration(seconds: 8),
        onTimeout: () => List.filled(11, -1),
      );

      _items = [
        {'catKey': 'product_master', 'title': 'Registered Products (Product Master)', 'icon': Icons.inventory_2_rounded, 'local': localCounts[0], 'server': serverCounts[0], 'color': Colors.blue},
        {'catKey': 'stock_batches', 'title': 'Active Stock Batches (Inventory)', 'icon': Icons.layers_rounded, 'local': localCounts[1], 'server': serverCounts[1], 'color': Colors.indigo},
        {'catKey': 'sales_invoices', 'title': 'Sales Invoices & Counter Bills', 'icon': Icons.point_of_sale_rounded, 'local': localCounts[2], 'server': serverCounts[2], 'color': Colors.green},
        {'catKey': 'purchase_entries', 'title': 'Purchase Inward Entries', 'icon': Icons.shopping_bag_rounded, 'local': localCounts[3], 'server': serverCounts[3], 'color': Colors.teal},
        {'catKey': 'sales_return_invoices', 'title': 'Sales Return Receipts', 'icon': Icons.assignment_return_rounded, 'local': localCounts[4], 'server': serverCounts[4], 'color': Colors.amber},
        {'catKey': 'purchase_return_entries', 'title': 'Purchase Return Entries', 'icon': Icons.unarchive_rounded, 'local': localCounts[5], 'server': serverCounts[5], 'color': Colors.orange},
        {'catKey': 'stock_adjustments', 'title': 'Stock Adjustments', 'icon': Icons.tune_rounded, 'local': localCounts[6], 'server': serverCounts[6], 'color': Colors.cyan},
        {'catKey': 'stock_write_offs', 'title': 'Damage & Write-off Entries', 'icon': Icons.remove_shopping_cart_rounded, 'local': localCounts[7], 'server': serverCounts[7], 'color': Colors.red},
        {'catKey': 'patients', 'title': 'Customers & Patients Registry', 'icon': Icons.people_alt_rounded, 'local': localCounts[8], 'server': serverCounts[8], 'color': Colors.purple},
        {'catKey': 'suppliers', 'title': 'Wholesalers & Suppliers', 'icon': Icons.local_shipping_rounded, 'local': localCounts[9], 'server': serverCounts[9], 'color': Colors.deepOrange},
        {'catKey': 'doctors', 'title': 'Doctors Profiles', 'icon': Icons.medical_services_rounded, 'local': localCounts[10], 'server': serverCounts[10], 'color': Colors.pink},
      ];
    } catch (e) {
      debugPrint("Error fetching counts: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##,###');

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.cloud_sync_rounded, color: Colors.teal.shade700, size: 26),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('LIVE SYSTEM DATA MONITOR', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              Text('Instant comparison: Local PC Database vs Supabase Cloud', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _isLoading ? null : _fetchCounts,
            tooltip: "Refresh Live Counts",
          ),
        ],
      ),
      content: AnimatedBuilder(
        animation: SupabaseSyncService.instance,
        builder: (context, _) {
          final syncService = SupabaseSyncService.instance;
          return SizedBox(
            width: 700,
            height: 520,
            child: Column(
              children: [
                if (syncService.isSyncing)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade300, width: 1.2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                syncService.syncStatusMessage.isNotEmpty
                                    ? syncService.syncStatusMessage
                                    : 'Synchronizing with Cloud Server...',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.blue.shade900,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${(syncService.syncProgress * 100).toInt()}%',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                color: Colors.blue.shade900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: syncService.syncProgress > 0 ? syncService.syncProgress : null,
                            backgroundColor: Colors.blue.shade100,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade700),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text("Pinging Supabase & querying local PC database...", style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (context, idx) {
                            final it = _items[idx];
                            final int local = it['local'] as int;
                            final int server = it['server'] as int;
                            final bool isSynced = server >= 0 && local == server;
                            final bool isCloudHigher = server > local;
                            final bool isLocalHigher = local > server && server >= 0;

                            Color statusColor = Colors.green;
                            String statusLabel = '100% IN SYNC';
                            if (server < 0) {
                              statusColor = Colors.grey;
                              statusLabel = 'OFFLINE / TIMEOUT';
                            } else if (isLocalHigher) {
                              statusColor = Colors.orange.shade800;
                              statusLabel = 'PC AHEAD (+${local - server})';
                            } else if (isCloudHigher) {
                              statusColor = Colors.blue.shade800;
                              statusLabel = 'CLOUD AHEAD (+${server - local})';
                            }

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSynced ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSynced ? Colors.green.shade200 : Colors.amber.shade300,
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(it['icon'] as IconData, color: it['color'] as Color, size: 22),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(it['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                        const SizedBox(height: 2),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: statusColor.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            const Text('LOCAL PC', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                            Text(fmt.format(local), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.black87)),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            const Text('CLOUD SERVER', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                            Text(server >= 0 ? fmt.format(server) : 'Timeout', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: server >= 0 ? (server == local ? Colors.green.shade800 : Colors.blue.shade800) : Colors.grey)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
      actions: [
        AnimatedBuilder(
          animation: SupabaseSyncService.instance,
          builder: (context, _) {
            final syncService = SupabaseSyncService.instance;
            final isBusy = syncService.isSyncing;
            return Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: isBusy
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('⚡ Pushing all local records (Catalog, Stock Batches & Invoices) to Supabase Cloud...'),
                              duration: Duration(seconds: 4),
                            ),
                          );
                          final success = await SupabaseSyncService.instance.forcePushAllData(forceFull: false);
                          await _fetchCounts();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(success ? '🎉 All Local Data Pushed & 100% Synced to Cloud!' : '⚠️ Sync finished with some notices.'),
                              backgroundColor: success ? Colors.green.shade800 : Colors.amber.shade800,
                            ),
                          );
                        },
                  icon: isBusy
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.cloud_upload_rounded, size: 16),
                  label: Text(
                    isBusy ? 'SYNCING TO CLOUD...' : 'PUSH ALL LOCAL DATA TO CLOUD',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: isBusy
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final provider = Provider.of<PharmacyProvider>(context, listen: false);
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('📥 Pulling full data from Cloud into this PC...'),
                              duration: Duration(seconds: 4),
                            ),
                          );
                          final success = await SupabaseSyncService.instance.syncAllPendingData(
                            forceFull: true,
                            isExportMode: false,
                            isManualTransfer: true,
                          );
                          if (success) {
                            await provider.loadFromDatabase();
                          }
                          await _fetchCounts();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(success ? '🎉 Downloaded full data from Cloud into this PC!' : '⚠️ Download finished with notices.'),
                              backgroundColor: Colors.teal.shade800,
                            ),
                          );
                        },
                  icon: const Icon(Icons.cloud_download_rounded, size: 16),
                  label: const Text('PULL FROM CLOUD TO THIS PC', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CLOSE', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
