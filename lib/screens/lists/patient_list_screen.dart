import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/pharmacy_provider.dart';
import '../../providers/app_provider.dart';
import '../../utils/theme_constants.dart';

class PatientListScreen extends StatelessWidget {
  const PatientListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final provider = Provider.of<PharmacyProvider>(context);
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final patientMaster = provider.patientMaster;
    final allPatientNames = provider.patients;

    return Container(
      padding: const EdgeInsets.all(30),
      color: c.cardBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Patient Database", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c.primaryText)),
              ElevatedButton.icon(
                onPressed: () => appProvider.openPatientRegistration(),
                icon: const Icon(Icons.person_add),
                label: const Text("Add New Patient"),
              )
            ],
          ),
          Divider(color: c.border),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: allPatientNames.length,
              separatorBuilder: (context, index) => Divider(color: c.border),
              itemBuilder: (context, index) {
                final name = allPatientNames[index];
                final details = patientMaster.cast<Patient?>().firstWhere((p) => p?.name == name, orElse: () => null);

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.withValues(alpha: 0.15),
                    child: const Icon(Icons.person, color: Colors.blueAccent),
                  ),
                  title: Text(name.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, color: c.primaryText)),
                  subtitle: Row(
                    children: [
                      Text(
                        details?.mobile.isNotEmpty == true ? details!.mobile : "No contact info",
                        style: TextStyle(color: c.secondaryText),
                      ),
                      if (details != null && details.currentBalance.abs() > 0.01) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: details.currentBalance > 0 ? Colors.red.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: details.currentBalance > 0 ? Colors.red.shade300 : Colors.green.shade300,
                            ),
                          ),
                          child: Text(
                            details.currentBalance > 0 
                                ? "Due: ₹${details.currentBalance.toStringAsFixed(2)}" 
                                : "Adv: ₹${details.currentBalance.abs().toStringAsFixed(2)}",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: details.currentBalance > 0 ? Colors.redAccent : Colors.greenAccent,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.history, size: 20, color: Colors.blue), 
                        onPressed: () => appProvider.openCustomerLedger(patientName: name),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20, color: Colors.orange),
                        onPressed: () => appProvider.openPatientRegistration(patient: details),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
