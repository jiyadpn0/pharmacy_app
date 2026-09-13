import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/pharmacy_provider.dart';
import '../../widgets/app_date_picker.dart';
import '../../utils/report_pdf_generator.dart';
import '../../utils/printer_service.dart';
import '../../services/whatsapp_service.dart';
import '../../utils/theme_constants.dart';
import '../../widgets/erp_tooltip.dart';

class CashCounterData {
  int count500;
  int count200;
  int count100;
  int count50;
  int count20;
  int count10;
  int count5;
  double coins;
  double upi;
  double card;

  CashCounterData({
    this.count500 = 0,
    this.count200 = 0,
    this.count100 = 0,
    this.count50 = 0,
    this.count20 = 0,
    this.count10 = 0,
    this.count5 = 0,
    this.coins = 0.0,
    this.upi = 0.0,
    this.card = 0.0,
  });

  double get cashTotal =>
      (count500 * 500) +
      (count200 * 200) +
      (count100 * 100) +
      (count50 * 50) +
      (count20 * 20) +
      (count10 * 10) +
      (count5 * 5) +
      coins;

  double get digitalTotal => upi + card;

  double get grandTotal => cashTotal + digitalTotal;

  Map<String, dynamic> toJson() => {
        'count500': count500,
        'count200': count200,
        'count100': count100,
        'count50': count50,
        'count20': count20,
        'count10': count10,
        'count5': count5,
        'coins': coins,
        'upi': upi,
        'card': card,
      };

  factory CashCounterData.fromJson(Map<String, dynamic> json) {
    return CashCounterData(
      count500: (json['count500'] as num?)?.toInt() ?? 0,
      count200: (json['count200'] as num?)?.toInt() ?? 0,
      count100: (json['count100'] as num?)?.toInt() ?? 0,
      count50: (json['count50'] as num?)?.toInt() ?? 0,
      count20: (json['count20'] as num?)?.toInt() ?? 0,
      count10: (json['count10'] as num?)?.toInt() ?? 0,
      count5: (json['count5'] as num?)?.toInt() ?? 0,
      coins: (json['coins'] as num?)?.toDouble() ?? 0.0,
      upi: (json['upi'] as num?)?.toDouble() ?? 0.0,
      card: (json['card'] as num?)?.toDouble() ?? 0.0,
    );
  }

  CashCounterData copy() {
    return CashCounterData(
      count500: count500,
      count200: count200,
      count100: count100,
      count50: count50,
      count20: count20,
      count10: count10,
      count5: count5,
      coins: coins,
      upi: upi,
      card: card,
    );
  }
}

class DetailLineItem {
  String id;
  String name;
  double amount;
  String note;

  DetailLineItem({
    required this.id,
    required this.name,
    required this.amount,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'amount': amount,
        'note': note,
      };

  factory DetailLineItem.fromJson(Map<String, dynamic> json) {
    return DetailLineItem(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      note: json['note'] as String? ?? '',
    );
  }

  DetailLineItem copy() {
    return DetailLineItem(
      id: id,
      name: name,
      amount: amount,
      note: note,
    );
  }
}

class _DialogRowHolder {
  final DetailLineItem item;
  final TextEditingController nameCtrl;
  final TextEditingController noteCtrl;
  final TextEditingController amountCtrl;

  _DialogRowHolder(this.item)
      : nameCtrl = TextEditingController(text: item.name),
        noteCtrl = TextEditingController(text: item.note),
        amountCtrl = TextEditingController(
            text: item.amount == 0.0 ? '' : (item.amount % 1 == 0 ? item.amount.toInt().toString() : item.amount.toString()));

  void dispose() {
    nameCtrl.dispose();
    noteCtrl.dispose();
    amountCtrl.dispose();
  }

  void syncToItem() {
    item.name = nameCtrl.text.trim();
    item.note = noteCtrl.text.trim();
    item.amount = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
  }
}

class DailyReportScreen extends StatefulWidget {
  const DailyReportScreen({super.key});

