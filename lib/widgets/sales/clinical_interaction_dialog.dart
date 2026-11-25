import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/clinical_interaction_service.dart';

class ClinicalInteractionDialog extends StatefulWidget {
  final List<ClinicalInteractionWarning> warnings;

  const ClinicalInteractionDialog({
    super.key,
    required this.warnings,
  });

  static Future<bool> show(
    BuildContext context, {
    required List<ClinicalInteractionWarning> warnings,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ClinicalInteractionDialog(warnings: warnings),
    );
    return result ?? false;
  }

  @override
  State<ClinicalInteractionDialog> createState() => _ClinicalInteractionDialogState();
}

class _ClinicalInteractionDialogState extends State<ClinicalInteractionDialog> {
  final FocusNode _focusNode = FocusNode();
  int _selectedButtonIndex = 0; // 0 = Cancel/Modify (default safe), 1 = Acknowledge & Proceed

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop(false);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      setState(() => _selectedButtonIndex = 0);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      setState(() => _selectedButtonIndex = 1);
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_selectedButtonIndex == 0) {
        Navigator.of(context).pop(false);
      } else {
        Navigator.of(context).pop(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasSevere = widget.warnings.any((w) => w.severity == InteractionSeverity.severe);
    final Color headerColor = hasSevere ? Colors.red.shade700 : Colors.orange.shade800;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 8,
        child: Container(
          width: 650,
          constraints: const BoxConstraints(maxHeight: 550),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: headerColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasSevere ? "CLINICAL ALERT: DRUG-DRUG INTERACTION DETECTED" : "CLINICAL ADVISORY: POTENTIAL DRUG INTERACTION",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "${widget.warnings.length} concurrent medication interaction(s) found in current basket.",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Warnings List
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  shrinkWrap: true,
                  itemCount: widget.warnings.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) {
                    final w = widget.warnings[i];
                    final isCritical = w.severity == InteractionSeverity.severe;
                    final Color cardColor = isCritical ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB);
                    final Color borderColor = isCritical ? Colors.red.shade300 : Colors.amber.shade300;
                    final Color badgeBg = isCritical ? Colors.red.shade600 : Colors.orange.shade700;

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: badgeBg,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isCritical ? "CRITICAL RISK" : "MODERATE RISK",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  w.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    color: isCritical ? Colors.red.shade900 : Colors.brown.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Interacting drugs tag
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.medication_liquid_rounded, size: 16, color: Colors.blueGrey),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "${w.drugA} ⚡ ${w.drugB}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Impact description
                          Text(
                            "Clinical Impact: ${w.clinicalImpact}",
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade900,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 4),

                          // Recommendation
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.lightbulb_outline_rounded, size: 14, color: Colors.blue.shade700),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  "Action: ${w.recommendation}",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Action Buttons with Zero-Mouse Keyboard First hints
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border(top: BorderSide(color: Colors.grey.shade300)),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    const Text(
                      "[← / →] Navigate  |  [Enter] Select  |  [Esc] Cancel",
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: _selectedButtonIndex == 0 ? Colors.blue.shade50 : Colors.white,
                        side: BorderSide(
                          color: _selectedButtonIndex == 0 ? Colors.blue.shade700 : Colors.grey.shade400,
                          width: _selectedButtonIndex == 0 ? 2 : 1,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      child: const Text(
                        "MODIFY CART (Esc)",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black87),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedButtonIndex == 1 ? (hasSevere ? Colors.red.shade700 : Colors.amber.shade800) : Colors.grey.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      child: const Text(
                        "ACKNOWLEDGE & PROCEED",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
