import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/pharmacy_provider.dart';
import '../providers/app_provider.dart';
import '../services/server_config_service.dart';
import '../services/supplier_ledger_service.dart';
import '../services/sync_event_bus.dart';
import '../utils/search_debouncer.dart';
import '../utils/theme_constants.dart';

class SupplierLedgerScreen extends StatefulWidget {
  final String? initialSupplier;
  const SupplierLedgerScreen({super.key, this.initialSupplier});

  @override
  State<SupplierLedgerScreen> createState() => _SupplierLedgerScreenState();
}

class _SupplierLedgerScreenState extends State<SupplierLedgerScreen> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  String _supplierSearchQuery = "";
  String? _selectedSupplier;
  bool _isLedgerView = false;
  final ScrollController _ledgerScrollCtrl = ScrollController();
  final SearchDebouncer _searchDebouncer = SearchDebouncer(milliseconds: 150);

  List<_SupplierLedgerRowData> _ledgerData = [];
  bool _isLoadingLedger = false;
  int? _selectedIndex;
  int? _lastTapIndex;
  DateTime? _lastTapTime;

  int _gridStatusFilter = 0; // 0: All, 1: Due, 2: Settled

  String? _sortKey;
  bool _isAscending = true;

  Map<String, double> _balCache = {};
  Map<String, bool> _activeCache = {};
  List<String> _sortedSuppliers = [];
  StreamSubscription? _syncBusSub;

  @override
  void initState() {
    super.initState();
    if (widget.initialSupplier != null) {
      _selectedSupplier = widget.initialSupplier;
      _isLedgerView = true;
      _fetchLedgerData();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _recomputeSupplierCache());

    _syncBusSub = SyncEventBus.instance.stream.listen((event) {
      if (!mounted) return;
      final table = (event is TableChangedEvent) ? event.tableName : event.toString();
      if (table == 'suppliers' || table == 'purchase_entries' || table == 'purchase_items' || table == 'supplier_payments' || table == 'purchase_return_entries') {
        _recomputeSupplierCache();
        if (_selectedSupplier != null && _isLedgerView) {
          _fetchLedgerData();
        }
      }
    });
  }

  @override
  void dispose() {
    _syncBusSub?.cancel();
    _searchDebouncer.dispose();
    _ledgerScrollCtrl.dispose();
    super.dispose();
  }

  void _recomputeSupplierCache() {
    if (!mounted) return;
    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    final Map<String, double> bal = {
      for (var s in provider.supplierMaster) s.name: s.currentBalance
    };

    final Map<String, bool> active = {};
    for (var s in provider.suppliers) {
      active[s] = false;
    }
    for (var p in provider.purchases) {
      if (!p.isDeleted) active[p.supplierName] = true;
    }

    final list = List<String>.from(provider.suppliers);
    list.sort((a, b) {
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

  void _fetchLedgerData() async {
    if (_selectedSupplier == null || !mounted) return;
    setState(() => _isLoadingLedger = true);
    final data = await SupplierLedgerService.instance.fetchSupplierLedger(_selectedSupplier!);
    if (!mounted) return;
    setState(() {
      _ledgerData = data.map((m) => _SupplierLedgerRowData(
        date: m['date'],
        reference: m['reference'] ?? '',
        supInvNo: m['sup_inv_no'] ?? '',
        debit: (m['debit'] as num?)?.toDouble() ?? 0.0,
        credit: (m['credit'] as num?)?.toDouble() ?? 0.0,
        type: m['type'] ?? '',
        method: m['method'] ?? '',
        remarks: m['remarks'] ?? '',
      )).toList();
      _isLoadingLedger = false;
    });
    _scrollToBottom();
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
      _recomputeSupplierCache();
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
      title: Text("SUPPLIER & WHOLESALER ACCOUNTS", style: TextStyle(color: c.primaryText, fontWeight: FontWeight.bold, fontSize: 16)),
      actions: [
        _buildGridStatusFilter(c),
        const SizedBox(width: 20),
        Container(
          width: 250,
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: TextField(
            style: TextStyle(color: c.primaryText, fontSize: 12),
            decoration: InputDecoration(
              hintText: "Search Wholesaler / Supplier...",
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
        _statusChip(c, "DUE (PAYABLE)", 1, color: Colors.red.shade400),
        const SizedBox(width: 8),
        _statusChip(c, "SETTLED", 2, color: Colors.green.shade500),
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
          final bool isPayable = balance > 0;

          final Color boxColor = !active
              ? (c.isDark ? const Color(0xFF334155) : Colors.blueGrey.shade100)
              : (isPayable ? Colors.red.shade400 : Colors.green.shade500);

          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedSupplier = supplierName;
                  _isLedgerView = true;
                });
                _fetchLedgerData();
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
    if (_isLoadingLedger) {
      return Scaffold(backgroundColor: c.background, body: const Center(child: CircularProgressIndicator()));
    }

    final List<_SupplierLedgerRowData> ledgerData = _ledgerData;
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
              Builder(
                builder: (ctx) {
                  final startOfDay = DateTime(_startDate.year, _startDate.month, _startDate.day, 0, 0, 0);
                  final endOfDay = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);
                  double opDeb = 0.0;
                  double opCred = 0.0;
                  for (var r in ledgerData) {
                    if (r.date.isBefore(startOfDay)) {
                      opDeb += r.debit;
                      opCred += r.credit;
                    }
                  }
                  double opBal = opCred - opDeb; // For supplier: Credit is payable debt
                  List<_SupplierLedgerRowData> inRangeList = [];
                  if (opBal.abs() >= 0.01 || opDeb > 0 || opCred > 0) {
                    inRangeList.add(_SupplierLedgerRowData(
                      date: startOfDay,
                      reference: "OPENING B/F",
                      debit: opBal < 0 ? opBal.abs() : 0.0,
                      credit: opBal > 0 ? opBal : 0.0,
                      type: "OPENING",
                      isOpening: true,
                    ));
                  }
                  inRangeList.addAll(ledgerData.where((r) => !r.date.isBefore(startOfDay) && !r.date.isAfter(endOfDay)));
                  return _buildLedgerFooter(c, inRangeList);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLedgerSidebar(AppThemeColors c, PharmacyProvider provider) {
    final filtered = provider.suppliers
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
              itemCount: filtered.length,
              itemBuilder: (ctx, i) {
                final s = filtered[i];
                bool isSelected = _selectedSupplier == s;
                return ListTile(
                  title: Text(s, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? (c.isDark ? Colors.blueAccent : Colors.blue.shade800) : c.primaryText)),
                  selected: isSelected,
                  selectedTileColor: c.isDark ? Colors.blue.shade900.withValues(alpha: 0.3) : Colors.blue.shade50,
                  onTap: () {
                    setState(() => _selectedSupplier = s);
                    _fetchLedgerData();
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
            child: const Icon(Icons.storefront_outlined, color: Colors.blueAccent, size: 24),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text((_selectedSupplier ?? "UNKNOWN").toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.5, color: c.primaryText)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Supplier & Wholesaler Transaction Ledger", style: TextStyle(fontSize: 12, color: c.secondaryText, fontWeight: FontWeight.w500)),
                  _buildCloudStatusBadge(c),
                ],
              ),
            ],
          ),
          const Spacer(),
          _dateRangePicker(c),
          const SizedBox(width: 24),
          _actionButton("MAKE PAYMENT", Icons.payments_outlined, Colors.blue.shade800, onTap: () {
            Provider.of<AppProvider>(context, listen: false).openPayment();
          }),
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

  Widget _buildCloudStatusBadge(AppThemeColors c) {
    final isServer = ServerConfigService.instance.isServerModeEnabled;
    final isConnected = ServerConfigService.instance.isConnected;
    final bool isLive = isServer && isConnected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      margin: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: (isLive ? Colors.green : Colors.orange).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (isLive ? Colors.green : Colors.orange).withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isLive ? Icons.cloud_done : Icons.cloud_off, size: 12, color: isLive ? Colors.green : Colors.orange),
          const SizedBox(width: 4),
          Text(
            isLive ? "CLOUD LIVE" : "LOCAL STORE",
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isLive ? Colors.green : Colors.orange),
          ),
        ],
      ),
    );
  }

  Widget _dateRangePicker(AppThemeColors c) {
    return InkWell(
      onTap: () async {
        final DateTimeRange? picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
        );
        if (!mounted) return;
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
          _hCell("DATE", 'date', width: 100),
          _hCell("ENTRY NO / REF", 'entry', width: 140),
          _hCell("SUPP BILL NO", 'sup_inv', width: 130),
          _hCell("PURCHASE (CR)", 'credit', flex: 1, align: TextAlign.right),
          _hCell("PAID / RET (DR)", 'debit', flex: 1, align: TextAlign.right),
          _hCell("BALANCE DUE", 'balance', flex: 1, align: TextAlign.right),
          _hCell("TYPE", 'type', width: 110, align: TextAlign.center),
        ],
      ),
    );
  }

  Widget _hCell(String t, String key, {double? width, int? flex, TextAlign align = TextAlign.left}) {
    bool isSorted = _sortKey == key;
    Widget child = InkWell(
      onTap: () {
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
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: align == TextAlign.left ? Alignment.centerLeft : Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                t,
                style: TextStyle(
                  color: isSorted ? Colors.amberAccent : Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSorted) ...[
              const SizedBox(width: 2),
              Icon(
                _isAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 11,
                color: Colors.amberAccent,
              ),
            ],
          ],
        ),
      ),
    );
    if (width != null) return SizedBox(width: width, child: child);
    return Expanded(flex: flex ?? 1, child: child);
  }

  Widget _buildLedgerRows(AppThemeColors c, List<_SupplierLedgerRowData> originalData, PharmacyProvider provider) {
    List<_SupplierLedgerRowData> ledgerData = List.from(originalData);

    if (_sortKey != null) {
      ledgerData.sort((a, b) {
        int comp = 0;
        if (_sortKey == 'date') {
          comp = a.date.compareTo(b.date);
        } else if (_sortKey == 'entry') {
          comp = a.reference.toLowerCase().compareTo(b.reference.toLowerCase());
        } else if (_sortKey == 'sup_inv') {
          comp = a.supInvNo.toLowerCase().compareTo(b.supInvNo.toLowerCase());
        } else if (_sortKey == 'debit') {
          comp = a.debit.compareTo(b.debit);
        } else if (_sortKey == 'credit') {
          comp = a.credit.compareTo(b.credit);
        }
        return _isAscending ? comp : -comp;
      });
    }

    final startOfDay = DateTime(_startDate.year, _startDate.month, _startDate.day, 0, 0, 0);
    final endOfDay = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);

    double openingDebit = 0.0;
    double openingCredit = 0.0;
    for (var row in ledgerData) {
      if (row.date.isBefore(startOfDay)) {
        openingDebit += row.debit;
        openingCredit += row.credit;
      }
    }
    double openingBal = openingCredit - openingDebit; // Supplier balance: Credit is amount owed

    double runningBalance = 0;
    List<Widget> visibleRows = [];

    if (openingBal.abs() >= 0.01 || openingDebit > 0 || openingCredit > 0) {
      runningBalance = openingBal;
      final opRow = _SupplierLedgerRowData(
        date: startOfDay,
        reference: "OPENING B/F",
        supInvNo: "-",
        debit: openingBal < 0 ? openingBal.abs() : 0.0,
        credit: openingBal > 0 ? openingBal : 0.0,
        type: "OPENING",
        remarks: "Brought Forward Balance prior to ${DateFormat('dd/MM/yyyy').format(startOfDay)}",
        isOpening: true,
      );
      visibleRows.add(_buildGridRow(c, opRow, runningBalance, provider, openingBal > 0 ? Colors.redAccent : Colors.greenAccent, -1));
    }

    for (int i = 0; i < ledgerData.length; i++) {
      var row = ledgerData[i];
      if (row.date.isBefore(startOfDay)) continue;

      runningBalance += row.credit;
      runningBalance -= row.debit;

      bool inRange = !row.date.isAfter(endOfDay);
      if (inRange) {
        Color balColor = runningBalance > 0.01 ? Colors.redAccent : Colors.greenAccent;
        visibleRows.add(_buildGridRow(c, row, runningBalance, provider, balColor, i));
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

  Widget _buildGridRow(AppThemeColors c, _SupplierLedgerRowData data, double balance, PharmacyProvider provider, Color balColor, int index) {
    bool isSelected = index == _selectedIndex;
    String cleanBalance = balance.abs() < 0.01 ? "0.00" : balance.toStringAsFixed(2);

    return InkWell(
      onTap: () {
        final now = DateTime.now();
        setState(() => _selectedIndex = index);
        if (_lastTapIndex == index && _lastTapTime != null && now.difference(_lastTapTime!) < const Duration(milliseconds: 350)) {
          _lastTapTime = null;
          _lastTapIndex = null;
          if (data.type == 'PURCHASE') {
            Provider.of<AppProvider>(context, listen: false).openPurchase(entryNo: data.reference);
          } else if (data.type == 'PURCHASE RETURN') {
            Provider.of<AppProvider>(context, listen: false).openPurchaseReturn(entryNo: data.reference);
          }
        } else {
          _lastTapIndex = index;
          _lastTapTime = now;
        }
      },
      child: Container(
        height: 35,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFBAE6FD)
               : data.isOpening ? Colors.amber.withValues(alpha: 0.18)
               : data.type == 'PAYMENT' ? Colors.green.withValues(alpha: 0.12)
               : data.type == 'PURCHASE RETURN' ? Colors.orange.withValues(alpha: 0.12)
               : data.type == 'CREDIT NOTE' ? Colors.purple.withValues(alpha: 0.12)
               : c.cardBg,
          border: Border(bottom: BorderSide(color: isSelected ? Colors.blue.shade300 : c.border)),
        ),
        child: Row(
          children: [
            _cell(c, DateFormat('dd/MM/yy').format(data.date), width: 100),
            _cell(c, data.reference, width: 140, fontWeight: FontWeight.bold),
            _cell(c, data.supInvNo, width: 130, color: c.secondaryText, fontWeight: FontWeight.w500),
            _cell(c, data.credit > 0 ? data.credit.toStringAsFixed(2) : "", flex: 1, align: TextAlign.right),
            _cell(c, data.debit > 0 ? data.debit.toStringAsFixed(2) : "", flex: 1, align: TextAlign.right, fontWeight: FontWeight.bold),
            _cell(c, cleanBalance, flex: 1, align: TextAlign.right, color: balColor, fontWeight: FontWeight.bold),
            _cell(c, data.type, width: 110, align: TextAlign.center, color: c.secondaryText),
          ],
        ),
      ),
    );
  }

  Widget _buildLedgerFooter(AppThemeColors c, List<_SupplierLedgerRowData> ledgerData) {
    double totalDebit = 0;
    double totalCredit = 0;
    for (var r in ledgerData) {
      totalDebit += r.debit;
      totalCredit += r.credit;
    }
    double netBal = totalCredit - totalDebit;

    Widget footerCell(String text, {double? width, int? flex, TextAlign align = TextAlign.left}) {
      Widget cell = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: align == TextAlign.left ? Alignment.centerLeft : Alignment.centerRight,
        child: Text(
          text,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue),
          overflow: TextOverflow.ellipsis,
        ),
      );
      if (width != null) return SizedBox(width: width, child: cell);
      return Expanded(flex: flex ?? 1, child: cell);
    }

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EAF6),
        border: Border(top: BorderSide(color: Colors.grey.shade400, width: 1)),
      ),
      child: Row(
        children: [
          footerCell('TOTAL', width: 100),
          footerCell('${ledgerData.length} Entries', width: 140),
          footerCell('', width: 130),
          footerCell('₹${totalCredit.toStringAsFixed(2)}', flex: 1, align: TextAlign.right),
          footerCell('₹${totalDebit.toStringAsFixed(2)}', flex: 1, align: TextAlign.right),
          footerCell('₹${netBal.toStringAsFixed(2)}', flex: 1, align: TextAlign.right),
          footerCell('', width: 110),
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

class _SupplierLedgerRowData {
  final DateTime date;
  final String reference;
  final String supInvNo;
  final double debit;
  final double credit;
  final String type;
  final String remarks;
  final String method;
  final bool isOpening;

  _SupplierLedgerRowData({
    required this.date,
    required this.reference,
    this.supInvNo = "",
    required this.debit,
    required this.credit,
    required this.type,
    this.remarks = "",
    this.method = "",
    this.isOpening = false,
  });
}
