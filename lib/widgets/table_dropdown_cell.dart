import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TableDropdownCell extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onDropdownTrigger;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final InputDecoration? decoration;
  final TextStyle? style;
  final TextAlign textAlign;

  const TableDropdownCell({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onDropdownTrigger,
    this.onChanged,
    this.onSubmitted,
    this.decoration,
    this.style,
    this.textAlign = TextAlign.left,
  });

  @override
  State<TableDropdownCell> createState() => _TableDropdownCellState();
}

class _TableDropdownCellState extends State<TableDropdownCell> {
  @override
  void initState() {
    super.initState();
    // Trigger dropdown instantly when cell receives focus for the first time
    widget.focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (widget.focusNode.hasFocus) {
      widget.onDropdownTrigger();
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        // Open dropdown on Arrow Down or Enter keypress
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            widget.onDropdownTrigger();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        style: widget.style,
        textAlign: widget.textAlign,
        onSubmitted: widget.onSubmitted,
        onTap: () {
          // Force open on mouse click
          widget.onDropdownTrigger();
        },
        onChanged: (value) {
          // Filter list dynamically as user types
          widget.onDropdownTrigger();
          if (widget.onChanged != null) {
            widget.onChanged!(value);
          }
        },
        decoration: widget.decoration ??
            const InputDecoration(
              border: InputBorder.none,
              isDense: true,
            ),
      ),
    );
  }
}
