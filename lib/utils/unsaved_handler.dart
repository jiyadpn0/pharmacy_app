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

  static void register(String tabTitle, UnsavedHandler handler) {
    _handlers[tabTitle] = handler;
  }

  static void unregister(String tabTitle) {
    _handlers.remove(tabTitle);
  }

  static UnsavedHandler? getHandler(String tabTitle) {
    return _handlers[tabTitle];
  }

  /// Checks if a tab title belongs to one of the 6 entry screens
  static bool isEntryTab(String title) {
    final upper = title.trim().toUpperCase();
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

/// Shows the 3-Option Unsaved Changes confirmation dialog:
/// [ SHOW THE DIFFERENCE ] | [ Discard ] | [ Cancel ]
Future<UnsavedDialogResult?> showUnsavedChangesDialog(BuildContext context) {
  final FocusNode diffFocusNode = FocusNode();

  return showDialog<UnsavedDialogResult>(
    context: context,
    builder: (ctx) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        diffFocusNode.requestFocus();
      });

      return AlertDialog(
        title: const Text("Unsaved Changes", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("Some data are not saved, are you sure to delete?"),
        actions: [
          ElevatedButton(
            focusNode: diffFocusNode,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (ctx.mounted && Navigator.of(ctx).canPop()) {
                Navigator.of(ctx).pop(UnsavedDialogResult.showDifference);
              }
            },
            child: const Text("SHOW THE DIFFERENCE", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (ctx.mounted && Navigator.of(ctx).canPop()) {
                Navigator.of(ctx).pop(UnsavedDialogResult.discard);
              }
            },
            child: const Text("Discard"),
          ),
          TextButton(
            onPressed: () {
              if (ctx.mounted && Navigator.of(ctx).canPop()) {
                Navigator.of(ctx).pop(UnsavedDialogResult.cancel);
              }
            },
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
        ],
      );
    },
  );
}
