import 'package:flutter/material.dart';

/// Contract for entry screens to manage unsaved changes & red box highlighting
abstract class UnsavedHandler {
  /// Checks whether there are unsaved changes:
  /// - New Entry: Total > 1.0
  /// - Saved Entry: Data modified (isDirty)
  bool hasUnsavedChanges();

  /// Highlights changed/modified fields/rows in RED
  void showDifferences();
}

/// Global registry mapping tab titles to their active UnsavedHandler state
class UnsavedChangesRegistry {
  static final Map<String, UnsavedHandler> _handlers = {};

  static String normalizeTitle(String title) {
    String clean = title.trim().toUpperCase();
    // Remove (#2), (#3) multi-tab suffixes
    clean = clean.replaceAll(RegExp(r'\s*\(\#\d+\)$'), '');
    if (clean.startsWith("STOCK ADJUSTMENT")) {
      return "STOCK ADJUSTMENT";
    }
    return clean;
  }

  static void register(String tabTitle, UnsavedHandler handler) {
    _handlers[normalizeTitle(tabTitle)] = handler;
  }

  static void unregister(String tabTitle) {
    _handlers.remove(normalizeTitle(tabTitle));
  }

  static UnsavedHandler? getHandler(String tabTitle) {
    return _handlers[normalizeTitle(tabTitle)];
  }

  /// Checks if a tab title belongs to one of the 6 entry screens
  static bool isEntryTab(String title) {
    final upper = normalizeTitle(title);
    return upper.startsWith("SALES ENTRY") ||
        upper.startsWith("PURCHASE ENTRY") ||
        upper.startsWith("PURCHASE RETURN") ||
        upper.startsWith("SALES RETURN") ||
        upper.startsWith("DAMAGE ENTRY") ||
        upper.startsWith("STOCK ADJUSTMENT");
  }
}

/// Enum for user response from the Unsaved Changes confirmation dialog
enum UnsavedDialogResult {
  showDifference,
  discard,
  cancel,
}

/// Shows the Unsaved Changes confirmation dialog:
/// [ Discard Changes ] | [ Keep Editing ]
Future<UnsavedDialogResult?> showUnsavedChangesDialog(BuildContext context) {
  return showDialog<UnsavedDialogResult>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 28),
            SizedBox(width: 8),
            Text("Unsaved Changes Detected", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Text(
          "You have unsaved modifications in this entry. Leaving or closing now will discard your changes.\n\nDo you want to discard your changes?",
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          OutlinedButton(
            onPressed: () {
              if (ctx.mounted && Navigator.of(ctx).canPop()) {
                Navigator.of(ctx).pop(UnsavedDialogResult.cancel);
              }
            },
            child: const Text("Keep Editing", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (ctx.mounted && Navigator.of(ctx).canPop()) {
                Navigator.of(ctx).pop(UnsavedDialogResult.discard);
              }
            },
            child: const Text("Discard Changes", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      );
    },
  );
}
