import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pharmacy_provider.dart';
import '../models/validation_rule.dart';
import 'draggable_modal.dart';

/// Interactive Manager Widget for Dynamic Color Validation Rules across all Entry screens.
class ValidationRuleManagerWidget extends StatefulWidget {
  final bool isModal;
  final String initialEntryType;
  const ValidationRuleManagerWidget({super.key, this.isModal = false, this.initialEntryType = "PURCHASE"});

  @override
  State<ValidationRuleManagerWidget> createState() => _ValidationRuleManagerWidgetState();
}

class _ValidationRuleManagerWidgetState extends State<ValidationRuleManagerWidget> {
  late String _selectedEntryType;

  @override
  void initState() {
    super.initState();
    _selectedEntryType = widget.initialEntryType.toUpperCase();
  }

  static const List<Map<String, String>> entryCategories = [
    {"type": "PURCHASE", "label": "Purchase Entry", "icon": "📦"},
    {"type": "SALES", "label": "Sales Entry", "icon": "🛒"},
    {"type": "PURCHASE_RETURN", "label": "Purchase Return", "icon": "🔄"},
    {"type": "SALES_RETURN", "label": "Sales Return", "icon": "↩️"},
    {"type": "DAMAGE", "label": "Damage Entry", "icon": "⚠️"},
    {"type": "STOCK_ADJUSTMENT", "label": "Stock Adjustment", "icon": "📊"},
    {"type": "ORDER_BOOK", "label": "Order Book", "icon": "📋"},
  ];

  static const Map<String, List<String>> headingOptionsMap = {
    "PURCHASE": ["L.Cost / P.Rate", "P.Rate", "Disc %", "S.Disc %", "MRP", "Expiry (Months)", "Pack Size", "Gross", "Net", "GST %"],
    "SALES": ["Selling Price", "MRP", "Disc %", "S.Disc %", "L.Cost", "P.Rate", "Expiry (Months)", "Pack Size", "Gross", "Net"],
    "PURCHASE_RETURN": ["Return Rate", "P.Rate", "Expiry (Months)", "Pack Size", "Disc %", "Net"],
    "SALES_RETURN": ["Return Rate", "Sale Rate", "Expiry (Months)", "Pack Size", "Disc %", "Net"],
    "DAMAGE": ["Loose Cost", "Qty", "Expiry (Months)", "Pack Size", "Total"],
    "STOCK_ADJUSTMENT": ["Physical Qty", "Variance Qty", "Unit Cost", "Expiry (Months)", "Pack Size", "Total"],
    "ORDER_BOOK": ["1st Purchase (Days)", "Last Sale (Days)", "Current Stock", "Order Qty", "Purchase Rate", "MRP"],
  };

  static const List<String> operatorOptions = [">=", ">", "<=", "<", "=", "!="];

  static const Map<String, List<String>> compareHeadingOptionsMap = {
    "PURCHASE": ["MRP", "Prev P.Rate", "Master Pack", "L.Cost / P.Rate", "P.Rate", "Disc %", "S.Disc %"],
    "SALES": ["MRP", "L.Cost", "P.Rate", "Master Pack", "Disc %"],
    "PURCHASE_RETURN": ["P.Rate", "MRP", "Master Pack", "Disc %"],
    "SALES_RETURN": ["Sale Rate", "MRP", "Master Pack", "Disc %"],
    "DAMAGE": ["Shelf Stock", "Loose Cost"],
    "STOCK_ADJUSTMENT": ["System Stock", "Master Pack"],
    "ORDER_BOOK": ["Current Stock", "Reorder Level", "Max Level", "Order Qty"],
  };

  static const List<int> colorOptions = [
    0xFFEF4444, // Red
    0xFFFB8C00, // Orange
    0xFFF59E0B, // Amber
    0xFFFFD54F, // Yellow
    0xFF10B981, // Green
    0xFF0D9488, // Teal
    0xFF3B82F6, // Blue
    0xFF8B5CF6, // Purple
    0xFF000000, // Black
    0xFFFFFFFF, // White
  ];

  void _addNewRule(PharmacyProvider provider) {
    final fieldOpts = headingOptionsMap[_selectedEntryType] ?? headingOptionsMap["PURCHASE"]!;
    final newRule = ValidationRule(
      id: "rule_${DateTime.now().millisecondsSinceEpoch}",
      entryType: _selectedEntryType,
      enabled: true,
      fieldA: fieldOpts.first,
      operator: ">",
      isFieldBHeading: false,
      fieldB: "10",
      bgColorHex: 0xFFFFD54F,
      textColorHex: 0xFF000000,
      description: "New Validation Rule",
    );
    provider.addValidationRule(newRule);
  }

  void _selectPreviousCategory() {
    int idx = entryCategories.indexWhere((cat) => cat["type"] == _selectedEntryType);
    if (idx != -1) {
      int prevIdx = (idx - 1 + entryCategories.length) % entryCategories.length;
      setState(() {
        _selectedEntryType = entryCategories[prevIdx]["type"]!;
      });
    }
  }

