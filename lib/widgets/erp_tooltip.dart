import 'package:flutter/material.dart';

class ERPTooltip extends StatefulWidget {
  final String message;
  final Widget child;

  const ERPTooltip({super.key, required this.message, required this.child});

  @override
  State<ERPTooltip> createState() => _ERPTooltipState();
}

class _ERPTooltipState extends State<ERPTooltip> {
  OverlayEntry? _overlayEntry;

  void _showTooltip(BuildContext context) {
    _hideTooltip();
    if (widget.message.isEmpty || !mounted) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: offset.dx.clamp(8.0, MediaQuery.of(context).size.width - 200.0),
        top: offset.dy > 40 ? offset.dy - 32 : offset.dy + size.height + 4,
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                widget.message,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final overlay = Overlay.maybeOf(context);
    if (overlay != null && _overlayEntry != null) {
      overlay.insert(_overlayEntry!);
    }
  }

  void _hideTooltip() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _hideTooltip();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.message.isEmpty) return widget.child;

    return MouseRegion(
      onEnter: (_) => _showTooltip(context),
      onExit: (_) => _hideTooltip(),
      child: widget.child,
    );
  }
}

