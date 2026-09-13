import 'package:flutter/material.dart';

class SmartSearchableDropdown extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: initialValue),
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return options;
        }
        final q = textEditingValue.text.toLowerCase().trim();
        final startsWith = options.where((String option) => option.toLowerCase().startsWith(q)).toList();
        final contains = options.where((String option) => !option.toLowerCase().startsWith(q) && option.toLowerCase().contains(q)).toList();
        return [...startsWith, ...contains];
      },
      onSelected: (String selection) {
        FocusScope.of(context).unfocus();
        onSelected(selection);
      },
      fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10, 
            fontWeight: FontWeight.w900, 
            color: textColor ?? Colors.black87
          ),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 2, horizontal: 1),
            border: InputBorder.none,
          ),
        );
      },
    );
  }
}
