import 'dart:async';

/// Event representing a change in a local database table
class TableChangedEvent {
  final String tableName;
  TableChangedEvent(this.tableName);
}

/// Global event bus for synchronizing database events across application components
class SyncEventBus {
  static final SyncEventBus instance = SyncEventBus._internal();
  SyncEventBus._internal();

  final StreamController<dynamic> _controller = StreamController<dynamic>.broadcast();

  Stream<dynamic> get stream => _controller.stream;

  void emit(dynamic event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  /// Part 6: Triggers table change notifications across subscribed UI screens
  void notifyTableChanged(String table) {
    if (!_controller.isClosed) {
      _controller.add(table);
      _controller.add(TableChangedEvent(table));
    }
  }

  void dispose() {
    _controller.close();
  }
}
