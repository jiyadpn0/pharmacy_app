import 'package:flutter/foundation.dart';

class PrintSpoolerService {
  static final List<Future<void> Function()> _printQueue = [];
  static bool _isProcessing = false;

  /// Enqueues a print task to be executed sequentially in the background
  static void enqueuePrintTask(Future<void> Function() task) {
    _printQueue.add(task);
    _processQueue();
  }

  static void _processQueue() async {
    if (_isProcessing || _printQueue.isEmpty) return;
    _isProcessing = true;

    final task = _printQueue.removeAt(0);
    try {
      await task();
    } catch (e) {
      debugPrint("Print Spooler Error: $e");
    } finally {
      _isProcessing = false;
      _processQueue(); // Process next job in line
    }
  }
}
