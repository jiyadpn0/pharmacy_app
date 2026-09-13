import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/pharmacy_provider.dart';
import '../../widgets/app_date_picker.dart';
import '../../utils/report_pdf_generator.dart';
import '../../utils/printer_service.dart';
import '../../utils/theme_constants.dart';

class ScheduleH1RegisterScreen extends StatefulWidget {
  const ScheduleH1RegisterScreen({super.key});

  @override
  State<ScheduleH1RegisterScreen> createState() => _ScheduleH1RegisterScreenState();
}

class _ScheduleH1RegisterScreenState extends State<ScheduleH1RegisterScreen> {
  DateTime _fromDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _toDate = DateTime.now();
  String _searchQuery = "";
  bool _isLoading = false;

  List<Map<String, dynamic>> _h1Entries = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchH1Records());
  }

  Future<void> _fetchH1Records() async {
    setState(() => _isLoading = true);
    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    final allSales = await provider.fetchSalesInDateRange(
      _fromDate,
      _toDate,
      loadItems: true,
      limit: 500,
      offset: 0,
    );

    List<Map<String, dynamic>> records = [];

    for (var sale in allSales.where((s) => !s.isDeleted)) {
      for (var item in sale.items) {
        final sched = item.product.schedule.toUpperCase().trim();
        // Check if item falls under Schedule H1 or Narcotic / Controlled schedule
        if (sched.contains("H1") || sched.contains("NRX") || item.product.isControlled || item.product.isNrx) {
          records.add({
            'date': DateFormat('dd/MM/yyyy').format(sale.date),
            'raw_date': sale.date,
            'bill_no': sale.entryNo,
            'patient_name': sale.patient.toUpperCase() == "GENERAL" ? sale.customerAcc : sale.patient,
            'mobile': sale.mobile.isNotEmpty ? sale.mobile : "-",
            'doctor_name': sale.doctor.isNotEmpty ? sale.doctor : "-",
            'doctor_reg_no': sale.doctorRegNo.isNotEmpty ? sale.doctorRegNo : "-",
            'medicine_name': item.product.name,
            'batch_no': item.product.batch,
            'exp_date': item.product.expiry,
            'qty': item.qty,
          });
        }
      }
    }

    if (mounted) {
      setState(() {
        _h1Entries = records;
        _isLoading = false;
      });
    }
  }

  void _printRegister() async {
    if (_h1Entries.isEmpty) return;
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);

    final headers = ["Date", "Bill No", "Patient Name", "Mobile", "Doctor Name", "Doctor Reg No", "Medicine Name", "Batch", "Exp", "Qty"];
    final data = _h1Entries.map((row) => [
      row['date'].toString(),
      row['bill_no'].toString(),
      row['patient_name'].toString(),
      row['mobile'].toString(),
      row['doctor_name'].toString(),
      row['doctor_reg_no'].toString(),
      row['medicine_name'].toString(),
      row['batch_no'].toString(),
      row['exp_date'].toString(),
      row['qty'].toString(),
    ]).toList();

    final doc = await ReportPdfGenerator.buildReportPdf(
      title: "Schedule H1 / Narcotics Statutory Register",
      headers: headers,
      data: data,
      company: pharma.companyProfile,
      subtitle: "From: ${DateFormat('dd/MM/yyyy').format(_fromDate)} To: ${DateFormat('dd/MM/yyyy').format(_toDate)}",
    );

    if (!mounted) return;
    PrinterService.showProfessionalPreview(
      context: context,
      doc: doc,
      title: "Schedule H1 Register Print Preview",
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _h1Entries.where((r) {
      final q = _searchQuery.toLowerCase().trim();
      if (q.isEmpty) return true;
      return r['medicine_name'].toString().toLowerCase().contains(q) ||
          r['patient_name'].toString().toLowerCase().contains(q) ||
          r['doctor_name'].toString().toLowerCase().contains(q) ||
          r['batch_no'].toString().toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      body: Column(
        children: [
          _buildTopBar(),
          _buildFilterBar(),
          Expanded(child: _buildRegisterTable(filtered)),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.menu_book_rounded, color: Colors.red.shade800, size: 22),
          ),
          const SizedBox(width: 14),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("SCHEDULE H1 / NARCOTICS REGISTER", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
              Text("Statutory Drug Controller Compliance Log", style: TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
            ],
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _printRegister,
            icon: const Icon(Icons.print_rounded, size: 16),
            label: const Text("PRINT INSPECTION REGISTER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          _dateSelector("From Date", _fromDate, (d) { setState(() => _fromDate = d); _fetchH1Records(); }),
          const SizedBox(width: 12),
          _dateSelector("To Date", _toDate, (d) { setState(() => _toDate = d); _fetchH1Records(); }),
          const SizedBox(width: 20),
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: "Search medicine, doctor, patient or batch...",
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text("Records Found: ${_h1Entries.length}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        ],
      ),
    );
  }

  Widget _dateSelector(String label, DateTime date, Function(DateTime) onPick) {
    return InkWell(
      onTap: () async {
        final picked = await showAppDatePicker(context: context, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime(2100));
        if (picked != null) onPick(picked);
      },
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300)),
        child: Row(
          children: [
            const Icon(Icons.calendar_month, size: 14, color: Colors.blueGrey),
            const SizedBox(width: 6),
            Text(DateFormat('dd/MM/yyyy').format(date), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildRegisterTable(List<Map<String, dynamic>> records) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (records.isEmpty) {
      return const Center(
        child: Text("No Schedule H1 or Narcotic sales recorded in this period.", style: TextStyle(color: Colors.grey, fontSize: 13)),
      );
    }

    return Column(
      children: [
        Container(
          height: 34,
          color: const Color(0xFF334155),
          child: const Row(
            children: [
              _Hdr("DATE", flex: 2),
              _Hdr("BILL NO", flex: 2),
              _Hdr("PATIENT NAME", flex: 4),
              _Hdr("MOBILE", flex: 3),
              _Hdr("DOCTOR NAME", flex: 4),
              _Hdr("DOC REG NO", flex: 3),
              _Hdr("DRUG NAME", flex: 5),
              _Hdr("BATCH", flex: 3),
              _Hdr("EXP", flex: 2, align: TextAlign.center),
              _Hdr("QTY", flex: 2, align: TextAlign.right),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: records.length,
            itemBuilder: (ctx, i) {
              final r = records[i];
              return Container(
                height: 32,
                decoration: BoxDecoration(
                  color: i % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC),
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    _Cell(r['date'], flex: 2),
                    _Cell(r['bill_no'], flex: 2, isBold: true),
                    _Cell(r['patient_name'], flex: 4),
                    _Cell(r['mobile'], flex: 3, color: Colors.blueGrey),
                    _Cell(r['doctor_name'], flex: 4),
                    _Cell(r['doctor_reg_no'], flex: 3, isBold: true, color: Colors.indigo.shade800),
                    _Cell(r['medicine_name'], flex: 5, isBold: true, color: Colors.red.shade900),
                    _Cell(r['batch_no'], flex: 3),
                    _Cell(r['exp_date'], flex: 2, align: TextAlign.center),
                    _Cell(r['qty'].toString(), flex: 2, align: TextAlign.right, isBold: true),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Hdr extends StatelessWidget {
  final String title; final int flex; final TextAlign align;
  const _Hdr(this.title, {required this.flex, this.align = TextAlign.left});
  @override Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.center ? Alignment.center : Alignment.centerRight),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String text; final int flex; final TextAlign align; final Color? color; final bool isBold;
  const _Cell(this.text, {required this.flex, this.align = TextAlign.left, this.color, this.isBold = false});
  @override Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.center ? Alignment.center : Alignment.centerRight),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(text, style: TextStyle(fontSize: 11, color: color ?? Colors.black87, fontWeight: isBold ? FontWeight.bold : FontWeight.w500), overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
