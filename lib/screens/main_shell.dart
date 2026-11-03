import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../providers/app_provider.dart';
import '../providers/pharmacy_provider.dart';
import '../providers/mdi_controller.dart';
import '../widgets/window_controls_bar.dart';
import '../widgets/draggable_modal.dart';
import '../widgets/floating_order_cart.dart';
import '../widgets/split_order_drawer.dart';
import '../utils/theme_constants.dart';
import '../utils/app_formatters.dart';
import '../utils/app_logger.dart';
import '../widgets/log_console_dialog.dart';
import 'quick_adjust_dialog.dart';
import 'current_stock_screen.dart';
import 'product_profile_screen.dart';
import '../database/db_helper.dart';
import '../services/update_checker_service.dart';
import 'package:pharmacy_app/services/remote_logger_service.dart';
import '../services/server_config_service.dart';
import '../services/supabase_sync_service.dart';
import '../services/supabase_realtime_service.dart';
import '../services/delta_sync_service.dart';
import '../services/lan_sync_service.dart';
import '../services/sync_event_bus.dart';
import '../services/app_notification_service.dart';
import '../widgets/notification_panel_dialog.dart';
import '../widgets/watchdog_panel_dialog.dart';
import '../widgets/pin_unlock_dialog.dart';
import 'server_settings_screen.dart';
import '../services/stock_outbox_service.dart';
import '../utils/unsaved_handler.dart';
import 'package:window_manager/window_manager.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WindowListener, WidgetsBindingObserver {
  final ScrollController _tabScrollController = ScrollController();

  Timer? _backupTimer;
  Timer? _cloudSyncTimer;
  Timer? _hourlySyncTimer;
  bool _wasConnected = ServerConfigService.instance.isConnected;
  Future<int>? _unsyncedCountFuture;
  StreamSubscription? _syncBusSubscription;

  void _refreshUnsyncedCount() {
    if (mounted) {
      setState(() {
        _unsyncedCountFuture = SupabaseSyncService.instance.getUnsyncedTotalCount();
      });
    }
  }

  bool _initialStartupSyncTriggered = false;

  void _handleConnectionChange() {
    if (!mounted) return;
    _refreshUnsyncedCount();
    final isConnectedNow = ServerConfigService.instance.isConnected;
    if (!_wasConnected && isConnectedNow) {
      _wasConnected = true;
      if (_initialStartupSyncTriggered) {
        debugPrint("Connection restored! Triggering automatic background sync & queue drain instantly...");
        unawaited(DeltaSyncService.instance.triggerReconnectionCatchupSync());
      }
    } else {
      _wasConnected = isConnectedNow;
    }

    if (ServerConfigService.instance.isLanSyncEnabled) {
      if (!LanSyncService.instance.isListening) {
        LanSyncService.instance.initLanListener(onLanEvent: (event) {
          if (!mounted) return;
          final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);
          pharmacy.scheduleDebouncedInventorySync();
        });
      }
    } else {
      LanSyncService.instance.stopLanListener();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    HardwareKeyboard.instance.addHandler(_handleGlobalKeys);
    ServerConfigService.instance.addListener(_handleConnectionChange);
    SupabaseSyncService.instance.addListener(_refreshUnsyncedCount);

    _syncBusSubscription = SyncEventBus.instance.stream.listen((event) {
      if (event is TableChangedEvent && mounted) {
        if (event.tableName == 'stock_batches') {
          final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);
          pharmacy.scheduleDebouncedInventorySync();
        }
      }
    });

    // Silent check for software updates on boot
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final autoUpdateEnabled = prefs.getBool('auto_update_check_enabled') ?? true;
          if (autoUpdateEnabled && mounted) {
            UpdateCheckerService.checkForUpdates(context, silent: true);
          }
        } catch (e) {
          debugPrint("Silent update check failed: $e");
        }
      }
    });

    // Delay auto-backup to 5 minutes after launch so it never contends for DB locks during startup sync
    _backupTimer = Timer(const Duration(minutes: 5), () async {
      if (!mounted) return;
      try {
        final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);
        final backupPath = await pharmacy.performAutoBackupIfNeeded();
        if (backupPath != null) {
          AppNotificationService.instance.addNotification(
            title: "Daily Backup Created",
            message: "Automated daily database snapshot saved successfully.",
            type: NotificationType.backup,
            actionRoute: "settings",
          );
        }
        // Weekly SQLite WAL checkpoint maintenance
        final prefs = await SharedPreferences.getInstance();
        final lastVacuumMillis = prefs.getInt('last_db_vacuum_timestamp') ?? 0;
        final nowMillis = DateTime.now().millisecondsSinceEpoch;
        if (nowMillis - lastVacuumMillis > 7 * 24 * 60 * 60 * 1000) {
          await DbHelper.instance.vacuumDatabase();
          await prefs.setInt('last_db_vacuum_timestamp', nowMillis);
        }

        await SupabaseSyncService.instance.checkAndPruneOldCloudData();
      } catch (e, stack) {
        RemoteLoggerService.instance.logError(
          e,
          stackTrace: stack,
          library: 'MainShell Timer',
          context: 'Auto-backup background timer',
        );
      }
    });

    // Staggered startup cloud sync on app opening to allow connection health check to stabilize
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mdi = Provider.of<MdiController>(context, listen: false);
      mdi.onPageMovement = () {
        if (mounted) {
          final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);
          pharmacy.refreshInventoryOnPageMovement();
        }
      };

      SupabaseSyncService.instance.onDataPulled = () async {
        if (mounted) {
          final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);
          await pharmacy.loadFromDatabase();
          await pharmacy.fetchAccounts();
          pharmacy.scheduleDebouncedInventorySync();
        }
      };

      Timer? eventDebounceTimer;
      void triggerDebouncedSync() {
        eventDebounceTimer?.cancel();
        eventDebounceTimer = Timer(const Duration(milliseconds: 800), () async {
          if (!mounted) return;
          if (!ServerConfigService.instance.isWiping) {
            final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);
            await SupabaseSyncService.instance.syncPendingCloudSalesAndPurchases(pharmacy: pharmacy);
            if (!SupabaseSyncService.instance.isSyncing) {
              final pulled = await SupabaseSyncService.instance.syncAllPendingData();
              if (pulled && mounted) {
                pharmacy.scheduleDebouncedInventorySync();
              }
            }
          }
        });
      }

      // Immediate startup initialization of LAN and Supabase Realtime Sync Listeners
      Future.microtask(() async {
        if (!mounted) return;
        
        // 1. Initialize Ultra-fast LAN Socket Listener (1ms LAN Sync)
        if (ServerConfigService.instance.isLanSyncEnabled) {
          try {
            await LanSyncService.instance.initLanListener(
              onLanEvent: (event) async {
                if (mounted && !ServerConfigService.instance.isWiping) {
                  final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);
                  final action = event['action']?.toString() ?? '';
                  final payload = event['payload'];
                  final eventId = (payload is Map<String, dynamic>)
                      ? (payload['event_id']?.toString() ?? payload['entry_no']?.toString() ?? '')
                      : '';

                  LanSyncService.instance.handleIncomingEvent(eventId, () async {
                    switch (action) {
                      case 'SALE_SAVED':
                      case 'SALE_COMPLETED':
                        if (payload is Map<String, dynamic> && payload.containsKey('batch_deductions')) {
                          final deductions = payload['batch_deductions'] as List;
                          for (final item in deductions) {
                            if (item is Map<String, dynamic>) {
                              await DbHelper.instance.deductBatchStock(
                                batchId: item['batch_id'] ?? item['batch_number'],
                                productId: item['product_id']?.toString(),
                                qty: (item['quantity_deducted'] ?? item['qty'] ?? 0) as num,
                              );
                            }
                          }
                          SyncEventBus.instance.emit(TableChangedEvent('stock_batches'));
                          pharmacy.scheduleDebouncedInventorySync();
                        } else if (payload is Map<String, dynamic> && payload.containsKey('items') && payload['items'] is List) {
                          final items = payload['items'] as List;
                          for (final item in items) {
                            if (item is Map<String, dynamic>) {
                              await DbHelper.instance.deductBatchStock(
                                batchId: item['batch_number'] ?? item['batch_id'],
                                productId: item['product_id']?.toString(),
                                qty: (item['qty'] ?? 0) as num,
                              );
                            }
                          }
                          SyncEventBus.instance.emit(TableChangedEvent('stock_batches'));
                          pharmacy.scheduleDebouncedInventorySync();
                        } else {
                          triggerDebouncedSync();
                        }
                        break;
                      case 'STOCK_DECREMENT':
                      case 'STOCK_UPDATE':
                        final List<dynamic> batchList = (payload is List) ? List<dynamic>.from(payload) : <dynamic>[payload];
                        await pharmacy.applyRemoteRealtimeUpdate('stock_batches', 'UPDATE', batchList);
                        break;
                      default:
                        triggerDebouncedSync();
                        break;
                    }
                  });
                }
              },
            );
          } catch (e) {
            debugPrint("LanSyncService startup init note: $e");
          }
        }

        // 2. Initialize Supabase Realtime WebSocket Channels & Sequential Phase 1 -> Phase 2 Transition
        if (ServerConfigService.instance.supabaseUrl.isNotEmpty && ServerConfigService.instance.supabaseAnonKey.isNotEmpty) {
          if (!mounted) return;
          if (mounted && !ServerConfigService.instance.isWiping && !_initialStartupSyncTriggered) {
            _initialStartupSyncTriggered = true;
            final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);
            unawaited(() async {
              // PHASE 1: Master Catalog Initial Verification / Download
              await SupabaseSyncService.instance.ensureMasterCatalogDownloaded(pharmacy: pharmacy);
              if (!mounted) return;

              // PHASE 2: Initialize Realtime WebSocket Listeners & Catch-up Sync post-Phase 1
              try {
                await SupabaseRealtimeService.instance.initialize();
                SupabaseRealtimeService.instance.startAllRealtimeListeners(
                  onTableEvent: (String tableName, String eventType, List<Map<String, dynamic>> rows) {
                    if (mounted && !ServerConfigService.instance.isWiping && rows.isNotEmpty) {
                      Future.microtask(() async {
                        if (!mounted) return;
                        LanSyncService.instance.handleIncomingEventsBatch(rows, (validRows) async {
                          await pharmacy.applyRemoteRealtimeUpdate(tableName, eventType, validRows);
                        });
                      });
                    }
                  },
                  onRealtimeEvent: () {
                    triggerDebouncedSync();
                  },
                );
              } catch (e) {
                debugPrint("SupabaseRealtimeService startup init note: $e");
              }
              await DeltaSyncService.instance.triggerReconnectionCatchupSync();
            }());
          }
        }
      });
    });

    // Multi-computer cloud sync loop for real-time multi-counter reflections (Every 2 minutes)
    _cloudSyncTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      if (!mounted) return;
      final serverConfig = ServerConfigService.instance;
      if (serverConfig.isServerModeEnabled && serverConfig.isConnected && serverConfig.autoSyncEnabled) {
        if (!serverConfig.isWiping) {
          try {
            final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);
            await SupabaseSyncService.instance.syncPendingCloudSalesAndPurchases(pharmacy: pharmacy);
            if (!SupabaseSyncService.instance.isSyncing) {
              await SupabaseSyncService.instance.syncAllPendingData().timeout(const Duration(seconds: 3));
            }
          } catch (_) {}
        }
      }
    });

    // Hourly full data refresh timer
    _hourlySyncTimer = Timer.periodic(const Duration(hours: 1), (_) async {
      if (!mounted) return;
      final serverConfig = ServerConfigService.instance;
      if (serverConfig.isServerModeEnabled && serverConfig.isConnected && serverConfig.autoSyncEnabled) {
        if (!serverConfig.isWiping) {
          await SupabaseSyncService.instance.syncAllPendingData(forceFull: true);
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _backupTimer?.cancel();
    _cloudSyncTimer?.cancel();
    _hourlySyncTimer?.cancel();
    _syncBusSubscription?.cancel();
    _tabScrollController.dispose();
    windowManager.removeListener(this);
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeys);
    ServerConfigService.instance.removeListener(_handleConnectionChange);
    SupabaseSyncService.instance.removeListener(_refreshUnsyncedCount);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (ServerConfigService.instance.isServerModeEnabled) {
        unawaited(SupabaseRealtimeService.instance.ensureRealtimeListenersActive());
      }
    }
  }

  @override
  void onWindowClose() async {
    try {
      bool isPreventClose = await windowManager.isPreventClose();
      if (isPreventClose && mounted) {
        // Safe Shutdown Guard: Check for unsynced local records before closing window
        final unsyncedCount = await SupabaseSyncService.instance.getUnsyncedTotalCount();
        if (unsyncedCount > 0 && mounted) {
          final String? choice = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 24),
                  SizedBox(width: 10),
                  Text(
                    "Unsynced Data Warning",
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "You have $unsyncedCount pending local record(s) awaiting cloud sync.",
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Closing the app now means other billing terminals will not see these entries until this PC is reopened.",
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'cancel'),
                  child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade900),
                  onPressed: () => Navigator.pop(ctx, 'sync_close'),
                  child: const Text("Sync & Close", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800),
                  onPressed: () => Navigator.pop(ctx, 'close_now'),
                  child: const Text("Close Anyway", style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );

          if (choice == 'cancel' || choice == null) {
            return; // Abort window close
          }

          if (choice == 'sync_close') {
            try {
              await DeltaSyncService.instance.triggerBackgroundSync(forcePostSave: true).timeout(const Duration(seconds: 8));
            } catch (_) {}
          }
        }

        if (!mounted) return;
        final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);
        await pharmacy.performAutoBackupIfNeeded(forceOnExit: true);
        await windowManager.destroy();
      }
    } catch (e, stack) {
      RemoteLoggerService.instance.logError(
        e,
        stackTrace: stack,
        library: 'MainShell WindowClose',
        context: 'Window close auto-backup',
      );
      await windowManager.destroy();
    }
  }

  bool _handleGlobalKeys(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    if (event.logicalKey == LogicalKeyboardKey.f8) {
      Provider.of<PharmacyProvider>(context, listen: false).toggleOrderPanel();
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.f9 ||
        (HardwareKeyboard.instance.isControlPressed &&
            (event.logicalKey == LogicalKeyboardKey.keyR || event.logicalKey == LogicalKeyboardKey.keyS))) {
      _triggerManualCloudSync();
      return true;
    }

    if (HardwareKeyboard.instance.isControlPressed) {
      if (event.logicalKey == LogicalKeyboardKey.arrowRight || event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        final pharma = Provider.of<PharmacyProvider>(context, listen: false);
        final app = Provider.of<AppProvider>(context, listen: false);

        final bool isRight = event.logicalKey == LogicalKeyboardKey.arrowRight;

        pharma.cycleStaffAgent(forward: isRight);

        bool hasW3Name = pharma.salesSessions[2]['agent'].toString().trim().isNotEmpty;
        int current = pharma.activeSessionIdx;
        int next;

        if (isRight) {
          if (hasW3Name) {
            next = (current + 1) % 3;
          } else {
            next = (current == 0) ? 1 : 0;
          }
        } else {
          if (hasW3Name) {
            next = (current - 1 + 3) % 3;
          } else {
            next = (current == 1) ? 0 : 1;
          }
        }

        pharma.setSalesSession(next);
        app.switchToSalesTab();
        return true;
      }
    }
    return false;
  }

  Future<void> _triggerManualCloudSync() async {
    final syncService = SupabaseSyncService.instance;
    if (syncService.isSyncing) return;

    final pharma = Provider.of<PharmacyProvider>(context, listen: false);
    await syncService.syncPendingCloudSalesAndPurchases(pharmacy: pharma);
    final success = await syncService.syncAllPendingData(forceFull: false, isManualTransfer: true);

    if (mounted) {
      if (success) {
        AppNotificationService.instance.addNotification(
          title: "Cloud Sync Complete",
          message: "All latest server sales and purchases have been pulled successfully.",
          type: NotificationType.backup,
        );
      } else {
        final msg = syncService.lastSyncError.isNotEmpty ? syncService.lastSyncError : 'Up to date';
        AppNotificationService.instance.addNotification(
          title: "Cloud Sync Status",
          message: "Sync finished: $msg",
          type: NotificationType.backup,
        );
      }
      _refreshUnsyncedCount();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = Provider.of<AppProvider>(context);

    return PopScope(
      canPop: false, // Prevents closing the entire window when a dialog pops
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            // 1. BACKGROUND CONTENT LAYER
            Column(
              children: [
                const SizedBox(height: 92), // Reserved space for the Header
                Expanded(
                  child: Container(
                    color: const Color(0xFF1E293B).withValues(alpha: 0.05),
                  ),
                ),
                const SizedBox(height: 24), // Reserved space for Status Bar
              ],
            ),

            // 2. THE FLOATING WINDOW LAYER (MDI)
            // This sits in the middle, but maximized windows stay below the header.
            const Positioned.fill(
              child: MdiArea(),
            ),

            // 3. FIXED HEADER LAYER (ALWAYS ON TOP)
            // We place this LAST in the stack so it's guaranteed to receive drag events!
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildUnifiedTitleBar(context, app),
                  _buildMenuBar(context, app),
                  _buildWindowDock(context, app),
                  _buildOfflineBanner(),
                  _buildDuplicateTerminalBanner(),
                  _buildRejectedOutboxBanner(),
                ],
              ),
            ),

            // 4. FIXED STATUS BAR
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildStatusBar(context),
            ),

            // 5. GLOBAL 50% SPLIT DRAWER
            const SplitOrderDrawer(),

            // 6. FLOATING DRAGGABLE ORDER BOOK ICON (WHEN MINIMIZED)
            const FloatingOrderCart(),
          ],
        ),
      ),
    );
  }

  Widget _buildUnifiedTitleBar(BuildContext context, AppProvider app) {
    return SizedBox(
      height: 32.0,
      child: WindowControlsBar(
        height: 32.0,
        backgroundColor: const Color(0xFF0F172A),
        titleWidget: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.medical_services_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            const Text(
              "PHARMA PRO",
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(width: 16),
            Container(height: 16, width: 1, color: Colors.white24),
            const SizedBox(width: 12),
            Expanded(
              child: Consumer<PharmacyProvider>(
                builder: (_, pharma, __) => _buildActiveStaffBar(app, pharma),
              ),
            ),
          ],
        ),
        trailingActions: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: ListenableBuilder(
                listenable: SupabaseSyncService.instance,
                builder: (context, _) {
                  final syncService = SupabaseSyncService.instance;
                  final bool showSpinner = syncService.isSyncing && syncService.isManualTransfer && !ServerConfigService.instance.isPureCloud;
                  return showSpinner
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                        )
                      : const Icon(Icons.sync_rounded, color: Colors.cyanAccent, size: 16);
                },
              ),
              onPressed: _triggerManualCloudSync,
              tooltip: "Pull Latest Server Entries (Ctrl+R / F9)",
              constraints: const BoxConstraints(maxHeight: 28, maxWidth: 28),
              padding: const EdgeInsets.all(4),
            ),
            const SizedBox(width: 4),
            _buildUnsyncedIndicatorButton(context),
            const SizedBox(width: 4),
            _buildNotificationBellButton(context, app),
            const SizedBox(width: 4),
            _buildWatchdogHeaderButton(context, app),
            const SizedBox(width: 4),
            _buildThemeToggleButton(app),
            const SizedBox(width: 4),
            _buildLogConsoleHeaderButton(context, app),
            const SizedBox(width: 8),
            _buildFinancialYearSelector(context),
            const SizedBox(width: 4),
            ListenableBuilder(
              listenable: ServerConfigService.instance,
              builder: (context, _) {
                final config = ServerConfigService.instance;
                IconData icon = Icons.cloud_off_rounded;
                Color color = Colors.white54;
                String tooltip = "Server Mode: Disabled (Local Mode)";

                if (config.isPureCloud) {
                  if (config.isConnected) {
                    icon = Icons.bolt_rounded;
                    color = Colors.cyanAccent;
                    tooltip = "Pure Cloud Live Mode: Active (${config.storeBranchId})";
                  } else {
                    icon = Icons.cloud_off_rounded;
                    color = Colors.orangeAccent;
                    tooltip = "Pure Cloud Live: Disconnected";
                  }
                } else if (config.isServerModeEnabled) {
                  if (config.isConnected) {
                    icon = Icons.cloud_done_rounded;
                    color = Colors.lightGreenAccent;
                    tooltip = "Server Mode: Connected (${config.storeBranchId})";
                  } else {
                    icon = Icons.cloud_off_rounded;
                    color = Colors.orangeAccent;
                    tooltip = "Server Mode: Connection Error";
                  }
                }

                return IconButton(
                  icon: Icon(icon, color: color, size: 16),
                  onPressed: () => app.addTab("Server Settings", const ServerSettingsScreen()),
                  tooltip: tooltip,
                  constraints: const BoxConstraints(maxHeight: 28, maxWidth: 28),
                  padding: const EdgeInsets.all(4),
                );
              },
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.security_outlined, color: Colors.white70, size: 16),
              onPressed: () => app.openSettings(tab: "Security & Backup"),
              tooltip: "Security & Backup",
              constraints: const BoxConstraints(maxHeight: 28, maxWidth: 28),
              padding: const EdgeInsets.all(4),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white70, size: 16),
              onPressed: () => app.openSettings(),
              tooltip: "Settings",
              constraints: const BoxConstraints(maxHeight: 28, maxWidth: 28),
              padding: const EdgeInsets.all(4),
            ),
            const SizedBox(width: 4),
            const CircleAvatar(
              radius: 10,
              backgroundColor: Colors.white24,
              child: Icon(Icons.person, color: Colors.white, size: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationBellButton(BuildContext context, AppProvider app) {
    final pharma = Provider.of<PharmacyProvider>(context);
    final activeTask = pharma.syncQueue.firstWhere(
      (t) => t.status == 'In Progress' || t.status == 'Pending',
      orElse: () => SyncTask(id: '', title: '', type: ''),
    );
    final bool hasActiveTask = activeTask.id.isNotEmpty;
    final int activeProgressPct = (activeTask.progress * 100).toInt();

    return ListenableBuilder(
      listenable: AppNotificationService.instance,
      builder: (context, _) {
        final service = AppNotificationService.instance;
        final unread = service.unreadCount;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: hasActiveTask
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.amberAccent),
                      ),
                    )
                  : Icon(
                      unread > 0 ? Icons.notifications_active_rounded : Icons.notifications_outlined,
                      color: unread > 0 ? Colors.amberAccent : Colors.white70,
                      size: 16,
                    ),
              onPressed: () async {
                if (service.isNotificationLockEnabled) {
                  final pharmaProvider = Provider.of<PharmacyProvider>(context, listen: false);
                  final bool isUnlocked = await PinUnlockDialog.show(
                    context,
                    pharmaProvider,
                    title: "Unlock Notification Center",
                    message: "Enter Master PIN to view or clear notification alerts.",
                  );

                  if (!isUnlocked) return;
                }

                if (!context.mounted) return;
                NotificationPanelDialog.show(context, onNavigate: (route) {
                  if (route == 'settings') {
                    app.openSettings(tab: "Security & Backup");
                  } else if (route == 'server') {
                    app.addTab("Server Settings", const ServerSettingsScreen());
                  } else if (route == 'expiry') {
                    app.addTab("Current Stock", const CurrentStockScreen());
                  }
                });
              },
              tooltip: hasActiveTask
                  ? "Excel Operation in Progress ($activeProgressPct%) - Click to view or cancel"
                  : (unread > 0 ? "Notification Center ($unread unread)" : "Notification Center"),
              constraints: const BoxConstraints(maxHeight: 28, maxWidth: 28),
              padding: const EdgeInsets.all(4),
            ),
            if (hasActiveTask)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade800,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: Text(
                    "$activeProgressPct%",
                    style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900),
                  ),
                ),
              )
            else if (unread > 0)
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                  child: Text(
                    unread > 9 ? '9+' : '$unread',
                    style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildActiveStaffBar(AppProvider app, PharmacyProvider pharma) {
    // Get staff list: Most active saved names on left, generic "Staff #" names at maximum right
    List<String> activeStaff = pharma.staffNames;

    if (activeStaff.isEmpty) {
      activeStaff = ["Admin"];
    }

    // 2. Currently selected sales agent
    String currentAgent = "";
    if (pharma.salesSessions.isNotEmpty && pharma.activeSessionIdx < pharma.salesSessions.length) {
      currentAgent = pharma.salesSessions[pharma.activeSessionIdx]['agent']?.toString().trim() ?? "";
    }

    // Helper to select an agent
    void selectAgent(String name) {
      int existingIdx = pharma.salesSessions.indexWhere(
        (s) => s['agent']?.toString().trim().toLowerCase() == name.toLowerCase()
      );
      if (existingIdx != -1) {
        pharma.setSalesSession(existingIdx);
      } else {
        final session = Map<String, dynamic>.from(pharma.salesSessions[pharma.activeSessionIdx]);
        session['agent'] = name;
        pharma.updateSalesSession(pharma.activeSessionIdx, session);
      }
      app.switchToSalesTab();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth;

        // Estimate width needed per button (~68px for average staff name, ~78px for overflow dropdown)
        const double approxItemWidth = 68.0;
        const double overflowBtnWidth = 78.0;

        int maxVisible = activeStaff.length;
        if (availableWidth.isFinite && availableWidth > 0) {
          final double totalRequiredWidth = activeStaff.length * approxItemWidth;
          if (totalRequiredWidth > availableWidth) {
            final double spaceForVisible = availableWidth - overflowBtnWidth;
            maxVisible = (spaceForVisible / approxItemWidth).floor().clamp(1, activeStaff.length);
          }
        }

        final bool hasOverflow = activeStaff.length > maxVisible;
        final List<String> visibleStaff = hasOverflow ? activeStaff.sublist(0, maxVisible) : activeStaff;
        final List<String> overflowStaff = hasOverflow ? activeStaff.sublist(maxVisible) : [];

        bool isCurrentInOverflow = overflowStaff.any((s) => s.toLowerCase() == currentAgent.toLowerCase());

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...visibleStaff.map((name) {
                final bool isSelected = currentAgent.toLowerCase() == name.toLowerCase();
                return Container(
                  margin: const EdgeInsets.only(right: 3),
                  child: InkWell(
                    onTap: () => selectAgent(name),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isSelected ? _getAgentColor(name) : Colors.white12,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isSelected ? _getAgentColor(name).withValues(alpha: 0.9) : Colors.white24,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person,
                            size: 11,
                            color: isSelected ? Colors.white : Colors.white70,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            name,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.9),
                              fontSize: 10,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              if (hasOverflow)
                PopupMenuButton<String>(
                  color: const Color(0xFF1E293B),
                  elevation: 8,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  onSelected: selectAgent,
                  itemBuilder: (context) => overflowStaff.map((name) {
                    final bool isSel = currentAgent.toLowerCase() == name.toLowerCase();
                    return PopupMenuItem<String>(
                      value: name,
                      height: 32,
                      child: Row(
                        children: [
                          Icon(
                            Icons.person,
                            size: 13,
                            color: isSel ? Colors.amberAccent : Colors.white70,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            name,
                            style: TextStyle(
                              color: isSel ? Colors.amberAccent : Colors.white,
                              fontSize: 11,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isCurrentInOverflow ? Colors.amber.shade700 : Colors.white10,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isCurrentInOverflow ? Colors.amberAccent : Colors.white24,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isCurrentInOverflow ? "Other: $currentAgent" : "Other...",
                          style: TextStyle(
                            color: isCurrentInOverflow ? Colors.white : Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 14),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWatchdogHeaderButton(BuildContext context, AppProvider app) {
    final service = AppNotificationService.instance;
    final serverConfig = ServerConfigService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([service, serverConfig]),
      builder: (context, _) {
        final watchdogNotifs = service.getNotificationsByType(NotificationType.watchdog);
        final int unreadWatchdog = watchdogNotifs.where((n) => !n.isRead).length;
        final bool isSynced = serverConfig.isConnected;

        return Tooltip(
          message: unreadWatchdog > 0
              ? "Multi-PC Watchdog Feed ($unreadWatchdog new events)"
              : (isSynced ? "Multi-PC Watchdog Live (System Synced 🟢)" : "Multi-PC Watchdog Live (Offline 🟠)"),
          child: InkWell(
            onTap: () {
              WatchdogPanelDialog.show(context, onNavigate: (route) {
                if (route == 'settings') {
                  app.openSettings(tab: "Security & Backup");
                } else if (route == 'server') {
                  app.addTab("Server Settings", const ServerSettingsScreen());
                } else if (route == 'expiry') {
                  app.addTab("Current Stock", const CurrentStockScreen());
                }
              });
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: unreadWatchdog > 0
                    ? Colors.purple.shade900.withValues(alpha: 0.5)
                    : Colors.white10,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: unreadWatchdog > 0
                      ? Colors.purpleAccent
                      : (isSynced ? Colors.green.shade600 : Colors.white24),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.visibility_rounded,
                    size: 12,
                    color: unreadWatchdog > 0 ? Colors.purpleAccent : (isSynced ? Colors.greenAccent : Colors.white70),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "WATCHDOG 🐕",
                    style: TextStyle(
                      color: unreadWatchdog > 0 ? Colors.purpleAccent : Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (isSynced) ...[
                    const SizedBox(width: 4),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.greenAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                  if (unreadWatchdog > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.purpleAccent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "$unreadWatchdog",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildThemeToggleButton(AppProvider app) {
    final bool isDark = app.isDarkMode;
    return Tooltip(
      message: isDark ? "Switch to White/Light Mode" : "Switch to Dark Mode",
      child: InkWell(
        onTap: () => app.toggleDarkMode(),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: isDark ? Colors.amber.shade900.withValues(alpha: 0.3) : Colors.white10,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isDark ? Colors.amberAccent : Colors.white24,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isDark ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                size: 12,
                color: isDark ? Colors.amberAccent : Colors.white70,
              ),
              const SizedBox(width: 4),
              Text(
                isDark ? "WHITE MODE" : "DARK MODE",
                style: TextStyle(
                  color: isDark ? Colors.amberAccent : Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogConsoleHeaderButton(BuildContext context, AppProvider app) {
    final bool isDark = app.isDarkMode;
    return ListenableBuilder(
      listenable: AppLogger.instance,
      builder: (context, _) {
        final hasErrors = AppLogger.instance.hasNewErrors;
        return Tooltip(
          message: "Open Detailed Log Console (Software & Supabase)",
          child: InkWell(
            onTap: () {
              AppLogger.instance.markErrorsAsSeen();
              showDialog(
                context: context,
                builder: (context) => const LogConsoleDialog(),
              );
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: hasErrors
                    ? Colors.red.shade900.withValues(alpha: 0.5)
                    : (isDark ? Colors.cyan.shade900.withValues(alpha: 0.3) : Colors.white10),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: hasErrors
                      ? Colors.redAccent
                      : (isDark ? Colors.cyanAccent.withValues(alpha: 0.6) : Colors.white24),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.terminal_rounded,
                    size: 12,
                    color: hasErrors ? Colors.redAccent : Colors.cyanAccent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "LOGS",
                    style: TextStyle(
                      color: hasErrors ? Colors.redAccent : Colors.cyanAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (hasErrors) ...[
                    const SizedBox(width: 4),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMenuBar(BuildContext context, AppProvider app) {
    return Container(
      height: 28,
      width: double.infinity,
      color: const Color(0xFF1E293B),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const SizedBox(width: 12),
          _CompactDropdownMenu(title: "MASTER", actions: [
            _MenuAction("Product Registration", () => app.openProductRegistration()),
            _MenuAction("Supplier Master", () => app.openSupplierList()),
            _MenuAction("Patient Master", () => app.openPatientList()),
            _MenuAction("Doctor Registration", () => app.openDoctorRegistration()),
            _MenuAction("Staff Management", () => app.openStaffManagement()),
            _MenuAction("Category Master", () => app.openCategoryRegistration()),
            _MenuAction("Rack Master", () => app.openRackRegistration()),
            _MenuAction("Generic Master", () => app.openGenericRegistration()),
            _MenuAction("Manufacturer Master", () => app.openManufacturerRegistration()),
            _MenuAction("Tax Registration", () => app.openTaxRegistration()),
            _MenuAction("Account Master", () => app.openAccountRegistration()),
            _MenuAction("Prescription Master", () => app.openPrescriptionRegistration()),
            _MenuAction("Mapping Manager", () => app.openProductMappingReport()),
          ]),
          _CompactDropdownMenu(title: "TRANSACTION", actions: [
            _MenuAction("Sales Entry", () => app.openSales()),
            _MenuAction("Purchase Entry", () => app.openPurchase()),
            _MenuAction("Purchase Return", () => app.openPurchaseReturn()),
            _MenuAction("Sales Return", () => app.openSalesReturn()),
            _MenuAction("Damage & Expiry Entry", () => app.openDamageEntry()),
          ]),
          _CompactDropdownMenu(title: "STOCK", actions: [
            _MenuAction("Product Profile", () {
              Provider.of<MdiController>(context, listen: false).openWindow(
                MdiWindow(
                  id: "product_profile",
                  title: "Product Profile Ledger",
                  width: 1100,
                  height: 700,
                  content: const ProductProfileScreen(),
                ),
              );
            }),
            _MenuAction("Realtime Stock Qty", () => app.openRealtimeStock()),
            _MenuAction("Live Current Stock", () {
              Provider.of<MdiController>(context, listen: false).openWindow(
                MdiWindow(
                  id: "current_stock",
                  title: "Live Current Stock",
                  width: 1000,
                  height: 600,
                  content: const CurrentStockScreen(),
                ),
              );
            }),
            _MenuAction("Stock Ledger", () => app.openStockLedger()),
            _MenuAction("Consolidate Stock", () => app.openConsolidateStock()),
            _MenuAction("Wholesale Stock Directory", () => app.openWholesaleStockDirectory()),
            _MenuAction("Inventory", () => app.openAllStockDetails()),
          ]),
          _CompactDropdownMenu(title: "STOCK MANAGEMENT", actions: [
            _MenuAction("Stock Checking", () => app.openStockChecking()),
            _MenuAction("Quick Adjustment", () {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const DraggableModal(child: QuickAdjustDialog()),
              );
            }),
            _MenuAction("Stock Adjustment (Batch)", () => app.openStockAdjustmentBatch()),
            _MenuAction("Damage & Expiry Entry", () => app.openDamageEntry()),
            _MenuAction("Expiry / Non Moving", () => app.openExpiryList()),
          ]),
          _CompactDropdownMenu(title: "ORDER", actions: [
            _MenuAction("Order Book", () => app.openOrderBook()),
            _MenuAction("Order Confirmation", () => app.openOrderConfirmation()),
            _MenuAction("Special Orders", () => app.openSpecialOrders()),
            _MenuAction("Stock Enquiries", () => app.openStockEnquiries()),
            _MenuAction("Product Ranking", () => app.openProductRanking()),
          ]),
          _CompactDropdownMenu(title: "REPORTS", actions: [
            _MenuAction("Sales Analysis", () => app.openSalesReport()),
            _MenuAction("Schedule H1 / Narcotics Register", () => app.openScheduleH1Register()),
            _MenuAction("Reorder Assistant (PO Generator)", () => app.openReorderAssistant()),
            _MenuAction("Sales Return Analysis", () => app.openSalesReturnReport()),
            _MenuAction("GST Filing Report", () => app.openGstReport()),
            _MenuAction("Purchase Analysis", () => app.openPurchaseReport()),
            _MenuAction("Purchase Return Analysis", () => app.openPurchaseReturnReport()),
            _MenuAction("Stock Adjustment Report", () => app.openStockAdjustmentBatchReport()),
          ]),
          _CompactDropdownMenu(title: "ACCOUNTS", actions: [
            _MenuAction("Ledger Registration", null, children: [
              _MenuAction("Ledger Registration", () => app.openLedgerRegistration()),
              _MenuAction("Account Master", () => app.openAccountRegistration()),
              _MenuAction("Payment Entry", () => app.openPayment()),
              _MenuAction("Customer Ledger", () => app.openCustomerLedger()),
            ]),
            _MenuAction("Receipt Entry", () => app.openReceipt()),
            _MenuAction("Daily Report", () => app.openDailyReport()),
          ]),
          _CompactDropdownMenu(title: "ANALYSIS", actions: [
            _MenuAction("Sales Analysis", () => app.openSalesReport()),
            _MenuAction("Purchase Analysis", () => app.openPurchaseReport()),
            _MenuAction("Sales Return Analysis", () => app.openSalesReturnReport()),
            _MenuAction("Purchase Return Analysis", () => app.openPurchaseReturnReport()),
            _MenuAction("Stock Adjustment Report", () => app.openStockAdjustmentBatchReport()),
            _MenuAction("Product Ranking Analysis", () => app.openProductRanking()),
          ]),

          // Add a solid drag handle for the remaining space in the Menu Bar
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => windowManager.startDragging(),
            child: Container(width: 50, color: Colors.transparent),
          ),
        ],
      ),
    ),
    );
  }

  // ---> NEW: AGENT COLOR MAPPER <---
  Color _getAgentColor(String agentName) {
    switch (agentName.trim().toLowerCase()) {
      case "jiyad": return Colors.teal.shade400;
      case "admin": return Colors.indigo.shade400;
      case "suresh": return Colors.orange.shade400;
      case "ramesh": return Colors.purple.shade400;
      case "staff 1": return Colors.pink.shade400;
      case "staff 2": return Colors.cyan.shade400;
      default:
        final colors = [
          Colors.teal.shade400,
          Colors.indigo.shade400,
          Colors.orange.shade400,
          Colors.purple.shade400,
          Colors.pink.shade400,
          Colors.cyan.shade400,
          Colors.blue.shade400,
          Colors.amber.shade600,
          const Color(0xFF34D399),
        ];
        if (agentName.isEmpty) return Colors.blue.shade400;
        final hash = agentName.trim().toLowerCase().codeUnits.fold(0, (prev, elem) => prev + elem);
        return colors[hash % colors.length];
    }
  }



  void _showTabContextMenu(BuildContext context, AppProvider app, Offset position, {int? tabIndex}) async {
    final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final int targetIdx = tabIndex ?? app.activeTabIndex;
    final bool canMoveLeft = targetIdx > 1;
    final bool canMoveRight = targetIdx > 0 && targetIdx < app.openTabs.length - 1;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        if (tabIndex != null && targetIdx > 0) ...[
          PopupMenuItem<String>(
            value: 'move_left',
            enabled: canMoveLeft,
            child: const Row(
              children: [
                Icon(Icons.arrow_back, size: 16),
                SizedBox(width: 8),
                Text("Move tab left"),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'move_right',
            enabled: canMoveRight,
            child: const Row(
              children: [
                Icon(Icons.arrow_forward, size: 16),
                SizedBox(width: 8),
                Text("Move tab right"),
              ],
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'close_others',
            enabled: app.openTabs.length > 2 || (app.openTabs.length == 2 && targetIdx != 0),
            child: const Row(
              children: [
                Icon(Icons.tab_unselected, size: 16),
                SizedBox(width: 8),
                Text("Close other tabs"),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'close_right',
            enabled: targetIdx < app.openTabs.length - 1,
            child: const Row(
              children: [
                Icon(Icons.clear_all, size: 16),
                SizedBox(width: 8),
                Text("Close tabs to the right"),
              ],
            ),
          ),
          const PopupMenuDivider(),
        ],
        PopupMenuItem<String>(
          value: 'recover',
          enabled: app.closedTabsHistory.isNotEmpty,
          child: const Row(
            children: [
              Icon(Icons.restore_page_rounded, size: 16),
              SizedBox(width: 8),
              Text("Recover last closed tab"),
            ],
          ),
        ),
      ],
    );

    if (result == 'move_left') {
      app.moveTabLeft(targetIdx);
    } else if (result == 'move_right') {
      app.moveTabRight(targetIdx);
    } else if (result == 'close_others') {
      app.closeOtherTabs(targetIdx);
    } else if (result == 'close_right') {
      app.closeTabsToRight(targetIdx);
    } else if (result == 'recover') {
      app.recoverLastClosedTab();
    }
  }

  Widget _buildWindowDock(BuildContext context, AppProvider app) {
    final mdi = Provider.of<MdiController>(context);
    final bool isDark = app.isDarkMode;
    final allItems = [
      ...app.openTabs.asMap().entries.map((e) => {
            'title': e.value.title,
            'type': 'tab',
            'index': e.key,
            'id': '',
            'isActive': app.activeTabIndex == e.key
          }),
      ...mdi.windows.where((w) => !w.isMinimized).map((w) => {
            'title': w.title,
            'type': 'mdi',
            'index': -1,
            'id': w.id,
            'isActive': true
          }),
    ];

    if (allItems.isEmpty) return const SizedBox.shrink();

    void scrollTabs(double delta) {
      if (!_tabScrollController.hasClients) return;
      final target = (_tabScrollController.offset + delta)
          .clamp(0.0, _tabScrollController.position.maxScrollExtent);
      _tabScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }

    return Container(
      height: 32,
      width: double.infinity,
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          // Scroll Left Button
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white70, size: 18),
            onPressed: () => scrollTabs(-150),
            tooltip: "Scroll tabs left",
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 22, minHeight: 28),
            hoverColor: Colors.white10,
          ),
          Expanded(
            child: GestureDetector(
              onSecondaryTapDown: (details) {
                _showTabContextMenu(context, app, details.globalPosition);
              },
              child: ReorderableListView.builder(
                scrollController: _tabScrollController,
                scrollDirection: Axis.horizontal,
                buildDefaultDragHandles: false,
                proxyDecorator: (Widget child, int index, Animation<double> animation) {
                  return AnimatedBuilder(
                    animation: animation,
                    builder: (BuildContext context, Widget? child) {
                      return Material(
                        elevation: 10,
                        color: Colors.transparent,
                        shadowColor: Colors.black87,
                        child: child,
                      );
                    },
                    child: child,
                  );
                },
                onReorderItem: (int oldIndex, int newIndex) {
                  if (oldIndex < app.openTabs.length) {
                    app.reorderTabs(oldIndex, newIndex);
                  }
                },
                itemCount: allItems.length,
                itemBuilder: (context, index) {
                  final item = allItems[index];
                  final bool isActive = item['isActive'] as bool;
                  final bool isHome = item['title'] == 'Home';
                  final String titleText = (item['title'] as String).toUpperCase();

                  final Color tabBg = isActive
                      ? (isDark ? const Color(0xFF1E293B) : Colors.white)
                      : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.12));

                  final Color txtColor = isActive
                      ? (isDark ? Colors.amberAccent : const Color(0xFF0F172A))
                      : Colors.white70;

                  final Color closeIconColor = isActive
                      ? (isDark ? Colors.amberAccent.withValues(alpha: 0.9) : const Color(0xFF0F172A))
                      : Colors.white38;

                  final Key itemKey = ValueKey(
                    item['type'] == 'tab'
                        ? 'tab_${item['title']}_${item['index']}'
                        : 'mdi_${item['id']}',
                  );

                  final double tabMaxWidth = isHome ? 75.0 : (isActive ? 220.0 : 160.0);
                  final double tabMinWidth = isHome ? 50.0 : 40.0;

                  return ReorderableDragStartListener(
                    key: itemKey,
                    index: index,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          if (item['type'] == 'tab') {
                            app.focusTab(item['index'] as int);
                          } else {
                            mdi.focusWindow(item['id'] as String);
                          }
                        },
                        onSecondaryTapDown: (details) {
                          _showTabContextMenu(
                            context,
                            app,
                            details.globalPosition,
                            tabIndex: item['type'] == 'tab' ? item['index'] as int : null,
                          );
                        },
                        child: Container(
                          constraints: BoxConstraints(minWidth: tabMinWidth, maxWidth: tabMaxWidth),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          margin: const EdgeInsets.only(right: 1, top: 1),
                          decoration: BoxDecoration(
                            color: tabBg,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                            border: Border(
                              right: BorderSide(
                                color: isActive ? Colors.transparent : Colors.white.withValues(alpha: 0.1),
                                width: 1,
                              ),
                            ),
                          ),
                          child: DefaultTextStyle(
                            style: TextStyle(
                              color: txtColor,
                              fontSize: 10.5,
                              fontWeight: isActive ? FontWeight.w900 : FontWeight.w600,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isHome) ...[
                                  Icon(Icons.home_rounded, size: 13, color: txtColor),
                                  const SizedBox(width: 4),
                                ],
                                Flexible(
                                  child: Text(
                                    titleText,
                                    style: TextStyle(
                                      color: txtColor,
                                      fontSize: 10.5,
                                      fontWeight: isActive ? FontWeight.w900 : FontWeight.w600,
                                      letterSpacing: 0.3,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                if (item['type'] == 'tab' && !isHome) ...[
                                  const SizedBox(width: 4),
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => confirmCloseTab(context, item['index'] as int),
                                      borderRadius: BorderRadius.circular(4),
                                      hoverColor: Colors.red.withValues(alpha: 0.2),
                                      child: Padding(
                                        padding: const EdgeInsets.all(2),
                                        child: Icon(
                                          Icons.close,
                                          size: 11,
                                          color: closeIconColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // Scroll Right Button
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.white70, size: 18),
            onPressed: () => scrollTabs(150),
            tooltip: "Scroll tabs right",
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 22, minHeight: 28),
            hoverColor: Colors.white10,
          ),
          // Drag area for the window
          Expanded(
            flex: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (details) => windowManager.startDragging(),
              child: const SizedBox(width: 50, height: double.infinity),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return ListenableBuilder(
      listenable: ServerConfigService.instance,
      builder: (context, _) {
        final config = ServerConfigService.instance;
        final bool isOffline = config.isPureCloud ? !config.isConnected : (config.isServerModeEnabled && !config.isConnected);
        if (!isOffline) {
          return const SizedBox.shrink();
        }
        final String bannerText = config.isPureCloud
            ? "PURE CLOUD LIVE DISCONNECTED — TYPING ENABLED (SAVE, EDIT & DELETE BLOCKED)"
            : "SERVER DISCONNECTED — WORKING IN OFFLINE MODE (Terminal: ${config.terminalId})";

        return Container(
          width: double.infinity,
          color: config.isPureCloud ? Colors.amber.shade900 : Colors.red.shade700,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                bannerText,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () {
                  config.connectServer(
                    url: config.supabaseUrl,
                    anonKey: config.supabaseAnonKey,
                    branchId: config.storeBranchId,
                    enableMode: true,
                  );
                },
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                ),
                child: const Text("RETRY CONNECTION", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDuplicateTerminalBanner() {
    return ListenableBuilder(
      listenable: ServerConfigService.instance,
      builder: (context, _) {
        final config = ServerConfigService.instance;
        final warning = config.duplicateTerminalWarning;
        if (warning == null || warning.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          color: Colors.red.shade900,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.amberAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  warning,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.settings, size: 14),
                label: const Text("CONFIGURE TERMINAL", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amberAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => const Dialog(
                      child: SizedBox(
                        width: 900,
                        height: 650,
                        child: ServerSettingsScreen(),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRejectedOutboxBanner() {
    return ListenableBuilder(
      listenable: StockOutboxService.instance.rejectedCount,
      builder: (context, _) {
        final count = StockOutboxService.instance.rejectedCount.value;
        if (count <= 0) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          color: Colors.deepOrange.shade900,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                "CRITICAL: $count stock operation(s) were REJECTED by Cloud Server (insufficient stock / race condition).",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () async {
                  await StockOutboxService.instance.reconcileLocalStockFromCloud();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Triggered local inventory reconciliation from cloud.')),
                    );
                  }
                },
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white24,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                ),
                child: const Text("RECONCILE STOCK", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUnsyncedBoxButton(BuildContext context) {
    _unsyncedCountFuture ??= SupabaseSyncService.instance.getUnsyncedTotalCount();
    return ListenableBuilder(
      listenable: SupabaseSyncService.instance,
      builder: (context, _) {
        final syncService = SupabaseSyncService.instance;
        final isSyncingActive = syncService.isSyncing;

        return FutureBuilder<int>(
          future: _unsyncedCountFuture,
          builder: (context, snapshot) {
            final rawCount = snapshot.data ?? 0;
            final isError = rawCount < 0;
            final count = isError ? 0 : rawCount;
            final hasUnsynced = count > 0;

            final String label = isError
                ? "Sync Unknown"
                : ((isSyncingActive && hasUnsynced)
                    ? "Syncing ($count left)..."
                    : (hasUnsynced ? "$count Unsynced" : "All Synced"));

            final Color bgColor = isError
                ? Colors.orange.shade900.withValues(alpha: 0.8)
                : ((isSyncingActive && hasUnsynced)
                    ? Colors.amber.shade900.withValues(alpha: 0.8)
                    : (hasUnsynced ? Colors.red.shade700 : Colors.white12));

            final Color borderColor = isError
                ? Colors.orangeAccent
                : ((isSyncingActive && hasUnsynced)
                    ? Colors.amberAccent
                    : (hasUnsynced ? Colors.red.shade300 : Colors.white24));

            return Tooltip(
              message: isError
                  ? "Unable to determine sync status. Check database/network connection."
                  : (hasUnsynced
                      ? "$count pending local record(s) stored in internal storage awaiting cloud sync."
                      : "All local entries are fully synced with live server."),
              child: InkWell(
                onTap: () => _showUnsyncedPanel(context),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSyncingActive && hasUnsynced)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent),
                        )
                      else
                        Icon(
                          isError
                              ? Icons.sync_problem_rounded
                              : (hasUnsynced ? Icons.warning_amber_rounded : Icons.cloud_done_rounded),
                          color: Colors.white,
                          size: 14,
                        ),
                      const SizedBox(width: 4),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUnsyncedIndicatorButton(BuildContext context) {
    return ListenableBuilder(
      listenable: ServerConfigService.instance,
      builder: (context, _) {
        final config = ServerConfigService.instance;
        if (config.isPureCloud) {
          final isOnline = config.isConnected;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: isOnline
                    ? "Pure Cloud Live Mode: Connected (${config.storeBranchId})"
                    : "Pure Cloud Live Mode: Disconnected (Entries saved inside local storage)",
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isOnline
                        ? Colors.cyan.shade900.withValues(alpha: 0.5)
                        : Colors.red.shade900.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: isOnline ? Colors.cyan.shade300 : Colors.red.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isOnline ? Icons.bolt_rounded : Icons.wifi_off_rounded,
                        color: isOnline ? Colors.cyanAccent : Colors.orangeAccent,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isOnline ? "Pure Cloud Live" : "Cloud Offline",
                        style: TextStyle(
                          color: isOnline ? Colors.cyanAccent : Colors.orangeAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _buildUnsyncedBoxButton(context),
            ],
          );
        }

        return _buildUnsyncedBoxButton(context);
      },
    );
  }

  void _showUnsyncedPanel(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const UnsyncedDiscrepanciesDialog(),
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, app, child) {
        return Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: AppColors.primary,
          child: Row(
            children: [
              const Icon(Icons.dns, size: 12, color: Colors.green),
              const SizedBox(width: 4),
              const Text(
                "CONNECTED",
                style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
              ),
              const Expanded(child: SizedBox()),
              Flexible(
                child: Text(
                  app.statusMessage,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontStyle: FontStyle.italic),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Expanded(child: SizedBox()),
              Text(
                "SAHAKAR MEDICALS - v${UpdateCheckerService.currentVersion}",
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFinancialYearSelector(BuildContext context) {
    return Consumer<PharmacyProvider>(
      builder: (context, pharma, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white24),
          ),
          child: PopupMenuButton<String>(
            tooltip: "Switch Financial Year",
            initialValue: pharma.selectedFinancialYear,
            onSelected: (String year) {
              pharma.setSelectedFinancialYear(year);
            },
            itemBuilder: (BuildContext context) {
              return pharma.availableFinancialYears.map((String year) {
                return PopupMenuItem<String>(
                  value: year,
                  height: 30,
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 12,
                        color: pharma.selectedFinancialYear == year ? AppColors.primary : Colors.black54,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        year,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: pharma.selectedFinancialYear == year ? FontWeight.bold : FontWeight.normal,
                          color: pharma.selectedFinancialYear == year ? AppColors.primary : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList();
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_month_rounded, size: 12, color: Colors.white70),
                const SizedBox(width: 4),
                Text(
                  pharma.selectedFinancialYear,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 12, color: Colors.white60),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CompactDropdownMenu extends StatefulWidget {
  final String title;
  final List<_MenuAction> actions;

  const _CompactDropdownMenu({required this.title, required this.actions});

  @override
  State<_CompactDropdownMenu> createState() => _CompactDropdownMenuState();
}

class _CompactDropdownMenuState extends State<_CompactDropdownMenu> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Provider.of<AppProvider>(context, listen: false).isDarkMode;
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
        elevation: const WidgetStatePropertyAll(12),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(8),
              bottomRight: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
          ),
        ),
      ),
      menuChildren: widget.actions.map((a) => _buildMenuItem(a, isDark)).toList(),
      builder: (context, controller, child) {
        bool isOpen = controller.isOpen;
        return MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isOpen 
                    ? const Color(0xFF334155) 
                    : (_isHovered ? Colors.white.withValues(alpha: 0.1) : Colors.transparent),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isOpen ? Colors.white54 : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: isOpen ? Colors.white : Colors.white70,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 12,
                    color: isOpen ? Colors.white : Colors.white38,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMenuItem(_MenuAction action, bool isDark) {
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    if (action.children != null && action.children!.isNotEmpty) {
      return SubmenuButton(
        menuChildren: action.children!.map((a) => _buildMenuItem(a, isDark)).toList(),
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
          minimumSize: const WidgetStatePropertyAll(Size(180, 35)),
          fixedSize: const WidgetStatePropertyAll(Size.fromHeight(35)),
          overlayColor: WidgetStatePropertyAll(isDark ? Colors.white12 : Colors.black12),
        ),
        child: Text(
          action.title,
          style: TextStyle(
            fontSize: 11, 
            fontWeight: FontWeight.w500, 
            color: textColor,
          ),
        ),
      );
    }
    return MenuItemButton(
      onPressed: action.callback,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
        minimumSize: const WidgetStatePropertyAll(Size(180, 35)),
        fixedSize: const WidgetStatePropertyAll(Size.fromHeight(35)),
        overlayColor: WidgetStatePropertyAll(isDark ? Colors.white12 : Colors.black12),
      ),
      child: Text(
        action.title,
        style: TextStyle(
          fontSize: 11, 
          fontWeight: FontWeight.w500, 
          color: textColor,
        ),
      ),
    );
  }
}

class _MenuAction {
  final String title;
  final VoidCallback? callback;
  final List<_MenuAction>? children;
  _MenuAction(this.title, this.callback, {this.children});
}

class MdiArea extends StatelessWidget {
  const MdiArea({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppProvider, MdiController>(
      builder: (context, app, mdi, child) {
        return LayoutBuilder(builder: (context, constraints) {
          List<Widget> allWindows = [];

          const double topSafeOffset = 92.0; // 32 (Title) + 28 (Menu) + 32 (Tabs)
          const double bottomSafeOffset = 24.0;
          final double safeHeight = constraints.maxHeight - topSafeOffset - bottomSafeOffset;

          // 1. RENDER BACKGROUND TABS (Locked to the safe zone)
          List<int> indices = List.generate(app.openTabs.length, (i) => i);
          indices.sort((a, b) {
            if (a == app.activeTabIndex) return 1;
            if (b == app.activeTabIndex) return -1;
            return 0;
          });

          for (int i in indices) {
            final tab = app.openTabs[i];
            bool isActive = app.activeTabIndex == i;
            bool isHome = tab.title == 'Home';
            bool isMax = tab.isMaximized || isHome;
            
            double left = isMax ? 0 : tab.position.dx;
            double top = isMax ? topSafeOffset : tab.position.dy;
            double width = isMax ? constraints.maxWidth : tab.size.width;
            double height = isMax ? safeHeight : tab.size.height;

            allWindows.add(
              Positioned(
                key: ValueKey("tab_$i"),
                left: left,
                top: top,
                width: width,
                height: height,
                child: Offstage(
                  offstage: isMax && !isActive,
                  child: TickerMode(
                    enabled: !isMax || isActive,
                    child: _MdiWindowWidget(
                      title: tab.title,
                      isMaximized: isMax,
                      isActive: isActive,
                      showHeader: !isHome && !tab.isMaximized, 
                      onClose: tab.closable ? () => confirmCloseTab(context, i) : null,
                      onMaximize: isHome ? null : () => app.toggleWindowMaximize(i),
                      onFocus: () => app.focusTab(i),
                      onDragFinished: (newPos) => app.updateWindowPosition(i, newPos),
                      onResizeFinished: (newSize) => app.updateWindowSize(i, newSize),
                      initialPosition: tab.position,
                      initialSize: tab.size,
                      child: tab.content,
                    ),
                  ),
                ),
              ),
            );
          }

          // 2. RENDER FLOATING WINDOWS (With proper Z-Indexing!)
          // The last window in the MDI controller's list is the active one in front
          final String? activeWindowId = mdi.windows.isNotEmpty ? mdi.windows.last.id : null;

          for (var window in mdi.windows.where((w) => !w.isMinimized)) {
            bool isMax = window.isMaximized;

            double left = isMax ? 0 : window.position.dx;
            double top = isMax ? topSafeOffset : window.position.dy;
            double width = isMax ? constraints.maxWidth : window.width;
            double height = isMax ? safeHeight : window.height;

            allWindows.add(
              Positioned(
                key: ValueKey("win_${window.id}"),
                left: left,
                top: top,
                width: width,
                height: height,
                child: _MdiWindowWidget(
                  title: window.title,
                  isMaximized: isMax,
                  isActive: window.id == activeWindowId, // Highlights the title bar of the top window!
                  onClose: () => mdi.closeWindow(window.id),
                  onMaximize: () => mdi.toggleMaximize(window.id),
                  onFocus: () => mdi.focusWindow(window.id),
                  onDragFinished: (newPos) => mdi.updateWindowPosition(window.id, newPos),
                  onResizeFinished: (newSize) => mdi.updateWindowSize(window.id, newSize.width, newSize.height),
                  initialPosition: window.position,
                  initialSize: Size(window.width, window.height),
                  child: window.content,
                ),
              ),
            );
          }

          return Stack(
            clipBehavior: Clip.none,
            children: allWindows,
          );
        });
      },
    );
  }
}

class _MdiWindowWidget extends StatefulWidget {
  final String title;
  final Widget child;
  final bool isMaximized;
  final bool isActive;
  final bool showHeader;
  final VoidCallback? onClose;
  final VoidCallback? onMaximize;
  final VoidCallback? onFocus;
  final Function(Offset)? onDragFinished;
  final Function(Size)? onResizeFinished;
  final Offset initialPosition;
  final Size initialSize;

  const _MdiWindowWidget({
    required this.title,
    required this.child,
    required this.isMaximized,
    required this.isActive,
    this.showHeader = true,
    this.onClose,
    this.onMaximize,
    this.onFocus,
    this.onDragFinished,
    this.onResizeFinished,
    required this.initialPosition,
    required this.initialSize,
  });

  @override
  State<_MdiWindowWidget> createState() => _MdiWindowWidgetState();
}

class _MdiWindowWidgetState extends State<_MdiWindowWidget> {
  Offset _dragOffset = Offset.zero;
  Size _resizeOffset = Size.zero;
  bool _isDragging = false;
  bool _isResizing = false;

  @override
  void didUpdateWidget(_MdiWindowWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPosition != oldWidget.initialPosition) _dragOffset = Offset.zero;
    if (widget.initialSize != oldWidget.initialSize) _resizeOffset = Size.zero;
  }

  @override
  Widget build(BuildContext context) {
    // --- DROPDOWN FIX ---
    // If the window is a maximized background tab, DO NOT intercept touches.
    // Return the pure widget so Flutter's dropdowns and overlays work natively!
    if (widget.isMaximized && !widget.showHeader) {
      return widget.child; 
    }

    final bool isDark = Provider.of<AppProvider>(context, listen: false).isDarkMode;
    final Color windowBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color inactiveHeaderBg = isDark ? const Color(0xFF182232) : Colors.blueGrey.shade100;
    final Color inactiveTextColor = isDark ? Colors.white70 : Colors.black87;
    final Color inactiveIconColor = isDark ? Colors.white60 : Colors.black45;

    // --- FLOATING WINDOW RENDERING ---
    return Transform.translate(
      offset: _dragOffset,
      child: SizedBox(
        width: widget.isMaximized ? null : (widget.initialSize.width + _resizeOffset.width),
        height: widget.isMaximized ? null : (widget.initialSize.height + _resizeOffset.height),
        // Use Listener instead of GestureDetector so it never swallows child taps!
        child: Listener(
          onPointerDown: (_) => widget.onFocus?.call(),
          behavior: HitTestBehavior.deferToChild,
          child: Material(
            elevation: widget.isMaximized ? 0 : (widget.isActive ? 24 : 8),
            borderRadius: widget.isMaximized ? BorderRadius.zero : BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: Container(
              decoration: BoxDecoration(
                color: windowBg,
                border: Border.all(
                  color: widget.isActive ? (isDark ? const Color(0xFF3B82F6) : const Color(0xFF0F172A)) : (isDark ? const Color(0xFF334155) : Colors.grey.shade400),
                  width: widget.isMaximized ? 0 : (widget.isActive ? 2.0 : 1.0),
                ),
                borderRadius: widget.isMaximized ? BorderRadius.zero : BorderRadius.circular(8),
              ),
              child: Stack(
                children: [
                  Column(
                    children: [
                      if (widget.showHeader)
                        GestureDetector(
                          onPanStart: (_) {
                            widget.onFocus?.call();
                            setState(() => _isDragging = true);
                          },
                          onPanUpdate: widget.isMaximized ? null : (details) {
                            final screenSize = MediaQuery.of(context).size;
                            setState(() {
                              double newDx = _dragOffset.dx + details.delta.dx;
                              double newDy = _dragOffset.dy + details.delta.dy;

                              double globalX = widget.initialPosition.dx + newDx;
                              double globalY = widget.initialPosition.dy + newDy;

                              // The Edge Bouncer
                              if (globalY < 90) newDy = 90 - widget.initialPosition.dy;
                              if (globalX > screenSize.width - 150) newDx = (screenSize.width - 150) - widget.initialPosition.dx;
                              if (globalX < -widget.initialSize.width + 150) newDx = (-widget.initialSize.width + 150) - widget.initialPosition.dx;
                              if (globalY > screenSize.height - 50) newDy = (screenSize.height - 50) - widget.initialPosition.dy;

                              _dragOffset = Offset(newDx, newDy);
                            });
                          },
                          onPanEnd: (_) {
                            if (_isDragging && widget.onDragFinished != null) {
                              widget.onDragFinished!(widget.initialPosition + _dragOffset);
                            }
                            setState(() => _isDragging = false);
                          },
                          onDoubleTap: widget.onMaximize,
                          child: Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            // Changes color based on Z-Index
                            color: widget.isActive ? const Color(0xFF0F172A) : inactiveHeaderBg,
                            child: Row(
                              children: [
                                Icon(Icons.window, size: 16, color: widget.isActive ? Colors.white70 : inactiveIconColor),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.title,
                                    style: TextStyle(
                                      color: widget.isActive ? Colors.white : inactiveTextColor,
                                      fontWeight: widget.isActive ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (widget.onMaximize != null)
                                  IconButton(
                                    icon: Icon(widget.isMaximized ? Icons.fullscreen_exit : Icons.fullscreen, size: 18, color: widget.isActive ? Colors.white70 : inactiveIconColor),
                                    onPressed: widget.onMaximize,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                if (widget.onClose != null) ...[
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: Icon(Icons.close, size: 18, color: widget.isActive ? Colors.red.shade300 : Colors.black45),
                                    onPressed: widget.onClose,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      Expanded(
                        child: RepaintBoundary(
                          child: ClipRect(
                            child: widget.child,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!widget.isMaximized && widget.onResizeFinished != null)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeDownRight,
                        child: GestureDetector(
                          onPanStart: (_) => setState(() => _isResizing = true),
                          onPanUpdate: (details) {
                            setState(() {
                              _resizeOffset = Size(
                                _resizeOffset.width + details.delta.dx,
                                _resizeOffset.height + details.delta.dy,
                              );
                            });
                          },
                          onPanEnd: (_) {
                            if (_isResizing) {
                              widget.onResizeFinished!(Size(
                                widget.initialSize.width + _resizeOffset.width,
                                widget.initialSize.height + _resizeOffset.height,
                              ));
                            }
                            setState(() => _isResizing = false);
                          },
                          child: Container(
                            width: 20,
                            height: 20,
                            color: Colors.transparent,
                            child: CustomPaint(
                              painter: _ResizeHandlePainter(),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResizeHandlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(size.width * 0.7, size.height), Offset(size.width, size.height * 0.7), paint);
    canvas.drawLine(Offset(size.width * 0.4, size.height), Offset(size.width, size.height * 0.4), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void confirmCloseTab(BuildContext context, int tabIndex) {
  final app = Provider.of<AppProvider>(context, listen: false);
  if (tabIndex < 0 || tabIndex >= app.openTabs.length) return;

  final tab = app.openTabs[tabIndex];
  final tabTitle = tab.title;

  // 1. Non-entry tabs close instantly
  if (!UnsavedChangesRegistry.isEntryTab(tabTitle)) {
    app.closeTab(tabIndex);
    return;
  }

  // 2. Entry tabs check for unsaved changes
  final handler = UnsavedChangesRegistry.getHandler(tabTitle);
  if (handler == null || !handler.hasUnsavedChanges()) {
    app.closeTab(tabIndex);
    return;
  }

  // 3. Show 3-Option Dialog
  showUnsavedChangesDialog(context).then((result) {
    if (result == UnsavedDialogResult.showDifference) {
      handler.showDifferences();
    } else if (result == UnsavedDialogResult.discard) {
      app.closeTab(tabIndex);
    }
  });
}

class UnsyncedDiscrepanciesDialog extends StatefulWidget {
  const UnsyncedDiscrepanciesDialog({super.key});

  @override
  State<UnsyncedDiscrepanciesDialog> createState() => _UnsyncedDiscrepanciesDialogState();
}

class _UnsyncedDiscrepanciesDialogState extends State<UnsyncedDiscrepanciesDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _forceSyncNow() async {
    setState(() => _isLoading = true);
    try {
      await SupabaseSyncService.instance.syncAllPendingData(forceFull: false, isManualTransfer: true);
      if (mounted) {
        AppNotificationService.instance.addNotification(
          title: "Cloud Sync Complete",
          message: "Manual sync finished successfully.",
          type: NotificationType.backup,
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        AppNotificationService.instance.addNotification(
          title: "Cloud Sync Warning",
          message: "Sync notice: $e",
          type: NotificationType.backup,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 750,
        height: 550,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_sync_rounded, color: Colors.indigo, size: 24),
                const SizedBox(width: 10),
                const Text(
                  "Unsynced Data & Stock Discrepancies Monitor",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _forceSyncNow,
                  icon: _isLoading
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync_rounded, size: 16, color: Colors.white),
                  label: Text(_isLoading ? 'Syncing...' : 'Sync All Pending Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 24),
            TabBar(
              controller: _tabController,
              labelColor: Colors.indigo,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.indigo,
              tabs: const [
                Tab(text: 'Unsynced Local Entries (Pending Upload)'),
                Tab(text: 'Stock Discrepancies / Negative Stock'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildUnsyncedEntriesTab(),
                  _buildNegativeStockTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnsyncedEntriesTab() {
    return ListenableBuilder(
      listenable: SupabaseSyncService.instance,
      builder: (context, _) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: SupabaseSyncService.instance.getUnsyncedEntriesList(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final entries = snapshot.data ?? [];
            if (entries.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.green, size: 48),
                    SizedBox(height: 12),
                    Text("All local entries are fully synced with the server!", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  ],
                ),
              );
            }

            return ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final e = entries[index];
                final cleanNo = cleanEntryNo(e['entry_no']?.toString() ?? '');
                final pcName = e['terminal_id']?.toString().isNotEmpty == true
                    ? e['terminal_id'].toString()
                    : ServerConfigService.instance.terminalId;
                return ListTile(
                  leading: const Icon(Icons.receipt_long_rounded, color: Colors.orange),
                  title: Row(
                    children: [
                      Text("${e['type']} #$cleanNo", style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.indigo.shade200),
                        ),
                        child: Text(
                          "PC: $pcName",
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text("Account: ${e['account']} | Date: ${e['date']}"),
                  trailing: Text("₹${(e['amount'] as num).toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.indigo)),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildNegativeStockTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: SupabaseSyncService.instance.getNegativeStockDiscrepancies(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inventory_2_rounded, color: Colors.green, size: 48),
                SizedBox(height: 12),
                Text("No negative stock or offline multi-PC conflicts detected!", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              leading: const Icon(Icons.warning_amber_rounded, color: Colors.red),
              title: Text(item['product_name']?.toString() ?? 'Unknown Product', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("Batch: ${item['batch_number']} | Product ID: ${item['product_id']}"),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  "Stock: ${item['current_stock']}",
                  style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

