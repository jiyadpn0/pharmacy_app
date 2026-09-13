import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../providers/pharmacy_provider.dart';
import '../providers/app_provider.dart';
import '../services/whatsapp_service.dart';
import '../utils/app_dialogs.dart';
import '../utils/theme_constants.dart';

// --- 1. DATA MODEL (Advanced Enterprise Logic) ---
class AdvancedProductMovement {
  String productName;
  String company;
  String preferredWholesale;

  int currentBalance;
  int packSize; // Must order in multiples of this
  int supplierLeadTimeDays; // How long delivery takes

  // Sales History
  int last30DaysSale;
  int maxDailySale; // To calculate volatility and safety stock

  // Additional Metrics for UI
  int last3MonthsTotal;
  int maxSale3Months;
  int maxSale6Months;
  int totalSale1Year;
  int saleCount1Year;

  int calculatedReorderQty = 0;
  int finalOrderStrips = 0;
  int manualOverrideQty = -1; // -1 means no override
  int rank = 0;

  AdvancedProductMovement({
    required this.productName,
    required this.company,
    required this.preferredWholesale,
    required this.currentBalance,
    required this.packSize,
    required this.supplierLeadTimeDays,
    required this.last30DaysSale,
    required this.maxDailySale,
    required this.last3MonthsTotal,
    required this.maxSale3Months,
    required this.maxSale6Months,
    required this.totalSale1Year,
    required this.saleCount1Year,
  });

  int get displayOrderQty => manualOverrideQty != -1 ? manualOverrideQty : finalOrderStrips;

  void calculateEnterpriseReorder() {
    double averageDailySale = last30DaysSale / 30.0;

    // 1. Calculate Safety Stock (Max Daily Sale x Max Lead Time) - (Avg Sale x Avg Lead Time)
    // Assuming 1 day delay risk for max lead time
    double maxLeadTimeDemand = maxDailySale.toDouble() * (supplierLeadTimeDays + 1);
    double avgLeadTimeDemand = averageDailySale * supplierLeadTimeDays;
    double safetyStock = maxLeadTimeDemand - avgLeadTimeDemand;

    // 2. Calculate Reorder Point (ROP)
    double reorderPoint = avgLeadTimeDemand + safetyStock;

    // 3. Determine if we need to order
    if (currentBalance <= reorderPoint) {
      // Order enough to get back to a 30-day baseline + safety stock
      double targetStock = last30DaysSale + safetyStock;
      calculatedReorderQty = (targetStock - currentBalance).ceil();

      // 4. Force rounding to the nearest full Pack Size (Strip/Box)
      if (packSize <= 0) packSize = 1;
      if (calculatedReorderQty % packSize != 0) {
        finalOrderStrips = ((calculatedReorderQty / packSize).floor() + 1);
      } else {
        finalOrderStrips = (calculatedReorderQty / packSize).floor();
      }
    } else {
      calculatedReorderQty = 0;
      finalOrderStrips = 0;
    }
  }
}

