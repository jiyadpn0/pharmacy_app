import 'package:flutter/material.dart';

class DraggableModal extends StatefulWidget {
  final Widget child;
  const DraggableModal({super.key, required this.child});

  @override
  State<DraggableModal> createState() => _DraggableModalState();
}

class _DraggableModalState extends State<DraggableModal> {
  Offset _offset = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Transform.translate(
      offset: _offset,
      child: Stack(
        children: [
          // 1. The Actual Dialog
          widget.child,
          
          // 2. An invisible "Drag Handle" placed exactly over the title bar
          Positioned(
            top: 0, left: 0, right: 0, height: 50, // Matches WindowControlsBar height
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanUpdate: (details) {
                setState(() {
                  double newDx = _offset.dx + details.delta.dx;
                  double newDy = _offset.dy + details.delta.dy;

                  // THE ANTI-TRAP BOUNCER: Prevents dragging off-screen!
                  if (newDy < -100) newDy = -100; // Top limit
                  if (newDy > screenSize.height - 150) newDy = screenSize.height - 150; // Bottom limit
                  if (newDx > screenSize.width - 200) newDx = screenSize.width - 200; // Right limit
                  if (newDx < -screenSize.width + 200) newDx = -screenSize.width + 200; // Left limit

                  _offset = Offset(newDx, newDy);
                });
              },
              child: Container(color: Colors.transparent),
            ),
          ),
        ],
      ),
    );
  }
}
