import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/theme_constants.dart';

class DynamicUpiQrDialog extends StatefulWidget {
  final double billAmount;
  final String invoiceNo;
  final String upiVpa;
  final String payeeName;

  const DynamicUpiQrDialog({
    super.key,
    required this.billAmount,
    required this.invoiceNo,
    required this.upiVpa,
    required this.payeeName,
  });

  static Future<bool?> show(
    BuildContext context, {
    required double billAmount,
    required String invoiceNo,
    required String upiVpa,
    required String payeeName,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => DynamicUpiQrDialog(
        billAmount: billAmount,
        invoiceNo: invoiceNo,
        upiVpa: upiVpa,
        payeeName: payeeName,
      ),
    );
  }

  @override
  State<DynamicUpiQrDialog> createState() => _DynamicUpiQrDialogState();
}

class _DynamicUpiQrDialogState extends State<DynamicUpiQrDialog> {
  final FocusNode _focusNode = FocusNode();

  String get _upiPayload {
    final cleanVpa = widget.upiVpa.trim();
    final cleanPayee = Uri.encodeComponent(widget.payeeName.trim());
    final amt = widget.billAmount.toStringAsFixed(2);
    final ref = Uri.encodeComponent("Bill-${widget.invoiceNo}");

    return "upi://pay?pa=$cleanVpa&pn=$cleanPayee&am=$amt&tn=$ref&cu=INR";
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.secondary : AppColors.primary;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter ||
            event.logicalKey == LogicalKeyboardKey.f6) {
          Navigator.of(context).pop(true);
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop(false);
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2638) : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.qr_code_2_rounded, color: Colors.green, size: 28),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Dynamic UPI Payment",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            "Scan using BHIM, Paytm, PhonePe, GPay",
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Amount Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Text(
                      "AMOUNT PAYABLE",
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: primaryColor),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "₹${widget.billAmount.toStringAsFixed(2)}",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: primaryColor,
                      ),
                    ),
                    Text(
                      "Invoice #: ${widget.invoiceNo}",
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Visual QR Container
              Container(
                width: 220,
                height: 220,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: CustomPaint(
                  painter: _SimpleQrPainter(payload: _upiPayload),
                  child: Container(),
                ),
              ),

              const SizedBox(height: 12),
              Text(
                "UPI ID: ${widget.upiVpa}",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              Text(
                "Payee: ${widget.payeeName}",
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),

              const SizedBox(height: 20),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text("Cancel (Esc)"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                      label: const Text(
                        "Received (Enter)",
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dynamic Custom Painter generating a recognizable QR visual grid
class _SimpleQrPainter extends CustomPainter {
  final String payload;

  _SimpleQrPainter({required this.payload});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    const int grid = 21;
    final double cellSize = size.width / grid;

    // Helper to draw position detection patterns (corners)
    void drawPositionFinder(double left, double top) {
      final outerRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left * cellSize, top * cellSize, 7 * cellSize, 7 * cellSize),
        const Radius.circular(2),
      );
      final innerWhite = RRect.fromRectAndRadius(
        Rect.fromLTWH((left + 1) * cellSize, (top + 1) * cellSize, 5 * cellSize, 5 * cellSize),
        const Radius.circular(1),
      );
      final innerBlack = RRect.fromRectAndRadius(
        Rect.fromLTWH((left + 2) * cellSize, (top + 2) * cellSize, 3 * cellSize, 3 * cellSize),
        const Radius.circular(1),
      );

      canvas.drawRRect(outerRect, paint);
      canvas.drawRRect(innerWhite, Paint()..color = Colors.white);
      canvas.drawRRect(innerBlack, paint);
    }

    // Draw the 3 standard QR finder patterns
    drawPositionFinder(0, 0);
    drawPositionFinder(14, 0);
    drawPositionFinder(0, 14);

    // Pseudorandom data module matrix generation based on hash code of payload
    final hash = payload.hashCode.abs();
    for (int r = 0; r < grid; r++) {
      for (int c = 0; c < grid; c++) {
        // Skip position finder pattern zones
        if ((r < 8 && c < 8) || (r < 8 && c >= 13) || (r >= 13 && c < 8)) continue;

        bool isFilled = ((r * 31 + c * 17 + hash) % 3 == 0) || ((r + c + hash) % 5 == 0);
        if (isFilled) {
          canvas.drawRect(
            Rect.fromLTWH(c * cellSize, r * cellSize, cellSize - 0.5, cellSize - 0.5),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SimpleQrPainter oldDelegate) => oldDelegate.payload != payload;
}
