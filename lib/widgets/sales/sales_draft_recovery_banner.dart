import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/sales_draft_service.dart';

/// Interactive alert ribbon displayed at the top of the POS screen when an uncommitted
/// cart has been automatically recovered from disk after a crash or power cut.
class SalesDraftRecoveryBanner extends StatelessWidget {
  final SalesDraft draft;
  final VoidCallback onDiscard;
  final VoidCallback onContinue;

  const SalesDraftRecoveryBanner({
    super.key,
    required this.draft,
    required this.onDiscard,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy hh:mm a');
    final formattedTime = dateFormat.format(draft.savedAt);
    final totalVal = draft.subtotal;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF78350F), // amber-900
            Color(0xFF451A03), // amber-950
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.restore_page_rounded,
              color: Color(0xFFFCD34D), // amber-300
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      "⚡ UNCOMMITTED CART RESTORED",
                      style: TextStyle(
                        color: Color(0xFFFDE68A),
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        "${draft.itemCount} Items • ₹${totalVal.toStringAsFixed(2)} • Saved $formattedTime",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "An active cart from a previous session was auto-recovered after unexpected shutdown or crash. "
                  "Verify medicines, batches, and patient details before completing the sale.",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: onDiscard,
                icon: const Icon(Icons.delete_sweep_outlined, size: 16, color: Colors.redAccent),
                label: const Text(
                  "DISCARD DRAFT (Alt+D)",
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.redAccent, width: 1.2),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: onContinue,
                icon: const Icon(Icons.check_circle_rounded, size: 16),
                label: const Text(
                  "CONTINUE BILLING (Alt+C)",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706), // amber-600
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  elevation: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
