import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:desktop_multi_window/desktop_multi_window.dart';

import 'screens/main_shell.dart';
import 'widgets/history_window_content.dart';
import 'providers/app_provider.dart';
import 'providers/pharmacy_provider.dart';
import 'providers/master_data_provider.dart';
import 'providers/inventory_provider.dart';
import 'providers/mdi_controller.dart';
import 'providers/gmail_account_provider.dart';
import 'providers/gst_provider.dart';
import 'providers/sales_provider.dart';
import 'providers/purchase_provider.dart';
import 'controllers/sales_controller.dart';
import 'utils/theme_constants.dart';
import 'utils/window_utils.dart';
import 'utils/app_logger.dart';
import 'database/db_helper.dart';
import 'services/remote_logger_service.dart';
import 'services/update_checker_service.dart';
import 'services/server_config_service.dart';
import 'services/supabase_sync_service.dart';
import 'services/supabase_realtime_service.dart';
import 'services/delta_sync_service.dart';
import 'services/lan_sync_service.dart';

bool _isIpcServerSet = false;

void setupMainIpcServer() {
  if (_isIpcServerSet) return;
  try {
    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
    try {
      final db = await DbHelper.instance.database;

      switch (call.method) {
        case 'query_sales_history':
        case 'query_product_history': {
          final Map argsMap = call.arguments is Map ? call.arguments : {};
          final String productName = argsMap['productName']?.toString() ?? '';
          final String? productId = argsMap['productId']?.toString();
          return await HistoryWindowContent.querySalesHistoryDirect(db, productName, productId);
        }

        case 'query_purchase_history': {
          final Map argsMap = call.arguments is Map ? call.arguments : {};
          final String productName = argsMap['productName']?.toString() ?? '';
          final String? productId = argsMap['productId']?.toString();
          return await HistoryWindowContent.queryPurchaseHistoryDirect(db, productName, productId);
        }

        case 'fetch_invoice': {
          final Map argsMap = call.arguments is Map ? call.arguments : {};
          final String entryNo = argsMap['entryNo']?.toString() ?? '';
          final res = await db.query('sales_invoices', where: 'entry_no = ? OR entry_no LIKE ?', whereArgs: [entryNo, '%_$entryNo']);
          return res.isNotEmpty ? res.first : null;
        }

        default:
          throw UnsupportedError("Unrecognized IPC method: ${call.method}");
      }
    } catch (e, stack) {
      RemoteLoggerService.instance.logError(
        e,
        stackTrace: stack,
        library: 'IPC Server',
        context: 'IPC call ${call.method}',
      );
      rethrow;
    }
  });
  _isIpcServerSet = true;
  } catch (e) {
    debugPrint("IPC Method Handler re-registration safely skipped: $e");
  }
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  AppLogger.instance.info("SYSTEM", "Main application launch initiated.");

  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // Teardown any background timers and subscriptions from previous hot restart sessions
  DeltaSyncService.instance.stopPeriodicSync();
  SupabaseRealtimeService.instance.disposeAll();
  LanSyncService.instance.dispose();

  if (!Platform.isAndroid && !Platform.isIOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  unawaited(RemoteLoggerService.instance.init().catchError((e, s) => debugPrint("RemoteLogger init error: $e")));
  unawaited(UpdateCheckerService.init().catchError((e, s) => debugPrint("UpdateChecker init error: $e")));
  unawaited(ServerConfigService.instance.init().catchError((e, s) => debugPrint("ServerConfig init error: $e")));
  unawaited(SupabaseSyncService.instance.init().catchError((e, s) => debugPrint("SupabaseSync init error: $e")));
  unawaited(DbHelper.instance.autoBackupDatabase().catchError((e, s) => debugPrint("AutoBackup init error: $e")));
  try {
    DeltaSyncService.instance.startPeriodicSync();
  } catch (e) {
    AppLogger.instance.error("SYSTEM", "Periodic sync start error: $e");
  }

  // Handle all unhandled asynchronous / Future platform errors
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.instance.error(
      "ASYNC_ERROR",
      "Unhandled async platform exception",
      error: error,
      stackTrace: stack,
    );
    RemoteLoggerService.instance.logError(
      error,
      stackTrace: stack,
      library: 'Async PlatformDispatcher',
      context: 'Unhandled Async / Future / Navigation Exception',
    );
    return true;
  };

  // =========================================================
  // GLOBAL RENDERFLEX OVERFLOW & LAYOUT ERROR HANDLER
  // =========================================================
  int renderFlexOverflowCount = 0;
  final originalOnError = FlutterError.onError;

  FlutterError.onError = (FlutterErrorDetails details) {
    final bool isRenderFlexOverflow =
        details.exceptionAsString().contains('RenderFlex overflowed');

    if (isRenderFlexOverflow) {
      renderFlexOverflowCount++;
      AppLogger.instance.warn("UI_LAYOUT", "RenderFlex overflow #$renderFlexOverflowCount", details: details.summary.toString());
    } else {
      AppLogger.instance.error(
        "UI_ERROR",
        details.exceptionAsString(),
        error: details.exception,
        stackTrace: details.stack,
        details: details.context?.toString(),
      );
      RemoteLoggerService.instance.logError(
        details.exception,
        stackTrace: details.stack,
        library: details.library,
        context: details.context?.toString(),
      );
    }

    if (originalOnError != null) {
      originalOnError(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  // Custom visual indicator for layout errors in UI
  ErrorWidget.builder = (FlutterErrorDetails details) {
    final bool isOverflow =
        details.exceptionAsString().contains('RenderFlex overflowed');

    if (isOverflow) {
      return Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.amber.shade900.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.amber.shade300, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '⚠️ RenderFlex Overflow: ${details.summary}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      color: const Color(0xFF0F172A),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 380),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.6), width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'UI Rendering Error Intercepted',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'A widget encountered an exception during build.',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      details.exceptionAsString(),
                      style: const TextStyle(
                        color: Color(0xFFF1F5F9),
                        fontSize: 11,
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Builder(
                    builder: (context) {
                      return OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: details.toString()));
                          try {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Error details copied to clipboard'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          } catch (_) {}
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.lightBlueAccent,
                          side: const BorderSide(color: Colors.lightBlueAccent),
                        ),
                        icon: const Icon(Icons.copy, size: 14),
                        label: const Text('Copy Error Details', style: TextStyle(fontSize: 12)),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  };

  // =========================================================
  // TRUE OS MULTI-WINDOW ROUTER (ANDROID STUDIO STYLE)
  // =========================================================
  if (args.isNotEmpty && args.first == 'multi_window') {
    final argument = args.length > 2 && args[2].isNotEmpty ? args[2] : '{}';
    final Map<String, dynamic> data = jsonDecode(argument);
    final String productName = data['productName']?.toString() ?? '';
    final String? productId = data['productId']?.toString();
    final bool isSales = data['isSales'] ?? true;

    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
            bodyColor: const Color(0xFFFFFFFF),
            displayColor: const Color(0xFFFFFFFF),
          ),
        ),
        home: Scaffold(
          appBar: AppBar(
            title: Text("$productName - ${isSales ? 'Sales' : 'Purchase'} History", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            elevation: 0,
            backgroundColor: const Color(0xFF1E293B),
          ),
          body: HistoryWindowContent(productName: productName, productId: productId, isSales: isSales),
        ),
      ),
    );
    return; // CRITICAL: Stops the main ERP from loading in the sub-window
  }

  // =========================================================
  // NORMAL MAIN APPLICATION BOOT
  // =========================================================
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    setupMainIpcServer();
    await windowManager.ensureInitialized();
    windowManager.addListener(ERPWindowListener());

    // 1. Dynamic Display Work Area Detection (Accounts for Taskbar & DPI Scaling)
    Display primaryDisplay = await screenRetriever.getPrimaryDisplay();
    Size workAreaSize = primaryDisplay.visibleSize ?? primaryDisplay.size;
    Offset workAreaOffset = primaryDisplay.visiblePosition ?? Offset.zero;

    // 2. Compute Safe Adaptive Minimum and Default Sizes
    double minWidth = (workAreaSize.width * 0.70).clamp(800.0, 1024.0);
    double minHeight = (workAreaSize.height * 0.70).clamp(540.0, 680.0);

    double defaultWidth = (workAreaSize.width * 0.88).clamp(minWidth, workAreaSize.width);
    double defaultHeight = (workAreaSize.height * 0.88).clamp(minHeight, workAreaSize.height);

    Size initialSize = Size(defaultWidth, defaultHeight);
    Offset initialPosition = Offset(
      workAreaOffset.dx + (workAreaSize.width - defaultWidth) / 2,
      workAreaOffset.dy + (workAreaSize.height - defaultHeight) / 2,
    );

    // 3. Restore Saved Bounds if Valid on Current Display
    bool useSavedPosition = false;
    bool wasMaximized = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      double? savedW = prefs.getDouble('win_width');
      double? savedH = prefs.getDouble('win_height');
      double? savedX = prefs.getDouble('win_x');
      double? savedY = prefs.getDouble('win_y');
      wasMaximized = prefs.getBool('win_is_maximized') ?? false;

      if (savedW != null && savedH != null && savedX != null && savedY != null) {
        // Validate if saved top-left corner is inside current active screen bounds
        bool isXVisible = savedX >= workAreaOffset.dx - 100 && savedX < (workAreaOffset.dx + workAreaSize.width - 100);
        bool isYVisible = savedY >= workAreaOffset.dy - 50 && savedY < (workAreaOffset.dy + workAreaSize.height - 100);

        if (isXVisible && isYVisible) {
          initialSize = Size(
            savedW.clamp(minWidth, workAreaSize.width),
            savedH.clamp(minHeight, workAreaSize.height),
          );
          initialPosition = Offset(savedX, savedY);
          useSavedPosition = true;
        }
      }
    } catch (_) {}

    WindowOptions windowOptions = WindowOptions(
      size: initialSize,
      minimumSize: Size(minWidth, minHeight),
      center: !useSavedPosition,
      backgroundColor: Colors.white,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: 'PHARMA PRO ERP',
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      try {
        await windowManager.setPreventClose(true);
        if (useSavedPosition) {
          await windowManager.setPosition(initialPosition);
        } else {
          await windowManager.center();
        }

        if (wasMaximized) {
          await windowManager.maximize();
        } else {
          await windowManager.show();
        }
        await windowManager.focus();
      } catch (e) {
        debugPrint("WindowManager initialization error handled: $e");
      }
    });
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()),
        ChangeNotifierProvider(create: (_) => PharmacyProvider()),
        ChangeNotifierProvider(create: (_) => MasterDataProvider()),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
        ChangeNotifierProvider(create: (_) => MdiController()),
        ChangeNotifierProvider(create: (_) => SalesController()),
        ChangeNotifierProvider(create: (_) => GmailAccountProvider()),
        ChangeNotifierProvider(create: (_) => GstProvider()),
        ChangeNotifierProvider(create: (_) => SalesProvider()),
        ChangeNotifierProvider(create: (_) => PurchaseProvider()),
      ],
      child: const PharmacyApp(),
    ),
  );
}

