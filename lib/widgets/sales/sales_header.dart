import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_date_picker.dart';
import '../../utils/theme_constants.dart';

class SalesHeader extends StatelessWidget {
  final String entryNo;
  final DateTime date;
  final ValueChanged<DateTime> onDateChanged;
  final TextEditingController customerAccCtrl;
  final TextEditingController patientCtrl;
  final TextEditingController mobileCtrl;
  final TextEditingController doctorCtrl;
  final TextEditingController doctorRegNoCtrl;
  final FocusNode patientFocus;
  final FocusNode mobileFocus;
  final FocusNode doctorFocus;
  final FocusNode doctorRegNoFocus;
  final FocusNode agentFocus;
  final int gstType;
  final ValueChanged<int> onGstTypeChanged;
  final String selectedAgent;
  final List<String> agents;
  final ValueChanged<String?> onAgentChanged;
  final bool isExistingEntry;
  final bool isDeleted;
  final VoidCallback onNewPressed;
  final VoidCallback onSavePressed;
  final VoidCallback onEditPressed;
  final VoidCallback onDeletePressed;
  final VoidCallback onPrintPressed;

  const SalesHeader({
    super.key,
    required this.entryNo,
    required this.date,
    required this.onDateChanged,
    required this.customerAccCtrl,
    required this.patientCtrl,
    required this.mobileCtrl,
    required this.doctorCtrl,
    required this.doctorRegNoCtrl,
    required this.patientFocus,
    required this.mobileFocus,
    required this.doctorFocus,
    required this.doctorRegNoFocus,
    required this.agentFocus,
    required this.gstType,
    required this.onGstTypeChanged,
    required this.selectedAgent,
    required this.agents,
    required this.onAgentChanged,
    required this.isExistingEntry,
    required this.isDeleted,
    required this.onNewPressed,
    required this.onSavePressed,
    required this.onEditPressed,
    required this.onDeletePressed,
    required this.onPrintPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cleanDisplayNo = entryNo.replaceAll(RegExp(r'^(SALE-|ORD-)'), '');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(bottom: BorderSide(color: c.border, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        children: [
          // TOP TOOLBAR WITH SHORTCUT GUIDES & ACTIONS
          Row(
            children: [
              // ENTRY NO BADGE
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDeleted 
                      ? Colors.red.withValues(alpha: 0.15)
                      : (isExistingEntry ? Colors.orange.withValues(alpha: 0.15) : Colors.blue.withValues(alpha: 0.15)),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDeleted 
                        ? Colors.red 
                        : (isExistingEntry ? Colors.orange : Colors.blue.shade600),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isDeleted ? Icons.cancel : (isExistingEntry ? Icons.edit_note : Icons.receipt_long),
                      size: 16,
                      color: isDeleted ? Colors.redAccent : (isExistingEntry ? Colors.orangeAccent : Colors.blueAccent),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "BILL #${cleanDisplayNo.isEmpty ? 'NEW' : cleanDisplayNo}",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isDeleted 
                            ? Colors.redAccent 
                            : (isExistingEntry ? Colors.orangeAccent : Colors.blueAccent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // ACTION BUTTONS
              _actionBtn(Icons.add_box_rounded, "NEW (F2)", Colors.blue.shade700, onNewPressed),
              const SizedBox(width: 8),
              _actionBtn(Icons.save_rounded, "SAVE (F6)", Colors.green.shade700, onSavePressed),
              const SizedBox(width: 8),
              if (isExistingEntry && !isDeleted) ...[
                _actionBtn(Icons.edit_rounded, "EDIT", Colors.orange.shade800, onEditPressed),
                const SizedBox(width: 8),
                _actionBtn(Icons.delete_forever_rounded, "DELETE", Colors.red.shade700, onDeletePressed),
                const SizedBox(width: 8),
              ],
              _actionBtn(Icons.print_rounded, "PRINT (F12)", Colors.indigo.shade700, onPrintPressed),

              const Spacer(),

              // AGENT SELECTOR
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: c.inputBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.person_pin_rounded, size: 16, color: c.secondaryText),
                    const SizedBox(width: 6),
                    Text("Staff:", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.secondaryText)),
                    const SizedBox(width: 6),
                    Builder(
                      builder: (context) {
                        final uniqueAgents = agents.toSet().toList();
                        final safeAgent = uniqueAgents.contains(selectedAgent) ? selectedAgent : (uniqueAgents.isNotEmpty ? uniqueAgents.first : "Admin");
                        if (!uniqueAgents.contains(safeAgent)) {
                          uniqueAgents.insert(0, safeAgent);
                        }
                        return DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            focusNode: agentFocus,
                            value: safeAgent,
                            isDense: true,
                            dropdownColor: c.surface,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c.primaryText),
                            items: uniqueAgents.map((a) => DropdownMenuItem(value: a, child: Text(a, style: TextStyle(color: c.primaryText)))).toList(),
                            onChanged: onAgentChanged,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // PATIENT, DOCTOR & TAX DETAILS HEADER FIELDS
          Row(
            children: [
              // PATIENT NAME FIELD
              Expanded(
                flex: 3,
                child: _headerTextField(
                  c: c,
                  label: "PATIENT / CUSTOMER (F7)",
                  controller: patientCtrl,
                  focusNode: patientFocus,
                  icon: Icons.person_outline_rounded,
                ),
              ),
              const SizedBox(width: 10),

              // MOBILE FIELD
              Expanded(
                flex: 2,
                child: _headerTextField(
                  c: c,
                  label: "MOBILE NO",
                  controller: mobileCtrl,
                  focusNode: mobileFocus,
                  icon: Icons.phone_android_rounded,
                  keyboardType: TextInputType.phone,
                ),
              ),
              const SizedBox(width: 10),

              // DOCTOR FIELD
              Expanded(
                flex: 3,
                child: _headerTextField(
                  c: c,
                  label: "DOCTOR NAME",
                  controller: doctorCtrl,
                  focusNode: doctorFocus,
                  icon: Icons.medical_services_outlined,
                ),
              ),
              const SizedBox(width: 10),

              // DOCTOR REG NO
              Expanded(
                flex: 2,
                child: _headerTextField(
                  c: c,
                  label: "REG NO",
                  controller: doctorRegNoCtrl,
                  focusNode: doctorRegNoFocus,
                  icon: Icons.badge_outlined,
                ),
              ),
              const SizedBox(width: 10),

              // DATE DISPLAY / PICKER
              InkWell(
                onTap: () async {
                  final picked = await showAppDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) onDateChanged(picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.blueAccent),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('dd/MM/yyyy').format(date),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueAccent),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  Widget _headerTextField({
    required AppThemeColors c,
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: c.secondaryText),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: keyboardType,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.primaryText),
              decoration: InputDecoration(
                hintText: label,
                hintStyle: TextStyle(fontSize: 11, color: c.secondaryText),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
