import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'server_config_service.dart';
import '../database/db_helper.dart';

/// Represents an active POS counter discovered on the local Wi-Fi or Ethernet network
class DiscoveredTerminalPeer {
  final String terminalId;
  final String terminalPrefix;
  final String machineUuid;
  final String computerName;
  final String ipAddress;
  final int productCount;
  final DateTime lastSeen;
  final bool isSelf;

  DiscoveredTerminalPeer({
    required this.terminalId,
    required this.terminalPrefix,
    required this.machineUuid,
    required this.computerName,
    required this.ipAddress,
    required this.productCount,
    required this.lastSeen,
    this.isSelf = false,
  });

  Map<String, dynamic> toJson() => {
    'terminal_id': terminalId,
    'terminal_prefix': terminalPrefix,
    'machine_uuid': machineUuid,
    'computer_name': computerName,
    'ip_address': ipAddress,
    'product_count': productCount,
    'last_seen': lastSeen.toIso8601String(),
    'is_self': isSelf,
  };
}

/// Ultra-low latency LAN Sync & Auto-Discovery Engine combining 1ms UDP Broadcasts (Port 9999)
/// and Direct TCP Socket Streams (Port 9998) for 1–3ms PC-to-PC shop network sync and plug-and-play terminal discovery.
class LanSyncService {
  static final LanSyncService instance = LanSyncService._internal();
  LanSyncService._internal();

  RawDatagramSocket? _socket;
  ServerSocket? _tcpServer;
  final List<Socket> _connectedClients = [];

  static const int udpPort = 9999;
  static const int tcpPort = 9998;

  bool _isListening = false;
  bool _isInitializing = false;
  final String _deviceId = Platform.localHostname.toLowerCase().trim();
  final List<void Function(Map<String, dynamic> event)> _listeners = [];
  final LinkedHashSet<String> _processedEvents = LinkedHashSet<String>();

  // Active Peer Reset Locks: Map of terminal_id -> lock expiry timestamp
  final Map<String, DateTime> _peerResetLocks = {};

  bool isTerminalInResetLock(String terminalId) {
    final clean = terminalId.toLowerCase().trim();
    final expiry = _peerResetLocks[clean];
    if (expiry == null) return false;
    if (DateTime.now().isAfter(expiry)) {
      _peerResetLocks.remove(clean);
      return false;
    }
    return true;
  }

