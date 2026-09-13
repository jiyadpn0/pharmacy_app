import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:math';
import 'package:intl/intl.dart';
import '../../providers/pharmacy_provider.dart';
import '../../providers/app_provider.dart';
import '../../models/product_ranking.dart';
import '../../widgets/window_controls_bar.dart';
import '../../widgets/erp_tooltip.dart';

class SpecialOrdersScreen extends StatefulWidget {
  final int initialView;
  final bool isDialog;
  const SpecialOrdersScreen({super.key, this.initialView = 0, this.isDialog = false});

  @override
  State<SpecialOrdersScreen> createState() => _SpecialOrdersScreenState();
}

class _SpecialOrdersScreenState extends State<SpecialOrdersScreen> {
  bool get _isDarkMode => Provider.of<AppProvider>(context, listen: false).isDarkMode;
  final Map<String, Map<String, dynamic>> _activeFilters = {};
  String _selectedTab = 'ORDER'; // Default active tab
  String _orderFilterMode = 'ORDER_BOOK'; // 'ORDER_BOOK', 'EXCESS_STOCK', or 'ALL'
  double _headerHeight = 52.0;

  List<Map<String, dynamic>> _specialOrders = [];
  List<Map<String, dynamic>> _orderSuggestions = [];
  bool _isLoadingData = false;
  final int _orderPage = 1;
  final int _orderPageSize = 50;
  bool _isMoreOrderData = true;

  // Toggle States for Columns
  bool _showProfile = true;
  bool _showRank = true;
  bool _showInterval = true;

  DateTime _selectedDate = DateTime.now();
  DateTime? _intervalFromDate;
  DateTime? _intervalToDate;

  int? _highlightFirstPurDays;
  int? _highlightLastSaleDays;

  final Set<dynamic> _orderedIds = {};
  final Map<dynamic, int> _orderedQtys = {};
  final Map<dynamic, String> _orderedSuppliers = {};

