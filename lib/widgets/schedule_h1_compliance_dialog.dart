import 'package:flutter/material.dart';

class ScheduleH1ComplianceResult {
  final String doctorName;
  final String doctorRegNo;
  final String patientName;
  final String patientAddress;

  ScheduleH1ComplianceResult({
    required this.doctorName,
    required this.doctorRegNo,
    required this.patientName,
    required this.patientAddress,
  });
}

class ScheduleH1ComplianceDialog extends StatefulWidget {
  final String initialDoctorName;
  final String initialPatientName;
  final List<String> restrictedItemNames;

  const ScheduleH1ComplianceDialog({
    super.key,
    required this.initialDoctorName,
    required this.initialPatientName,
    required this.restrictedItemNames,
  });

  @override
  State<ScheduleH1ComplianceDialog> createState() => _ScheduleH1ComplianceDialogState();
}

class _ScheduleH1ComplianceDialogState extends State<ScheduleH1ComplianceDialog> {
  late TextEditingController _doctorCtrl;
  final TextEditingController _doctorRegCtrl = TextEditingController();
  late TextEditingController _patientCtrl;
  final TextEditingController _addressCtrl = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _doctorCtrl = TextEditingController(text: widget.initialDoctorName);
    _patientCtrl = TextEditingController(text: widget.initialPatientName);
  }

  @override
  void dispose() {
    _doctorCtrl.dispose();
    _doctorRegCtrl.dispose();
    _patientCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.shield_outlined, color: Colors.amberAccent, size: 28),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "Statutory Compliance Verification (Schedule H1 / X)",
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade900.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade700),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Drugs & Cosmetics Rules mandate recording Prescribing Doctor Reg No. & Patient Address for regulated medicines:\n• ${widget.restrictedItemNames.join('\n• ')}",
                          style: const TextStyle(color: Colors.amberAccent, fontSize: 11, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _doctorCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: "Prescribing Doctor Name*",
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.medical_services_outlined, color: Colors.tealAccent, size: 18),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? "Doctor Name is required" : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _doctorRegCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: "Doctor State/Medical Reg. No.*",
                    hintText: "e.g. KMC/12345/2018",
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                    labelStyle: const TextStyle(color: Colors.amberAccent),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.verified_user_outlined, color: Colors.amberAccent, size: 18),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? "Doctor Medical Reg No. is required for Schedule H1/X" : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _patientCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: "Patient Full Name*",
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.person_outline, color: Colors.lightBlueAccent, size: 18),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? "Patient Name is required" : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: "Patient Full Address*",
                    hintText: "House Name / Street / Town",
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                    labelStyle: const TextStyle(color: Colors.amberAccent),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.home_outlined, color: Colors.amberAccent, size: 18),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? "Patient Residential Address is required for statutory register" : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text("CANCEL SAVE", style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.verified_rounded, size: 18),
          label: const Text("VERIFY & PROCEED", style: TextStyle(fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(
                context,
                ScheduleH1ComplianceResult(
                  doctorName: _doctorCtrl.text.trim(),
                  doctorRegNo: _doctorRegCtrl.text.trim(),
                  patientName: _patientCtrl.text.trim(),
                  patientAddress: _addressCtrl.text.trim(),
                ),
              );
            }
          },
        ),
      ],
    );
  }
}
