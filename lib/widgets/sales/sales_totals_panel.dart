import 'package:flutter/material.dart';

/// Clean, responsive widget displaying invoice totals, tax summaries, and grand total.
class SalesTotalsPanel extends StatelessWidget {
  final double subTotal;
  final double gstAmount;
  final double discountAmount;
  final double roundOff;
  final double grandTotal;
  final int itemCount;

  const SalesTotalsPanel({
    super.key,
    required this.subTotal,
    required this.gstAmount,
    required this.discountAmount,
    required this.roundOff,
    required this.grandTotal,
    required this.itemCount,
  });

  Widget _buildSummaryRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isBold ? 14 : 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color ?? Colors.grey.shade700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isBold ? 14 : 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "BILL SUMMARY",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 0.5),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "$itemCount Items",
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                ),
              ),
            ],
          ),
          const Divider(height: 16),
          _buildSummaryRow("Subtotal", "₹${subTotal.toStringAsFixed(2)}"),
          _buildSummaryRow("GST Tax", "₹${gstAmount.toStringAsFixed(2)}"),
          if (discountAmount > 0)
            _buildSummaryRow("Discount", "-₹${discountAmount.toStringAsFixed(2)}", color: Colors.green.shade700),
          if (roundOff != 0)
            _buildSummaryRow("Round Off", "₹${roundOff.toStringAsFixed(2)}"),
          const Divider(height: 16),
          _buildSummaryRow(
            "GRAND TOTAL",
            "₹${grandTotal.toStringAsFixed(2)}",
            isBold: true,
            color: Colors.blue.shade900,
          ),
        ],
      ),
    );
  }
}
