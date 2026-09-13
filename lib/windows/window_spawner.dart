import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'dart:convert';
import 'package:flutter/material.dart';

void spawnOSWindow(String windowType, String productName) async {
  final window = await DesktopMultiWindow.createWindow(jsonEncode({
    'type': windowType,
    'productName': productName,
  }));
  window
    ..setTitle(windowType == 'sales_history' ? "Sales History: $productName" : "Purchase History: $productName")
    ..setFrame(const Offset(100, 100) & const Size(1000, 600))
    ..center()
    ..show();
}
