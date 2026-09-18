import 'dart:async';
import 'package:flutter/material.dart';
import 'app_watchdog.dart';
import 'app_dialogs.dart';

/// Universal Watchdog Mixin for Flutter StatefulWidget State classes.
///
/// Provides clean, non-repetitive wrappers for page initialization, heavy queries,
/// database writes, and button callbacks with automatic timeout protection,
/// loading indicators, and error dialogs.
mixin WatchdogMixin<T extends StatefulWidget> on State<T> {
  /// Executes an async action [action] guarded by the Global Watchdog.
  ///
  /// - Automatically displays an optional [AppDialogs.showLoadingDialog] if [showLoading] is true.
  /// - Times out after [timeout] (default: 5 seconds).
  /// - Catches timeouts/exceptions and displays an [AppDialogs.showFastDialog] alert.
  /// - Cleans up loading dialogs safely upon completion.
  Future<R?> runWithWatchdog<R>({
    required Future<R> Function() action,
    required String operationName,
    Duration timeout = AppWatchdog.defaultTimeout,
    bool showLoading = false,
    String loadingMessage = "Processing...",
    bool showErrorDialog = true,
  }) async {
    bool isDialogShowing = false;

    if (showLoading && mounted) {
      isDialogShowing = true;
      AppDialogs.showLoadingDialog(context, message: loadingMessage);
    }

    try {
      final result = await AppWatchdog.runWithTimeout<R>(
        action: action,
        operationName: operationName,
        timeout: timeout,
      );

      return result;
    } catch (e) {
      if (showErrorDialog && mounted) {
        // Dismiss loading dialog if visible before showing error
        if (isDialogShowing && Navigator.canPop(context)) {
          Navigator.pop(context);
          isDialogShowing = false;
        }

        final errorText = e is WatchdogTimeoutException
            ? "Process '$operationName' timed out after ${timeout.inSeconds} seconds.\nOperation aborted to keep the application responsive."
            : "Error during '$operationName': $e";

        AppDialogs.showFastDialog(
          context: context,
          title: "Watchdog Alert",
          content: errorText,
          isSuccess: false,
        );
      }
      return null;
    } finally {
      if (isDialogShowing && mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }

  /// Safe Page Initialization Helper to wrap `initState` or `didChangeDependencies` heavy async loads.
  ///
  /// Prevents screens from freezing on launch if SQLite or Network is slow/hung.
  Future<R?> watchdogPageInit<R>({
    required Future<R> Function() loadAction,
    required String pageName,
    Duration timeout = const Duration(seconds: 5),
    R? fallbackValue,
  }) async {
    return await AppWatchdog.runWithTimeout<R>(
      action: loadAction,
      operationName: "Init Page: $pageName",
      timeout: timeout,
      onTimeout: () {
        if (mounted) {
          AppDialogs.showFastDialog(
            context: context,
            title: "Loading Timed Out",
            content:
                "Loading data for $pageName took too long. Showing last cached view.",
            isSuccess: false,
          );
        }
        return fallbackValue as R;
      },
    );
  }
}
