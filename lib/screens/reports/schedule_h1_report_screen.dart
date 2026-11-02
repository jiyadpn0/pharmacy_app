import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/schedule_h1_register_service.dart';

class ScheduleH1ReportScreen extends StatefulWidget {
  const ScheduleH1ReportScreen({super.key});

  @override
  State<ScheduleH1ReportScreen> createState() => _ScheduleH1ReportScreenState();
}

class _ScheduleH1ReportScreenState extends State<ScheduleH1ReportScreen> {
  final DateTime _fromDate = DateTime.now();
  final DateTime _toDate = DateTime.now();
  List<ScheduleH1Record> _records = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchRecords();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Schedule H1 Restricted Drugs Audit Register", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.red.shade900,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildFilterHeader(),
            const SizedBox(height: 14),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _records.isEmpty
                      ? const Center(child: Text("No Schedule H1 transactions recorded for selected date range.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)))
                      : _buildTable(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user_outlined, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          const Text("Drug Inspector Audit Register (Schedule H / H1)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _fetchRecords,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text("REFRESH"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ListView.separated(
        itemCount: _records.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final r = _records[i];
          return ListTile(
            dense: true,
            title: Text("${r.productName} (Batch: ${r.batchNumber}) - Qty: ${r.qty}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            subtitle: Text("Dr. ${r.doctorName} (Reg: ${r.doctorRegNo}) | Patient: ${r.patientName} (${r.patientContact})", style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
            trailing: Text("Inv #${r.invoiceNo}\n${r.date}", textAlign: TextAlign.right, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          );
        },
      ),
    );
  }
}