  void _selectNextCategory() {
    int idx = entryCategories.indexWhere((cat) => cat["type"] == _selectedEntryType);
    if (idx != -1) {
      int nextIdx = (idx + 1) % entryCategories.length;
      setState(() {
        _selectedEntryType = entryCategories[nextIdx]["type"]!;
      });
    }
  }

  void _confirmDeleteRule(BuildContext context, PharmacyProvider provider, ValidationRule rule) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text("Delete Validation Rule"),
          ],
        ),
        content: Text("Are you sure you want to delete this rule?\n\nTarget: ${rule.fieldA} ${rule.operator} ${rule.fieldB}"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              provider.deleteValidationRule(_selectedEntryType, rule.id);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Validation rule deleted successfully."),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.delete, size: 16),
            label: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PharmacyProvider>(context);
    final rules = provider.getValidationRules(_selectedEntryType);

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Reset Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Color Validation Rules Manager",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Configure automatic text & box background highlight rules per entry type.",
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
              OutlinedButton.icon(
                onPressed: () {
                  provider.resetValidationRulesToDefaults(_selectedEntryType);
                },
                icon: const Icon(Icons.restore, size: 16),
                label: Text("Reset ${_getCategoryLabel()} Defaults"),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Category Selector Row with Navigation Buttons
          Row(
            children: [
              // Previous Category Button
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 24),
                tooltip: "Previous Category",
                onPressed: _selectPreviousCategory,
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: entryCategories.map((cat) {
                      final bool isSel = cat["type"] == _selectedEntryType;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          selected: isSel,
                          selectedColor: Colors.teal.shade100,
                          checkmarkColor: Colors.teal.shade900,
                          label: Text(
                            "${cat["icon"]} ${cat["label"]}",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                              color: isSel ? Colors.teal.shade900 : Colors.grey.shade800,
                            ),
                          ),
                          onSelected: (val) {
                            if (val) {
                              setState(() {
                                _selectedEntryType = cat["type"]!;
                              });
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              // Next Category Button
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 24),
                tooltip: "Next Category",
                onPressed: _selectNextCategory,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),

          // Rules List View
          Expanded(
            child: rules.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.palette_outlined, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text(
                          "No rules defined for ${_getCategoryLabel()}. Click '+' below to add.",
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade700,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _addNewRule(provider),
                          icon: const Icon(Icons.add_circle_outline, size: 18),
                          label: const Text("Add New Rule"),
                        ),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: rules.length,
                    onReorderItem: (oldIndex, newIndex) {
                      provider.reorderValidationRules(_selectedEntryType, oldIndex, newIndex);
                    },
                    footer: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                          onPressed: () => _addNewRule(provider),
                          icon: const Icon(Icons.add_circle_outline, size: 18),
                          label: const Text("Add New Rule", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                    itemBuilder: (context, index) {
                      final rule = rules[index];
                      return Container(
                        key: ValueKey(rule.id),
                        child: _buildRuleRow(provider, rule, index, rules.length),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _getCategoryLabel() {
    final cat = entryCategories.firstWhere((c) => c["type"] == _selectedEntryType, orElse: () => entryCategories.first);
    return cat["label"]!;
  }

  Widget _buildRuleRow(PharmacyProvider provider, ValidationRule rule, int index, int totalRules) {
    final Color currentBgColor = Color(rule.bgColorHex);
    final Color currentTextColor = Color(rule.textColorHex);

    final fieldOpts = headingOptionsMap[_selectedEntryType] ?? headingOptionsMap["PURCHASE"]!;
    final compareOpts = compareHeadingOptionsMap[_selectedEntryType] ?? compareHeadingOptionsMap["PURCHASE"]!;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Reorder Drag Handle
                ReorderableDragStartListener(
                  index: index,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Tooltip(
                      message: "Drag to reorder rule",
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                        child: Icon(Icons.drag_indicator, size: 20, color: Colors.grey.shade500),
                      ),
                    ),
                  ),
                ),

                // Move Up / Move Down Navigation Buttons
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: index > 0
                          ? () => provider.moveValidationRule(_selectedEntryType, index, -1)
                          : null,
                      child: Tooltip(
                        message: "Move Rule Up",
                        child: Icon(
                          Icons.keyboard_arrow_up,
                          size: 18,
                          color: index > 0 ? Colors.teal.shade700 : Colors.grey.shade300,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: index < totalRules - 1
                          ? () => provider.moveValidationRule(_selectedEntryType, index, 1)
                          : null,
                      child: Tooltip(
                        message: "Move Rule Down",
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          size: 18,
                          color: index < totalRules - 1 ? Colors.teal.shade700 : Colors.grey.shade300,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),

                // Enable/Disable Switch
                Tooltip(
                  message: rule.enabled ? "Rule Enabled" : "Rule Disabled",
                  child: Switch(
                    value: rule.enabled,
                    activeThumbColor: Colors.teal,
                    activeTrackColor: Colors.teal.shade100,
                    onChanged: (val) {
                      rule.enabled = val;
                      provider.updateValidationRule(rule);
                    },
                  ),
                ),
                const SizedBox(width: 6),

                // Field A Dropdown
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: "Target Column",
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    initialValue: fieldOpts.contains(rule.fieldA) ? rule.fieldA : fieldOpts.first,
                    items: fieldOpts.map((f) => DropdownMenuItem(value: f, child: Text(f, style: const TextStyle(fontSize: 12)))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        rule.fieldA = val;
                        provider.updateValidationRule(rule);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 6),

                // Operator Dropdown
                SizedBox(
                  width: 70,
                  child: DropdownButtonFormField<String>(
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: "Op",
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    ),
                    initialValue: operatorOptions.contains(rule.operator) ? rule.operator : operatorOptions.first,
                    items: operatorOptions.map((op) => DropdownMenuItem(value: op, child: Text(op, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        rule.operator = val;
                        provider.updateValidationRule(rule);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 6),

                // Field B Box with Heading/Value selector
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Mode Selector ABOVE the field
                      Row(
                        children: [
                          InkWell(
                            onTap: () {
                              rule.isFieldBHeading = true;
                              rule.fieldB = compareOpts.first;
                              provider.updateValidationRule(rule);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: rule.isFieldBHeading ? Colors.blue.shade800 : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                "Heading ▾",
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: rule.isFieldBHeading ? Colors.white : Colors.black87),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () {
                              rule.isFieldBHeading = false;
                              rule.fieldB = "10";
                              provider.updateValidationRule(rule);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: !rule.isFieldBHeading ? Colors.blue.shade800 : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                "Value # ✎",
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: !rule.isFieldBHeading ? Colors.white : Colors.black87),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),

                      // Input / Dropdown Field
                      rule.isFieldBHeading
                          ? DropdownButtonFormField<String>(
                              isDense: true,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              ),
                              initialValue: compareOpts.contains(rule.fieldB) ? rule.fieldB : compareOpts.first,
                              items: compareOpts.map((f) => DropdownMenuItem(value: f, child: Text(f, style: const TextStyle(fontSize: 12)))).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  rule.fieldB = val;
                                  provider.updateValidationRule(rule);
                                }
                              },
                            )
                          : TextFormField(
                              initialValue: rule.fieldB,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              ),
                              style: const TextStyle(fontSize: 12),
                              onChanged: (val) {
                                rule.fieldB = val.trim();
                                provider.updateValidationRule(rule);
                              },
                            ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),

                // Box Background Color Picker
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Box Bg", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    PopupMenuButton<int>(
                      tooltip: "Select Box Background Color",
                      onSelected: (colHex) {
                        rule.bgColorHex = colHex;
                        provider.updateValidationRule(rule);
                      },
                      itemBuilder: (ctx) => colorOptions.map((hex) {
                        return PopupMenuItem<int>(
                          value: hex,
                          child: Row(
                            children: [
                              Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: Color(hex),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.black26),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text("0x${hex.toRadixString(16).toUpperCase()}"),
                            ],
                          ),
                        );
                      }).toList(),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: currentBgColor,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.black38),
                        ),
                        child: const Icon(Icons.format_color_fill, size: 14, color: Colors.black54),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 6),

                // Text Color Picker
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Text Col", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    PopupMenuButton<int>(
                      tooltip: "Select Text Color",
                      onSelected: (colHex) {
                        rule.textColorHex = colHex;
                        provider.updateValidationRule(rule);
                      },
                      itemBuilder: (ctx) => colorOptions.map((hex) {
                        return PopupMenuItem<int>(
                          value: hex,
                          child: Row(
                            children: [
                              Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: Color(hex),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.black26),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text("0x${hex.toRadixString(16).toUpperCase()}"),
                            ],
                          ),
                        );
                      }).toList(),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: currentTextColor,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.black38),
                        ),
                        child: Icon(
                          Icons.format_color_text,
                          size: 14,
                          color: currentTextColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),

                // Delete Button
                Tooltip(
                  message: "Delete Validation Rule",
                  child: IconButton(
                    icon: Icon(Icons.delete_outline, color: Colors.red.shade700, size: 20),
                    onPressed: () => _confirmDeleteRule(context, provider, rule),
                  ),
                ),
              ],
            ),

            if (rule.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                "Note: ${rule.description}",
                style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Backwards compatibility alias
typedef PurchaseRuleManagerWidget = ValidationRuleManagerWidget;

/// Show Validation Rule Config Modal Dialog
void showPurchaseRuleConfigDialog(BuildContext context, {String entryType = "PURCHASE"}) {
  showDialog(
    context: context,
    builder: (ctx) => DraggableModal(
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 880,
          height: 620,
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: Colors.white,
              title: const Row(
                children: [
                  Icon(Icons.drag_indicator, size: 20, color: Colors.white70),
                  SizedBox(width: 8),
                  Text("Validation Rules Manager", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  SizedBox(width: 8),
                  Text("(Draggable Window)", style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.white54)),
                ],
              ),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: "Close",
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            body: ValidationRuleManagerWidget(isModal: true, initialEntryType: entryType),
          ),
        ),
      ),
    ),
  );
}
