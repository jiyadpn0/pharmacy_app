import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/pharmacy_provider.dart';
import 'app_sounds.dart';

class AppDialogs {
  // ---> THE FIX: The Global Exception Cleaner <---
  static String _cleanErrorMessage(String msg) {
    String clean = msg;
    
    // 1. Remove the standard Exception prefix
    clean = clean.replaceAll('Exception: ', '');
    
    // 2. Hide raw SQL queries if a database crash happens
    if (clean.contains('Causing statement:')) {
      clean = clean.split('Causing statement:').first;
    }
    
    // 3. Strip out ugly SQLite database tags
    clean = clean.replaceAll(RegExp(r'SqfliteFfiException\(.*?\)[:]?', caseSensitive: false, dotAll: true), '');
    clean = clean.replaceAll(RegExp(r'DatabaseException\(.*?\)[:]?', caseSensitive: false, dotAll: true), '');
    clean = clean.replaceAll(RegExp(r'SqliteException\(\d+\):', caseSensitive: false), '');
    clean = clean.replaceAll('SQL logic error (code 1)', '');
    clean = clean.replaceAll('while preparing statement,', '');
    
    // 4. Return the clean, human-readable string
    return clean.trim();
  }

  static void showLoadingDialog(BuildContext context, {String message = "Processing..."}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
            try {
              Provider.of<PharmacyProvider>(context, listen: false).cancelImport();
            } catch (_) {}
            if (Navigator.canPop(ctx)) Navigator.pop(ctx);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Center(
          child: Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(message, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  const Text("Press ESC to cancel / go back", style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static void showFastDialog({
    required BuildContext context,
    required String title,
    required String content,
    bool isSuccess = false,
  }) {
    if (!isSuccess) AppSounds.playError();
    
    final cleanContent = _cleanErrorMessage(content);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.pop(ctx);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: AlertDialog(
          title: Row(
            children: [
              Text(isSuccess ? "✅" : "⚠️"),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isSuccess ? "✨" : "❌", style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(child: Text(cleanContent, style: const TextStyle(fontSize: 14))),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: isSuccess ? Colors.green : Colors.blueGrey.shade700,
                foregroundColor: Colors.white,
              ),
              child: const Text("OK (ENTER/ESC)", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  static Future<bool?> showConfirmDialog({
    required BuildContext context,
    required String title,
    required String content,
    String yesLabel = "YES",
    String noLabel = "NO",
    bool isDangerous = false,
  }) {
    AppSounds.playError();
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter) {
              Navigator.pop(ctx, true);
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.pop(ctx, false);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: AlertDialog(
          title: Row(
            children: [
              const Text("⚠️"),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("❓", style: TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(child: Text(content)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text("$noLabel (ESC)", style: const TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDangerous ? Colors.red : Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: Text("$yesLabel (ENTER)", style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
