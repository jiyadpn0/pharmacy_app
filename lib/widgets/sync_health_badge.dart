import 'dart:async';
import 'package:flutter/material.dart';
import '../services/server_config_service.dart';
import '../services/stock_outbox_service.dart';
import '../services/lan_sync_service.dart';
import '../services/supabase_sync_service.dart';
import 'lan_terminal_discovery_dialog.dart';

class SyncHealthBadge extends StatefulWidget {
  final bool isDark;
  const SyncHealthBadge({super.key, this.isDark = false});

  @override
  State<SyncHealthBadge> createState() => _SyncHealthBadgeState();
}

class _SyncHealthBadgeState extends State<SyncHealthBadge> {
  StreamSubscription? _peerSub;

  @override
  void initState() {
    super.initState();
    _peerSub = LanSyncService.instance.peersStream.listen((_) {
      if (mounted) setState(() {});
    });
    StockOutboxService.instance.refreshCounts();
  }

  @override
  void dispose() {
    _peerSub?.cancel();
    super.dispose();
  }

  void _showHealthDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const SyncHealthDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    return ListenableBuilder(
      listenable: ServerConfigService.instance,
      builder: (context, _) {
        final config = ServerConfigService.instance;
        final bool isConnected = config.isConnected;
        final int pingMs = config.lastPingMs;
        final peersCount = LanSyncService.instance.discoveredPeers.length;

        return ValueListenableBuilder<int>(
          valueListenable: StockOutboxService.instance.pendingCount,
          builder: (context, outboxCount, __) {
            Color cloudColor;
            IconData cloudIcon;
            String cloudLabel;

            if (config.isPureCloud || config.isServerModeEnabled) {
              if (isConnected) {
                cloudColor = isDark ? const Color(0xFF34D399) : Colors.green.shade700;
                cloudIcon = Icons.cloud_done_rounded;
                cloudLabel = pingMs > 0 ? "${pingMs}ms" : "Live";
              } else if (config.status == ServerConnectionStatus.connecting) {
                cloudColor = isDark ? Colors.amberAccent : Colors.amber.shade800;
                cloudIcon = Icons.cloud_sync_rounded;
                cloudLabel = "Connecting";
              } else {
                cloudColor = isDark ? const Color(0xFFF87171) : Colors.red.shade700;
                cloudIcon = Icons.cloud_off_rounded;
                cloudLabel = "Offline";
              }
            } else {
              cloudColor = isDark ? Colors.white60 : Colors.grey.shade600;
              cloudIcon = Icons.cloud_off_rounded;
              cloudLabel = "Local";
            }

            return InkWell(
              onTap: _showHealthDialog,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  border: Border.all(
                    color: outboxCount > 0
                        ? (isDark ? Colors.orangeAccent : Colors.orange.shade400)
                        : (isDark ? const Color(0xFF334155) : Colors.grey.shade300),
                    width: outboxCount > 0 ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Terminal Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF3B82F6).withValues(alpha: 0.2) : Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isDark ? const Color(0xFF3B82F6) : Colors.indigo.shade200,
                        ),
                      ),
                      child: Text(
                        config.terminalId,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: isDark ? const Color(0xFF93C5FD) : Colors.indigo.shade900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Cloud Icon & Latency
                    Icon(cloudIcon, size: 14, color: cloudColor),
                    const SizedBox(width: 3),
                    Text(
                      cloudLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: cloudColor,
                      ),
                    ),

                    // Outbox Badge if pending items exist
                    if (outboxCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade600,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.outbox_rounded, size: 10, color: Colors.white),
                            const SizedBox(width: 3),
                            Text(
                              "$outboxCount queued",
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // LAN Peers Icon
                    if (config.isLanSyncEnabled) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.lan_rounded,
                        size: 13,
                        color: peersCount > 0
                            ? (isDark ? const Color(0xFF2DD4BF) : Colors.teal.shade700)
                            : (isDark ? Colors.white38 : Colors.grey.shade400),
                      ),
                      if (peersCount > 0) ...[
                        const SizedBox(width: 2),
                        Text(
                          "$peersCount",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: isDark ? const Color(0xFF2DD4BF) : Colors.teal.shade800,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class SyncHealthDialog extends StatefulWidget {
  const SyncHealthDialog({super.key});

  @override
  State<SyncHealthDialog> createState() => _SyncHealthDialogState();
}

class _SyncHealthDialogState extends State<SyncHealthDialog> {
  bool _isTesting = false;
  bool _isFlushing = false;
  String? _testResult;

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    final ok = await ServerConfigService.instance.checkConnectionNow();
    if (mounted) {
      setState(() {
        _isTesting = false;
        _testResult = ok
            ? "Cloud Server Active (${ServerConfigService.instance.lastPingMs}ms ping)"
            : "Cloud Unreachable: ${ServerConfigService.instance.lastErrorMessage}";
      });
    }
  }

  Future<void> _flushOutbox() async {
    setState(() => _isFlushing = true);
    try {
      final success = await StockOutboxService.instance.drainOutbox();
      await StockOutboxService.instance.refreshCounts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? "Outbox flushed successfully!" : "Outbox partially flushed or offline."),
            backgroundColor: success ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error flushing outbox: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isFlushing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ServerConfigService.instance,
      builder: (context, _) {
        final config = ServerConfigService.instance;
        final peers = LanSyncService.instance.discoveredPeers;

        return ValueListenableBuilder<int>(
          valueListenable: StockOutboxService.instance.pendingCount,
          builder: (context, outboxCount, __) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Container(
                width: 520,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.speed_rounded, color: Colors.blue.shade800, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Sync & Concurrency Health Monitor",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              "Real-time terminal status and data pipeline",
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    // Terminal Info Card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          _buildMetricItem("Terminal ID", config.terminalId, Icons.computer_rounded, Colors.indigo),
                          const SizedBox(width: 16),
                          _buildMetricItem("Branch Code", config.storeBranchId, Icons.store_rounded, Colors.blueGrey),
                          const SizedBox(width: 16),
                          _buildMetricItem("Sync Mode", config.syncMode.name.toUpperCase(), Icons.sync_alt_rounded, Colors.teal),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Cloud Health Section
                    Text("CLOUD SERVER CONNECTION", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.grey.shade700)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            config.isConnected ? Icons.check_circle_rounded : Icons.cancel_rounded,
                            color: config.isConnected ? Colors.green : Colors.red,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  config.isConnected ? "Connected to Cloud (${config.lastPingMs}ms)" : "Disconnected from Cloud",
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                Text(
                                  config.supabaseUrl,
                                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: _isTesting ? null : _testConnection,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            child: _isTesting
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text("PING", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                    if (_testResult != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _testResult!,
                        style: TextStyle(fontSize: 11, color: _testResult!.contains("Active") ? Colors.green.shade800 : Colors.red.shade800, fontWeight: FontWeight.bold),
                      ),
                    ],
                    const SizedBox(height: 14),

                    // Outbox Section
                    Text("TRANSACTIONAL OFFLINE OUTBOX", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.grey.shade700)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: outboxCount > 0 ? Colors.orange.shade50 : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: outboxCount > 0 ? Colors.orange.shade300 : Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.outbox_rounded, color: outboxCount > 0 ? Colors.orange.shade800 : Colors.grey.shade600, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  outboxCount > 0 ? "$outboxCount transactions queued for cloud upload" : "Outbox clear — all vouchers synchronized",
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: outboxCount > 0 ? Colors.orange.shade900 : Colors.black87),
                                ),
                                Text(
                                  "Automatic FIFO sync runs transparently in background",
                                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: (_isFlushing || outboxCount == 0) ? null : _flushOutbox,
                            icon: const Icon(Icons.sync, size: 14),
                            label: const Text("FLUSH NOW", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade800,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // LAN Terminals Section
                    Text("LOCAL LAN CONCURRENCY (MULTI-PC)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.grey.shade700)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lan_rounded, color: peers.isNotEmpty ? Colors.teal.shade700 : Colors.grey.shade600, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  peers.isNotEmpty ? "${peers.length} active terminal(s) discovered on subnet" : "No other terminals detected on local LAN",
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                Text(
                                  "Real-time UDP stock sync port 9999",
                                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              LanTerminalDiscoveryDialog.show(context);
                            },
                            icon: const Icon(Icons.explore_rounded, size: 14),
                            label: const Text("VIEW PEERS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.teal.shade800,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Bottom Action
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text("CLOSE"),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            SupabaseSyncService.instance.triggerInstantSync();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Cloud sync initiated transparently in background..."),
                                backgroundColor: Colors.teal,
                              ),
                            );
                          },
                          icon: const Icon(Icons.cloud_sync, size: 16),
                          label: const Text("TRIGGER CLOUD SYNC", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade900,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMetricItem(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
