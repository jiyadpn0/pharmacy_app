import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// An ERP-optimized TextField that supports Smart Boundary Caret Navigation (Workflow A).
///
/// Features:
/// 1. Tapping '<' Left Arrow when caret is at index 0 or when text is fully selected
///    triggers [onNavigatePrevious] to move focus to the previous column/cell.
/// 2. Tapping '>' Right Arrow when caret is at the end of text or when text is fully selected
///    triggers [onNavigateNext] to move focus to the next column/cell.
/// 3. While caret is inside text, '<' and '>' standardly move the caret character-by-character.
/// 4. Auto-selects all text on gaining focus if [autoSelectOnFocus] is true.
class ErpGridTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback? onNavigatePrevious;
  final VoidCallback? onNavigateNext;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final GestureTapCallback? onTap;
  final TextAlign textAlign;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final InputDecoration? decoration;
  final TextStyle? style;
  final TextCapitalization textCapitalization;
  final bool readOnly;
  final bool enabled;
  final bool autoSelectOnFocus;

  const ErpGridTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.onNavigatePrevious,
    this.onNavigateNext,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.textAlign = TextAlign.left,
    this.keyboardType,
    this.inputFormatters,
    this.decoration,
    this.style,
    this.textCapitalization = TextCapitalization.characters,
    this.readOnly = false,
    this.enabled = true,
    this.autoSelectOnFocus = true,
  });

  @override
  State<ErpGridTextField> createState() => _ErpGridTextFieldState();
}

class _ErpGridTextFieldState extends State<ErpGridTextField> {
  FocusNode? _internalFocusNode;
  FocusNode get _effectiveFocusNode => widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    try {
      _effectiveFocusNode.addListener(_handleFocusChange);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant ErpGridTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      final oldNode = oldWidget.focusNode ?? _internalFocusNode;
      if (oldNode != null) {
        try {
          oldNode.removeListener(_handleFocusChange);
        } catch (_) {}
      }
      try {
        _effectiveFocusNode.addListener(_handleFocusChange);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    try {
      _effectiveFocusNode.removeListener(_handleFocusChange);
    } catch (_) {}
    _internalFocusNode?.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    try {
      if (!mounted) return;
      if (_effectiveFocusNode.hasFocus && widget.autoSelectOnFocus && !widget.readOnly) {
        // Defer selection so Flutter finishes building focus
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            try {
              if (_effectiveFocusNode.hasFocus) {
                final txt = widget.controller.text.trim();
                if (txt.isEmpty || txt == "--/--") {
                  widget.controller.selection = const TextSelection.collapsed(offset: 0);
                } else {
                  widget.controller.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: widget.controller.text.length,
                  );
                }
              }
            } catch (_) {}
          }
        });
      }
    } catch (_) {}
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final text = widget.controller.text;
    final selection = widget.controller.selection;

    if (key == LogicalKeyboardKey.arrowLeft) {
      // 1. If text is empty -> jump instantly to previous cell
      if (text.isEmpty && widget.onNavigatePrevious != null) {
        widget.onNavigatePrevious!();
        return KeyEventResult.handled;
      }
      // 2. If entire text is highlighted -> collapse selection to start (index 0)
      if (selection.isValid && text.isNotEmpty && selection.baseOffset == 0 && selection.extentOffset == text.length) {
        widget.controller.selection = const TextSelection.collapsed(offset: 0);
        return KeyEventResult.handled;
      }
      // 3. If cursor is already collapsed at far-left start (index 0) -> jump to previous cell
      if (selection.isValid && selection.isCollapsed && selection.baseOffset == 0 && widget.onNavigatePrevious != null) {
        widget.onNavigatePrevious!();
        return KeyEventResult.handled;
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      // 1. If text is empty -> jump instantly to next cell
      if (text.isEmpty && widget.onNavigateNext != null) {
        widget.onNavigateNext!();
        return KeyEventResult.handled;
      }
      // 2. If entire text is highlighted -> collapse selection to end (text.length)
      if (selection.isValid && text.isNotEmpty && selection.baseOffset == 0 && selection.extentOffset == text.length) {
        widget.controller.selection = TextSelection.collapsed(offset: text.length);
        return KeyEventResult.handled;
      }
      // 3. If cursor is already collapsed at far-right end (text.length) -> jump to next cell
      if (selection.isValid && selection.isCollapsed && selection.baseOffset == text.length && widget.onNavigateNext != null) {
        widget.onNavigateNext!();
        return KeyEventResult.handled;
      }
    } else if (key == LogicalKeyboardKey.arrowUp && widget.onNavigateUp != null) {
      widget.onNavigateUp!();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown && widget.onNavigateDown != null) {
      widget.onNavigateDown!();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      final bool isFullySelected = selection.isValid &&
          text.isNotEmpty &&
          ((selection.baseOffset == 0 && selection.extentOffset == text.length) ||
           (selection.baseOffset == text.length && selection.extentOffset == 0));
      if (isFullySelected) {
        widget.controller.clear();
        if (widget.onChanged != null) {
          widget.onChanged!("");
        }
        return KeyEventResult.handled;
      }
    }

    // Allow native character-by-character cursor movement while inside text string
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: TextField(
        controller: widget.controller,
        focusNode: _effectiveFocusNode,
        textAlign: widget.textAlign,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.inputFormatters,
        decoration: widget.decoration ??
            const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            ),
        style: widget.style,
        textCapitalization: widget.textCapitalization,
        readOnly: widget.readOnly,
        enabled: widget.enabled,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        onTap: widget.onTap,
        cursorWidth: 2.0,
      ),
    );
  }
}