  @override
  State<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends State<DailyReportScreen> {
  DateTime _selectedDate = DateTime.now();
  DateTime _historyMonth = DateTime.now();
  bool _isLoading = false;
  bool _isShowingMonthSummary = false;

  List<SaleInvoice> _monthSales = [];
  List<PurchaseEntry> _monthPurchases = [];
  List<SaleReturnInvoice> _monthReturns = [];

  String? _selectedStaff; // null = Show Staff Selector view, "ALL" or staff name

  List<String> get _baseStaffList => ["ALL", ...Provider.of<PharmacyProvider>(context, listen: false).staffNames];

  List<SaleInvoice> _allDaySales = [];
  List<SaleInvoice> _daySales = [];
  List<PurchaseEntry> _dayPurchases = [];
  List<SupplierPayment> _daySupplierPayments = [];
  List<SaleReturnInvoice> _dayReturns = [];
  List<StockWriteOff> _dayDamages = [];

  CashCounterData _openingCounter = CashCounterData();
  CashCounterData _closingCounter = CashCounterData();

  // Multi-item detail lists for all categories
  List<DetailLineItem> _creditPaymentItems = [];
  List<DetailLineItem> _prePaymentItems = [];
  List<DetailLineItem> _notReceivedItems = [];
  List<DetailLineItem> _salesReturnItems = [];
  List<DetailLineItem> _expenseItems = [];
  List<DetailLineItem> _supplierPaidItems = [];
  List<DetailLineItem> _purchaseItems = [];
  List<DetailLineItem> _cashToBankItems = [];
  List<DetailLineItem> _bankToCashItems = [];

  // Headings Filter Dropdown Selection
  Set<String> _selectedHeadings = {
    'PRE_ENTER',
    'DIFFERENCE',
    'NOT_RECEIVED',
    'SALES_RETURN',
    'EXPENSES',
  };

  List<CustomHeadingData> _customHeadings = [];

  bool get _showPreEnter => _selectedHeadings.contains('PRE_ENTER');
  bool get _showDifference => _selectedHeadings.contains('DIFFERENCE');
  bool get _showNotReceived => _selectedHeadings.contains('NOT_RECEIVED');
  bool get _showSalesReturn => _selectedHeadings.contains('SALES_RETURN');
  bool get _showExpenses => _selectedHeadings.contains('EXPENSES');

  Widget _buildHeadingsFilterDropdown() {
    return PopupMenuButton<String>(
      tooltip: "Select Headings to Include",
      onSelected: (value) {
        setState(() {
          if (_selectedHeadings.contains(value)) {
            if (_selectedHeadings.length > 1) {
              _selectedHeadings.remove(value);
            }
          } else {
            _selectedHeadings.add(value);
          }
        });
      },
      itemBuilder: (ctx) => [
        _buildHeadingMenuItem('PRE_ENTER', 'PRE ENTER HEADINGS'),
        _buildHeadingMenuItem('DIFFERENCE', 'DIFFERENCE'),
        _buildHeadingMenuItem('NOT_RECEIVED', 'NOT RECEIVED (WITH NAME)'),
        _buildHeadingMenuItem('SALES_RETURN', 'SALES RETURN'),
        _buildHeadingMenuItem('EXPENSES', 'EXPENSES WITH EXPENSE NAME'),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade300, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list_rounded, size: 16, color: Colors.blue.shade800),
            const SizedBox(width: 6),
            Text(
              "Headings Filter (${_selectedHeadings.length}/5)",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.blue.shade900),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 18, color: Colors.blue.shade800),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildHeadingMenuItem(String value, String label) {
    final bool isChecked = _selectedHeadings.contains(value);
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(
            isChecked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
            color: isChecked ? Colors.blue.shade800 : Colors.grey,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
                color: isChecked ? Colors.blue.shade900 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddCustomHeadingDialog() {
    final headingNameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String? selectedPreset;

    final presets = [
      "STAFF SALARY & ADVANCE",
      "RENT & MAINTENANCE",
      "ELECTRICITY & UTILITIES",
      "MISCELLANEOUS OUTFLOWS",
      "OFFICE SUPPLIES & TEA",
      "DIRECT EXPENSES",
    ];

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: const [
              Icon(Icons.add_chart_rounded, color: Colors.purple, size: 22),
              SizedBox(width: 8),
              Text("ADD HEADING FROM ADMIN DAY BOOK", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Select Preset Heading from Day Book:", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: presets.map((preset) {
                    final isSelected = selectedPreset == preset;
                    return ChoiceChip(
                      label: Text(preset, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87)),
                      selected: isSelected,
                      selectedColor: Colors.purple.shade700,
                      backgroundColor: Colors.purple.shade50,
                      onSelected: (selected) {
                        setDialogState(() {
                          selectedPreset = selected ? preset : null;
                          if (selected) {
                            headingNameCtrl.text = preset;
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: headingNameCtrl,
                  decoration: const InputDecoration(
                    labelText: "Custom Heading Name",
                    hintText: "e.g. MAINTENANCE, SALARY, etc.",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: "Initial Amount (₹)",
                    hintText: "0.00",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text("CANCEL"),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text("ADD HEADING"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final name = headingNameCtrl.text.trim().toUpperCase();
                if (name.isNotEmpty) {
                  final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                  final newHeading = CustomHeadingData(
                    id: "h_${DateTime.now().millisecondsSinceEpoch}",
                    name: name,
                    amount: amt,
                  );
                  setState(() {
                    _customHeadings.add(newHeading);
                  });
                  Navigator.pop(dialogCtx);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openHeadingDetailView({
    required String headingTitle,
    required Color color,
    required List<HeadingDetailRecord> records,
  }) {
    final searchCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final query = searchCtrl.text.trim().toLowerCase();
            final filteredRecords = records.where((r) {
              return r.name.toLowerCase().contains(query) ||
                  r.remark.toLowerCase().contains(query) ||
                  r.dateStr.toLowerCase().contains(query);
            }).toList();

            final totalAmt = filteredRecords.fold(0.0, (sum, r) => sum + r.amount);

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              clipBehavior: Clip.antiAlias,
              child: Container(
                width: 920,
                height: 600,
                color: const Color(0xFFF8FAFC),
                child: Column(
                  children: [
                    // Header Bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      color: color,
                      child: Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => Navigator.pop(dialogCtx),
                            icon: const Icon(Icons.arrow_back_rounded, size: 16),
                            label: const Text("BACK TO REPORT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white24,
                              foregroundColor: Colors.white,
                              elevation: 0,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Icon(Icons.format_list_bulleted_rounded, color: Colors.white, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "DETAILED ITEM LIST: ${headingTitle.toUpperCase()}",
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              "TOTAL: ₹ ${totalAmt.toStringAsFixed(2)} (${filteredRecords.length} Items)",
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white),
                            onPressed: () => Navigator.pop(dialogCtx),
                          ),
                        ],
                      ),
                    ),

                    // Filter Search Input Bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      color: Colors.white,
                      child: TextField(
                        controller: searchCtrl,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          hintText: "Search by Name, Remark, or Day...",
                          prefixIcon: const Icon(Icons.search, size: 18),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          suffixIcon: searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    searchCtrl.clear();
                                    setDialogState(() {});
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),
                    const Divider(height: 1),

                    // Items List Table with DAY, NAME, REMARK, AMOUNT
                    Expanded(
                      child: filteredRecords.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.inbox_rounded, size: 48, color: Colors.grey.shade400),
                                  const SizedBox(height: 10),
                                  const Text("No detailed records found for this heading.", style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            )
                          : SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: DataTable(
                                  headingRowHeight: 36,
                                  dataRowMinHeight: 32,
                                  dataRowMaxHeight: 40,
                                  headingRowColor: WidgetStateProperty.all(color.withValues(alpha: 0.1)),
                                  columns: const [
                                    DataColumn(label: Text("#", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                    DataColumn(label: Text("DAY / DATE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                    DataColumn(label: Text("NAME", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                    DataColumn(label: Text("REMARK", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                    DataColumn(label: Text("AMOUNT (₹)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                  ],
                                  rows: filteredRecords.asMap().entries.map((entry) {
                                    final idx = entry.key + 1;
                                    final item = entry.value;
                                    return DataRow(cells: [
                                      DataCell(Text("$idx", style: const TextStyle(fontSize: 11, color: Colors.grey))),
                                      DataCell(Text(item.dateStr, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                      DataCell(Text(item.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                                      DataCell(Text(item.remark.isNotEmpty ? item.remark : "-", style: const TextStyle(fontSize: 11, color: Colors.blueGrey))),
                                      DataCell(Text("₹ ${item.amount.toStringAsFixed(2)}", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: item.amount >= 0 ? color : Colors.red))),
                                    ]);
                                  }).toList(),
                                ),
                              ),
                            ),
                    ),

                    // Bottom Total Footer Bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      color: Colors.white,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Total Entries: ${filteredRecords.length} items", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                          Row(
                            children: [
                              const Text("TOTAL AMOUNT: ", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
                              Text("₹ ${totalAmt.toStringAsFixed(2)}", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  bool _hasCustomCreditPayments = false;
  bool _hasCustomPrePayments = false;
  bool _hasCustomNotReceived = false;
  bool _hasCustomSalesReturns = false;
  bool _hasCustomExpenses = false;
  bool _hasCustomSupplierPaid = false;
  bool _hasCustomPurchases = false;
  bool _hasCustomCashToBank = false;
  bool _hasCustomBankToCash = false;
  bool _isTotalSaleSynced = false;
  double? _customTotalSaleAmount;
  bool _autoFetchOpeningSale = true;
  bool _autoFetchClosingSale = true;
  String? _customOpeningBillNo;
  String? _customOpeningTimeStr;
  double? _customOpeningAmount;
  String? _customClosingBillNo;
  String? _customClosingTimeStr;
  double? _customClosingAmount;

  double get totalCreditPayments => _creditPaymentItems.fold(0.0, (sum, i) => sum + i.amount);
  double get totalPrePayments => _prePaymentItems.fold(0.0, (sum, i) => sum + i.amount);
  double get totalNotReceived => _notReceivedItems.fold(0.0, (sum, i) => sum + i.amount);
  double get totalSalesReturns => _salesReturnItems.fold(0.0, (sum, i) => sum + i.amount);
  double get totalExpenses => _expenseItems.fold(0.0, (sum, i) => sum + i.amount);
  double get totalSupplierPaid => _supplierPaidItems.fold(0.0, (sum, i) => sum + i.amount);
  double get totalPurchases => _purchaseItems.fold(0.0, (sum, i) => sum + i.amount);
  double get totalCashToBank => _cashToBankItems.fold(0.0, (sum, i) => sum + i.amount);
  double get totalBankToCash => _bankToCashItems.fold(0.0, (sum, i) => sum + i.amount);

  double _cashSales = 0.0;
  double _upiSales = 0.0;
  double _cardSales = 0.0;
  double _creditSales = 0.0;
  double _totalSales = 0.0;

  void _recalculateMetrics() {
    double cs = 0.0, us = 0.0, cds = 0.0, crs = 0.0, ts = 0.0;
    for (int i = 0; i < _daySales.length; i++) {
      final s = _daySales[i];
      final acc = s.customerAcc.toUpperCase();
      final gt = s.grandTotal;
      ts += gt;
      if (acc == "CASH") {
        cs += gt;
      } else if (acc == "UPI") {
        us += gt;
      } else if (acc == "CARD") {
        cds += gt;
      } else if (acc == "CREDIT") {
        crs += gt;
      }
    }
    _cashSales = cs;
    _upiSales = us;
    _cardSales = cds;
    _creditSales = crs;
    _totalSales = ts;
  }

  double get cashSales => _cashSales;
  double get upiSales => _upiSales;
  double get cardSales => _cardSales;
  double get creditSales => _creditSales;
  double get totalSales => _totalSales;

  double get totalInflow => (_customTotalSaleAmount ?? totalSales) + totalCreditPayments + totalPrePayments + totalBankToCash;
  double get totalOutflow => totalSalesReturns + totalSupplierPaid + totalExpenses + totalCashToBank;

  double get expectedCashInDrawer => _openingCounter.cashTotal + cashSales + totalCreditPayments + totalPrePayments + totalBankToCash - totalSalesReturns - totalSupplierPaid - totalExpenses - totalCashToBank;
  double get actualClosingCash => _closingCounter.cashTotal;
  double get totalDifference => actualClosingCash - expectedCashInDrawer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchDayRecords());
  }

  String _dateKey(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt);

  String _staffStorageKey() {
    final staffTag = (_selectedStaff == null || _selectedStaff == "ALL") ? "ALL" : _selectedStaff!.replaceAll(" ", "_");
    return "${_dateKey(_selectedDate)}_$staffTag";
  }

  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> _loadSettingsForDate() async {
    final prefs = await _getPrefs();
    final keyTag = _staffStorageKey();

    final openRaw = prefs.getString("cash_counter_opening_$keyTag");
    final closeRaw = prefs.getString("cash_counter_closing_$keyTag");

    _openingCounter = openRaw != null ? CashCounterData.fromJson(jsonDecode(openRaw)) : CashCounterData();
    _closingCounter = closeRaw != null ? CashCounterData.fromJson(jsonDecode(closeRaw)) : CashCounterData();

    List<DetailLineItem> loadList(String prefKey, Function(bool) setHasCustom) {
      final raw = prefs.getString(prefKey);
      if (raw != null) {
        try {
          final List parsed = jsonDecode(raw);
          setHasCustom(true);
          return parsed.map((e) => DetailLineItem.fromJson(e)).toList();
        } catch (_) {}
      }
      setHasCustom(false);
      return [];
    }

    _creditPaymentItems = loadList("items_credit_payments_$keyTag", (v) => _hasCustomCreditPayments = v);
    _prePaymentItems = loadList("items_pre_payments_$keyTag", (v) => _hasCustomPrePayments = v);
    _notReceivedItems = loadList("items_not_received_$keyTag", (v) => _hasCustomNotReceived = v);
    _salesReturnItems = loadList("items_sales_return_$keyTag", (v) => _hasCustomSalesReturns = v);
    _expenseItems = loadList("items_expenses_$keyTag", (v) => _hasCustomExpenses = v);
    _supplierPaidItems = loadList("items_supplier_paid_$keyTag", (v) => _hasCustomSupplierPaid = v);
    _purchaseItems = loadList("items_purchases_$keyTag", (v) => _hasCustomPurchases = v);
    _cashToBankItems = loadList("items_cash_to_bank_$keyTag", (v) => _hasCustomCashToBank = v);
    _bankToCashItems = loadList("items_bank_to_cash_$keyTag", (v) => _hasCustomBankToCash = v);

    _isTotalSaleSynced = prefs.getBool("total_sale_synced_$keyTag") ?? false;
    _customTotalSaleAmount = prefs.getDouble("total_sale_amount_$keyTag");
    _autoFetchOpeningSale = prefs.getBool("auto_fetch_opening_sale_$keyTag") ?? true;
    _autoFetchClosingSale = prefs.getBool("auto_fetch_closing_sale_$keyTag") ?? true;
    _customOpeningBillNo = prefs.getString("custom_opening_bill_$keyTag");
    _customOpeningTimeStr = prefs.getString("custom_opening_time_$keyTag");
    _customOpeningAmount = prefs.getDouble("custom_opening_amount_$keyTag");
    _customClosingBillNo = prefs.getString("custom_closing_bill_$keyTag");
    _customClosingTimeStr = prefs.getString("custom_closing_time_$keyTag");
    _customClosingAmount = prefs.getDouble("custom_closing_amount_$keyTag");
  }

  Future<void> _saveSettingsForDate() async {
    final prefs = await _getPrefs();
    final keyTag = _staffStorageKey();

    prefs.setString("cash_counter_opening_$keyTag", jsonEncode(_openingCounter.toJson()));
    prefs.setString("cash_counter_closing_$keyTag", jsonEncode(_closingCounter.toJson()));
    prefs.setString("items_credit_payments_$keyTag", jsonEncode(_creditPaymentItems.map((e) => e.toJson()).toList()));
    prefs.setString("items_pre_payments_$keyTag", jsonEncode(_prePaymentItems.map((e) => e.toJson()).toList()));
    prefs.setString("items_not_received_$keyTag", jsonEncode(_notReceivedItems.map((e) => e.toJson()).toList()));
    prefs.setString("items_sales_return_$keyTag", jsonEncode(_salesReturnItems.map((e) => e.toJson()).toList()));
    prefs.setString("items_expenses_$keyTag", jsonEncode(_expenseItems.map((e) => e.toJson()).toList()));
    prefs.setString("items_supplier_paid_$keyTag", jsonEncode(_supplierPaidItems.map((e) => e.toJson()).toList()));
    prefs.setString("items_purchases_$keyTag", jsonEncode(_purchaseItems.map((e) => e.toJson()).toList()));
    prefs.setString("items_cash_to_bank_$keyTag", jsonEncode(_cashToBankItems.map((e) => e.toJson()).toList()));
    prefs.setString("items_bank_to_cash_$keyTag", jsonEncode(_bankToCashItems.map((e) => e.toJson()).toList()));
    prefs.setBool("total_sale_synced_$keyTag", _isTotalSaleSynced);
    prefs.setBool("auto_fetch_opening_sale_$keyTag", _autoFetchOpeningSale);
    prefs.setBool("auto_fetch_closing_sale_$keyTag", _autoFetchClosingSale);
    if (_customOpeningBillNo != null) {
      prefs.setString("custom_opening_bill_$keyTag", _customOpeningBillNo!);
    } else {
      prefs.remove("custom_opening_bill_$keyTag");
    }
    if (_customOpeningTimeStr != null) {
      prefs.setString("custom_opening_time_$keyTag", _customOpeningTimeStr!);
    } else {
      prefs.remove("custom_opening_time_$keyTag");
    }
    if (_customOpeningAmount != null) {
      prefs.setDouble("custom_opening_amount_$keyTag", _customOpeningAmount!);
    } else {
      prefs.remove("custom_opening_amount_$keyTag");
    }
    if (_customClosingBillNo != null) {
      prefs.setString("custom_closing_bill_$keyTag", _customClosingBillNo!);
    } else {
      prefs.remove("custom_closing_bill_$keyTag");
    }
    if (_customClosingTimeStr != null) {
      prefs.setString("custom_closing_time_$keyTag", _customClosingTimeStr!);
    } else {
      prefs.remove("custom_closing_time_$keyTag");
    }
    if (_customClosingAmount != null) {
      prefs.setDouble("custom_closing_amount_$keyTag", _customClosingAmount!);
    } else {
      prefs.remove("custom_closing_amount_$keyTag");
    }
    if (_customTotalSaleAmount != null) {
      prefs.setDouble("total_sale_amount_$keyTag", _customTotalSaleAmount!);
    } else {
      prefs.remove("total_sale_amount_$keyTag");
    }
  }

  Future<void> _fetchDayRecords() async {
    setState(() => _isLoading = true);

    final p = Provider.of<PharmacyProvider>(context, listen: false);

    final startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 0, 0, 0);
    final endOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);

    final sales = await p.fetchSalesInDateRange(startOfDay, endOfDay, loadItems: false, limit: 1000, offset: 0);
    final purchases = await p.fetchPurchasesInDateRange(startOfDay, endOfDay, loadItems: false, limit: 1000, offset: 0);
    final returns = await p.fetchSaleReturnsInDateRange(startOfDay, endOfDay, loadItems: false, limit: 1000, offset: 0);

    final supplierPays = p.supplierPayments.where((sp) {
      final spd = DateTime(sp.date.year, sp.date.month, sp.date.day);
      return spd.isAtSameMomentAs(DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day));
    }).toList();

    final damages = p.writeOffs.where((wo) {
      final wod = DateTime(wo.date.year, wo.date.month, wo.date.day);
      return wod.isAtSameMomentAs(DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day));
    }).toList();

    _allDaySales = sales.where((s) => !s.isDeleted).toList();

    if (_selectedStaff != null) {
      await _loadSettingsForDate();

      if (_selectedStaff == "ALL") {
        _daySales = List.from(_allDaySales);
      } else {
        final target = _selectedStaff!.trim().toLowerCase();
        _daySales = _allDaySales.where((s) => s.agent.trim().toLowerCase() == target).toList();
      }

      _recalculateMetrics();

      _dayPurchases = purchases.where((pe) => !pe.isDeleted).toList();
      _dayReturns = returns.where((r) => !r.isDeleted).toList();
      _daySupplierPayments = supplierPays;
      _dayDamages = damages;

      if (!_hasCustomNotReceived) {
        final creditSalesInvoices = _daySales.where((s) => s.customerAcc.toUpperCase() == "CREDIT").toList();
        _notReceivedItems = creditSalesInvoices
            .map((s) => DetailLineItem(
                  id: s.entryNo,
                  name: s.patient.isEmpty ? "Credit Customer #${s.entryNo}" : "${s.patient} (Bill #${s.entryNo})",
                  amount: s.grandTotal,
                ))
            .toList();
      }

      if (!_hasCustomSalesReturns) {
        _salesReturnItems = _dayReturns
            .map((r) => DetailLineItem(
                  id: r.entryNo,
                  name: "Sales Return #${r.entryNo}",
                  amount: r.grandTotal,
                ))
            .toList();
      }

      if (!_hasCustomSupplierPaid) {
        _supplierPaidItems = _daySupplierPayments
            .map((sp) => DetailLineItem(
                  id: sp.id,
                  name: "Payment to ${sp.supplierName}",
                  amount: sp.amount,
                ))
            .toList();
      }

      if (!_hasCustomPurchases) {
        _purchaseItems = _dayPurchases
            .map((p) => DetailLineItem(
                  id: p.entryNo,
                  name: "Purchase #${p.entryNo} (${p.supplierName})",
                  amount: p.grandTotal,
                ))
            .toList();
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _selectStaff(String staffName) async {
    _selectedStaff = staffName;
    await _fetchDayRecords();
  }

  void _showCashCounterDialog({required bool isOpening}) {
    final currentData = isOpening ? _openingCounter.copy() : _closingCounter.copy();

    final c500 = TextEditingController(text: currentData.count500 == 0 ? '' : currentData.count500.toString());
    final c200 = TextEditingController(text: currentData.count200 == 0 ? '' : currentData.count200.toString());
    final c100 = TextEditingController(text: currentData.count100 == 0 ? '' : currentData.count100.toString());
    final c50 = TextEditingController(text: currentData.count50 == 0 ? '' : currentData.count50.toString());
    final c20 = TextEditingController(text: currentData.count20 == 0 ? '' : currentData.count20.toString());
    final c10 = TextEditingController(text: currentData.count10 == 0 ? '' : currentData.count10.toString());
    final c5 = TextEditingController(text: currentData.count5 == 0 ? '' : currentData.count5.toString());
    final cCoins = TextEditingController(text: currentData.coins == 0.0 ? '' : currentData.coins.toStringAsFixed(2));
    final cUpi = TextEditingController(text: currentData.upi == 0.0 ? '' : currentData.upi.toStringAsFixed(2));
    final cCard = TextEditingController(text: currentData.card == 0.0 ? '' : currentData.card.toStringAsFixed(2));

    final f500 = FocusNode();
    final f200 = FocusNode();
    final f100 = FocusNode();
    final f50 = FocusNode();
    final f20 = FocusNode();
    final f10 = FocusNode();
    final f5 = FocusNode();
    final fCoins = FocusNode();
    final fUpi = FocusNode();
    final fCard = FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      f500.requestFocus();
    });

    showDialog(
      context: context,
      builder: (dialogContext) {
        void saveCounter() {
          if (isOpening) {
            _openingCounter = currentData;
          } else {
            _closingCounter = currentData;
          }
          if (mounted) setState(() {});
          Navigator.pop(dialogContext);
          _saveSettingsForDate();
        }

        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            void updateState() {
              currentData.count500 = int.tryParse(c500.text.trim()) ?? 0;
              currentData.count200 = int.tryParse(c200.text.trim()) ?? 0;
              currentData.count100 = int.tryParse(c100.text.trim()) ?? 0;
              currentData.count50 = int.tryParse(c50.text.trim()) ?? 0;
              currentData.count20 = int.tryParse(c20.text.trim()) ?? 0;
              currentData.count10 = int.tryParse(c10.text.trim()) ?? 0;
              currentData.count5 = int.tryParse(c5.text.trim()) ?? 0;
              currentData.coins = double.tryParse(cCoins.text.trim()) ?? 0.0;
              currentData.upi = double.tryParse(cUpi.text.trim()) ?? 0.0;
              currentData.card = double.tryParse(cCard.text.trim()) ?? 0.0;
              setDialogState(() {});
            }

            Widget denomRow(
              String label,
              int value,
              TextEditingController ctrl,
              FocusNode focusNode,
              FocusNode nextFocusNode,
            ) {
              final subtotal = (int.tryParse(ctrl.text.trim()) ?? 0) * value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 75,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
                      child: Text("₹ $value", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, color: Colors.blue.shade900, fontSize: 13)),
                    ),
                    const SizedBox(width: 10),
                    const Text("x", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        focusNode: focusNode,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          hintText: "Count",
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onChanged: (_) => updateState(),
                        onSubmitted: (_) {
                          updateState();
                          nextFocusNode.requestFocus();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: Text("₹ ${subtotal.toStringAsFixed(2)}", textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.black87)),
                    ),
                  ],
                ),
              );
            }

            Widget coinsRow(
              String label,
              TextEditingController ctrl,
              FocusNode focusNode,
              VoidCallback onFinalSubmitted,
            ) {
              final amount = double.tryParse(ctrl.text.trim()) ?? 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 75,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
                      child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, color: Colors.blue.shade900, fontSize: 12)),
                    ),
                    const SizedBox(width: 10),
                    const Text("=", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        focusNode: focusNode,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          hintText: "Amount (₹)",
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onChanged: (_) => updateState(),
                        onSubmitted: (_) {
                          updateState();
                          onFinalSubmitted();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: Text("₹ ${amount.toStringAsFixed(2)}", textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.black87)),
                    ),
                  ],
                ),
              );
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 520,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(isOpening ? Icons.play_circle_fill_rounded : Icons.stop_circle_rounded, color: isOpening ? Colors.green.shade700 : Colors.indigo.shade700, size: 24),
                        const SizedBox(width: 10),
                        Text(
                          isOpening ? "OPENING CASH COUNTER (${_selectedStaff ?? 'ALL'})" : "CLOSING CASH COUNTER (${_selectedStaff ?? 'ALL'})",
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF1E293B)),
                        ),
                        const Spacer(),
                        IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close)),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 6),
                    denomRow("500", 500, c500, f500, f200),
                    denomRow("200", 200, c200, f200, f100),
                    denomRow("100", 100, c100, f100, f50),
                    denomRow("50", 50, c50, f50, f20),
                    denomRow("20", 20, c20, f20, f10),
                    denomRow("10", 10, c10, f10, f5),
                    denomRow("5", 5, c5, f5, fCoins),
                    coinsRow("COINS", cCoins, fCoins, saveCounter),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("TOTAL CASH COUNTER BALANCE", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                          Text("₹ ${currentData.cashTotal.toStringAsFixed(2)}", style: const TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text("CANCEL"),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: saveCounter,
                          icon: const Icon(Icons.check_circle_rounded, size: 16),
                          label: Text(isOpening ? "SAVE OPENING COUNTER" : "SAVE CLOSING COUNTER", style: const TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isOpening ? Colors.green.shade700 : Colors.indigo.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showMultiItemListDialog({
    required String title,
    required List<DetailLineItem> currentItems,
    required Function(List<DetailLineItem>) onSave,
    VoidCallback? onRestoreAuto,
    required Color primaryColor,
  }) {
    final rowHolders = currentItems.map((e) => _DialogRowHolder(e.copy())).toList();
    final searchCtrl = TextEditingController();
    final totalNotifier = ValueNotifier<double>(rowHolders.fold(0.0, (s, r) => s + r.item.amount));

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final filterQuery = searchCtrl.text.trim().toLowerCase();
            final filteredHolders = rowHolders.where((h) {
              return h.nameCtrl.text.toLowerCase().contains(filterQuery) ||
                     h.noteCtrl.text.toLowerCase().contains(filterQuery);
            }).toList();

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 780,
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header Bar with BACK / CLOSE Button
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            for (var r in rowHolders) { r.dispose(); }
                            Navigator.pop(dialogCtx);
                          },
                          icon: const Icon(Icons.arrow_back_rounded, size: 16),
                          label: const Text("BACK TO FLOW", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade800,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Icon(Icons.format_list_bulleted_rounded, color: primaryColor, size: 24),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: primaryColor)),
                              Text("Staff: ${_selectedStaff ?? 'ALL'}", style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            for (var r in rowHolders) { r.dispose(); }
                            Navigator.pop(dialogCtx);
                          },
                          icon: const Icon(Icons.close_rounded, size: 22),
                          tooltip: "Close Modal",
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 6),

                    // Table Column Headers
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: Colors.blueGrey.shade900, borderRadius: BorderRadius.circular(6)),
                      child: const Row(
                        children: [
                          Expanded(flex: 4, child: Text("NAME / ACCOUNT / PARTY", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                          SizedBox(width: 8),
                          Expanded(flex: 3, child: Text("REMARK / NOTE", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                          SizedBox(width: 8),
                          Expanded(flex: 2, child: Text("AMOUNT (₹)", textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
                          SizedBox(width: 48, child: Text("ACTION", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Items List
                    Expanded(
                      child: rowHolders.isEmpty
                          ? const Center(child: Text("No entries added yet. Click '+ ADD NEW ENTRY' below.", style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: rowHolders.length,
                              itemBuilder: (context, i) {
                                final holder = rowHolders[i];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
                                  ),
                                  child: Row(
                                    children: [
                                      // NAME COLUMN (Flex 4)
                                      Expanded(
                                        flex: 4,
                                        child: TextField(
                                          controller: holder.nameCtrl,
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            hintText: "Enter Name / Account",
                                            border: OutlineInputBorder(),
                                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          ),
                                          onChanged: (_) => holder.syncToItem(),
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // REMARK COLUMN (Flex 3)
                                      Expanded(
                                        flex: 3,
                                        child: TextField(
                                          controller: holder.noteCtrl,
                                          style: const TextStyle(fontSize: 12),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            hintText: "Remark / Note (Optional)",
                                            border: OutlineInputBorder(),
                                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          ),
                                          onChanged: (_) => holder.syncToItem(),
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // AMOUNT COLUMN (Flex 2)
                                      Expanded(
                                        flex: 2,
                                        child: TextField(
                                          controller: holder.amountCtrl,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            hintText: "Amount ₹",
                                            border: OutlineInputBorder(),
                                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          ),
                                          onChanged: (_) {
                                            holder.syncToItem();
                                            totalNotifier.value = rowHolders.fold(0.0, (s, r) => s + r.item.amount);
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 4),

                                      // ACTION COLUMN (Delete)
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                        onPressed: () {
                                          holder.dispose();
                                          rowHolders.remove(holder);
                                          totalNotifier.value = rowHolders.fold(0.0, (s, r) => s + r.item.amount);
                                          setDialogState(() {});
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 10),

                    // Bottom Action Row: ADD NEW ENTRY & RESTORE AUTO RECORDS
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            final newHolder = _DialogRowHolder(DetailLineItem(
                              id: DateTime.now().millisecondsSinceEpoch.toString(),
                              name: "Entry ${rowHolders.length + 1}",
                              amount: 0.0,
                            ));
                            rowHolders.add(newHolder);
                            totalNotifier.value = rowHolders.fold(0.0, (s, r) => s + r.item.amount);
                            setDialogState(() {});
                          },
                          icon: const Icon(Icons.add_circle_rounded, size: 16),
                          label: const Text("ADD NEW ENTRY", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                        ),
                        if (onRestoreAuto != null) ...[
                          const SizedBox(width: 12),
                          TextButton.icon(
                            onPressed: () {
                              for (var r in rowHolders) { r.dispose(); }
                              onRestoreAuto();
                              Navigator.pop(dialogCtx);
                            },
                            icon: const Icon(Icons.restore_rounded, size: 16),
                            label: const Text("RESTORE SYSTEM AUTO RECORDS", style: TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Summary Footer Card with ValueListenableBuilder for Instant Total Sum
                    ValueListenableBuilder<double>(
                      valueListenable: totalNotifier,
                      builder: (context, totalSum, _) {
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(10)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("TOTAL ITEMS: ${rowHolders.length}", style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                              Row(
                                children: [
                                  const Text("TOTAL AMOUNT: ", style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
                                  Text("₹ ${totalSum.toStringAsFixed(2)}", style: const TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.w900)),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // Action Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            for (var r in rowHolders) { r.dispose(); }
                            Navigator.pop(dialogCtx);
                          },
                          icon: const Icon(Icons.arrow_back_rounded, size: 16),
                          label: const Text("CLOSE / BACK TO FLOW", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade700,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final List<DetailLineItem> finalItems = rowHolders.map<DetailLineItem>((r) {
                              r.syncToItem();
                              return r.item;
                            }).toList();
                            await onSave(finalItems);
                            await _saveSettingsForDate();
                            for (var r in rowHolders) { r.dispose(); }
                            if (mounted) setState(() {});
                            Navigator.pop(dialogCtx);
                          },
                          icon: const Icon(Icons.check_circle_rounded, size: 16),
                          label: const Text("SAVE LIST", style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _printDailySettlement() async {
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);

    final staffTitle = (_selectedStaff == null || _selectedStaff == "ALL") ? "ALL STAFF / COMBINED REGISTER" : "STAFF REGISTER: ${_selectedStaff!.toUpperCase()}";

    final headers = ["Metric / Account", "Amount (₹)"];
    final data = [
      ["REGISTER STAFF", staffTitle],
      ["OPENING BALANCE (Cash + UPI + Card)", _openingCounter.grandTotal.toStringAsFixed(2)],
      ["  - Opening Cash Notes/Coins", _openingCounter.cashTotal.toStringAsFixed(2)],
      ["  - Opening UPI", _openingCounter.upi.toStringAsFixed(2)],
      ["  - Opening Card", _openingCounter.card.toStringAsFixed(2)],
      ["----------------------------------------", "----------------"],
      ["Cash Counter Sales", cashSales.toStringAsFixed(2)],
      ["UPI Online Collections", upiSales.toStringAsFixed(2)],
      ["Card Swipe Payments", cardSales.toStringAsFixed(2)],
      ["Credit Invoices Issued", creditSales.toStringAsFixed(2)],
      ["TOTAL GROSS SALES", totalSales.toStringAsFixed(2)],
      ["CREDIT PAYMENTS RECEIVED (${_creditPaymentItems.length} items)", "+ ${totalCreditPayments.toStringAsFixed(2)}"],
      ["PRE PAYMENTS RECEIVED (${_prePaymentItems.length} items)", "+ ${totalPrePayments.toStringAsFixed(2)}"],
      ["BANK TO CASH (WITHDRAWAL) (${_bankToCashItems.length} items)", "+ ${totalBankToCash.toStringAsFixed(2)}"],
      ["----------------------------------------", "----------------"],
      ["TOTAL SALES RETURN (${_salesReturnItems.length} items)", "- ${totalSalesReturns.toStringAsFixed(2)}"],
      ["Supplier Cash Outflows (${_supplierPaidItems.length} items)", "- ${totalSupplierPaid.toStringAsFixed(2)}"],
      ["SHOP EXPENSES (${_expenseItems.length} items)", "- ${totalExpenses.toStringAsFixed(2)}"],
      ["CASH TAKEN / DEPOSIT (${_cashToBankItems.length} items)", "- ${totalCashToBank.toStringAsFixed(2)}"],
      ["----------------------------------------", "----------------"],
      ["EXPECTED CASH IN DRAWER", expectedCashInDrawer.toStringAsFixed(2)],
      ["ACTUAL CLOSING CASH COUNTER", actualClosingCash.toStringAsFixed(2)],
      ["TOTAL DIFFERENCE (Excess / Shortage)", totalDifference.toStringAsFixed(2)],
      ["NOT RECEIVED AMOUNT (${_notReceivedItems.length} items)", totalNotReceived.toStringAsFixed(2)],
      ["PURCHASES (${_purchaseItems.length} items)", totalPurchases.toStringAsFixed(2)],
    ];

    final doc = await ReportPdfGenerator.buildReportPdf(
      title: "Daily Settlement Report - $staffTitle",
      headers: headers,
      data: data,
      company: pharma.companyProfile,
      subtitle: "Date: ${DateFormat('dd/MM/yyyy (EEEE)').format(_selectedDate)}",
    );

    if (!mounted) return;
    PrinterService.showProfessionalPreview(context: context, doc: doc, title: "Daily Settlement Preview");
  }

  void _sendWhatsAppSummary() async {
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);

    final staffTitle = (_selectedStaff == null || _selectedStaff == "ALL") ? "ALL STAFF" : _selectedStaff!;

    final msg = StringBuffer();
    msg.writeln("📊 *DAILY REGISTER SUMMARY*");
    msg.writeln("🏥 ${pharma.companyProfile.name}");
    msg.writeln("📅 Date: ${DateFormat('dd/MM/yyyy').format(_selectedDate)}");
    msg.writeln("👤 Staff: $staffTitle");
    msg.writeln("--------------------------------");
    msg.writeln("💵 *OPENING BALANCE:* ₹${_openingCounter.grandTotal.toStringAsFixed(2)}");
    msg.writeln("   • Cash: ₹${_openingCounter.cashTotal.toStringAsFixed(2)} | UPI: ₹${_openingCounter.upi.toStringAsFixed(2)}");
    msg.writeln("--------------------------------");
    msg.writeln("📈 *GROSS SALES:* ₹${totalSales.toStringAsFixed(2)}");
    msg.writeln("   • Cash Sales: ₹${cashSales.toStringAsFixed(2)}");
    msg.writeln("   • UPI Sales: ₹${upiSales.toStringAsFixed(2)}");
    msg.writeln("   • Card Sales: ₹${cardSales.toStringAsFixed(2)}");
    msg.writeln("➕ *Credit Payments Recd:* ₹${totalCreditPayments.toStringAsFixed(2)}");
    msg.writeln("➖ *Sales Returns:* ₹${totalSalesReturns.toStringAsFixed(2)}");
    msg.writeln("➖ *Supplier Payments:* ₹${totalSupplierPaid.toStringAsFixed(2)}");
    msg.writeln("➖ *Expenses:* ₹${totalExpenses.toStringAsFixed(2)}");
    msg.writeln("--------------------------------");
    msg.writeln("🏦 *EXPECTED CASH IN DRAWER:* ₹${expectedCashInDrawer.toStringAsFixed(2)}");
    msg.writeln("💵 *ACTUAL CLOSING CASH:* ₹${actualClosingCash.toStringAsFixed(2)}");
    msg.writeln("${totalDifference >= 0 ? '🟢' : '🔴'} *DIFFERENCE:* ₹${totalDifference.toStringAsFixed(2)} (${totalDifference >= 0 ? 'Excess' : 'Shortage'})");

    final phone = pharma.companyProfile.phone.trim();
    if (phone.isNotEmpty) {
      await WhatsAppService.sendDailyClosingSummary(
        context: context,
        ownerPhone: phone,
        companyProfile: pharma.companyProfile,
        date: _selectedDate,
        totalSales: totalSales,
        totalInvoices: _daySales.length,
        cashReceived: cashSales,
        upiReceived: upiSales,
        cardReceived: cardSales,
        creditSales: creditSales,
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please configure company phone in Settings to send WhatsApp.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedStaff == null) {
      return _buildStaffSelectorView();
    }
    if (_selectedStaff == "HISTORY") {
      return _buildRegisterHistoryView();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.account_tree_rounded, size: 22),
            const SizedBox(width: 8),
            Text("DAILY INFOGRAPHIC FLOW REPORT (${_selectedStaff == 'ALL' ? 'ALL STAFF' : _selectedStaff!.toUpperCase()})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_alt_rounded),
            tooltip: "Switch Staff Register",
            onPressed: () => setState(() => _selectedStaff = null),
          ),
          IconButton(
            icon: const Icon(Icons.print_rounded),
            tooltip: "Print Daily Settlement",
            onPressed: _printDailySettlement,
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Colors.greenAccent),
            tooltip: "Send WhatsApp Summary",
            onPressed: _sendWhatsAppSummary,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: "Refresh Records",
            onPressed: _fetchDayRecords,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Filter Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.white,
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      _selectedDate = picked;
                      await _fetchDayRecords();
                    }
                  },
                  icon: const Icon(Icons.calendar_today_rounded, size: 16),
                  label: Text(DateFormat('dd MMMM yyyy (EEEE)').format(_selectedDate), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(width: 14),
                Chip(
                  avatar: const Icon(Icons.person, size: 14),
                  label: Text("Staff: ${_selectedStaff ?? 'ALL'}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  backgroundColor: Colors.blue.shade50,
                ),
                const SizedBox(width: 14),
                _buildHeadingsFilterDropdown(),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => setState(() => _selectedStaff = null),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                  label: const Text("SWITCH STAFF REGISTER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey.shade800,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                    child: Column(
                      children: [
                        // 1. TOP START NODE: OPENING BALANCES (Thumbs Up / Play Badge)
                        _buildSpineStartNode(),

                        // 1b. DAY SALE ENTRIES TIMELINE (OPENING & CLOSING SALE ENTRY WITH TIME & AUTO FETCH)
                        _buildSaleEntriesSection(),

                        // 2. CENTRAL INFOGRAPHIC SPINE TREE DIAGRAM
                        RepaintBoundary(child: _buildInfographicSpineTree()),
                        const SizedBox(height: 10),

                        // 3. BOTTOM FINISH NODE: CLOSING BALANCES & RECONCILIATION
                        _buildSpineFinishNode(),
                        const SizedBox(height: 28),

                        // Cash Denomination Breakdown Cards
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildCashCounterCard(title: "OPENING CASH COUNTER BREAKDOWN", data: _openingCounter, isOpening: true)),
                            const SizedBox(width: 16),
                            Expanded(child: _buildCashCounterCard(title: "CLOSING CASH COUNTER BREAKDOWN", data: _closingCounter, isOpening: false)),
                          ],
                        ),
                        const SizedBox(height: 24),

                        _buildSectionTitle("SALES INVOICE SETTLEMENTS (${_daySales.length}) - ${_selectedStaff ?? 'ALL STAFF'}"),
                        _buildSalesBreakdownTable(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // TOP CENTRAL START SPINE NODE
  Widget _buildSpineStartNode() {
    return Column(
      children: [
        // Opening Balances Card Container
        Container(
          width: 720,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.teal.shade400, width: 2),
            boxShadow: [
              BoxShadow(color: Colors.teal.shade100.withValues(alpha: 0.5), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(color: Colors.teal.shade800, borderRadius: BorderRadius.circular(20)),
                        child: const Row(
                          children: [
                            Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text("OPENING BALANCES", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showCashCounterDialog(isOpening: true),
                    icon: const Icon(Icons.edit_rounded, size: 14),
                    label: const Text("SET COUNTER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  _accountTile(
                    "💵 Cash", 
                    _openingCounter.cashTotal, 
                    Colors.green.shade800, 
                    Colors.green.shade50,
                    onTap: () => _showCashCounterDialog(isOpening: true),
                  ),
                  _accountTile(
                    "📱 UPI Online", 
                    _openingCounter.upi, 
                    Colors.purple.shade800, 
                    Colors.purple.shade50,
                    onTap: () => _showDirectAmountEditDialog(
                      title: "Edit Opening UPI Amount",
                      initialAmount: _openingCounter.upi,
                      color: Colors.purple.shade800,
                      onSave: (amt) async => _openingCounter.upi = amt,
                    ),
                  ),
                  _accountTile(
                    "💳 Card Swipe", 
                    _openingCounter.card, 
                    Colors.indigo.shade800, 
                    Colors.indigo.shade50,
                    onTap: () => _showDirectAmountEditDialog(
                      title: "Edit Opening Card Amount",
                      initialAmount: _openingCounter.card,
                      color: Colors.indigo.shade800,
                      onSave: (amt) async => _openingCounter.card = amt,
                    ),
                  ),
                  _accountTile("🏆 OPENING TOTAL", _openingCounter.grandTotal, Colors.black, Colors.grey.shade200, isBold: true),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  DateTime? _parseTimeToTodayDate(DateTime baseDate, String timeStr) {
    try {
      final format = DateFormat("hh:mm a");
      final dt = format.parse(timeStr);
      return DateTime(baseDate.year, baseDate.month, baseDate.day, dt.hour, dt.minute);
    } catch (_) {
      try {
        final format24 = DateFormat("HH:mm");
        final dt = format24.parse(timeStr);
        return DateTime(baseDate.year, baseDate.month, baseDate.day, dt.hour, dt.minute);
      } catch (_) {
        return null;
      }
    }
  }

  void _showManualSaleEntryDialog({required bool isOpening}) {
    final billCtrl = TextEditingController(
      text: isOpening ? (_customOpeningBillNo ?? '') : (_customClosingBillNo ?? ''),
    );
    final amtCtrl = TextEditingController(
      text: isOpening
          ? (_customOpeningAmount?.toStringAsFixed(2) ?? '')
          : (_customClosingAmount?.toStringAsFixed(2) ?? ''),
    );
    String timeStr = isOpening
        ? (_customOpeningTimeStr ?? "10:00 AM")
        : (_customClosingTimeStr ?? "09:00 PM");

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              Icon(
                isOpening ? Icons.play_circle_fill_rounded : Icons.stop_circle_rounded,
                color: isOpening ? Colors.green.shade700 : Colors.indigo.shade700,
              ),
              const SizedBox(width: 8),
              Text(
                isOpening ? "Manual Opening Sale Entry" : "Manual Closing Sale Entry",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: billCtrl,
                decoration: const InputDecoration(
                  labelText: "Bill / Entry No / Description",
                  hintText: "e.g. Bill #101 • Patient Name",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amtCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "Amount (₹)",
                  hintText: "0.00",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Time: $timeStr", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final TimeOfDay? picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (picked != null) {
                        final now = DateTime.now();
                        final dt = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
                        setDlgState(() {
                          timeStr = DateFormat('hh:mm a').format(dt);
                        });
                      }
                    },
                    icon: const Icon(Icons.access_time, size: 16),
                    label: const Text("Select Time"),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("CANCEL"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isOpening ? Colors.green.shade700 : Colors.indigo.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                setState(() {
                  if (isOpening) {
                    _customOpeningBillNo = billCtrl.text.trim();
                    _customOpeningAmount = double.tryParse(amtCtrl.text.trim());
                    _customOpeningTimeStr = timeStr;
                    _autoFetchOpeningSale = false;
                  } else {
                    _customClosingBillNo = billCtrl.text.trim();
                    _customClosingAmount = double.tryParse(amtCtrl.text.trim());
                    _customClosingTimeStr = timeStr;
                    _autoFetchClosingSale = false;
                  }
                });
                await _saveSettingsForDate();
                Navigator.pop(ctx);
              },
              child: const Text("SAVE ENTRY"),
            ),
          ],
        ),
      ),
    );
  }

  // SALE ENTRIES SECTION (OPENING & CLOSING SALE ENTRY WITH INDEPENDENT AUTO-FETCH TICKS & CENTER TIME DIFFERENCE)
  Widget _buildSaleEntriesSection() {
    final List<SaleInvoice> sortedSales = List<SaleInvoice>.from(_daySales)
      ..sort((a, b) => a.date.compareTo(b.date));

    // OPENING SALE RESOLUTION
    SaleInvoice? autoOpeningSale = sortedSales.isNotEmpty ? sortedSales.first : null;
    String openingBillDisplay = "No Sale Entry Recorded";
    String openingTimeDisplay = "--:--";
    double openingAmountDisplay = 0.0;
    DateTime? openingDt;

    if (_autoFetchOpeningSale && autoOpeningSale != null) {
      openingBillDisplay = "Bill #${autoOpeningSale.entryNo}${autoOpeningSale.patient.isNotEmpty ? ' • ${autoOpeningSale.patient}' : (autoOpeningSale.customerAcc.isNotEmpty ? ' • ${autoOpeningSale.customerAcc}' : '')}";
      openingTimeDisplay = DateFormat('hh:mm a').format(autoOpeningSale.date);
      openingAmountDisplay = autoOpeningSale.grandTotal;
      openingDt = autoOpeningSale.date;
    } else if (!_autoFetchOpeningSale && _customOpeningTimeStr != null) {
      openingBillDisplay = _customOpeningBillNo?.isNotEmpty == true ? _customOpeningBillNo! : "Manual Opening Entry";
      openingTimeDisplay = _customOpeningTimeStr!;
      openingAmountDisplay = _customOpeningAmount ?? 0.0;
      openingDt = _parseTimeToTodayDate(_selectedDate, _customOpeningTimeStr!);
    } else if (autoOpeningSale != null) {
      openingBillDisplay = "Bill #${autoOpeningSale.entryNo}${autoOpeningSale.patient.isNotEmpty ? ' • ${autoOpeningSale.patient}' : (autoOpeningSale.customerAcc.isNotEmpty ? ' • ${autoOpeningSale.customerAcc}' : '')}";
      openingTimeDisplay = DateFormat('hh:mm a').format(autoOpeningSale.date);
      openingAmountDisplay = autoOpeningSale.grandTotal;
      openingDt = autoOpeningSale.date;
    }

    // CLOSING SALE RESOLUTION
    SaleInvoice? autoClosingSale = sortedSales.isNotEmpty ? sortedSales.last : null;
    String closingBillDisplay = "No Sale Entry Recorded";
    String closingTimeDisplay = "--:--";
    double closingAmountDisplay = 0.0;
    DateTime? closingDt;

    if (_autoFetchClosingSale && autoClosingSale != null) {
      closingBillDisplay = "Bill #${autoClosingSale.entryNo}${autoClosingSale.patient.isNotEmpty ? ' • ${autoClosingSale.patient}' : (autoClosingSale.customerAcc.isNotEmpty ? ' • ${autoClosingSale.customerAcc}' : '')}";
      closingTimeDisplay = DateFormat('hh:mm a').format(autoClosingSale.date);
      closingAmountDisplay = autoClosingSale.grandTotal;
      closingDt = autoClosingSale.date;
    } else if (!_autoFetchClosingSale && _customClosingTimeStr != null) {
      closingBillDisplay = _customClosingBillNo?.isNotEmpty == true ? _customClosingBillNo! : "Manual Closing Entry";
      closingTimeDisplay = _customClosingTimeStr!;
      closingAmountDisplay = _customClosingAmount ?? 0.0;
      closingDt = _parseTimeToTodayDate(_selectedDate, _customClosingTimeStr!);
    } else if (autoClosingSale != null) {
      closingBillDisplay = "Bill #${autoClosingSale.entryNo}${autoClosingSale.patient.isNotEmpty ? ' • ${autoClosingSale.patient}' : (autoClosingSale.customerAcc.isNotEmpty ? ' • ${autoClosingSale.customerAcc}' : '')}";
      closingTimeDisplay = DateFormat('hh:mm a').format(autoClosingSale.date);
      closingAmountDisplay = autoClosingSale.grandTotal;
      closingDt = autoClosingSale.date;
    }

    // TIME FRAME DIFFERENCE CALCULATION
    String timeDiffStr = "--";
    if (openingDt != null && closingDt != null) {
      final diff = closingDt.difference(openingDt).abs();
      final int totalMins = diff.inMinutes;
      final int hrs = totalMins ~/ 60;
      final int mins = totalMins % 60;
      if (hrs == 0 && mins == 0) {
        timeDiffStr = "0 mins";
      } else if (hrs == 0) {
        timeDiffStr = "${mins}m";
      } else if (mins == 0) {
        timeDiffStr = "${hrs}h";
      } else {
        timeDiffStr = "${hrs}h ${mins}m";
      }
    }

    return Column(
      children: [
        Container(width: 4, height: 16, color: Colors.blue.shade600),

        Container(
          width: 720,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.teal.shade400, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.teal.shade100.withValues(alpha: 0.5),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.receipt_long_rounded, color: Colors.teal.shade900, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        "DAY SALE ENTRIES TIMELINE",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Colors.teal.shade900,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    "Check boxes for Auto-Fetch",
                    style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.teal.shade800),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Left Side: OPENING SALE ENTRY
                  Expanded(
                    child: InkWell(
                      onTap: () => _showManualSaleEntryDialog(isOpening: true),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade300, width: 1.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.play_circle_fill_rounded, size: 16, color: Colors.green.shade800),
                                    const SizedBox(width: 4),
                                    Text(
                                      "OPENING",
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.green.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: Checkbox(
                                        value: _autoFetchOpeningSale,
                                        activeColor: Colors.green.shade800,
                                        onChanged: (val) {
                                          setState(() {
                                            _autoFetchOpeningSale = val ?? true;
                                          });
                                          _saveSettingsForDate();
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade800,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.access_time_rounded, size: 10, color: Colors.white),
                                          const SizedBox(width: 3),
                                          Text(
                                            openingTimeDisplay,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              openingBillDisplay,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "₹ ${openingAmountDisplay.toStringAsFixed(2)}",
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.green.shade900),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // CENTER TIME FRAME DIFFERENCE BADGE
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.amber.shade400, width: 1.5),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 6,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "TIME FRAME",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer_outlined, size: 12, color: Colors.amberAccent),
                              const SizedBox(width: 4),
                              Text(
                                timeDiffStr,
                                style: const TextStyle(
                                  color: Colors.amberAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Right Side: CLOSING SALE ENTRY
                  Expanded(
                    child: InkWell(
                      onTap: () => _showManualSaleEntryDialog(isOpening: false),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.indigo.shade300, width: 1.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.stop_circle_rounded, size: 16, color: Colors.indigo.shade800),
                                    const SizedBox(width: 4),
                                    Text(
                                      "CLOSING",
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.indigo.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: Checkbox(
                                        value: _autoFetchClosingSale,
                                        activeColor: Colors.indigo.shade800,
                                        onChanged: (val) {
                                          setState(() {
                                            _autoFetchClosingSale = val ?? true;
                                          });
                                          _saveSettingsForDate();
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.indigo.shade800,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.access_time_rounded, size: 10, color: Colors.white),
                                          const SizedBox(width: 3),
                                          Text(
                                            closingTimeDisplay,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              closingBillDisplay,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "₹ ${closingAmountDisplay.toStringAsFixed(2)}",
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.indigo.shade900),
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
      ],
    );
  }

  void _deleteSubItem(DetailLineItem item) {
    setState(() {
      _notReceivedItems.removeWhere((it) => it.id == item.id);
      _creditPaymentItems.removeWhere((it) => it.id == item.id);
      _prePaymentItems.removeWhere((it) => it.id == item.id);
      _salesReturnItems.removeWhere((it) => it.id == item.id);
      _expenseItems.removeWhere((it) => it.id == item.id);
      _supplierPaidItems.removeWhere((it) => it.id == item.id);
      _purchaseItems.removeWhere((it) => it.id == item.id);
      _cashToBankItems.removeWhere((it) => it.id == item.id);
      _bankToCashItems.removeWhere((it) => it.id == item.id);
    });
    _saveSettingsForDate();
  }

  void _showDirectAmountEditDialog({
    required String title,
    required double initialAmount,
    required Function(double) onSave,
    required Color color,
  }) {
    final ctrl = TextEditingController(text: initialAmount == 0.0 ? '' : initialAmount.toStringAsFixed(2));
    final focusNode = FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) => focusNode.requestFocus());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(Icons.edit_note_rounded, color: color, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color))),
          ],
        ),
        content: TextField(
          controller: ctrl,
          focusNode: focusNode,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            labelText: "Amount (₹)",
            hintText: "Enter amount",
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.currency_rupee, size: 18),
          ),
          onSubmitted: (val) {
            final double newAmt = double.tryParse(val.trim()) ?? 0.0;
            onSave(newAmt);
            if (mounted) setState(() {});
            Navigator.pop(ctx);
            _saveSettingsForDate();
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
            onPressed: () {
              final double newAmt = double.tryParse(ctrl.text.trim()) ?? 0.0;
              onSave(newAmt);
              if (mounted) setState(() {});
              Navigator.pop(ctx);
              _saveSettingsForDate();
            },
            child: const Text("SAVE AMOUNT", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // BOTTOM CENTRAL FINISH SPINE NODE
  Widget _buildSpineFinishNode() {
    return Column(
      children: [
        Container(width: 4, height: 16, color: Colors.indigo.shade600),

        // Closing Balances Card Container
        Container(
          width: 720,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.indigo.shade400, width: 2),
            boxShadow: [
              BoxShadow(color: Colors.indigo.shade100.withValues(alpha: 0.5), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: Colors.indigo.shade900, borderRadius: BorderRadius.circular(20)),
                    child: const Row(
                      children: [
                        Icon(Icons.stop_circle_rounded, color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text("CLOSING BALANCES (ACTUAL)", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showCashCounterDialog(isOpening: false),
                    icon: const Icon(Icons.edit_rounded, size: 14),
                    label: const Text("SET COUNTER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade900,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  _accountTile(
                    "💵 Cash", 
                    _closingCounter.cashTotal, 
                    Colors.green.shade800, 
                    Colors.green.shade50,
                    onTap: () => _showCashCounterDialog(isOpening: false),
                  ),
                  _accountTile(
                    "📱 UPI Online", 
                    _closingCounter.upi, 
                    Colors.purple.shade800, 
                    Colors.purple.shade50,
                    onTap: () => _showDirectAmountEditDialog(
                      title: "Edit Closing UPI Amount",
                      initialAmount: _closingCounter.upi,
                      color: Colors.purple.shade800,
                      onSave: (amt) async => _closingCounter.upi = amt,
                    ),
                  ),
                  _accountTile(
                    "💳 Card Swipe", 
                    _closingCounter.card, 
                    Colors.indigo.shade800, 
                    Colors.indigo.shade50,
                    onTap: () => _showDirectAmountEditDialog(
                      title: "Edit Closing Card Amount",
                      initialAmount: _closingCounter.card,
                      color: Colors.indigo.shade800,
                      onSave: (amt) async => _closingCounter.card = amt,
                    ),
                  ),
                  _accountTile("🏆 CLOSING TOTAL", _closingCounter.grandTotal, Colors.black, Colors.grey.shade200, isBold: true),
                ],
              ),
              const SizedBox(height: 14),

              // Reconciliation Banner inside finish node
              if (_showDifference) ...[
                _buildNetDifferenceBanner(
                  expectedCash: expectedCashInDrawer,
                  actualCash: actualClosingCash,
                  totalDifference: totalDifference,
                  netDayGrowth: totalInflow - totalOutflow,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // CENTRAL INFOGRAPHIC SPINE TREE DIAGRAM
  Widget _buildInfographicSpineTree() {
    return Column(
      children: [
        // Top Header Banners for Left (Increasing) vs Right (Decreasing)
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.green.shade800,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text("🟢 FUNDS IN (CASH INCREASING)", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
                      ],
                    ),
                    Text("₹ ${totalInflow.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ),
            Container(width: 4, color: Colors.blueGrey.shade800),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.shade800,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text("🔴 FUNDS OUT (CASH DECREASING)", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
                      ],
                    ),
                    Text("₹ ${totalOutflow.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ),
          ],
        ),

        // BRANCH 1: Left = Counter Cash Sales | Right = NOT RECEIVED (DEBITS)
        if (_showPreEnter || _showNotReceived)
          _buildSpineRowPair(
            leftNode: _showPreEnter
                ? _buildSpineBranchCard(
                    title: "Counter Cash Sales",
                    amount: _customTotalSaleAmount ?? totalSales,
                    color: const Color(0xFF0284C7), // Teal / Blue
                    icon: Icons.store_rounded,
                    items: [
                      DetailLineItem(id: "cs1", name: "Total Sale", amount: _customTotalSaleAmount ?? totalSales),
                    ],
                    badgeLabel: "${_daySales.length} Bills",
                    isLeft: true,
                    allowDelete: false,
                    onExpand: () async {
                      await _fetchDayRecords(); // Auto-fetch live sales from database when clicked/opened!
                      _showMultiItemListDialog(
                        title: "COUNTER CASH SALES",
                        currentItems: [
                          DetailLineItem(id: "cs1", name: "Total Sale", amount: _customTotalSaleAmount ?? totalSales),
                        ],
                        primaryColor: const Color(0xFF0284C7),
                        onSave: (items) async {
                          if (items.isNotEmpty) {
                            _customTotalSaleAmount = items.first.amount;
                          }
                          await _saveSettingsForDate();
                          if (mounted) setState(() {});
                        },
                        onRestoreAuto: () async {
                          await _fetchDayRecords();
                          _customTotalSaleAmount = totalSales;
                          await _saveSettingsForDate();
                          if (mounted) setState(() {});
                        },
                      );
                    },
                  )
                : const SizedBox(),
            rightNode: _showNotReceived
                ? _buildSpineBranchCard(
                    title: "NOT RECEIVED (WITH NAME)",
                    amount: totalNotReceived,
                    color: const Color(0xFF475569), // Dark Blue / Grey
                    icon: Icons.info_outline_rounded,
                    items: _notReceivedItems,
                    onExpand: () => _showMultiItemListDialog(
                      title: "NOT RECEIVED / PENDING PAYMENTS",
                      currentItems: _notReceivedItems,
                      primaryColor: const Color(0xFF475569),
                      onSave: (items) async {
                        _notReceivedItems = items;
                        _hasCustomNotReceived = true;
                      },
                      onRestoreAuto: () async {
                        final creditSalesInvoices = _daySales.where((s) => s.customerAcc.toUpperCase() == "CREDIT").toList();
                        _notReceivedItems = creditSalesInvoices
                            .map((s) => DetailLineItem(
                                  id: s.entryNo,
                                  name: s.patient.isEmpty ? "Credit Customer #${s.entryNo}" : "${s.patient} (Bill #${s.entryNo})",
                                  amount: s.grandTotal,
                                ))
                            .toList();
                        _hasCustomNotReceived = false;
                        await _saveSettingsForDate();
                        if (mounted) setState(() {});
                      },
                    ),
                    isLeft: false,
                  )
                : const SizedBox(),
          ),

        // BRANCH 2: Left = CREDIT / PRE-PAYMENTS / ADVANCES | Right = Sales Returns & Refunds
        if (_showPreEnter || _showSalesReturn)
          _buildSpineRowPair(
            leftNode: _showPreEnter
                ? _buildSpineBranchCard(
                    title: "CREDIT / PRE-PAYMENTS / ADVANCES",
                    amount: totalCreditPayments + totalPrePayments,
                    color: const Color(0xFFDB2777), // Pink / Magenta
                    icon: Icons.bar_chart_rounded,
                    items: [..._creditPaymentItems, ..._prePaymentItems],
                    onExpand: () => _showMultiItemListDialog(
                      title: "CREDIT / PRE-PAYMENTS / ADVANCES",
                      currentItems: [..._creditPaymentItems, ..._prePaymentItems],
                      primaryColor: const Color(0xFFDB2777),
                      onSave: (items) async {
                        _prePaymentItems = items;
                        _hasCustomPrePayments = true;
                      },
                    ),
                    isLeft: true,
                  )
                : const SizedBox(),
            rightNode: _showSalesReturn
                ? _buildSpineBranchCard(
                    title: "Sales Returns & Refunds",
                    amount: totalSalesReturns,
                    color: const Color(0xFF65A30D), // Green
                    icon: Icons.monetization_on_rounded,
                    items: _salesReturnItems,
                    onExpand: () => _showMultiItemListDialog(
                      title: "TOTAL SALES RETURNS",
                      currentItems: _salesReturnItems,
                      primaryColor: const Color(0xFF65A30D),
                      onSave: (items) async {
                        _salesReturnItems = items;
                        _hasCustomSalesReturns = true;
                      },
                      onRestoreAuto: () async {
                        _salesReturnItems = _dayReturns
                            .map((r) => DetailLineItem(
                                  id: r.entryNo,
                                  name: "Sales Return #${r.entryNo}",
                                  amount: r.grandTotal,
                                ))
                            .toList();
                        _hasCustomSalesReturns = false;
                        await _saveSettingsForDate();
                        if (mounted) setState(() {});
                      },
                    ),
                    isLeft: false,
                  )
                : const SizedBox(),
          ),

        // BRANCH 3: Left = BANK TO CASH / ADDED CASH | Right = Shop Expenses
        if (_showPreEnter || _showExpenses)
          _buildSpineRowPair(
            leftNode: _showPreEnter
                ? _buildSpineBranchCard(
                    title: "BANK TO CASH / ADDED CASH",
                    amount: totalBankToCash,
                    color: const Color(0xFF2563EB), // Deep Blue
                    icon: Icons.people_rounded,
                    items: _bankToCashItems,
                    onExpand: () => _showMultiItemListDialog(
                      title: "CASH WITHDRAWAL / ADDED CASH FROM BANK",
                      currentItems: _bankToCashItems,
                      primaryColor: const Color(0xFF2563EB),
                      onSave: (items) async {
                        _bankToCashItems = items;
                        _hasCustomBankToCash = true;
                      },
                    ),
                    isLeft: true,
                  )
                : const SizedBox(),
            rightNode: _showExpenses
                ? _buildSpineBranchCard(
                    title: "Shop Expenses",
                    amount: totalExpenses,
                    color: const Color(0xFFDC2626), // Red / Magenta
                    icon: Icons.settings_applications_rounded,
                    items: _expenseItems,
                    onExpand: () => _showMultiItemListDialog(
                      title: "SHOP EXPENSES",
                      currentItems: _expenseItems,
                      primaryColor: const Color(0xFFDC2626),
                      onSave: (items) async {
                        _expenseItems = items;
                        _hasCustomExpenses = true;
                      },
                    ),
                    isLeft: false,
                  )
                : const SizedBox(),
          ),

        // BRANCH 4: Left = Empty | Right = Supplier Payments
        if (_showExpenses)
          _buildSpineRowPair(
            leftNode: const SizedBox(),
            rightNode: _buildSpineBranchCard(
              title: "Supplier Payments",
              amount: totalSupplierPaid,
              color: const Color(0xFFEA580C), // Orange / Gold
              icon: Icons.calendar_month_rounded,
              items: _supplierPaidItems,
              onExpand: () => _showMultiItemListDialog(
                title: "SUPPLIER PAYMENTS",
                currentItems: _supplierPaidItems,
                primaryColor: const Color(0xFFEA580C),
                onSave: (items) async {
                  _supplierPaidItems = items;
                  _hasCustomSupplierPaid = true;
                },
                onRestoreAuto: () async {
                  _supplierPaidItems = _daySupplierPayments
                      .map((sp) => DetailLineItem(
                            id: sp.id,
                            name: "Payment to ${sp.supplierName}",
                            amount: sp.amount,
                          ))
                      .toList();
                  _hasCustomSupplierPaid = false;
                  await _saveSettingsForDate();
                  if (mounted) setState(() {});
                },
              ),
              isLeft: false,
            ),
          ),

        // BRANCH 5: Right = Cash Taken / Deposits
        _buildSpineRowPair(
          leftNode: const SizedBox(),
          rightNode: _buildSpineBranchCard(
            title: "Cash Taken / Deposit",
            amount: totalCashToBank,
            color: const Color(0xFF0D9488), // Teal
            icon: Icons.account_balance_rounded,
            items: _cashToBankItems,
            onExpand: () => _showMultiItemListDialog(
              title: "CASH TAKEN / DEPOSIT",
              currentItems: _cashToBankItems,
              primaryColor: const Color(0xFF0D9488),
              onSave: (items) async {
                _cashToBankItems = items;
                _hasCustomCashToBank = true;
              },
            ),
            isLeft: false,
          ),
          isLast: true,
        ),
      ],
    );
  }

  // Row pair containing Left Card | Central Vertical Spine Line | Right Card
  Widget _buildSpineRowPair({required Widget leftNode, required Widget rightNode, bool isLast = false}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Node Column (Soft Transparent Green Background Tint)
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4).withValues(alpha: 0.85),
                border: Border(
                  left: BorderSide(color: Colors.green.shade200, width: 1.5),
                  bottom: BorderSide(color: isLast ? Colors.green.shade200 : Colors.transparent, width: 1.5),
                ),
                borderRadius: isLast ? const BorderRadius.only(bottomLeft: Radius.circular(12)) : null,
              ),
              child: leftNode,
            ),
          ),

          // Central Vertical Trunk Line
          Container(
            width: 4,
            color: Colors.blueGrey.shade400,
          ),

          // Right Node Column (Soft Transparent Red Background Tint)
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2).withValues(alpha: 0.85),
                border: Border(
                  right: BorderSide(color: Colors.red.shade200, width: 1.5),
                  bottom: BorderSide(color: isLast ? Colors.red.shade200 : Colors.transparent, width: 1.5),
                ),
                borderRadius: isLast ? const BorderRadius.only(bottomRight: Radius.circular(12)) : null,
              ),
              child: rightNode,
            ),
          ),
        ],
      ),
    );
  }

  // Infographic Branch Card with Spider Web Lines Layout
  Widget _buildSpineBranchCard({
    required String title,
    required double amount,
    required Color color,
    required IconData icon,
    required List<DetailLineItem> items,
    VoidCallback? onExpand,
    String? badgeLabel,
    required bool isLeft,
    bool allowDelete = true,
  }) {
    // Sort sub-items by amount descending (bigger numbers first)
    final sortedItems = List<DetailLineItem>.from(items)..sort((a, b) => b.amount.compareTo(a.amount));
    final displayItems = sortedItems.take(8).toList();
    final remainingCount = sortedItems.length - displayItems.length;

    Widget badgeAndIcon = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: color, width: 3),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Icon(icon, color: color, size: 20),
    );

    Widget pillHeader = Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 5, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              "₹ ${amount.toStringAsFixed(2)}",
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900),
            ),
            if (onExpand != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.open_in_full_rounded, size: 12, color: Colors.white),
            ],
          ],
        ),
      ),
    );

    // Main Heading Node docked flush against the center spine
    Widget mainNode = Row(
      mainAxisSize: MainAxisSize.min,
      children: isLeft
          ? [pillHeader, const SizedBox(width: 4), badgeAndIcon]
          : [badgeAndIcon, const SizedBox(width: 4), pillHeader],
    );

    // Build list of sub-heading chips positioned away from the center line
    List<Widget> subChips = [];

    if (displayItems.isNotEmpty) {
      for (int i = 0; i < displayItems.length; i++) {
        final item = displayItems[i];
        subChips.add(
          Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: InkWell(
                    onTap: onExpand,
                    borderRadius: BorderRadius.circular(6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            item.name,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black87),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "₹ ${item.amount.toStringAsFixed(2)}",
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color),
                        ),
                      ],
                    ),
                  ),
                ),
                if (allowDelete) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => _deleteSubItem(item),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.red.shade200, width: 1),
                      ),
                      child: const Icon(Icons.close, size: 10, color: Colors.red),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }
      if (remainingCount > 0 && onExpand != null) {
        subChips.add(
          InkWell(
            onTap: onExpand,
            child: Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "+ $remainingCount MORE ITEMS",
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: color),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 11, color: color),
                ],
              ),
            ),
          ),
        );
      }
    } else {
      subChips.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Text(
            "No entries recorded.",
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
          ),
        ),
      );
    }

    Widget subItemsColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isLeft ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: subChips,
    );

    final int itemCount = subChips.length;

    return InkWell(
      onTap: onExpand,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: isLeft ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: isLeft
                ? [
                    Flexible(child: subItemsColumn),
                    SizedBox(
                      width: 32,
                      child: CustomPaint(
                        painter: SpiderLinesPainter(
                          isLeft: true,
                          itemCount: itemCount,
                          color: color,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Flexible(child: mainNode),
                  ]
                : [
                    Flexible(child: mainNode),
                    SizedBox(
                      width: 32,
                      child: CustomPaint(
                        painter: SpiderLinesPainter(
                          isLeft: false,
                          itemCount: itemCount,
                          color: color,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Flexible(child: subItemsColumn),
                  ],
          ),
        ),
      ),
    );
  }

  Widget _accountTile(String label, double amount, Color textColor, Color bg, {bool isBold = false, VoidCallback? onTap, String? formattedValue}) {
    final String displayVal = formattedValue ?? "₹ ${amount.toStringAsFixed(2)}";
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: textColor.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor.withValues(alpha: 0.85)),
                    ),
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 2),
                  Icon(Icons.edit_rounded, size: 10, color: textColor.withValues(alpha: 0.6)),
                ],
              ],
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                displayVal,
                style: TextStyle(fontSize: 13, fontWeight: isBold ? FontWeight.w900 : FontWeight.bold, color: textColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Net Discrepancy & Reconciliation Bar
  Widget _buildNetDifferenceBanner({
    required double expectedCash,
    required double actualCash,
    required double totalDifference,
    required double netDayGrowth,
  }) {
    final double equationDiff = totalOutflow + _closingCounter.grandTotal - _openingCounter.grandTotal - totalInflow;
    final bool isExactTally = equationDiff.abs() < 0.01;
    final bool isExcess = equationDiff > 0;
    final Color diffColor = isExactTally ? Colors.greenAccent : (isExcess ? Colors.greenAccent : Colors.redAccent);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("EQUATION = FUNDS OUT + CLOSING TOTAL - OPENING TOTAL - FUNDS IN", style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    "₹ ${totalOutflow.toStringAsFixed(2)} + ₹ ${_closingCounter.grandTotal.toStringAsFixed(2)} - ₹ ${_openingCounter.grandTotal.toStringAsFixed(2)} - ₹ ${totalInflow.toStringAsFixed(2)}",
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    isExactTally ? "CALCULATED DIFFERENCE (EXACT MATCH)" : (isExcess ? "CALCULATED DIFFERENCE (EXCESS +)" : "CALCULATED DIFFERENCE (SHORTAGE -)"),
                    style: TextStyle(color: diffColor, fontSize: 11, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "₹ ${equationDiff.toStringAsFixed(2)}",
                    style: TextStyle(color: diffColor, fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCashCounterCard({required String title, required CashCounterData data, required bool isOpening}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isOpening ? Icons.play_circle_fill_rounded : Icons.stop_circle_rounded, size: 16, color: isOpening ? Colors.green : Colors.indigo),
                const SizedBox(width: 6),
                Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isOpening ? Colors.green.shade900 : Colors.indigo.shade900)),
                const Spacer(),
                InkWell(
                  onTap: () => _showCashCounterDialog(isOpening: isOpening),
                  child: const Text("EDIT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)),
                ),
              ],
            ),
            const Divider(),
            _denomTile("₹ 500 Notes", data.count500, data.count500 * 500),
            _denomTile("₹ 200 Notes", data.count200, data.count200 * 200),
            _denomTile("₹ 100 Notes", data.count100, data.count100 * 100),
            _denomTile("₹ 50 Notes", data.count50, data.count50 * 50),
            _denomTile("₹ 20 Notes", data.count20, data.count20 * 20),
            _denomTile("₹ 10 Notes", data.count10, data.count10 * 10),
            _denomTile("₹ 5 Notes", data.count5, data.count5 * 5),
            _denomTile("Coins", 1, data.coins, isCoin: true),
            const Divider(),
            _denomTile("TOTAL CASH", 0, data.cashTotal, isTotal: true),
            _denomTile("UPI ONLINE", 0, data.upi, isDigital: true),
            _denomTile("CARD SWIPE", 0, data.card, isDigital: true),
            _denomTile("GRAND TOTAL", 0, data.grandTotal, isGrandTotal: true),
          ],
        ),
      ),
    );
  }

  Widget _denomTile(String label, int count, double subtotal, {bool isCoin = false, bool isTotal = false, bool isDigital = false, bool isGrandTotal = false}) {
    if (count == 0 && subtotal == 0 && !isTotal && !isGrandTotal) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: isGrandTotal || isTotal ? FontWeight.bold : FontWeight.normal, color: isGrandTotal ? Colors.blue.shade900 : Colors.black87)),
          if (!isCoin && !isTotal && !isDigital && !isGrandTotal)
            Text("x $count", style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(
            "₹ ${subtotal.toStringAsFixed(2)}",
            style: TextStyle(
              fontSize: isGrandTotal ? 13 : 11,
              fontWeight: isGrandTotal || isTotal ? FontWeight.bold : FontWeight.normal,
              color: isGrandTotal ? Colors.blue.shade900 : (isTotal ? Colors.green.shade800 : (isDigital ? Colors.purple.shade800 : Colors.black87)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
    );
  }

  Widget _buildSalesBreakdownTable() {
    if (_daySales.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
        child: const Center(child: Text("No sales invoices recorded for this staff/date.", style: TextStyle(color: Colors.grey))),
      );
    }

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 32,
          dataRowMaxHeight: 30,
          dataRowMinHeight: 28,
          columns: const [
            DataColumn(label: Text("ENTRY NO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
            DataColumn(label: Text("TIME", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
            DataColumn(label: Text("PATIENT / CUSTOMER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
            DataColumn(label: Text("ACCOUNT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
            DataColumn(label: Text("AGENT / STAFF", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
            DataColumn(label: Text("AMOUNT (₹)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
          ],
          rows: _daySales.map((s) {
            return DataRow(cells: [
              DataCell(Text(s.entryNo, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
              DataCell(Text(DateFormat('hh:mm a').format(s.date), style: const TextStyle(fontSize: 11))),
              DataCell(Text(s.patient.isEmpty ? "-" : s.patient, style: const TextStyle(fontSize: 11))),
              DataCell(Text(s.customerAcc, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: s.customerAcc.toUpperCase() == "CREDIT" ? Colors.red : Colors.green.shade800))),
              DataCell(Text(s.agent.isEmpty ? "-" : s.agent, style: const TextStyle(fontSize: 11))),
              DataCell(Text("₹ ${s.grandTotal.toStringAsFixed(2)}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _fetchMonthSummaryRecords() async {
    setState(() => _isLoading = true);
    final p = Provider.of<PharmacyProvider>(context, listen: false);

    final startOfMonth = DateTime(_historyMonth.year, _historyMonth.month, 1, 0, 0, 0);
    final endOfMonth = DateTime(_historyMonth.year, _historyMonth.month + 1, 0, 23, 59, 59);

    final results = await Future.wait([
      p.fetchSalesInDateRange(startOfMonth, endOfMonth, loadItems: false, limit: 3000, offset: 0),
      p.fetchPurchasesInDateRange(startOfMonth, endOfMonth, loadItems: false, limit: 3000, offset: 0),
      p.fetchSaleReturnsInDateRange(startOfMonth, endOfMonth, loadItems: false, limit: 3000, offset: 0),
    ]);

    _monthSales = (results[0] as List<SaleInvoice>).where((s) => !s.isDeleted).toList();
    _monthPurchases = (results[1] as List<PurchaseEntry>).where((pe) => !pe.isDeleted).toList();
    _monthReturns = (results[2] as List<SaleReturnInvoice>).where((r) => !r.isDeleted).toList();

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildMonthlySummaryPanel() {
    final double salesTotal = _monthSales.fold(0.0, (sum, s) => sum + s.grandTotal);
    final double purchasesTotal = _monthPurchases.fold(0.0, (sum, p) => sum + p.grandTotal);
    final double returnsTotal = _monthReturns.fold(0.0, (sum, r) => sum + r.grandTotal);
    final int invoiceCount = _monthSales.length;

    final double netMonthFlow = salesTotal - returnsTotal - totalExpenses;

    const double colDateWidth = 140;
    const double colInvoicesWidth = 110;
    const double colGrossWidth = 135;
    const double colReturnsWidth = 125;
    const double colNetWidth = 135;
    const double colNotReceivedWidth = 135;
    const double colExpensesWidth = 135;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.shade400, width: 2),
            ),
            child: Text(
              "MONTHLY SUMMARY ${DateFormat('MMM-yy').format(_historyMonth).toUpperCase()}",
              style: const TextStyle(color: Colors.amberAccent, fontSize: 15, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 16),

          _buildSectionTitle("DAILY SALES BREAKDOWN FOR ${DateFormat('MMMM yyyy').format(_historyMonth).toUpperCase()}"),

          // Horizontal scroll view keeping Summary Tiles & Table Columns perfectly aligned 1-to-1
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // KPI Summary Tiles aligned STRAIGHT on top of matching columns
                    Row(
                      children: [
                        const SizedBox(width: colDateWidth + 24), // Blank offset space over DATE column
                        SizedBox(
                          width: colInvoicesWidth,
                          child: _accountTile(
                            "📄 TOTAL INVOICES",
                            0,
                            Colors.blue.shade800,
                            Colors.blue.shade50,
                            isBold: true,
                            formattedValue: "$invoiceCount Bills",
                            onTap: () => _openHeadingDetailView(
                              headingTitle: "TOTAL SALES INVOICES",
                              color: Colors.blue.shade800,
                              records: _monthSales
                                  .map((s) => HeadingDetailRecord(
                                        dateStr: DateFormat('dd/MM/yyyy (EEE)').format(s.date),
                                        name: s.patient.isNotEmpty ? s.patient : "Customer (Bill #${s.entryNo})",
                                        remark: "Sales Invoice #${s.entryNo} • Account: ${s.customerAcc}",
                                        amount: s.grandTotal,
                                      ))
                                  .toList(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        SizedBox(
                          width: colGrossWidth,
                          child: _accountTile(
                            "📈 GROSS SALES",
                            salesTotal,
                            Colors.green.shade800,
                            Colors.green.shade50,
                            isBold: true,
                            onTap: () => _openHeadingDetailView(
                              headingTitle: "GROSS SALES REVENUE",
                              color: Colors.green.shade800,
                              records: _monthSales
                                  .map((s) => HeadingDetailRecord(
                                        dateStr: DateFormat('dd/MM/yyyy (EEE)').format(s.date),
                                        name: s.patient.isNotEmpty ? s.patient : "Customer (Bill #${s.entryNo})",
                                        remark: "Gross Sales Inv #${s.entryNo}",
                                        amount: s.grandTotal,
                                      ))
                                  .toList(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        SizedBox(
                          width: colReturnsWidth,
                          child: _accountTile(
                            "↩️ TOTAL RETURNS",
                            returnsTotal,
                            Colors.red.shade800,
                            Colors.red.shade50,
                            isBold: true,
                            onTap: () => _openHeadingDetailView(
                              headingTitle: "SALES RETURNS & REFUNDS",
                              color: Colors.red.shade800,
                              records: _monthReturns
                                  .map((r) => HeadingDetailRecord(
                                        dateStr: DateFormat('dd/MM/yyyy (EEE)').format(r.date),
                                        name: r.patient.isNotEmpty ? r.patient : "Customer (Return #${r.entryNo})",
                                        remark: "Sales Return Invoice #${r.entryNo}",
                                        amount: r.grandTotal,
                                      ))
                                  .toList(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        SizedBox(
                          width: colNetWidth,
                          child: _accountTile(
                            "🏆 NET REVENUE",
                            salesTotal - returnsTotal,
                            Colors.amber.shade900,
                            Colors.amber.shade50,
                            isBold: true,
                            onTap: () => _openHeadingDetailView(
                              headingTitle: "NET REVENUE BREAKDOWN",
                              color: Colors.amber.shade900,
                              records: [
                                ..._monthSales.map((s) => HeadingDetailRecord(
                                      dateStr: DateFormat('dd/MM/yyyy (EEE)').format(s.date),
                                      name: s.patient.isNotEmpty ? s.patient : "Sales Inv #${s.entryNo}",
                                      remark: "Gross Sales (+)",
                                      amount: s.grandTotal,
                                    )),
                                ..._monthReturns.map((r) => HeadingDetailRecord(
                                      dateStr: DateFormat('dd/MM/yyyy (EEE)').format(r.date),
                                      name: r.patient.isNotEmpty ? r.patient : "Return Inv #${r.entryNo}",
                                      remark: "Sales Return (-)",
                                      amount: -r.grandTotal,
                                    )),
                              ],
                            ),
                          ),
                        ),
                        if (_showNotReceived) ...[
                          const SizedBox(width: 24),
                          SizedBox(
                            width: colNotReceivedWidth,
                            child: _accountTile(
                              "ℹ️ NOT RECEIVED",
                              totalNotReceived,
                              Colors.blueGrey.shade800,
                              Colors.blueGrey.shade50,
                              isBold: true,
                              onTap: () => _openHeadingDetailView(
                                headingTitle: "NOT RECEIVED / PENDING DEBITS",
                                color: Colors.blueGrey.shade800,
                                records: _notReceivedItems
                                    .map((item) => HeadingDetailRecord(
                                          dateStr: DateFormat('dd/MM/yyyy (EEE)').format(_selectedDate),
                                          name: item.name,
                                          remark: item.note.isNotEmpty ? item.note : "Pending Credit Payment",
                                          amount: item.amount,
                                        ))
                                    .toList(),
                              ),
                            ),
                          ),
                        ],
                        if (_showExpenses) ...[
                          const SizedBox(width: 24),
                          SizedBox(
                            width: colExpensesWidth,
                            child: _accountTile(
                              "💸 SHOP EXPENSES",
                              totalExpenses,
                              Colors.purple.shade800,
                              Colors.purple.shade50,
                              isBold: true,
                              onTap: () => _openHeadingDetailView(
                                headingTitle: "SHOP EXPENSES & OUTFLOWS",
                                color: Colors.purple.shade800,
                                records: _expenseItems
                                    .map((item) => HeadingDetailRecord(
                                          dateStr: DateFormat('dd/MM/yyyy (EEE)').format(_selectedDate),
                                          name: item.name,
                                          remark: item.note.isNotEmpty ? item.note : "Shop Expense Entry",
                                          amount: item.amount,
                                        ))
                                    .toList(),
                              ),
                            ),
                          ),
                        ],
                        // Custom Headings added via "+" button
                        for (var customHeading in _customHeadings) ...[
                          const SizedBox(width: 24),
                          SizedBox(
                            width: colExpensesWidth,
                            child: _accountTile(
                              "📑 ${customHeading.name}",
                              customHeading.amount,
                              customHeading.color,
                              customHeading.color.withValues(alpha: 0.1),
                              isBold: true,
                              onTap: () => _openHeadingDetailView(
                                headingTitle: customHeading.name,
                                color: customHeading.color,
                                records: [
                                  HeadingDetailRecord(
                                    dateStr: DateFormat('dd/MM/yyyy (EEE)').format(_selectedDate),
                                    name: customHeading.name,
                                    remark: "Custom Day Book Entry",
                                    amount: customHeading.amount,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 16),
                        // "+" Button on the right side of EXPENSES to add another Heading from Admin Day Book
                        InkWell(
                          onTap: _showAddCustomHeadingDialog,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.purple.shade300, width: 1.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_circle_outline_rounded, size: 18, color: Colors.purple.shade800),
                                const SizedBox(width: 4),
                                Text(
                                  "Add Heading",
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purple.shade900),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Data Table with matching explicit column widths & spacing
                    DataTable(
                      headingRowHeight: 34,
                      dataRowMinHeight: 28,
                      dataRowMaxHeight: 32,
                      columnSpacing: 24,
                      horizontalMargin: 12,
                      columns: [
                        DataColumn(label: SizedBox(width: colDateWidth, child: const Text("DATE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))),
                        DataColumn(label: SizedBox(width: colInvoicesWidth, child: const Text("INVOICES", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))),
                        DataColumn(label: SizedBox(width: colGrossWidth, child: const Text("GROSS SALES (₹)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))),
                        DataColumn(label: SizedBox(width: colReturnsWidth, child: const Text("RETURNS (₹)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))),
                        DataColumn(label: SizedBox(width: colNetWidth, child: const Text("NET REVENUE (₹)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))),
                        if (_showNotReceived)
                          DataColumn(label: SizedBox(width: colNotReceivedWidth, child: const Text("NOT RECEIVED (₹)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))),
                        if (_showExpenses)
                          DataColumn(label: SizedBox(width: colExpensesWidth, child: const Text("EXPENSES (₹)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))),
                        for (var customHeading in _customHeadings)
                          DataColumn(label: SizedBox(width: colExpensesWidth, child: Text("${customHeading.name} (₹)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)))),
                      ],
                      rows: List.generate(DateTime(_historyMonth.year, _historyMonth.month + 1, 0).day, (idx) {
                        final dayNum = idx + 1;
                        final dt = DateTime(_historyMonth.year, _historyMonth.month, dayNum);
                        final daySalesList = _monthSales.where((s) => s.date.year == dt.year && s.date.month == dt.month && s.date.day == dt.day).toList();
                        final dayReturnsList = _monthReturns.where((r) => r.date.year == dt.year && r.date.month == dt.month && r.date.day == dt.day).toList();

                        final dSales = daySalesList.fold(0.0, (s, item) => s + item.grandTotal);
                        final dReturns = dayReturnsList.fold(0.0, (s, item) => s + item.grandTotal);
                        final dNet = dSales - dReturns;

                        return DataRow(cells: [
                          DataCell(SizedBox(width: colDateWidth, child: Text(DateFormat('dd MMM yyyy (EEE)').format(dt), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)))),
                          DataCell(SizedBox(width: colInvoicesWidth, child: Text("${daySalesList.length} Bills", style: const TextStyle(fontSize: 11)))),
                          DataCell(SizedBox(width: colGrossWidth, child: Text("₹ ${dSales.toStringAsFixed(2)}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green)))),
                          DataCell(SizedBox(width: colReturnsWidth, child: Text("₹ ${dReturns.toStringAsFixed(2)}", style: const TextStyle(fontSize: 11, color: Colors.red)))),
                          DataCell(SizedBox(width: colNetWidth, child: Text("₹ ${dNet.toStringAsFixed(2)}", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: dNet >= 0 ? Colors.blue.shade900 : Colors.red)))),
                          if (_showNotReceived)
                            DataCell(SizedBox(width: colNotReceivedWidth, child: Text("₹ 0.00", style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade800)))),
                          if (_showExpenses)
                            DataCell(SizedBox(width: colExpensesWidth, child: Text("₹ 0.00", style: TextStyle(fontSize: 11, color: Colors.purple.shade800)))),
                          for (var customHeading in _customHeadings)
                            DataCell(SizedBox(width: colExpensesWidth, child: Text("₹ ${customHeading.amount.toStringAsFixed(2)}", style: TextStyle(fontSize: 11, color: customHeading.color, fontWeight: FontWeight.bold)))),
                        ]);
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterHistoryView() {
    final year = _historyMonth.year;
    final month = _historyMonth.month;
    final totalDays = DateTime(year, month + 1, 0).day;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: Row(
          children: [
            const Icon(Icons.history_edu_rounded, color: Colors.amberAccent, size: 22),
            const SizedBox(width: 10),
            const Text("REGISTER HISTORY ARCHIVE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: () => setState(() => _selectedStaff = null),
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text("BACK TO STAFF SELECTOR", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey.shade800,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          // Top Month Selector Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.white,
            child: Row(
              children: [
                const Icon(Icons.calendar_month_rounded, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                const Text("CHOOSE MONTH:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _historyMonth,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                      initialDatePickerMode: DatePickerMode.year,
                    );
                    if (picked != null) {
                      setState(() {
                        _historyMonth = DateTime(picked.year, picked.month);
                        _selectedDate = DateTime(picked.year, picked.month, 1);
                      });
                      if (_isShowingMonthSummary) {
                        await _fetchMonthSummaryRecords();
                      } else {
                        await _fetchDayRecords();
                      }
                    }
                  },
                  icon: const Icon(Icons.arrow_drop_down_circle_rounded, size: 18, color: Colors.amber),
                  label: Text(
                    DateFormat('MMMM yyyy').format(_historyMonth).toUpperCase(),
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.amber.shade900),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.amber.shade700, width: 1.5),
                    backgroundColor: Colors.amber.shade50,
                  ),
                ),
                const Spacer(),
                Chip(
                  avatar: Icon(_isShowingMonthSummary ? Icons.pie_chart_rounded : Icons.event_note, size: 14, color: Colors.amber),
                  label: Text(
                    _isShowingMonthSummary
                        ? "Month Summary Mode: ${DateFormat('MMMM yyyy').format(_historyMonth)}"
                        : "Selected Date: ${DateFormat('dd MMM yyyy (EEEE)').format(_selectedDate)}",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                  backgroundColor: Colors.amber.shade50,
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: Row(
              children: [
                // Left Panel: Vertical Dates List with "SUMMARY OF MONTH" at Index 0
                Container(
                  width: 220,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(right: BorderSide(color: Colors.grey.shade300)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        color: const Color(0xFF1E293B),
                        child: Text(
                          "DATES ($totalDays DAYS)",
                          style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: totalDays + 1,
                          itemBuilder: (ctx, idx) {
                            if (idx == 0) {
                              final isSelected = _isShowingMonthSummary;
                              return InkWell(
                                onTap: () async {
                                  setState(() {
                                    _isShowingMonthSummary = true;
                                  });
                                  await _fetchMonthSummaryRecords();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.amber.shade100 : Colors.amber.shade50.withValues(alpha: 0.5),
                                    border: Border(
                                      bottom: BorderSide(color: Colors.amber.shade300, width: 2),
                                      left: BorderSide(color: isSelected ? Colors.amber.shade900 : Colors.amber.shade700, width: 4),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 28,
                                        height: 28,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade900,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.pie_chart_rounded, size: 16, color: Colors.white),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "SUMMARY OF ${DateFormat('MMM').format(_historyMonth).toUpperCase()}",
                                              style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 11,
                                                color: Colors.amber.shade900,
                                              ),
                                            ),
                                            const Text(
                                              "Monthly Overview",
                                              style: TextStyle(fontSize: 9, color: Colors.brown, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            final dayNum = idx;
                            final dt = DateTime(year, month, dayNum);
                            final isSelected = !_isShowingMonthSummary &&
                                _selectedDate.year == dt.year &&
                                _selectedDate.month == dt.month &&
                                _selectedDate.day == dt.day;

                            return InkWell(
                              onTap: () async {
                                setState(() {
                                  _isShowingMonthSummary = false;
                                  _selectedDate = dt;
                                });
                                await _fetchDayRecords();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isSelected ? Colors.amber.shade100 : (idx % 2 == 0 ? Colors.white : Colors.grey.shade50),
                                  border: Border(
                                    bottom: BorderSide(color: Colors.grey.shade200),
                                    left: BorderSide(color: isSelected ? Colors.amber.shade800 : Colors.transparent, width: 4),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 28,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: isSelected ? Colors.amber.shade900 : Colors.blueGrey.shade100,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        "$dayNum",
                                        style: TextStyle(
                                          color: isSelected ? Colors.white : Colors.blueGrey.shade900,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            DateFormat('dd MMM (EEE)').format(dt),
                                            style: TextStyle(
                                              fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                                              fontSize: 11,
                                              color: isSelected ? Colors.amber.shade900 : Colors.black87,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // Right Panel: Monthly Summary View or Daily Flow Report for Selected Date
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : (_isShowingMonthSummary
                          ? _buildMonthlySummaryPanel()
                          : SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                              child: Column(
                                children: [
                                  _buildSpineStartNode(),
                                  _buildSaleEntriesSection(),
                                  RepaintBoundary(child: _buildInfographicSpineTree()),
                                  const SizedBox(height: 10),
                                  _buildSpineFinishNode(),
                                  const SizedBox(height: 28),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: _buildCashCounterCard(title: "OPENING CASH COUNTER BREAKDOWN", data: _openingCounter, isOpening: true)),
                                      const SizedBox(width: 16),
                                      Expanded(child: _buildCashCounterCard(title: "CLOSING CASH COUNTER BREAKDOWN", data: _closingCounter, isOpening: false)),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  _buildSectionTitle("SALES INVOICE SETTLEMENTS (${_daySales.length}) - ALL STAFF"),
                                  _buildSalesBreakdownTable(),
                                ],
                              ),
                            )),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffSelectorView() {
    final pharmacy = Provider.of<PharmacyProvider>(context);
    final activeStaffNames = pharmacy.staffNames;

    final Set<String> staffSet = {"ALL", ...activeStaffNames};
    for (final s in _allDaySales) {
      if (s.agent.trim().isNotEmpty) {
        final agentName = s.agent.trim();
        final hasSalesOnDay = _allDaySales.any((sale) => sale.agent.trim().toLowerCase() == agentName.toLowerCase());
        if (hasSalesOnDay) {
          staffSet.add(agentName);
        }
      }
    }
    final List<String> availableStaff = staffSet.toList()..add("HISTORY");

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text("DAILY FLOW REPORT - SELECT STAFF REGISTER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchDayRecords,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      _selectedDate = picked;
                      await _fetchDayRecords();
                    }
                  },
                  icon: const Icon(Icons.calendar_today_rounded, size: 16),
                  label: Text(DateFormat('dd MMMM yyyy (EEEE)').format(_selectedDate), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const Spacer(),
                Text("Total Day Invoices: ${_allDaySales.length}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2.2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: availableStaff.length,
              itemBuilder: (context, i) {
                final staffName = availableStaff[i];
                final isAll = staffName == "ALL";
                final isHistory = staffName == "HISTORY";

                int invoiceCount = 0;
                double totalRevenue = 0.0;

                if (isAll || isHistory) {
                  invoiceCount = _allDaySales.length;
                  totalRevenue = _allDaySales.fold(0.0, (sum, s) => sum + s.grandTotal);
                } else {
                  final target = staffName.trim().toLowerCase();
                  final staffSales = _allDaySales.where((s) => s.agent.trim().toLowerCase() == target).toList();
                  invoiceCount = staffSales.length;
                  totalRevenue = staffSales.fold(0.0, (sum, s) => sum + s.grandTotal);
                }

                Color cardBorderColor = isHistory
                    ? Colors.amber.shade600
                    : (isAll ? Colors.blue.shade300 : Colors.grey.shade300);

                Gradient? cardGradient = isHistory
                    ? LinearGradient(colors: [Colors.amber.shade50, Colors.white])
                    : (isAll ? LinearGradient(colors: [Colors.blue.shade50, Colors.white]) : null);

                Color avatarBg = isHistory
                    ? Colors.amber.shade800
                    : (isAll ? Colors.blue.shade800 : Colors.blueGrey.shade700);

                IconData avatarIcon = isHistory
                    ? Icons.history_rounded
                    : (isAll ? Icons.pie_chart_rounded : Icons.person_rounded);

                String cardTitle = isHistory
                    ? "REGISTER HISTORY"
                    : (isAll ? "ALL STAFF (COMBINED REGISTER)" : staffName.toUpperCase());

                Color titleColor = isHistory
                    ? Colors.amber.shade900
                    : (isAll ? Colors.blue.shade900 : Colors.black87);

                return Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    onTap: () => _selectStaff(staffName),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cardBorderColor, width: (isAll || isHistory) ? 2 : 1),
                        gradient: cardGradient,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: avatarBg,
                                child: Icon(avatarIcon, size: 18, color: Colors.white),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  cardTitle,
                                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: titleColor),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("INVOICES", style: TextStyle(fontSize: 10, color: isHistory ? Colors.amber.shade900 : Colors.grey, fontWeight: FontWeight.bold)),
                                  Text("$invoiceCount Bills", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isHistory ? Colors.amber.shade900 : Colors.black87)),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(isHistory ? "HISTORY REVENUE" : "REVENUE", style: TextStyle(fontSize: 10, color: isHistory ? Colors.amber.shade900 : Colors.grey, fontWeight: FontWeight.bold)),
                                  Text("₹ ${totalRevenue.toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: isHistory ? Colors.amber.shade800 : Colors.green.shade800)),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
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

class SpiderLinesPainter extends CustomPainter {
  final bool isLeft;
  final int itemCount;
  final Color color;

  SpiderLinesPainter({
    required this.isLeft,
    required this.itemCount,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (itemCount <= 0) return;

    final paintLine = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final paintDot = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Anchor point at the Main Heading Node (flush against node)
    final double anchorX = isLeft ? size.width : 0.0;
    final double anchorY = size.height / 2.0;

    // Target X at the sub-heading chips column edge
    final double targetX = isLeft ? 0.0 : size.width;

    // Draw main anchor dot
    canvas.drawCircle(Offset(anchorX, anchorY), 4.5, paintDot);

    // Draw spider lines to each sub-heading chip
    for (int i = 0; i < itemCount; i++) {
      final double targetY = itemCount == 1
          ? size.height / 2.0
          : (size.height * (i + 0.5)) / itemCount;

      final path = Path();
      path.moveTo(anchorX, anchorY);

      final double controlX = isLeft
          ? anchorX - (size.width * 0.5)
          : anchorX + (size.width * 0.5);

      path.cubicTo(
        controlX, anchorY,
        controlX, targetY,
        targetX, targetY,
      );

      canvas.drawPath(path, paintLine);

      // Draw connection dot at the end of each spider line
      canvas.drawCircle(Offset(targetX, targetY), 3.2, paintDot);
    }
  }

  @override
  bool shouldRepaint(covariant SpiderLinesPainter oldDelegate) {
    return oldDelegate.isLeft != isLeft ||
        oldDelegate.itemCount != itemCount ||
        oldDelegate.color != color;
  }
}

class CustomHeadingData {
  final String id;
  String name;
  double amount;
  Color color;

  CustomHeadingData({
    required this.id,
    required this.name,
    this.amount = 0.0,
    this.color = const Color(0xFF7C3AED),
  });
}

class HeadingDetailRecord {
  final String dateStr;
  final String name;
  final String remark;
  final double amount;

  HeadingDetailRecord({
    required this.dateStr,
    required this.name,
    required this.remark,
    required this.amount,
  });
}

