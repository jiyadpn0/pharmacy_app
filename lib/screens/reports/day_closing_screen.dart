import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/pharmacy_provider.dart';
import '../../widgets/app_date_picker.dart';
import '../../services/daily_snapshot_service.dart';
import '../../services/day_closing_service.dart';
import '../../widgets/owner_mobile_pulse_dialog.dart';

class DayClosingScreen extends StatefulWidget {
  const DayClosingScreen({super.key});

  @override
  State<DayClosingScreen> createState() => _DayClosingScreenState();
}

class _DayClosingScreenState extends State<DayClosingScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  bool _isClosing = false;
  DayClosingSummary? _summary;

  final TextEditingController _physicalCashCtrl = TextEditingController();
  final TextEditingController _openingFloatCtrl = TextEditingController(text: "0.00");
  final TextEditingController _closingNotesCtrl = TextEditingController();
  final Map<String, TextEditingController> _terminalCashControllers = {};

  final Map<int, TextEditingController> _denomControllers = {
    500: TextEditingController(),
    200: TextEditingController(),
    100: TextEditingController(),
    50: TextEditingController(),
    20: TextEditingController(),
    10: TextEditingController(),
    1: TextEditingController(), // Coins
  };

  @override
  void initState() {
    super.initState();
    _fetchClosingData();
  }

  @override
  void dispose() {
    _physicalCashCtrl.dispose();
    _openingFloatCtrl.dispose();
    _closingNotesCtrl.dispose();
    for (final ctrl in _terminalCashControllers.values) {
      ctrl.dispose();
    }
    for (final ctrl in _denomControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _calculateCashFromDenominations() {
    double total = 0.0;
    _denomControllers.forEach((denom, ctrl) {
      final count = int.tryParse(ctrl.text.trim()) ?? 0;
      total += (denom * count);
    });
    if (total > 0) {
      _physicalCashCtrl.text = total.toStringAsFixed(2);
      setState(() {});
    }
  }

  Map<int, int> _getDenominationsMap() {
    final Map<int, int> map = {};
    _denomControllers.forEach((denom, ctrl) {
      map[denom] = int.tryParse(ctrl.text.trim()) ?? 0;
    });
    return map;
  }

  Future<void> _fetchClosingData() async {
    setState(() => _isLoading = true);
    final double opFloat = double.tryParse(_openingFloatCtrl.text) ?? 0.0;

    try {
      final summary = await DayClosingService.instance.getDaySummary(
        _selectedDate,
        openingFloat: opFloat,
      );

      if (mounted) {
        setState(() {
          _summary = summary;
          _openingFloatCtrl.text = summary.openingFloat.toStringAsFixed(2);
          _closingNotesCtrl.text = summary.notes ?? "";

          if (summary.denominations.isNotEmpty) {
            summary.denominations.forEach((denom, count) {
              if (_denomControllers.containsKey(denom)) {
                _denomControllers[denom]!.text = count > 0 ? count.toString() : "";
              }
            });
          }

          if (_physicalCashCtrl.text.isEmpty || summary.isClosed) {
            _physicalCashCtrl.text = summary.countedCash.toStringAsFixed(2);
          }

          for (final t in summary.terminals) {
            final termId = t['terminal_id']?.toString() ?? 'POS-01';
            final staff = t['staff_name']?.toString() ?? 'Cashier';
            final key = '${termId}_$staff';
            if (!_terminalCashControllers.containsKey(key)) {
              final termCash = (t['cash_sales'] as num?)?.toDouble() ?? 0.0;
              _terminalCashControllers[key] = TextEditingController(text: termCash.toStringAsFixed(2));
            }
          }
          _isLoading = false;
        });

        // Update cloud daily snapshot asynchronously
        unawaited(DailySnapshotService.instance.generateAndPushSnapshot(date: _selectedDate));
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmAndCloseDay() async {
    final double opFloat = double.tryParse(_openingFloatCtrl.text) ?? 0.0;
    final double counted = double.tryParse(_physicalCashCtrl.text) ?? 0.0;
    final denoms = _getDenominationsMap();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_clock_rounded, color: Colors.indigo),
            SizedBox(width: 8),
            Text("Confirm Shift Close & Backup"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Are you sure you want to close and lock shift records for ${DateFormat('dd/MM/yyyy').format(_selectedDate)}?"),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("• Expected Cash: ₹${_summary?.expectedCash.toStringAsFixed(2) ?? '0.00'}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  Text("• Physical Counted: ₹${counted.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  Text("• Variance: ₹${(counted - (_summary?.expectedCash ?? 0.0)).toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: (counted - (_summary?.expectedCash ?? 0.0)) == 0 ? Colors.green : Colors.red)),
                  const SizedBox(height: 4),
                  const Text("• Zero-loss database backup & secondary USB mirror will be captured automatically.", style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade800, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("YES, FINALIZE & BACKUP"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isClosing = true);
    try {
      final updated = await DayClosingService.instance.recordDayClosing(
        date: _selectedDate,
        openingFloat: opFloat,
        countedCash: counted,
        denominations: denoms,
        closedBy: 'Admin',
        notes: _closingNotesCtrl.text.trim(),
      );

      if (mounted) {
        setState(() {
          _summary = updated;
          _isClosing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Day finalized successfully! Database backup & USB mirror captured: ${updated.backupPath ?? 'Created in Backups/'}"),
            backgroundColor: Colors.green.shade800,
            duration: const Duration(seconds: 4),
          ),
        );

        _printShiftSettlementSlip();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isClosing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error closing day: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _printShiftSettlementSlip() async {
    final s = _summary;
    if (s == null) return;

    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final company = provider.companyProfile;
    final dateStr = DateFormat('dd/MM/yyyy').format(_selectedDate);
    final printTimeStr = DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now());

    final prefs = await SharedPreferences.getInstance();
    final preferredName = prefs.getString('preferred_printer_name');

    Printer? targetPrinter;
    if (preferredName != null && preferredName.isNotEmpty) {
      try {
        final printers = await Printing.listPrinters();
        for (var p in printers) {
          if (p.name.toLowerCase() == preferredName.toLowerCase()) {
            targetPrinter = p;
            break;
          }
        }
      } catch (_) {}
    }

    Future<Uint8List> generatePdf(PdfPageFormat format) async {
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
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                if (company.tagline.isNotEmpty)
                  pw.Center(
                    child: pw.Text(
                      company.tagline,
                      style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                if (company.address.isNotEmpty)
                  pw.Center(
                    child: pw.Text(
                      company.address,
                      style: const pw.TextStyle(fontSize: 7),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                if (company.phone.isNotEmpty)
                  pw.Center(
                    child: pw.Text("Phone: ${company.phone}", style: const pw.TextStyle(fontSize: 7)),
                  ),
                if (company.gstIn.isNotEmpty || company.dlNumber.isNotEmpty)
                  pw.Center(
                    child: pw.Text(
                      "${company.gstIn.isNotEmpty ? 'GSTIN: ${company.gstIn}  ' : ''}${company.dlNumber.isNotEmpty ? 'DL: ${company.dlNumber}' : ''}",
                      style: const pw.TextStyle(fontSize: 6.5),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                pw.SizedBox(height: 4),
                pw.Center(
                  child: pw.Text(
                    "DAY-END SHIFT SETTLEMENT & CASH RECONCILIATION",
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Divider(thickness: 0.5),
                _pdfRow("Closing Date:", dateStr, isBold: true),
                _pdfRow("Print Time:", printTimeStr),
                _pdfRow("Total Invoices:", "${s.totalInvoices}"),
                _pdfRow("Gross Total Sales:", "Rs. ${s.totalSales.toStringAsFixed(2)}", isBold: true),
                pw.Divider(thickness: 0.5),
                pw.Text("SALES MODES BREAKDOWN", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                _pdfRow("• Cash Sales:", "Rs. ${s.cashSales.toStringAsFixed(2)}"),
                _pdfRow("• UPI / Online:", "Rs. ${s.upiSales.toStringAsFixed(2)}"),
                _pdfRow("• Card Payments:", "Rs. ${s.cardSales.toStringAsFixed(2)}"),
                _pdfRow("• Credit Sales (Khata):", "Rs. ${s.creditSales.toStringAsFixed(2)}"),
                pw.Divider(thickness: 0.5),
                pw.Text("CASH REGISTER INFLOWS & OUTFLOWS", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                _pdfRow("(+) Opening Drawer Float:", "Rs. ${s.openingFloat.toStringAsFixed(2)}"),
                _pdfRow("(+) Cash Counter Sales:", "Rs. ${s.cashSales.toStringAsFixed(2)}"),
                _pdfRow("(+) Customer Credit Received:", "Rs. ${s.customerCashCollected.toStringAsFixed(2)}"),
                _pdfRow("(-) Cash Sales Returns:", "-Rs. ${s.cashReturns.toStringAsFixed(2)}"),
                _pdfRow("(-) Supplier Cash Payments:", "-Rs. ${s.supplierCashPaid.toStringAsFixed(2)}"),
                _pdfRow("(-) Cash Purchases:", "-Rs. ${s.cashPurchases.toStringAsFixed(2)}"),
                pw.Divider(thickness: 0.5),
                _pdfRow("EXPECTED DRAWER CASH:", "Rs. ${s.expectedCash.toStringAsFixed(2)}", isBold: true, fontSize: 9),
                _pdfRow("ACTUAL PHYSICAL COUNT:", "Rs. ${s.countedCash.toStringAsFixed(2)}", isBold: true, fontSize: 9),
                _pdfRow(
                  "VARIANCE:",
                  s.variance == 0
                      ? "PERFECT MATCH"
                      : "${s.variance > 0 ? '+' : ''}Rs. ${s.variance.toStringAsFixed(2)} (${s.variance > 0 ? 'Surplus' : 'Shortage'})",
                  isBold: true,
                  fontSize: 9,
                ),
                if (s.denominations.entries.any((e) => e.value > 0)) ...[
                  pw.Divider(thickness: 0.5),
                  pw.Text("PHYSICAL CASH DENOMINATIONS", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  ...s.denominations.entries.where((e) => e.value > 0).map((e) {
                    final label = e.key == 1 ? "Coins & Change" : "Rs. ${e.key} Notes";
                    final total = e.key * e.value;
                    return _pdfRow("$label (x${e.value}):", "Rs. ${total.toStringAsFixed(2)}");
                  }),
                ],
                pw.Divider(thickness: 0.5),
                pw.Text("MULTI-TERMINAL BREAKDOWN", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ...s.terminals.map((t) {
                  final termId = t['terminal_id']?.toString() ?? 'POS-01';
                  final staff = t['staff_name']?.toString() ?? 'Cashier';
                  final tCash = (t['cash_sales'] as num?)?.toDouble() ?? 0.0;
                  return _pdfRow("$termId ($staff):", "Rs. ${tCash.toStringAsFixed(2)}");
                }),
                pw.SizedBox(height: 14),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Container(width: 70, height: 0.5, color: PdfColors.black),
                        pw.SizedBox(height: 2),
                        pw.Text("Cashier Signature", style: const pw.TextStyle(fontSize: 7)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Container(width: 70, height: 0.5, color: PdfColors.black),
                        pw.SizedBox(height: 2),
                        pw.Text("Auditor / Owner", style: const pw.TextStyle(fontSize: 7)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.Text("--- END OF DAY SHIFT SETTLEMENT ---", style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
                ),
              ],
            );
          },
        ),
      );

      return pdf.save();
    }

    if (targetPrinter != null) {
      await Printing.directPrintPdf(
        printer: targetPrinter,
        onLayout: generatePdf,
      );
    } else {
      await Printing.layoutPdf(
        name: 'Shift_Settlement_${DateFormat('yyyyMMdd').format(_selectedDate)}',
        onLayout: generatePdf,
      );
    }
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
    final s = _summary;
    final double totalSales = s?.totalSales ?? 0.0;
    final double cashSales = s?.cashSales ?? 0.0;
    final double upiSales = s?.upiSales ?? 0.0;
    final double cardSales = s?.cardSales ?? 0.0;
    final double creditSales = s?.creditSales ?? 0.0;
    final int invoiceCount = s?.totalInvoices ?? 0;

    final double expectedCash = s?.expectedCash ?? 0.0;
    final double physicalCash = double.tryParse(_physicalCashCtrl.text) ?? (s?.countedCash ?? 0.0);
    final double cashVariance = physicalCash - expectedCash;

    final terminals = s?.terminals ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Day-End Closing & Cash Register Reconciliation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
        actions: [
          if (s?.isClosed == true)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(color: Colors.green.shade700, borderRadius: BorderRadius.circular(12)),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text("LOCKED & CLOSED", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                ],
              ),
            ),
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
          const SizedBox(width: 8),
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
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, color: Colors.indigo),
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
                                  _terminalCashControllers.clear();
                                });
                                _fetchClosingData();
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal.shade700,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.print_rounded, size: 18),
                            label: const Text('Print 80mm Slip'),
                            onPressed: _printShiftSettlementSlip,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Sales Overview 4 Cards
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          title: 'Total Revenue',
                          value: '₹${totalSales.toStringAsFixed(2)}',
                          subtitle: '$invoiceCount Invoices',
                          icon: Icons.account_balance_wallet,
                          color: Colors.blue.shade800,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MetricCard(
                          title: 'Cash Sales',
                          value: '₹${cashSales.toStringAsFixed(2)}',
                          subtitle: 'Counter Inflow',
                          icon: Icons.payments,
                          color: Colors.green.shade800,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MetricCard(
                          title: 'UPI / Digital',
                          value: '₹${upiSales.toStringAsFixed(2)}',
                          subtitle: 'Direct Bank Deposits',
                          icon: Icons.qr_code_2,
                          color: Colors.purple.shade800,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MetricCard(
                          title: 'Card / Khata Credit',
                          value: '₹${(cardSales + creditSales).toStringAsFixed(2)}',
                          subtitle: 'Card: ₹${cardSales.toStringAsFixed(0)} | Khata: ₹${creditSales.toStringAsFixed(0)}',
                          icon: Icons.credit_card,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // CASH DRAWER EQUATION BREAKDOWN
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    child: Padding(
                      padding: const EdgeInsets.all(18.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.calculate_rounded, color: Colors.teal, size: 22),
                              const SizedBox(width: 8),
                              const Text(
                                "Cash Register Liquidity Equation",
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              Text(
                                "Formula: Opening Float + (Cash Sales + Khata Receipts) - (Returns + Supplier Cash + Purchases)",
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                              ),
                            ],
                          ),
                          const Divider(height: 20),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Inflows
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6)),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.arrow_downward, color: Colors.green.shade800, size: 16),
                                          const SizedBox(width: 4),
                                          Text("CASH INFLOWS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green.shade900)),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Text("Opening Cash Float: ", style: TextStyle(fontSize: 11)),
                                          SizedBox(
                                            width: 90,
                                            height: 28,
                                            child: TextField(
                                              controller: _openingFloatCtrl,
                                              keyboardType: TextInputType.number,
                                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                              decoration: const InputDecoration(
                                                prefixText: "₹ ",
                                                contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                                                border: OutlineInputBorder(),
                                              ),
                                              onChanged: (_) => _fetchClosingData(),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text("• Counter Cash Sales: ₹${cashSales.toStringAsFixed(2)}", style: const TextStyle(fontSize: 11)),
                                      Text("• Patient Khata Collections: ₹${(s?.customerCashCollected ?? 0.0).toStringAsFixed(2)}", style: const TextStyle(fontSize: 11)),
                                      const Divider(height: 12),
                                      Text(
                                        "Total Cash Inflow: ₹${((double.tryParse(_openingFloatCtrl.text) ?? 0.0) + cashSales + (s?.customerCashCollected ?? 0.0)).toStringAsFixed(2)}",
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green.shade900),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),

                              // Outflows
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.arrow_upward, color: Colors.red.shade800, size: 16),
                                          const SizedBox(width: 4),
                                          Text("CASH OUTFLOWS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red.shade900)),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text("• Sales Return Refunds: -₹${(s?.cashReturns ?? 0.0).toStringAsFixed(2)}", style: const TextStyle(fontSize: 11)),
                                      Text("• Supplier Cash Paid: -₹${(s?.supplierCashPaid ?? 0.0).toStringAsFixed(2)}", style: const TextStyle(fontSize: 11)),
                                      Text("• Cash Purchases: -₹${(s?.cashPurchases ?? 0.0).toStringAsFixed(2)}", style: const TextStyle(fontSize: 11)),
                                      const Divider(height: 12),
                                      Text(
                                        "Total Cash Outflow: -₹${((s?.cashReturns ?? 0.0) + (s?.supplierCashPaid ?? 0.0) + (s?.cashPurchases ?? 0.0)).toStringAsFixed(2)}",
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red.shade900),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),

                              // Theoretical Net
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.indigo.shade200)),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.account_balance, color: Colors.indigo.shade800, size: 16),
                                          const SizedBox(width: 4),
                                          Text("DRAWER LIQUIDITY", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo.shade900)),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      const Text("Expected Cash in Safe:", style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                                      Text("₹${expectedCash.toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.indigo.shade900)),
                                      const SizedBox(height: 6),
                                      Text("Physical Cash Counted: ₹${physicalCash.toStringAsFixed(2)}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                      Text(
                                        cashVariance == 0
                                            ? "Variance: ₹0.00 (Balanced)"
                                            : "Variance: ${cashVariance > 0 ? '+' : ''}₹${cashVariance.toStringAsFixed(2)} (${cashVariance > 0 ? 'Surplus' : 'Shortage'})",
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: cashVariance == 0 ? Colors.green.shade800 : (cashVariance > 0 ? Colors.orange.shade800 : Colors.red.shade800),
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
                  const SizedBox(height: 18),

                  // CASH DENOMINATION COUNTER & RECONCILIATION
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    child: Padding(
                      padding: const EdgeInsets.all(18.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.payments_outlined, color: Colors.green, size: 22),
                              SizedBox(width: 8),
                              Text("Physical Cash Denomination Counter", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const Divider(height: 20),
                          Row(
                            children: [
                              _buildDenomInput(500, "₹500"),
                              _buildDenomInput(200, "₹200"),
                              _buildDenomInput(100, "₹100"),
                              _buildDenomInput(50, "₹50"),
                              _buildDenomInput(20, "₹20"),
                              _buildDenomInput(10, "₹10"),
                              _buildDenomInput(1, "Coins"),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              const Text("Notes & Coins Sum: ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              Text("₹${physicalCash.toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.green.shade900)),
                              const SizedBox(width: 20),
                              const Text("Manual Total Override: ", style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                              SizedBox(
                                width: 120,
                                height: 32,
                                child: TextField(
                                  controller: _physicalCashCtrl,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  decoration: const InputDecoration(
                                    prefixText: "₹ ",
                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // MULTI-TERMINAL SHIFT AUDIT
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    child: Padding(
                      padding: const EdgeInsets.all(18.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.devices, color: Colors.indigo, size: 22),
                              SizedBox(width: 8),
                              Text("Multi-Terminal Cashier Breakdown & Shift Audit", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const Divider(height: 20),
                          if (terminals.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14.0),
                              child: Center(
                                child: Text('No terminal sales recorded on this date.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              ),
                            )
                          else
                            Column(
                              children: terminals.map((t) {
                                final termId = t['terminal_id']?.toString() ?? 'POS-01';
                                final staff = t['staff_name']?.toString() ?? 'Cashier';
                                final key = '${termId}_$staff';
                                final int tInvoices = (t['total_invoices'] as num?)?.toInt() ?? 0;
                                final double tSales = (t['total_sales'] as num?)?.toDouble() ?? 0.0;
                                final double tCash = (t['cash_sales'] as num?)?.toDouble() ?? 0.0;
                                final double tUpi = (t['upi_sales'] as num?)?.toDouble() ?? 0.0;
                                final double tCard = (t['card_sales'] as num?)?.toDouble() ?? 0.0;
                                final double tCredit = (t['credit_sales'] as num?)?.toDouble() ?? 0.0;

                                final ctrl = _terminalCashControllers[key] ?? TextEditingController(text: tCash.toStringAsFixed(2));
                                double termPhysicalCash = double.tryParse(ctrl.text) ?? 0.0;
                                double termVariance = termPhysicalCash - tCash;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(color: Colors.indigo.shade800, borderRadius: BorderRadius.circular(4)),
                                        child: Text(termId, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(staff, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      const SizedBox(width: 8),
                                      Text("($tInvoices inv)", style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                                      const Spacer(),
                                      Text("Cash: ₹${tCash.toStringAsFixed(0)}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green)),
                                      const SizedBox(width: 10),
                                      Text("UPI: ₹${tUpi.toStringAsFixed(0)}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purple)),
                                      const SizedBox(width: 10),
                                      Text("Card: ₹${tCard.toStringAsFixed(0)}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange)),
                                      if (tCredit > 0) ...[
                                        const SizedBox(width: 10),
                                        Text("Khata: ₹${tCredit.toStringAsFixed(0)}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                                      ],
                                      const SizedBox(width: 10),
                                      Text("Total: ₹${tSales.toStringAsFixed(2)}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      const SizedBox(width: 16),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: termVariance == 0 ? Colors.green.shade50 : Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: termVariance == 0 ? Colors.green : Colors.red),
                                        ),
                                        child: Text(
                                          termVariance == 0 ? "MATCHED" : "VAR: ${termVariance > 0 ? '+' : ''}₹${termVariance.toStringAsFixed(2)}",
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: termVariance == 0 ? Colors.green.shade800 : Colors.red.shade800),
                                        ),
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
                  const SizedBox(height: 18),

                  // FINAL CLOSING & BACKUP ACTION BAR
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.indigo.shade200, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _closingNotesCtrl,
                            decoration: const InputDecoration(
                              hintText: "Add Day Closing remarks / auditor handover notes...",
                              hintStyle: TextStyle(fontSize: 12),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        ElevatedButton.icon(
                          onPressed: _isClosing ? null : _confirmAndCloseDay,
                          icon: _isClosing
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.lock_clock, size: 18),
                          label: Text(
                            s?.isClosed == true ? "RE-FINALIZE & BACKUP" : "FINALIZE DAY CLOSE & BACKUP",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo.shade800,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildDenomInput(int denom, String label) {
    final ctrl = _denomControllers[denom]!;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: "0",
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
              ),
              onChanged: (_) => _calculateCashFromDenominations(),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 6),
                Text(title, style: TextStyle(color: Colors.grey.shade700, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
