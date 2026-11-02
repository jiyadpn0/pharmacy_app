import 'package:flutter/material.dart';

class RankingFormulaHeader extends StatelessWidget {
  final String title;
  final Color mainColor;
  final Color innerColor;
  final List<Map<String, dynamic>> rules;
  final TextEditingController formulaCtrl;
  final bool isValid;
  final ValueChanged<String> onFormulaChanged;
  final VoidCallback onFormulaSaved;
  final VoidCallback onOpenRules;
  final double colWidth;

  const RankingFormulaHeader({
    super.key,
    required this.title,
    required this.mainColor,
    required this.innerColor,
    required this.rules,
    required this.formulaCtrl,
    this.isValid = true,
    required this.onFormulaChanged,
    required this.onFormulaSaved,
    required this.onOpenRules,
    this.colWidth = 110.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: colWidth,
      margin: const EdgeInsets.symmetric(horizontal: 1.0),
      padding: const EdgeInsets.all(4.0),
      decoration: BoxDecoration(
        color: mainColor.withAlpha(25),
        border: Border.all(color: mainColor, width: 1.5),
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: mainColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 24,
            child: TextField(
              controller: formulaCtrl,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isValid ? Colors.black : Colors.red,
              ),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                filled: true,
                fillColor: innerColor.withAlpha(30),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(3),
                  borderSide: BorderSide(color: mainColor),
                ),
              ),
              onChanged: onFormulaChanged,
              onSubmitted: (_) => onFormulaSaved(),
            ),
          ),
          const SizedBox(height: 2),
          InkWell(
            onTap: onOpenRules,
            child: Text(
              rules.isEmpty ? "+ Rules" : "${rules.length} Rules",
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: mainColor,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
