import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/pharmacy_provider.dart';
import '../widgets/app_date_picker.dart';
import '../utils/app_formatters.dart';
import '../utils/search_debouncer.dart';
import '../utils/theme_constants.dart';

class PaymentEntryScreen extends StatefulWidget {
  const PaymentEntryScreen({super.key});

  @override
  State<PaymentEntryScreen> createState() => _PaymentEntryScreenState();
}

class _PaymentEntryScreenState extends State<PaymentEntryScreen> {
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();
  String _supplierSearchQuery = "";
  String? _selectedSupplier;
  bool _isLedgerView = false;
  final ScrollController _ledgerScrollCtrl = ScrollController();
  final SearchDebouncer _searchDebouncer = SearchDebouncer(milliseconds: 150);

  int _gridStatusFilter = 0; // 0: All, 1: Due, 2: Settled/Excess

  Map<String, double> _balCache = {};
  Map<String, bool> _activeCache = {};
  List<String> _sortedSuppliers = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recomputeBalances());
  }

  @override
  void dispose() {
    _searchDebouncer.dispose();
    _ledgerScrollCtrl.dispose();
    super.dispose();
  }

  void _recomputeBalances() {
    if (!mounted) return;
    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    final Map<String, double> bal = {};
    final Map<String, bool> active = {};

    for (var s in provider.suppliers) {
      bal[s] = 0.0;
      active[s] = false;
    }

    for (var p in provider.purchases) {
      bal[p.supplierName] = (bal[p.supplierName] ?? 0.0) + p.grandTotal;
      if (p.paymentStatus == 1) {
        bal[p.supplierName] = (bal[p.supplierName] ?? 0.0) - p.paidAmount;
      }
      active[p.supplierName] = true;
    }
    for (var p in provider.supplierPayments) {
      bal[p.supplierName] = (bal[p.supplierName] ?? 0.0) - p.amount;
      active[p.supplierName] = true;
    }
    for (var c in provider.supplierCreditNotes) {
      bal[c.supplierName] = (bal[c.supplierName] ?? 0.0) - c.amount;
      active[c.supplierName] = true;
    }

    final list = provider.suppliers.toList();
    list.sort((a, b) {
      final bool activeA = active[a] ?? false;
      final bool activeB = active[b] ?? false;
      if (activeA && !activeB) return -1;
      if (!activeA && activeB) return 1;

      final balA = bal[a] ?? 0.0;
      final balB = bal[b] ?? 0.0;
      if (balA > 0 && balB <= 0) return -1;
      if (balB > 0 && balA <= 0) return 1;
      return balB.abs().compareTo(balA.abs());
    });

    setState(() {
      _balCache = bal;
      _activeCache = active;
      _sortedSuppliers = list;
    });
  }

  void _scrollToBottom() {
    if (_ledgerScrollCtrl.hasClients) {
      Future.delayed(const Duration(milliseconds: 200), () {
        _ledgerScrollCtrl.animateTo(
          _ledgerScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final provider = Provider.of<PharmacyProvider>(context);
    if (_sortedSuppliers.isEmpty && provider.suppliers.isNotEmpty) {
      final Map<String, double> bal = {};
      final Map<String, bool> active = {};
      for (var s in provider.suppliers) {
        bal[s] = 0.0; active[s] = false;
      }
      for (var p in provider.purchases) {
        bal[p.supplierName] = (bal[p.supplierName] ?? 0.0) + p.grandTotal;
        if (p.paymentStatus == 1) {
          bal[p.supplierName] = (bal[p.supplierName] ?? 0.0) - p.paidAmount;
        }
        active[p.supplierName] = true;
      }
      for (var p in provider.supplierPayments) {
        bal[p.supplierName] = (bal[p.supplierName] ?? 0.0) - p.amount;
        active[p.supplierName] = true;
      }
      for (var c in provider.supplierCreditNotes) {
        bal[c.supplierName] = (bal[c.supplierName] ?? 0.0) - c.amount;
        active[c.supplierName] = true;
      }
      final list = provider.suppliers.toList();
      list.sort((a, b) {
        final bool activeA = active[a] ?? false;
        final bool activeB = active[b] ?? false;
        if (activeA && !activeB) return -1;
        if (!activeA && activeB) return 1;
        final balA = bal[a] ?? 0.0;
        final balB = bal[b] ?? 0.0;
        if (balA > 0 && balB <= 0) return -1;
        if (balB > 0 && balA <= 0) return 1;
        return balB.abs().compareTo(balA.abs());
      });
      _balCache = bal;
      _activeCache = active;
      _sortedSuppliers = list;
    }
    
    return Scaffold(
      backgroundColor: c.background,
      appBar: _isLedgerView ? null : _buildOverviewAppBar(c),
      body: _isLedgerView 
        ? _buildLedgerView(c, provider)
        : _buildOverviewGrid(c, provider),
    );
  }

  PreferredSizeWidget _buildOverviewAppBar(AppThemeColors c) {
    return AppBar(
      backgroundColor: c.cardBg,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: c.secondaryText),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text("PAYMENT OVERVIEW", style: TextStyle(color: c.primaryText, fontWeight: FontWeight.bold, fontSize: 16)),
      actions: [
        _buildGridStatusFilter(c),
        const SizedBox(width: 20),
        Container(
          width: 250,
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: TextField(
            style: TextStyle(color: c.primaryText, fontSize: 12),
            decoration: InputDecoration(
              hintText: "Search Wholesaler...",
              hintStyle: TextStyle(color: c.secondaryText, fontSize: 12),
              prefixIcon: Icon(Icons.search, size: 18, color: c.secondaryText),
              isDense: true,
              filled: true,
              fillColor: c.inputBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
            ),
            onChanged: (v) {
              _searchDebouncer.run(() {
                if (mounted) setState(() => _supplierSearchQuery = v);
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGridStatusFilter(AppThemeColors c) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _statusChip(c, "ALL", 0),
        const SizedBox(width: 8),
        _statusChip(c, "UNPAID", 1, color: Colors.red.shade400),
        const SizedBox(width: 8),
        _statusChip(c, "PAID", 2, color: Colors.green.shade500),
      ],
    );
  }

  Widget _statusChip(AppThemeColors c, String label, int val, {Color? color}) {
    bool isSelected = _gridStatusFilter == val;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : c.secondaryText)),
      selected: isSelected,
      selectedColor: color ?? Colors.blue.shade700,
      onSelected: (s) => setState(() => _gridStatusFilter = val),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildOverviewGrid(AppThemeColors c, PharmacyProvider provider) {
    final filteredSuppliers = _sortedSuppliers.where((s) {
      final queryMatch = s.toLowerCase().contains(_supplierSearchQuery.toLowerCase());
      if (!queryMatch) return false;

      if (_gridStatusFilter == 0) return true;
      final balance = _balCache[s] ?? 0.0;
      if (_gridStatusFilter == 1) return balance > 0;
      if (_gridStatusFilter == 2) return balance <= 0 && (_activeCache[s] ?? false);
      return true;
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          childAspectRatio: 1.4,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: filteredSuppliers.length,
        itemBuilder: (context, index) {
          final supplierName = filteredSuppliers[index];
          final balance = _balCache[supplierName] ?? 0.0;
          final bool active = _activeCache[supplierName] ?? false;
          final bool isDebt = balance > 0;

          final Color boxColor = !active
              ? (c.isDark ? const Color(0xFF334155) : Colors.blueGrey.shade100)
              : (isDebt ? Colors.red.shade400 : Colors.green.shade500);

          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedSupplier = supplierName;
                  _isLedgerView = true;
                });
                _scrollToBottom();
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: boxColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: boxColor.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("${index + 1}",
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                        if (!active) Icon(Icons.info_outline, color: Colors.white.withValues(alpha: 0.6), size: 12),
                      ],
                    ),
                    Text(
                      supplierName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (active)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                        child: Text(
                          "₹ ${balance.abs().toStringAsFixed(0)}",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                        ),
                      )
                    else
                      const Text("No History", style: TextStyle(color: Colors.white54, fontSize: 11, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLedgerView(AppThemeColors c, PharmacyProvider provider) {
    final List<_LedgerRowData> ledgerData = [];
    
    for (var p in provider.purchases.where((p) => p.supplierName == _selectedSupplier)) {
      ledgerData.add(_LedgerRowData(
        date: p.date,
        reference: p.entryNo,
        debit: p.grandTotal,
        credit: 0.0,
        type: 'PURCHASE',
        invoice: cleanInvoiceNo(p.supInvNo),
      ));
      
      if (p.paymentStatus == 1 && p.paidAmount > 0) {
        ledgerData.add(_LedgerRowData(
          date: p.paymentDate ?? p.date,
          reference: "AUTO-${p.entryNo}",
          debit: 0.0,
          credit: p.paidAmount,
          type: 'PAYMENT',
          method: p.paymentMode ?? "CASH",
          invoice: cleanInvoiceNo(p.supInvNo),
          remarks: "Auto Paid - Cash Purchase",
        ));
      }
    }
    
    for (var pay in provider.supplierPayments.where((pay) => pay.supplierName == _selectedSupplier)) {
      ledgerData.add(_LedgerRowData(
        date: pay.date,
        reference: pay.id,
        debit: 0.0,
        credit: pay.amount,
        type: 'PAYMENT',
        remarks: pay.remarks,
        method: pay.paymentMethod,
        invoice: pay.invoiceNo,
      ));
    }

    for (var cn in provider.supplierCreditNotes.where((cn) => cn.supplierName == _selectedSupplier)) {
      ledgerData.add(_LedgerRowData(
        date: cn.date,
        reference: cn.id,
        debit: 0.0,
        credit: cn.amount,
        type: 'CREDIT NOTE',
        remarks: cn.remarks,
        invoice: cn.invoiceNo,
      ));
    }

    ledgerData.sort((a, b) => a.date.compareTo(b.date));

    return Row(
      children: [
        _buildLedgerSidebar(c, provider),
        VerticalDivider(width: 1, color: c.border),
        Expanded(
          child: Column(
            children: [
              _buildLedgerHeader(c),
              _buildLedgerTableHeader(),
              Expanded(
                child: Container(
                  color: c.cardBg,
                  child: _buildLedgerRows(c, ledgerData, provider),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLedgerSidebar(AppThemeColors c, PharmacyProvider provider) {
    final filteredSuppliers = provider.suppliers
        .where((s) => s.toLowerCase().contains(_supplierSearchQuery.toLowerCase()))
        .toList();

    return Container(
      width: 250,
      color: c.cardBg,
      child: Column(
        children: [
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: Colors.blue.shade800,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                  onPressed: () => setState(() => _isLedgerView = false),
                ),
                const Expanded(
                  child: Text("BACK TO GRID", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              style: TextStyle(color: c.primaryText, fontSize: 12),
              decoration: InputDecoration(hintText: "Search...", hintStyle: TextStyle(color: c.secondaryText, fontSize: 12), prefixIcon: Icon(Icons.search, size: 18, color: c.secondaryText), isDense: true, border: OutlineInputBorder(borderSide: BorderSide(color: c.border))),
              onChanged: (v) => setState(() => _supplierSearchQuery = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredSuppliers.length,
              itemBuilder: (ctx, i) {
                final s = filteredSuppliers[i];
                bool isSelected = _selectedSupplier == s;
                return ListTile(
                  title: Text(s, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? (c.isDark ? Colors.blueAccent : Colors.blue.shade800) : c.primaryText)),
                  selected: isSelected,
                  selectedTileColor: c.isDark ? Colors.blue.shade900.withValues(alpha: 0.3) : Colors.blue.shade50,
                  onTap: () {
                    setState(() => _selectedSupplier = s);
                    _scrollToBottom();
                  },
                  dense: true,
                  visualDensity: VisualDensity.compact,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLedgerHeader(AppThemeColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(bottom: BorderSide(color: c.border, width: 1)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: c.isDark ? 0.2 : 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.blueAccent, size: 24),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_selectedSupplier!.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.5, color: c.primaryText)),
              Text("Transaction Ledger", style: TextStyle(fontSize: 12, color: c.secondaryText, fontWeight: FontWeight.w500)),
            ],
          ),
          const Spacer(),
          _dateRangePicker(c),
          const SizedBox(width: 24),
          _actionButton("ADD PAYMENT", Icons.add_card, Colors.green, onTap: () => _showPaymentDialog()),
          const SizedBox(width: 12),
          _actionButton("CREDIT NOTE", Icons.receipt_long_outlined, Colors.orange.shade800, onTap: () => _showCreditNoteDialog()),
        ],
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, Color color, {VoidCallback? onTap}) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
    );
  }

  void _showPaymentDialog({SupplierPayment? existing}) {
    final c = AppColors.of(context);
    final bool isEdit = existing != null;
    final TextEditingController amountCtrl = TextEditingController(text: isEdit ? existing.amount.toString() : "");
    final TextEditingController invoiceCtrl = TextEditingController(text: isEdit ? existing.invoiceNo : "");
    final TextEditingController remarksCtrl = TextEditingController(text: isEdit ? existing.remarks : "");
    final TextEditingController noCtrl = TextEditingController(text: isEdit ? existing.id : "PAY-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}");
    DateTime paymentDate = isEdit ? existing.date : DateTime.now();
    String method = isEdit ? existing.paymentMethod : "CASH";

    bool isSaving = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: c.surface,
          title: Row(
            children: [
              Icon(isEdit ? Icons.edit : Icons.payment, color: isEdit ? Colors.orange : Colors.green),
              const SizedBox(width: 10),
              Text(isEdit ? "Edit Payment Entry" : "New Payment Entry", style: TextStyle(color: c.primaryText)),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: _dialogInput(c, "Payment No", noCtrl, enabled: false)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showAppDatePicker(context: context, initialDate: paymentDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                          if (picked != null) setDialogState(() => paymentDate = picked);
                        },
                        child: _dialogFieldLabel(c, "Date", DateFormat('dd/MM/yyyy').format(paymentDate)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _dialogInput(c, "Amount", amountCtrl, isNum: true, autofocus: true),
                const SizedBox(height: 12),
                _dialogInput(c, "Invoice / Ref", invoiceCtrl),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text("Method: ", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c.secondaryText)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButton<String>(
                        value: method,
                        isExpanded: true,
                        dropdownColor: c.surface,
                        style: TextStyle(color: c.primaryText, fontSize: 13, fontWeight: FontWeight.bold),
                        items: ["CASH", "UPI", "BANK"].map((e) => DropdownMenuItem(value: e, child: Text(e, style: TextStyle(color: c.primaryText)))).toList(),
                        onChanged: (v) => setDialogState(() => method = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _dialogInput(c, "Remarks", remarksCtrl),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text("CANCEL", style: TextStyle(color: c.secondaryText))),
            ElevatedButton(
              onPressed: () async {
                if (amountCtrl.text.isEmpty || isSaving) return;
                setDialogState(() => isSaving = true);
                try {
                  final provider = Provider.of<PharmacyProvider>(context, listen: false);
                  final payObj = SupplierPayment(
                    id: noCtrl.text,
                    supplierName: _selectedSupplier!,
                    date: paymentDate,
                    amount: double.tryParse(amountCtrl.text) ?? 0.0,
                    invoiceNo: invoiceCtrl.text,
                    paymentMethod: method,
                    remarks: remarksCtrl.text,
                  );
                  
                  if (isEdit) {
                    await provider.updateSupplierPayment(payObj);
                  } else {
                    await provider.addSupplierPayment(payObj);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                } finally {
                  setDialogState(() => isSaving = false);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: isEdit ? Colors.orange : Colors.green, foregroundColor: Colors.white),
              child: Text(isEdit ? "UPDATE PAYMENT" : "SAVE PAYMENT"),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreditNoteDialog({SupplierCreditNote? existing}) {
    final c = AppColors.of(context);
    final bool isEdit = existing != null;
    final TextEditingController amountCtrl = TextEditingController(text: isEdit ? existing.amount.toString() : "");
    final TextEditingController invoiceCtrl = TextEditingController(text: isEdit ? existing.invoiceNo : "");
    final TextEditingController remarksCtrl = TextEditingController(text: isEdit ? existing.remarks : "");
    final TextEditingController noCtrl = TextEditingController(text: isEdit ? existing.id : "CN-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}");
    DateTime cnDate = isEdit ? existing.date : DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: c.surface,
          title: Row(
            children: [
              Icon(isEdit ? Icons.edit : Icons.receipt_long, color: Colors.orange.shade800),
              const SizedBox(width: 10),
              Text(isEdit ? "Edit Credit Note" : "New Credit Note Entry", style: TextStyle(color: c.primaryText)),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: _dialogInput(c, "CN Number", noCtrl, enabled: false)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showAppDatePicker(context: context, initialDate: cnDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                          if (picked != null) setDialogState(() => cnDate = picked);
                        },
                        child: _dialogFieldLabel(c, "Date", DateFormat('dd/MM/yyyy').format(cnDate)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _dialogInput(c, "Credit Amount", amountCtrl, isNum: true, autofocus: true),
                const SizedBox(height: 12),
                _dialogInput(c, "Invoice / Purchase Ref", invoiceCtrl),
                const SizedBox(height: 12),
                _dialogInput(c, "Remarks / Reason", remarksCtrl),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text("CANCEL", style: TextStyle(color: c.secondaryText))),
            ElevatedButton(
              onPressed: () async {
                if (amountCtrl.text.isEmpty) return;
                final provider = Provider.of<PharmacyProvider>(context, listen: false);
                final cnObj = SupplierCreditNote(
                  id: noCtrl.text,
                  supplierName: _selectedSupplier!,
                  date: cnDate,
                  amount: double.tryParse(amountCtrl.text) ?? 0.0,
                  invoiceNo: invoiceCtrl.text,
                  remarks: remarksCtrl.text,
                );
                
                if (isEdit) {
                  await provider.updateSupplierCreditNote(cnObj);
                } else {
                  await provider.addSupplierCreditNote(cnObj);
                }
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white),
              child: Text(isEdit ? "UPDATE CREDIT NOTE" : "SAVE CREDIT NOTE"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogInput(AppThemeColors c, String label, TextEditingController ctrl, {bool isNum = false, bool enabled = true, bool autofocus = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: c.secondaryText)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          enabled: enabled,
          autofocus: autofocus,
          keyboardType: isNum ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderSide: BorderSide(color: c.border)), contentPadding: const EdgeInsets.all(8), fillColor: c.inputBg, filled: true),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: c.primaryText),
        ),
      ],
    );
  }

  Widget _dialogFieldLabel(AppThemeColors c, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: c.secondaryText)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(4), color: c.inputBg),
          child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: c.primaryText)),
        ),
      ],
    );
  }

  Widget _dateRangePicker(AppThemeColors c) {
    return InkWell(
      onTap: () async {
        final DateTimeRange? picked = await showDateRangePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDateRange: DateTimeRange(start: _startDate, end: _endDate));
        if (picked != null) {
          setState(() { _startDate = picked.start; _endDate = picked.end; });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.blue.withValues(alpha: 0.3))),
        child: Row(
          children: [
            const Icon(Icons.calendar_month, size: 14, color: Colors.blueAccent),
            const SizedBox(width: 8),
            Text("${DateFormat('dd/MM/yy').format(_startDate)} - ${DateFormat('dd/MM/yy').format(_endDate)}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
          ],
        ),
      ),
    );
  }

  Widget _buildLedgerTableHeader() {
    return Container(
      height: 35,
      color: const Color(0xFF334155),
      child: Row(
        children: [
          _hCell("DATE", width: 100),
          _hCell("ENTRY NO / REF", width: 150),
          _hCell("INVOICE NO", width: 120),
          _hCell("PURCHASE", flex: 1, align: TextAlign.right),
          _hCell("PAYMENT", flex: 1, align: TextAlign.right),
          _hCell("BALANCE", flex: 1, align: TextAlign.right),
          _hCell("ACT", width: 60, align: TextAlign.center),
        ],
      ),
    );
  }

  Widget _hCell(String t, {double? width, int? flex, TextAlign align = TextAlign.left}) {
    Widget child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: align == TextAlign.left ? Alignment.centerLeft : Alignment.centerRight,
      child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
    if (width != null) return SizedBox(width: width, child: child);
    return Expanded(flex: flex ?? 1, child: child);
  }

  Widget _buildLedgerRows(AppThemeColors c, List<_LedgerRowData> ledgerData, PharmacyProvider provider) {
    double tempBalance = 0;
    int lastSettledIndex = -1;

    for (int i = 0; i < ledgerData.length; i++) {
      tempBalance += ledgerData[i].debit;
      tempBalance -= ledgerData[i].credit;
      if (tempBalance.abs() < 0.01) {
        lastSettledIndex = i;
      }
    }

    double runningBalance = 0;
    List<Widget> visibleRows = [];

    for (int i = 0; i < ledgerData.length; i++) {
      var row = ledgerData[i];
      runningBalance += row.debit;
      runningBalance -= row.credit;

      bool inRange = row.date.isAfter(_startDate.subtract(const Duration(seconds: 1))) &&
          row.date.isBefore(_endDate.add(const Duration(days: 1)));
      
      if (inRange) {
        Color balColor = c.primaryText; 
        
        if (i > lastSettledIndex && runningBalance.abs() >= 0.01) {
          balColor = runningBalance > 0 ? Colors.greenAccent : Colors.redAccent;
        }

        visibleRows.add(_buildGridRow(c, row, runningBalance, provider, balColor));
      }
    }

    if (visibleRows.isEmpty) {
      return Center(child: Text("No records found for this period.", style: TextStyle(fontSize: 12, color: c.secondaryText)));
    }

    return ListView(
      controller: _ledgerScrollCtrl,
      children: visibleRows,
    );
  }

  Widget _buildGridRow(AppThemeColors c, _LedgerRowData data, double balance, PharmacyProvider provider, Color balColor) {
    bool isPay = data.type == 'PAYMENT' || data.type == 'CREDIT NOTE';
    bool isAuto = data.reference.startsWith("AUTO-");
    
    String cleanBalance = balance.abs() < 0.01 ? "0.00" : balance.toStringAsFixed(2);
    
    return Container(
      height: 35,
      decoration: BoxDecoration(
        color: data.type == 'PAYMENT' ? Colors.green.withValues(alpha: 0.12) 
             : data.type == 'CREDIT NOTE' ? Colors.orange.withValues(alpha: 0.12)
             : c.cardBg,
        border: Border(bottom: BorderSide(color: c.border))
      ),
      child: Row(
        children: [
          _cell(c, DateFormat('dd/MM/yy').format(data.date), width: 100),
          _cell(c, data.reference, width: 150, fontWeight: FontWeight.bold),
          _cell(c, data.invoice, width: 120, color: c.secondaryText, fontWeight: FontWeight.w500),
          _cell(c, data.debit > 0 ? data.debit.toStringAsFixed(2) : "", flex: 1, align: TextAlign.right),
          _cell(c, data.credit > 0 ? data.credit.toStringAsFixed(2) : "", flex: 1, align: TextAlign.right, fontWeight: FontWeight.bold),
          _cell(c, cleanBalance, flex: 1, align: TextAlign.right, color: balColor, fontWeight: FontWeight.bold),
          SizedBox(
            width: 60,
            child: (isPay && !isAuto) ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                InkWell(
                  onTap: () {
                    if (data.type == 'PAYMENT') {
                      final payment = provider.supplierPayments.firstWhere((p) => p.id == data.reference);
                      _showPaymentDialog(existing: payment);
                    } else if (data.type == 'CREDIT NOTE') {
                      final cn = provider.supplierCreditNotes.firstWhere((p) => p.id == data.reference);
                      _showCreditNoteDialog(existing: cn);
                    }
                  },
                  child: const Icon(Icons.edit, size: 14, color: Colors.orange),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _showDeleteConfirm(data.reference, data.type),
                  child: const Icon(Icons.delete, size: 14, color: Colors.red),
                ),
              ],
            ) : null,
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(String refId, String type) {
    final c = AppColors.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text("Confirm Delete", style: TextStyle(color: c.primaryText)),
        content: Text("Are you sure you want to delete this $type entry?", style: TextStyle(color: c.secondaryText)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("CANCEL", style: TextStyle(color: c.secondaryText))),
          ElevatedButton(
            onPressed: () {
              final provider = Provider.of<PharmacyProvider>(context, listen: false);
              if (type == 'PAYMENT') {
                provider.deleteSupplierPayment(refId);
              } else {
                provider.deleteSupplierCreditNote(refId);
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("DELETE"),
          ),
        ],
      ),
    );
  }

  Widget _cell(AppThemeColors c, String t, {double? width, int? flex, TextAlign align = TextAlign.left, Color? color, FontWeight? fontWeight}) {
    Widget child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: align == TextAlign.left ? Alignment.centerLeft : Alignment.centerRight,
      child: Text(t, style: TextStyle(fontSize: 12, color: color ?? c.primaryText, fontWeight: fontWeight), overflow: TextOverflow.ellipsis),
    );
    if (width != null) return SizedBox(width: width, child: child);
    return Expanded(flex: flex ?? 1, child: child);
  }
}

class _LedgerRowData {
  final DateTime date;
  final String reference;
  final double debit;
  final double credit;
  final String type;
  final String remarks;
  final String method;
  final String invoice;

  _LedgerRowData({
    required this.date,
    required this.reference,
    required this.debit,
    required this.credit,
    required this.type,
    this.remarks = "",
    this.method = "",
    this.invoice = "",
  });
}
