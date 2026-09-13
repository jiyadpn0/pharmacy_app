import 'package:flutter/material.dart';

class MdiWindow {
  final String id;
  final String title;
  final Widget content;
  final double width;
  final double height;
  final bool isMinimized;
  final bool isMaximized;
  final Offset position;

  MdiWindow({
    required this.id,
    required this.title,
    required this.content,
    this.width = 600,
    this.height = 500,
    this.isMinimized = false,
    this.isMaximized = false,
    this.position = const Offset(100, 100),
  });

  MdiWindow copyWith({
    String? title,
    Widget? content,
    double? width,
    double? height,
    bool? isMinimized,
    bool? isMaximized,
    Offset? position,
  }) {
    return MdiWindow(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      width: width ?? this.width,
      height: height ?? this.height,
      isMinimized: isMinimized ?? this.isMinimized,
      isMaximized: isMaximized ?? this.isMaximized,
      position: position ?? this.position,
    );
  }
}

class MdiController extends ChangeNotifier {
  final List<MdiWindow> _windows = [];
  List<MdiWindow> get windows => _windows;

  void openWindow(MdiWindow window) {
    int index = _windows.indexWhere((w) => w.id == window.id);
    if (index != -1) {
      // THE FIX: If window exists, update its content/title/size as well!
      _windows[index] = window.copyWith(isMinimized: false);
      // Bring to front
      MdiWindow win = _windows.removeAt(index);
      _windows.add(win);
    } else {
      _windows.add(window);
    }
    notifyListeners();
  }

  void focusWindow(String id) {
    int index = _windows.indexWhere((w) => w.id == id);
    if (index != -1 && index != _windows.length - 1) {
      MdiWindow win = _windows.removeAt(index);
      _windows.add(win.copyWith(isMinimized: false));
      notifyListeners();
    }
  }

  void closeWindow(String id) {
    _windows.removeWhere((w) => w.id == id);
    notifyListeners();
  }

  void toggleMaximize(String id) {
    int index = _windows.indexWhere((w) => w.id == id);
    if (index != -1) {
      _windows[index] = _windows[index].copyWith(isMaximized: !_windows[index].isMaximized);
      notifyListeners();
    }
  }

  void minimizeWindow(String id) {
    int index = _windows.indexWhere((w) => w.id == id);
    if (index != -1) {
      _windows[index] = _windows[index].copyWith(isMinimized: true);
      notifyListeners();
    }
  }

  void restoreWindow(String id) {
    int index = _windows.indexWhere((w) => w.id == id);
    if (index != -1) {
      MdiWindow win = _windows.removeAt(index);
      _windows.add(win.copyWith(isMinimized: false));
      notifyListeners();
    }
  }

  void updateWindowPosition(String id, Offset newPosition) {
    int index = _windows.indexWhere((w) => w.id == id);
    if (index != -1) {
      // THE UNLEASH FIX: Removed the clamp. 
      // The window can now go anywhere, but we keep a tiny 0.0 safety net 
      // so you don't accidentally drag the title bar completely off your physical monitor!
      double safeY = newPosition.dy < 0 ? 0.0 : newPosition.dy; 
      _windows[index] = _windows[index].copyWith(position: Offset(newPosition.dx, safeY));
      notifyListeners();
    }
  }
  
  void updateWindowSize(String id, double width, double height) {
    int index = _windows.indexWhere((w) => w.id == id);
    if (index != -1) {
      _windows[index] = _windows[index].copyWith(width: width, height: height);
      notifyListeners();
    }
  }
}
