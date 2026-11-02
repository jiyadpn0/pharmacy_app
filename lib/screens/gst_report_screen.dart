import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as ex;
import '../providers/pharmacy_provider.dart';
import '../providers/app_provider.dart';
import '../utils/tax_calculator.dart';
import '../widgets/pin_unlock_dialog.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/erp_tooltip.dart';
import '../utils/app_formatters.dart';
import '../utils/app_dialogs.dart';
import '../services/gst_export_service.dart';
import '../utils/theme_constants.dart';

class GstReportScreen extends StatefulWidget {
  const GstReportScreen({super.key});

  @override
  State<GstReportScreen> createState() => _GstReportScreenState();
}

class _GstReportScreenState extends State<GstReportScreen> {
  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();
  String _reportType = 'B2C_SALES'; // B2C_SALES, B2B_SALES, PURCHASES, HSN_SUMMARY, GSTR_3B
  bool _isLoading = false;
  bool _isAuthorized = false;

  List<Map<String, dynamic>> _reportData = [];
  int? _selectedIndex;
  int? _lastTapIndex;
  DateTime? _lastTapTime;

  // Sorting state
  String? _sortKey;
  bool _isAscending = true;

  int _offset = 0;
  final int _pageSize = 100;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAuthorization());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) _loadMore();
    }
  }

  void _checkAuthorization() async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    if (provider.securityToggles['require_pin_financial_reports'] == true) {
      bool isUnlocked = await PinUnlockDialog.show(
        context,
        provider,
        title: "Tax Report Locked",
        message: "Enter Master PIN to access GST filings and tax returns.",
      );
      if (!mounted) return;
      if (isUnlocked) {
        setState(() => _isAuthorized = true);
        _generateReport();
      }
    } else {
      setState(() => _isAuthorized = true);
      _generateReport();
    }
  }

  void _generateReport() async {
    setState(() {
      _isLoading = true;
      _reportData = [];
      _offset = 0;
      _hasMore = true;
    });
    await _fetchData(0);
  }

  Future<void> _fetchData(int offset) async {
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    List<Map<String, dynamic>> data = [];
    int batchCount = 0;

    if (_reportType == 'B2C_SALES' || _reportType == 'B2B_SALES' || _reportType == 'HSN_SUMMARY' || _reportType == 'GSTR_3B') {
      final allInRange = await p.fetchSalesInDateRange(_fromDate, _toDate, loadItems: true, limit: _pageSize, offset: offset);
      batchCount = allInRange.length;
      final sales = allInRange.where((s) => !s.isDeleted).toList();

      for (var s in sales) {
        bool isB2B = (s.customerAcc.toUpperCase() == "CREDIT" && s.mobile.length >= 10);
        if ((_reportType == 'B2C_SALES' && !isB2B) || (_reportType == 'B2B_SALES' && isB2B) || _reportType == 'HSN_SUMMARY' || _reportType == 'GSTR_3B') {
          int totalTaxable = 0;
          int totalCgst = 0;
          int totalSgst = 0;
          int totalIgst = 0;

          for (var item in s.items) {
            int totalP = item.totalPaise;
            int gstP = item.gstAmtPaise;
            int itemTaxable = totalP - gstP;
            if (itemTaxable < 0) itemTaxable = 0;

            totalTaxable += itemTaxable.toInt();
            totalCgst += item.cgstAmtPaise.toInt();
            totalSgst += item.sgstAmtPaise.toInt();
            totalIgst += item.igstAmtPaise.toInt();
          }

          int totalTaxAmt = (totalCgst + totalSgst + totalIgst).toInt();
          int preAdjustTotal = totalTaxable + totalTaxAmt;
          if (preAdjustTotal > 0 && (s.discount > 0 || s.salesReturn > 0)) {
            double netGrandTotal = (s.grandTotalPaise - s.roundOffPaise).toDouble();
            double ratio = netGrandTotal / preAdjustTotal.toDouble();
            totalTaxable = (totalTaxable * ratio).round().toInt();
            totalCgst = (totalCgst * ratio).round().toInt();
            totalSgst = (totalSgst * ratio).round().toInt();
            totalIgst = (totalIgst * ratio).round().toInt();
          }

          int taxablePaiseInt = totalTaxable;
          int cgstPaiseInt = totalCgst;
          int sgstPaiseInt = totalSgst;
          int igstPaiseInt = totalIgst;

          int grandTotalPaise = s.grandTotalPaise;
          int totalTaxPaise = cgstPaiseInt + sgstPaiseInt + igstPaiseInt;

          data.add({
            'date': DateFormat('dd/MM/yyyy').format(s.date),
            'invoice_no': s.entryNo,
            'party_name': s.patient.toUpperCase() == "GENERAL" ? s.customerAcc : s.patient,
            'gstin': isB2B ? "URD-B2B" : "URD",
            'taxable_paise': taxablePaiseInt,
            'cgst_paise': cgstPaiseInt,
            'sgst_paise': sgstPaiseInt,
            'igst_paise': igstPaiseInt,
            'total_tax_paise': totalTaxPaise,
            'invoice_total_paise': grandTotalPaise,
            'taxable_value': taxablePaiseInt.toRupees(),
            'cgst': cgstPaiseInt.toRupees(),
            'sgst': sgstPaiseInt.toRupees(),
            'igst': igstPaiseInt.toRupees(),
            'total_tax': totalTaxPaise.toRupees(),
            'invoice_total': grandTotalPaise.toRupees(),
          });
        }
      }
    } else if (_reportType == 'PURCHASES') {
      final allInRange = await p.fetchPurchasesInDateRange(_fromDate, _toDate, loadItems: true, limit: _pageSize, offset: offset);
      batchCount = allInRange.length;
      for (var pur in allInRange.where((pe) => !pe.isDeleted)) {
        int totalTaxablePaise = 0;
        int totalCgstPaise = 0;
        int totalSgstPaise = 0;
        int totalIgstPaise = 0;

        String gstin = "URD";
        try {
          final sup = p.supplierMaster.firstWhere((s) => s.name == pur.supplierName);
          if (sup.gstIn.isNotEmpty) gstin = sup.gstIn;
        } catch (_) {}

        bool isInterstate = pur.taxType == 'Interstate' || (gstin != "URD" && TaxCalculator.isInterstate(p.companyProfile.gstIn, gstin));

        for (var item in pur.items) {
          totalTaxablePaise += item.netPaise.toInt();
          if (isInterstate) {
            totalIgstPaise += item.gstAmtPaise.toInt();
          } else {
            int halfGstPaise = (item.gstAmtPaise / 2.0).round();
            totalCgstPaise += halfGstPaise;
            totalSgstPaise += (item.gstAmtPaise - halfGstPaise);
          }
        }

        int grandTotalPaise = pur.grandTotalPaise;
        int totalTaxPaise = totalCgstPaise + totalSgstPaise + totalIgstPaise;

        data.add({
          'date': DateFormat('dd/MM/yyyy').format(pur.date),
          'invoice_no': pur.supInvNo.isNotEmpty ? pur.supInvNo : pur.entryNo,
          'party_name': pur.supplierName,
          'gstin': gstin,
          'taxable_paise': totalTaxablePaise,
          'cgst_paise': totalCgstPaise,
          'sgst_paise': totalSgstPaise,
          'igst_paise': totalIgstPaise,
          'total_tax_paise': totalTaxPaise,
          'invoice_total_paise': grandTotalPaise,
          'taxable_value': totalTaxablePaise.toRupees(),
          'cgst': totalCgstPaise.toRupees(),
          'sgst': totalSgstPaise.toRupees(),
          'igst': totalIgstPaise.toRupees(),
          'total_tax': totalTaxPaise.toRupees(),
          'invoice_total': grandTotalPaise.toRupees(),
        });
      }
    }

    if (mounted) {
      setState(() {
        _reportData.addAll(data);
        _offset += batchCount;
        _hasMore = batchCount == _pageSize;
        _isLoading = false;
      });
    }
  }

  void _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);
    await _fetchData(_offset);
  }

  void _exportToExcel() async {
    if (_reportData.isEmpty) return;
    final String defaultFileName = "GSTR_Report_${_reportType}_${DateFormat('MMM_yyyy').format(_fromDate)}.xlsx";
    String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Save Statutory GST Report (Excel)',
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (outputFile != null) {
      final excel = ex.Excel.createExcel();
      final sheet = excel['GST Report'];
      excel.delete('Sheet1');

      sheet.appendRow([
        ex.TextCellValue("Date"),
        ex.TextCellValue("Invoice No"),
        ex.TextCellValue("Party Name"),
        ex.TextCellValue("GSTIN"),
        ex.TextCellValue("Taxable Base (₹)"),
        ex.TextCellValue("CGST (₹)"),
        ex.TextCellValue("SGST (₹)"),
        ex.TextCellValue("IGST (₹)"),
        ex.TextCellValue("Total Tax (₹)"),
        ex.TextCellValue("Grand Total (₹)"),
      ]);

      for (var r in _reportData) {
        int taxableP = r['taxable_paise'] as int? ?? 0;
        int cgstP = r['cgst_paise'] as int? ?? 0;
        int sgstP = r['sgst_paise'] as int? ?? 0;
        int igstP = r['igst_paise'] as int? ?? 0;
        int totalTaxP = r['total_tax_paise'] as int? ?? 0;
        int invTotalP = r['invoice_total_paise'] as int? ?? 0;

        sheet.appendRow([
          ex.TextCellValue(r['date']?.toString() ?? ''),
          ex.TextCellValue(r['invoice_no']?.toString() ?? ''),
          ex.TextCellValue(r['party_name']?.toString() ?? ''),
          ex.TextCellValue(r['gstin']?.toString() ?? ''),
          ex.DoubleCellValue(taxableP.toRupees()),
          ex.DoubleCellValue(cgstP.toRupees()),
          ex.DoubleCellValue(sgstP.toRupees()),
          ex.DoubleCellValue(igstP.toRupees()),
          ex.DoubleCellValue(totalTaxP.toRupees()),
          ex.DoubleCellValue(invTotalP.toRupees()),
        ]);
      }

      final bytes = excel.encode();
      if (bytes != null) {
        await File(outputFile).writeAsBytes(bytes);
        if (mounted) {
          AppDialogs.showPathDialog(
            context: context,
            title: "Export Complete",
            message: "Statutory GSTR Report exported to Excel successfully:",
            path: outputFile,
            icon: Icons.table_chart_rounded,
            iconColor: Colors.green,
          );
        }
      }
    }
  }

  void _exportToGovtJson() async {
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final String defaultFileName = "GSTR1_${DateFormat('MMM_yyyy').format(_fromDate)}.json";
    String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Export Statutory GSTR-1 JSON for Govt Portal',
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (outputFile != null) {
      await GstExportService.exportGstr1JsonFile(_fromDate, _toDate, outputFile, provider: p);
      if (mounted) {
        AppDialogs.showPathDialog(
          context: context,
          title: "Export Complete",
          message: "Official GSTR-1 Govt JSON exported successfully:",
          path: outputFile,
          icon: Icons.code_rounded,
          iconColor: Colors.blue,
        );
      }
    }
  }

  void _exportToCsv() async {
    if (_reportData.isEmpty) return;
    final String defaultFileName = "GSTR_${_reportType}_${DateFormat('MMM_yyyy').format(_fromDate)}.csv";
    String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Export CA CSV File',
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (outputFile != null) {
      final StringBuffer sb = StringBuffer();
      sb.writeln("Date,Invoice No,Party Name,GSTIN,Taxable Value (Rupees),CGST (Rupees),SGST (Rupees),IGST (Rupees),Total Tax (Rupees),Grand Total (Rupees)");

      for (var r in _reportData) {
        sb.writeln([
          '"${r['date']}"',
          '"${r['invoice_no']}"',
          '"${r['party_name']}"',
          '"${r['gstin']}"',
          (r['taxable_paise'] as int).toRupeesString(),
          (r['cgst_paise'] as int).toRupeesString(),
          (r['sgst_paise'] as int).toRupeesString(),
          (r['igst_paise'] as int).toRupeesString(),
          (r['total_tax_paise'] as int).toRupeesString(),
          (r['invoice_total_paise'] as int).toRupeesString(),
        ].join(','));
      }

      await File(outputFile).writeAsString(sb.toString());
      if (mounted) {
        AppDialogs.showPathDialog(
          context: context,
          title: "Export Complete",
          message: "CSV Exported successfully for Tax Audit:",
          path: outputFile,
          icon: Icons.description_rounded,
          iconColor: Colors.orange,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (!_isAuthorized) {
      return Scaffold(backgroundColor: c.background, body: const Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSidebar(),
                Expanded(child: _buildDataGrid()),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.account_balance_rounded, color: Colors.purple.shade700, size: 22),
          ),
          const SizedBox(width: 16),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("GST & TAX FILING REPORT", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
              Text("GSTR-1 (Sales), GSTR-2 (Purchases), GSTR-3B Computation (Fixed-Point Precision)", style: TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w600)),
            ],
          ),
          const Spacer(),
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'excel') _exportToExcel();
              if (val == 'json') _exportToGovtJson();
              if (val == 'csv') _exportToCsv();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'excel', child: Row(children: [Icon(Icons.table_chart, color: Colors.green, size: 18), SizedBox(width: 8), Text("Export Excel (.xlsx)")] )),
              const PopupMenuItem(value: 'json', child: Row(children: [Icon(Icons.code, color: Colors.blue, size: 18), SizedBox(width: 8), Text("Export Govt JSON (.json)")] )),
              const PopupMenuItem(value: 'csv', child: Row(children: [Icon(Icons.description, color: Colors.orange, size: 18), SizedBox(width: 8), Text("Export CA CSV (.csv)")] )),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.shade700,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.download, size: 16, color: Colors.white),
                  SizedBox(width: 8),
                  Text("STATUTORY GSTR EXPORTS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white)),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border(right: BorderSide(color: Colors.grey.shade300)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("REPORT PERIOD", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.blueGrey)),
          const SizedBox(height: 10),
          _datePicker("From Date", _fromDate, (d) { setState(() => _fromDate = d); _generateReport(); }),
          const SizedBox(height: 8),
          _datePicker("To Date", _toDate, (d) { setState(() => _toDate = d); _generateReport(); }),
          const SizedBox(height: 24),
          const Text("FILING TYPE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.blueGrey)),
          const SizedBox(height: 10),
          _filterOption('B2C_SALES', 'GSTR-1 (B2C Retail)', Icons.storefront),
          _filterOption('B2B_SALES', 'GSTR-1 (B2B Credit)', Icons.business),
          _filterOption('PURCHASES', 'GSTR-2 (ITC Inward)', Icons.shopping_cart),
          _filterOption('GSTR_3B', 'GSTR-3B Tax Summary', Icons.analytics_outlined),
        ],
      ),
    );
  }

  Widget _datePicker(String label, DateTime date, Function(DateTime) onPick) {
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(DateFormat('dd/MM/yyyy').format(date), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            const Icon(Icons.calendar_month, size: 14, color: Colors.blueGrey),
          ],
        ),
      ),
    );
  }

  Widget _filterOption(String type, String label, IconData icon) {
    bool isSelected = _reportType == type;
    return InkWell(
      onTap: () {
        setState(() => _reportType = type);
        _generateReport();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade800 : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? Colors.blue.shade800 : Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.blueGrey),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87)),
          ],
        ),
      ),
    );
  }

  Widget _buildDataGrid() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    int totalTaxableP = _reportData.fold(0, (int s, r) => s + (r['taxable_paise'] as int? ?? 0));
    int totalTaxP = _reportData.fold(0, (int s, r) => s + (r['total_tax_paise'] as int? ?? 0));
    int totalInvP = _reportData.fold(0, (int s, r) => s + (r['invoice_total_paise'] as int? ?? 0));

    List<Map<String, dynamic>> displayData = List.from(_reportData);
    if (_sortKey != null) {
      displayData.sort((a, b) {
        dynamic valA = a[_sortKey];
        dynamic valB = b[_sortKey];

        int comp = 0;
        if (valA is num && valB is num) {
          comp = valA.compareTo(valB);
        } else {
          String strA = valA?.toString().toLowerCase() ?? '';
          String strB = valB?.toString().toLowerCase() ?? '';
          comp = strA.compareTo(strB);
        }
        return _isAscending ? comp : -comp;
      });
    }

    return Column(
      children: [
        Container(
          height: 35,
          color: const Color(0xFF334155),
          child: Row(
            children: [
              _Hdr("DATE", 'date', flex: 2, isSorted: _sortKey == 'date', isAscending: _isAscending, onSortTap: () => _onColumnHeaderTap('date')),
              _Hdr("INVOICE NO", 'invoice_no', flex: 3, isSorted: _sortKey == 'invoice_no', isAscending: _isAscending, onSortTap: () => _onColumnHeaderTap('invoice_no')),
              _Hdr("PARTY NAME", 'party_name', flex: 4, isSorted: _sortKey == 'party_name', isAscending: _isAscending, onSortTap: () => _onColumnHeaderTap('party_name')),
              _Hdr("GSTIN", 'gstin', flex: 3, isSorted: _sortKey == 'gstin', isAscending: _isAscending, onSortTap: () => _onColumnHeaderTap('gstin')),
              _Hdr("TAXABLE (₹)", 'taxable_paise', flex: 3, align: TextAlign.right, isSorted: _sortKey == 'taxable_paise', isAscending: _isAscending, onSortTap: () => _onColumnHeaderTap('taxable_paise')),
              _Hdr("TAX (₹)", 'total_tax_paise', flex: 3, align: TextAlign.right, isSorted: _sortKey == 'total_tax_paise', isAscending: _isAscending, onSortTap: () => _onColumnHeaderTap('total_tax_paise')),
              _Hdr("TOTAL (₹)", 'invoice_total_paise', flex: 3, align: TextAlign.right, isSorted: _sortKey == 'invoice_total_paise', isAscending: _isAscending, onSortTap: () => _onColumnHeaderTap('invoice_total_paise')),
            ],
          ),
        ),
        Expanded(
          child: displayData.isEmpty
              ? const Center(child: Text("No transactions recorded for this period.", style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  controller: _scrollController,
                  itemCount: displayData.length,
                  itemBuilder: (ctx, i) {
                    final row = displayData[i];
                    int taxableP = row['taxable_paise'] as int? ?? 0;
                    int taxP = row['total_tax_paise'] as int? ?? 0;
                    int invP = row['invoice_total_paise'] as int? ?? 0;
                    final bool isSelected = (i == _selectedIndex);

                    return InkWell(
                      onTap: () {
                        final now = DateTime.now();
                        setState(() => _selectedIndex = i);
                        if (_lastTapIndex == i && _lastTapTime != null && now.difference(_lastTapTime!) < const Duration(milliseconds: 350)) {
                          _lastTapTime = null;
                          _lastTapIndex = null;
                          final invNo = row['invoice_no']?.toString();
                          if (invNo != null && invNo.isNotEmpty) {
                            final app = Provider.of<AppProvider>(context, listen: false);
                            if (_reportType == 'PURCHASES') {
                              app.openPurchase(entryNo: invNo);
                            } else {
                              app.openSales(invoiceNo: invNo);
                            }
                          }
                        } else {
                          _lastTapIndex = i;
                          _lastTapTime = now;
                        }
                      },
                      child: Container(
                        height: 32,
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFBAE6FD) : (i % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC)),
                          border: Border(bottom: BorderSide(color: isSelected ? Colors.blue.shade300 : Colors.grey.shade200)),
                        ),
                        child: Row(
                          children: [
                            _Cell(row['date'], flex: 2),
                            _Cell(row['invoice_no'], flex: 3, isBold: true),
                            _Cell(row['party_name'], flex: 4),
                            _Cell(row['gstin'], flex: 3, color: Colors.blueGrey),
                            _Cell(taxableP.toRupeesString(), flex: 3, align: TextAlign.right),
                            _Cell(taxP.toRupeesString(), flex: 3, align: TextAlign.right, color: Colors.red.shade700),
                            _Cell(invP.toRupeesString(), flex: 3, align: TextAlign.right, isBold: true, color: Colors.green.shade800),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          height: 36,
          color: Colors.blueGrey.shade100,
          child: Row(
            children: [
              const Expanded(flex: 12, child: Padding(padding: EdgeInsets.only(left: 12), child: Text("PERIOD TOTALS (FIXED-POINT PRECISION)", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)))),
              _footerInteractiveCell(totalTaxableP.toRupeesString(), flex: 3, isBold: true),
              _footerInteractiveCell(totalTaxP.toRupeesString(), flex: 3, isBold: true, color: Colors.red.shade900),
              _footerInteractiveCell(totalInvP.toRupeesString(), flex: 3, isBold: true, color: Colors.green.shade900),
            ],
          ),
        ),
      ],
    );
  }

  Widget _footerInteractiveCell(String text, {int flex = 1, bool isBold = false, Color? color}) {
    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTapDown: (details) => _showCopyMenu(details.globalPosition, text),
        onSecondaryTapDown: (details) => _showCopyMenu(details.globalPosition, text),
        child: ERPTooltip(
          message: text,
          child: _Cell(text, flex: flex, align: TextAlign.right, isBold: isBold, color: color),
        ),
      ),
    );
  }

  void _showCopyMenu(Offset position, String text) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: "COPY",
          height: 32,
          child: Row(
            children: [
              const Icon(Icons.copy, size: 14, color: Colors.blue),
              const SizedBox(width: 8),
              Text("Copy ($text)", style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ],
    ).then((val) {
      if (val == "COPY") {
        Clipboard.setData(ClipboardData(text: text));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Copied $text to clipboard"), duration: const Duration(seconds: 1)),
          );
        }
      }
    });
  }

  void _onColumnHeaderTap(String key) {
    setState(() {
      if (_sortKey == key) {
        if (_isAscending) {
          _isAscending = false;
        } else {
          _sortKey = null;
          _isAscending = true;
        }
      } else {
        _sortKey = key;
        _isAscending = true;
      }
    });
  }
}

class _Hdr extends StatelessWidget {
  final String title;
  final String colKey;
  final int flex;
  final TextAlign align;
  final bool isSorted;
  final bool isAscending;
  final VoidCallback? onSortTap;

  const _Hdr(
    this.title,
    this.colKey, {
    required this.flex,
    this.align = TextAlign.left,
    this.isSorted = false,
    this.isAscending = true,
    this.onSortTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: onSortTap,
        child: Container(
          alignment: align == TextAlign.left ? Alignment.centerLeft : Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    color: isSorted ? Colors.amberAccent : Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSorted) ...[
                const SizedBox(width: 2),
                Icon(
                  isAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 11,
                  color: Colors.amberAccent,
                ),
              ],
            ],
          ),
        ),
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
        alignment: align == TextAlign.left ? Alignment.centerLeft : Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(text, style: TextStyle(fontSize: 11, color: color ?? Colors.black87, fontWeight: isBold ? FontWeight.bold : FontWeight.w500), overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