  Color _getSupplierBgColor(String name, bool isDark) {
    final clean = name.trim();
    if (clean.isEmpty || clean == '-' || clean == 'General Wholesale') {
      return isDark ? const Color(0xFF1E293B) : Colors.white; // Blank column in WHITE
    }
    final lightColors = [
      const Color(0xFFDBEAFE), // Soft Blue
      const Color(0xFFDCFCE7), // Soft Green
      const Color(0xFFFEF3C7), // Soft Amber
      const Color(0xFFF3E8FF), // Soft Purple
      const Color(0xFFFFE4E6), // Soft Rose
      const Color(0xFFE0E7FF), // Soft Indigo
      const Color(0xFFCCFBF1), // Soft Teal
      const Color(0xFFFFEDD5), // Soft Orange
      const Color(0xFFFCE7F3), // Soft Pink
      const Color(0xFFCFFAFE), // Soft Cyan
    ];
    final darkColors = [
      const Color(0xFF1E3A8A), // Deep Blue
      const Color(0xFF14532D), // Deep Green
      const Color(0xFF78350F), // Deep Amber
      const Color(0xFF581C87), // Deep Purple
      const Color(0xFF881337), // Deep Rose
      const Color(0xFF312E81), // Deep Indigo
      const Color(0xFF134E4A), // Deep Teal
      const Color(0xFF7C2D12), // Deep Orange
      const Color(0xFF701A75), // Deep Pink
      const Color(0xFF164E63), // Deep Cyan
    ];
    final palette = isDark ? darkColors : lightColors;
    int hash = 0;
    for (int i = 0; i < clean.length; i++) {
      hash = clean.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return palette[hash.abs() % palette.length];
  }

  Color _getSupplierTextColor(String name, bool isDark) {
    final clean = name.trim();
    if (clean.isEmpty || clean == '-' || clean == 'General Wholesale') {
      return isDark ? Colors.grey : Colors.grey.shade600;
    }
    final lightText = [
      const Color(0xFF1E40AF),
      const Color(0xFF166534),
      const Color(0xFF92400E),
      const Color(0xFF6B21A8),
      const Color(0xFF9F1239),
      const Color(0xFF3730A3),
      const Color(0xFF115E59),
      const Color(0xFF9A3412),
      const Color(0xFF831843),
      const Color(0xFF155E75),
    ];
    final darkText = [
      const Color(0xFF93C5FD),
      const Color(0xFF86EFAC),
      const Color(0xFFFDE68A),
      const Color(0xFFE9D5FF),
      const Color(0xFFFECDD3),
      const Color(0xFFC7D2FE),
      const Color(0xFF99F6E4),
      const Color(0xFFFED7AA),
      const Color(0xFFFBCFE8),
      const Color(0xFFA5F3FC),
    ];
    final palette = isDark ? darkText : lightText;
    int hash = 0;
    for (int i = 0; i < clean.length; i++) {
      hash = clean.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return palette[hash.abs() % palette.length];
  }

  final Map<String, double> _colWidths = {
    'agent': 120, 'date': 100, 'product': 210, 'qty': 60,
    'phone': 120, 'name': 160, 'expecting_date': 110,
    'stock': 70, 'expiry': 80, 'mrp': 65, 'rack': 60, 'manufacturer': 140,
    'delete': 45,
    'min_level': 65, 'max_level': 65, 'sales_30d': 80, 'supplier': 140,
    'classification': 100, 'content': 140, 'pRate': 65, 'brand': 110,
    'packSize': 60, 'lastSaleEntryNo': 100, 'lastSaleQty': 70,
    'bestProfitWholesale': 140, 'latestOffer': 80, 'saleCount4M': 80,
    'totalSale1Y': 75, 'peakHigh4M': 80, 'firstPurchaseDate': 85,
    'lastSaleDate': 85, 'rank': 55, 'warning': 65, 'mappedName': 160,
    'pending_order': 85, 'ordered': 110, 'wholesale': 140, 'intervalSaleQty': 85,
    'maxSingleTxn4M': 85, 'lastOrderType': 95,
  };

  static const Map<String, String> _colTooltips = {
    'product': 'PRODUCT NAME\nMaster product item name from database.',
    'rack': 'RACK LOCATION\nPhysical shelf / rack location assigned to product.',
    'classification': 'CLASSIFICATION\nTherapeutic / product category classification.',
    'content': 'CONTENT (GENERIC)\nActive chemical salt / generic ingredient composition.',
    'brand': 'BRAND / MANUFACTURER\nBrand owner or manufacturing company name.',
    'bestProfitWholesale': 'BEST WHOLESALE SUPPLIER\nSupplier offering highest profit margin % = ((MRP - P.Rate) / MRP × 100) from purchases in last 6 months.',
    'latestOffer': 'LATEST OFFER / SCHEME\nMost recent purchase scheme deal (e.g. Free Qty 10+1, 5% Disc, or Scheme Disc %).',
    'mrp': 'MRP (MAX RETAIL PRICE)\nUnit retail selling price ceiling from product master.',
    'pRate': 'PURCHASE RATE (P.RATE)\nLatest unit purchase cost price before tax.',
    'packSize': 'PACK SIZE\nPackaging unit size (e.g. 10s, 100ml).',
    'min_level': 'MIN LEVEL (RE-ORDER POINT)\nMinimum threshold stock level. Warning triggers when Current Stock < Min Level.',
    'max_level': 'MAX LEVEL\nUpper ceiling target stock level to avoid over-stocking.',
    'rank': 'RANK (SALES VELOCITY SCORE)\nWeighted Formula = (Current Month Sales × 0.4) + (1 Month Ago × 0.3) + (2 Months Ago × 0.2) + (12 Month Avg × 0.1).\nUsed as stock benchmark when Min Level is 0.',
    'warning': 'WARNING LEVEL\nRe-order threshold trigger value set in product master.',
    'lastOrderType': 'ORDER TYPE\nOrder mode selected in the sales window (NORMAL, SPECIAL ORDER, ONE TIME ORDER).',
    'ordered': 'ORDERED QTY & TICK\nEnter order quantity or check tick box to auto-fill pending order.',
    'wholesale': 'WHOLESALE SUPPLIER\nTypable / searchable dropdown for selecting purchase order supplier.',
    'stock': 'CURRENT STOCK\nTotal available stock balance across non-expired batches.\nMath: SUM(Stock Batches)',
    'pending_order': 'PENDING ORDER QTY\nCondition: (Current Stock / Pack Size) <= Min Level.\nFormula: Rank - (Current Stock / Pack Size).\nRounding: Fraction >= 0.1 rounds up to next integer.\nSky Blue background shown when > 0.',
    'lastSaleEntryNo': 'LAST SALE INVOICE NO\nInvoice / entry number of the most recent sales transaction.',
    'lastSaleQty': 'LAST SALE QUANTITY\nQuantity sold in the most recent sales invoice.',
    'maxSingleTxn4M': '4M MAX SINGLE TRANSACTION SALE\nHighest quantity sold in a single transaction over the last 4 months (120 days).',
    'totalSale1Y': '1Y TOTAL SALES QTY\nTotal quantity sold across all invoices over the past 12 months (365 days).\nMath: SUM(Sales Qty in last 12M)',
    'firstPurchaseDate': 'FIRST PURCHASE DATE\nEarliest recorded purchase invoice date for this product.\nMath: MIN(Purchase Entry Date)',
    'lastSaleDate': 'LAST SALE DATE\nMost recent sales invoice date for this product.\nMath: MAX(Sales Invoice Date)',
    'mappedName': 'MAPPED EXTERNAL ITEM NAMES\nWholesale / external item names mapped to this stock product (separated by comma if multiple).',
    'agent': 'AGENT NAME\nMedical representative or agent name for special order.',
    'date': 'ORDER DATE\nDate when special order was created.',
    'qty': 'SPECIAL ORDER QTY\nQuantity requested by customer for special order.',
    'phone': 'PHONE NUMBER\nCustomer contact phone number for special order.',
    'name': 'CUSTOMER NAME\nCustomer name for special order.',
    'expecting_date': 'EXPECTING DATE\nExpected / promised delivery date for special order.',
    'expiry': 'EXPIRY DATE\nNearest batch expiry date for current stock.',
    'manufacturer': 'MANUFACTURER\nManufacturer / producer company name.',
    'sales_30d': '30-DAY SALES\nTotal sales quantity sold over the last 30 days.\nMath: SUM(Sales Qty in last 30 days)',
    'supplier': 'PRIMARY SUPPLIER\nPrimary supplier assigned to this product.',
  };

  final ScrollController _leftVerticalScroll = ScrollController();
  final ScrollController _rightVerticalScroll = ScrollController();

  String _formatOffer(String offer) {
    if (offer == '-' || offer.trim().isEmpty) return '-';
    final trimmed = offer.trim();
    if (RegExp(r'^\d+\+\d+$').hasMatch(trimmed)) return trimmed;

    final match = RegExp(r'^([\d.]+)\s*(%?\s*(DISC|SDISC)?)', caseSensitive: false).firstMatch(trimmed);
    if (match != null) {
      final numStr = match.group(1);
      final suffix = match.group(2)?.trim() ?? '';
      final val = double.tryParse(numStr ?? '');
      if (val != null) {
        String formattedVal = (val % 1 == 0) ? val.toInt().toString() : val.toStringAsFixed(1);
        if (suffix.isNotEmpty) {
          return "$formattedVal $suffix".replaceAll(RegExp(r'\s+'), ' ').trim();
        } else {
          return "$formattedVal% DISC";
        }
      }
    }
    return trimmed;
  }

  @override
  void initState() {
    super.initState();
    _leftVerticalScroll.addListener(() {
      if (_leftVerticalScroll.hasClients && _rightVerticalScroll.hasClients) {
        if (_rightVerticalScroll.offset != _leftVerticalScroll.offset) {
          _rightVerticalScroll.jumpTo(_leftVerticalScroll.offset);
        }
      }
    });
    _rightVerticalScroll.addListener(() {
      if (_rightVerticalScroll.hasClients && _leftVerticalScroll.hasClients) {
        if (_leftVerticalScroll.offset != _rightVerticalScroll.offset) {
          _leftVerticalScroll.jumpTo(_rightVerticalScroll.offset);
        }
      }
    });

    _intervalFromDate = _selectedDate.subtract(const Duration(days: 30));
    _intervalToDate = _selectedDate;
    if (widget.initialView == 0) {
      _selectedTab = 'SPECIAL_ORDERS';
    } else {
      _selectedTab = 'ORDER';
    }
    _fetchData();
  }

  @override
  void dispose() {
    _leftVerticalScroll.dispose();
    _rightVerticalScroll.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoadingData = true);
    final p = Provider.of<PharmacyProvider>(context, listen: false);

    try {
      if (_selectedTab == 'SPECIAL_ORDERS') {
        final orders = await p.fetchSpecialOrders(filterDate: _selectedDate);

        final List<Map<String, dynamic>> allItems = [];
        for (var s in orders) {
          try {
            DateTime date = DateTime.tryParse(s['date'].toString()) ?? DateTime.now();
            List<dynamic> list = jsonDecode(s['special_order_json']);
            for (var item in list) {
              allItems.add({
                'entry_no': s['entry_no'],
                'agent': s['agent'] ?? "Admin",
                'date': DateFormat('dd/MM/yyyy HH:mm').format(date),
                'product': item['name'],
                'qty': item['qty'],
                'phone': (s['special_customer_phone']?.toString().isNotEmpty ?? false) ? s['special_customer_phone'] : s['mobile'],
                'name': (s['special_customer_name']?.toString().isNotEmpty ?? false) ? s['special_customer_name'] : s['patient'],
                'expecting_date': (s['expecting_date']?.toString().isEmpty ?? true) ? "N/A" : s['expecting_date'],
              });
            }
          } catch (_) {}
        }
        _specialOrders = allItems;

      } else if (_selectedTab == 'ORDER') {
        // Step 1: Load base items & stock instantly (20ms!)
        final baseItems = await p.getFastBaseOrderBookAnalysis();
        if (baseItems.isNotEmpty && mounted) {
          setState(() {
            _orderSuggestions = baseItems;
            _isLoadingData = false;
          });
        }

        // Step 2: Hydrate full sales history in background seamlessly
        final fullData = await p.getAdvancedOrderBookAnalysis(
          fromDate: _showInterval ? _intervalFromDate : _selectedDate.subtract(const Duration(days: 30)),
          toDate: _showInterval ? _intervalToDate : _selectedDate,
        );
        _isMoreOrderData = false;
        if (mounted && fullData.isNotEmpty) {
          setState(() {
            _orderSuggestions = fullData;
          });
        }
      }
    } catch (e, stack) {
      debugPrint("Error fetching order book data: $e\n$stack");
    } finally {
      if (mounted && _isLoadingData) {
        setState(() {
          _isLoadingData = false;
        });
      }
    }
  }

  void _applyQuickFilter(String col, String condition, String value) {
    setState(() {
      if (condition == 'Clear' || value.isEmpty) {
        _activeFilters.remove(col);
      } else {
        _activeFilters[col] = {
          'condition': condition,
          'value': value,
        };
      }
    });
  }

  void _openAdvancedFilter(String colKey, String title, Offset position) async {
    List<Map<String, dynamic>> data = [];
    if (_selectedTab == 'SPECIAL_ORDERS') {
       data = _specialOrders;
    } else {
       data = _orderSuggestions;
    }

    List<String> uniqueVals = data.map((item) => item[colKey]?.toString() ?? "").toSet().toList();
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
                columnName: title,
                columnKey: colKey,
                uniqueValues: uniqueVals,
                initialFilter: _activeFilters[colKey],
              ),
            ),
          )
        ],
      ),
    );

    if (result != null) {
      if (result['condition'] == 'Clear') {
        _activeFilters.remove(colKey);
      } else {
        _activeFilters[colKey] = result;
      }
      setState(() {});
    }
  }

  bool _matchesFilter(dynamic val, String colKey) {
    if (!_activeFilters.containsKey(colKey)) return true;
    final filter = _activeFilters[colKey]!;
    String condition = filter['condition'];

    if (condition == 'Boolean') {
      bool filterBool = filter['value'].toString().toLowerCase() == 'true';
      bool itemBool = val == true || val.toString().toLowerCase() == 'true' || val.toString() == '1';
      return itemBool == filterBool;
    }

    if (condition == 'Values') {
      List<String> selected = List<String>.from(filter['selected']);
      return selected.contains(val?.toString() ?? "");
    }

    if (condition == 'Numeric') {
      double itemNum = double.tryParse(val?.toString() ?? "0") ?? 0.0;
      String subCond = filter['subCondition'] ?? 'Between';
      if (subCond == 'Between') {
        double from = (filter['from'] as num?)?.toDouble() ?? 0.0;
        double to = (filter['to'] as num?)?.toDouble() ?? double.infinity;
        return itemNum >= from && itemNum <= to;
      } else if (subCond == 'Equals') {
        double target = (filter['val'] as num?)?.toDouble() ?? 0.0;
        return (itemNum - target).abs() < 0.0001;
      } else if (subCond == 'Does Not Equal') {
        double target = (filter['val'] as num?)?.toDouble() ?? 0.0;
        return (itemNum - target).abs() >= 0.0001;
      } else if (subCond == 'Greater Than') {
        double target = (filter['val'] as num?)?.toDouble() ?? 0.0;
        return itemNum > target;
      } else if (subCond == 'Greater Than Or Equal To') {
        double target = (filter['val'] as num?)?.toDouble() ?? 0.0;
        return itemNum >= target;
      } else if (subCond == 'Less Than') {
        double target = (filter['val'] as num?)?.toDouble() ?? 0.0;
        return itemNum < target;
      } else if (subCond == 'Less Than Or Equal To') {
        double target = (filter['val'] as num?)?.toDouble() ?? 0.0;
        return itemNum <= target;
      }
    }

    String filterVal = filter['value'].toString().toLowerCase();
    String itemVal = val?.toString().toLowerCase() ?? "";

    switch (condition) {
      case 'Equals': return itemVal == filterVal;
      case 'Does Not Equal': return itemVal != filterVal;
      case 'Contains': return itemVal.contains(filterVal);
      case 'Does Not Contain': return !itemVal.contains(filterVal);
      case 'Begins With': return itemVal.startsWith(filterVal);
      case 'Ends With': return itemVal.endsWith(filterVal);
      default: return true;
    }
  }

  String _formatNumberString(double val) {
    if (val <= 0 || val.isNaN || val.isInfinite) return "0";
    return (val % 1 == 0) ? val.toInt().toString() : val.toStringAsFixed(1);
  }

  int _calculatePendingOrderQty(double rawPending) {
    if (rawPending <= 0 || rawPending.isNaN || rawPending.isInfinite) return 0;
    int floorVal = rawPending.floor();
    double remainder = rawPending - floorVal;
    // Remainder >= 0.1 rounds up (e.g. 1.0 -> 1, 1.01 -> 1, 1.1 -> 2)
    if (remainder >= 0.09999) {
      return floorVal + 1;
    } else {
      return floorVal;
    }
  }

  String _getOrderTypeLabel(dynamic typeVal) {
    int type = int.tryParse(typeVal?.toString() ?? "0") ?? 0;
    switch (type) {
      case 1:
        return "SPECIAL ORDER";
      case 2:
        return "ONE TIME ORDER";
      default:
        return "NORMAL";
    }
  }

  Color _getOrderTypeColor(dynamic typeVal) {
    int type = int.tryParse(typeVal?.toString() ?? "0") ?? 0;
    switch (type) {
      case 1:
        return Colors.purple.shade900;
      case 2:
        return const Color(0xFFC2410C);
      default:
        return _isDarkMode ? Colors.grey.shade300 : Colors.black87;
    }
  }

  Color? _getOrderTypeBgColor(dynamic typeVal) {
    int type = int.tryParse(typeVal?.toString() ?? "0") ?? 0;
    switch (type) {
      case 1:
        return _isDarkMode ? const Color(0xFF581C87) : const Color(0xFFF3E8FF);
      case 2:
        return _isDarkMode ? const Color(0xFF7C2D12) : const Color(0xFFFFEDD5);
      default:
        return null;
    }
  }

  void _saveSelectedOrdersToConfirmation() async {
    final tickedItems = _orderSuggestions.where((item) => _orderedIds.contains(item['id'])).toList();

    if (tickedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please tick/check at least one product in the ORDERED column to save."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final Map<String, List<Map<String, dynamic>>> groupedBySupplier = {};
    for (var item in tickedItems) {
      final dynamic itemId = item['id'];
      String supplier = (_orderedSuppliers[itemId] ?? item['bestProfitWholesale'] ?? item['preferred_wholesale'] ?? "").toString().trim();
      if (supplier.isEmpty || supplier == '-') {
        supplier = "General Wholesale";
      }
      groupedBySupplier.putIfAbsent(supplier, () => []).add(item);
    }

    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    int count = 0;

    for (var entry in groupedBySupplier.entries) {
      String supplier = entry.key;
      List<Map<String, dynamic>> items = entry.value;
      String orderId = "ORD-${DateFormat('yyyyMMdd').format(_selectedDate)}-${(DateTime.now().millisecondsSinceEpoch + count).toString().substring(8)}";

      List<OrderConfirmationItem> orderItems = items.map((i) {
        final dynamic itemId = i['id'];
        double pRate = double.tryParse(i['pRate']?.toString() ?? "0") ?? 0.0;
        double minLvl = double.tryParse(i['minLevel']?.toString() ?? "0") ?? 0.0;
        double stock = double.tryParse(i['currentBalance']?.toString() ?? "0") ?? 0.0;
        double rank = double.tryParse(i['rank']?.toString() ?? "0") ?? 0.0;
        int pack = int.tryParse(i['packSize']?.toString() ?? "1") ?? 1;
        if (pack <= 0) pack = 1;

        double effMin = minLvl > 0 ? minLvl : (rank > 0 ? rank : 1.0);
        double stockInPacks = stock / pack.toDouble();

        int defaultReqQty = 1;
        if (stockInPacks <= effMin) {
          defaultReqQty = _calculatePendingOrderQty(rank - stockInPacks);
          if (defaultReqQty <= 0) defaultReqQty = 1;
        }

        int reqQty = _orderedQtys[itemId] ?? defaultReqQty;

        return OrderConfirmationItem(
          orderId: orderId,
          productId: i['id']?.toString() ?? "",
          productName: i['name']?.toString() ?? "",
          company: i['brand']?.toString() ?? "",
          orderQty: reqQty,
          packSize: pack,
          unitPrice: pRate,
        );
      }).toList();

      double totalAmt = orderItems.fold(0.0, (sum, item) => sum + (item.orderQty * item.unitPrice));

      OrderConfirmation order = OrderConfirmation(
        orderId: orderId,
        orderDate: _selectedDate,
        supplierName: supplier,
        totalItems: orderItems.length,
        totalAmount: totalAmt,
        status: 'PENDING',
        expectedDeliveryDate: DateFormat('dd/MM/yyyy').format(_selectedDate.add(const Duration(days: 2))),
        notes: "Generated from Order Book on ${DateFormat('dd/MM/yyyy').format(_selectedDate)}",
        createdAt: DateTime.now(),
        items: orderItems,
      );

      await provider.saveOrderConfirmation(order);
      count++;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Saved $count Order Confirmation(s) (${tickedItems.length} items) successfully!"),
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

  @override
  Widget build(BuildContext context) {
    final pharmacy = Provider.of<PharmacyProvider>(context);
    final app = Provider.of<AppProvider>(context);
    final isDarkMode = app.isDarkMode;

    // Dynamic Colors based on Mode
    final bgColor = isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
    final cardColor = isDarkMode ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF1E293B);
    final subTextColor = isDarkMode ? Colors.white70 : Colors.blueGrey;
    final borderColor = isDarkMode ? Colors.blueGrey.shade900 : Colors.grey.shade200;

    return Column(
      children: [
        if (widget.isDialog)
          WindowControlsBar(
            onClose: () => Navigator.pop(context),
          ),
        Expanded(
          child: Container(
            color: bgColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // LEFT SIDE: Title + Date Range + Tab Selectors
                    Text("Order Book",
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: textColor, letterSpacing: -0.5)),
                    if (_showInterval) ...[
                      const SizedBox(width: 12),
                      _buildMergedIntervalRangePicker(textColor),
                    ],
                    const SizedBox(width: 12),
                    _buildTabSelector(),
                    if (_selectedTab == 'ORDER') ...[
                      const SizedBox(width: 12),
                      _buildModeSwitch(),
                    ],

                    const Spacer(),

                    // RIGHT SIDE: Checkboxes on Top, Dropdowns Slightly Below
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Top Sub-Row: Checkboxes PROFILE, RANK, INTERVAL
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildToggle("PROFILE", _showProfile, (v) => setState(() => _showProfile = v), textColor),
                            const SizedBox(width: 12),
                            _buildToggle("RANK", _showRank, (v) => setState(() => _showRank = v), textColor),
                            const SizedBox(width: 12),
                            _buildToggle("INTERVAL", _showInterval, (v) {
                              setState(() {
                                _showInterval = v;
                                _fetchData();
                              });
                            }, textColor),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Bottom Sub-Row: Dropdowns 1st Pur > and Last Sale >
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildHighlightDaysPicker(
                              label: "1st Pur >",
                              selectedDays: _highlightFirstPurDays,
                              onDaysChanged: (d) => setState(() => _highlightFirstPurDays = d),
                            ),
                            const SizedBox(width: 8),
                            _buildHighlightDaysPicker(
                              label: "Last Sale >",
                              selectedDays: _highlightLastSaleDays,
                              onDaysChanged: (d) => setState(() => _highlightLastSaleDays = d),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _isLoadingData 
                          ? const Center(child: CircularProgressIndicator())
                          : (_selectedTab == 'ORDER' ? _buildOrderView(pharmacy, textColor, subTextColor, cardColor, borderColor) : _buildSpecialOrdersView(pharmacy, textColor, subTextColor, cardColor, borderColor)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateSelector(Color textColor) {
    String formattedDate = DateFormat('dd/MM/yyyy').format(_selectedDate);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.white,
            border: Border.all(color: _isDarkMode ? Colors.white24 : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: Text(formattedDate, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
        ),
        const SizedBox(width: 4),
        Builder(
          builder: (context) {
            return InkWell(
              onTap: () => _showCalendarPopup(context),
              child: Container(
                height: 32,
                width: 40,
                decoration: BoxDecoration(
                  color: _isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade100,
                  border: Border.all(color: _isDarkMode ? Colors.white24 : Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_month_outlined, size: 16, color: textColor),
                    Icon(Icons.arrow_drop_down, size: 14, color: textColor),
                  ],
                ),
              ),
            );
          }
        ),
      ],
    );
  }

  void _showCalendarPopup(BuildContext context) async {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    
    // Calculate position
    final Offset offset = button.localToGlobal(Offset.zero, ancestor: overlay);
    
    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => Stack(
        children: [
          Positioned(
            top: offset.dy + button.size.height + 5,
            left: offset.dx - 100, // Slightly offset to the left to center better
            child: Material(
              elevation: 12,
              shadowColor: Colors.black45,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 280,
                height: 320,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: Theme(
                        data: ThemeData.light().copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: Colors.blueAccent,
                            onPrimary: Colors.white,
                            onSurface: Colors.black87,
                          ),
                          textTheme: const TextTheme(
                            bodyMedium: TextStyle(fontSize: 12),
                          ),
                        ),
                        child: CalendarDatePicker(
                          initialDate: _selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          onDateChanged: (date) {
                            Navigator.pop(ctx, date);
                          },
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Today: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}",
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                          ),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _fetchData();
      });
    }
  }

  Widget _buildToggle(String label, bool value, Function(bool) onChanged, Color textColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: const Color(0xFF2563EB),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: textColor)),
      ],
    );
  }

  Widget _buildMergedIntervalRangePicker(Color textColor) {
    final fromStr = _intervalFromDate != null ? DateFormat('dd/MM/yyyy').format(_intervalFromDate!) : 'Start';
    final toStr = _intervalToDate != null ? DateFormat('dd/MM/yyyy').format(_intervalToDate!) : 'End';
    final formattedRange = "$fromStr - $toStr";

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        border: Border.all(color: _isDarkMode ? Colors.blueGrey.shade700 : Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: InkWell(
        onTap: () async {
          final picked = await showDateRangePicker(
            context: context,
            initialDateRange: DateTimeRange(
              start: _intervalFromDate ?? DateTime.now().subtract(const Duration(days: 30)),
              end: _intervalToDate ?? DateTime.now(),
            ),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
            builder: (context, child) {
              return Theme(
                data: ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: Color(0xFF2563EB),
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Colors.black87,
                  ),
                ),
                child: child!,
              );
            },
          );

          if (picked != null) {
            setState(() {
              _intervalFromDate = picked.start;
              _intervalToDate = picked.end;
              _fetchData();
            });
          }
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formattedRange,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: _isDarkMode ? Colors.tealAccent : const Color(0xFF2563EB),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.calendar_month_outlined,
              size: 15,
              color: _isDarkMode ? Colors.tealAccent : const Color(0xFF2563EB),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTabItem("ORDER ANALYSIS", 'ORDER'),
          _buildTabItem("SPECIAL ORDERS", 'SPECIAL_ORDERS'),
        ],
      ),
    );
  }

  Widget _buildModeSwitch() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _isDarkMode ? const Color(0xFF1E293B) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _isDarkMode ? Colors.blueGrey.shade800 : Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeSwitchItem("ORDER BOOK", 'ORDER_BOOK', const Color(0xFF2563EB)),
          _buildModeSwitchItem("EXCESS STOCK", 'EXCESS_STOCK', const Color(0xFF16A34A)),
          _buildModeSwitchItem("ALL", 'ALL', Colors.grey),
        ],
      ),
    );
  }

  Widget _buildModeSwitchItem(String label, String mode, Color accentColor) {
    final bool isSelected = _orderFilterMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _orderFilterMode = mode;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? (_isDarkMode ? accentColor.withValues(alpha: 0.25) : accentColor.withValues(alpha: 0.15))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected
              ? Border.all(color: accentColor, width: 1.2)
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? accentColor : Colors.grey.shade400,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                color: isSelected
                    ? (_isDarkMode ? Colors.white : accentColor)
                    : (_isDarkMode ? Colors.white60 : Colors.grey.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isDateOnOrAfter(String? dateStr, DateTime? targetDate) {
    if (dateStr == null || dateStr.isEmpty || dateStr == '-' || targetDate == null) return false;
    try {
      final parsed = DateTime.parse(dateStr);
      final dateOnly = DateTime(parsed.year, parsed.month, parsed.day);
      final targetOnly = DateTime(targetDate.year, targetDate.month, targetDate.day);
      return !dateOnly.isBefore(targetOnly);
    } catch (_) {
      return false;
    }
  }

  String _formatDate(dynamic d) {
    if (d == null || d.toString().isEmpty || d.toString() == '-') return '-';
    try {
      return DateFormat('dd/MM/yy').format(DateTime.parse(d.toString()));
    } catch (_) {
      return d.toString();
    }
  }

  DateTime? _getCutoffDateFromDays(int? days) {
    if (days == null || days <= 0) return null;
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);
    return todayOnly.subtract(Duration(days: days));
  }

  void _showDaysPickerPopup(BuildContext context, String title, int? currentDays, Function(int?) onSelected) async {
    final TextEditingController customCtrl = TextEditingController();
    final items = [15, 30, 45, 60, 90, 120, 180, 365];

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text("Select Previous Days ($title)", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _isDarkMode ? Colors.white : Colors.black87)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Quick Presets:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _isDarkMode ? Colors.white70 : Colors.grey.shade700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: items.map((days) {
                final isSelected = currentDays == days;
                return ChoiceChip(
                  label: Text("$days Days", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : (_isDarkMode ? Colors.white70 : Colors.black87))),
                  selected: isSelected,
                  selectedColor: Colors.red.shade600,
                  backgroundColor: _isDarkMode ? Colors.blueGrey.shade800 : Colors.grey.shade100,
                  onSelected: (_) => Navigator.pop(ctx, days),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: customCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: _isDarkMode ? Colors.white : Colors.black),
                    decoration: InputDecoration(
                      labelText: "Custom Days",
                      hintText: "e.g. 60",
                      isDense: true,
                      labelStyle: TextStyle(color: _isDarkMode ? Colors.white70 : Colors.grey.shade700),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white),
                  onPressed: () {
                    final val = int.tryParse(customCtrl.text);
                    if (val != null && val > 0) {
                      Navigator.pop(ctx, val);
                    }
                  },
                  child: const Text("Apply"),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (currentDays != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, -1),
              child: const Text("Clear Highlight", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Cancel", style: TextStyle(color: _isDarkMode ? Colors.white60 : Colors.blueGrey)),
          ),
        ],
      ),
    );

    if (result == -1) {
      onSelected(null);
    } else if (result != null) {
      onSelected(result);
    }
  }

  Widget _buildHighlightDaysPicker({
    required String label,
    required int? selectedDays,
    required Function(int?) onDaysChanged,
  }) {
    final hasDays = selectedDays != null && selectedDays > 0;
    final displayTxt = hasDays ? "$selectedDays Days" : "Days";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: hasDays
            ? (_isDarkMode ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2))
            : (_isDarkMode ? const Color(0xFF1E293B) : Colors.white),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasDays ? Colors.red.shade400 : (_isDarkMode ? Colors.blueGrey.shade700 : Colors.grey.shade300),
          width: hasDays ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.circle,
            size: 6,
            color: hasDays ? Colors.red : Colors.grey.shade400,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: hasDays ? Colors.red.shade700 : (_isDarkMode ? Colors.white70 : Colors.blueGrey.shade800),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _showDaysPickerPopup(context, label, selectedDays, onDaysChanged),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: hasDays ? Colors.red.shade600 : (_isDarkMode ? Colors.blueGrey.shade800 : const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayTxt,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: hasDays ? Colors.white : (_isDarkMode ? Colors.white : const Color(0xFF1E293B)),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 14,
                    color: hasDays ? Colors.white : (_isDarkMode ? Colors.tealAccent : const Color(0xFF2563EB)),
                  ),
                ],
              ),
            ),
          ),
          if (hasDays) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: () => onDaysChanged(null),
              child: const Padding(
                padding: EdgeInsets.all(2.0),
                child: Icon(Icons.close, size: 14, color: Colors.red),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTabItem(String label, String tab) {
    final isSelected = _selectedTab == tab;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTab = tab;
          _fetchData();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: isSelected ? Colors.white : (_isDarkMode ? Colors.white54 : Colors.blueGrey),
          ),
        ),
      ),
    );
  }

  Widget _buildOrderView(PharmacyProvider pharmacy, Color textColor, Color subTextColor, Color cardColor, Color borderColor) {
    final filtered = _orderSuggestions.where((item) {
      for (String filterKey in _activeFilters.keys) {
        dynamic itemVal;
        switch (filterKey) {
          case 'product':
            itemVal = item['name'];
            break;
          case 'stock':
            itemVal = item['currentBalance'];
            break;
          case 'min_level':
            itemVal = item['minLevel'];
            break;
          case 'max_level':
            itemVal = item['maxLevel'];
            break;
          case 'ordered':
            itemVal = _orderedIds.contains(item['id']);
            break;
          case 'lastSaleDate':
            itemVal = _formatDate(item['lastSaleDate']);
            break;
          case 'warning':
            final double databaseWarning = double.tryParse(item['warning']?.toString() ?? "0") ?? 0;
            itemVal = databaseWarning > 0 ? databaseWarning.toStringAsFixed(1) : "0.0";
            break;
          default:
            itemVal = item[filterKey];
            break;
        }
        if (!_matchesFilter(itemVal, filterKey)) return false;
      }

      // Mode Switch Filter (ORDER BOOK vs EXCESS STOCK vs ALL)
      if (_orderFilterMode == 'ORDER_BOOK') {
        final double databaseRank = double.tryParse(item['rank']?.toString() ?? "0") ?? 0;
        final double databaseMinLevel = double.tryParse(item['minLevel']?.toString() ?? "0") ?? 0;
        final double currentStock = double.tryParse(item['currentBalance']?.toString() ?? "0") ?? 0;
        final int packSizeVal = int.tryParse(item['packSize']?.toString() ?? "1") ?? 1;
        final double safePackSize = packSizeVal > 0 ? packSizeVal.toDouble() : 1.0;
        final double stockInPacks = currentStock / safePackSize;
        final double effectiveMinLevel = databaseMinLevel > 0 ? databaseMinLevel : (databaseRank > 0 ? databaseRank : 1.0);
        final bool isWarning = stockInPacks <= effectiveMinLevel;

        int pendingOrderQty = 0;
        bool isPendingOrder = false;

        if (isWarning) {
          double rawPending = databaseRank - stockInPacks;
          pendingOrderQty = _calculatePendingOrderQty(rawPending);
          if (pendingOrderQty > 0) {
            isPendingOrder = true;
          }
        }

        final double lastSaleQty = double.tryParse(item['lastSaleQty']?.toString() ?? "0") ?? 0;
        final double maxSingle4M = double.tryParse(item['maxSingleTxn4M']?.toString() ?? "0") ?? 0;
        final double databaseWarningVal = double.tryParse(item['warning']?.toString() ?? "0") ?? 0;
        final double warningTarget = max(databaseWarningVal, max(lastSaleQty, maxSingle4M));
        final double totalAvailableUnits = (pendingOrderQty * safePackSize) + currentStock;
        final bool isWarningTriggered = warningTarget > totalAvailableUnits && warningTarget > 0;

        // Shows Blue Pendings OR Red Warnings
        if (!isPendingOrder && !isWarningTriggered) return false;

      } else if (_orderFilterMode == 'EXCESS_STOCK') {
        final double databaseRank = double.tryParse(item['rank']?.toString() ?? "0") ?? 0;
        final double databaseMaxLevel = double.tryParse(item['maxLevel']?.toString() ?? "0") ?? 0;
        final double databaseMinLevel = double.tryParse(item['minLevel']?.toString() ?? "0") ?? 0;
        final double currentStock = double.tryParse(item['currentBalance']?.toString() ?? "0") ?? 0;
        final int packSizeVal = int.tryParse(item['packSize']?.toString() ?? "1") ?? 1;
        final double safePackSize = packSizeVal > 0 ? packSizeVal.toDouble() : 1.0;
        final double stockInPacks = currentStock / safePackSize;
        final double effectiveMinLevel = databaseMinLevel > 0 ? databaseMinLevel : (databaseRank > 0 ? databaseRank : 1.0);
        final bool isWarning = stockInPacks <= effectiveMinLevel;

        bool isExcessOrder = false;
        if (!isWarning && databaseMaxLevel > 0 && databaseMaxLevel > databaseRank && stockInPacks > databaseMaxLevel) {
          double rawExcess = stockInPacks - databaseMaxLevel;
          int pendingOrderQty = rawExcess.floor();
          if (pendingOrderQty > 0) {
            isExcessOrder = true;
          }
        }

        // Shows Green Excess Stocks
        if (!isExcessOrder) return false;
      }

      return true;
    }).toList();

    double rightTotalWidth = 0;
    if (_showProfile) {
      rightTotalWidth += _colWidths['rack']! + _colWidths['classification']! + _colWidths['content']! + _colWidths['brand']!;
    }
    rightTotalWidth += _colWidths['bestProfitWholesale']! + _colWidths['latestOffer']! + _colWidths['mrp']! + _colWidths['pRate']! + _colWidths['packSize']!;
    if (_showRank) {
      rightTotalWidth += _colWidths['min_level']! + _colWidths['max_level']!;
    }
    rightTotalWidth += _colWidths['lastOrderType']!;
    rightTotalWidth += _colWidths['rank']!;
    rightTotalWidth += _colWidths['stock']! + _colWidths['pending_order']! + _colWidths['ordered']! + _colWidths['wholesale']!;
    if (_showRank) {
      rightTotalWidth += _colWidths['warning']!;
    }
    rightTotalWidth += _colWidths['lastSaleQty']! + _colWidths['lastSaleDate']! + _colWidths['maxSingleTxn4M']!;
    if (_showInterval) {
      rightTotalWidth += _colWidths['totalSale1Y']! + _colWidths['firstPurchaseDate']!;
    }
    rightTotalWidth += _colWidths['mappedName']!;

    const headerColor = Color(0xFF0F172A); // Dark navy PHARMA PRO header color
    final oddRowColor = _isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

    final ScrollController horizontalScroll = ScrollController();
    final double leftPaneWidth = 45 + _colWidths['product']!;

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // LEFT FROZEN PANE (SL NUMBER AND PRODUCT BOX)
              SizedBox(
                width: leftPaneWidth,
                child: Column(
                  children: [
                    Container(
                      height: _headerHeight,
                      color: headerColor,
                      child: Row(
                        children: [
                          const SizedBox(width: 45, child: Center(child: Text("SL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)))),
                          _hdr("PRODUCT", 'product', width: _colWidths['product']!),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: _leftVerticalScroll,
                        itemCount: filtered.length,
                        itemExtent: 36.0,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return Container(
                            key: ValueKey("left_${item['id']}"),
                            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: borderColor)), color: index % 2 == 0 ? cardColor : oddRowColor),
                            child: Row(
                              children: [
                                _Cell("${index + 1}", width: 45, align: TextAlign.center, color: _isDarkMode ? Colors.white38 : Colors.grey, isDarkMode: _isDarkMode),
                                _Cell(item['name']?.toString() ?? "", width: _colWidths['product']!, fontWeight: FontWeight.bold, color: textColor, isDarkMode: _isDarkMode),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // DIVIDER BORDER
              Container(width: 1, color: borderColor),

              // RIGHT SCROLLABLE PANE
              Expanded(
                child: Scrollbar(
                  controller: horizontalScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: horizontalScroll,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: rightTotalWidth,
                      child: Column(
                        children: [
                          Container(
                            height: _headerHeight,
                            color: headerColor,
                            child: Row(
                              children: [
                                if (_showProfile) ...[
                                  _hdr("RACK", 'rack', width: _colWidths['rack']!),
                                  _hdr("CLASSIFICATION", 'classification', width: _colWidths['classification']!),
                                  _hdr("CONTENT", 'content', width: _colWidths['content']!),
                                  _hdr("BRAND", 'brand', width: _colWidths['brand']!),
                                ],
                                _hdr("BEST WHOLESALE", 'bestProfitWholesale', width: _colWidths['bestProfitWholesale']!),
                                _hdr("OFFER", 'latestOffer', width: _colWidths['latestOffer']!),
                                _hdr("MRP", 'mrp', width: _colWidths['mrp']!),
                                _hdr("P.RATE", 'pRate', width: _colWidths['pRate']!),
                                _hdr("PACK SIZE", 'packSize', width: _colWidths['packSize']!),
                                if (_showRank) ...[
                                  _hdr("MIN LEVEL", 'min_level', width: _colWidths['min_level']!),
                                  _hdr("MAX LEVEL", 'max_level', width: _colWidths['max_level']!),
                                ],
                                _hdr("ORDER TYPE", 'lastOrderType', width: _colWidths['lastOrderType']!),
                                _hdr("RANK", 'rank', width: _colWidths['rank']!),
                                _hdr("CURR. STOCK", 'stock', width: _colWidths['stock']!),
                                _hdr("PENDING ORDER", 'pending_order', width: _colWidths['pending_order']!),
                                _hdr("ORDERED", 'ordered', width: _colWidths['ordered']!),
                                _hdr("WHOLESALE", 'wholesale', width: _colWidths['wholesale']!),
                                if (_showRank) _hdr("WARNING", 'warning', width: _colWidths['warning']!),
                                _hdr("LAST SALE QTY", 'lastSaleQty', width: _colWidths['lastSaleQty']!),
                                _hdr("LAST SALE DATE", 'lastSaleDate', width: _colWidths['lastSaleDate']!),
                                _hdr("4M MAX SINGLE", 'maxSingleTxn4M', width: _colWidths['maxSingleTxn4M']!),
                                if (_showInterval) ...[
                                  _hdr("1Y TOTAL", 'totalSale1Y', width: _colWidths['totalSale1Y']!),
                                  _hdr("F.PUR DATE", 'firstPurchaseDate', width: _colWidths['firstPurchaseDate']!),
                                ],
                                _hdr("MAPPED NAME", 'mappedName', width: _colWidths['mappedName']!),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Scrollbar(
                              controller: _rightVerticalScroll,
                              thumbVisibility: true,
                              child: ListView.builder(
                                controller: _rightVerticalScroll,
                                itemCount: filtered.length,
                                itemExtent: 36.0,
                                itemBuilder: (context, index) {
                                  final item = filtered[index];
                                  final double currentStock = double.tryParse(item['currentBalance']?.toString() ?? "0") ?? 0;
                                  final double databaseMinLevel = double.tryParse(item['minLevel']?.toString() ?? "0") ?? 0;
                                  final double databaseMaxLevel = double.tryParse(item['maxLevel']?.toString() ?? "0") ?? 0;
                                  final double databaseRank = double.tryParse(item['rank']?.toString() ?? "0") ?? 0;
                                  final double databaseWarning = double.tryParse(item['warning']?.toString() ?? "0") ?? 0;

                                  final int packSizeVal = int.tryParse(item['packSize']?.toString() ?? "1") ?? 1;
                                  final double safePackSize = packSizeVal > 0 ? packSizeVal.toDouble() : 1.0;
                                  final double stockInPacks = currentStock / safePackSize;

                                  // Effective min level benchmark
                                  final double effectiveMinLevel = databaseMinLevel > 0 ? databaseMinLevel : (databaseRank > 0 ? databaseRank : 1.0);
                                  final bool isWarning = stockInPacks <= effectiveMinLevel;

                                  int pendingOrderQty = 0;
                                  bool isPendingOrder = false; // Sky Blue
                                  bool isExcessOrder = false;  // Green

                                  if (isWarning) {
                                    double rawPending = databaseRank - stockInPacks;
                                    pendingOrderQty = _calculatePendingOrderQty(rawPending);
                                    if (pendingOrderQty > 0) {
                                      isPendingOrder = true;
                                    }
                                  } else if (databaseMaxLevel > 0 && databaseMaxLevel > databaseRank && stockInPacks > databaseMaxLevel) {
                                    double rawExcess = stockInPacks - databaseMaxLevel;
                                    pendingOrderQty = rawExcess.floor();
                                    if (pendingOrderQty > 0) {
                                      isExcessOrder = true;
                                    }
                                  }

                                  // WARNING Calculation & Column Red Highlights
                                  final double lastSaleQty = double.tryParse(item['lastSaleQty']?.toString() ?? "0") ?? 0;
                                  final double maxSingle4M = double.tryParse(item['maxSingleTxn4M']?.toString() ?? "0") ?? 0;
                                  final double warningTarget = max(databaseWarning, max(lastSaleQty, maxSingle4M));
                                  final double totalAvailableUnits = (pendingOrderQty * safePackSize) + currentStock;

                                  final bool isWarningTriggered = warningTarget > totalAvailableUnits && warningTarget > 0;
                                  final String warningDisplayVal = databaseWarning > 0
                                      ? _formatNumberString(databaseWarning)
                                      : (isWarningTriggered ? _formatNumberString(warningTarget) : "0");

                                  final bool isWarningRed = isWarningTriggered;
                                  final bool isLastSaleRed = isWarningTriggered && (lastSaleQty == warningTarget) && lastSaleQty > 0;
                                  final bool isMaxSingleRed = isWarningTriggered && (maxSingle4M == warningTarget) && maxSingle4M > 0;

                                  return Container(
                                    key: ValueKey("right_${item['id']}"),
                                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: borderColor)), color: index % 2 == 0 ? cardColor : oddRowColor),
                                    child: Row(
                                      children: [
                                        if (_showProfile) ...[
                                          _Cell(item['rack']?.toString() ?? "", width: _colWidths['rack']!, align: TextAlign.center, isDarkMode: _isDarkMode),
                                          _Cell(item['classification']?.toString() ?? "", width: _colWidths['classification']!, isDarkMode: _isDarkMode),
                                          _Cell(item['content']?.toString() ?? "", width: _colWidths['content']!, isDarkMode: _isDarkMode),
                                          _Cell(item['brand']?.toString() ?? "", width: _colWidths['brand']!, isDarkMode: _isDarkMode),
                                        ],
                                        _Cell(item['bestProfitWholesale']?.toString() ?? "-", width: _colWidths['bestProfitWholesale']!, isDarkMode: _isDarkMode),
                                        _Cell(_formatOffer(item['latestOffer']?.toString() ?? "-"), width: _colWidths['latestOffer']!, color: Colors.green.shade700, fontWeight: FontWeight.bold, isDarkMode: _isDarkMode),
                                        _Cell(item['mrp']?.toString() ?? "0", width: _colWidths['mrp']!, align: TextAlign.right, isDarkMode: _isDarkMode),
                                        _Cell(item['pRate']?.toString() ?? "0", width: _colWidths['pRate']!, align: TextAlign.right, isDarkMode: _isDarkMode),
                                        _Cell(item['packSize']?.toString() ?? "", width: _colWidths['packSize']!, align: TextAlign.center, isDarkMode: _isDarkMode),
                                        if (_showRank) ...[
                                          _Cell(
                                            effectiveMinLevel.toStringAsFixed(1),
                                            width: _colWidths['min_level']!,
                                            align: TextAlign.center,
                                            fontWeight: FontWeight.bold,
                                            color: _isDarkMode ? Colors.redAccent : const Color(0xFFEF4444),
                                            isDarkMode: _isDarkMode,
                                            bgColor: _isDarkMode ? Colors.red.withValues(alpha: 0.2) : const Color(0xFFFEF2F2),
                                            borderColor: _isDarkMode ? Colors.redAccent.withValues(alpha: 0.5) : const Color(0xFFFEE2E2),
                                          ),
                                          _Cell(
                                            databaseMaxLevel > 0 ? databaseMaxLevel.toStringAsFixed(1) : "0",
                                            width: _colWidths['max_level']!,
                                            align: TextAlign.center,
                                            fontWeight: FontWeight.bold,
                                            color: _isDarkMode ? Colors.greenAccent : const Color(0xFF22C55E),
                                            isDarkMode: _isDarkMode,
                                            bgColor: _isDarkMode ? Colors.green.withValues(alpha: 0.2) : const Color(0xFFF0FDF4),
                                            borderColor: _isDarkMode ? Colors.greenAccent.withValues(alpha: 0.5) : const Color(0xFFDCFCE7),
                                          ),
                                        ],
                                        _Cell(
                                          _getOrderTypeLabel(item['lastOrderType']),
                                          width: _colWidths['lastOrderType']!,
                                          align: TextAlign.center,
                                          fontWeight: FontWeight.bold,
                                          color: _getOrderTypeColor(item['lastOrderType']),
                                          bgColor: _getOrderTypeBgColor(item['lastOrderType']),
                                          isDarkMode: _isDarkMode,
                                        ),
                                        _Cell(
                                          databaseRank.toStringAsFixed(1),
                                          width: _colWidths['rank']!,
                                          align: TextAlign.center,
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold,
                                          isDarkMode: _isDarkMode,
                                          bgColor: const Color(0xFFFFD700),
                                          borderColor: const Color(0xFFFFD700),
                                        ),
                                        _Cell(
                                          item['currentBalance']?.toString() ?? "0",
                                          width: _colWidths['stock']!,
                                          align: TextAlign.center,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          isDarkMode: _isDarkMode,
                                          bgColor: const Color(0xFF0F172A),
                                          borderColor: const Color(0xFF1E293B),
                                        ),
                                        _Cell(
                                          pendingOrderQty.toString(),
                                          width: _colWidths['pending_order']!,
                                          align: TextAlign.center,
                                          fontWeight: FontWeight.bold,
                                          color: isPendingOrder
                                              ? Colors.black
                                              : (isExcessOrder ? Colors.white : (_isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600)),
                                          isDarkMode: _isDarkMode,
                                          bgColor: isPendingOrder
                                              ? const Color(0xFF38BDF8)
                                              : (isExcessOrder ? const Color(0xFF16A34A) : null),
                                          borderColor: isPendingOrder
                                              ? const Color(0xFF0284C7)
                                              : (isExcessOrder ? const Color(0xFF15803D) : null),
                                        ),
                                        // ORDERED Cell (Input Text Box + Checkbox)
                                        Container(
                                          width: _colWidths['ordered']!,
                                          height: 35,
                                          alignment: Alignment.center,
                                          padding: const EdgeInsets.symmetric(horizontal: 4),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              right: BorderSide(
                                                color: _isDarkMode ? Colors.blueGrey.shade900 : const Color(0xFFF1F5F9),
                                                width: 1,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: SizedBox(
                                                  height: 26,
                                                  child: TextFormField(
                                                    key: ValueKey("ord_qty_${item['id']}_${_orderedQtys[item['id']] ?? (_orderedIds.contains(item['id']) ? pendingOrderQty : 0)}"),
                                                    initialValue: _orderedIds.contains(item['id'])
                                                        ? (_orderedQtys[item['id']] ?? pendingOrderQty).toString()
                                                        : "",
                                                    keyboardType: TextInputType.number,
                                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: (_orderedIds.contains(item['id']) &&
                                                              (_orderedQtys[item['id']] ?? pendingOrderQty) != pendingOrderQty)
                                                          ? const Color(0xFFEF4444)
                                                          : (_orderedIds.contains(item['id']) ? Colors.green.shade700 : textColor),
                                                    ),
                                                    decoration: InputDecoration(
                                                      isDense: true,
                                                      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                                      hintText: "0",
                                                      hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                                      filled: true,
                                                      fillColor: _isDarkMode
                                                          ? Colors.white.withValues(alpha: 0.05)
                                                          : Colors.grey.shade100,
                                                      border: OutlineInputBorder(
                                                        borderRadius: BorderRadius.circular(4),
                                                        borderSide: BorderSide(
                                                          color: (_orderedIds.contains(item['id']) &&
                                                                  (_orderedQtys[item['id']] ?? pendingOrderQty) != pendingOrderQty)
                                                              ? const Color(0xFFEF4444)
                                                              : Colors.grey.shade300,
                                                        ),
                                                      ),
                                                      focusedBorder: OutlineInputBorder(
                                                        borderRadius: BorderRadius.circular(4),
                                                        borderSide: BorderSide(
                                                          color: (_orderedIds.contains(item['id']) &&
                                                                  (_orderedQtys[item['id']] ?? pendingOrderQty) != pendingOrderQty)
                                                              ? const Color(0xFFEF4444)
                                                              : Colors.blue,
                                                          width: 1.5,
                                                        ),
                                                      ),
                                                    ),
                                                    onChanged: (val) {
                                                      final int? parsed = int.tryParse(val.trim());
                                                      setState(() {
                                                        if (parsed != null && parsed > 0) {
                                                          _orderedIds.add(item['id']);
                                                          _orderedQtys[item['id']] = parsed;
                                                        } else {
                                                          _orderedIds.remove(item['id']);
                                                          _orderedQtys.remove(item['id']);
                                                        }
                                                      });
                                                    },
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 2),
                                              SizedBox(
                                                width: 26,
                                                height: 26,
                                                child: Checkbox(
                                                  value: _orderedIds.contains(item['id']),
                                                  activeColor: Colors.green,
                                                  onChanged: (v) {
                                                    setState(() {
                                                      if (v == true) {
                                                        _orderedIds.add(item['id']);
                                                        _orderedQtys[item['id']] = pendingOrderQty > 0 ? pendingOrderQty : 1;
                                                      } else {
                                                        _orderedIds.remove(item['id']);
                                                        _orderedQtys.remove(item['id']);
                                                      }
                                                    });
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        // WHOLESALE Cell (Typable / Searchable Autocomplete Dropdown)
                                        SizedBox(
                                          width: _colWidths['wholesale']!,
                                          height: 35,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                            child: Builder(
                                              builder: (context) {
                                                final dynamic itemId = item['id'];
                                                final String defaultSupplier = (item['bestProfitWholesale'] ?? item['preferred_wholesale'] ?? "").toString().trim();
                                                final String rawSelected = _orderedSuppliers[itemId] ?? (defaultSupplier.isNotEmpty && defaultSupplier != '-' && defaultSupplier != 'General Wholesale' ? defaultSupplier : "");
                                                final String currentVal = rawSelected == "General Wholesale" ? "" : rawSelected;

                                                final Color bgCol = _getSupplierBgColor(currentVal, _isDarkMode);
                                                final Color txtCol = _getSupplierTextColor(currentVal, _isDarkMode);

                                                void applyWholesaleSelection(String supplier) {
                                                  setState(() {
                                                    _orderedSuppliers[itemId] = supplier;
                                                    if (supplier.trim().isNotEmpty) {
                                                      _orderedIds.add(itemId);
                                                      if (!_orderedQtys.containsKey(itemId) || _orderedQtys[itemId] == 0) {
                                                        _orderedQtys[itemId] = pendingOrderQty > 0 ? pendingOrderQty : 1;
                                                      }
                                                    }
                                                  });
                                                }

                                                return Autocomplete<String>(
                                                  initialValue: TextEditingValue(text: currentVal),
                                                  optionsBuilder: (TextEditingValue textEditingValue) {
                                                    final String query = textEditingValue.text.trim().toLowerCase();
                                                    final List<String> allOptions = [
                                                      if (defaultSupplier.isNotEmpty && defaultSupplier != '-' && defaultSupplier != 'General Wholesale') defaultSupplier,
                                                      ...pharmacy.suppliers,
                                                    ].where((s) => s.trim().isNotEmpty && s != 'General Wholesale').toSet().toList();

                                                    if (query.isEmpty) {
                                                      return allOptions;
                                                    }
                                                    return allOptions.where((String option) {
                                                      return option.toLowerCase().contains(query);
                                                    });
                                                  },
                                                  onSelected: (String selection) {
                                                    applyWholesaleSelection(selection);
                                                  },
                                                  optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<String> onSelected, Iterable<String> options) {
                                                    return Align(
                                                      alignment: Alignment.topLeft,
                                                      child: Material(
                                                        elevation: 6.0,
                                                        borderRadius: BorderRadius.circular(8),
                                                        color: _isDarkMode ? const Color(0xFF1E293B) : Colors.white,
                                                        child: Container(
                                                          width: 300, // Wide overlay so names fit on ONE LINE ONLY!
                                                          constraints: const BoxConstraints(maxHeight: 250),
                                                          decoration: BoxDecoration(
                                                            borderRadius: BorderRadius.circular(8),
                                                            border: Border.all(color: _isDarkMode ? Colors.blueGrey.shade700 : Colors.grey.shade300),
                                                          ),
                                                          child: ListView.separated(
                                                            padding: const EdgeInsets.symmetric(vertical: 4),
                                                            shrinkWrap: true,
                                                            itemCount: options.length,
                                                            separatorBuilder: (context, index) => Divider(height: 1, color: _isDarkMode ? Colors.white10 : Colors.grey.shade200),
                                                            itemBuilder: (BuildContext context, int index) {
                                                              final String option = options.elementAt(index);
                                                              final Color optBg = _getSupplierBgColor(option, _isDarkMode);
                                                              final Color optTxt = _getSupplierTextColor(option, _isDarkMode);

                                                              return InkWell(
                                                                onTap: () => onSelected(option),
                                                                child: Container(
                                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                                  child: Row(
                                                                    children: [
                                                                      Container(
                                                                        width: 12,
                                                                        height: 12,
                                                                        decoration: BoxDecoration(
                                                                          color: optBg,
                                                                          shape: BoxShape.circle,
                                                                          border: Border.all(color: optTxt, width: 1),
                                                                        ),
                                                                      ),
                                                                      const SizedBox(width: 8),
                                                                      Expanded(
                                                                        child: Text(
                                                                          option,
                                                                          maxLines: 1, // ONE NAME IN ONE LINE ONLY!
                                                                          overflow: TextOverflow.ellipsis,
                                                                          style: TextStyle(
                                                                            fontSize: 12,
                                                                            fontWeight: FontWeight.w700,
                                                                            color: _isDarkMode ? Colors.white : Colors.black87,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              );
                                                            },
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                                                    return TextFormField(
                                                      controller: controller,
                                                      focusNode: focusNode,
                                                      onFieldSubmitted: (val) {
                                                        onFieldSubmitted();
                                                        applyWholesaleSelection(val);
                                                      },
                                                      onChanged: (val) {
                                                        if (val.trim().isNotEmpty) {
                                                          applyWholesaleSelection(val);
                                                        } else {
                                                          setState(() {
                                                            _orderedSuppliers[itemId] = val;
                                                          });
                                                        }
                                                      },
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: txtCol,
                                                      ),
                                                      maxLines: 1,
                                                      decoration: InputDecoration(
                                                        isDense: true,
                                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                        hintText: "Wholesale",
                                                        hintStyle: TextStyle(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.normal),
                                                        filled: true,
                                                        fillColor: bgCol,
                                                        suffixIcon: const Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey),
                                                        suffixIconConstraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                                        border: OutlineInputBorder(
                                                          borderRadius: BorderRadius.circular(4),
                                                          borderSide: BorderSide(color: Colors.grey.shade300),
                                                        ),
                                                        enabledBorder: OutlineInputBorder(
                                                          borderRadius: BorderRadius.circular(4),
                                                          borderSide: BorderSide(color: currentVal.isEmpty ? Colors.grey.shade300 : txtCol.withValues(alpha: 0.5)),
                                                        ),
                                                        focusedBorder: OutlineInputBorder(
                                                          borderRadius: BorderRadius.circular(4),
                                                          borderSide: const BorderSide(color: Colors.blue, width: 1.5),
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                        if (_showRank)
                                          _Cell(
                                            warningDisplayVal,
                                            width: _colWidths['warning']!,
                                            align: TextAlign.center,
                                            fontWeight: FontWeight.bold,
                                            color: isWarningRed ? Colors.white : Colors.grey,
                                            isDarkMode: _isDarkMode,
                                            bgColor: isWarningRed ? const Color(0xFFEF4444) : null,
                                            borderColor: isWarningRed ? const Color(0xFFDC2626) : null,
                                          ),
                                        _Cell(
                                          _formatNumberString(lastSaleQty),
                                          width: _colWidths['lastSaleQty']!,
                                          align: TextAlign.center,
                                          fontWeight: FontWeight.bold,
                                          color: isLastSaleRed ? Colors.white : (_isDarkMode ? Colors.white : Colors.black87),
                                          isDarkMode: _isDarkMode,
                                          bgColor: isLastSaleRed ? const Color(0xFFEF4444) : null,
                                          borderColor: isLastSaleRed ? const Color(0xFFDC2626) : null,
                                        ),
                                        _Cell(
                                          _formatDate(item['lastSaleDate']),
                                          width: _colWidths['lastSaleDate']!,
                                          align: TextAlign.center,
                                          isDarkMode: _isDarkMode,
                                          bgColor: _isDateOnOrAfter(item['lastSaleDate']?.toString(), _getCutoffDateFromDays(_highlightLastSaleDays))
                                              ? (_isDarkMode ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2))
                                              : null,
                                          color: _isDateOnOrAfter(item['lastSaleDate']?.toString(), _getCutoffDateFromDays(_highlightLastSaleDays))
                                              ? (_isDarkMode ? Colors.white : const Color(0xFF991B1B))
                                              : null,
                                          fontWeight: _isDateOnOrAfter(item['lastSaleDate']?.toString(), _getCutoffDateFromDays(_highlightLastSaleDays))
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          borderColor: _isDateOnOrAfter(item['lastSaleDate']?.toString(), _getCutoffDateFromDays(_highlightLastSaleDays))
                                              ? Colors.red.shade400
                                              : null,
                                        ),
                                        _Cell(
                                          _formatNumberString(maxSingle4M),
                                          width: _colWidths['maxSingleTxn4M']!,
                                          align: TextAlign.center,
                                          fontWeight: FontWeight.bold,
                                          color: isMaxSingleRed ? Colors.white : (_isDarkMode ? Colors.tealAccent : const Color(0xFF0284C7)),
                                          isDarkMode: _isDarkMode,
                                          bgColor: isMaxSingleRed ? const Color(0xFFEF4444) : null,
                                          borderColor: isMaxSingleRed ? const Color(0xFFDC2626) : null,
                                        ),
                                        if (_showInterval) ...[
                                          _Cell(item['totalSale1Y']?.toString() ?? "0", width: _colWidths['totalSale1Y']!, align: TextAlign.center, isDarkMode: _isDarkMode),
                                          _Cell(
                                            _formatDate(item['firstPurchaseDate']),
                                            width: _colWidths['firstPurchaseDate']!,
                                            align: TextAlign.center,
                                            isDarkMode: _isDarkMode,
                                            bgColor: _isDateOnOrAfter(item['firstPurchaseDate']?.toString(), _getCutoffDateFromDays(_highlightFirstPurDays))
                                                ? (_isDarkMode ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2))
                                                : null,
                                            color: _isDateOnOrAfter(item['firstPurchaseDate']?.toString(), _getCutoffDateFromDays(_highlightFirstPurDays))
                                                ? (_isDarkMode ? Colors.white : const Color(0xFF991B1B))
                                                : null,
                                            fontWeight: _isDateOnOrAfter(item['firstPurchaseDate']?.toString(), _getCutoffDateFromDays(_highlightFirstPurDays))
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            borderColor: _isDateOnOrAfter(item['firstPurchaseDate']?.toString(), _getCutoffDateFromDays(_highlightFirstPurDays))
                                                ? Colors.red.shade400
                                                : null,
                                          ),
                                        ],
                                        _Cell(item['mappedName']?.toString() ?? item['mappedWholesaler']?.toString() ?? "", width: _colWidths['mappedName']!, isDarkMode: _isDarkMode),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: cardColor,
            border: Border(top: BorderSide(color: borderColor)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Consumer<PharmacyProvider>(
                builder: (context, p, _) {
                  int totalCount = _selectedTab == 'ORDER' ? _orderSuggestions.length : _specialOrders.length;
                  int tickedCount = _orderedIds.length;
                  return Row(
                    children: [
                      Text(
                        "Total Items: $totalCount",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: subTextColor),
                      ),
                      if (_selectedTab == 'ORDER') ...[
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: tickedCount > 0
                                ? (_isDarkMode ? Colors.green.withValues(alpha: 0.2) : const Color(0xFFDCFCE7))
                                : (_isDarkMode ? Colors.white10 : Colors.grey.shade100),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: tickedCount > 0 ? Colors.green : Colors.grey.shade300,
                            ),
                          ),
                          child: Text(
                            "Ticked: $tickedCount",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: tickedCount > 0 ? Colors.green : subTextColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
              if (_selectedTab == 'ORDER')
                ElevatedButton.icon(
                  onPressed: _saveSelectedOrdersToConfirmation,
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: const Text("SAVE TO ORDER CONFIRMATION", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 2,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSpecialOrdersView(PharmacyProvider pharmacy, Color textColor, Color subTextColor, Color cardColor, Color borderColor) {
    final List<Map<String, dynamic>> allItems = _specialOrders;

    final filtered = allItems.where((item) {
      for (String filterKey in _activeFilters.keys) {
        if (!_matchesFilter(item[filterKey], filterKey)) return false;
      }
      return true;
    }).toList();

    double totalWidth = 45 + _colWidths['agent']! + _colWidths['date']! + _colWidths['product']! + _colWidths['qty']! + _colWidths['phone']! + _colWidths['name']! + _colWidths['expecting_date']! + _colWidths['delete']!;

    const headerColor = Color(0xFF0F172A);
    final oddRowColor = _isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

    final ScrollController horizontalScroll = ScrollController();
    final ScrollController verticalScroll = ScrollController();

    return Column(
      children: [
        Expanded(
          child: Scrollbar(
            controller: horizontalScroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: horizontalScroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth,
                child: Column(
                  children: [
                    Container(
                      height: _headerHeight,
                      color: headerColor,
                      child: Row(
                        children: [
                          const SizedBox(width: 45, child: Center(child: Text("SL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)))),
                          _hdr("AGENT NAME", 'agent', width: _colWidths['agent']!),
                          _hdr("DATE", 'date', width: _colWidths['date']!),
                          _hdr("PRODUCT", 'product', width: _colWidths['product']!),
                          _hdr("QTY", 'qty', width: _colWidths['qty']!),
                          _hdr("PHONE NUMBER", 'phone', width: _colWidths['phone']!),
                          _hdr("NAME", 'name', width: _colWidths['name']!),
                          _hdr("EXPECTING DATE", 'expecting_date', width: _colWidths['expecting_date']!),
                          const SizedBox(width: 45, child: Center(child: Text("DEL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)))),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Scrollbar(
                        controller: verticalScroll,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: verticalScroll,
                          itemCount: filtered.length,
                          itemExtent: 36.0,
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            return Container(
                              key: ValueKey(item['entry_no'].toString() + item['product'].toString()),
                              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: borderColor)), color: index % 2 == 0 ? cardColor : oddRowColor),
                              child: Row(
                                children: [
                                  _Cell("${index + 1}", width: 45, align: TextAlign.center, color: _isDarkMode ? Colors.white38 : Colors.grey, isDarkMode: _isDarkMode),
                                  _Cell(item['agent']?.toString() ?? "", width: _colWidths['agent']!, fontWeight: FontWeight.bold, color: textColor, isDarkMode: _isDarkMode),
                                  _Cell(item['date']?.toString() ?? "", width: _colWidths['date']!, isDarkMode: _isDarkMode),
                                  _Cell(item['product']?.toString() ?? "", width: _colWidths['product']!, fontWeight: FontWeight.bold, color: textColor, isDarkMode: _isDarkMode),
                                  _Cell(item['qty']?.toString() ?? "0", width: _colWidths['qty']!, align: TextAlign.center, isDarkMode: _isDarkMode),
                                  _Cell(item['phone']?.toString() ?? "", width: _colWidths['phone']!, isDarkMode: _isDarkMode),
                                  _Cell(item['name']?.toString() ?? "", width: _colWidths['name']!, isDarkMode: _isDarkMode),
                                  _Cell(item['expecting_date']?.toString() ?? "", width: _colWidths['expecting_date']!, color: _isDarkMode ? Colors.blueAccent : Colors.blue.shade700, isDarkMode: _isDarkMode),
                                  SizedBox(
                                    width: 45,
                                    child: Center(
                                      child: IconButton(
                                        icon: const Icon(Icons.close, color: Colors.red, size: 16),
                                        onPressed: () async {
                                          bool? confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: const Text("Delete Entry?"),
                                                content: const Text("Do you want to delete this special order entry?"),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("No")),
                                                  ElevatedButton(
                                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                                      onPressed: () => Navigator.pop(ctx, true),
                                                      child: const Text("Yes", style: TextStyle(color: Colors.white))
                                                  ),
                                                ],
                                              )
                                          );

                                          if (confirm == true) {
                                            await pharmacy.deleteSpecialOrderItem(item['entry_no'], item['product']);
                                            _fetchData();
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _hdr(String title, String key, {double? width, int? flex, String columnType = 'text'}) {
    return _Hdr(
      title: title,
      tooltip: _colTooltips[key] ?? title,
      width: width ?? _colWidths[key]!,
      flex: flex,
      columnType: columnType,
      isDarkMode: _isDarkMode,
      onQuickFilter: (c, v) => _applyQuickFilter(key, c, v),
      onAdvancedTap: (pos) => _openAdvancedFilter(key, title, pos),
      onResize: (v) => setState(() => _colWidths[key] = v.clamp(40, 500)),
      onHeightResize: (v) => setState(() => _headerHeight = v.clamp(40, 150)),
    );
  }
}

class _Cell extends StatelessWidget {
  final String text; final double? width; final int? flex; final TextAlign align; final FontWeight fontWeight; final Color? color; final bool isDarkMode;
  final Color? bgColor; final Color? borderColor;

  const _Cell(this.text, {
    this.width,
    this.align = TextAlign.left,
    this.fontWeight = FontWeight.normal,
    this.color,
    this.isDarkMode = false,
    this.bgColor,
    this.borderColor,
  }) : flex = null;

  @override Widget build(BuildContext context) {
    Widget child = ERPTooltip(
      message: text,
      child: Container(
        width: width,
        height: 35,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: align == TextAlign.left ? Alignment.centerLeft : (align == TextAlign.center ? Alignment.center : Alignment.centerRight),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(
            right: BorderSide(color: borderColor ?? (isDarkMode ? Colors.blueGrey.shade900 : const Color(0xFFF1F5F9)), width: borderColor != null ? 1.5 : 1),
            left: borderColor != null ? BorderSide(color: borderColor!, width: 1.5) : BorderSide.none,
            top: borderColor != null ? BorderSide(color: borderColor!, width: 1.5) : BorderSide.none,
            bottom: borderColor != null ? BorderSide(color: borderColor!, width: 1.5) : BorderSide.none,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: fontWeight,
            color: color ?? (isDarkMode ? Colors.white70 : Colors.blueGrey.shade700),
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
    if (flex != null) return Expanded(flex: flex!, child: child);
    return child;
  }
}

class _Hdr extends StatefulWidget {
  final String title;
  final String? tooltip;
  final double width;
  final int? flex;
  final String columnType;
  final bool isDarkMode;
  final Function(String condition, String value) onQuickFilter;
  final Function(Offset position)? onAdvancedTap;
  final Function(double) onResize;
  final Function(double) onHeightResize;

  const _Hdr({
    required this.title,
    this.tooltip,
    required this.width,
    this.flex,
    this.columnType = 'text',
    this.isDarkMode = false,
    required this.onQuickFilter,
    this.onAdvancedTap,
    required this.onResize,
    required this.onHeightResize,
  });

  @override
  State<_Hdr> createState() => _HdrState();
}

class _HdrState extends State<_Hdr> {
  String _quickCondition = 'Contains';
  final TextEditingController _quickCtrl = TextEditingController();
  bool _isHovered = false;
  bool? _boolFilterValue; // null = All, true = Ticked, false = Unticked

  @override
  void initState() {
    super.initState();
    _quickCondition = widget.columnType == 'text' ? 'Contains' : 'Equals';
  }

  @override
  void dispose() {
    _quickCtrl.dispose();
    super.dispose();
  }

  String _getConditionSymbol() {
    switch (_quickCondition) {
      case 'Equals': return '=';
      case 'Does Not Equal': return '≠';
      case 'Contains': return 'inc';
      case 'Does Not Contain': return '!inc';
      case 'Begins With': return 'A..';
      case 'Ends With': return '..Z';
      default: return '=';
    }
  }

  void _showQuickConditionMenu(TapDownDetails details) async {
    final items = ['Equals', 'Does Not Equal', 'Contains', 'Does Not Contain', 'Begins With', 'Ends With'];

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx, details.globalPosition.dy + 10,
        details.globalPosition.dx, 0,
      ),
      items: items.map((e) => PopupMenuItem(
          value: e,
          height: 30,
          child: Text(e, style: const TextStyle(fontSize: 12))
      )).toList(),
    );

    if (result != null) {
      setState(() => _quickCondition = result);
      if (_quickCtrl.text.isNotEmpty) {
        widget.onQuickFilter(_quickCondition, _quickCtrl.text);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool showFilter = _isHovered || _quickCtrl.text.isNotEmpty || _boolFilterValue != null;
    Widget content = ERPTooltip(
      message: widget.tooltip ?? widget.title,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Container(
          width: widget.width,
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: Colors.blueGrey.shade800, width: 1),
            bottom: BorderSide(color: Colors.blueGrey.shade700, width: 1),
          ),
        ),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Text(
                          widget.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    Opacity(
                      opacity: showFilter ? 1.0 : 0.0,
                      child: GestureDetector(
                        onTapDown: (details) => widget.onAdvancedTap?.call(details.globalPosition),
                        child: const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.filter_alt_outlined, size: 14, color: Colors.tealAccent),
                        ),
                      ),
                    ),
                  ],
                ),
                Container(
                  height: 20,
                  margin: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  decoration: BoxDecoration(
                    color: widget.isDarkMode ? const Color(0xFF0F172A) : Colors.white,
                    border: Border.all(color: widget.isDarkMode ? Colors.blueGrey.shade800 : Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: widget.columnType == 'boolean'
                      ? Center(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                if (_boolFilterValue == null) {
                                  _boolFilterValue = true;
                                } else if (_boolFilterValue == true) {
                                  _boolFilterValue = false;
                                } else {
                                  _boolFilterValue = null;
                                }
                              });
                              if (_boolFilterValue == null) {
                                widget.onQuickFilter('Clear', '');
                              } else {
                                widget.onQuickFilter('Boolean', _boolFilterValue.toString());
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: Checkbox(
                                      tristate: true,
                                      value: _boolFilterValue,
                                      onChanged: (val) {
                                        setState(() {
                                          _boolFilterValue = val;
                                        });
                                        if (val == null) {
                                          widget.onQuickFilter('Clear', '');
                                        } else {
                                          widget.onQuickFilter('Boolean', val.toString());
                                        }
                                      },
                                      activeColor: Colors.green,
                                      checkColor: Colors.white,
                                      side: BorderSide(
                                        color: widget.isDarkMode ? Colors.white60 : Colors.grey.shade700,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _boolFilterValue == true
                                        ? "Ticked"
                                        : (_boolFilterValue == false ? "Unticked" : "All"),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: _boolFilterValue == true
                                          ? Colors.green
                                          : (_boolFilterValue == false
                                              ? Colors.red
                                              : (widget.isDarkMode ? Colors.white54 : Colors.grey.shade600)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : Row(
                          children: [
                            GestureDetector(
                              onTapDown: _showQuickConditionMenu,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                color: widget.isDarkMode ? Colors.blueGrey.shade800 : Colors.grey.shade200,
                                alignment: Alignment.center,
                                child: Text(
                                    _getConditionSymbol(),
                                    style: const TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold)
                                ),
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _quickCtrl,
                                cursorColor: Colors.black,
                                style: const TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.w600),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                                  border: InputBorder.none,
                                ),
                                onChanged: (val) {
                                  widget.onQuickFilter(_quickCondition, val);
                                  setState(() {});
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
                  onHorizontalDragUpdate: (details) => widget.onResize(widget.width + details.delta.dx),
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
            )
          ],
        ),
      ),
    ),
  );

    if (widget.flex != null) return Expanded(flex: widget.flex!, child: content);
    return content;
  }
}

class _AdvancedFilterPopup extends StatefulWidget {
  final String columnName;
  final String columnKey;
  final List<String> uniqueValues;
  final Map<String, dynamic>? initialFilter;

  const _AdvancedFilterPopup({
    required this.columnName,
    required this.columnKey,
    required this.uniqueValues,
    this.initialFilter,
  });

  @override
  State<_AdvancedFilterPopup> createState() => _AdvancedFilterPopupState();
}

class _AdvancedFilterPopupState extends State<_AdvancedFilterPopup> with SingleTickerProviderStateMixin {
  late bool _isNumeric;
  TabController? _tabController;

  // Checklist state
  final TextEditingController _searchCtrl = TextEditingController();
  List<String> _filteredValues = [];
  Set<String> _selectedValues = {};
  bool _selectAll = true;

  // Numeric filter state
  String _selectedNumericCond = "Between";
  late double _colMin;
  late double _colMax;
  late double _sliderFrom;
  late double _sliderTo;
  final TextEditingController _fromCtrl = TextEditingController();
  final TextEditingController _toCtrl = TextEditingController();
  final TextEditingController _singleNumCtrl = TextEditingController();

  final List<String> _numericConditions = [
    "Between",
    "Equals",
    "Does Not Equal",
    "Greater Than",
    "Greater Than Or Equal To",
    "Less Than",
    "Less Than Or Equal To",
  ];

  @override
  void initState() {
    super.initState();

    _isNumeric = _checkIsNumeric(widget.columnKey, widget.uniqueValues);

    if (_isNumeric) {
      _tabController = TabController(length: 2, vsync: this);

      List<double> numbers = widget.uniqueValues
          .map((v) => double.tryParse(v.trim()))
          .whereType<double>()
          .toList();

      if (numbers.isNotEmpty) {
        numbers.sort();
        _colMin = numbers.first;
        _colMax = numbers.last;
      } else {
        _colMin = 0.0;
        _colMax = 10000.0;
      }

      if (_colMin == _colMax) {
        _colMax = _colMin + 100.0;
      }

      if (widget.initialFilter != null && widget.initialFilter!['condition'] == 'Numeric') {
        _selectedNumericCond = widget.initialFilter!['subCondition'] ?? "Between";
        _sliderFrom = (widget.initialFilter!['from'] as num?)?.toDouble() ?? _colMin;
        _sliderTo = (widget.initialFilter!['to'] as num?)?.toDouble() ?? _colMax;
        if (widget.initialFilter!['val'] != null) {
          _singleNumCtrl.text = widget.initialFilter!['val'].toString();
        }
      } else {
        _sliderFrom = _colMin;
        _sliderTo = _colMax;
      }

      _fromCtrl.text = _sliderFrom.toStringAsFixed(0);
      _toCtrl.text = _sliderTo.toStringAsFixed(0);
    }

    _filteredValues = List.from(widget.uniqueValues);
    if (widget.initialFilter != null && widget.initialFilter!['selected'] != null) {
      _selectedValues = Set<String>.from(widget.initialFilter!['selected']);
      _selectAll = _selectedValues.length == widget.uniqueValues.length;
    } else {
      _selectedValues = Set<String>.from(widget.uniqueValues);
      _selectAll = true;
    }
  }

  bool _checkIsNumeric(String colKey, List<String> uniqueValues) {
    const numericKeys = {
      'mrp', 'pRate', 'packSize', 'min_level', 'max_level',
      'rank', 'stock', 'pending_order', 'ordered', 'warning',
      'lastSaleQty', 'maxSingleTxn4M', 'totalSale1Y', 'qty'
    };
    if (numericKeys.contains(colKey)) return true;

    int numCount = 0;
    int strCount = 0;
    for (String v in uniqueValues) {
      final clean = v.trim();
      if (clean.isEmpty || clean == '-') continue;
      if (double.tryParse(clean) != null) {
        numCount++;
      } else {
        strCount++;
      }
    }
    return numCount > 0 && strCount == 0;
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _searchCtrl.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _singleNumCtrl.dispose();
    super.dispose();
  }

  void _updateSliderFromText() {
    double? f = double.tryParse(_fromCtrl.text);
    double? t = double.tryParse(_toCtrl.text);
    if (f != null && t != null && f <= t) {
      setState(() {
        _sliderFrom = f.clamp(_colMin, _colMax);
        _sliderTo = t.clamp(_colMin, _colMax);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 270,
      height: 380,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.columnName,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF0F172A)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Tabs (ONLY IF THE COLUMN CONTAINS NUMBERS!)
          if (_isNumeric && _tabController != null)
            Container(
              height: 32,
              color: Colors.grey.shade100,
              child: TabBar(
                controller: _tabController,
                labelColor: const Color(0xFF2563EB),
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: const Color(0xFF2563EB),
                indicatorWeight: 2,
                labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                tabs: const [
                  Tab(text: "Values"),
                  Tab(text: "Numeric Filters"),
                ],
              ),
            ),

          // Tab Content
          Expanded(
            child: _isNumeric && _tabController != null
                ? TabBarView(
                    controller: _tabController,
                    children: [
                      _buildValuesTab(),
                      _buildNumericFiltersTab(),
                    ],
                  )
                : _buildValuesTab(),
          ),

          // Footer Actions
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, {'condition': 'Clear'}),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: const Size(60, 28),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: const Text("Clear Filter", style: TextStyle(color: Colors.black87, fontSize: 11)),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () {
                    if (_isNumeric && _tabController != null && _tabController!.index == 1) {
                      Navigator.pop(context, {
                        'condition': 'Numeric',
                        'subCondition': _selectedNumericCond,
                        'from': _sliderFrom,
                        'to': _sliderTo,
                        'val': double.tryParse(_singleNumCtrl.text) ?? 0.0,
                      });
                    } else {
                      Navigator.pop(context, {
                        'condition': 'Values',
                        'selected': _selectedValues.toList(),
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    minimumSize: const Size(60, 28),
                  ),
                  child: const Text("Apply", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValuesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(6.0),
          child: SizedBox(
            height: 32,
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: 11),
              decoration: InputDecoration(
                hintText: "Search values...",
                hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                prefixIcon: const Icon(Icons.search, size: 16),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
              ),
              onChanged: (v) => setState(() {
                _filteredValues = widget.uniqueValues.where((e) => e.toLowerCase().contains(v.toLowerCase())).toList();
              }),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              CheckboxListTile(
                title: const Text("(Select All)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                value: _selectAll,
                onChanged: (v) {
                  setState(() {
                    _selectAll = v ?? false;
                    if (_selectAll) {
                      _selectedValues = Set<String>.from(widget.uniqueValues);
                    } else {
                      _selectedValues.clear();
                    }
                  });
                },
                dense: true,
                visualDensity: VisualDensity.compact,
              ),
              const Divider(height: 1),
              ..._filteredValues.map((val) {
                return CheckboxListTile(
                  title: Text(val.isEmpty ? "(Blank)" : val, style: const TextStyle(fontSize: 11)),
                  value: _selectedValues.contains(val),
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedValues.add(val);
                      } else {
                        _selectedValues.remove(val);
                        _selectAll = false;
                      }
                    });
                  },
                  dense: true,
                  visualDensity: VisualDensity.compact,
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNumericFiltersTab() {
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Condition:", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedNumericCond,
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down, size: 18),
                style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600),
                items: _numericConditions.map((String c) {
                  return DropdownMenuItem<String>(
                    value: c,
                    child: Text(c),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _selectedNumericCond = v!),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_selectedNumericCond == "Between") ...[
            Row(
              children: [
                const Text("From ", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                Expanded(
                  child: SizedBox(
                    height: 28,
                    child: TextField(
                      controller: _fromCtrl,
                      style: const TextStyle(fontSize: 11),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
                      onSubmitted: (_) => _updateSliderFromText(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text("To ", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                Expanded(
                  child: SizedBox(
                    height: 28,
                    child: TextField(
                      controller: _toCtrl,
                      style: const TextStyle(fontSize: 11),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
                      onSubmitted: (_) => _updateSliderFromText(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 30,
              child: RangeSlider(
                values: RangeValues(_sliderFrom.clamp(_colMin, _colMax), _sliderTo.clamp(_colMin, _colMax)),
                min: _colMin,
                max: _colMax,
                divisions: (_colMax - _colMin) > 0 ? 100 : 1,
                activeColor: const Color(0xFF2563EB),
                onChanged: (RangeValues values) {
                  setState(() {
                    _sliderFrom = values.start;
                    _sliderTo = values.end;
                    _fromCtrl.text = _sliderFrom.toStringAsFixed(0);
                    _toCtrl.text = _sliderTo.toStringAsFixed(0);
                  });
                },
              ),
            ),
          ] else ...[
            const Text("Value:", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 4),
            SizedBox(
              height: 28,
              child: TextField(
                controller: _singleNumCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 11),
                decoration: const InputDecoration(
                  hintText: "Enter value...",
                  hintStyle: TextStyle(fontSize: 11),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
