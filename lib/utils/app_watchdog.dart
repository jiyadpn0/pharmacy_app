import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'app_dialogs.dart';
import '../services/remote_logger_service.dart';

/// Exception thrown when an operation exceeds the watchdog timeout limit.
class WatchdogTimeoutException implements Exception {
  final String operationName;
  final Duration timeout;

  WatchdogTimeoutException({
    required this.operationName,
    required this.timeout,
  });

  @override
  String toString() =>
      "Watchdog Timeout Error: Operation '$operationName' exceeded limit of ${timeout.inSeconds} seconds and was aborted to protect app stability.";
}

/// Generic Exception for transaction or isolate execution failures captured by the Watchdog.
class WatchdogExecutionException implements Exception {
  final String operationName;
  final dynamic originalError;
  final StackTrace? stackTrace;

  WatchdogExecutionException({
    required this.operationName,
    required this.originalError,
    this.stackTrace,
  });

  @override
  String toString() =>
      "Watchdog Execution Error in '$operationName': $originalError";
}

/// A lightweight snapshot token representing the saved in-memory state before an operation.
class StateSnapshot<T> {
  final T data;
  final DateTime timestamp;

  StateSnapshot(this.data) : timestamp = DateTime.now();
}

/// Global Application Watchdog and Transaction Recovery Safety Net
class AppWatchdog {
  static const Duration defaultTimeout = Duration(seconds: 5);

  /// Executes an asynchronous [action] wrapped with a strict Watchdog timeout guard.
  ///
  /// If the operation takes longer than [timeout] (default 5s), it cancels/aborts,
  /// throws a [WatchdogTimeoutException], logs the incident, and executes optional [onTimeout].
  static Future<T> runWithTimeout<T>({
    required Future<T> Function() action,
    required String operationName,
    Duration timeout = defaultTimeout,
    FutureOr<T> Function()? onTimeout,
  }) async {
    try {
      return await action().timeout(
        timeout,
        onTimeout: () async {
          final timeoutErr = WatchdogTimeoutException(
            operationName: operationName,
            timeout: timeout,
          );
          
          // Log incident for remote analytics/debugging if available
          try {
            RemoteLoggerService.instance.logError(
              timeoutErr,
              stackTrace: StackTrace.current,
              library: "WATCHDOG_TIMEOUT",
            );
          } catch (_) {}

          if (onTimeout != null) {
            return await onTimeout();
          }
          throw timeoutErr;
        },
      );
    } on TimeoutException {
      final err = WatchdogTimeoutException(
        operationName: operationName,
        timeout: timeout,
      );
      throw err;
    } catch (e, st) {
      if (e is WatchdogTimeoutException) rethrow;
      
      try {
        RemoteLoggerService.instance.logError(
          e,
          stackTrace: st,
          library: "WATCHDOG_EXECUTION_FAILURE",
          context: "Failed in $operationName",
        );
      } catch (_) {}

      throw WatchdogExecutionException(
        operationName: operationName,
        originalError: e,
        stackTrace: st,
      );
    }
  }

  /// Executes a complex state-mutating or database operation inside a Memento Safety Net.
  ///
  /// 1. Captures pre-transaction state via [captureState].
  /// 2. Executes [action] protected by [AppWatchdog.runWithTimeout].
  /// 3. On success: returns result.
  /// 4. On failure/timeout: calls [restoreState] with the snapshot to restore in-memory state,
  ///    and if a [context] is provided, presents an [AppDialogs.showFastDialog] alert.
  static Future<T?> runWithSafetyNet<T, S>({
    required Future<T> Function() action,
    required String operationName,
    required S Function() captureState,
    required void Function(S snapshot) restoreState,
    BuildContext? context,
    Duration timeout = defaultTimeout,
    bool showErrorDialog = true,
  }) async {
    // Step 1: Capture in-memory snapshot before starting
    final S snapshot = captureState();

    try {
      // Step 2: Execute action under strict Watchdog timeout
      return await runWithTimeout<T>(
        action: action,
        operationName: operationName,
        timeout: timeout,
      );
    } catch (error) {
      // Step 3: Automatic Rollback - Restore in-memory state snapshot
      try {
        restoreState(snapshot);
        if (kDebugMode) {
          print("🛡️ [WATCHDOG ROLLBACK]: Restored snapshot for '$operationName'.");
        }
      } catch (rollbackError) {
        if (kDebugMode) {
          print("⚠️ [WATCHDOG ROLLBACK FAILED]: $rollbackError");
        }
      }

      // Step 4: UI Recovery Alert
      if (showErrorDialog && context != null && context.mounted) {
        final cleanMsg = error is WatchdogTimeoutException
            ? "Operation '$operationName' took longer than ${timeout.inSeconds} seconds and was safely cancelled to prevent app freeze.\n\nYour previous data/state has been safely restored."
            : "An unexpected issue occurred during '$operationName':\n\n$error\n\nSystem state has been restored to safety.";

        AppDialogs.showFastDialog(
          context: context,
          title: "Transaction Protected",
          content: cleanMsg,
          isSuccess: false,
        );
      }

      return null;
    }
  }
}
