import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/pharmacy_provider.dart';
import '../database/db_helper.dart';
import '../utils/app_formatters.dart';

enum AccountTarget { customer, wholesaler }

class PaymentReceivedDialog extends StatefulWidget {
  final AccountTarget initialTarget;
  final String? initialName;

  const PaymentReceivedDialog({
    super.key,
    this.initialTarget = AccountTarget.customer,
    this.initialName,
  });

  @override
  State<PaymentReceivedDialog> createState() => _PaymentReceivedDialogState();
}

class _PaymentReceivedDialogState extends State<PaymentReceivedDialog> {
  late AccountTarget _selectedTarget;
  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedAccountName = "";

  bool _isLoadingLedger = false;
  List<Map<String, dynamic>> _ledgerEntries = [];
  double _currentBalance = 0.0;

  @override
  void initState() {
    super.initState();
    _selectedTarget = widget.initialTarget;
    if (widget.initialName != null && widget.initialName!.isNotEmpty) {
      _selectedAccountName = widget.initialName!;
      _searchCtrl.text = widget.initialName!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchLedger());
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchLedger() async {
    if (_selectedAccountName.trim().isEmpty) return;
    setState(() => _isLoadingLedger = true);

    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final db = await DbHelper.instance.database;

    try {
      if (_selectedTarget == AccountTarget.customer) {
        // Fetch Customer (Patient) Ledger
        final ledger = await provider.fetchPatientLedger(_selectedAccountName.trim());
        
        // Calculate balance: Positive = Customer owes pharmacy (Need to get -> RED)
        double bal = 0.0;
        for (var row in ledger) {
          bal += ((row['debit'] as num?)?.toDouble() ?? 0.0) - ((row['credit'] as num?)?.toDouble() ?? 0.0);
        }

        if (mounted) {
          setState(() {
            _ledgerEntries = ledger;
            _currentBalance = bal;
          });
        }
      } else {
        // Fetch Wholesaler (Supplier) Ledger
        final String supName = _selectedAccountName.trim();
        List<Map<String, dynamic>> ledger = [];

        // 1. Purchases (Debit to store / Credit to supplier)
        final purchases = await db.query(
          'purchase_entries',
          where: 'supplier_name = ? COLLATE NOCASE AND IFNULL(is_deleted, 0) = 0',
          whereArgs: [supName],
          orderBy: 'date ASC',
        );
        for (var p in purchases) {
          DateTime dt = DateTime.tryParse(p['date'].toString()) ?? DateTime.now();
          ledger.add({
            'date': dt,
            'reference': p['entry_no'],
            'invoice': cleanInvoiceNo(p['sup_inv_no']).isNotEmpty ? cleanInvoiceNo(p['sup_inv_no']) : p['entry_no'],
            'type': 'PURCHASE',
            'debit': (p['grand_total'] as num?)?.toDouble() ?? 0.0, // Bill amount we owe
            'credit': 0.0,
            'remarks': "Purchase Invoice #${cleanInvoiceNo(p['sup_inv_no']).isNotEmpty ? cleanInvoiceNo(p['sup_inv_no']) : p['entry_no']}",
          });

          // Immediate payment if marked paid
          double paid = (p['paid_amount'] as num?)?.toDouble() ?? 0.0;
          if (paid > 0) {
            ledger.add({
              'date': dt,
              'reference': "AUTO-${p['entry_no']}",
              'invoice': cleanInvoiceNo(p['sup_inv_no']).isNotEmpty ? cleanInvoiceNo(p['sup_inv_no']) : p['entry_no'],
              'type': 'PAYMENT',
              'debit': 0.0,
              'credit': paid,
              'remarks': "Immediate Payment (${p['payment_mode'] ?? 'Cash'})",
            });
          }
        }

        // 2. Purchase Returns
        final purReturns = await db.query(
          'purchase_return_entries',
          where: 'supplier_name = ? COLLATE NOCASE AND IFNULL(is_deleted, 0) = 0',
          whereArgs: [supName],
          orderBy: 'date ASC',
        );
        for (var pr in purReturns) {
          DateTime dt = DateTime.tryParse(pr['date'].toString()) ?? DateTime.now();
          ledger.add({
            'date': dt,
            'reference': pr['entry_no'],
            'invoice': pr['original_purchase_no'],
            'type': 'PUR RETURN',
            'debit': 0.0,
            'credit': (pr['grand_total'] as num?)?.toDouble() ?? 0.0,
            'remarks': "Return against Pur #${pr['original_purchase_no']}",
          });
        }

        // 3. Manual Supplier Payments
        final payments = await db.query(
          'supplier_payments',
          where: 'supplier_name = ? COLLATE NOCASE',
          whereArgs: [supName],
          orderBy: 'date ASC',
        );
        for (var pay in payments) {
          DateTime dt = DateTime.tryParse(pay['date'].toString()) ?? DateTime.now();
          ledger.add({
            'date': dt,
            'reference': pay['id'],
            'invoice': pay['invoice_no'],
            'type': 'PAYMENT',
            'debit': 0.0,
            'credit': (pay['amount'] as num?)?.toDouble() ?? 0.0,
            'remarks': pay['remarks'] ?? "Payment via ${pay['payment_method']}",
          });
        }

        // 4. Supplier Credit Notes
        final creditNotes = await db.query(
          'supplier_credit_notes',
          where: 'supplier_name = ? COLLATE NOCASE',
          whereArgs: [supName],
          orderBy: 'date ASC',
        );
        for (var cn in creditNotes) {
          DateTime dt = DateTime.tryParse(cn['date'].toString()) ?? DateTime.now();
          ledger.add({
            'date': dt,
            'reference': cn['id'],
            'invoice': cn['invoice_no'],
            'type': 'CREDIT NOTE',
            'debit': 0.0,
            'credit': (cn['amount'] as num?)?.toDouble() ?? 0.0,
            'remarks': cn['remarks'] ?? "Credit Note adjustment",
          });
        }

        ledger.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

        // Balance for Wholesaler: Positive = Store owes wholesaler (Need to give -> GREEN)
        double bal = 0.0;
        for (var row in ledger) {
          bal += ((row['debit'] as num?)?.toDouble() ?? 0.0) - ((row['credit'] as num?)?.toDouble() ?? 0.0);
        }

        if (mounted) {
          setState(() {
            _ledgerEntries = ledger;
            _currentBalance = bal;
          });
        }
      }
    } catch (e) {
      debugPrint("Ledger Fetch Error: $e");
    } finally {
      if (mounted) setState(() => _isLoadingLedger = false);
    }
  }

  void _openPaymentDialog() {
    if (_selectedAccountName.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please search and select an account first!"), backgroundColor: Colors.orange),
      );
      return;
    }

    final amtCtrl = TextEditingController(text: _currentBalance > 0 ? _currentBalance.toStringAsFixed(2) : "");
    final cashCtrl = TextEditingController();
    final upiCtrl = TextEditingController();
    final cardCtrl = TextEditingController();
    final bankCtrl = TextEditingController();

    final remarksCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    String paymentMode = "CASH";
    bool isSplitMode = false;
    DateTime payDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSubState) {
          double cashVal = double.tryParse(cashCtrl.text) ?? 0.0;
          double upiVal = double.tryParse(upiCtrl.text) ?? 0.0;
          double cardVal = double.tryParse(cardCtrl.text) ?? 0.0;
          double bankVal = double.tryParse(bankCtrl.text) ?? 0.0;
          double splitTotal = cashVal + upiVal + cardVal + bankVal;

          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.add_card_rounded, color: Colors.tealAccent),
                const SizedBox(width: 10),
                Text(
                  _selectedTarget == AccountTarget.customer ? "Receive Payment (Customer)" : "Make Payment (Wholesaler)",
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                ChoiceChip(
                  label: Text(isSplitMode ? "Split Payment" : "Single Payment"),
                  selected: isSplitMode,
                  selectedColor: Colors.teal,
                  backgroundColor: const Color(0xFF0F172A),
                  labelStyle: TextStyle(
                    color: isSplitMode ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                  onSelected: (val) => setSubState(() => isSplitMode = val),
                ),
              ],
            ),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Account: $_selectedAccountName", style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    if (!isSplitMode) ...[
                      TextField(
                        controller: amtCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: "Amount (₹)*",
                          labelStyle: const TextStyle(color: Colors.tealAccent),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: paymentMode,
                              dropdownColor: const Color(0xFF0F172A),
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                labelText: "Payment Mode",
                                labelStyle: const TextStyle(color: Colors.white70),
                                filled: true,
                                fillColor: const Color(0xFF0F172A),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              items: ["CASH", "UPI", "CARD", "BANK", "CHEQUE"]
                                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                                  .toList(),
                              onChanged: (v) => setSubState(() => paymentMode = v ?? "CASH"),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: refCtrl,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                labelText: "Invoice / Ref #",
                                labelStyle: const TextStyle(color: Colors.white70),
                                filled: true,
                                fillColor: const Color(0xFF0F172A),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.teal.shade700),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: cashCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                    onChanged: (_) => setSubState(() {}),
                                    decoration: const InputDecoration(
                                      labelText: "Cash (₹)",
                                      labelStyle: TextStyle(color: Colors.tealAccent, fontSize: 12),
                                      prefixIcon: Icon(Icons.money, color: Colors.green, size: 18),
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: upiCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                    onChanged: (_) => setSubState(() {}),
                                    decoration: const InputDecoration(
                                      labelText: "UPI / QR (₹)",
                                      labelStyle: TextStyle(color: Colors.cyanAccent, fontSize: 12),
                                      prefixIcon: Icon(Icons.qr_code, color: Colors.cyan, size: 18),
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: cardCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                    onChanged: (_) => setSubState(() {}),
                                    decoration: const InputDecoration(
                                      labelText: "Card (₹)",
                                      labelStyle: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                                      prefixIcon: Icon(Icons.credit_card, color: Colors.orange, size: 18),
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: bankCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                    onChanged: (_) => setSubState(() {}),
                                    decoration: const InputDecoration(
                                      labelText: "Bank / Cheque (₹)",
                                      labelStyle: TextStyle(color: Colors.purpleAccent, fontSize: 12),
                                      prefixIcon: Icon(Icons.account_balance, color: Colors.purple, size: 18),
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade900.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("TOTAL SPLIT TENDER:", style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                                  Text("₹${splitTotal.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: refCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: "Invoice / Ref #",
                          labelStyle: const TextStyle(color: Colors.white70),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextField(
                      controller: remarksCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: "Remarks (Optional)",
                        labelStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () async {
                  double parsedAmt = isSplitMode
                      ? splitTotal
                      : (double.tryParse(amtCtrl.text.replaceAll(',', '').trim()) ?? 0.0);

                  if (parsedAmt <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Enter a valid total amount!"), backgroundColor: Colors.red),
                    );
                    return;
                  }

                  String finalPaymentMode = isSplitMode ? "SPLIT" : paymentMode;
                  List<String> splitParts = [];
                  if (isSplitMode) {
                    if (cashVal > 0) splitParts.add("Cash: ₹${cashVal.toStringAsFixed(2)}");
                    if (upiVal > 0) splitParts.add("UPI: ₹${upiVal.toStringAsFixed(2)}");
                    if (cardVal > 0) splitParts.add("Card: ₹${cardVal.toStringAsFixed(2)}");
                    if (bankVal > 0) splitParts.add("Bank: ₹${bankVal.toStringAsFixed(2)}");
                  }

                  String userRemarks = remarksCtrl.text.trim();
                  String finalRemarks = isSplitMode
                      ? "Split Tender [${splitParts.join(', ')}] ${userRemarks.isNotEmpty ? '| $userRemarks' : ''}"
                      : (userRemarks.isNotEmpty ? userRemarks : (_selectedTarget == AccountTarget.customer ? "Direct Customer Receipt" : "Wholesaler Settlement"));

                  final provider = Provider.of<PharmacyProvider>(context, listen: false);

                  if (_selectedTarget == AccountTarget.customer) {
                    await provider.addPatientPayment(SupplierPayment(
                      id: "RCT_${DateTime.now().millisecondsSinceEpoch}",
                      supplierName: _selectedAccountName.trim(),
                      date: payDate,
                      amount: parsedAmt,
                      invoiceNo: refCtrl.text.trim(),
                      paymentMethod: finalPaymentMode,
                      remarks: finalRemarks,
                    ));
                  } else {
                    await provider.addSupplierPayment(SupplierPayment(
                      id: "PAY_${DateTime.now().millisecondsSinceEpoch}",
                      supplierName: _selectedAccountName.trim(),
                      date: payDate,
                      amount: parsedAmt,
                      invoiceNo: refCtrl.text.trim(),
                      paymentMethod: finalPaymentMode,
                      remarks: finalRemarks,
                    ));
                  }

                  if (mounted) {
                    Navigator.pop(ctx);
                    _fetchLedger();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Payment transaction recorded successfully!"), backgroundColor: Colors.green),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: const Text("SAVE PAYMENT", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PharmacyProvider>(context);

    // Color Rules:
    // 1. Need to give -> GREEN
    // 2. Need to get to our pharmacy -> RED
    bool isNeedToGet = (_selectedTarget == AccountTarget.customer && _currentBalance > 0) ||
        (_selectedTarget == AccountTarget.wholesaler && _currentBalance < 0);
    bool isNeedToGive = (_selectedTarget == AccountTarget.wholesaler && _currentBalance > 0) ||
        (_selectedTarget == AccountTarget.customer && _currentBalance < 0);

    Color balanceColor = Colors.grey.shade400;
    String statusText = "SETTLED (₹0.00)";

    if (_currentBalance.abs() > 0.01) {
      if (isNeedToGet) {
        balanceColor = const Color(0xFFEF4444); // RED
        statusText = "NEED TO GET: ₹${_currentBalance.abs().toStringAsFixed(2)}";
      } else if (isNeedToGive) {
        balanceColor = const Color(0xFF10B981); // GREEN
        statusText = "NEED TO GIVE: ₹${_currentBalance.abs().toStringAsFixed(2)}";
      }
    }

    final List<String> searchOptions = _selectedTarget == AccountTarget.customer
        ? provider.patients
        : provider.suppliers;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 1100,
        height: 720,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            // Top Controls Bar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_rounded, color: Colors.tealAccent, size: 24),
                  const SizedBox(width: 10),
                  const Text(
                    "ACCOUNTS & PAYMENT SETTLEMENT",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1),
                  ),
                  const Spacer(),
                  // Target Switcher (Customer vs Wholesaler)
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blueGrey.shade700),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildTargetTab("CUSTOMER", AccountTarget.customer),
                        _buildTargetTab("WHOLESALER", AccountTarget.wholesaler),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Search Bar & Balance Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              color: const Color(0xFF1E293B).withValues(alpha: 0.6),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Autocomplete<String>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        final query = textEditingValue.text.trim().toLowerCase();
                        
                        // 1. Hide dropdown if empty OR if already 100% matched/selected
                        if (query.isEmpty || query == _selectedAccountName.trim().toLowerCase()) {
                          return const Iterable<String>.empty();
                        }

                        // 2. Filter and prioritize matches starting with typed alphabets
                        final matches = searchOptions
                            .where((opt) => opt.toLowerCase().contains(query))
                            .toList();

                        matches.sort((a, b) {
                          final aStarts = a.toLowerCase().startsWith(query);
                          final bStarts = b.toLowerCase().startsWith(query);
                          if (aStarts != bStarts) return aStarts ? -1 : 1;
                          return a.toLowerCase().compareTo(b.toLowerCase());
                        });

                        return matches.take(50);
                      },
                      onSelected: (String selection) {
                        setState(() {
                          _selectedAccountName = selection;
                          _searchCtrl.text = selection;
                        });
                        _fetchLedger();
                      },
                      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          // Capture Enter key directly on selection
                          onSubmitted: (value) {
                            final q = value.trim().toLowerCase();
                            if (q.isNotEmpty) {
                              final matched = searchOptions.firstWhere(
                                (opt) => opt.toLowerCase() == q,
                                orElse: () => searchOptions.firstWhere(
                                  (opt) => opt.toLowerCase().contains(q),
                                  orElse: () => "",
                                ),
                              );
                              if (matched.isNotEmpty) {
                                controller.text = matched;
                                setState(() {
                                  _selectedAccountName = matched;
                                });
                                _fetchLedger();
                                focusNode.unfocus();
                                return;
                              }
                            }
                            onFieldSubmitted();
                          },
                          decoration: InputDecoration(
                            hintText: "Search ${_selectedTarget == AccountTarget.customer ? 'Customer / Patient' : 'Wholesaler / Supplier'}...",
                            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                            prefixIcon: const Icon(Icons.search, color: Colors.tealAccent, size: 20),
                            suffixIcon: _selectedAccountName.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, color: Colors.white38, size: 16),
                                    onPressed: () {
                                      controller.clear();
                                      setState(() {
                                        _selectedAccountName = "";
                                        _ledgerEntries.clear();
                                        _currentBalance = 0.0;
                                      });
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.blueGrey.shade700),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.blueGrey.shade700),
                            ),
                          ),
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 8,
                            borderRadius: BorderRadius.circular(8),
                            color: const Color(0xFF1E293B),
                            child: Container(
                              width: 380,
                              constraints: const BoxConstraints(maxHeight: 260),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blueGrey.shade700),
                              ),
                              child: ListView.separated(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length,
                                separatorBuilder: (_, __) => Divider(height: 1, color: Colors.blueGrey.shade800),
                                itemBuilder: (context, index) {
                                  final option = options.elementAt(index);
                                  return InkWell(
                                    onTap: () => onSelected(option),
                                    hoverColor: Colors.teal.withValues(alpha: 0.2),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      child: Text(
                                        option,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 20),
                  // Highlighted Balance Display
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: balanceColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: balanceColor, width: 1.8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isNeedToGet ? Icons.arrow_downward_rounded : (isNeedToGive ? Icons.arrow_upward_rounded : Icons.check_circle),
                          color: balanceColor,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: balanceColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _selectedAccountName.isNotEmpty ? _openPaymentDialog : null,
                    icon: const Icon(Icons.payment_rounded, size: 18),
                    label: const Text("RECORD PAYMENT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade800,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),

            // Ledger History Table View
            Expanded(
              child: _isLoadingLedger
                  ? const Center(child: CircularProgressIndicator())
                  : _selectedAccountName.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: Map<String, int>.from({}).isEmpty ? MainAxisSize.min : MainAxisSize.max,
                            children: [
                              Icon(Icons.search, size: 48, color: Colors.blueGrey.shade700),
                              const SizedBox(height: 12),
                              const Text(
                                "Search and choose an account above to view history and balance.",
                                style: TextStyle(color: Colors.blueGrey, fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      : _ledgerEntries.isEmpty
                          ? const Center(child: Text("No transaction history found for this account.", style: TextStyle(color: Colors.white54)))
                          : _buildLedgerTable(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetTab(String label, AccountTarget target) {
    bool isSelected = _selectedTarget == target;
    return InkWell(
      onTap: () {
        if (_selectedTarget != target) {
          setState(() {
            _selectedTarget = target;
            _selectedAccountName = "";
            _searchCtrl.clear();
            _ledgerEntries.clear();
            _currentBalance = 0.0;
          });
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.teal : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.blueGrey.shade300,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildLedgerTable() {
    double runningBal = 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.blueGrey.shade800),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DataTable(
          headingRowHeight: 38,
          dataRowMinHeight: 32,
          dataRowMaxHeight: 36,
          headingRowColor: WidgetStateProperty.all(const Color(0xFF1E293B)),
          columnSpacing: 20,
          columns: const [
            DataColumn(label: Text("DATE", style: TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold))),
            DataColumn(label: Text("TYPE", style: TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold))),
            DataColumn(label: Text("REF / INV #", style: TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold))),
            DataColumn(label: Text("DEBIT (₹)", style: TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold))),
            DataColumn(label: Text("CREDIT (₹)", style: TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold))),
            DataColumn(label: Text("RUNNING BALANCE", style: TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold))),
            DataColumn(label: Text("REMARKS", style: TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold))),
          ],
          rows: _ledgerEntries.map((row) {
            double debit = (row['debit'] as num?)?.toDouble() ?? 0.0;
            double credit = (row['credit'] as num?)?.toDouble() ?? 0.0;
            runningBal += (debit - credit);

            DateTime dt = row['date'] as DateTime;
            String dateStr = DateFormat('dd/MM/yyyy').format(dt);
            String type = row['type']?.toString() ?? "";
            String ref = (row['invoice'] ?? row['reference'] ?? "-").toString();
            String remarks = row['remarks']?.toString() ?? "-";

            return DataRow(
              cells: [
                DataCell(Text(dateStr, style: const TextStyle(color: Colors.white70, fontSize: 11))),
                DataCell(Text(type, style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold))),
                DataCell(Text(ref, style: const TextStyle(color: Colors.white, fontSize: 11))),
                DataCell(Text(debit > 0 ? debit.toStringAsFixed(2) : "-", style: const TextStyle(color: Colors.white70, fontSize: 11))),
                DataCell(Text(credit > 0 ? credit.toStringAsFixed(2) : "-", style: const TextStyle(color: Colors.tealAccent, fontSize: 11))),
                DataCell(
                  Text(
                    "₹${runningBal.abs().toStringAsFixed(2)} ${runningBal >= 0 ? 'Dr' : 'Cr'}",
                    style: TextStyle(
                      color: runningBal >= 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                DataCell(Text(remarks, style: const TextStyle(color: Colors.white54, fontSize: 10))),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
