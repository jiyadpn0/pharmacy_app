import 'package:flutter/material.dart';

class AppStrictAutocomplete extends StatefulWidget {
  final String? label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final FocusNode? nextFocus;
  final List<String> Function()? getItems;
  final List<String>? items;
  final String defaultOption;
  final Function(String) onValueChanged;
  final bool isStrict;
  final double height;
  final String? hintText;
  final TextStyle? style;

  const AppStrictAutocomplete({
    super.key,
    this.label,
    required this.controller,
    required this.focusNode,
    this.nextFocus,
    this.getItems,
    this.items,
    this.defaultOption = "",
    required this.onValueChanged,
    this.isStrict = true,
    this.height = 32.0,
    this.hintText,
    this.style,
  });

  @override
  State<AppStrictAutocomplete> createState() => _AppStrictAutocompleteState();
}

class _AppStrictAutocompleteState extends State<AppStrictAutocomplete> {
  String? _lastHighlightedOption;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(AppStrictAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (widget.focusNode.hasFocus) {
      if (widget.controller.text.isNotEmpty) {
        widget.controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.controller.text.length,
        );
      }
    } else {
      _commitSelectionOrClear();
    }
  }

  bool _isPlaceholder(String val) {
    final v = val.trim().toLowerCase();
    return v.isEmpty || v.startsWith("select ") || v == "select";
  }

  List<String> _getAllItems() {
    if (widget.getItems != null) {
      return widget.getItems!();
    }
    return widget.items ?? [];
  }

  List<String> _getValidItems() {
    final allItems = _getAllItems();
    return allItems.where((item) => !_isPlaceholder(item)).toList();
  }

  void _commitSelectionOrClear() {
    final currentText = widget.controller.text.trim();
    final validItems = _getValidItems();

    // 1. Text is empty or placeholder
    if (currentText.isEmpty || _isPlaceholder(currentText)) {
      if (_lastHighlightedOption != null && !_isPlaceholder(_lastHighlightedOption!)) {
        widget.controller.text = _lastHighlightedOption!;
        widget.onValueChanged(_lastHighlightedOption!);
      } else {
        if (widget.controller.text.isNotEmpty && widget.controller.text != widget.defaultOption) {
          widget.controller.clear();
          widget.onValueChanged(widget.defaultOption);
        }
      }
      return;
    }

    // 2. Exact match check (case-insensitive)
    final exactMatch = validItems.firstWhere(
      (item) => item.toLowerCase() == currentText.toLowerCase(),
      orElse: () => "",
    );

    if (exactMatch.isNotEmpty) {
      if (widget.controller.text != exactMatch) {
        widget.controller.text = exactMatch;
      }
      widget.onValueChanged(exactMatch);
      return;
    }

    // 3. Partial query match
    final matches = validItems
        .where((item) => item.toLowerCase().contains(currentText.toLowerCase()))
        .toList();

    if (matches.isNotEmpty) {
      String chosen = matches.first;
      if (_lastHighlightedOption != null && matches.contains(_lastHighlightedOption)) {
        chosen = _lastHighlightedOption!;
      }
      widget.controller.text = chosen;
      widget.onValueChanged(chosen);
    } else {
      // 4. Invalid custom text -> clear to blank if strict mode
      if (widget.isStrict) {
        widget.controller.clear();
        widget.onValueChanged(widget.defaultOption);
      } else {
        // Flexible mode: keep user's custom text
        widget.onValueChanged(currentText);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final validItems = _getValidItems();
    final displayHint = widget.hintText ?? (widget.defaultOption.isEmpty ? "Select ${widget.label ?? ''}".trim() : widget.defaultOption);

    Widget fieldWidget = LayoutBuilder(
      builder: (context, constraints) {
        return RawAutocomplete<String>(
          textEditingController: widget.controller,
          focusNode: widget.focusNode,
          optionsBuilder: (TextEditingValue textEditingValue) {
            final text = textEditingValue.text.trim().toLowerCase();
            if (text.isEmpty || _isPlaceholder(text)) {
              return validItems.take(50);
            }
            final matches = validItems.where((g) => g.toLowerCase().contains(text)).toList();
            return matches.take(50);
          },
          onSelected: (String selection) {
            if (!_isPlaceholder(selection)) {
              widget.controller.text = selection;
              widget.onValueChanged(selection);
            } else {
              widget.controller.clear();
              widget.onValueChanged(widget.defaultOption);
            }
            if (widget.nextFocus != null) {
              widget.nextFocus!.requestFocus();
            }
          },
          fieldViewBuilder: (context, textController, fieldFocusNode, onFieldSubmitted) {
            return Container(
              height: widget.height,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: fieldFocusNode.hasFocus ? Colors.blue : Colors.grey.shade300,
                  width: fieldFocusNode.hasFocus ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: textController,
                      focusNode: fieldFocusNode,
                      style: widget.style ?? const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: displayHint,
                        hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onTap: () {
                        if (textController.text.isNotEmpty) {
                          textController.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: textController.text.length,
                          );
                        }
                      },
                      onChanged: (val) {
                        if (val.trim().isEmpty) {
                          _lastHighlightedOption = null;
                          widget.onValueChanged(widget.defaultOption);
                        }
                      },
                      onSubmitted: (_) {
                        _commitSelectionOrClear();
                        if (widget.nextFocus != null) {
                          widget.nextFocus!.requestFocus();
                        }
                      },
                    ),
                  ),
                  if (textController.text.isNotEmpty && textController.text != widget.defaultOption)
                    InkWell(
                      onTap: () {
                        textController.clear();
                        _lastHighlightedOption = null;
                        widget.onValueChanged(widget.defaultOption);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.close, size: 14, color: Colors.grey.shade600),
                      ),
                    ),
                  Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                ],
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final highlightedIndex = AutocompleteHighlightedOption.of(context);
            if (options.isNotEmpty) {
              if (highlightedIndex >= 0 && highlightedIndex < options.length) {
                _lastHighlightedOption = options.elementAt(highlightedIndex);
              } else {
                _lastHighlightedOption = options.first;
              }
            } else {
              _lastHighlightedOption = null;
            }

            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 6.0,
                borderRadius: BorderRadius.circular(6),
                color: Colors.white,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  width: constraints.maxWidth,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade100),
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      final isHighlighted = (highlightedIndex == index) || (highlightedIndex == -1 && index == 0);
                      return InkWell(
                        onTap: () => onSelected(option),
                        child: Container(
                          color: isHighlighted ? Colors.blue.shade50 : Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Text(
                            option,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w600,
                              color: isHighlighted ? Colors.blue.shade900 : Colors.black87,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (widget.label != null && widget.label!.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.label!,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade600),
          ),
          const SizedBox(height: 4),
          fieldWidget,
        ],
      );
    }

    return fieldWidget;
  }
}
