import 'dart:async';
import 'package:flutter/foundation.dart';

enum PrintJobStatus { pending, printing, completed, failed }

class PrintJob {
  final String id;
  final String title;
  final Future<void> Function() task;
  final int maxAttempts;
  int attempt;
  PrintJobStatus status;
  String? lastError;
  final DateTime createdAt;

  PrintJob({
    required this.id,
    required this.title,
    required this.task,
    this.maxAttempts = 3,
    this.attempt = 0,
    this.status = PrintJobStatus.pending,
    this.lastError,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

/// Robust, background sequential print spooler with automated exponential retry,
/// dead-letter failed queue, and reactive failure notifications.
class PrintSpoolerService extends ChangeNotifier {
  static final PrintSpoolerService instance = PrintSpoolerService._internal();
  PrintSpoolerService._internal();

  static final List<PrintJob> _printQueue = [];
  static final List<PrintJob> _failedJobs = [];
  static bool _isProcessing = false;

  /// Global callback for failed print tasks (e.g. to display UI snackbar/banner)
  static void Function(PrintJob failedJob)? onPrintFailed;

  /// Unmodifiable view of currently queued jobs
  List<PrintJob> get queuedJobs => List.unmodifiable(_printQueue);

  /// Unmodifiable view of dead-letter failed print jobs
  List<PrintJob> get failedJobs => List.unmodifiable(_failedJobs);

  /// Returns true if there are currently any failed print jobs requiring operator attention
  bool get hasFailedJobs => _failedJobs.isNotEmpty;

  /// Enqueues a print task to be executed sequentially in the background with automatic retry
  static void enqueuePrintTask(
    Future<void> Function() task, {
    String title = "Receipt Print",
    int maxAttempts = 3,
  }) {
    final job = PrintJob(
      id: "PRINT_${DateTime.now().microsecondsSinceEpoch}",
      title: title,
      task: task,
      maxAttempts: maxAttempts > 0 ? maxAttempts : 1,
    );
    _printQueue.add(job);
    instance.notifyListeners();
    _processQueue();
  }

  /// Retries a specific failed print job by its ID
  void retryJob(String jobId) {
    final idx = _failedJobs.indexWhere((j) => j.id == jobId);
    if (idx != -1) {
      final job = _failedJobs.removeAt(idx);
      job.attempt = 0;
      job.status = PrintJobStatus.pending;
      job.lastError = null;
      _printQueue.add(job);
      notifyListeners();
      _processQueue();
    }
  }

  /// Retries all dead-letter failed jobs (e.g. after cashier loads paper or reconnects USB)
  void retryAllFailedJobs() {
    if (_failedJobs.isEmpty) return;
    for (var job in _failedJobs) {
      job.attempt = 0;
      job.status = PrintJobStatus.pending;
      job.lastError = null;
      _printQueue.add(job);
    }
    _failedJobs.clear();
    notifyListeners();
    _processQueue();
  }

  /// Clears dead-letter failed jobs list
  void clearFailedJobs() {
    _failedJobs.clear();
    notifyListeners();
  }

  static void _processQueue() async {
    if (_isProcessing || _printQueue.isEmpty) return;
    _isProcessing = true;

    final job = _printQueue.removeAt(0);
    job.status = PrintJobStatus.printing;
    instance.notifyListeners();

    bool succeeded = false;
    while (!succeeded && job.attempt < job.maxAttempts) {
      job.attempt++;
      try {
        await job.task();
        succeeded = true;
        job.status = PrintJobStatus.completed;
      } catch (e) {
        job.lastError = e.toString();
        debugPrint("Print Spooler Error (Job: ${job.id}, Attempt: ${job.attempt}/${job.maxAttempts}): $e");

        if (job.attempt < job.maxAttempts) {
          // Exponential backoff delay before retry (e.g. 500ms, 1000ms)
          await Future.delayed(Duration(milliseconds: 500 * job.attempt));
        }
      }
    }

    if (!succeeded) {
      job.status = PrintJobStatus.failed;
      _failedJobs.add(job);
      debugPrint("🚨 Print Spooler: Job ${job.id} ('${job.title}') failed after ${job.maxAttempts} attempts. Moved to Dead-Letter queue.");
      if (onPrintFailed != null) {
        try {
          onPrintFailed!(job);
        } catch (_) {}
      }
    }

    _isProcessing = false;
    instance.notifyListeners();

    // Process next job in line
    if (_printQueue.isNotEmpty) {
      _processQueue();
    }
  }
}