class ERPWindowListener extends WindowListener {
  @override
  void onWindowResize() => _saveBounds();

  @override
  void onWindowMove() => _saveBounds();

  @override
  void onWindowMaximize() => _saveMaximized(true);

  @override
  void onWindowUnmaximize() => _saveMaximized(false);

  @override
  void onWindowClose() async {
    if (AppCloseHandler.isClosing) return;
    AppCloseHandler.isClosing = true;

    try {
      // Stop periodic sync and realtime subscriptions before backing up & closing
      DeltaSyncService.instance.stopPeriodicSync();
      SupabaseRealtimeService.instance.disposeAll();
      LanSyncService.instance.dispose();

      bool isPreventClose = await windowManager.isPreventClose();
      if (isPreventClose) {
        try {
          await windowManager.hide();
        } catch (e) {
          debugPrint("Error hiding window on close: $e");
        }

        try {
          await DbHelper.instance.autoBackupOnClose();
        } catch (e) {
          debugPrint("Auto backup on close error: $e");
        }

        await windowManager.destroy();
      }
    } catch (e) {
      debugPrint("Window close error: $e");
      await windowManager.destroy();
    }
  }

  static Timer? _boundsSaveTimer;

  static void _saveBounds() {
    _boundsSaveTimer?.cancel();
    _boundsSaveTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        if (await windowManager.isMaximized() || await windowManager.isMinimized()) return;
        final bounds = await windowManager.getBounds();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('win_width', bounds.width);
        await prefs.setDouble('win_height', bounds.height);
        await prefs.setDouble('win_x', bounds.topLeft.dx);
        await prefs.setDouble('win_y', bounds.topLeft.dy);
        await prefs.setBool('win_is_maximized', false);
      } catch (_) {}
    });
  }

  static void _saveMaximized(bool isMaximized) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('win_is_maximized', isMaximized);
    } catch (_) {}
  }
}

