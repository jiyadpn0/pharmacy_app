import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../database/db_helper.dart';

class FinancialStatementsScreen extends StatefulWidget {
  const FinancialStatementsScreen({super.key});

  @override
  State<FinancialStatementsScreen> createState() => _FinancialStatementsScreenState();
}

class _FinancialStatementsScreenState extends State<FinancialStatementsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;

  double _openingInventoryValue = 0.0;
  double _totalSales = 0.0;
  double _totalPurchases = 0.0;
  double _inventoryValue = 0.0;
  double _customerReceivables = 0.0;
  double _supplierPayables = 0.0;
  double _cashBalance = 0.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadFinancialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFinancialData() async {
    setState(() => _isLoading = true);
    final db = await DbHelper.instance.database;

    try {
      // 1. Sales Income Total & Verified Cash Inflow
      final salesRes = await db.rawQuery("""
        SELECT 
          IFNULL(SUM(grand_total), 0.0) as total,
          IFNULL(SUM(CASE 
            WHEN (is_paid = 1 OR customer_acc IN ('Cash', 'UPI', 'Card')) AND IFNULL(rcvd_amt, 0.0) <= 0 
            THEN grand_total 
            ELSE IFNULL(rcvd_amt, 0.0) 
          END), 0.0) as cash_rcvd 
        FROM sales_invoices 
        WHERE (is_deleted = 0 OR is_deleted IS NULL)
      """);
      _totalSales = (salesRes.first['total'] as num?)?.toDouble() ?? 0.0;
      double actualCashRcvd = (salesRes.first['cash_rcvd'] as num?)?.toDouble() ?? 0.0;

      // 2. Purchase Cost Total & Verified Outflows
      final purchaseRes = await db.rawQuery("""
        SELECT 
          IFNULL(SUM(grand_total), 0.0) as total,
          IFNULL(SUM(CASE 
            WHEN payment_status = 1 AND IFNULL(paid_amount, 0.0) <= 0 
            THEN grand_total 
            ELSE IFNULL(paid_amount, 0.0) 
          END), 0.0) as cash_paid 
        FROM purchase_entries 
        WHERE (is_deleted = 0 OR is_deleted IS NULL)
      """);
      _totalPurchases = (purchaseRes.first['total'] as num?)?.toDouble() ?? 0.0;
      double actualCashPaid = (purchaseRes.first['cash_paid'] as num?)?.toDouble() ?? 0.0;

      // 3. Ending Stock Asset Valuation
      final stockRes = await db.rawQuery("""
        SELECT IFNULL(SUM(b.current_stock * (
          CASE 
            WHEN IFNULL(b.landing_cost, 0.0) > 0 THEN b.landing_cost 
            ELSE IFNULL(b.purchase_rate, 0.0) 
          END / CASE WHEN IFNULL(b.packing, 1) > 0 THEN b.packing ELSE 1 END
        )), 0.0) as total 
        FROM stock_batches b 
        WHERE b.current_stock > 0
      """);
      _inventoryValue = (stockRes.first['total'] as num?)?.toDouble() ?? 0.0;

      // 4. Opening Stock Asset Valuation
      final opRes = await db.rawQuery("""
        SELECT IFNULL(SUM(qty_in * (purchase_rate / 1.0)), 0.0) as total 
        FROM stock_ledger 
        WHERE voucher_type = 'OPENING_STOCK'
      """);
      _openingInventoryValue = (opRes.first['total'] as num?)?.toDouble() ?? 0.0;

      // 5. Receivables & Payables
      final recRes = await db.rawQuery("SELECT IFNULL(SUM(current_balance), 0.0) as total FROM patients WHERE current_balance > 0 AND (is_deleted = 0 OR is_deleted IS NULL)");
      _customerReceivables = (recRes.first['total'] as num?)?.toDouble() ?? 0.0;

      final payRes = await db.rawQuery("SELECT IFNULL(SUM(current_balance), 0.0) as total FROM suppliers WHERE current_balance > 0 AND (is_deleted = 0 OR is_deleted IS NULL)");
      _supplierPayables = (payRes.first['total'] as num?)?.toDouble() ?? 0.0;

      // 6. Net Liquid Assets
      _cashBalance = (actualCashRcvd - actualCashPaid);
      if (_cashBalance < 0) _cashBalance = 0.0;
    } catch (e) {
      debugPrint("Error loading financial data: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Statutory Cost of Goods Sold (COGS)
  double get _cogs {
    double computed = (_openingInventoryValue + _totalPurchases) - _inventoryValue;
    return computed < 0 ? 0.0 : computed;
  }

  // True Operating Gross Profit
  double get _grossProfit => _totalSales - _cogs;

  double get _equity => _grossProfit + _inventoryValue;

  void _printFinancialReportPdf() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text("FINANCIAL STATEMENTS REPORT", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Text("Generated on: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}", style: const pw.TextStyle(fontSize: 10)),
              pw.Divider(),
              pw.SizedBox(height: 12),
              pw.Text("PROFIT & LOSS STATEMENT", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                headers: ["Account Line", "Amount (₹)"],
                data: [
                  ["Sales Revenue", "₹${_totalSales.toStringAsFixed(2)}"],
                  ["Opening Inventory", "₹${_openingInventoryValue.toStringAsFixed(2)}"],
                  ["Total Purchases", "₹${_totalPurchases.toStringAsFixed(2)}"],
                  ["Less: Ending Inventory", "(₹${_inventoryValue.toStringAsFixed(2)})"],
                  ["Cost of Goods Sold (COGS)", "₹${_cogs.toStringAsFixed(2)}"],
                  ["Gross Profit Margin", "₹${_grossProfit.toStringAsFixed(2)}"],
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Text("BALANCE SHEET SUMMARY", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                headers: ["Assets", "Amount (₹)", "Liabilities & Capital", "Amount (₹)"],
                data: [
                  ["Inventory Stock Value", "₹${_inventoryValue.toStringAsFixed(2)}", "Supplier Accounts Payable", "₹${_supplierPayables.toStringAsFixed(2)}"],
                  ["Accounts Receivable", "₹${_customerReceivables.toStringAsFixed(2)}", "Operating Capital & Profit", "₹${(_grossProfit + _inventoryValue).toStringAsFixed(2)}"],
                  ["Actual Cash & Bank", "₹${_cashBalance.toStringAsFixed(2)}", "-", "-"],
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: "Financial_Statements_${DateFormat('ddMMyyyy').format(DateTime.now())}.pdf",
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1E2638) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Financial Statements & Double-Entry Accounting", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded),
            tooltip: "Print Financial Report PDF",
            onPressed: _printFinancialReportPdf,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: "Refresh Data",
            onPressed: _loadFinancialData,
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amberAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey.shade300,
          tabs: const [
            Tab(text: "Trial Balance"),
            Tab(text: "Profit & Loss (P&L)"),
            Tab(text: "Balance Sheet"),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTrialBalanceTab(isDark),
                _buildProfitAndLossTab(isDark),
                _buildBalanceSheetTab(isDark),
              ],
            ),
    );
  }

  Widget _buildCard(String title, List<Widget> children) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const Divider(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String title, String debit, String credit, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(title, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: 12, color: color))),
          if (debit.isNotEmpty) Text(debit, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: 12, color: color)),
          const SizedBox(width: 24),
          if (credit.isNotEmpty) Text(credit, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: 12, color: color)),
        ],
      ),
    );
  }

  Widget _buildTrialBalanceTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCard("TRIAL BALANCE SUMMARY", [
            _buildRow("Sales Revenue Account", "0.00", "₹${_totalSales.toStringAsFixed(2)}"),
            _buildRow("Opening Inventory Account", "₹${_openingInventoryValue.toStringAsFixed(2)}", "0.00"),
            _buildRow("Purchase COGS Account", "₹${_totalPurchases.toStringAsFixed(2)}", "0.00"),
            _buildRow("Inventory Asset Account", "₹${_inventoryValue.toStringAsFixed(2)}", "0.00"),
            _buildRow("Customer Debtors Receivable", "₹${_customerReceivables.toStringAsFixed(2)}", "0.00"),
            _buildRow("Supplier Creditors Payable", "0.00", "₹${_supplierPayables.toStringAsFixed(2)}"),
            _buildRow("Cash & Bank Account", "₹${_cashBalance.toStringAsFixed(2)}", "0.00"),
          ]),
        ],
      ),
    );
  }

  Widget _buildProfitAndLossTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCard("PROFIT & LOSS STATEMENT", [
            _buildRow("1. Gross Sales Revenue", "", "₹${_totalSales.toStringAsFixed(2)}", isBold: true),
            _buildRow("2. Opening Inventory", "₹${_openingInventoryValue.toStringAsFixed(2)}", ""),
            _buildRow("3. Total Purchases", "₹${_totalPurchases.toStringAsFixed(2)}", ""),
            _buildRow("4. Less: Ending Inventory Stock", "(₹${_inventoryValue.toStringAsFixed(2)})", ""),
            const Divider(),
            _buildRow("COST OF GOODS SOLD (COGS)", "", "₹${_cogs.toStringAsFixed(2)}"),
            const Divider(),
            _buildRow("GROSS OPERATING PROFIT", "", "₹${_grossProfit.toStringAsFixed(2)}", isBold: true, color: Colors.green),
          ]),
        ],
      ),
    );
  }

  Widget _buildBalanceSheetTab(bool isDark) {
    final List<Widget> rows = [
      _buildRow("ASSETS: Current Inventory Value", "", "₹${_inventoryValue.toStringAsFixed(2)}"),
      _buildRow("ASSETS: Customer Accounts Receivable", "", "₹${_customerReceivables.toStringAsFixed(2)}"),
      _buildRow("ASSETS: Actual Cash & Bank", "", "₹${_cashBalance.toStringAsFixed(2)}"),
      const Divider(),
      _buildRow("LIABILITIES: Supplier Accounts Payable", "₹${_supplierPayables.toStringAsFixed(2)}", ""),
      _buildRow("EQUITY: Net Capital and Profit", "₹${_equity.toStringAsFixed(2)}", ""),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCard("BALANCE SHEET (ASSETS vs LIABILITIES)", rows),
        ],
      ),
    );
  }
}
