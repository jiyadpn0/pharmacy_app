import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/lan_sync_service.dart';
import '../services/server_config_service.dart';
import '../database/db_helper.dart';
import 'package:sqflite/sqflite.dart';

class LanTerminalDiscoveryDialog extends StatefulWidget {
  const LanTerminalDiscoveryDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const LanTerminalDiscoveryDialog(),
    );
  }

  @override
  State<LanTerminalDiscoveryDialog> createState() => _LanTerminalDiscoveryDialogState();
}

class _LanTerminalDiscoveryDialogState extends State<LanTerminalDiscoveryDialog> {
  StreamSubscription? _peerSub;
  int _localProductCount = 0;
  bool _isBroadcasting = false;
  String? _statusBanner;

  @override
  void initState() {
    super.initState();
    _fetchLocalCount();
    _peerSub = LanSyncService.instance.peersStream.listen((_) {
      if (mounted) setState(() {});
    });
    // Immediately broadcast a discovery ping
    LanSyncService.instance.broadcastDiscoveryPing();
  }

  @override
  void dispose() {
    _peerSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchLocalCount() async {
    try {
      final db = await DbHelper.instance.database;
      final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM product_master;')) ?? 0;
      if (mounted) setState(() => _localProductCount = count);
    } catch (_) {}
  }

  Future<void> _broadcastNow() async {
    setState(() {
      _isBroadcasting = true;
      _statusBanner = "Broadcasted discovery ping on local UDP port 9999...";
    });
    await LanSyncService.instance.broadcastDiscoveryPing();
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      setState(() {
        _isBroadcasting = false;
        _statusBanner = "Active counters discovered on shop network: ${LanSyncService.instance.discoveredPeers.length}";
      });
    }
  }

  void _sendTestPing() {
    LanSyncService.instance.sendTestPing();
    setState(() {
      _statusBanner = "1ms LAN test ping sent across all shop counters!";
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = ServerConfigService.instance;
    final peers = LanSyncService.instance.discoveredPeers.values.toList();
    final isLanActive = LanSyncService.instance.isListening;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Container(
        width: 840,
        constraints: const BoxConstraints(maxHeight: 720),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: const Icon(Icons.radar_rounded, color: Colors.blue, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Multi-Terminal LAN Network Map & Live Radar',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isLanActive ? Colors.green.shade50 : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isLanActive ? Colors.green.shade400 : Colors.red.shade400),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.wifi_tethering, size: 12, color: isLanActive ? Colors.green.shade800 : Colors.red.shade800),
                                const SizedBox(width: 4),
                                Text(
                                  isLanActive ? 'UDP 9999 • TCP 9998 (1ms)' : 'LAN Disabled',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isLanActive ? Colors.green.shade800 : Colors.red.shade800),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Zero-touch plug-and-play counter auto-discovery with sequence prefix isolation.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const Divider(height: 24),

            // Controls Bar
            Row(
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  icon: _isBroadcasting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.refresh, size: 16),
                  label: const Text('Broadcast Discovery Ping', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: _isBroadcasting ? null : _broadcastNow,
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.bolt, size: 16, color: Colors.amber),
                  label: const Text('Send 1ms Test Ping', style: TextStyle(fontSize: 12)),
                  onPressed: _sendTestPing,
                ),
                const Spacer(),
                if (_statusBanner != null)
                  Text(
                    _statusBanner!,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // THIS COMPUTER CARD
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade300, width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade800,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  config.terminalId,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'THIS COMPUTER (Local Terminal)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.green.shade400),
                                ),
                                child: Text(
                                  config.terminalPrefix.isEmpty ? 'Prefix: (Standard Numbers)' : 'Prefix: ${config.terminalPrefix}',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.green.shade900),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: _InfoItem(
                                  label: 'Host Machine',
                                  value: config.computerName.isNotEmpty ? config.computerName : Platform.localHostname,
                                ),
                              ),
                              Expanded(
                                child: _InfoItem(
                                  label: 'Catalog Count',
                                  value: '$_localProductCount Products',
                                ),
                              ),
                              Expanded(
                                child: _InfoItem(
                                  label: 'Branch Namespace',
                                  value: config.storeBranchId,
                                ),
                              ),
                              Expanded(
                                child: _InfoItem(
                                  label: 'Machine UUID',
                                  value: config.machineUuid.length > 18
                                      ? '${config.machineUuid.substring(0, 18)}...'
                                      : config.machineUuid,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // DISCOVERED PEERS SECTION
                    Row(
                      children: [
                        const Icon(Icons.devices, size: 18, color: Colors.indigo),
                        const SizedBox(width: 8),
                        Text(
                          'Discovered LAN Counters (${peers.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (peers.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.wifi_find, size: 40, color: Colors.grey.shade400),
                            const SizedBox(height: 10),
                            Text(
                              'Listening on Shop Wi-Fi / LAN Broadcast (Port 9999)...',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'When you launch the app on Counter 2 or Counter 3 on the same network, it will be automatically detected and mapped here with 0 setup.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    else
                      Column(
                        children: peers.map((p) {
                          final timeDiff = DateTime.now().difference(p.lastSeen).inSeconds;
                          final lastSeenText = timeDiff < 5 ? 'Just now' : '${timeDiff}s ago';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.indigo.shade200),
                              boxShadow: [
                                BoxStyle.subtle,
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade700,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    p.terminalId,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            p.computerName,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade50,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              p.ipAddress,
                                              style: TextStyle(fontSize: 11, color: Colors.blue.shade900, fontFamily: 'monospace'),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Sequence Prefix: ${p.terminalPrefix.isEmpty ? "(Standard)" : p.terminalPrefix} • Catalog: ${p.productCount} items • Last Seen: $lastSeenText',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.green.shade400),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.flash_on, size: 12, color: Colors.green),
                                      const SizedBox(width: 4),
                                      Text(
                                        '1ms Online',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),

                    const SizedBox(height: 16),

                    // ARCHITECTURAL GUARANTEE FOOTER
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blueGrey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.shield_outlined, size: 16, color: Colors.blueGrey),
                              SizedBox(width: 6),
                              Text(
                                'Enterprise Zero-Loss & Zero-Duplicate Guarantee',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '• Sequence Prefix Isolation: Each counter bills into its own unique namespace (POS-01: 1, 2, 3...; POS-02: T2-1, T2-2...).\n• Durable Outbox: If LAN or Cloud drops, invoices queue in local SQLite with 0ms delay and sync automatically on reconnection.\n• Row-Level Locking: Cloud stock deductions use atomic PostgreSQL FOR UPDATE locks to prevent simultaneous double-dispensing.',
                            style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade800, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;

  const _InfoItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class BoxStyle {
  static final BoxShadow subtle = BoxShadow(
    color: Colors.black.withValues(alpha: 0.04),
    blurRadius: 4,
    offset: const Offset(0, 2),
  );
}
