import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/daily_snapshot_service.dart';
import '../services/server_config_service.dart';
import '../widgets/app_date_picker.dart';

class OwnerMobilePulseDialog extends StatefulWidget {
  const OwnerMobilePulseDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const OwnerMobilePulseDialog(),
    );
  }

  @override
  State<OwnerMobilePulseDialog> createState() => _OwnerMobilePulseDialogState();
}

class _OwnerMobilePulseDialogState extends State<OwnerMobilePulseDialog> {
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  Map<String, dynamic>? _snapshot;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadSnapshot();
  }

  Future<void> _loadSnapshot() async {
    setState(() => _isLoading = true);
    try {
      final snap = await DailySnapshotService.instance.generateAndPushSnapshot(date: _selectedDate);
      if (mounted) {
        setState(() {
          _snapshot = snap;
          _isLoading = false;
          _statusMessage = 'Snapshot synced with Cloud (${DateFormat('hh:mm a').format(DateTime.now())})';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Loaded locally (Cloud sync notice: $e)';
        });
      }
    }
  }

  Future<void> _forcePushLive() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Recalculating & pushing snapshot to Supabase Cloud...';
    });

    try {
      final snap = await DailySnapshotService.instance.generateAndPushSnapshot(date: _selectedDate);
      if (mounted) {
        setState(() {
          _snapshot = snap;
          _isLoading = false;
          _statusMessage = 'Successfully pushed to Cloud at ${DateFormat('hh:mm:ss a').format(DateTime.now())}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Error pushing snapshot: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverConfig = ServerConfigService.instance;
    final isCloudConnected = serverConfig.isConnected;

    final double totalSales = (_snapshot?['total_sales'] as num?)?.toDouble() ?? 0.0;
    final double cashSales = (_snapshot?['cash_sales'] as num?)?.toDouble() ?? 0.0;
    final double upiSales = (_snapshot?['upi_sales'] as num?)?.toDouble() ?? 0.0;
    final double cardSales = (_snapshot?['card_sales'] as num?)?.toDouble() ?? 0.0;
    final double creditSales = (_snapshot?['credit_sales'] as num?)?.toDouble() ?? 0.0;
    final int invoiceCount = (_snapshot?['total_invoices'] as num?)?.toInt() ?? 0;

    final double invCost = (_snapshot?['total_inventory_valuation_cost'] as num?)?.toDouble() ?? 0.0;
    final double invMrp = (_snapshot?['total_inventory_valuation_mrp'] as num?)?.toDouble() ?? 0.0;
    final double grossMargin = (_snapshot?['gross_margin_est'] as num?)?.toDouble() ?? 0.0;
    final int activeBatches = (_snapshot?['total_active_batches'] as num?)?.toInt() ?? 0;
    final int lowStock = (_snapshot?['low_stock_items_count'] as num?)?.toInt() ?? 0;
    final int expiring = (_snapshot?['expiring_soon_count'] as num?)?.toInt() ?? 0;

    final terminals = (_snapshot?['terminal_breakdown'] as List<dynamic>?) ?? [];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Container(
        width: 880,
        constraints: const BoxConstraints(maxHeight: 760),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: const Icon(Icons.insights, color: Colors.indigo, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Owner Mobile Pulse & Cloud Financial Snapshot',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isCloudConnected ? Colors.green.shade50 : Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isCloudConnected ? Colors.green.shade400 : Colors.amber.shade400,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isCloudConnected ? Icons.cloud_done : Icons.cloud_queue,
                                  size: 13,
                                  color: isCloudConnected ? Colors.green.shade800 : Colors.amber.shade900,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isCloudConnected ? 'Cloud Active' : 'Offline / Local',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isCloudConnected ? Colors.green.shade800 : Colors.amber.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Midnight auto-snapshot & live remote store pulse for multi-terminal pharmacy control.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const Divider(height: 24),

            // Date Bar & Actions
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Date: ${DateFormat('dd MMMM yyyy').format(_selectedDate)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_calendar, size: 14),
                  label: const Text('Change Date', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    minimumSize: const Size(0, 32),
                  ),
                  onPressed: () async {
                    final picked = await showAppDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() => _selectedDate = picked);
                      _loadSnapshot();
                    }
                  },
                ),
                const Spacer(),
                if (_statusMessage != null)
                  Text(
                    _statusMessage!,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
                  ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  icon: const Icon(Icons.cloud_upload_rounded, size: 16),
                  label: const Text('Capture & Push Now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: _isLoading ? null : _forcePushLive,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Financial Row
                          Row(
                            children: [
                              Expanded(
                                child: _PulseCard(
                                  title: 'Gross Revenue',
                                  value: '₹${totalSales.toStringAsFixed(2)}',
                                  subtitle: '$invoiceCount Bills • Margin: ₹${grossMargin.toStringAsFixed(0)}',
                                  icon: Icons.currency_rupee,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _PulseCard(
                                  title: 'Cash Drawer',
                                  value: '₹${cashSales.toStringAsFixed(2)}',
                                  subtitle: '${totalSales > 0 ? ((cashSales / totalSales) * 100).toStringAsFixed(1) : "0"}% of Daily Sales',
                                  icon: Icons.payments,
                                  color: Colors.green.shade700,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _PulseCard(
                                  title: 'Digital Payments',
                                  value: '₹${(upiSales + cardSales).toStringAsFixed(2)}',
                                  subtitle: 'UPI: ₹${upiSales.toStringAsFixed(0)} • Card: ₹${cardSales.toStringAsFixed(0)}',
                                  icon: Icons.qr_code_2,
                                  color: Colors.purple.shade700,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _PulseCard(
                                  title: 'Credit / Khata',
                                  value: '₹${creditSales.toStringAsFixed(2)}',
                                  subtitle: 'Pending Customer Balances',
                                  icon: Icons.assignment_late,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Inventory Capital Valuation Pulse
                          Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.inventory_2, color: Colors.teal, size: 20),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Inventory Capital Valuation & Stock Pulse',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '$activeBatches Active Batches In Stock',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 18),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _ValuationPill(
                                          label: 'Stock Locked Capital (Cost)',
                                          value: '₹${invCost.toStringAsFixed(2)}',
                                          color: Colors.teal.shade800,
                                          description: 'Total wholesale purchase cost tied up',
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _ValuationPill(
                                          label: 'Stock Retail Valuation (MRP)',
                                          value: '₹${invMrp.toStringAsFixed(2)}',
                                          color: Colors.indigo.shade800,
                                          description: 'Gross retail value at full printed MRP',
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _ValuationPill(
                                          label: 'Unrealized Gross Margin',
                                          value: '₹${(invMrp - invCost).toStringAsFixed(2)}',
                                          color: Colors.green.shade800,
                                          description: 'Estimated retail gross profit potential',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Multi-Terminal Performance & Alerts Row
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Counter Performance
                              Expanded(
                                flex: 3,
                                child: Card(
                                  elevation: 1,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Row(
                                          children: [
                                            Icon(Icons.point_of_sale, size: 18, color: Colors.blueGrey),
                                            SizedBox(width: 8),
                                            Text('Counter Sales Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                          ],
                                        ),
                                        const Divider(height: 16),
                                        if (terminals.isEmpty)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 12.0),
                                            child: Text('No terminal transactions on this date.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                          )
                                        else
                                          ...terminals.map((t) {
                                            final tMap = t as Map<String, dynamic>;
                                            final termId = tMap['terminal_id']?.toString() ?? 'POS-01';
                                            final staff = tMap['staff_name']?.toString() ?? 'Cashier';
                                            final int tInvoices = (tMap['total_invoices'] as num?)?.toInt() ?? 0;
                                            final double tSales = (tMap['total_sales'] as num?)?.toDouble() ?? 0.0;
                                            final double tCash = (tMap['cash_sales'] as num?)?.toDouble() ?? 0.0;
                                            final double tDigital = ((tMap['upi_sales'] as num?)?.toDouble() ?? 0.0) + ((tMap['card_sales'] as num?)?.toDouble() ?? 0.0);

                                            return Padding(
                                              padding: const EdgeInsets.only(bottom: 8.0),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.blueGrey.shade100,
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(termId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(staff, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                                  const SizedBox(width: 6),
                                                  Text('($tInvoices bills)', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                                  const Spacer(),
                                                  Text('Cash: ₹${tCash.toStringAsFixed(0)}', style: TextStyle(fontSize: 11, color: Colors.green.shade700)),
                                                  const SizedBox(width: 8),
                                                  Text('Online: ₹${tDigital.toStringAsFixed(0)}', style: TextStyle(fontSize: 11, color: Colors.purple.shade700)),
                                                  const SizedBox(width: 12),
                                                  Text('₹${tSales.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                                ],
                                              ),
                                            );
                                          }),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Watchdog Alerts
                              Expanded(
                                flex: 2,
                                child: Card(
                                  elevation: 1,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Row(
                                          children: [
                                            Icon(Icons.warning_amber_rounded, size: 18, color: Colors.deepOrange),
                                            SizedBox(width: 8),
                                            Text('Critical Stock Alerts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                          ],
                                        ),
                                        const Divider(height: 16),
                                        _AlertRow(
                                          label: 'Low Stock Items (≤ 10)',
                                          count: lowStock,
                                          color: lowStock > 0 ? Colors.orange.shade800 : Colors.green.shade800,
                                        ),
                                        const SizedBox(height: 10),
                                        _AlertRow(
                                          label: 'Expiring Soon (90 Days)',
                                          count: expiring,
                                          color: expiring > 0 ? Colors.red.shade800 : Colors.green.shade800,
                                        ),
                                      ],
                                    ),
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

class _PulseCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _PulseCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
        ],
      ),
    );
  }
}

class _ValuationPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final String description;

  const _ValuationPill({
    required this.label,
    required this.value,
    required this.color,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(description, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _AlertRow({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color),
          ),
        ),
      ],
    );
  }
}
