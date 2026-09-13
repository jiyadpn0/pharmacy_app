import 'package:flutter/material.dart';

class ERPTooltip extends StatelessWidget {
  final String message;
  final Widget child;

  const ERPTooltip({super.key, required this.message, required this.child});

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return child;

    return Tooltip(
      message: message,
      waitDuration: const Duration(milliseconds: 500),
      showDuration: const Duration(seconds: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      textStyle: const TextStyle(
        color: Colors.black87,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
      child: child,
    );
  }
}
