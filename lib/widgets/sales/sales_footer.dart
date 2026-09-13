import 'package:flutter/material.dart';
import '../../utils/theme_constants.dart';

class SalesFooter extends StatelessWidget {
  final TextEditingController subTotalCtrl;
  final TextEditingController footerDiscPctCtrl;
  final TextEditingController footerDiscAmtCtrl;
  final TextEditingController roundOffCtrl;
  final TextEditingController netTotalCtrl;
  final TextEditingController rcvdAmtCtrl;
  final TextEditingController balanceCtrl;
  final FocusNode rcvdAmtFocus;
  final VoidCallback onSaveAndPrintPressed;
  final VoidCallback onResetPressed;

  const SalesFooter({
    super.key,
    required this.subTotalCtrl,
    required this.footerDiscPctCtrl,
    required this.footerDiscAmtCtrl,
    required this.roundOffCtrl,
    required this.netTotalCtrl,
    required this.rcvdAmtCtrl,
    required this.balanceCtrl,
    required this.rcvdAmtFocus,
    required this.onSaveAndPrintPressed,
    required this.onResetPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(top: BorderSide(color: c.border, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, -2),
          )
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // SUB-TOTAL
          _footerField(c, "Sub Total", subTotalCtrl, readOnly: true, width: 110),
          const SizedBox(width: 12),

          // DISCOUNT %
          _footerField(c, "Disc %", footerDiscPctCtrl, width: 70),
          const SizedBox(width: 8),

          // DISCOUNT AMT
          _footerField(c, "Disc ₹", footerDiscAmtCtrl, width: 90),
          const SizedBox(width: 12),

          // ROUND OFF
          _footerField(c, "Round Off", roundOffCtrl, readOnly: true, width: 80),
          const SizedBox(width: 16),

          // RECEIVED AMOUNT (CASH / F8)
          _footerField(c, "Received (F8)", rcvdAmtCtrl, focusNode: rcvdAmtFocus, width: 110, isHighlight: true),
          const SizedBox(width: 12),

          // CHANGE / BALANCE
          _footerField(c, "Balance / Change", balanceCtrl, readOnly: true, width: 120, isChange: true),

          const Spacer(),

          // NET GRAND TOTAL DISPLAY
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.shade900,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.shade900.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("NET AMOUNT", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: netTotalCtrl,
                  builder: (context, val, _) {
                    return Text(
                      "₹ ${val.text.isEmpty ? '0.00' : val.text}",
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // SAVE & PRINT CHECKOUT BUTTON
          ElevatedButton.icon(
            onPressed: onSaveAndPrintPressed,
            icon: const Icon(Icons.print_rounded, size: 18),
            label: const Text("PRINT & SAVE\n(F12)", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, height: 1.1)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footerField(
    AppThemeColors c,
    String label,
    TextEditingController controller, {
    FocusNode? focusNode,
    bool readOnly = false,
    double width = 100,
    bool isHighlight = false,
    bool isChange = false,
  }) {
    Color bg = readOnly 
        ? c.inputBg 
        : (isHighlight 
            ? (c.isDark ? Colors.amber.shade900.withValues(alpha: 0.3) : Colors.amber.shade50) 
            : (isChange ? (c.isDark ? Colors.blue.shade900.withValues(alpha: 0.3) : Colors.blue.shade50) : c.cardBg));
    Color border = isHighlight 
        ? Colors.amber.shade600 
        : (isChange ? Colors.blue.shade400 : c.border);

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: c.secondaryText)),
          const SizedBox(height: 3),
          Container(
            height: 34,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: border, width: isHighlight || isChange ? 1.5 : 1),
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              readOnly: readOnly,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: c.primaryText,
              ),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
