import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'dart:convert';
import 'package:flutter/material.dart';

/// Helper function to spawn a native OS window with a specific route and arguments.
Future<void> openUntrappedWindow({
  required String routeName, 
  required String windowTitle, 
  Map<String, dynamic>? extraArguments,
  Size size = const Size(1050, 650),
}) async {
  // Package the route and any extra data (like product names or IDs)
  final arguments = extraArguments ?? {};
  arguments['route'] = routeName;

  // Command the OS to build a physical window
  final window = await DesktopMultiWindow.createWindow(jsonEncode(arguments));

  await window.setFrame(const Offset(0, 0) & size);
  await window.center();
  await window.setTitle(windowTitle);
  await window.show();
}
