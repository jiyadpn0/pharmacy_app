import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../providers/pharmacy_provider.dart';
import '../../widgets/app_date_picker.dart';
import '../../services/daily_snapshot_service.dart';
import '../../widgets/owner_mobile_pulse_dialog.dart';

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
  final Map<String, TextEditingController> _terminalCashControllers = {};

  @override
  void initState() {
    super.initState();
    _fetchClosingData();
  }

  @override
  void dispose() {
    _physicalCashCtrl.dispose();
    for (final ctrl in _terminalCashControllers.values) {
      ctrl.dispose();
    }
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

          final terminals = (res['terminals'] as List<dynamic>?) ?? [];
          for (final t in terminals) {
            final tMap = t as Map<String, dynamic>;
            final termId = tMap['terminal_id']?.toString() ?? 'POS-01';
            final staff = tMap['staff_name']?.toString() ?? 'Cashier';
            final key = '${termId}_$staff';
            if (!_terminalCashControllers.containsKey(key)) {
              final termCash = (tMap['cash_sales'] as num?)?.toDouble() ?? 0.0;
              _terminalCashControllers[key] = TextEditingController(text: termCash.toStringAsFixed(2));
            }
          }
          _isLoading = false;
        });

        // Asynchronously update daily snapshot and push to cloud
        unawaited(DailySnapshotService.instance.generateAndPushSnapshot(date: _selectedDate));
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _printShiftSettlementSlip() async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final company = provider.companyProfile;
    final dateStr = DateFormat('dd/MM/yyyy').format(_selectedDate);
    final printTimeStr = DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now());

    final double totalSales = (_closingData['total_sales'] as num?)?.toDouble() ?? 0.0;
    final double cashSales = (_closingData['cash_sales'] as num?)?.toDouble() ?? 0.0;
    final double upiSales = (_closingData['upi_sales'] as num?)?.toDouble() ?? 0.0;
    final double cardSales = (_closingData['card_sales'] as num?)?.toDouble() ?? 0.0;
    final double creditSales = (_closingData['credit_sales'] as num?)?.toDouble() ?? 0.0;
    final int invoiceCount = (_closingData['total_invoices'] as num?)?.toInt() ?? 0;
    final double physicalCash = double.tryParse(_physicalCashCtrl.text) ?? 0.0;
    final double storeVariance = physicalCash - cashSales;

    final terminals = (_closingData['terminals'] as List<dynamic>?) ?? [];

    await Printing.layoutPdf(
      name: 'Shift_Settlement_${DateFormat('yyyyMMdd').format(_selectedDate)}',
      onLayout: (PdfPageFormat format) async {
        final pdf = pw.Document();
        const thermalFormat = PdfPageFormat(
          80 * PdfPageFormat.mm,
          double.infinity,
          marginAll: 4 * PdfPageFormat.mm,
        );

        pdf.addPage(
          pw.Page(
            pageFormat: thermalFormat,
            build: (pw.Context ctx) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Center(
                    child: pw.Text(
                      company.name.toUpperCase(),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                  if (company.address.isNotEmpty)
                    pw.Center(
                      child: pw.Text(
                        company.address,
                        style: const pw.TextStyle(fontSize: 8),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  if (company.phone.isNotEmpty)
                    pw.Center(
                      child: pw.Text("Ph: ${company.phone}", style: const pw.TextStyle(fontSize: 8)),
                    ),
                  pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 0.8),
                  pw.Center(
                    child: pw.Text(
                      "DAY CLOSING & SHIFT SETTLEMENT",
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("Closing Date: $dateStr", style: const pw.TextStyle(fontSize: 8)),
                      pw.Text("Bills: $invoiceCount", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.Text("Printed: $printTimeStr", style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                  pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 0.5),

                  pw.Text("STORE-WIDE SUMMARY", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                  pw.SizedBox(height: 2),
                  _pdfRow("Total Invoices", invoiceCount.toString()),
                  _pdfRow("Cash Sales", "Rs. ${cashSales.toStringAsFixed(2)}"),
                  _pdfRow("UPI / Digital", "Rs. ${upiSales.toStringAsFixed(2)}"),
                  _pdfRow("Card / POS", "Rs. ${cardSales.toStringAsFixed(2)}"),
                  _pdfRow("Credit / Khata", "Rs. ${creditSales.toStringAsFixed(2)}"),
                  pw.Divider(thickness: 0.5),
                  _pdfRow("Gross Revenue", "Rs. ${totalSales.toStringAsFixed(2)}", isBold: true),
                  pw.SizedBox(height: 2),
                  _pdfRow("Physical Cash Drawer", "Rs. ${physicalCash.toStringAsFixed(2)}"),
                  _pdfRow(
                    "Cash Variance",
                    "${storeVariance >= 0 ? '+' : '-'} Rs. ${storeVariance.abs().toStringAsFixed(2)} (${storeVariance == 0 ? 'MATCHED' : (storeVariance > 0 ? 'SURPLUS' : 'SHORTAGE')})",
                    isBold: true,
                  ),

                  if (terminals.isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 0.8),
                    pw.Center(
                      child: pw.Text(
                        "MULTI-COUNTER TERMINAL BREAKDOWN",
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    ...terminals.map((t) {
                      final tMap = t as Map<String, dynamic>;
                      final termId = tMap['terminal_id']?.toString() ?? 'POS-01';
                      final staff = tMap['staff_name']?.toString() ?? 'Cashier';
                      final key = '${termId}_$staff';
                      final int tInvoices = (tMap['total_invoices'] as num?)?.toInt() ?? 0;
                      final double tSales = (tMap['total_sales'] as num?)?.toDouble() ?? 0.0;
                      final double tCash = (tMap['cash_sales'] as num?)?.toDouble() ?? 0.0;
                      final double tUpi = (tMap['upi_sales'] as num?)?.toDouble() ?? 0.0;
                      final double tCard = (tMap['card_sales'] as num?)?.toDouble() ?? 0.0;
                      final double tCredit = (tMap['credit_sales'] as num?)?.toDouble() ?? 0.0;
                      final double tCounted = double.tryParse(_terminalCashControllers[key]?.text ?? '') ?? tCash;
                      final double tVar = tCounted - tCash;

                      return pw.Container(
                        margin: const pw.EdgeInsets.only(bottom: 6),
                        padding: const pw.EdgeInsets.all(3),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text("Counter: $termId", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                                pw.Text("Staff: $staff", style: const pw.TextStyle(fontSize: 8)),
                              ],
                            ),
                            pw.SizedBox(height: 2),
                            _pdfRow("Invoices", tInvoices.toString(), fontSize: 7),
                            _pdfRow("Cash", "Rs. ${tCash.toStringAsFixed(2)}", fontSize: 7),
                            _pdfRow("UPI / Card / Credit", "Rs. ${(tUpi + tCard + tCredit).toStringAsFixed(2)}", fontSize: 7),
                            _pdfRow("Total Collected", "Rs. ${tSales.toStringAsFixed(2)}", fontSize: 7, isBold: true),
                            _pdfRow("Drawer Cash Counted", "Rs. ${tCounted.toStringAsFixed(2)}", fontSize: 7),
                            _pdfRow(
                              "Counter Variance",
                              "${tVar >= 0 ? '+' : '-'} Rs. ${tVar.abs().toStringAsFixed(2)}",
                              fontSize: 7,
                              isBold: true,
                            ),
                          ],
                        ),
                      );
                    }),
                  ],

                  pw.SizedBox(height: 12),
                  pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 0.5),
                  pw.SizedBox(height: 16),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Container(width: 70, height: 0.5, color: PdfColors.black),
                          pw.SizedBox(height: 2),
                          pw.Text("Cashier Sign", style: const pw.TextStyle(fontSize: 7)),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Container(width: 70, height: 0.5, color: PdfColors.black),
                          pw.SizedBox(height: 2),
                          pw.Text("Manager / Auditor", style: const pw.TextStyle(fontSize: 7)),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Center(
                    child: pw.Text("--- END OF DAY SHIFT SETTLEMENT ---", style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                  ),
                ],
              );
            },
          ),
        );

        return pdf.save();
      },
    );
  }

  pw.Widget _pdfRow(String label, String value, {bool isBold = false, double fontSize = 8}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 0.8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
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

    final terminals = (_closingData['terminals'] as List<dynamic>?) ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Day-End Closing & Daybook Reconciliation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.insights_rounded),
            onPressed: () => OwnerMobilePulseDialog.show(context),
            tooltip: 'Owner Mobile Pulse & Cloud Snapshot',
          ),
          IconButton(
            icon: const Icon(Icons.print_rounded),
            onPressed: _printShiftSettlementSlip,
            tooltip: 'Print Shift Settlement Slip (Roll 80)',
          ),
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
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo.shade700,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.insights_rounded, size: 18),
                            label: const Text('Owner Pulse'),
                            onPressed: () => OwnerMobilePulseDialog.show(context),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal.shade700,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.print_rounded, size: 18),
                            label: const Text('Print Slip (80mm)'),
                            onPressed: _printShiftSettlementSlip,
                          ),
                          const SizedBox(width: 12),
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
                                  _terminalCashControllers.clear();
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

                  // Multi-Terminal Counter Settlement Section
                  Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(Icons.devices, color: Colors.indigo, size: 24),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Multi-Terminal Cashier Breakdown & Shift Audit',
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      'Reconcile cash collected across counters (POS-01, POS-02, etc.) to prevent shift-end discrepancies.',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          if (terminals.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20.0),
                              child: Center(
                                child: Text(
                                  'No sales invoices recorded on this date.',
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                                ),
                              ),
                            )
                          else
                            Column(
                              children: terminals.map((t) {
                                final tMap = t as Map<String, dynamic>;
                                final termId = tMap['terminal_id']?.toString() ?? 'POS-01';
                                final staff = tMap['staff_name']?.toString() ?? 'Cashier';
                                final key = '${termId}_$staff';
                                final int tInvoices = (tMap['total_invoices'] as num?)?.toInt() ?? 0;
                                final double tSales = (tMap['total_sales'] as num?)?.toDouble() ?? 0.0;
                                final double tCash = (tMap['cash_sales'] as num?)?.toDouble() ?? 0.0;
                                final double tUpi = (tMap['upi_sales'] as num?)?.toDouble() ?? 0.0;
                                final double tCard = (tMap['card_sales'] as num?)?.toDouble() ?? 0.0;
                                final double tCredit = (tMap['credit_sales'] as num?)?.toDouble() ?? 0.0;

                                final ctrl = _terminalCashControllers[key] ?? TextEditingController(text: tCash.toStringAsFixed(2));
                                double termPhysicalCash = double.tryParse(ctrl.text) ?? 0.0;
                                double termVariance = termPhysicalCash - tCash;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.indigo.shade700,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              termId,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            'Cashier: $staff',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                          const Spacer(),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade50,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: Colors.blue.shade300),
                                            ),
                                            child: Text(
                                              '$tInvoices Invoices',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.blue.shade800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _CounterMetric(
                                              label: 'Cash Recorded',
                                              value: '₹${tCash.toStringAsFixed(2)}',
                                              color: Colors.green.shade700,
                                            ),
                                          ),
                                          Expanded(
                                            child: _CounterMetric(
                                              label: 'UPI / Digital',
                                              value: '₹${tUpi.toStringAsFixed(2)}',
                                              color: Colors.purple.shade700,
                                            ),
                                          ),
                                          Expanded(
                                            child: _CounterMetric(
                                              label: 'Card & Credit',
                                              value: '₹${(tCard + tCredit).toStringAsFixed(2)}',
                                              color: Colors.orange.shade800,
                                            ),
                                          ),
                                          Expanded(
                                            child: _CounterMetric(
                                              label: 'Gross Total',
                                              value: '₹${tSales.toStringAsFixed(2)}',
                                              color: Colors.black87,
                                              isBold: true,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 20),
                                      Row(
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: Row(
                                              children: [
                                                const Text(
                                                  'Drawer Cash Counted: ',
                                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                                ),
                                                const SizedBox(width: 8),
                                                SizedBox(
                                                  width: 140,
                                                  height: 36,
                                                  child: TextField(
                                                    controller: ctrl,
                                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                                    decoration: const InputDecoration(
                                                      prefixText: '₹ ',
                                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                                      border: OutlineInputBorder(),
                                                      hintText: '0.00',
                                                    ),
                                                    onChanged: (_) => setState(() {}),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: termVariance == 0
                                                  ? Colors.green.shade50
                                                  : (termVariance > 0 ? Colors.orange.shade50 : Colors.red.shade50),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: termVariance == 0
                                                    ? Colors.green
                                                    : (termVariance > 0 ? Colors.orange : Colors.red),
                                              ),
                                            ),
                                            child: Text(
                                              termVariance == 0
                                                  ? 'MATCHED PERFECTLY'
                                                  : 'VARIANCE: ${termVariance > 0 ? '+' : ''}₹${termVariance.toStringAsFixed(2)} (${termVariance > 0 ? 'Surplus' : 'Shortage'})',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: termVariance == 0
                                                    ? Colors.green.shade800
                                                    : (termVariance > 0 ? Colors.orange.shade800 : Colors.red.shade800),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Store-Wide Physical Cash Drawer Reconciliation Section
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
                                'Store-Wide Physical Cash Drawer Reconciliation',
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
                                      'Enter Total Counted Cash in Central Safe / Drawer:',
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
                                                ? 'STORE CASH MATCHED PERFECTLY'
                                                : (cashVariance > 0 ? 'STORE CASH SURPLUS DETECTED' : 'STORE CASH SHORTAGE DETECTED'),
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

class _CounterMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isBold;

  const _CounterMetric({
    required this.label,
    required this.value,
    required this.color,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color,
          ),
        ),
      ],
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
