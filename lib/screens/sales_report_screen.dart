import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as ex;
import '../providers/pharmacy_provider.dart';
import '../providers/app_provider.dart';
import '../services/app_notification_service.dart';
import '../widgets/app_date_picker.dart';
import 'package:intl/intl.dart';
import '../widgets/pin_unlock_dialog.dart';
import '../widgets/erp_tooltip.dart';
import '../utils/report_pdf_generator.dart';
import '../utils/printer_service.dart';
import '../utils/theme_constants.dart';
import '../utils/app_formatters.dart';
import '../widgets/server_discrepancy_dialog.dart';
import '../services/server_config_service.dart';
import '../services/supabase_sync_service.dart';

class SalesReportScreen extends StatefulWidget {
  const SalesReportScreen({super.key});

  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

enum ReportType { detailed, productVs, summary, productVsSummary, accounts }
enum AggregationType { sum, min, max, count, average, none }
enum ColumnType { text, numeric, date }

class _ColInfo {
  final String key;
  final String label;
  double width;
  final double flex;
  final TextAlign align;
  final ColumnType type;
  _ColInfo(this.key, this.label, {double? width, this.flex = 1, this.align = TextAlign.left, this.type = ColumnType.text})
      : width = width ?? (flex * 70);
}

class _SalesReportScreenState extends State<SalesReportScreen> {
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  ReportType _reportType = ReportType.detailed;
  double _headerHeight = 52.0;

  // Sorting state
  String? _sortColumnKey;
  bool _isAscending = true;

  // Stores advanced filter rules per column
  final Map<String, Map<String, dynamic>> _activeFilters = {};
  final Map<String, AggregationType> _columnAggregations = {};
  bool _hideDeletedEntries = false;

  List<dynamic> _masterData = [];
  List<dynamic> _displayData = [];
  List<_ColInfo>? _cachedCols;

  // Row selection & double-tap variables
  int? _selectedIndex;
  DateTime? _lastTapTime;
  int? _lastTapIndex;

  // Pagination Variables
  bool _hasMore = true;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  int _currentOffset = 0;
  static const int _pageSize = 100;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();

