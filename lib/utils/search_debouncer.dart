import 'dart:async';
import 'package:flutter/foundation.dart';

/// A debouncer helper class to prevent UI thrashing and excessive SQL query execution
/// during rapid barcode scanning or typing in search input fields.
class SearchDebouncer {
  final int milliseconds;
  Timer? _timer;

  SearchDebouncer({required this.milliseconds});

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: milliseconds), action);
  }

  void dispose() {
    _timer?.cancel();
  }
}
