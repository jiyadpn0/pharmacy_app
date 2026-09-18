import 'package:flutter/material.dart';

class SmartSearchableDropdown extends StatefulWidget {
  final List<String> options;
  final String initialValue;
  final Function(String) onSelected;
  final bool isHeader;
  final Color? textColor;

  const SmartSearchableDropdown({
    super.key,
    required this.options,
    required this.initialValue,
    required this.onSelected,
    this.isHeader = false,
    this.textColor,
  });

  @override
  State<SmartSearchableDropdown> createState() => _SmartSearchableDropdownState();
}

class _SmartSearchableDropdownState extends State<SmartSearchableDropdown> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  int _highlightedIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant SmartSearchableDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue && _controller.text != widget.initialValue) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _resolveSelection();
    }
  }

  List<String> _getFilteredOptions(String text) {
    final cleanText = text.trim().toLowerCase();
    if (cleanText.isEmpty) {
      return widget.options;
    }
    final startsWith = widget.options.where((String option) => option.toLowerCase().startsWith(cleanText)).toList();
    final contains = widget.options.where((String option) => !option.toLowerCase().startsWith(cleanText) && option.toLowerCase().contains(cleanText)).toList();
    return [...startsWith, ...contains];
  }

  void _resolveSelection() {
    final currentText = _controller.text.trim();
    if (currentText.isEmpty) {
      _controller.text = "";
      widget.onSelected("");
      return;
    }

    final filtered = _getFilteredOptions(currentText);
    if (filtered.isNotEmpty) {
      int idx = _highlightedIndex;
      if (idx < 0 || idx >= filtered.length) {
        idx = 0;
      }
      final selectedOption = filtered[idx];
      _controller.text = selectedOption;
      widget.onSelected(selectedOption);
    } else {
      _controller.text = "";
      widget.onSelected("");
    }
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: _controller,
      focusNode: _focusNode,
      optionsBuilder: (TextEditingValue textEditingValue) {
        return _getFilteredOptions(textEditingValue.text);
      },
      onSelected: (String selection) {
        _controller.text = selection;
        widget.onSelected(selection);
        FocusScope.of(context).unfocus();
      },
      fieldViewBuilder: (context, textController, fieldFocusNode, onFieldSubmitted) {
        return TextField(
          controller: textController,
          focusNode: fieldFocusNode,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: widget.textColor ?? Colors.black87,
          ),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 2, horizontal: 1),
            border: InputBorder.none,
          ),
          onChanged: (val) {
            _highlightedIndex = 0;
          },
          onSubmitted: (_) {
            _resolveSelection();
            FocusScope.of(context).unfocus();
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final highlightedIndex = AutocompleteHighlightedOption.of(context);
        if (highlightedIndex >= 0 && highlightedIndex < options.length) {
          _highlightedIndex = highlightedIndex;
        }

        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4.0,
            color: Colors.white,
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, index) {
                final option = options.elementAt(index);
                final isHighlighted = AutocompleteHighlightedOption.of(context) == index;
                return InkWell(
                  onTap: () => onSelected(option),
                  child: Container(
                    color: isHighlighted ? Colors.blue.shade50 : Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text(
                      option,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
                        color: isHighlighted ? Colors.blue.shade900 : Colors.black87,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
