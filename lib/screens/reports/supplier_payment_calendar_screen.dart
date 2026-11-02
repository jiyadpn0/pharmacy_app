import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/pharmacy_provider.dart';

class SupplierPaymentCalendarScreen extends StatelessWidget {
  const SupplierPaymentCalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pharma = Provider.of<PharmacyProvider>(context);
    final payments = pharma.supplierPayments;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Wholesaler Credit & Payment Due Calendar", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.teal.shade900,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildHeader(payments.length),
            const SizedBox(height: 16),
            Expanded(
              child: payments.isEmpty
                  ? const Center(
                      child: Text(
                        "No pending supplier payments or credit milestones recorded.",
                        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(8),
                        itemCount: payments.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final sp = payments[i];
                          final dateStr = DateFormat('dd MMM yyyy').format(sp.date);
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.teal.shade800,
                              child: const Icon(Icons.payment, color: Colors.white, size: 18),
                            ),
                            title: Text(sp.supplierName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text("Payment Ref #${sp.id} • Date: $dateStr", style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                            trailing: Text(
                              "₹ ${sp.amount.toStringAsFixed(2)}",
                              textAlign: TextAlign.right,
                              style: TextStyle(fontWeight: FontWeight.w900, color: Colors.teal.shade800, fontSize: 13),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(int count) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month_outlined, color: Colors.teal, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Supplier Payment Milestones & Payments History", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A))),
              Text("Recorded Supplier Payment Entries: $count Payments", style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}
