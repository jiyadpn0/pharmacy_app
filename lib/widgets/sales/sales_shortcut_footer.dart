import 'package:flutter/material.dart';

/// Single row widget for shortcut cheat sheet
class ShortcutRowWidget extends StatelessWidget {
  final String keyCombo;
  final String description;

  const ShortcutRowWidget(this.keyCombo, this.description, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Text(
              keyCombo,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueAccent),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog presenting all POS keyboard shortcuts
class SalesShortcutCheatSheetDialog extends StatelessWidget {
  const SalesShortcutCheatSheetDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const SalesShortcutCheatSheetDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.keyboard_outlined, size: 28, color: Colors.blueAccent),
                const SizedBox(width: 10),
                const Text("POS Hotkeys & Shortcuts Cheat-Sheet", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              ],
            ),
            const Divider(height: 16),
            SizedBox(
              height: 380,
              child: ListView(
                children: const [
                  ShortcutRowWidget("F1", "Show Hotkeys Cheat-Sheet"),
                  ShortcutRowWidget("Shift + F1 / Ctrl + N", "New Invoice / Reset Form"),
                  ShortcutRowWidget("F2", "Focus Patient / Customer Name"),
                  ShortcutRowWidget("F3", "Wholesale Stock Directory"),
                  ShortcutRowWidget("F4", "Jump to Product Item Grid"),
                  ShortcutRowWidget("F5", "Substitute Generic Salt Finder"),
                  ShortcutRowWidget("F6", "Dynamic UPI Payment QR Checkout"),
                  ShortcutRowWidget("F7", "Fast Save & Thermal Invoice Print"),
                  ShortcutRowWidget("F8", "Focus Cash Received Amount"),
                  ShortcutRowWidget("F9", "Invoice PDF Preview & Export"),
                  ShortcutRowWidget("F10", "Save Invoice / Edit Record"),
                  ShortcutRowWidget("F11", "Hold Billing Session & Switch Workspace"),
                  ShortcutRowWidget("F12", "Express Save & Print Bill"),
                  ShortcutRowWidget("Ctrl + 1", "Product Purchase History"),
                  ShortcutRowWidget("Ctrl + 2", "Product Sales History"),
                  ShortcutRowWidget("Ctrl + L", "Product Stock Movement Ledger"),
                  ShortcutRowWidget("Ctrl + Z", "Undo Last Grid Action"),
                  ShortcutRowWidget("Ctrl + Del", "Delete Selected Grid Row"),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Close (Esc)"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
