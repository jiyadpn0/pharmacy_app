import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pharmacy_provider.dart';

class EditHistoryDialog {
  static void show(BuildContext context, String entryNo) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.history_edu_rounded, color: Colors.blueGrey),
            const SizedBox(width: 10),
            Text("Edit History: $entryNo", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: 600,
          height: 400,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _loadEditLogs(context, entryNo),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_user_rounded, size: 48, color: Colors.green.shade200),
                      const SizedBox(height: 16),
                      Text("No Edits Found", style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                      const Text("This invoice has never been altered.", style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                );
              }

              final logs = snapshot.data!;
              return ListView.separated(
                itemCount: logs.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final log = logs[index];
                  final editDate = DateTime.parse(log['edit_timestamp']);
                  final List<String> diffs = (log['_diffs'] as List<String>?) ?? [];
                  final List<dynamic> oldItems = (log['_parsed_old_items'] as List<dynamic>?) ?? [];

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200)
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Edited on: ${editDate.day}/${editDate.month}/${editDate.year} at ${editDate.hour}:${editDate.minute.toString().padLeft(2, '0')}",
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                            ),
                            Text(
                              "Old Total: ₹${log['previous_grand_total']}",
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text("Reason: ${log['reason_for_edit']}", style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13)),
                        const SizedBox(height: 8),
                        if (diffs.isNotEmpty) ...[
                          const Text("Edits / Changes:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                          const SizedBox(height: 4),
                          ...diffs.map((diffText) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("• ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13)),
                                Expanded(
                                  child: Text(
                                    diffText,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
                                  ),
                                ),
                              ],
                            ),
                          )),
                        ] else ...[
                          const Text("Previous Items Snapshot:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                          const SizedBox(height: 4),
                          ...oldItems.map((item) {
                            final name = item['name'] ?? item['productName'] ?? '';
                            final batch = item['batch'] ?? '';
                            final qty = item['qty'] ?? 0;
                            final total = item['total'] ?? '';
                            return Text(
                              "• ${qty}x $name (Batch: $batch) - ₹$total",
                              style: const TextStyle(fontSize: 12),
                            );
                          }),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CLOSE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  static Future<List<Map<String, dynamic>>> _loadEditLogs(BuildContext context, String entryNo) async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final rawLogs = await provider.getEditHistory(entryNo);
    if (rawLogs.isEmpty) return [];

    final currentItems = await provider.getCurrentInvoiceItems(entryNo);

    List<Map<String, dynamic>> processed = [];

    for (int i = 0; i < rawLogs.length; i++) {
      final log = Map<String, dynamic>.from(rawLogs[i]);

      List<dynamic> oldItems = [];
      try {
        if (log['previous_items_json'] != null) {
          oldItems = jsonDecode(log['previous_items_json']);
        }
      } catch (_) {}

      List<dynamic> newItems = [];
      if (log['new_items_json'] != null && log['new_items_json'].toString().trim().isNotEmpty) {
        try {
          newItems = jsonDecode(log['new_items_json']);
        } catch (_) {}
      } else if (i > 0 && rawLogs[i - 1]['previous_items_json'] != null) {
        try {
          newItems = jsonDecode(rawLogs[i - 1]['previous_items_json']);
        } catch (_) {}
      } else {
        newItems = currentItems;
      }

      log['_diffs'] = generateDiffSummary(oldItems, newItems);
      log['_parsed_old_items'] = oldItems;
      processed.add(log);
    }

    return processed;
  }

  static List<String> generateDiffSummary(List<dynamic> oldItemsList, List<dynamic> newItemsList) {
    List<String> diffs = [];

    String getName(dynamic item) {
      if (item is! Map) return '';
      return (item['name'] ?? item['productName'] ?? item['product_name'] ?? '').toString().trim();
    }

    String getBatch(dynamic item) {
      if (item is! Map) return '';
      return (item['batch'] ?? '').toString().trim();
    }

    num getQty(dynamic item) {
      if (item is! Map) return 0;
      final q = item['qty'];
      if (q is num) return q;
      return num.tryParse(q?.toString() ?? '0') ?? 0;
    }

    String getPack(dynamic item) {
      if (item is! Map) return '';
      final p = item['pack'] ?? item['packSize'] ?? item['pack_size'];
      return (p ?? '').toString().trim();
    }

    num getRate(dynamic item) {
      if (item is! Map) return 0;
      final r = item['s_rate'] ?? item['p_rate'] ?? item['rate'] ?? item['mrp'];
      if (r is num) return r;
      return num.tryParse(r?.toString() ?? '0') ?? 0;
    }

    final oldList = oldItemsList.whereType<Map<String, dynamic>>().toList();
    final newList = newItemsList.whereType<Map<String, dynamic>>().toList();

    Set<int> matchedOld = {};
    Set<int> matchedNew = {};

    // 1. First Pass: Match by exact name
    for (int i = 0; i < oldList.length; i++) {
      final oldName = getName(oldList[i]);
      if (oldName.isEmpty) continue;

      for (int j = 0; j < newList.length; j++) {
        if (matchedNew.contains(j)) continue;
        final newName = getName(newList[j]);

        if (oldName.toLowerCase() == newName.toLowerCase()) {
          matchedOld.add(i);
          matchedNew.add(j);

          final oQty = getQty(oldList[i]);
          final nQty = getQty(newList[j]);
          final oPack = getPack(oldList[i]);
          final nPack = getPack(newList[j]);
          final oBatch = getBatch(oldList[i]);
          final nBatch = getBatch(newList[j]);
          final oRate = getRate(oldList[i]);
          final nRate = getRate(newList[j]);

          if (oPack.isNotEmpty && nPack.isNotEmpty && oPack.toLowerCase() != nPack.toLowerCase()) {
            diffs.add("$oldName pack $oPack change to pack $nPack");
          }

          if (oQty != nQty) {
            diffs.add("$oldName qty $oQty changed to $nQty qty");
          }

          if (oBatch.isNotEmpty && nBatch.isNotEmpty && oBatch.toLowerCase() != nBatch.toLowerCase()) {
            diffs.add("$oldName batch $oBatch change to batch $nBatch");
          }

          if (oRate != nRate && oRate > 0 && nRate > 0) {
            diffs.add("$oldName rate ₹$oRate change to ₹$nRate");
          }
          break;
        }
      }
    }

    // 2. Second Pass: Unmatched position substitution (Product Name Changed)
    for (int i = 0; i < oldList.length; i++) {
      if (matchedOld.contains(i)) continue;
      final oldName = getName(oldList[i]);
      if (oldName.isEmpty) continue;

      if (i < newList.length && !matchedNew.contains(i)) {
        final newName = getName(newList[i]);
        if (newName.isNotEmpty && oldName.toLowerCase() != newName.toLowerCase()) {
          matchedOld.add(i);
          matchedNew.add(i);

          diffs.add("$oldName change to $newName");

          final oQty = getQty(oldList[i]);
          final nQty = getQty(newList[i]);
          if (oQty != nQty) {
            diffs.add("$newName qty $oQty changed to $nQty qty");
          }

          final oPack = getPack(oldList[i]);
          final nPack = getPack(newList[i]);
          if (oPack.isNotEmpty && nPack.isNotEmpty && oPack.toLowerCase() != nPack.toLowerCase()) {
            diffs.add("$newName pack $oPack change to pack $nPack");
          }
          continue;
        }
      }

      for (int j = 0; j < newList.length; j++) {
        if (matchedNew.contains(j)) continue;
        final newName = getName(newList[j]);
        if (newName.isNotEmpty && oldName.toLowerCase() != newName.toLowerCase()) {
          matchedOld.add(i);
          matchedNew.add(j);

          diffs.add("$oldName change to $newName");

          final oQty = getQty(oldList[i]);
          final nQty = getQty(newList[j]);
          if (oQty != nQty) {
            diffs.add("$newName qty $oQty changed to $nQty qty");
          }

          final oPack = getPack(oldList[i]);
          final nPack = getPack(newList[i]);
          if (oPack.isNotEmpty && nPack.isNotEmpty && oPack.toLowerCase() != nPack.toLowerCase()) {
            diffs.add("$newName pack $oPack change to pack $nPack");
          }
          break;
        }
      }
    }

    // 3. Removed items
    for (int i = 0; i < oldList.length; i++) {
      if (!matchedOld.contains(i)) {
        final oldName = getName(oldList[i]);
        final oQty = getQty(oldList[i]);
        if (oldName.isNotEmpty) {
          diffs.add("$oldName (qty $oQty) removed");
        }
      }
    }

    // 4. Unmatched new items -> Added
    for (int j = 0; j < newList.length; j++) {
      if (!matchedNew.contains(j)) {
        final newName = getName(newList[j]);
        final nQty = getQty(newList[j]);
        if (newName.isNotEmpty) {
          diffs.add("$newName added ($nQty qty)");
        }
      }
    }

    return diffs;
  }
}