  /// Broadcasts a network-wide wipe lock so all peers pause syncing to this machine
  void broadcastResetLock({int durationSeconds = 60}) {
    broadcastEvent('LAN_RESET_LOCK', {
      'terminal_id': ServerConfigService.instance.terminalId,
      'duration_seconds': durationSeconds,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Broadcasts a network-wide wipe release so peers resume normal sync
  void broadcastResetRelease() {
    broadcastEvent('LAN_RESET_RELEASE', {
      'terminal_id': ServerConfigService.instance.terminalId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // Plug-and-Play Peer Discovery Registry
  final Map<String, DiscoveredTerminalPeer> _discoveredPeers = {};
  final StreamController<List<DiscoveredTerminalPeer>> _peersStreamCtrl = StreamController<List<DiscoveredTerminalPeer>>.broadcast();
  Timer? _discoveryTimer;

  bool get isListening => _isListening;
  Map<String, DiscoveredTerminalPeer> get discoveredPeers => Map.unmodifiable(_discoveredPeers);
  Stream<List<DiscoveredTerminalPeer>> get peersStream => _peersStreamCtrl.stream;

  /// Starts periodic LAN auto-discovery broadcast every 20 seconds
  void startAutoDiscovery() {
    if (_discoveryTimer != null && _discoveryTimer!.isActive) return;

    // Send immediate announcement
    unawaited(broadcastDiscoveryPing());

    _discoveryTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(broadcastDiscoveryPing());
      _pruneStalePeers();
    });
    debugPrint("⚡ [LanSyncService]: Plug-and-Play Terminal Auto-Discovery armed (Port $udpPort).");
  }

  /// Prunes peers not seen in the last 60 seconds
  void _pruneStalePeers() {
    final now = DateTime.now();
    final toRemove = <String>[];
    _discoveredPeers.forEach((key, peer) {
      if (!peer.isSelf && now.difference(peer.lastSeen).inSeconds > 60) {
        toRemove.add(key);
      }
    });

    if (toRemove.isNotEmpty) {
      for (final k in toRemove) {
        _discoveredPeers.remove(k);
      }
      _emitPeers();
    }
  }

  void _emitPeers() {
    if (!_peersStreamCtrl.isClosed) {
      _peersStreamCtrl.add(_discoveredPeers.values.toList());
    }
  }

  /// Broadcasts a lightweight discovery ping announcing terminal ID, sequence prefix, and product count
  Future<void> broadcastDiscoveryPing({bool isPong = false}) async {
    if (!ServerConfigService.instance.isLanSyncEnabled) return;

    int pCount = 0;
    try {
      final db = await DbHelper.instance.database;
      pCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM product_master;')) ?? 0;
    } catch (_) {}

    final config = ServerConfigService.instance;
    final action = isPong ? 'LAN_DISCOVERY_PONG' : 'LAN_DISCOVERY_PING';

    final payload = {
      'terminal_id': config.terminalId,
      'terminal_prefix': config.terminalPrefix,
      'machine_uuid': config.machineUuid,
      'computer_name': config.computerName.isNotEmpty ? config.computerName : Platform.localHostname,
      'product_count': pCount,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    broadcastEvent(action, payload);
  }

  /// Sends a 1ms test broadcast across all counters to verify real-time LAN communication
  void sendTestPing() {
    final config = ServerConfigService.instance;
    broadcastEvent('LAN_TEST_PING', {
      'from_terminal': config.terminalId,
      'computer_name': config.computerName.isNotEmpty ? config.computerName : Platform.localHostname,
      'sent_at': DateTime.now().toIso8601String(),
    });
  }

  /// Calculates the next available terminal ID (e.g. POS-02, POS-03) not currently taken by peers
  String calculateNextAvailableTerminalId() {
    final takenNumbers = <int>{};

    // Current PC number
    final curNum = int.tryParse(ServerConfigService.instance.terminalId.replaceAll(RegExp(r'\D'), ''));
    if (curNum != null) takenNumbers.add(curNum);

    // Peer numbers
    for (final peer in _discoveredPeers.values) {
      final pNum = int.tryParse(peer.terminalId.replaceAll(RegExp(r'\D'), ''));
      if (pNum != null) takenNumbers.add(pNum);
    }

    int next = 1;
    while (takenNumbers.contains(next)) {
      next++;
    }

    return next < 10 ? 'POS-0$next' : 'POS-$next';
  }

  /// Issue 5.2: LAN + Cloud Deduplication Guard
  void handleIncomingEvent(String eventId, Function() applyAction) {
    final cleanId = eventId.trim();
    if (cleanId.isEmpty) {
      applyAction();
      return;
    }
    if (_processedEvents.contains(cleanId)) {
      debugPrint("⚡ [Deduplication Guard]: Skipping duplicate event ID '$cleanId'");
      return;
    }
    _processedEvents.add(cleanId);
    if (_processedEvents.length > 1000) {
      _processedEvents.remove(_processedEvents.first);
    }
    unawaited(DbHelper.instance.markEventProcessed(cleanId, 'LAN_EVENT'));
    applyAction();
  }

  /// Batch deduplication guard: filters out already-processed events and applies remaining rows in a single batch
  void handleIncomingEventsBatch(List<Map<String, dynamic>> rows, void Function(List<Map<String, dynamic>> validRows) applyAction) {
    if (rows.isEmpty) return;
    final List<Map<String, dynamic>> validRows = [];
    for (final row in rows) {
      final eventId = (row['event_id'] ?? row['entry_no'] ?? row['invoice_no'] ?? '').toString().trim();
      if (eventId.isEmpty) {
        validRows.add(row);
        continue;
      }
      if (_processedEvents.contains(eventId)) {
        debugPrint("⚡ [Deduplication Guard]: Skipping duplicate event ID '$eventId'");
        continue;
      }
      _processedEvents.add(eventId);
      if (_processedEvents.length > 1000) {
        _processedEvents.remove(_processedEvents.first);
      }
      unawaited(DbHelper.instance.markEventProcessed(eventId, 'REALTIME_EVENT'));
      validRows.add(row);
    }
    if (validRows.isNotEmpty) {
      applyAction(validRows);
    }
  }

  Future<bool> isEventProcessed(String eventId) async {
    final cleanId = eventId.trim();
    if (cleanId.isEmpty) return false;
    if (_processedEvents.contains(cleanId)) return true;
    return await DbHelper.instance.isEventAlreadyProcessed(cleanId);
  }

  /// Initializes UDP Socket listener and Direct TCP Socket Server on shop network
  Future<void> initLanListener({required void Function(Map<String, dynamic> event) onLanEvent}) async {
    if (!_listeners.contains(onLanEvent)) {
      _listeners.add(onLanEvent);
    }
    if (_isListening || _isInitializing) return;
    if (!ServerConfigService.instance.isLanSyncEnabled) return;

    _isInitializing = true;

    try {
      // 1. Initialize UDP Broadcast Socket (Port 9999)
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        udpPort,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
      _socket?.broadcastEnabled = true;
      _isListening = true;

      _socket?.listen(
        (RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            final datagram = _socket?.receive();
            if (datagram != null) {
              try {
                final message = utf8.decode(datagram.data);
                final map = jsonDecode(message) as Map<String, dynamic>;

                final senderId = (map['sender_id']?.toString() ?? '').toLowerCase().trim();
                final action = map['action']?.toString() ?? '';

                // Handle Plug-and-Play Discovery Packets
                if (action == 'LAN_DISCOVERY_PING' || action == 'LAN_DISCOVERY_PONG') {
                  _handleDiscoveryPacket(map, datagram.address.address, action == 'LAN_DISCOVERY_PING');
                  return;
                }

                if (action == 'LAN_TEST_PING') {
                  debugPrint('⚡ [LAN 1ms Test Ping Received from ${datagram.address.address}]: ${map['payload']}');
                  return;
                }

                // Handle network-wide peer wipe locks
                if (action == 'LAN_RESET_LOCK') {
                  final term = (map['terminal_id']?.toString() ?? senderId).toLowerCase().trim();
                  final duration = (map['duration_seconds'] as num?)?.toInt() ?? 60;
                  _peerResetLocks[term] = DateTime.now().add(Duration(seconds: duration));
                  debugPrint('🔒 [LAN SYNC]: Peer $term is performing a database reset. Muting sync to it for ${duration}s.');
                  return;
                }

                if (action == 'LAN_RESET_RELEASE') {
                  final term = (map['terminal_id']?.toString() ?? senderId).toLowerCase().trim();
                  _peerResetLocks.remove(term);
                  debugPrint('🔓 [LAN SYNC]: Peer $term has finished reset. Resuming sync.');
                  return;
                }

                // If this machine is currently in wiping state, ignore all incoming sync mutations
                if (ServerConfigService.instance.isWiping) {
                  debugPrint('⚡ [LAN SYNC]: Dropping incoming $action because this terminal is in RESET/WIPE mode.');
                  return;
                }

                // Ignore empty sender IDs or packets sent by this exact computer to prevent self-looping
                if (senderId.isEmpty || senderId == _deviceId) {
                  return;
                }

                debugPrint('⚡ [1ms LAN UDP Event Received]: $action from $senderId');
                for (var listener in _listeners) {
                  try {
                    listener(map);
                  } catch (_) {}
                }
              } catch (_) {}
            }
          }
        },
        onError: (e) {
          debugPrint('LanSyncService UDP socket error: $e');
        },
      );

      // 2. Initialize Direct TCP Socket Server (Port 9998) with LineSplitter framing
      try {
        _tcpServer = await ServerSocket.bind(InternetAddress.anyIPv4, tcpPort, shared: true);
        _tcpServer?.listen((Socket clientSocket) {
          _connectedClients.add(clientSocket);
          debugPrint('⚡ [LAN TCP Client Connected]: ${clientSocket.remoteAddress.address}');

          clientSocket
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .listen(
            (String line) {
              if (line.trim().isEmpty) return;
              try {
                final map = jsonDecode(line) as Map<String, dynamic>;
                final senderId = (map['sender_id']?.toString() ?? '').toLowerCase().trim();
                final action = map['action']?.toString() ?? '';

                // If this terminal is currently wiping, drop all incoming sync writes
                if (ServerConfigService.instance.isWiping) {
                  debugPrint('⚡ [LAN TCP SYNC]: Dropping incoming $action because this terminal is in RESET/WIPE mode.');
                  return;
                }

                if (senderId.isNotEmpty && senderId != _deviceId) {
                  debugPrint('⚡ [LAN TCP Event]: $action from $senderId');
                  for (var listener in _listeners) {
                    try {
                      listener(map);
                    } catch (_) {}
                  }
                }
              } catch (e) {
                debugPrint('TCP Line parse error: $e');
              }
            },
            onDone: () {
              _connectedClients.remove(clientSocket);
              clientSocket.destroy();
            },
            onError: (err) {
              _connectedClients.remove(clientSocket);
              clientSocket.destroy();
            },
          );
        });
      } catch (tcpErr) {
        debugPrint('LanSyncService: High-speed UDP Broadcast active on Port $udpPort (TCP port $tcpPort reserved or already bound by active host).');
      }

      if (_tcpServer != null) {
        debugPrint('LanSyncService: High-speed UDP Broadcast (Port $udpPort) & TCP Stream (Port $tcpPort) Active.');
      } else {
        debugPrint('LanSyncService: High-speed UDP Broadcast (Port $udpPort) Active.');
      }
      startAutoDiscovery();
    } catch (e) {
      debugPrint('LanSyncService init error: $e');
    } finally {
      _isInitializing = false;
    }
  }

  /// Processes incoming peer announcements, resolves terminal collisions automatically, and updates registry
  void _handleDiscoveryPacket(Map<String, dynamic> map, String senderIp, bool requiresPong) {
    try {
      final payload = (map['payload'] as Map<String, dynamic>?) ?? {};
      final peerTermId = (payload['terminal_id']?.toString() ?? 'POS-01').trim().toUpperCase();
      final peerTermPrefix = (payload['terminal_prefix']?.toString() ?? '').trim();
      final peerMachineUuid = (payload['machine_uuid']?.toString() ?? '').trim();
      final peerCompName = (payload['computer_name']?.toString() ?? 'Unknown PC').trim();
      final peerProdCount = (payload['product_count'] as num?)?.toInt() ?? 0;

      final config = ServerConfigService.instance;
      final isSelf = peerMachineUuid == config.machineUuid;

      if (!isSelf && peerMachineUuid.isNotEmpty) {
        _discoveredPeers[peerMachineUuid] = DiscoveredTerminalPeer(
          terminalId: peerTermId,
          terminalPrefix: peerTermPrefix,
          machineUuid: peerMachineUuid,
          computerName: peerCompName,
          ipAddress: senderIp,
          productCount: peerProdCount,
          lastSeen: DateTime.now(),
          isSelf: false,
        );

        _emitPeers();

        // Zero-Touch Plug & Play Conflict Resolution:
        // If another active PC is claiming the exact same Terminal ID as this PC:
        if (peerTermId == config.terminalId.trim().toUpperCase()) {
          // If this PC has not been explicitly locked/manually set by the user, auto-assign next slot:
          if (!config.isTerminalConfigured && config.terminalId == 'POS-01') {
            final nextId = calculateNextAvailableTerminalId();
            debugPrint("⚡ [Plug & Play Conflict Auto-Resolution]: Existing $peerTermId found on LAN at $senderIp. Auto-assigning this counter to '$nextId' with prefix '${config.terminalPrefix}'.");
            unawaited(config.setTerminalId(nextId).then((_) {
              broadcastDiscoveryPing(isPong: true);
            }));
          }
        }

        // If received ping, reply with pong so sender immediately discovers this machine
        if (requiresPong) {
          unawaited(broadcastDiscoveryPing(isPong: true));
        }
      }
    } catch (e) {
      debugPrint("LanSyncService _handleDiscoveryPacket notice: $e");
    }
  }

  /// Broadcasts a lightweight 1ms UDP network packet and sends TCP stream to connected shop PCs
  void broadcastEvent(String action, [Map<String, dynamic>? payload]) {
    if (!ServerConfigService.instance.isLanSyncEnabled) return;

    final dataMap = {
      'action': action,
      'sender_id': _deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'payload': payload ?? {},
    };

    final dataJson = jsonEncode(dataMap);
    final tcpPayload = "$dataJson\n";

    // Send UDP Broadcast (uses active socket or binds temporary socket on demand for instant delivery)
    try {
      final bytes = utf8.encode(dataJson);
      if (_socket != null) {
        _socket?.send(bytes, InternetAddress('255.255.255.255'), udpPort);
      } else {
        RawDatagramSocket.bind(InternetAddress.anyIPv4, 0).then((tempSocket) {
          tempSocket.broadcastEnabled = true;
          tempSocket.send(bytes, InternetAddress('255.255.255.255'), udpPort);
          Future.delayed(const Duration(milliseconds: 100), () => tempSocket.close());
        }).catchError((_) {});
      }
      debugPrint('⚡ [1ms LAN UDP Broadcast Sent]: $action');
    } catch (e) {
      debugPrint('LanSyncService UDP broadcast error: $e');
    }

    // Send Direct TCP Packet to connected PCs
    for (var client in List<Socket>.from(_connectedClients)) {
      try {
        client.write(tcpPayload);
      } catch (e) {
        _connectedClients.remove(client);
      }
    }
  }

  /// Direct high-speed LAN TCP socket stream (Port 9998) / UDP broadcast (Port 9999)
  /// for bulk product transfers (e.g. 50,805 products) in 5–10 seconds without touching cloud REST endpoints.
  Future<void> sendBulkProductsOverLan(List<Map<String, dynamic>> products) async {
    if (!_isListening || !ServerConfigService.instance.isLanSyncEnabled) return;

    const int chunkSize = 500;
    for (int i = 0; i < products.length; i += chunkSize) {
      final chunk = products.sublist(i, (i + chunkSize < products.length) ? i + chunkSize : products.length);
      broadcastEvent('BULK_PRODUCT_CHUNK', {
        'chunk': chunk,
        'index': i,
        'total': products.length,
      });
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Explicitly stops sockets and releases ports
  void stopLanListener() {
    dispose();
    debugPrint('LanSyncService: LAN Sockets Closed.');
  }

  /// Closes UDP & TCP Sockets
  void dispose() {
    _discoveryTimer?.cancel();
    _discoveryTimer = null;

    _socket?.close();
    _socket = null;

    _tcpServer?.close();
    _tcpServer = null;

    for (var client in _connectedClients) {
      client.destroy();
    }
    _connectedClients.clear();
    _listeners.clear();

    _isListening = false;
    _isInitializing = false;
  }
}
