import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'dart:convert';
import 'package:flutter/material.dart';

void spawnOSWindow(String windowType, String productName, {String? productId}) async {
  final cleanName = productName.trim().toUpperCase();
  final String title = (windowType == 'sales_history' || windowType == 'sales')
      ? "Sales History: $cleanName"
      : "Purchase History: $cleanName";

  final window = await DesktopMultiWindow.createWindow(jsonEncode({
    'type': windowType,
    'productName': cleanName,
    'productId': productId ?? '',
    'isSales': windowType == 'sales_history' || windowType == 'sales',
  }));

  window
    ..setTitle(title)
    ..setFrame(const Offset(100, 100) & const Size(1050, 620))
    ..center()
    ..show();
}
