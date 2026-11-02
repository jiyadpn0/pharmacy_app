import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/pharmacy_provider.dart';
import '../../widgets/app_date_picker.dart';

class DayClosingScreen extends StatefulWidget {
  const DayClosingScreen({super.key});

  @override
  State<DayClosingScreen> createState() => _DayClosingScreenState();
}

class _DayClosingScreenState extends State<DayClosingScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  Map<String, dynamic> _closingData = {};

  final TextEditingController _physicalCashCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchClosingData();
  }

  @override
  void dispose() {
    _physicalCashCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchClosingData() async {
    setState(() => _isLoading = true);
    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    try {
      final res = await provider.getDayClosingData(_selectedDate);
      if (mounted) {
        setState(() {
          _closingData = res;
          double systemCash = (res['cash_sales'] as num?)?.toDouble() ?? 0.0;
          if (_physicalCashCtrl.text.isEmpty) {
            _physicalCashCtrl.text = systemCash.toStringAsFixed(2);
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    double totalSales = (_closingData['total_sales'] as num?)?.toDouble() ?? 0.0;
    double cashSales = (_closingData['cash_sales'] as num?)?.toDouble() ?? 0.0;
    double upiSales = (_closingData['upi_sales'] as num?)?.toDouble() ?? 0.0;
    double cardSales = (_closingData['card_sales'] as num?)?.toDouble() ?? 0.0;
    double creditSales = (_closingData['credit_sales'] as num?)?.toDouble() ?? 0.0;
    int invoiceCount = (_closingData['total_invoices'] as num?)?.toInt() ?? 0;

    double physicalCash = double.tryParse(_physicalCashCtrl.text) ?? 0.0;
    double cashVariance = physicalCash - cashSales;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Day-End Closing & Daybook Reconciliation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchClosingData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date Picker Card
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, color: Colors.blue),
                          const SizedBox(width: 12),
                          Text(
                            'Closing Date: ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const Spacer(),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.edit_calendar, size: 18),
                            label: const Text('Change Date'),
                            onPressed: () async {
                              final picked = await showAppDatePicker(
                                context: context,
                                initialDate: _selectedDate,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setState(() {
                                  _selectedDate = picked;
                                  _physicalCashCtrl.clear();
                                });
                                _fetchClosingData();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Sales Overview Cards
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          title: 'Total Revenue',
                          value: '₹${totalSales.toStringAsFixed(2)}',
                          subtitle: '$invoiceCount Invoices',
                          icon: Icons.account_balance_wallet,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          title: 'Cash Sales',
                          value: '₹${cashSales.toStringAsFixed(2)}',
                          subtitle: 'System Record',
                          icon: Icons.payments,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          title: 'UPI / Digital',
                          value: '₹${upiSales.toStringAsFixed(2)}',
                          subtitle: 'Online Payments',
                          icon: Icons.qr_code_2,
                          color: Colors.purple,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          title: 'Card / Credit',
                          value: '₹${(cardSales + creditSales).toStringAsFixed(2)}',
                          subtitle: 'Bank & Accounts',
                          icon: Icons.credit_card,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Cash Drawer Balancing Section
                  Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.point_of_sale, color: Colors.teal, size: 28),
                              SizedBox(width: 10),
                              Text(
                                'Physical Cash Drawer Reconciliation',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Enter Counted Cash in Drawer:',
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: _physicalCashCtrl,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(
                                        prefixText: '₹ ',
                                        border: OutlineInputBorder(),
                                        hintText: '0.00',
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                flex: 3,
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: cashVariance == 0
                                        ? Colors.green.shade50
                                        : (cashVariance > 0 ? Colors.orange.shade50 : Colors.red.shade50),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: cashVariance == 0
                                          ? Colors.green
                                          : (cashVariance > 0 ? Colors.orange : Colors.red),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            cashVariance == 0
                                                ? Icons.check_circle
                                                : (cashVariance > 0 ? Icons.info : Icons.warning),
                                            color: cashVariance == 0
                                                ? Colors.green
                                                : (cashVariance > 0 ? Colors.orange : Colors.red),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            cashVariance == 0
                                                ? 'CASH MATCHED PERFECTLY'
                                                : (cashVariance > 0 ? 'CASH SURPLUS DETECTED' : 'CASH SHORTAGE DETECTED'),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: cashVariance == 0
                                                  ? Colors.green.shade800
                                                  : (cashVariance > 0 ? Colors.orange.shade800 : Colors.red.shade800),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text('System Cash Record: ₹${cashSales.toStringAsFixed(2)}'),
                                      Text('Physical Cash Count: ₹${physicalCash.toStringAsFixed(2)}'),
                                      const Divider(),
                                      Text(
                                        'Variance: ₹${cashVariance.abs().toStringAsFixed(2)} ${cashVariance >= 0 ? "(Extra)" : "(Missing)"}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: cashVariance == 0
                                              ? Colors.green.shade900
                                              : (cashVariance > 0 ? Colors.orange.shade900 : Colors.red.shade900),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