class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class PharmacyApp extends StatelessWidget {
  const PharmacyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = Provider.of<AppProvider>(context);

    // High-Contrast Crisp Typography for Windows ClearType Rendering
    final baseLight = GoogleFonts.interTextTheme(ThemeData.light().textTheme);
    final lightTextTheme = baseLight.copyWith(
      bodySmall: baseLight.bodySmall?.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.black),
      labelSmall: baseLight.labelSmall?.copyWith(fontSize: 11.0, fontWeight: FontWeight.bold, color: Colors.black),
      labelMedium: baseLight.labelMedium?.copyWith(fontSize: 12.0, fontWeight: FontWeight.w600, color: Colors.black),
      bodyMedium: baseLight.bodyMedium?.copyWith(fontSize: 13.0, fontWeight: FontWeight.w500, color: Colors.black),
    ).apply(
      bodyColor: Colors.black,
      displayColor: Colors.black,
    );

    final baseDark = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);
    final darkTextTheme = baseDark.copyWith(
      bodySmall: baseDark.bodySmall?.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600, color: const Color(0xFFFFFFFF)),
      labelSmall: baseDark.labelSmall?.copyWith(fontSize: 11.0, fontWeight: FontWeight.bold, color: const Color(0xFFFFFFFF)),
      labelMedium: baseDark.labelMedium?.copyWith(fontSize: 12.0, fontWeight: FontWeight.w600, color: const Color(0xFFFFFFFF)),
      bodyMedium: baseDark.bodyMedium?.copyWith(fontSize: 13.0, fontWeight: FontWeight.w500, color: const Color(0xFFFFFFFF)),
    ).apply(
      bodyColor: const Color(0xFFFFFFFF),
      displayColor: const Color(0xFFFFFFFF),
    );

    return MaterialApp(
      title: 'PharmaPro ERP',
      scrollBehavior: AppScrollBehavior(),
      debugShowCheckedModeBanner: false,
      themeMode: app.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamilyFallback: const ['Segoe UI', 'Roboto', 'Arial', 'sans-serif'],
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.secondary,
          primary: AppColors.primary,
          brightness: Brightness.light,
        ),
        textTheme: lightTextTheme,
        visualDensity: VisualDensity.compact,
        inputDecorationTheme: const InputDecorationTheme(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamilyFallback: const ['Segoe UI', 'Roboto', 'Arial', 'sans-serif'],
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        cardColor: const Color(0xFF1E293B),
        dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF1E293B)),
        dividerColor: const Color(0xFF334155),
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.secondary,
          primary: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
          surface: const Color(0xFF1E293B),
          onSurface: const Color(0xFFF8FAFC),
        ),
        textTheme: darkTextTheme,
        visualDensity: VisualDensity.compact,
        inputDecorationTheme: const InputDecorationTheme(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      builder: (context, child) {
        final mediaQueryData = MediaQuery.of(context);
        final clampedData = mediaQueryData.copyWith(
          textScaler: mediaQueryData.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.3),
        );
        return MediaQuery(
          data: clampedData,
          child: Builder(
            builder: (innerContext) {
            return Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
                  try {
                    final pharma = Provider.of<PharmacyProvider>(innerContext, listen: false);
                    if (pharma.isImportInProgress) {
                      pharma.cancelImport();
                      return KeyEventResult.handled;
                    }
                  } catch (_) {}

                  final primaryFocus = FocusManager.instance.primaryFocus;
                  if (primaryFocus != null && primaryFocus.context != null) {
                    final isEditable = primaryFocus.context!.findAncestorWidgetOfExactType<EditableText>() != null;
                    if (isEditable) {
                      primaryFocus.unfocus();
                      return KeyEventResult.handled;
                    }
                  }

                  try {
                    final navigatorState = Navigator.maybeOf(innerContext);
                    if (navigatorState != null && navigatorState.canPop()) {
                      navigatorState.maybePop();
                      return KeyEventResult.handled;
                    }
                  } catch (e) {
                    debugPrint('Safely caught ESC key navigation exception: $e');
                  }
                }
                return KeyEventResult.ignored;
              },
              child: child ?? const SizedBox.shrink(),
            );
          },
        ),
      );
    },
      home: const MainShell(),
    );
  }
}

class GlobalShortcutWrapper extends StatelessWidget {
  final Widget child;
  final VoidCallback onSave;
  final VoidCallback onFind;
  final VoidCallback onNew;

  const GlobalShortcutWrapper({
    super.key,
    required this.child,
    required this.onSave,
    required this.onFind,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.f2): onNew,
        const SingleActivator(LogicalKeyboardKey.f6): onSave,
        const SingleActivator(LogicalKeyboardKey.f3): onFind,
      },
      child: Focus(
        autofocus: true,
        child: child,
      ),
    );
  }
}