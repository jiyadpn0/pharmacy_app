import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../services/schedule_h1_register_service.dart';

class ScheduleH1ReportScreen extends StatefulWidget {
  const ScheduleH1ReportScreen({super.key});

  @override
  State<ScheduleH1ReportScreen> createState() => _ScheduleH1ReportScreenState();
}

class _ScheduleH1ReportScreenState extends State<ScheduleH1ReportScreen> {
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _toDate = DateTime.now();
  List<ScheduleH1Record> _records = [];
  bool _isLoading = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _fetchRecords();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchRecords() async {
    setState(() => _isLoading = true);
    final fromStr = DateFormat('yyyy-MM-dd').format(_fromDate);
    final toStr = DateFormat('yyyy-MM-dd').format(_toDate);
    final list = await ScheduleH1RegisterService.instance.getRecords(fromDate: fromStr, toDate: toStr);
    setState(() {
      _records = list;
      _isLoading = false;
    });
  }

  List<ScheduleH1Record> get _filteredRecords {
    if (_searchQuery.trim().isEmpty) return _records;
    final q = _searchQuery.toLowerCase().trim();
    return _records.where((r) {
      return r.productName.toLowerCase().contains(q) ||
          r.patientName.toLowerCase().contains(q) ||
          r.doctorName.toLowerCase().contains(q) ||
          r.invoiceNo.toLowerCase().contains(q) ||
          r.batchNumber.toLowerCase().contains(q) ||
          r.doctorRegNo.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _fromDate : _toDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
          if (_fromDate.isAfter(_toDate)) _toDate = _fromDate;
        } else {
          _toDate = picked;
          if (_toDate.isBefore(_fromDate)) _fromDate = _toDate;
        }
      });
      _fetchRecords();
    }
  }

  Future<void> _exportCsv() async {
    final active = _filteredRecords;
    if (active.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No records available to export"), backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      final csvContent = ScheduleH1RegisterService.instance.exportToCsv(active);
      final fromStr = DateFormat('ddMMyyyy').format(_fromDate);
      final toStr = DateFormat('ddMMyyyy').format(_toDate);
      final defaultName = "Schedule_H1_Register_${fromStr}_to_$toStr.csv";

      String? filePath = await FilePicker.saveFile(
        dialogTitle: 'Save Schedule H1 CSV Report',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (filePath != null) {
        final file = File(filePath);
        await file.writeAsString(csvContent);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Schedule H1 CSV exported to: $filePath"), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to export CSV: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _printPdf() async {
    final active = _filteredRecords;
    if (active.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No records available to print"), backgroundColor: Colors.orange),
      );
      return;
    }

    final doc = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('SCHEDULE H1 / NARCOTIC RESTRICTED DRUG REGISTER', style: pw.TextStyle(font: boldFont, fontSize: 14)),
                    pw.Text('Statutory compliance audit register under Rule 65 & Rule 97 (Drugs & Cosmetics Rules)', style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700)),
                  ],
                ),
                pw.Text(
                  'Period: ${DateFormat('dd/MM/yyyy').format(_fromDate)} to ${DateFormat('dd/MM/yyyy').format(_toDate)}',
                  style: pw.TextStyle(font: boldFont, fontSize: 10),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            context: context,
            headers: [
              'Sl',
              'Date',
              'Inv #',
              'Drug Name',
              'Batch',
              'Qty',
              'Patient Name & Contact',
              'Doctor Name',
              'Doc Reg No'
            ],
            headerStyle: pw.TextStyle(font: boldFont, fontSize: 8, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.red900),
            cellStyle: pw.TextStyle(font: font, fontSize: 7.5),
            data: active.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final r = entry.value;
              return [
                idx.toString(),
                r.date,
                r.invoiceNo,
                r.productName,
                r.batchNumber,
                r.qty.toStringAsFixed(r.qty % 1 == 0 ? 0 : 2),
                "${r.patientName}\n${r.patientContact}",
                r.doctorName,
                r.doctorRegNo.isEmpty ? "N/A" : r.doctorRegNo,
              ];
            }).toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Schedule_H1_Register.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRecords;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Schedule H1 Restricted Drugs Audit Register", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: "Export Statutory CSV",
            onPressed: _exportCsv,
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: "Print Inspection PDF",
            onPressed: _printPdf,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh Records",
            onPressed: _fetchRecords,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildFilterHeader(),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? const Center(child: Text("No Schedule H1 transactions found for selected filters.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)))
                      : _buildTable(filtered),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterHeader() {
    final df = DateFormat('dd/MM/yyyy');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_outlined, color: Colors.red, size: 20),
              const SizedBox(width: 8),
              const Text("Drug Inspector Audit Register (Schedule H / H1 / Narcotics)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const Spacer(),
              // Date Range Pickers
              InkWell(
                onTap: () => _pickDate(isFrom: true),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 14, color: Colors.blueGrey),
                      const SizedBox(width: 6),
                      Text("From: ${df.format(_fromDate)}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                onTap: () => _pickDate(isFrom: false),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 14, color: Colors.blueGrey),
                      const SizedBox(width: 6),
                      Text("To: ${df.format(_toDate)}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _exportCsv,
                icon: const Icon(Icons.table_chart_outlined, size: 15),
                label: const Text("EXPORT CSV", style: TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _printPdf,
                icon: const Icon(Icons.picture_as_pdf, size: 15),
                label: const Text("PRINT PDF", style: TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade900, foregroundColor: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Search Box
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: "Search by Drug Name, Patient, Contact, Doctor, or Invoice #...",
              hintStyle: const TextStyle(fontSize: 12),
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = "");
                      },
                    )
                  : null,
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(List<ScheduleH1Record> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: Colors.red.shade50,
            child: const Row(
              children: [
                SizedBox(width: 40, child: Text("SL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                SizedBox(width: 85, child: Text("DATE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                SizedBox(width: 90, child: Text("INVOICE #", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                Expanded(flex: 3, child: Text("DRUG / BATCH", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                SizedBox(width: 60, child: Text("QTY", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                SizedBox(width: 20),
                Expanded(flex: 3, child: Text("PATIENT & CONTACT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                Expanded(flex: 3, child: Text("DOCTOR & REG NO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final r = items[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(width: 40, child: Text("${i + 1}", style: const TextStyle(fontSize: 11, color: Colors.grey))),
                      SizedBox(width: 85, child: Text(r.date, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                      SizedBox(width: 90, child: Text(r.invoiceNo, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey))),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.productName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                            Text("Batch: ${r.batchNumber}", style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 60,
                        child: Text(
                          r.qty.toStringAsFixed(r.qty % 1 == 0 ? 0 : 2),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.patientName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                            if (r.patientContact.isNotEmpty)
                              Text(r.patientContact, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Dr. ${r.doctorName}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                            Text("Reg: ${r.doctorRegNo.isEmpty ? "N/A" : r.doctorRegNo}", style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                          ],
                        ),
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
