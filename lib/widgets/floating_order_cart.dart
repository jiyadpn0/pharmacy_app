import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/pharmacy_provider.dart';

class FloatingOrderCart extends StatefulWidget {
  const FloatingOrderCart({super.key});

  @override
  State<FloatingOrderCart> createState() => _FloatingOrderCartState();
}

class _FloatingOrderCartState extends State<FloatingOrderCart> {
  Offset? _position;
  bool _isDragging = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      double? x = prefs.getDouble('floating_cart_x');
      double? y = prefs.getDouble('floating_cart_y');
      if (x != null && y != null) {
        if (mounted) {
          setState(() {
            _position = Offset(x, y);
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _savePosition(Offset pos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('floating_cart_x', pos.dx);
      await prefs.setDouble('floating_cart_y', pos.dy);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final pharmacy = Provider.of<PharmacyProvider>(context);

    // Only render when Order Book is in minimized floating state
    if (!pharmacy.isOrderPanelMinimized) {
      return const SizedBox.shrink();
    }

    final screenSize = MediaQuery.of(context).size;

    // Set default initial position (top-right area, safely below titlebar)
    final double defaultX = (screenSize.width - 210.0).clamp(10.0, screenSize.width - 10.0);
    final double defaultY = 80.0;

    Offset currentPos = _position ?? Offset(defaultX, defaultY);

    // Ensure floating position is clamped within visible screen boundaries
    final double clampedX = currentPos.dx.clamp(10.0, (screenSize.width - 180.0).clamp(10.0, double.infinity));
    final double clampedY = currentPos.dy.clamp(40.0, (screenSize.height - 70.0).clamp(40.0, double.infinity));
    currentPos = Offset(clampedX, clampedY);

    final int totalCount = pharmacy.specialOrders.length +
        pharmacy.lowStockItems.length +
        pharmacy.customExtraOrderItems.length;

    return Positioned(
      left: currentPos.dx,
      top: currentPos.dy,
      child: GestureDetector(
        onPanStart: (_) {
          setState(() {
            _isDragging = true;
          });
        },
        onPanUpdate: (details) {
          setState(() {
            final newX = (currentPos.dx + details.delta.dx).clamp(10.0, (screenSize.width - 180.0).clamp(10.0, double.infinity));
            final newY = (currentPos.dy + details.delta.dy).clamp(40.0, (screenSize.height - 70.0).clamp(40.0, double.infinity));
            _position = Offset(newX, newY);
          });
        },
        onPanEnd: (_) {
          setState(() {
            _isDragging = false;
          });
          if (_position != null) {
            _savePosition(_position!);
          }
        },
        onTap: () {
          if (!_isDragging) {
            pharmacy.openOrderPanel();
          }
        },
        child: MouseRegion(
          cursor: _isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _isHovered ? Colors.tealAccent : Colors.teal.shade600,
                width: _isHovered ? 2.0 : 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.tealAccent.withValues(alpha: _isHovered ? 0.35 : 0.2),
                  blurRadius: _isHovered ? 12 : 8,
                  spreadRadius: 1,
                  offset: const Offset(0, 3),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag Grip
                const Icon(
                  Icons.drag_indicator_rounded,
                  color: Colors.white38,
                  size: 16,
                ),
                const SizedBox(width: 4),

                // Order Book Icon
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade900.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.style_rounded,
                    color: Colors.tealAccent,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 6),

                // Title
                const Text(
                  "ORDER BOOK",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),

                // Badge Counter
                if (totalCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade700,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      "$totalCount",
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],

                const SizedBox(width: 6),

                // Close Button
                InkWell(
                  onTap: () => pharmacy.closeOrderPanelCompletely(),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                      size: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