  StreamSubscription<AppNotification>? _watchdogSub;
  Timer? _watchdogDebounceTimer;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, now.day);
    _cachedCols = _getColumns();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());

    _watchdogSub = AppNotificationService.instance.watchdogStream.listen((notif) {
      if (!mounted) return;
      final cat = notif.detectedCategory;
      if (cat == 'SALES' || cat == 'RETURNS') {
        _watchdogDebounceTimer?.cancel();
        _watchdogDebounceTimer = Timer(const Duration(milliseconds: 500), () {
          if (mounted) _search();
        });
      }
    });
  }

  @override
  void dispose() {
    _watchdogDebounceTimer?.cancel();
    _watchdogSub?.cancel();
    _scrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoading || _isLoadingMore) return;
    if (_reportType != ReportType.detailed && _reportType != ReportType.productVs) return;

    if (_scrollController.hasClients &&
        _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMoreData();
    }
  }

  Future<void> _loadMoreData() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final provider = Provider.of<PharmacyProvider>(context, listen: false);
      final moreSales = await provider.fetchSalesInDateRange(
        _from,
        _to,
        loadItems: true,
        limit: _pageSize,
        offset: _currentOffset,
        includeDeleted: true,
      );

      final newRows = _processData(moreSales);
      if (!mounted) return;

      setState(() {
        if (newRows.isEmpty || newRows.length < _pageSize) {
          _hasMore = false;
        } else {
          _hasMore = true;
        }
        _currentOffset += newRows.length;
        _masterData.addAll(newRows);
        _isLoadingMore = false;
        _applyFilters(notify: true);
      });
    } catch (e) {
      debugPrint("Sales Load More Error: $e");
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _search() async {
    if (!mounted) return;
    setState(() {
      _masterData = [];
      _displayData = [];
      _currentOffset = 0;
      _hasMore = false;
      _isLoading = true;
    });

    try {
      final provider = Provider.of<PharmacyProvider>(context, listen: false);

      // Non-blocking background cloud check: displays local data immediately (<50ms)
      if (ServerConfigService.instance.isServerModeEnabled && ServerConfigService.instance.isConnected) {
        unawaited(
          SupabaseSyncService.instance.refreshDateRangeTransactionsCloudDirect(_from, _to, pharmacy: provider).then((synced) {
            if (synced && mounted) {
              _loadLocalData(provider, silent: true);
            }
          }).catchError((e) {
            debugPrint("Non-blocking background sync error: $e");
          }),
        );
      }

      await _loadLocalData(provider, silent: false);
    } catch (e) {
      debugPrint("Sales Search Error: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasMore = false;
        });
      }
    }
  }

  Future<void> _loadLocalData(PharmacyProvider provider, {bool silent = false}) async {
    if (!silent) {
      if (!mounted) return;
      setState(() => _isLoading = true);
    }
    try {
      List<dynamic> processedData;
      if (_reportType == ReportType.summary) {
        processedData = await provider.fetchDailySalesSummary(_from, _to, includeDeleted: true);
        _hasMore = false;
      } else if (_reportType == ReportType.accounts) {
        processedData = await provider.fetchAccountsSalesSummary(_from, _to, includeDeleted: true);
        _hasMore = false;
      } else if (_reportType == ReportType.productVsSummary) {
        processedData = await provider.fetchProductSalesSummary(_from, _to, includeDeleted: true);
        _hasMore = false;
      } else {
        _currentOffset = 0;
        final filteredSales = await provider.fetchSalesInDateRange(
          _from, 
          _to, 
          loadItems: true, 
          limit: _pageSize, 
          offset: 0, 
          includeDeleted: true,
        );
        processedData = _processData(filteredSales);
        _currentOffset = processedData.length;
        _hasMore = processedData.length >= _pageSize;
      }

      if (!mounted) return;
      setState(() {
        _masterData = processedData;
        _isLoading = false;
        _applyFilters(notify: false); // Update _displayData with loaded rows
      });
    } catch (e) {
      debugPrint("Sales Local Load Error: $e");
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _hasMore = false;
        });
      }
    }
  }



  DateTime? _parseFlexibleDate(String dateStr) {
    if (dateStr.isEmpty) return null;
    try {
      // Expiry format MM/YY
      if (dateStr.contains('/') && dateStr.length == 5) {
        final parts = dateStr.split('/');
        int m = int.parse(parts[0]);
        int y = 2000 + int.parse(parts[1]);
        return DateTime(y, m, 1);
      }
      // Standard Format dd/MM/yyyy
      return DateFormat('dd/MM/yyyy').parse(dateStr);
    } catch (e) {
      return null;
    }
  }

  void _applyFilters({bool notify = true}) {
    _selectedIndex = null;
    List<dynamic> filtered;
    if (_activeFilters.isEmpty) {
      filtered = List.from(_masterData);
    } else {
      filtered = _masterData.where((row) {
        bool match = true;
        _activeFilters.forEach((colKey, filter) {
          if (!match) return;

          if (filter['mode'] == 'values') {
            List<String> allowed = List<String>.from(filter['selected_values']);
            String cellVal = row[colKey]?.toString() ?? "";
            if (!allowed.contains(cellVal)) match = false;
            return;
          }

          String condition = filter['condition'];
          if (condition == 'Clear' || condition == 'None') return;

          final val = row[colKey];

          if (filter['type'] == ColumnType.text) {
            String cellStr = val?.toString().toLowerCase() ?? "";
            String filterStr = filter['value1']?.toString().toLowerCase() ?? "";

            if (condition == 'Equals' && cellStr != filterStr) {
              match = false;
            } else if (condition == 'Does Not Equal' && cellStr == filterStr) match = false;
            else if (condition == 'Contains' && !cellStr.contains(filterStr)) match = false;
            else if (condition == 'Does Not Contain' && cellStr.contains(filterStr)) match = false;
            else if (condition == 'Begins With' && !cellStr.startsWith(filterStr)) match = false;
            else if (condition == 'Ends With' && !cellStr.endsWith(filterStr)) match = false;
          }
          else if (filter['type'] == ColumnType.numeric) {
            double cellNum = double.tryParse(val?.toString() ?? "0") ?? 0.0;
            double v1 = double.tryParse(filter['value1']?.toString() ?? "0") ?? 0.0;

            if (condition == 'Between') {
              double v2 = double.tryParse(filter['value2']?.toString() ?? "0") ?? 0.0;
              if (cellNum < v1 || cellNum > v2) match = false;
            } else {
              if (condition == 'Equals' && cellNum != v1) {
                match = false;
              } else if (condition == 'Does Not Equal' && cellNum == v1) match = false;
              else if (condition == 'Greater Than' && cellNum <= v1) match = false;
              else if (condition == 'Less Than' && cellNum >= v1) match = false;
            }
          }
          else if (filter['type'] == ColumnType.date) {
            DateTime? cellDate = (colKey == 'date' && row['raw_date'] != null)
                ? row['raw_date']
                : _parseFlexibleDate(val?.toString() ?? "");

            if (cellDate == null) {
              match = false;
              return;
            }

            DateTime? d1 = _parseFlexibleDate(filter['value1']?.toString() ?? "");
            if (d1 == null) return;

            cellDate = DateTime(cellDate.year, cellDate.month, cellDate.day);
            d1 = DateTime(d1.year, d1.month, d1.day);

            if (condition == 'Between') {
              DateTime? d2 = _parseFlexibleDate(filter['value2']?.toString() ?? "");
              if (d2 == null) return;
              d2 = DateTime(d2.year, d2.month, d2.day);
              if (cellDate.isBefore(d1) || cellDate.isAfter(d2)) match = false;
            } else {
              if (condition == 'Equals' && !cellDate.isAtSameMomentAs(d1)) {
                match = false;
              } else if (condition == 'Before' && !cellDate.isBefore(d1)) match = false;
              else if (condition == 'After' && !cellDate.isAfter(d1)) match = false;
            }
          }
        });
        return match;
      }).toList();
    }

    if (_hideDeletedEntries) {
      filtered = filtered.where((row) => row['status'] != 'DELETED ENTRY').toList();
    }

    // Apply Column Header Sorting (A-Z / Z-A for Text/Date, 0-9 / 9-0 for Numbers)
    if (_sortColumnKey != null) {
      final colDef = _getColumns().firstWhere((c) => c.key == _sortColumnKey, orElse: () => _getColumns().first);
      final isNum = colDef.type == ColumnType.numeric;
      final isDate = colDef.type == ColumnType.date;

      filtered.sort((a, b) {
        dynamic valA = a[_sortColumnKey];
        dynamic valB = b[_sortColumnKey];

        int comp = 0;
        if (isNum) {
          double numA = (valA is num) ? valA.toDouble() : (double.tryParse(formatSaleDisplayNo(valA?.toString() ?? '')) ?? 0.0);
          double numB = (valB is num) ? valB.toDouble() : (double.tryParse(formatSaleDisplayNo(valB?.toString() ?? '')) ?? 0.0);
          comp = numA.compareTo(numB);
        } else if (isDate) {
          DateTime? dateA = (a['raw_date'] is DateTime && _sortColumnKey == 'date') ? a['raw_date'] : _parseFlexibleDate(valA?.toString() ?? '');
          DateTime? dateB = (b['raw_date'] is DateTime && _sortColumnKey == 'date') ? b['raw_date'] : _parseFlexibleDate(valB?.toString() ?? '');
          if (dateA == null && dateB == null) {
            comp = 0;
          } else if (dateA == null) comp = -1;
          else if (dateB == null) comp = 1;
          else comp = dateA.compareTo(dateB);
        } else {
          String strA = valA?.toString().toLowerCase() ?? '';
          String strB = valB?.toString().toLowerCase() ?? '';
          comp = strA.compareTo(strB);
        }
        return _isAscending ? comp : -comp;
      });
    }

    if (notify) {
      setState(() => _displayData = filtered);
    } else {
      _displayData = filtered;
    }
  }

  void _onColumnHeaderTap(String key) {
    setState(() {
      if (_sortColumnKey == key) {
        if (_isAscending) {
          _isAscending = false;
        } else {
          _sortColumnKey = null;
          _isAscending = true;
        }
      } else {
        _sortColumnKey = key;
        _isAscending = true;
      }
      _applyFilters();
    });
  }

  void _showSettlementDialog(String entryNo) {
    String selectedMode = "Cash";
    final TextEditingController remarksCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text("Settle Credit Sale #$entryNo"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Select Payment Account:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: selectedMode,
                isExpanded: true,
                items: ["Cash", "Card", "UPI", "Bank"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) => setDialogState(() => selectedMode = v!),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: remarksCtrl,
                decoration: const InputDecoration(
                  labelText: "Remarks",
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () async {
                final p = Provider.of<PharmacyProvider>(context, listen: false);
                Navigator.pop(ctx);
                await p.settleSalePayment(entryNo, selectedMode, remarksCtrl.text);
                _search();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade800, foregroundColor: Colors.white),
              child: const Text("Settle Payment"),
            ),
          ],
        ),
      ),
    );
  }

  List<dynamic> _processData(List<SaleInvoice> inputSales) {
    // Filter out Special Orders as they belong in the Order Book, not Sales Analysis
    final sales = inputSales.where((s) => s.customerAcc != "Special Order").toList();

    // Sort sales by numerical Entry No descending (greatest entry number on top, lowest on bottom)
    sales.sort((a, b) {
      int numA = int.tryParse(formatSaleDisplayNo(a.entryNo)) ?? 0;
      int numB = int.tryParse(formatSaleDisplayNo(b.entryNo)) ?? 0;
      if (numA != numB) {
        return numB.compareTo(numA);
      }
      return b.date.compareTo(a.date);
    });

    switch (_reportType) {
      case ReportType.detailed:
        return sales.map((s) {
          double totalItemDiscounts = s.items.fold(0.0, (sum, item) => sum + item.discAmt);
          double totalGst = s.items.fold(0.0, (sum, item) => sum + item.gstAmt);

          // Deduct GST from item.total to establish true taxable turnover
          double taxableBase = s.items.fold(0.0, (sum, item) {
            double base = item.total - item.gstAmt;
            return sum + (base > 0 ? base : 0.0);
          });
          double profit = s.items.fold(0.0, (sum, item) => sum + item.profit);
          
          // ADJUSTMENT: Proportional Footer Discount / Return Adjustment
          double netTaxable = taxableBase;
          double netGst = totalGst;
          double preAdjustTotal = taxableBase + totalGst;
          if (preAdjustTotal > 0 && (s.discount > 0 || s.salesReturn > 0)) {
            double ratio = (s.grandTotal - s.roundOff) / preAdjustTotal;
            netTaxable = taxableBase * ratio;
            netGst = totalGst * ratio;
          }

          double totalDiscount = totalItemDiscounts + s.discount;
          double grossMRP = netTaxable + totalDiscount;

          // LCWT = Taxable Base - Profit (Since profit is strictly exclusive of GST now)
          double lcwt = netTaxable - profit;

          String pcIdentity = "PC 1";
          final String canonicalKey = s.entryNo.toUpperCase();
          if (canonicalKey.startsWith("T1-")) {
            pcIdentity = "PC 1";
          } else if (canonicalKey.startsWith("T2-")) {
            pcIdentity = "PC 2";
          } else if (canonicalKey.startsWith("T3-")) {
            pcIdentity = "PC 3";
          } else if (canonicalKey.contains("_")) {
            final prefix = canonicalKey.substring(0, canonicalKey.indexOf("_")).trim();
            if (prefix.isNotEmpty) pcIdentity = prefix;
          }
          final String agentName = s.agent.trim();
          if (agentName.isNotEmpty && agentName.toLowerCase() != "admin") {
            pcIdentity = "$pcIdentity ($agentName)";
          } else if (agentName.isNotEmpty) {
            pcIdentity = "$pcIdentity (Admin)";
          }

          return {
            'date': DateFormat('dd/MM/yyyy').format(s.date),
            'raw_date': s.date,
            'time': DateFormat('hh:mm a').format(s.date),
            'entry_no': formatSaleDisplayNo(s.entryNo),
            'raw_entry_no': s.entryNo,
            'customer': s.customerAcc,
            'mobile': s.mobile,
            'patient': s.patient,
            'doctor': s.doctor,
            'agent': s.agent.isEmpty ? "Admin" : s.agent,
            'computer': pcIdentity,
            'tax': s.taxType,
            'is_tax': s.taxType == 'Gst' ? 'Yes' : 'No',
            'gross': grossMRP, // MRP sum before discount (Gross - Discount = Net)
            'discount': totalDiscount, // Total of all discounts
            'net': netTaxable, // Net amount after discount given to customer
            'gst': netGst,
            'total': netTaxable + netGst, // Pre-return total
            'other_disc': s.discount, // Footer discount
            'other_cha': s.salesReturn, // Dedicated Sales Return field
            'round_off': s.roundOff,
            'grand_total': s.grandTotal, // Final amount customer paid
            'lcwt': lcwt,
            'profit': profit,
            'is_paid': s.isPaid,
            'status': s.isDeleted ? 'DELETED ENTRY' : 'Active'
          };
        }).toList();

      case ReportType.productVs:
        List<Map<String, dynamic>> items = [];
        for (var s in sales) {
          String pcIdentity = "PC 1";
          final String canonicalKey = s.entryNo.toUpperCase();
          if (canonicalKey.startsWith("T1-")) {
            pcIdentity = "PC 1";
          } else if (canonicalKey.startsWith("T2-")) {
            pcIdentity = "PC 2";
          } else if (canonicalKey.startsWith("T3-")) {
            pcIdentity = "PC 3";
          } else if (canonicalKey.contains("_")) {
            final prefix = canonicalKey.substring(0, canonicalKey.indexOf("_")).trim();
            if (prefix.isNotEmpty) pcIdentity = prefix;
          }
          final String agentName = s.agent.trim();
          if (agentName.isNotEmpty && agentName.toLowerCase() != "admin") {
            pcIdentity = "$pcIdentity ($agentName)";
          } else if (agentName.isNotEmpty) {
            pcIdentity = "$pcIdentity (Admin)";
          }

          for (var item in s.items) {
            items.add({
              'date': DateFormat('dd/MM/yyyy').format(s.date),
              'time': DateFormat('hh:mm a').format(s.date),
              'entry_no': formatSaleDisplayNo(s.entryNo),
              'raw_entry_no': s.entryNo,
              'customer': s.customerAcc,
              'mobile': s.mobile,
              'patient': s.patient,
              'doctor': s.doctor,
              'agent': s.agent.isEmpty ? "Admin" : s.agent,
              'computer': pcIdentity,
              'product': item.product.name,
              'category': item.product.category,
              'sub_category': item.product.subCategory,
              'patent_name': item.product.manufacturer,
              'hsncode': item.product.hsnCode,
              'qty': item.qty,
              'packing': item.packin,
              'batch': item.product.batch,
              'expiry': item.product.expiry,
              'mrp': item.mrp,
              'total': item.total,
              'profit': item.profit,
              'status': s.isDeleted ? 'DELETED ENTRY' : 'Active',
            });
          }
        }
        return items;

      case ReportType.summary:
        Map<String, Map<String, dynamic>> daily = {};
        for (var s in sales) {
          String day = DateFormat('dd/MM/yyyy').format(s.date);
          String status = s.isDeleted ? 'DELETED ENTRY' : 'Active';
          String key = "${day}_$status"; 

          double dayProfit = s.items.fold(0.0, (sum, item) => sum + item.profit);
          double dayGst = s.items.fold(0.0, (sum, item) => sum + item.gstAmt);
          // Deduct GST from item.total to establish true taxable turnover
          double taxableBase = s.items.fold(0.0, (sum, item) {
            double base = item.total - item.gstAmt;
            return sum + (base > 0 ? base : 0.0);
          });

          daily.putIfAbsent(key, () => {
            'date': day, 'net': 0.0, 'gst': 0.0, 'total': 0.0,
            'other_discount': 0.0, 'other_charges': 0.0, 'round_off': 0.0,
            'grand_total': 0.0, 'profit': 0.0,
            'status': status, 
            'from_date': DateFormat('dd/MM/yyyy').format(_from),
            'to_date': DateFormat('dd/MM/yyyy').format(_to),
          });

          daily[key]!['net'] += taxableBase; // Net must be Taxable Base for CA
          daily[key]!['gst'] += dayGst;
          daily[key]!['total'] += (taxableBase + dayGst);
          daily[key]!['other_discount'] += s.discount; // Footer discount
          daily[key]!['other_charges'] += s.salesReturn; // Sales Return
          daily[key]!['round_off'] += s.roundOff;
          daily[key]!['grand_total'] += s.grandTotal;
          daily[key]!['profit'] += dayProfit;
        }
        return daily.values.toList()..sort((a,b) => b['date'].compareTo(a['date']));

      case ReportType.productVsSummary:
        Map<String, Map<String, dynamic>> prodSum = {};
        for (var s in sales) {
          String status = s.isDeleted ? 'DELETED ENTRY' : 'Active';
          for (var item in s.items) {
            String pName = item.product.name;
            String key = "${pName}_$status"; 

            prodSum.putIfAbsent(key, () => {
              'product': pName, 'qty': 0.0, 'mrp': item.mrp, 'mrp_value': 0.0,
              'disc_amt_piece': item.discAmt / (item.qty == 0 ? 1 : item.qty),
              'disc_amt': 0.0, 'lcwt': 0.0, 'total': 0.0, 'profit': 0.0,
              'status': status, 
            });
            prodSum[key]!['qty'] += item.qty;
            prodSum[key]!['mrp_value'] += (item.mrp * item.qty);
            prodSum[key]!['disc_amt'] += item.discAmt;
            
            // CODE MASTER FIX: Historical lock for Product Summary
            prodSum[key]!['lcwt'] += ((item.total + item.gstAmt) - item.profit);
            
            prodSum[key]!['total'] += item.total;
            prodSum[key]!['profit'] += item.profit;
          }
        }
        return prodSum.values.toList()..sort((a,b) => b['total'].compareTo(a['total']));

      case ReportType.accounts:
        Map<String, Map<String, dynamic>> accSum = {};
        for (var s in sales) {
          String acc = s.customerAcc;
          String status = s.isDeleted ? 'DELETED ENTRY' : 'Active';
          String key = "${acc}_$status";

          double dayProfit = s.items.fold(0.0, (sum, item) => sum + item.profit);
          double dayGst = s.items.fold(0.0, (sum, item) => sum + item.gstAmt);
          // Deduct GST from item.total to establish true taxable turnover
          double taxableBase = s.items.fold(0.0, (sum, item) {
            double base = item.total - item.gstAmt;
            return sum + (base > 0 ? base : 0.0);
          });

          accSum.putIfAbsent(key, () => {
            'account': acc, 'net': 0.0, 'gst': 0.0, 'total': 0.0,
            'other_discount': 0.0, 'other_charges': 0.0, 'round_off': 0.0,
            'grand_total': 0.0, 'profit': 0.0,
            'status': status,
          });

          accSum[key]!['net'] += taxableBase;
          accSum[key]!['gst'] += dayGst;
          accSum[key]!['total'] += (taxableBase + dayGst);
          accSum[key]!['other_discount'] += s.discount;
          accSum[key]!['other_charges'] += s.salesReturn;
          accSum[key]!['round_off'] += s.roundOff;
          accSum[key]!['grand_total'] += s.grandTotal;
          accSum[key]!['profit'] += dayProfit;
        }
        return accSum.values.toList()..sort((a,b) => b['grand_total'].compareTo(a['grand_total']));
    }
  }

  List<_ColInfo> _getColumns() {
    switch (_reportType) {
      case ReportType.detailed:
        return [
          _ColInfo("date", "Date", flex: 1.1, type: ColumnType.date),
          _ColInfo("time", "Time", flex: 0.9),
          _ColInfo("entry_no", "Entry No", flex: 1.0, type: ColumnType.numeric),
          _ColInfo("customer", "Customer", flex: 1.4),
          _ColInfo("mobile", "Mobile", flex: 1.1),
          _ColInfo("patient", "Patient", flex: 1.1),
          _ColInfo("doctor", "Doctor", flex: 1.1),
          _ColInfo("agent", "Agent", flex: 1.1),
          _ColInfo("computer", "Saved/Edited By (PC)", flex: 1.3),
          _ColInfo("tax", "Tax", flex: 1.0),
          _ColInfo("gross", "Gross", flex: 1.0, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("discount", "Discount", flex: 1.0, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("net", "Net", flex: 1.0, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("gst", "Gst", flex: 1.0, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("total", "Total", flex: 1.0, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("grand_total", "Grand Total", flex: 1.2, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("profit", "Profit", flex: 1.0, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("actions", "Actions", flex: 0.9),
          _ColInfo("status", "Status", flex: 1.0),
        ];
      case ReportType.productVs:
        return [
          _ColInfo("date", "Date", flex: 1.1, type: ColumnType.date),
          _ColInfo("time", "Time", flex: 0.9),
          _ColInfo("entry_no", "Entry No", flex: 1.0, type: ColumnType.numeric),
          _ColInfo("customer", "Customer", flex: 1.4),
          _ColInfo("mobile", "Mobile", flex: 1.1),
          _ColInfo("patient", "Patient", flex: 1.1),
          _ColInfo("doctor", "Doctor", flex: 1.1),
          _ColInfo("agent", "Agent", flex: 1.1),
          _ColInfo("computer", "Saved/Edited By (PC)", flex: 1.3),
          _ColInfo("product", "Product", flex: 2.2),
          _ColInfo("category", "Category", flex: 1.3),
          _ColInfo("patent_name", "Patent name", flex: 1.3),
          _ColInfo("hsncode", "hsncode", flex: 1.0),
          _ColInfo("qty", "Qty", flex: 0.8, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("batch", "batch", flex: 1.1),
          _ColInfo("expiry", "expiry", flex: 1.1, type: ColumnType.date),
          _ColInfo("mrp", "mrp", flex: 1.1, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("total", "total", flex: 1.1, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("profit", "Profit", flex: 1.1, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("status", "Status", flex: 1.0),
        ];
      case ReportType.summary:
        return [
          _ColInfo("date", "Date", flex: 1.2, type: ColumnType.date),
          _ColInfo("net", "Net", flex: 1.2, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("gst", "Gst", flex: 1.2, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("total", "Total", flex: 1.2, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("other_discount", "Other Discount", flex: 1.2, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("other_charges", "Other Charges", flex: 1.2, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("round_off", "Round Off", flex: 1.2, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("grand_total", "Grand Total", flex: 1.2, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("profit", "Profit", flex: 1.2, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("status", "Status", flex: 1.2),
        ];
      case ReportType.productVsSummary:
        return [
          _ColInfo("product", "Product", flex: 3.0),
          _ColInfo("qty", "Qty", flex: 1.0, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("mrp", "MRP", flex: 1.0, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("mrp_value", "MRP Value", flex: 1.3, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("disc_amt", "Disc Amt", flex: 1.3, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("lcwt", "LCWT", flex: 1.3, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("total", "Total", flex: 1.3, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("profit", "Profit", flex: 1.3, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("status", "Status", flex: 1.3),
        ];
      case ReportType.accounts:
        return [
          _ColInfo("account", "Account", flex: 1.5),
          _ColInfo("net", "Net", flex: 1.2, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("gst", "Gst", flex: 1.2, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("total", "Total", flex: 1.2, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("other_discount", "Other Discount", flex: 1.2, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("other_charges", "Other Charges", flex: 1.2, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("round_off", "Round Off", flex: 1.2, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("grand_total", "Grand Total", flex: 1.2, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("profit", "Profit", flex: 1.2, align: TextAlign.right, type: ColumnType.numeric),
          _ColInfo("status", "Status", flex: 1.2),
        ];
    }
  }

  void _openAdvancedFilterDialog(_ColInfo col, Offset position) async {
    List<String> uniqueVals = _masterData.map((row) => row[col.key]?.toString() ?? "").toSet().toList();
    uniqueVals.sort();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => Stack(
        children: [
          Positioned(
            top: position.dy + 10,
            left: (position.dx - 100).clamp(0, MediaQuery.of(context).size.width - 250),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(4),
              child: _AdvancedFilterPopup(
                columnName: col.label,
                columnType: col.type,
                uniqueValues: uniqueVals,
                initialFilter: _activeFilters[col.key],
              ),
            ),
          )
        ],
      ),
    );

    if (result != null) {
      if (result['condition'] == 'Clear') {
        _activeFilters.remove(col.key);
      } else {
        _activeFilters[col.key] = result;
      }
      _applyFilters();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSidebar(c),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildReportHeader(),
                Expanded(
                  child: Container(
                    color: c.background,
                    child: _buildDataGrid(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(AppThemeColors c) {
    final now = DateTime.now();
    return Container(
      width: 250,
      color: c.cardBg,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _datePicker("From", _from, (d) { setState(() => _from = d); _search(); })),
              const SizedBox(width: 8),
              Expanded(child: _datePicker("To", _to, (d) { setState(() => _to = d); _search(); })),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _from = DateTime(now.year, now.month, 1);
                      _to = DateTime(now.year, now.month + 1, 0);
                    });
                    _search();
                  },
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  child: const Text("This Month", style: TextStyle(fontSize: 9)),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _from = DateTime(now.month >= 4 ? now.year : now.year - 1, 4, 1);
                      _to = DateTime(now.month >= 4 ? now.year + 1 : now.year, 3, 31);
                    });
                    _search();
                  },
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  child: const Text("FY", style: TextStyle(fontSize: 9)),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _from = DateTime(2000, 1, 1);
                      _to = DateTime(2100, 12, 31);
                    });
                    _search();
                  },
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  child: const Text("All Time", style: TextStyle(fontSize: 9)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _reportTypeRadio(ReportType.detailed, "Detailed"),
              _reportTypeRadio(ReportType.summary, "Summary"),
              _reportTypeRadio(ReportType.productVs, "Product v/s"),
              _reportTypeRadio(ReportType.productVsSummary, "Product v/s Summary"),
              _reportTypeRadio(ReportType.accounts, "Accounts"),
            ],
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () {
              setState(() {
                _hideDeletedEntries = !_hideDeletedEntries;
                _applyFilters();
              });
            },
            child: Row(
              children: [
                Checkbox(
                  value: _hideDeletedEntries,
                  onChanged: (v) {
                    setState(() {
                      _hideDeletedEntries = v ?? false;
                      _applyFilters();
                    });
                  },
                  visualDensity: VisualDensity.compact,
                ),
                const Expanded(
                  child: Text(
                    "Hide Deleted",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(child: _sideActionBtn("Export", Icons.exit_to_app, onPressed: _exportExcel)),
              const SizedBox(width: 4),
              Expanded(child: _sideActionBtn("Print", Icons.print, onPressed: _printReport)),
              const SizedBox(width: 4),
              Expanded(child: _sideActionBtn("Audit", Icons.youtube_searched_for_rounded, onPressed: () {
                ServerDiscrepancyDialog.show(context, initialCategoryKey: 'sales_invoices');
              })),
            ],
          )
        ],
      ),
    );
  }

  void _exportExcel() async {
    if (_displayData.isEmpty) return;
    String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Save Sales Report Excel',
      fileName: 'Sales_Report_${_reportType.name}_${DateFormat('ddMMyyyy').format(_from)}.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (outputFile != null) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(strokeWidth: 3),
                  SizedBox(width: 16),
                  Text("Exporting Sales Report to Excel...", style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
      );

      try {
        final provider = Provider.of<PharmacyProvider>(context, listen: false);
        List<dynamic> exportRows;
        if (_hasMore && (_reportType == ReportType.detailed || _reportType == ReportType.productVs)) {
          final allSales = await provider.fetchSalesInDateRange(
            _from,
            _to,
            loadItems: true,
            limit: null,
            offset: null,
            includeDeleted: true,
          );
          exportRows = _processData(allSales);
        } else {
          exportRows = _displayData;
        }

        final excel = ex.Excel.createExcel();
        final sheet = excel['Sales Report'];
        excel.delete('Sheet1');

        final columns = _getColumns().where((c) => c.key != "actions").toList();
        sheet.appendRow(columns.map((c) => ex.TextCellValue(c.label)).toList());

        for (var row in exportRows) {
          sheet.appendRow(columns.map((col) {
            final val = row[col.key];
            if (val is double) return ex.DoubleCellValue(val);
            if (val is int) return ex.IntCellValue(val);
            return ex.TextCellValue(val?.toString() ?? '');
          }).toList());
        }

        final bytes = excel.encode();
        if (bytes != null) {
          await File(outputFile).writeAsBytes(bytes);
        }

        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Sales Report Exported to Excel!"), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Excel Export Error: $e"), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Widget _datePicker(String label, DateTime date, Function(DateTime) onPick) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        InkWell(
          onTap: () async {
            final picked = await showAppDatePicker(context: context, initialDate: date, firstDate: DateTime(2000), lastDate: DateTime(2100));
            if (picked != null) {
              if (label == "From") {
                if (picked.isAfter(_to)) {
                  setState(() => _to = picked);
                }
              } else {
                if (picked.isBefore(_from)) {
                  setState(() => _from = picked);
                }
              }
              onPick(picked);
            }
          },
          child: Container(
            height: 25,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey), color: Colors.white),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(DateFormat('dd/MM/yyyy').format(date), style: const TextStyle(fontSize: 10)),
                const Icon(Icons.arrow_drop_down, size: 14),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _reportTypeRadio(ReportType type, String label) {
    return SizedBox(
      height: 28,
      child: InkWell(
        onTap: () {
          setState(() {
            _reportType = type;
            _cachedCols = null; // Force header refresh
            _activeFilters.clear();
            _columnAggregations.clear();
          });
          _search();
        },
        child: RadioGroup<ReportType>(
          groupValue: _reportType,
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _reportType = v;
                _cachedCols = null;
                _activeFilters.clear();
                _columnAggregations.clear();
              });
              _search();
            }
          },
          child: Row(
            children: [
              Radio<ReportType>(
                value: type,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sideActionBtn(String label, IconData icon, {required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 10)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }

  void _printReport() async {
    if (_displayData.isEmpty) return;
    final pharma = Provider.of<PharmacyProvider>(context, listen: false);

    bool shouldShowDialog = _hasMore && (_reportType == ReportType.detailed || _reportType == ReportType.productVs);
    if (shouldShowDialog) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(strokeWidth: 3),
                  SizedBox(width: 16),
                  Text("Preparing Complete Report for Print...", style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    try {
      List<dynamic> printRows;
      if (_hasMore && (_reportType == ReportType.detailed || _reportType == ReportType.productVs)) {
        final allSales = await pharma.fetchSalesInDateRange(
          _from,
          _to,
          loadItems: true,
          limit: null,
          offset: null,
          includeDeleted: true,
        );
        printRows = _processData(allSales);
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
      } else {
        printRows = _displayData;
      }

      final columns = _getColumns().where((c) => c.key != "actions").toList();
      final headers = columns.map((c) => c.label).toList();
      final data = printRows.map((row) {
        return columns.map((col) {
          final val = row[col.key];
          if (val == null) return "";
          if (val is double) return val.toStringAsFixed(2);
          return val.toString();
        }).toList();
      }).toList();

      final doc = await ReportPdfGenerator.buildReportPdf(
        title: "Sales Report (${_reportType.name.toUpperCase()})",
        headers: headers,
        data: data,
        company: pharma.companyProfile,
        subtitle: "From: ${DateFormat('dd/MM/yyyy').format(_from)} To: ${DateFormat('dd/MM/yyyy').format(_to)}",
      );

      if (!mounted) return;
      PrinterService.showProfessionalPreview(
        context: context,
        doc: doc,
        title: "Sales Report Preview",
      );
    } catch (e) {
      if (mounted && shouldShowDialog) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      debugPrint("Print Report Error: $e");
    }
  }

  Widget _buildReportHeader() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFD1D9E1),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "Report Summary From: ${DateFormat('dd/MM/yyyy').format(_from)} To: ${DateFormat('dd/MM/yyyy').format(_to)}",
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF2C3E50)),
            ),
          ),
          InkWell(
            onTap: () => ServerDiscrepancyDialog.show(context, initialCategoryKey: 'sales_invoices'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red.shade700,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.youtube_searched_for_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text('Cloud Audit', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataGrid() {
    _cachedCols ??= _getColumns();
    final columns = _cachedCols!;

    if (_isLoading && _masterData.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_isLoading && _displayData.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text("No records found for the selected range.", style: TextStyle(color: Colors.grey, fontSize: 14)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double totalWidth = columns.fold<double>(0.0, (sum, col) => sum + col.width);
        final double availableWidth = constraints.maxWidth;
        final double scale = availableWidth > totalWidth ? (availableWidth / totalWidth) : 1.0;

        final double effectiveWidth = math.max(totalWidth, availableWidth);
        final List<double> scaledWidths = columns.map((col) => col.width * scale).toList();
        if (scaledWidths.isNotEmpty) {
          final double sumWidths = scaledWidths.fold<double>(0.0, (sum, w) => sum + w);
          final double diff = effectiveWidth - sumWidths;
          scaledWidths[scaledWidths.length - 1] += diff;
        }

        return Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400)),
          child: Scrollbar(
            controller: _horizontalScrollController,
            thumbVisibility: true,
            trackVisibility: true,
            interactive: true,
            thickness: 12.0,
            radius: const Radius.circular(6),
            notificationPredicate: (notif) => notif.depth == 1,
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: effectiveWidth,
                child: Column(
                  children: [
                    // HEADER ROW
                    Container(
                      height: _headerHeight,
                      color: const Color(0xFFF5F5F5),
                      child: Row(
                        children: List.generate(
                          columns.length,
                          (idx) => _GridHeaderCell(
                            col: columns[idx],
                            width: scaledWidths[idx],
                            isSorted: _sortColumnKey == columns[idx].key,
                            isAscending: _isAscending,
                            onSortTap: () => _onColumnHeaderTap(columns[idx].key),
                            onAdvancedTap: (pos) => _openAdvancedFilterDialog(columns[idx], pos),
                            onResize: (newWidth) => setState(() => columns[idx].width = newWidth.clamp(40, 500)),
                            onHeightResize: (newHeight) => setState(() => _headerHeight = newHeight.clamp(40, 150)),
                            onQuickFilter: (condition, val) {
                              if (condition == 'Clear' || val.isEmpty) {
                                _activeFilters.remove(columns[idx].key);
                              } else {
                                _activeFilters[columns[idx].key] = {
                                  'mode': 'rules',
                                  'type': columns[idx].type,
                                  'condition': condition,
                                  'value1': val,
                                };
                              }
                              _applyFilters();
                            },
                          ),
                        ),
                      ),
                    ),
                    // DATA ROWS WITH INTERACTIVE VERTICAL SCROLLBAR
                    Expanded(
                      child: Stack(
                        children: [
                          Scrollbar(
                            controller: _scrollController,
                            thumbVisibility: true,
                            trackVisibility: true,
                            interactive: true,
                            thickness: 12.0,
                            radius: const Radius.circular(6),
                            child: ListView.builder(
                              controller: _scrollController,
                              itemExtent: 25.0,
                              itemCount: _displayData.length + (_hasMore ? 1 : 0),
                              itemBuilder: (ctx, i) {
                                if (i == _displayData.length) {
                                  return Container(
                                    height: 25,
                                    alignment: Alignment.center,
                                    child: const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  );
                                }
                                return _buildGridRow(_displayData[i], columns, scaledWidths, i);
                              },
                            ),
                          ),
                          // QUICK JUMP BUTTONS (Scroll to Top / Scroll to Bottom)
                          Positioned(
                            right: 20,
                            bottom: 10,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Tooltip(
                                  message: "Scroll to Top",
                                  child: Material(
                                    elevation: 4,
                                    shape: const CircleBorder(),
                                    color: Colors.blue.shade700,
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: () {
                                        if (_scrollController.hasClients) {
                                          _scrollController.animateTo(
                                            0,
                                            duration: const Duration(milliseconds: 300),
                                            curve: Curves.easeOut,
                                          );
                                        }
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white, size: 20),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Tooltip(
                                  message: "Scroll to Bottom",
                                  child: Material(
                                    elevation: 4,
                                    shape: const CircleBorder(),
                                    color: Colors.blue.shade700,
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: () {
                                        if (_scrollController.hasClients) {
                                          _scrollController.animateTo(
                                            _scrollController.position.maxScrollExtent,
                                            duration: const Duration(milliseconds: 300),
                                            curve: Curves.easeOut,
                                          );
                                        }
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 20),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildGridFooter(columns, scaledWidths),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridRow(Map<String, dynamic> row, List<_ColInfo> columns, List<double> scaledWidths, int index) {
    bool isDeleted = row['status'] == 'DELETED ENTRY';
    bool isSelected = (index == _selectedIndex);
    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    Color rowBg = isSelected
        ? const Color(0xFFBAE6FD)
        : (isDeleted ? const Color(0xFFFEF2F2) : (index % 2 == 0 ? Colors.white : const Color(0xFFF9F9F9)));

    return InkWell(
      onTap: () {
        final now = DateTime.now();
        setState(() {
          _selectedIndex = index;
        });

        if (_lastTapIndex == index && _lastTapTime != null && now.difference(_lastTapTime!) < const Duration(milliseconds: 350)) {
          _lastTapTime = null;
          _lastTapIndex = null;
          final entryNo = row['raw_entry_no']?.toString() ?? row['entry_no']?.toString();
          if (entryNo != null && entryNo.isNotEmpty) {
            _handleEdit(entryNo, row['raw_date']);
          }
        } else {
          _lastTapIndex = index;
          _lastTapTime = now;
        }
      },
      child: Container(
        height: 25,
        color: rowBg,
        child: ClipRect(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Row(
              children: List.generate(columns.length, (colIdx) {
              final col = columns[colIdx];
              final cellWidth = scaledWidths[colIdx];

              if (col.key == "actions") {
                bool isCredit = row['customer'] == 'Credit';
                bool isPaid = row['is_paid'] ?? true;
                final targetEntryNo = row['raw_entry_no']?.toString() ?? row['entry_no']?.toString() ?? '';
                return Container(
                  width: cellWidth,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200, width: 0.5)),
                  alignment: Alignment.center,
                  child: isDeleted
                      ? const Text("LOCKED", style: TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold))
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isCredit && !isPaid)
                                Tooltip(
                                  message: "Settle",
                                  child: InkWell(
                                    onTap: () => _showSettlementDialog(targetEntryNo),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                                      child: Icon(Icons.account_balance_wallet_rounded, color: Colors.blue, size: 14),
                                    ),
                                  ),
                                ),
                              Tooltip(
                                message: "Delete",
                                child: InkWell(
                                  onTap: () => _handleDelete(targetEntryNo, row['raw_date']),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                                    child: Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                );
              }

              final val = row[col.key];
              String text = "";
              if (val is double) {
                text = val.toStringAsFixed(2);
              } else {
                text = val?.toString() ?? "";
              }

              // --- ACCOUNT COLOR LOGIC ---
              Color? cellBg;
              Color? cellBorder;
              Color? cellText;
              bool isAccountCell = (_reportType == ReportType.accounts && col.key == 'account') ||
                  (_reportType == ReportType.detailed && col.key == 'customer');

              if (isAccountCell && !isDeleted) {
                final String accName = text.toUpperCase().trim();
                try {
                  final account = provider.accountMaster.firstWhere(
                    (a) => a.name.toUpperCase().trim() == accName,
                  );
                  final Color baseColor = Color(int.parse(account.color));
                  cellBg = baseColor.withValues(alpha: 0.15);
                  cellBorder = baseColor;
                  cellText = baseColor.withValues(alpha: 0.9);
                } catch (_) {
                  // Inline fallbacks for standard names if object not found
                  if (accName == "CASH") {
                    cellBg = const Color(0xFFE8F5E9);
                    cellBorder = const Color(0xFF4CAF50);
                    cellText = const Color(0xFF2E7D32);
                  } else if (accName == "UPI") {
                    cellBg = const Color(0xFFE3F2FD);
                    cellBorder = const Color(0xFF2196F3);
                    cellText = const Color(0xFF1565C0);
                  } else if (accName == "NOT RECIEVED" || accName == "NOT RECEIVED") {
                    cellBg = const Color(0xFFFFEBEE); // Light Red
                    cellBorder = const Color(0xFFEF5350);
                    cellText = const Color(0xFFC62828);
                  }
                }
              }

              return ERPTooltip(
                message: text,
                child: Container(
                  width: cellWidth,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: cellBg,
                    border: cellBorder != null
                        ? Border.all(color: cellBorder, width: 1)
                        : Border.all(color: Colors.grey.shade200, width: 0.5),
                    borderRadius: cellBorder != null ? BorderRadius.circular(4) : null,
                  ),
                  alignment: col.align == TextAlign.left ? Alignment.centerLeft : Alignment.centerRight,
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 10,
                      color: cellText ?? (isDeleted ? const Color(0xFF7F1D1D) : Colors.black87),
                      fontWeight: (isDeleted && col.key == 'status') || cellText != null ? FontWeight.bold : FontWeight.normal,
                      decoration: isDeleted && col.key != 'status' ? TextDecoration.lineThrough : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    ),
  );
}

  Widget _buildGridFooter(List<_ColInfo> columns, List<double> scaledWidths) {
    List<Widget> cells = [];
    for (int colIdx = 0; colIdx < columns.length; colIdx++) {
      final col = columns[colIdx];
      final cellWidth = scaledWidths[colIdx];
      final agg = _columnAggregations[col.key] ?? AggregationType.none;
      final result = _calculateAggregation(col.key, agg);

      cells.add(
        GestureDetector(
          onTapDown: (details) => _showAggregationMenu(details.globalPosition, col.key),
          onSecondaryTapDown: (details) => _showAggregationMenu(details.globalPosition, col.key),
          child: ERPTooltip(
            message: result,
            child: Container(
              width: cellWidth,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade300, width: 0.5))),
              alignment: col.align == TextAlign.left ? Alignment.centerLeft : Alignment.centerRight,
              child: Text(
                result,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EAF6),
        border: Border(top: BorderSide(color: Colors.grey.shade400)),
      ),
      child: ClipRect(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Row(
            children: cells,
          ),
        ),
      ),
    );
  }

  String _calculateAggregation(String colKey, AggregationType type) {
    if (type == AggregationType.none || _displayData.isEmpty) return "";

    List<double> values = [];
    for (var row in _displayData) {
      if (row['status'] == 'DELETED ENTRY') continue; // Do not include deleted entries in financial totals
      final val = row[colKey];
      if (val is num) {
        values.add(val.toDouble());
      } else if (val is String) {
        final parsed = double.tryParse(val);
        if (parsed != null) values.add(parsed);
      }
    }

    final activeCount = _displayData.where((r) => r['status'] != 'DELETED ENTRY').length;
    if (type == AggregationType.count) return activeCount.toString();
    if (values.isEmpty) return "";

    switch (type) {
      case AggregationType.sum:
        return values.fold(0.0, (sum, v) => sum + v).toStringAsFixed(2);
      case AggregationType.min:
        return values.reduce((a, b) => a < b ? a : b).toStringAsFixed(2);
      case AggregationType.max:
        return values.reduce((a, b) => a > b ? a : b).toStringAsFixed(2);
      case AggregationType.average:
        return (values.fold(0.0, (sum, v) => sum + v) / values.length).toStringAsFixed(2);
      default:
        return "";
    }
  }

  void _showAggregationMenu(Offset position, String colKey) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final currentAgg = _columnAggregations[colKey] ?? AggregationType.none;
    final resultStr = _calculateAggregation(colKey, currentAgg);

    final List<PopupMenuEntry<dynamic>> items = [
      _buildPopupItem(AggregationType.sum, "Sum", Icons.functions),
      _buildPopupItem(AggregationType.min, "Min", Icons.bar_chart),
      _buildPopupItem(AggregationType.max, "Max", Icons.bar_chart),
      _buildPopupItem(AggregationType.count, "Count", Icons.numbers),
      _buildPopupItem(AggregationType.average, "Average", Icons.abc),
      const PopupMenuDivider(),
      _buildPopupItem(AggregationType.none, "None", Icons.check),
    ];

    if (resultStr.isNotEmpty) {
      items.addAll([
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: "COPY_VALUE",
          height: 32,
          child: Row(
            children: [
              const Icon(Icons.copy, size: 14, color: Colors.blue),
              const SizedBox(width: 8),
              Text("Copy ($resultStr)", style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ]);
    }

    showMenu<dynamic>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: items,
    ).then((selected) {
      if (selected is AggregationType) {
        setState(() => _columnAggregations[colKey] = selected);
      } else if (selected == "COPY_VALUE") {
        Clipboard.setData(ClipboardData(text: resultStr));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Copied $resultStr to clipboard"), duration: const Duration(seconds: 1)),
          );
        }
      }
    });
  }

  void _handleEdit(String entryNo, dynamic date) {
    if (entryNo.toString().isEmpty) return;
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    appProvider.openSales(invoiceNo: entryNo.toString());
  }

  void _handleDelete(String entryNo, DateTime date) async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    if (provider.securityToggles['require_pin_delete_sales'] == true) {
      if (!provider.isAdminSessionActive()) {
        bool isUnlocked = await PinUnlockDialog.show(
            context,
            provider,
            title: "Confirm Deletion",
            message: "Enter Master Password to permanently delete Invoice $entryNo."
        );
        if (!mounted) return;
        if (!isUnlocked) return;
        provider.refreshAdminSession();
      }
    }

    if (!mounted) return;

    // PREVIOUS DAY LOCK CHECK
    bool isOldLocked = provider.isEditLocked(date);
    if (isOldLocked && !provider.isAdminSessionActive()) {
      bool isUnlocked = await PinUnlockDialog.show(
          context,
          provider,
          title: "Locked Entry",
          message: "This entry is from a previous day. Enter Master Password to unlock it for deletion."
      );
      if (!mounted) return;
      if (!isUnlocked) return;
      provider.refreshAdminSession();
      provider.logAudit('UNLOCK_OLD_ENTRY_DELETE', 'Unlocked old entry $entryNo from ${DateFormat('yyyy-MM-dd').format(date)} for deletion.');
    }

    if (!context.mounted) return;
    bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        int focusedIdx = 1; // 1: Delete (Right), 2: Cancel (Left)
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                    Navigator.of(ctx).pop(focusedIdx == 1);
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                    Navigator.of(ctx).pop(false);
                    return KeyEventResult.handled;
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft || event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    setDialogState(() => focusedIdx = (focusedIdx == 1 ? 2 : 1));
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: AlertDialog(
                title: const Text("Delete Invoice"),
                content: Text("Are you sure you want to permanently delete Invoice #$entryNo?"),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(
                      backgroundColor: focusedIdx == 2 ? Colors.grey.shade200 : null,
                      side: focusedIdx == 2 ? const BorderSide(color: Colors.grey, width: 2) : null,
                    ),
                    child: const Text("CANCEL", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold)),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: focusedIdx == 1 ? Colors.red : Colors.red.shade100,
                      foregroundColor: focusedIdx == 1 ? Colors.white : Colors.red.shade900,
                      side: focusedIdx == 1 ? const BorderSide(color: Colors.black26, width: 2) : null,
                    ),
                    child: const Text("DELETE", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (confirm == true) {
      await provider.deleteSale(entryNo);
      provider.logAudit('DELETE_SALE', 'Invoice $entryNo deleted by Admin.');
      _search();
    }
  }

  PopupMenuItem<AggregationType> _buildPopupItem(AggregationType type, String label, IconData icon) {
    return PopupMenuItem(
      value: type,
      height: 35,
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.blueGrey),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

// ============================================================================
// INLINE QUICK FILTER HEADER (The 2-Line Row from the Video)
// ============================================================================
class _GridHeaderCell extends StatefulWidget {
  final _ColInfo col;
  final double width;
  final bool isSorted;
  final bool isAscending;
  final VoidCallback? onSortTap;
  final Function(Offset) onAdvancedTap;
  final Function(String condition, String value) onQuickFilter;
  final Function(double) onResize;
  final Function(double) onHeightResize;

  const _GridHeaderCell({
    required this.col,
    required this.width,
    this.isSorted = false,
    this.isAscending = true,
    this.onSortTap,
    required this.onAdvancedTap,
    required this.onQuickFilter,
    required this.onResize,
    required this.onHeightResize,
  });

  @override
  State<_GridHeaderCell> createState() => _GridHeaderCellState();
}

class _GridHeaderCellState extends State<_GridHeaderCell> {
  late String _quickCondition;
  final TextEditingController _quickCtrl = TextEditingController();
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _setInitialCondition();
  }

  void _setInitialCondition() {
    if (widget.col.type == ColumnType.text) {
      _quickCondition = 'Contains';
    } else if (widget.col.type == ColumnType.numeric) _quickCondition = 'Equals';
    else _quickCondition = 'Equals'; // Date
  }

  @override
  void dispose() {
    _quickCtrl.dispose();
    super.dispose();
  }

  String _getConditionSymbol() {
    switch (_quickCondition) {
      case 'Equals': return '=';
      case 'Does Not Equal': return '!=';
      case 'Contains': return 'inc';
      case 'Does Not Contain': return '!inc';
      case 'Begins With': return 'A..';
      case 'Ends With': return '..Z';
      case 'Greater Than': return '>';
      case 'Less Than': return '<';
      case 'Between': return '><';
      case 'Before': return '<';
      case 'After': return '>';
      default: return '=';
    }
  }

  void _showConditionMenu(TapDownDetails details) async {
    List<String> items = [];
    if (widget.col.type == ColumnType.text) {
      items = ['Equals', 'Does Not Equal', 'Contains', 'Does Not Contain', 'Begins With', 'Ends With'];
    } else if (widget.col.type == ColumnType.numeric) {
      items = ['Equals', 'Does Not Equal', 'Greater Than', 'Less Than', 'Between'];
    } else {
      items = ['Equals', 'Before', 'After', 'Between'];
    }

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(details.globalPosition.dx, details.globalPosition.dy + 10, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: items.map((e) => PopupMenuItem(value: e, height: 30, child: Text(e, style: const TextStyle(fontSize: 11)))).toList(),
    );

    if (result != null) {
      setState(() => _quickCondition = result);
      if (_quickCtrl.text.isNotEmpty) widget.onQuickFilter(_quickCondition, _quickCtrl.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool showFilter = _isHovered || _quickCtrl.text.isNotEmpty;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: ClipRect(
        child: Container(
          width: widget.width,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: Colors.grey.shade300, width: 1),
              bottom: BorderSide(color: Colors.grey.shade400, width: 1),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Row 1: Title and Advanced Filter Icon (Click header title to sort A-Z/Z-A or 0-9/9-0)
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: widget.onSortTap,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6, top: 4, bottom: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    widget.col.label,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: widget.isSorted ? Colors.blue.shade900 : Colors.grey.shade800,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                if (widget.isSorted) ...[
                                  const SizedBox(width: 2),
                                  Icon(
                                    widget.isAscending ? Icons.arrow_upward : Icons.arrow_downward,
                                    size: 11,
                                    color: Colors.blue.shade900,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (showFilter)
                        GestureDetector(
                          onTapDown: (details) => widget.onAdvancedTap(details.globalPosition),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 4, top: 4, bottom: 2),
                            child: Icon(Icons.filter_alt_outlined, size: 14, color: Colors.blueGrey.shade600),
                          ),
                        ),
                    ],
                  ),
                  // Row 2: Quick Filter Input (Always Visible)
                  Container(
                    height: 20,
                    margin: const EdgeInsets.fromLTRB(2, 0, 2, 4),
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300)),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTapDown: _showConditionMenu,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            color: Colors.grey.shade100,
                            alignment: Alignment.center,
                            child: Text(_getConditionSymbol(), style: const TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _quickCtrl,
                            style: const TextStyle(fontSize: 10),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                              border: InputBorder.none,
                              hintText: widget.col.type == ColumnType.date ? "dd/mm/yyyy" : "",
                              hintStyle: const TextStyle(fontSize: 8, color: Colors.grey),
                            ),
                            onChanged: (val) {
                              if (val.isEmpty) {
                                widget.onQuickFilter('Clear', '');
                              } else {
                                widget.onQuickFilter(_quickCondition, val);
                              }
                              setState(() {}); // Rebuild to keep visible if text exists
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Resize handles
              Positioned(
                right: 0, top: 0, bottom: 0,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (details) => widget.onResize(widget.col.width + details.delta.dx),
                    child: Container(width: 4),
                  ),
                ),
              ),
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (details) {
                      final rb = context.findRenderObject() as RenderBox;
                      widget.onHeightResize(rb.size.height + details.delta.dy);
                    },
                    child: Container(height: 4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ============================================================================
// ADVANCED POPUP FILTER DIALOG (Values + Rules Tabs)
// ============================================================================
class _AdvancedFilterPopup extends StatefulWidget {
  final String columnName;
  final ColumnType columnType;
  final List<String> uniqueValues;
  final Map<String, dynamic>? initialFilter;

  const _AdvancedFilterPopup({
    required this.columnName,
    required this.columnType,
    required this.uniqueValues,
    this.initialFilter,
  });

  @override
  State<_AdvancedFilterPopup> createState() => _AdvancedFilterPopupState();
}

class _AdvancedFilterPopupState extends State<_AdvancedFilterPopup> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  String _searchQuery = "";
  late List<String> _selectedValues;

  String _ruleCondition = "None";
  final TextEditingController _val1Ctrl = TextEditingController();
  final TextEditingController _val2Ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);

    _selectedValues = List.from(widget.uniqueValues);

    if (widget.initialFilter != null) {
      if (widget.initialFilter!['mode'] == 'values') {
        _tabCtrl.index = 0;
        _selectedValues = List.from(widget.initialFilter!['selected_values']);
      } else {
        _tabCtrl.index = 1;
        _ruleCondition = widget.initialFilter!['condition'];
        _val1Ctrl.text = widget.initialFilter!['value1'] ?? "";
        _val2Ctrl.text = widget.initialFilter!['value2'] ?? "";
      }
    } else {
      _ruleCondition = widget.columnType == ColumnType.text ? 'Contains' : 'Equals';
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _val1Ctrl.dispose();
    _val2Ctrl.dispose();
    super.dispose();
  }

  void _applyValuesFilter() {
    Navigator.pop(context, {
      'mode': 'values',
      'selected_values': _selectedValues,
    });
  }

  void _applyRulesFilter() {
    if (_ruleCondition == 'None' || _ruleCondition == 'Clear') {
      Navigator.pop(context, {'condition': 'Clear'});
      return;
    }
    Navigator.pop(context, {
      'mode': 'rules',
      'type': widget.columnType,
      'condition': _ruleCondition,
      'value1': _val1Ctrl.text,
      'value2': _val2Ctrl.text,
    });
  }

  void _clearFilter() {
    Navigator.pop(context, {'condition': 'Clear'});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      height: 320,
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade400)),
      child: Column(
        children: [
          Container(
            height: 30,
            color: Colors.grey.shade200,
            child: TabBar(
              controller: _tabCtrl,
              labelColor: Colors.black,
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              indicatorSize: TabBarIndicatorSize.tab,
              tabs: const [Tab(text: "Values"), Tab(text: "Data Filters")],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildValuesTab(),
                _buildRulesTab(),
              ],
            ),
          ),
          Container(
            height: 40,
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade300))),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(onPressed: _clearFilter, child: const Text("Clear Filter", style: TextStyle(fontSize: 11, color: Colors.red))),
                ElevatedButton(
                  onPressed: () {
                    if (_tabCtrl.index == 0) {
                      _applyValuesFilter();
                    } else {
                      _applyRulesFilter();
                    }
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(60, 25), padding: const EdgeInsets.symmetric(horizontal: 10)),
                  child: const Text("Apply", style: TextStyle(fontSize: 11)),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildValuesTab() {
    final filteredList = widget.uniqueValues.where((v) => v.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    bool allSelected = _selectedValues.length == widget.uniqueValues.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: SizedBox(
            height: 25,
            child: TextField(
              style: const TextStyle(fontSize: 11),
              decoration: const InputDecoration(hintText: "Search values...", prefixIcon: Icon(Icons.search, size: 14), border: OutlineInputBorder(), contentPadding: EdgeInsets.zero),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        ),
        InkWell(
          onTap: () {
            setState(() {
              if (allSelected) {
                _selectedValues.clear();
              } else {
                _selectedValues = List.from(widget.uniqueValues);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Icon(allSelected ? Icons.check_box : Icons.check_box_outline_blank, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                const Text("(Select All)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        const Divider(height: 4),
        Expanded(
          child: ListView.builder(
            itemCount: filteredList.length,
            itemBuilder: (ctx, i) {
              final val = filteredList[i];
              final isChecked = _selectedValues.contains(val);
              return InkWell(
                onTap: () {
                  setState(() {
                    if (isChecked) {
                      _selectedValues.remove(val);
                    } else {
                      _selectedValues.add(val);
                    }
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Icon(isChecked ? Icons.check_box : Icons.check_box_outline_blank, size: 16, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(child: Text(val.isEmpty ? "(Blanks)" : val, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              );
            },
          ),
        )
      ],
    );
  }

  Widget _buildRulesTab() {
    List<String> conditions = [];
    if (widget.columnType == ColumnType.text) {
      conditions = ['None', 'Equals', 'Does Not Equal', 'Contains', 'Does Not Contain', 'Begins With', 'Ends With'];
    } else if (widget.columnType == ColumnType.numeric) {
      conditions = ['None', 'Equals', 'Does Not Equal', 'Greater Than', 'Less Than', 'Between'];
    } else {
      conditions = ['None', 'Equals', 'Before', 'After', 'Between'];
    }

    if (!conditions.contains(_ruleCondition)) _ruleCondition = conditions.first;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Show rows where ${widget.columnName}:", style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
          const SizedBox(height: 8),
          SizedBox(
            height: 28,





            child: DropdownButtonFormField<String>(
              initialValue: _ruleCondition,
              decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8)),
              style: const TextStyle(fontSize: 11, color: Colors.black),
              items: conditions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => _ruleCondition = v!),
            ),
          ),
          const SizedBox(height: 12),
          if (_ruleCondition != 'None') ...[
            SizedBox(
              height: 28,
              child: TextField(
                controller: _val1Ctrl,
                style: const TextStyle(fontSize: 11),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  hintText: widget.columnType == ColumnType.date ? "dd/mm/yyyy or mm/yy" : "Enter value...",
                ),
              ),
            ),
            if (_ruleCondition == 'Between') ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Center(child: Text("AND", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
              ),
              SizedBox(
                height: 28,
                child: TextField(
                  controller: _val2Ctrl,
                  style: const TextStyle(fontSize: 11),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    hintText: widget.columnType == ColumnType.date ? "dd/mm/yyyy or mm/yy" : "Enter value...",
                  ),
                ),
              ),
            ]
          ]
        ],
      ),
    );
  }
}