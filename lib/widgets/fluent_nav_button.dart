import 'package:flutter/material.dart';

/// A modern, tactile, fluent navigation button designed for desktop and touch screens.
/// Features smooth hover, springy tap scale animations, accessible hit testing, and busy/disabled states.
class FluentNavButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final bool isBusy;
  final double width;
  final double height;
  final Color? activeColor;
  final Color? activeBgColor;

  const FluentNavButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip = "",
    this.isBusy = false,
    this.width = 24.0,
    this.height = 26.0,
    this.activeColor,
    this.activeBgColor,
  });

  @override
  State<FluentNavButton> createState() => _FluentNavButtonState();
}

class _FluentNavButtonState extends State<FluentNavButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = widget.onTap != null && !widget.isBusy;
    final primaryColor = widget.activeColor ?? const Color(0xFF2563EB); // Royal Blue
    final hoverBg = widget.activeBgColor ?? const Color(0xFFEFF6FF); // Light Blue 50

    Widget buttonCore = MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onEnter: (_) {
        if (mounted && isEnabled) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _isHovered = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: isEnabled ? (_) {
          if (mounted) setState(() => _isPressed = true);
        } : null,
        onTapUp: isEnabled ? (_) {
          if (mounted) setState(() => _isPressed = false);
        } : null,
        onTapCancel: () {
          if (mounted) setState(() => _isPressed = false);
        },
        onTap: isEnabled ? widget.onTap : null,
        child: AnimatedScale(
          scale: _isPressed ? 0.90 : (_isHovered && isEnabled ? 1.05 : 1.0),
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: widget.width,
            height: widget.height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: !isEnabled
                  ? Colors.grey.shade100
                  : (_isHovered ? hoverBg : Colors.grey.shade100),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: !isEnabled
                    ? Colors.grey.shade300
                    : (_isHovered ? primaryColor.withValues(alpha: 0.8) : Colors.grey.shade400),
                width: _isHovered && isEnabled ? 1.2 : 1.0,
              ),
              boxShadow: _isHovered && isEnabled
                  ? [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.16),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: widget.isBusy
                ? SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.grey.shade500),
                    ),
                  )
                : Icon(
                    widget.icon,
                    size: 15,
                    color: !isEnabled
                        ? Colors.grey.shade400
                        : (_isHovered ? primaryColor : Colors.grey.shade800),
                  ),
          ),
        ),
      ),
    );

    if (widget.tooltip.isNotEmpty) {
      return Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: buttonCore,
      );
    }
    return buttonCore;
  }
}
