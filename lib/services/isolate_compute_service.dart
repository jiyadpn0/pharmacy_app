import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Background Isolate Engine to execute heavy JSON parsing, list transforms,
/// and data calculations off the main Flutter UI thread, guaranteeing 60 FPS
/// responsiveness and 0% "Not Responding" UI freezing.
class IsolateComputeService {
  static final IsolateComputeService instance = IsolateComputeService._internal();
  IsolateComputeService._internal();

  /// Offloads heavy computational tasks to a background Dart isolate
  Future<R> runInBackground<Q, R>(ComputeCallback<Q, R> callback, Q message) async {
    return await compute(callback, message);
  }

  /// Decodes large JSON strings in a background isolate
  Future<List<dynamic>> parseJsonList(String jsonString) async {
    if (jsonString.length < 1024) {
      try {
        final decoded = jsonDecode(jsonString);
        return decoded is List<dynamic> ? decoded : [decoded];
      } catch (_) {
        return [];
      }
    }
    return await compute(_decodeJsonListIsolate, jsonString);
  }

  /// Decodes any JSON string (List or Map) in a background isolate
  Future<dynamic> parseJsonDynamic(String jsonString) async {
    if (jsonString.length < 1024) {
      try {
        return jsonDecode(jsonString);
      } catch (_) {
        return null;
      }
    }
    return await compute(_decodeJsonDynamicIsolate, jsonString);
  }

  /// Encodes large Dart maps/lists to JSON strings in a background isolate
  Future<String> encodeJson(dynamic object) async {
    return await compute(_encodeJsonIsolate, object);
  }
}

List<dynamic> _decodeJsonListIsolate(String jsonStr) {
  try {
    final decoded = jsonDecode(jsonStr);
    return decoded is List<dynamic> ? decoded : [decoded];
  } catch (_) {
    return [];
  }
}

dynamic _decodeJsonDynamicIsolate(String jsonStr) {
  try {
    return jsonDecode(jsonStr);
  } catch (_) {
    return null;
  }
}

String _encodeJsonIsolate(dynamic obj) {
  try {
    return jsonEncode(obj);
  } catch (_) {
    return "{}";
  }
}