// --- 2. MAIN SCREEN UI ---
class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key});

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _horizontalCtrl = ScrollController();
  final ScrollController _verticalCtrl = ScrollController();

  List<AdvancedProductMovement> _fullList = [];
  bool _isLoading = true;

  final Map<int, double> _colWidths = {
    0: 45,  // Rank
    1: 220, // Product
    2: 120, // Company
    3: 160, // Preferred Wholesale
    4: 70,  // Balance
    5: 80,  // 1M Avg (30D/30 * 30)
    6: 75,  // 3M Max
    7: 75,  // 6M Max
    8: 110, // 1Y Total/Count
    9: 100, // Enterprise Order (Strips)
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchAndRankData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _horizontalCtrl.dispose();
    _verticalCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchAndRankData() async {
    setState(() => _isLoading = true);
    final p = Provider.of<PharmacyProvider>(context, listen: false);
    final data = await p.getProductMovementAnalysis();

    List<AdvancedProductMovement> rawData = data.map((m) => AdvancedProductMovement(
      productName: m['productName'] ?? "Unknown",
      company: m['company'] ?? "",
      preferredWholesale: m['preferredWholesale'] ?? "Direct",
      currentBalance: (m['currentBalance'] as num?)?.toInt() ?? 0,
      packSize: (m['packSize'] as num?)?.toInt() ?? 1,
      supplierLeadTimeDays: (m['supplierLeadTimeDays'] as num?)?.toInt() ?? 2,
      last30DaysSale: (m['last30DaysSale'] as num?)?.toInt() ?? 0,
      maxDailySale: (m['maxDailySale'] as num?)?.toInt() ?? 0,
      last3MonthsTotal: (m['last3MonthsTotal'] as num?)?.toInt() ?? 0,
      maxSale3Months: (m['maxSale3Months'] as num?)?.toInt() ?? 0,
      maxSale6Months: (m['maxSale6Months'] as num?)?.toInt() ?? 0,
      totalSale1Year: (m['totalSale1Year'] as num?)?.toInt() ?? 0,
      saleCount1Year: (m['saleCount1Year'] as num?)?.toInt() ?? 0,
    )).toList();

    for (var item in rawData) {
      item.calculateEnterpriseReorder();
    }

    // Sort by 30-day velocity
    rawData.sort((a, b) => b.last30DaysSale.compareTo(a.last30DaysSale));
    for (int i = 0; i < rawData.length; i++) {
      rawData[i].rank = i + 1;
    }

    setState(() {
      _fullList = rawData;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(100),
        child: Container(
          color: c.cardBg,
          child: Column(
            children: [
              _buildTopToolbar(),
              TabBar(
                controller: _tabController,
                labelColor: Colors.blue.shade900,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.blue.shade900,
                indicatorWeight: 3,
                tabs: const [
                  Tab(text: "AUTO-DRAFTS (THE BRAIN)"),
                  Tab(text: "SHORT / EXCESS STOCK"),
                  Tab(text: "SPECIAL / MANUAL ORDERS"),
                ],
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          _buildDraftsTab(),
          _buildInventoryHealthTab(),
          _buildManualOrdersTab(),
        ],
      ),
      bottomNavigationBar: _buildFooter(),
    );
  }

  Widget _buildTopToolbar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Row(
        children: [
          const Icon(Icons.psychology_outlined, color: Colors.blue, size: 28),
          const SizedBox(width: 12),
          const Text("SMART PROCUREMENT ENGINE", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.5)),
          const Spacer(),
          _actionBtn(Icons.refresh, "Recalculate", Colors.blueGrey, _fetchAndRankData),
          const SizedBox(width: 8),
          _actionBtn(Icons.save_rounded, "SAVE ORDER CONFIRMATION", const Color(0xFF1E3A8A), _saveToOrderConfirmation),
          const SizedBox(width: 8),
          _actionBtn(Icons.picture_as_pdf, "GENERATE POs", Colors.red.shade700, _generateAllPDFs),
          const SizedBox(width: 8),
          _actionBtn(Icons.send_rounded, "DISPATCH TO WHATSAPP", Colors.green.shade700, _dispatchToWhatsApp),
        ],
      ),
    );
  }

  void _saveToOrderConfirmation() async {
    final drafts = _fullList.where((i) => i.displayOrderQty > 0).toList();
    if (drafts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No items with order quantities to save."), backgroundColor: Colors.orange),
      );
      return;
    }

    final Map<String, List<AdvancedProductMovement>> grouped = {};
    for (var item in drafts) {
      final supplier = item.preferredWholesale.trim().isEmpty ? "Direct / General Wholesale" : item.preferredWholesale.trim();
      grouped.putIfAbsent(supplier, () => []).add(item);
    }

    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final now = DateTime.now();
    int count = 0;

    for (var entry in grouped.entries) {
      String supplier = entry.key;
      List<AdvancedProductMovement> items = entry.value;
      String orderId = "ORD-${DateFormat('yyyyMMdd').format(now)}-${(now.millisecondsSinceEpoch + count).toString().substring(8)}";

      List<OrderConfirmationItem> orderItems = items.map((i) => OrderConfirmationItem(
        orderId: orderId,
        productName: i.productName,
        company: i.company,
        orderQty: i.displayOrderQty,
        packSize: i.packSize,
        unitPrice: 0.0,
      )).toList();

      OrderConfirmation order = OrderConfirmation(
        orderId: orderId,
        orderDate: now,
        supplierName: supplier,
        totalItems: orderItems.length,
        totalAmount: 0.0,
        status: 'PENDING',
        expectedDeliveryDate: DateFormat('dd/MM/yyyy').format(now.add(const Duration(days: 2))),
        notes: "Generated from Smart Procurement Engine",
        createdAt: now,
        items: orderItems,
      );

      await provider.saveOrderConfirmation(order);
      count++;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Saved $count Order Confirmation(s) successfully! Retained up to 2 months."),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: "VIEW TRACKER",
            textColor: Colors.white,
            onPressed: () => appProvider.openOrderConfirmation(),
          ),
        ),
      );
    }
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
      onPressed: onTap,
    );
  }

  Widget _buildDraftsTab() {
    final drafts = _fullList.where((i) => i.finalOrderStrips > 0).toList();
    if (drafts.isEmpty) return _emptyState("No medicines have breached Reorder Points today.", Icons.check_circle_outline, Colors.green);
    return _buildGrid(drafts);
  }

  Widget _buildInventoryHealthTab() {
    // Overstock logic: 30-day sale * 6 < current balance
    final healthItems = _fullList.where((i) => (i.last30DaysSale * 6 < i.currentBalance && i.currentBalance > 0)).toList();
    if (healthItems.isEmpty) return _emptyState("Inventory levels look healthy. No significant overstock detected.", Icons.health_and_safety_outlined, Colors.blue);
    return _buildGrid(healthItems, isHealthTab: true);
  }

  Widget _buildManualOrdersTab() {
    return _emptyState("Manual order entry feature coming soon.", Icons.edit_note, Colors.orange);
  }

  Widget _buildGrid(List<AdvancedProductMovement> items, {bool isHealthTab = false}) {
    double totalWidth = _colWidths.values.fold(0, (sum, w) => sum + w);
    return Scrollbar(
      controller: _horizontalCtrl,
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: _horizontalCtrl,
        child: SizedBox(
          width: totalWidth,
          child: Column(
            children: [
              _buildGridHeader(),
              Expanded(
                child: Scrollbar(
                  controller: _verticalCtrl,
                  thumbVisibility: true,
                  child: ListView.builder(
                    cacheExtent: 300.0, controller: _verticalCtrl,
                    itemExtent: 35.0,
                    itemCount: items.length,
                    itemBuilder: (ctx, i) => _buildGridRow(items[i], isHealthTab),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridHeader() {
    return Container(
      height: 38,
      color: const Color(0xFF1E293B),
      child: Row(
        children: List.generate(10, (i) => _hdrCell(i, [
          "Rank", "Product", "Company", "Preferred Wholesale", "Balance", "30D Sale", "3M Max", "6M Max", "1Y Total/Count", "Order (Strips)"
        ][i])),
      ),
    );
  }

  Widget _hdrCell(int idx, String title) => Container(
    width: _colWidths[idx],
    alignment: Alignment.center,
    decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.white24, width: 0.5))),
    child: Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
  );

  Widget _buildGridRow(AdvancedProductMovement item, bool isHealthTab) {
    Color rowBg = Colors.white;
    if (isHealthTab) rowBg = Colors.red.shade50;

    return Container(
      height: 35,
      decoration: BoxDecoration(color: rowBg, border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
      child: Row(
        children: [
          _cell(0, "#${item.rank}", align: Alignment.center, color: Colors.grey),
          _cell(1, item.productName, bold: true),
          _cell(2, item.company, color: Colors.blueGrey),
          _cell(3, item.preferredWholesale, color: Colors.blue.shade700, bold: true),
          _cell(4, item.currentBalance.toString(), align: Alignment.center, bold: true, color: item.currentBalance == 0 ? Colors.red : Colors.black),
          _cell(5, item.last30DaysSale.toString(), align: Alignment.center),
          _cell(6, item.maxSale3Months.toString(), align: Alignment.center),
          _cell(7, item.maxSale6Months.toString(), align: Alignment.center),
          _cell(8, "${item.totalSale1Year}/${item.saleCount1Year}", align: Alignment.center, color: Colors.purple),

          // Order Edit Cell
          Container(
            width: _colWidths[9],
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: const BoxDecoration(color: Color(0xFFFFFDE7), border: Border(right: BorderSide(color: Colors.black12))),
            child: TextField(
              controller: TextEditingController(text: item.displayOrderQty.toString()),
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue),
              decoration: const InputDecoration(border: InputBorder.none, isDense: true),
              onChanged: (val) => item.manualOverrideQty = int.tryParse(val) ?? item.finalOrderStrips,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(int col, String val, {Color? color, bool bold = false, Alignment align = Alignment.centerLeft}) => Container(
    width: _colWidths[col],
    padding: const EdgeInsets.symmetric(horizontal: 8),
    alignment: align,
    decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black12, width: 0.5))),
    child: Text(val, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: color ?? Colors.black87, fontWeight: bold ? FontWeight.w800 : FontWeight.normal)),
  );

  Widget _emptyState(String msg, IconData icon, Color color) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 64, color: color.withValues(alpha: 0.2)),
        const SizedBox(height: 16),
        Text(msg, style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 14, fontStyle: FontStyle.italic)),
      ],
    ),
  );

  Widget _buildFooter() {
    int toOrder = _fullList.where((i) => i.displayOrderQty > 0).length;
    return Container(
      height: 40,
      color: const Color(0xFF1E293B),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          const Text("Ready for Dispatch: ", style: TextStyle(color: Colors.white70, fontSize: 12)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(20)),
            child: Text("$toOrder Items", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const Spacer(),
          const Icon(Icons.info_outline, color: Colors.white54, size: 14),
          const SizedBox(width: 8),
          const Text("Quantities rounded up to nearest Pack Size (Strip/Box)", style: TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }

  Future<void> _dispatchToWhatsApp() async {
    final toOrder = _fullList.where((i) => i.displayOrderQty > 0).toList();
    if (toOrder.isEmpty) {
      AppDialogs.showFastDialog(
        context: context,
        title: "No Draft Orders",
        content: "There are no purchase order items ready for dispatch. Please calculate or adjust order quantities first.",
      );
      return;
    }

    final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);

    // Group by Wholesale Supplier
    Map<String, List<AdvancedProductMovement>> grouped = {};
    for (var item in toOrder) {
      grouped.putIfAbsent(item.preferredWholesale, () => []).add(item);
    }

    if (grouped.length == 1) {
      final supplierName = grouped.keys.first;
      await _dispatchSingleSupplierWhatsApp(pharmacy, supplierName, grouped[supplierName]!);
    } else {
      final selectedSupplier = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text("Select Supplier for WhatsApp Dispatch", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          children: grouped.keys.map((sName) {
            int itemCount = grouped[sName]!.length;
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, sName),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  children: [
                    const Icon(Icons.store, color: Colors.teal),
                    const SizedBox(width: 10),
                    Expanded(child: Text(sName, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Text("$itemCount items", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      );

      if (selectedSupplier != null && grouped.containsKey(selectedSupplier)) {
        await _dispatchSingleSupplierWhatsApp(pharmacy, selectedSupplier, grouped[selectedSupplier]!);
      }
    }
  }

  Future<void> _dispatchSingleSupplierWhatsApp(
    PharmacyProvider pharmacy,
    String supplierName,
    List<AdvancedProductMovement> items,
  ) async {
    final supp = pharmacy.supplierMaster.firstWhere(
      (s) => s.name.trim().toLowerCase() == supplierName.trim().toLowerCase(),
      orElse: () => Supplier(id: "", name: supplierName, phone: ""),
    );

    String phone = supp.phone;
    if (phone.trim().isEmpty) {
      final phoneCtrl = TextEditingController();
      final enteredPhone = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text("Enter Mobile Number for $supplierName"),
          content: TextField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: "10-digit WhatsApp Mobile Number",
              hintText: "e.g. 9876543210",
              prefixIcon: Icon(Icons.phone),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, phoneCtrl.text.trim()),
              child: const Text("Send PO"),
            ),
          ],
        ),
      );

      if (enteredPhone == null || enteredPhone.isEmpty) return;
      phone = enteredPhone;
    }

    final formattedItems = items.map((i) => {
      'name': i.productName,
      'qty': i.displayOrderQty,
    }).toList();

    if (!mounted) return;
    await WhatsAppService.sendPurchaseOrder(
      context: context,
      supplierName: supplierName,
      supplierMobile: phone,
      companyName: pharmacy.companyProfile.name,
      items: formattedItems,
    );
  }

  // --- PDF GENERATION LOGIC (Enterprise Splitting) ---
  Future<void> _generateAllPDFs() async {
    final toOrder = _fullList.where((i) => i.displayOrderQty > 0).toList();
    if (toOrder.isEmpty) return;

    // Group by Wholesale
    Map<String, List<AdvancedProductMovement>> grouped = {};
    for (var item in toOrder) {
      grouped.putIfAbsent(item.preferredWholesale, () => []).add(item);
    }

    for (var entry in grouped.entries) {
      await _generateSingleSupplierPDF(entry.key, entry.value);
    }
  }

  Future<void> _generateSingleSupplierPDF(String supplier, List<AdvancedProductMovement> items) async {
    final pdf = pw.Document();
    final now = DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now());

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("PURCHASE ORDER", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                        pw.Text("SAHAKAR MEDICALS", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text("Date: $now"),
                        pw.Text("Supplier: ${supplier.toUpperCase()}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _pdfHdr("Sl"), _pdfHdr("Product Description"), _pdfHdr("Company"), _pdfHdr("Qty (Strips)"),
                    ],
                  ),
                  ...items.asMap().entries.map((e) => pw.TableRow(
                    children: [
                      _pdfCell((e.key + 1).toString()),
                      _pdfCell(e.value.productName),
                      _pdfCell(e.value.company),
                      _pdfCell(e.value.displayOrderQty.toString(), align: pw.TextAlign.center),
                    ],
                  )),
                ],
              ),
              pw.Spacer(),
              pw.Divider(color: PdfColors.grey),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Generated by Smart Procurement Engine", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  pw.Text("Authorized Signature", style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  pw.Widget _pdfHdr(String t) => pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(t, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)));
  pw.Widget _pdfCell(String t, {pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(t, style: const pw.TextStyle(fontSize: 10), textAlign: align));
}
