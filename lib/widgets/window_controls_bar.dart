import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class _TopBarScrollBehavior extends MaterialScrollBehavior {
  const _TopBarScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

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
    final borderDecoration = BoxDecoration(
      color: backgroundColor,
      borderRadius: borderRadius,
      border: Border(
        bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
      ),
    );

    final rowContent = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. LEFT ANCHOR: Title / Logo Widget (Anchored on far left, never flexed/squeezed/clipped)
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(width: 12),
            if (titleWidget != null)
              titleWidget!
            else if (title != null)
              Text(
                title!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),

        // 2. MIDDLE FLEXIBLE AREA: Takes ONLY remaining space between Left Logo and Right Window Controls
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
              color: Colors.transparent, // Draggable empty middle area
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Navigation Menus (if passed directly on title bar, e.g. main_dashboard.dart)
                  if (navigationMenu != null) ...[
                    Flexible(
                      child: ScrollConfiguration(
                        behavior: const _TopBarScrollBehavior(),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: navigationMenu!,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],

                  // Trailing Actions (Status & Action Badges): Uses only available middle space and scrolls if constrained
                  if (trailingActions != null)
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: ScrollConfiguration(
                          behavior: const _TopBarScrollBehavior(),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: trailingActions!,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        // 3. RIGHT ANCHOR: OS Window Controls (Anchored on far right)
        _buildWindowControls(),
      ],
    );

    return Container(
      height: height,
      decoration: borderDecoration,
      child: borderRadius != null
          ? ClipRRect(
              borderRadius: borderRadius!,
              child: rowContent,
            )
          : rowContent,
    );
  }

  Widget _buildWindowControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onClose == null) ...[
          _buildBtn(
            Icons.remove,
            hoverColor: Colors.white24,
            onTap: onMinimize ?? () => windowManager.minimize(),
          ),
          _buildBtn(
            Icons.filter_none,
            hoverColor: Colors.white24,
            size: 14,
            onTap: onMaximize ?? () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
        ],
        _buildBtn(
          Icons.close,
          hoverColor: const Color(0xFFE81123),
          isClose: true,
          onTap: onClose ?? () => windowManager.close(),
        ),
      ],
    );
  }

  Widget _buildBtn(
    IconData icon, {
    required Color hoverColor,
    required VoidCallback onTap,
    double size = 16,
    bool isClose = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: hoverColor,
        child: Container(
          width: 46,
          height: double.infinity,
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.white, size: size),
        ),
      ),
    );
  }
}