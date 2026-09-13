import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../providers/pharmacy_provider.dart';
import '../utils/theme_constants.dart';

class PinUnlockDialog {
  /// Returns [true] if the PIN is correct, [false] if canceled or incorrect.
  static Future<bool> show(
      BuildContext context,
      PharmacyProvider provider, {
        String title = "Authentication Required",
        String message = "Enter Master Password to proceed.",
      }) async {

    // If no password is set in the system yet, show a setup warning with direct navigation
    if (provider.masterPassword.isEmpty) {
      bool? goToSettings = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.lock_reset_rounded, color: Colors.orange),
              SizedBox(width: 10),
              Text("Security PIN Required"),
            ],
          ),
          content: const Text(
              "This action is protected by a Security PIN, but no Master PIN is currently set.\n\nWould you like to open Security Settings to set up a Master PIN now?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text("OPEN SETTINGS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (goToSettings == true && context.mounted) {
        Provider.of<AppProvider>(context, listen: false).openSecuritySettings();
      }
      return false;
    }

    final TextEditingController pinCtrl = TextEditingController();
    String errorText = "";

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Force them to enter PIN or hit Cancel
      builder: (ctx) {
        return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: [
                    const Icon(Icons.lock_person_rounded, color: Colors.redAccent),
                    const SizedBox(width: 10),
                    Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message, style: TextStyle(color: Colors.grey.shade700, fontSize: 14)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: pinCtrl,
                      obscureText: true,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: "Enter PIN / Password",
                        errorText: errorText.isNotEmpty ? errorText : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        prefixIcon: const Icon(Icons.key_rounded, color: Colors.blueGrey),
                      ),
                      onSubmitted: (value) {
                        // Allow hitting "Enter" on keyboard to submit using salted SHA-256 verification
                        if (provider.verifyMasterPin(value)) {
                          Navigator.pop(ctx, true);
                        } else {
                          setState(() { errorText = "Incorrect password"; });
                          pinCtrl.clear();
                        }
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text("CANCEL", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                    ),
                    onPressed: () {
                      if (provider.verifyMasterPin(pinCtrl.text)) {
                        Navigator.pop(ctx, true); // Success!
                      } else {
                        setState(() { errorText = "Incorrect password"; });
                        pinCtrl.clear();
                      }
                    },
                    child: const Text("UNLOCK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  )
                ],
              );
            }
        );
      },
    ) ?? false; // If they tap completely outside (if barrier isn't perfectly respected), default to false
  }
}
