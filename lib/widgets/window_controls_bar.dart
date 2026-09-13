import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class WindowControlsBar extends StatelessWidget {
  final String? title;
  final VoidCallback? onClose;
  final VoidCallback? onMinimize;
  final VoidCallback? onMaximize;
  final Color backgroundColor;
  final BorderRadiusGeometry? borderRadius;

  // NEW PARAMETERS FOR UNIFIED TITLE BAR
  final double height;
  final Widget? titleWidget; // For your PHARMA PRO logo
  final Widget? navigationMenu; // For MASTER, ORDER BOOK, etc.
  final Widget? trailingActions; // For Search, Settings, Profile

  const WindowControlsBar({
    super.key,
    this.title,
    this.onClose,
    this.onMinimize,
    this.onMaximize,
    this.backgroundColor = const Color(0xFF161E2E), // Deep dark blue to match your theme
    this.borderRadius,
    this.height = 32.0, // Defaults to 32 for dialogs. Pass 48 or 56 for the main screen.
    this.titleWidget,
    this.navigationMenu,
    this.trailingActions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: borderRadius,
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          // 1. LEFT SIDE: Logo (Fixed)
          const SizedBox(width: 16),
          if (titleWidget != null) titleWidget!,
          if (title != null && titleWidget == null)
            Text(
              title!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          
          // 2. MIDDLE: Drag Area + Menus (Flexible & Scrollable)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (details) {
                if (onClose == null) windowManager.startDragging();
              },
              onDoubleTap: () async {
                if (onClose != null) return;
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              child: Container(
                color: Colors.transparent, // CRITICAL: Makes the empty space draggable
                padding: const EdgeInsets.symmetric(horizontal: 24),
                alignment: Alignment.centerLeft,
                child: navigationMenu != null
                    ? SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [navigationMenu!],
                        ),
                      )
                    : const SizedBox.expand(), // Ensures the handle fills all available space
              ),
            ),
          ),

          // 3. RIGHT SIDE: Actions + OS Window Controls (Flexible to avoid overflow)
          if (trailingActions != null)
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: trailingActions!,
              ),
            ),
          const SizedBox(width: 8),

          if (onClose == null) ...[
            _buildBtn(Icons.remove, hoverColor: Colors.white24, onTap: () => windowManager.minimize()),

            _buildBtn(Icons.filter_none, hoverColor: Colors.white24, size: 14, onTap: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            }),
          ],

          _buildBtn(
            Icons.close,
            hoverColor: const Color(0xFFE81123),
            isClose: true,
            onTap: onClose ?? () => windowManager.close(),
          ),
        ],
      ),
    );
  }

  Widget _buildBtn(IconData icon, {required Color hoverColor, required VoidCallback onTap, double size = 18, bool isClose = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: hoverColor,
        child: Container(
          width: 48,
          height: double.infinity,
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.white, size: size),
        ),
      ),
    );
  }
}