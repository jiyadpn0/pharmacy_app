import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import '../../providers/pharmacy_provider.dart';
import '../../models/product_ranking.dart';
import '../../utils/search_debouncer.dart';
import '../../utils/theme_constants.dart';

class ProductRankingScreen extends StatefulWidget {
  const ProductRankingScreen({super.key});

  @override
  State<ProductRankingScreen> createState() => _ProductRankingScreenState();
}

enum ColumnType { text, numeric, date }

class _ProductRankingScreenState extends State<ProductRankingScreen> {
  final TextEditingController _monthsCtrl = TextEditingController(text: "1");
  final FocusNode _monthsFocusNode = FocusNode();
  List<ProductRanking> _allRankings = [];
  List<ProductRanking> _displayRankings = [];
  Set<String> _duplicateCriteriaKeys = {};
  bool _isLoading = true;
  String _lastUpdatedTime = "";
  bool _showMonths = true;
  bool _showFeatures = true;
  bool _showRanking = true;
  bool _includeCurrentMonth = false;
  bool _showOffer = true;

  // Filtering state
  final Map<String, Map<String, dynamic>> _activeFilters = {};

  String _rankFormula = "=MAX(C,D,A)+B";
  final TextEditingController _formulaCtrl = TextEditingController();
  bool _isFormulaValid = true;

  String _warningFormula = "IF(Y <= F, F, 0)";
  final TextEditingController _warningCtrl = TextEditingController();
  bool _isWarningValid = true;

  String _reOrderFormula = "W";
  final TextEditingController _reOrderCtrl = TextEditingController();
  bool _isReOrderValid = true;

  String _maxOrderFormula = "Y * 2";
  final TextEditingController _maxOrderCtrl = TextEditingController();

  List<Map<String, dynamic>> _rankRules = [];
  List<Map<String, dynamic>> _warningRules = [];
  List<Map<String, dynamic>> _reOrderRules = [];
  List<Map<String, dynamic>> _maxOrderRules = [];

  int _mavgInterval = 0; // 0 means ALL
  int _specialInterval = 0;

  final SearchDebouncer _debouncer = SearchDebouncer(milliseconds: 1000);
  String _lastSavedMonths = "1";

  String _cleanFormat(double val) {
    if (val == 0) return "0";
    if (val == val.toInt()) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(1);
  }

  String _sortCol = "OVERALL";
  bool _sortAscending = false;

  final Map<String, double> _colWidths = {};

  final ScrollController _leftScrollCtrl = ScrollController();
  final ScrollController _rightScrollCtrl = ScrollController();
  final ScrollController _horizontalScrollCtrl = ScrollController();

  final List<Map<String, dynamic>> _customMetricColumns = [];

  final List<String> _rankOptions = const [
    "1st HIGHER", "1st LOWER", "2nd HIGHER", "2nd LOWER", "3rd HIGHER", "3rd LOWER"
  ];

  final List<String> _metricOptions = const [
    "TOTAL MONTH SALE COUNTS",
    "SINGLE HIGHER SALE TOTAL",
    "TOTAL MONTH SALE",
    "MOVING AVERAGE"
  ];

  @override
  void initState() {
    super.initState();
    _leftScrollCtrl.addListener(() {
      if (_leftScrollCtrl.hasClients && _rightScrollCtrl.hasClients) {
        if (_rightScrollCtrl.offset != _leftScrollCtrl.offset) {
          _rightScrollCtrl.jumpTo(_leftScrollCtrl.offset);
        }
      }
    });
    _rightScrollCtrl.addListener(() {
      if (_rightScrollCtrl.hasClients && _leftScrollCtrl.hasClients) {
        if (_leftScrollCtrl.offset != _rightScrollCtrl.offset) {
          _leftScrollCtrl.jumpTo(_rightScrollCtrl.offset);
        }
      }
    });

    _monthsCtrl.addListener(_handleMonthsChange);
    _monthsFocusNode.addListener(_onMonthsFocusChange);
    _loadSettings();
  }

  void _onMonthsFocusChange() {
    if (!_monthsFocusNode.hasFocus) {
      _checkAndSaveMonthsChange();
    }
  }

  void _checkAndSaveMonthsChange() {
    final val = _monthsCtrl.text.trim();
    if (val.isNotEmpty && val != _lastSavedMonths) {
      _lastSavedMonths = val;
      _saveSettings();
    }
  }

  void _handleMonthsChange() {
    final val = _monthsCtrl.text.trim();
    if (val == _lastSavedMonths) return;
    
    _debouncer.run(() {
      if (mounted && _monthsCtrl.text.trim() != _lastSavedMonths) {
        _lastSavedMonths = _monthsCtrl.text.trim();
        _saveSettings();
      }
    });
  }

  @override
  void dispose() {
    _monthsCtrl.dispose();
    _monthsFocusNode.dispose();
    _formulaCtrl.dispose();
    _reOrderCtrl.dispose();
    _warningCtrl.dispose();
    _maxOrderCtrl.dispose();
    _debouncer.dispose();
    _leftScrollCtrl.dispose();
    _rightScrollCtrl.dispose();
    _horizontalScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMonths = prefs.getString('pr_months') ?? "1";
    
    setState(() {
      _lastSavedMonths = savedMonths;
      _monthsCtrl.text = savedMonths;
      _showFeatures = prefs.getBool('pr_feat') ?? true;
      _showMonths = prefs.getBool('pr_showm') ?? true;
      _showRanking = prefs.getBool('pr_showr') ?? true;
      _includeCurrentMonth = prefs.getBool('pr_live') ?? false;
      _showOffer = prefs.getBool('pr_showoffer') ?? true;
      _rankFormula = prefs.getString('pr_formula_v2') ?? "=MAX(C,D,A)+B";
      _formulaCtrl.text = _rankFormula;
      _reOrderFormula = prefs.getString('pr_reorder_f') ?? "W";
      _reOrderCtrl.text = _reOrderFormula;
      _warningFormula = prefs.getString('pr_warning_f') ?? "IF(Y <= F, F, 0)";
      _warningCtrl.text = _warningFormula;
      _maxOrderFormula = prefs.getString('pr_maxorder_f') ?? "Y * 2";
      _maxOrderCtrl.text = _maxOrderFormula;
      _mavgInterval = prefs.getInt('pr_mavg_int') ?? 0;
      _specialInterval = prefs.getInt('pr_spec_int') ?? 0;

      String? rankRulesJson = prefs.getString('pr_rank_rules_v1');
      if (rankRulesJson != null) {
        try {
          _rankRules = List<Map<String, dynamic>>.from(jsonDecode(rankRulesJson));
        } catch (_) {
          _rankRules = [];
        }
      } else {
        _rankRules = [];
      }

      String? warningRulesJson = prefs.getString('pr_warning_rules_v1');
      if (warningRulesJson != null) {
        try {
          _warningRules = List<Map<String, dynamic>>.from(jsonDecode(warningRulesJson));
        } catch (_) {
          _warningRules = [];
        }
      } else {
        _warningRules = [];
      }

      String? rulesJson = prefs.getString('pr_reorder_rules_v1');
      if (rulesJson != null) {
        try {
          _reOrderRules = List<Map<String, dynamic>>.from(jsonDecode(rulesJson));
        } catch (_) {
          _reOrderRules = [];
        }
      } else {
        _reOrderRules = [];
      }

      String? maxRulesJson = prefs.getString('pr_maxorder_rules_v1');
      if (maxRulesJson != null) {
        try {
          _maxOrderRules = List<Map<String, dynamic>>.from(jsonDecode(maxRulesJson));
        } catch (_) {
          _maxOrderRules = [];
        }
      } else {
        _maxOrderRules = [];
      }

      List<String>? savedColsJson = prefs.getStringList('pr_cols_dual_v8');
      if (savedColsJson != null) {
        _customMetricColumns.clear();
        for (var item in savedColsJson) {
          try {
            Map<String, dynamic> decoded = jsonDecode(item);
            _customMetricColumns.add({
              'rank': decoded['rank']?.toString() ?? "1st HIGHER",
              'metric': decoded['metric']?.toString() ?? "TOTAL MONTH SALE",
              'interval': decoded['interval'] ?? 0,
              'minRank': (decoded['minRank'] as num?)?.toDouble() ?? 0.0,
            });
          } catch (_) {}
        }
      }

      String? widthsJson = prefs.getString('pr_widths');
      if (widthsJson != null) {
        try {
          Map<String, dynamic> decoded = jsonDecode(widthsJson);
          decoded.forEach((key, value) {
            _colWidths[key] = (value as num).toDouble();
          });
        } catch (_) {}
      }
    });
    _loadCacheOrLightweight();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final monthsVal = _monthsCtrl.text.trim();
    await prefs.setString('pr_months', monthsVal);
    _lastSavedMonths = monthsVal;
    await prefs.setBool('pr_feat', _showFeatures);
    await prefs.setBool('pr_showm', _showMonths);
    await prefs.setBool('pr_showr', _showRanking);
    await prefs.setBool('pr_live', _includeCurrentMonth);
    await prefs.setBool('pr_showoffer', _showOffer);
    await prefs.setString('pr_formula_v2', _rankFormula);
    await prefs.setString('pr_reorder_f', _reOrderFormula);
    await prefs.setString('pr_warning_f', _warningFormula);
    await prefs.setString('pr_maxorder_f', _maxOrderFormula);
    await prefs.setInt('pr_mavg_int', _mavgInterval);
    await prefs.setInt('pr_spec_int', _specialInterval);
    await prefs.setString('pr_rank_rules_v1', jsonEncode(_rankRules));
    await prefs.setString('pr_warning_rules_v1', jsonEncode(_warningRules));
    await prefs.setString('pr_reorder_rules_v1', jsonEncode(_reOrderRules));
    await prefs.setString('pr_maxorder_rules_v1', jsonEncode(_maxOrderRules));

    List<String> encodedCols = _customMetricColumns.map((m) => jsonEncode(m)).toList();
    await prefs.setStringList('pr_cols_dual_v8', encodedCols);
    await prefs.setString('pr_widths', jsonEncode(_colWidths));
  }

  Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pr_last_updated_time', _lastUpdatedTime);
      
      List<String> encodedList = _allRankings.map((r) => jsonEncode(r.toJson())).toList();
      await prefs.setStringList('pr_cached_rankings_v2', encodedList);
    } catch (e) {
      debugPrint("Error saving ranking cache: $e");
    }
  }

  Future<void> _loadCacheOrLightweight() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTime = prefs.getString('pr_last_updated_time') ?? "";
    final cachedList = prefs.getStringList('pr_cached_rankings_v2');

    if (cachedList != null && cachedList.isNotEmpty) {
      try {
        List<ProductRanking> loaded = [];
        for (var item in cachedList) {
          loaded.add(ProductRanking.fromJson(jsonDecode(item)));
        }
        if (mounted) {
          setState(() {
            _lastUpdatedTime = savedTime;
            _allRankings = loaded;
            _calculateRankings();
            _applyFilters();
            _isLoading = false;
          });
        }
        return;
      } catch (e) {
        debugPrint("Error reading ranking cache: $e");
      }
    }

    try {
      final provider = Provider.of<PharmacyProvider>(context, listen: false);
      int months = int.tryParse(_monthsCtrl.text) ?? 1;
      final lightData = await provider.getLightweightProductList(monthsCount: months);
      if (mounted) {
        setState(() {
          _lastUpdatedTime = savedTime;
          _allRankings = lightData;
          _calculateRankings();
          _applyFilters();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading lightweight products: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _performAnalysis() async {
    int months = int.tryParse(_monthsCtrl.text) ?? 1;
    if (months > 24) {
      months = 24;
      _monthsCtrl.text = "24";
    }
    await _saveSettings();

    setState(() => _isLoading = true);

    final provider = Provider.of<PharmacyProvider>(context, listen: false);

    try {
      final data = await provider.getDynamicProductRanking(months, rollingMode: _includeCurrentMonth);

      if (mounted) {
        final nowStr = DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now());
        setState(() {
          _allRankings = data;
          _lastUpdatedTime = nowStr;
          _calculateRankings();
          _applyFilters();
        });
        provider.updateCachedRankings(_allRankings);
        await _saveCache();
      }
    } catch (e) {
      debugPrint("Product Ranking Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error calculating rankings: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _exportToExcel() async {
    if (_displayRankings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No data to export!")));
      return;
    }

    String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Select where to save Product Ranking Excel:',
      fileName: 'product_ranking_export.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (outputFile != null) {
      setState(() => _isLoading = true);
      try {
        final provider = Provider.of<PharmacyProvider>(context, listen: false);
        final bytes = await provider.exportProductRankingToExcelBytes(_displayRankings, _customMetricColumns);

        if (bytes != null) {
          final file = File(outputFile);
          await file.writeAsBytes(bytes);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text("Ranking data exported successfully!")));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text("Export failed: $e")));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilters() {
    if (_activeFilters.isEmpty) {
      setState(() => _displayRankings = List.from(_allRankings));
      return;
    }

    setState(() {
      _displayRankings = _allRankings.where((r) {
        bool match = true;
        _activeFilters.forEach((colKey, filter) {
          if (!match) return;

          dynamic rawVal = _getValueForCol(r, colKey);
          
          if (filter['mode'] == 'values') {
            List<String> allowed = List<String>.from(filter['selected_values']);
            String cellVal = rawVal?.toString() ?? "";
            if (!allowed.contains(cellVal)) match = false;
            return;
          }

          String condition = filter['condition'];
          if (condition == 'Clear' || condition == 'None') return;

          ColumnType type = filter['type'] ?? ColumnType.text;

          if (type == ColumnType.text) {
            String cellStr = rawVal?.toString().toLowerCase() ?? "";
            String filterStr = (filter['value'] ?? filter['value1'])?.toString().toLowerCase() ?? "";

            if (condition == 'Equals' && cellStr != filterStr) {
              match = false;
            } else if (condition == 'Does Not Equal' && cellStr == filterStr) match = false;
            else if (condition == 'Contains' && !cellStr.contains(filterStr)) match = false;
            else if (condition == 'Does Not Contain' && cellStr.contains(filterStr)) match = false;
            else if (condition == 'Begins With' && !cellStr.startsWith(filterStr)) match = false;
            else if (condition == 'Ends With' && !cellStr.endsWith(filterStr)) match = false;
          } 
          else if (type == ColumnType.numeric) {
            double cellNum = double.tryParse(rawVal?.toString() ?? "0") ?? 0.0;
            double v1 = double.tryParse((filter['value'] ?? filter['value1'])?.toString() ?? "0") ?? 0.0;

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
        });
        return match;
      }).toList();

      // Apply Sorting
      _displayRankings.sort((a, b) {
        dynamic valA = _getValueForCol(a, _sortCol);
        dynamic valB = _getValueForCol(b, _sortCol);

        int cmp;
        if (valA is num && valB is num) {
          cmp = valA.compareTo(valB);
        } else {
          cmp = (valA?.toString() ?? "").toLowerCase().compareTo(valB?.toString().toLowerCase() ?? "");
        }
        return _sortAscending ? cmp : -cmp;
      });
    });
  }

  dynamic _getValueForCol(ProductRanking r, String colKey) {
    if (colKey == 'STATUS') return r.isActive ? "ACTIVE" : "INACTIVE";
    if (colKey == 'NAME') return r.name;
    if (colKey == 'PACK' || colKey == 'P') return r.pack;
    if (colKey == 'PATENT') return r.patent;
    if (colKey == 'BRAND') return r.category;
    if (colKey == 'RACK') return r.rack;
    if (colKey == 'MRP') return r.mrp;
    if (colKey == 'PRATE') return r.pRate;
    if (colKey == 'CONTENT') return r.genericName;
    if (colKey == 'SUPP') return r.preferredWholesale;
    if (colKey == 'OFFER') return r.offer;
    if (colKey == 'B') return r.specialOrders;
    if (colKey == 'MAVG' || colKey == 'A') return r.mavg;
    if (colKey == 'SPECIAL') return r.specialOrders;
    if (colKey == 'LASTSALE' || colKey == 'C') return r.lastSaleQty;
    if (colKey == 'OVERALL' || colKey == 'W') return r.weightedScore;
    if (colKey == 'WARNING' || colKey == 'X') return r.warningScore;
    if (colKey == 'REORDER' || colKey == 'Y') return r.reOrderScore;
    if (colKey == 'MAXORDER' || colKey == 'Z') return r.maxOrderLevel;
    
    // Monthly stats... (unchanged)
    if (colKey.startsWith('M')) {
      final parts = colKey.split('_');
      int mIdx = int.tryParse(parts[0].substring(1)) ?? -1;
      if (mIdx != -1 && mIdx < r.monthlyStats.length) {
        final stat = r.monthlyStats[mIdx];
        if (parts[1] == 'C') return stat.saleCount;
        if (parts[1] == 'H') return stat.higherSale;
        if (parts[1] == 'M') return stat.monthSale;
      }
    }

    // Custom Columns: D, E, F ...
    if (colKey.length == 1 && colKey.codeUnitAt(0) >= 68) {
       return r.customCriteria[colKey] ?? 0.0;
    }

    return null;
  }

  void _openAdvancedFilterDialog(String colKey, String label, ColumnType type, Offset position) async {
    List<String> uniqueVals = _allRankings.map((r) => _getValueForCol(r, colKey)?.toString() ?? "").toSet().toList();
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
                columnName: label,
                columnType: type,
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
      _applyFilters();
    }
  }

  void _applyQuickFilter(String col, String condition, String value) {
    setState(() {
      if (condition == 'Clear' || value.isEmpty) {
        _activeFilters.remove(col);
      } else {
        _activeFilters[col] = {
          'mode': 'quick',
          'condition': condition,
          'value': value,
          'type': _getColType(col),
        };
      }
    });
    _applyFilters();
  }

  ColumnType _getColType(String col) {
    if (col == 'NAME' || col == 'STATUS' || col == 'PATENT' || col == 'BRAND' || col == 'RACK' || col == 'CONTENT' || col == 'SUPP' || col == 'OFFER') return ColumnType.text;
    return ColumnType.numeric;
  }

  void _calculateRankings() {
    ProductRankingCalculator.calculateRankings(
      rankings: _allRankings,
      rankFormula: _rankFormula,
      rankRules: _rankRules,
      reOrderFormula: _reOrderFormula,
      reOrderRules: _reOrderRules,
      warningFormula: _warningFormula,
      warningRules: _warningRules,
      maxOrderFormula: _maxOrderFormula,
      maxOrderRules: _maxOrderRules,
      customMetricColumns: _customMetricColumns,
      mavgInterval: _mavgInterval,
      specialInterval: _specialInterval,
    );

    if (mounted) {
      setState(() {
        _isFormulaValid = true;
        _isReOrderValid = true;
        _isWarningValid = true;
        _duplicateCriteriaKeys = _getDuplicateCriteriaKeys();
        _allRankings.sort((a, b) => b.weightedScore.compareTo(a.weightedScore));
        _applyFilters();
      });
    }
  }

  double _evaluateRules(List<Map<String, dynamic>> rules, Map<String, double> vars) {
    const double eps = 0.0001;
    for (var rule in rules) {
      try {
        String varName = rule['var'] ?? 'Y';
        String op = rule['op'] ?? '>=';
        
        // Evaluate Value and Result as full formulas to allow variables like 'A' or 'Y*0.5'
        double target = _evaluateFormula(rule['val']?.toString() ?? '0', vars) ?? 0.0;
        double result = _evaluateFormula(rule['res']?.toString() ?? '0', vars) ?? 0.0;

        double leftValue = vars[varName] ?? 0.0;
        
        bool trigger = false;
        switch (op) {
          case '>': trigger = leftValue > (target + eps); break;
          case '<': trigger = leftValue < (target - eps); break;
          case '>=': trigger = leftValue >= (target - eps); break;
          case '<=': trigger = leftValue <= (target + eps); break;
          case '=': trigger = (leftValue - target).abs() < eps; break;
        }
        
        if (trigger) return result;
      } catch (_) {}
    }
    return 0.0;
  }

  void _validateFormulaSubmission(String formula, String title) {
    if (_allRankings.isEmpty) return;
    
    Map<String, double> vars = {};
    vars['P'] = 0.0; // Pack Size
    vars['A'] = 0.0; vars['B'] = 0.0;
    vars['C'] = 0.0; // Last Sale Qty
    vars['L'] = 0.0; // Last Sale Qty (Legacy)
    for (int i = 0; i < _customMetricColumns.length; i++) {
      vars[String.fromCharCode(68 + i)] = 0.0; // Shift to D, E, F...
    }
    if (title == "RE-ORDER LEVEL") {
      vars['W'] = 0.0;
    } else if (title == "WARNING") {
      vars['W'] = 0.0;
      vars['Y'] = 0.0;
    } else if (title == "MAX ORDER LEVEL") {
      vars['W'] = 0.0;
      vars['Y'] = 0.0;
      vars['X'] = 0.0;
    }

    String clean = formula.toUpperCase().replaceAll(' ', '').replaceAll('=', '');
    // Ignore Excel Keywords
    final List<String> keywords = ['MAX', 'MIN', 'AVERAGE', 'IF'];
    for (var kw in keywords) {
      clean = clean.replaceAll(kw, '');
    }
    // Remove all numbers and operators
    clean = clean.replaceAll(RegExp(r'[0-9+\-*/(),.><=!]'), '');
    
    for (int i = 0; i < clean.length; i++) {
      String letter = clean[i];
      if (!vars.containsKey(letter)) {
         showDialog(
           context: context,
           builder: (ctx) => AlertDialog(
             title: Row(children: [const Icon(Icons.warning_amber_rounded, color: Colors.orange), const SizedBox(width: 10), Text("Unknown Column: $letter")]),
             content: Text("The formula for $title uses character '$letter', which isn't a recognized column.\n\n"
                 "Available columns are: ${vars.keys.join(', ')}"),
             actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
           ),
         );
         return;
      }
    }
  }

  // Clean parameter splitter preventing comma clashes inside nested formulas
  List<String> _splitParams(String s) {
    List<String> res = [];
    int depth = 0;
    StringBuffer sb = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      String char = s[i];
      if (char == '(') {
        depth++;
      } else if (char == ')') depth--;
      if (char == ',' && depth == 0) {
        res.add(sb.toString().trim());
        sb.clear();
      } else {
        sb.write(char);
      }
    }
    res.add(sb.toString().trim());
    return res;
  }

  static final RegExp _funcRegex = RegExp(r"(AVERAGE|MAX|MIN|IF)\(([^()]+)\)");
  static final RegExp _parenRegex = RegExp(r"\(([^()]+)\)");
  static final Map<String, RegExp> _varRegexCache = {};

  static RegExp _getVarRegex(String k) {
    return _varRegexCache.putIfAbsent(k, () => RegExp('(?<![A-Z0-9\\.])$k(?![A-Z0-9\\.])'));
  }

  double? _evaluateFormula(String formula, Map<String, double> vars) {
    try {
      // 1. Pre-process: Remove spaces and ONLY the leading '=' if it exists
      String s = formula.toUpperCase().replaceAll(' ', '');
      if (s.startsWith('=')) s = s.substring(1);
      if (s.isEmpty) return 0.0;

      // 2. Resolve Variables with strict boundary checking
      List<String> sortedKeys = vars.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
      for (var k in sortedKeys) {
        s = s.replaceAll(_getVarRegex(k), vars[k].toString());
      }

      return _recursiveEval(s);
    } catch (e) {
      debugPrint("Formula Error: $e");
      return null;
    }
  }

  double? _recursiveEval(String s) {
    int safety = 0;

    while (safety < 50) {
      safety++;
      
      // A. Innermost Functions
      var fMatch = _funcRegex.firstMatch(s);
      if (fMatch != null) {
        String name = fMatch.group(1)!;
        List<String> parts = _splitParams(fMatch.group(2)!);
        double result = 0.0;

        if (name == "IF") {
          if (parts.length >= 3) {
            double cond = _recursiveEval(parts[0]) ?? 0.0;
            result = (cond > 0.5) ? (_recursiveEval(parts[1]) ?? 0.0) : (_recursiveEval(parts[2]) ?? 0.0);
          }
        } else {
          List<double> vals = parts.map((p) => _recursiveEval(p) ?? 0.0).toList();
          if (vals.isNotEmpty) {
            if (name == "MAX") {
              result = vals.reduce(max);
            } else if (name == "MIN") result = vals.reduce(min);
            else if (name == "AVERAGE") result = vals.reduce((a, b) => a + b) / vals.length;
          }
        }
        s = s.replaceRange(fMatch.start, fMatch.end, result.toString());
        continue;
      }

      // B. Innermost Parentheses
      var pMatch = _parenRegex.firstMatch(s);
      if (pMatch != null) {
        double res = _recursiveEval(pMatch.group(1)!) ?? 0.0;
        s = s.replaceRange(pMatch.start, pMatch.end, res.toString());
        continue;
      }

      break;
    }

    return _evaluateFinalMath(s);
  }

  double? _evaluateFinalMath(String expr) {
    const double eps = 0.0001;
    
    // 1. Resolve logical comparison (IF condition or standalone comparison)
    // We search for operators in a specific order to avoid partial matching (e.g., <= before <)
    final List<String> ops = [">=", "<=", "!=", ">", "<", "="];
    for (var op in ops) {
      if (expr.contains(op)) {
        int idx = expr.indexOf(op);
        // Trim to handle cases like " 3.0 <= 3.0 "
        String leftPart = expr.substring(0, idx).trim();
        String rightPart = expr.substring(idx + op.length).trim();
        
        // Evaluate both sides as pure math before comparing
        double left = _evaluateBasicMath(leftPart) ?? 0.0;
        double right = _evaluateBasicMath(rightPart) ?? 0.0;
        
        bool res = false;
        if (op == ">") {
          res = left > (right + eps);
        } else if (op == "<") res = left < (right - eps);
        else if (op == ">=") res = left >= (right - eps);
        else if (op == "<=") res = left <= (right + eps);
        else if (op == "=") res = (left - right).abs() < eps;
        else if (op == "!=") res = (left - right).abs() >= eps;
        
        return res ? 1.0 : 0.0;
      }
    }

    // 2. If no comparison, evaluate as standard math (+ - * /)
    return _evaluateBasicMath(expr);
  }

  double? _evaluateBasicMath(String expr) {
    try {
      // Multiplication / Division
      // Regex updated to support scientific notation (e.g. 1.2e-5)
      RegExp mdRegex = RegExp(r"(-?[0-9.]+(?:[eE]-?[0-9]+)?)([*]" r"[/])(-?[0-9.]+(?:[eE]-?[0-9]+)?)");
      int s1 = 0;
      while (mdRegex.hasMatch(expr) && s1 < 20) {
        s1++;
        expr = expr.replaceAllMapped(mdRegex, (m) {
          double a = double.tryParse(m.group(1)!) ?? 0;
          double b = double.tryParse(m.group(3)!) ?? 0;
          return m.group(2) == "*" ? (a * b).toString() : (b.abs() < 1e-12 ? "0" : (a / b).toString());
        });
      }

      // Addition / Subtraction
      List<String> tokens = [];
      String cur = "";
      for (int i = 0; i < expr.length; i++) {
        String c = expr[i];
        // Check if '-' is a sign or an operator (allowing for scientific notation like 1e-5)
        bool isSign = (c == "-" && (i == 0 || "+-*/".contains(expr[i - 1]) || (i > 0 && expr[i - 1].toUpperCase() == "E")));
        
        if (isSign) { 
          cur += c; 
          continue; 
        }
        
        if ("+-".contains(c)) { 
          if (cur.isNotEmpty) tokens.add(cur); 
          tokens.add(c); 
          cur = ""; 
        }
        else { 
          cur += c; 
        }
      }
      if (cur.isNotEmpty) tokens.add(cur);

      double res = 0.0;
      String op = "+";
      for (var t in tokens) {
        if (t == "+" || t == "-") {
          op = t;
        } else {
          double v = double.tryParse(t) ?? 0.0;
          res = (op == "+") ? res + v : res - v;
        }
      }
      return res;
    } catch (_) { return null; }
  }



  Set<String> _getDuplicateCriteriaKeys() {
    List<String> keys = [];
    // A: MAVG
    keys.add("MOVING AVERAGE_NONE_$_mavgInterval");
    // B: SPECIAL
    keys.add("SPECIAL ORDERS_NONE_$_specialInterval");
    
    for (var col in _customMetricColumns) {
       keys.add("${col['metric']}_${col['rank']}_${col['interval']}");
    }

    Map<String, int> counts = {};
    for (var k in keys) {
      counts[k] = (counts[k] ?? 0) + 1;
    }
    
    return counts.entries.where((e) => e.value > 1).map((e) => e.key).toSet();
  }

  String _getMovingAverage(ProductRanking r, {int interval = 0}) {
    if (r.monthlyStats.isEmpty) return "0.0";
    
    List<MonthlyStat> stats = r.monthlyStats;
    if (interval > 0) {
      stats = stats.take(interval).toList();
    }
    
    List<double> chronoSales = stats.map((e) => e.monthSale).toList().reversed.toList();

    int firstSaleIndex = 0;
    bool hasSales = false;
    for (int i = 0; i < chronoSales.length; i++) {
      if (chronoSales[i] != 0) { // Changed from > 0 to != 0 to account for net sales being negative or positive
        firstSaleIndex = i;
        hasSales = true;
        break;
      }
    }

    if (!hasSales) return "0";

    List<double> activeSales = chronoSales.sublist(firstSaleIndex);
    double totalSum = activeSales.fold(0.0, (a, b) => a + b);
    int divisor = activeSales.length < 3 ? 3 : activeSales.length;

    return _cleanFormat(totalSum / divisor);
  }

  String _calculateCustomMetric({
    required ProductRanking product,
    required String rankPart,
    required String metricPart,
    int interval = 0,
    double minRank = 0.0,
  }) {
    if (product.monthlyStats.isEmpty) {
      if (minRank > 0) return _cleanFormat(minRank);
      return "0";
    }

    List<MonthlyStat> stats = product.monthlyStats;
    if (interval > 0) {
      stats = stats.take(interval).toList();
    }

    double resVal = 0.0;

    if (metricPart == "MOVING AVERAGE" || metricPart == "TOTAL SALE AVERAGE") {
      resVal = double.tryParse(_getMovingAverage(product, interval: interval)) ?? 0.0;
    } else {
      List<double> monthSales = stats.map((e) => e.monthSale).toList();
      List<double> higherSales = stats.map((e) => e.higherSale).toList();
      List<int> saleCounts = stats.map((e) => e.saleCount).toList();

      monthSales.sort();
      higherSales.sort();
      saleCounts.sort();

      int rankIndex = 1;
      if (rankPart.startsWith("2")) rankIndex = 2;
      if (rankPart.startsWith("3")) rankIndex = 3;

      bool isAscending = rankPart.contains("LOWER");

      double getDesc(List<double> l, int rnk) => l.length >= rnk ? l[l.length - rnk] : 0.0;
      double getAsc(List<double> l, int rnk) => l.length >= rnk ? l[rnk - 1] : 0.0;
      int getDescInt(List<int> l, int rnk) => l.length >= rnk ? l[l.length - rnk] : 0;
      int getAscInt(List<int> l, int rnk) => l.length >= rnk ? l[rnk - 1] : 0;

      if (metricPart == "TOTAL MONTH SALE COUNTS") {
        resVal = (isAscending ? getAscInt(saleCounts, rankIndex) : getDescInt(saleCounts, rankIndex)).toDouble();
      } else if (metricPart == "SINGLE HIGHER SALE TOTAL") {
        resVal = isAscending ? getAsc(higherSales, rankIndex) : getDesc(higherSales, rankIndex);
      } else if (metricPart == "TOTAL MONTH SALE") {
        resVal = isAscending ? getAsc(monthSales, rankIndex) : getDesc(monthSales, rankIndex);
      }
    }

    if (minRank > 0 && resVal < minRank) {
      resVal = minRank;
    }

    return _cleanFormat(resVal);
  }

  String _getColKey(Map<String, dynamic> col) {
    return "${col['rank']}_${col['metric']}";
  }

  double _getW(String key, double defaultWidth) {
    return _colWidths[key] ?? defaultWidth;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.cardBg,
        toolbarHeight: 60,
        titleSpacing: 12,
        automaticallyImplyLeading: false,
        title: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Icon(Icons.analytics_outlined, color: c.primaryText, size: 24),
              const SizedBox(width: 10),
              Text("Product Ranking & Analysis", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.primaryText, letterSpacing: -0.5)),
              const SizedBox(width: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("PERIOD (MONTHS):", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF566573))),
                    const SizedBox(width: 8),
                    Container(
                      width: 42,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: const Color(0xFFF2F4F4), borderRadius: BorderRadius.circular(4)),
                      child: TextField(
                        controller: _monthsCtrl,
                        focusNode: _monthsFocusNode,
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF2E86C1)),
                        decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                        onSubmitted: (_) {
                          _monthsFocusNode.unfocus();
                          _checkAndSaveMonthsChange();
                        },
                        onEditingComplete: () {
                          _monthsFocusNode.unfocus();
                          _checkAndSaveMonthsChange();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _performAnalysis,
                icon: _isLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.analytics_rounded, size: 16),
                label: Text(
                  _isLoading ? "ANALYZING..." : "ANALYZE RANKINGS",
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0288D1),
                  foregroundColor: Colors.white,
                  elevation: 1,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4F8),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFD0D7DE)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.access_time_rounded, size: 14, color: Color(0xFF57606A)),
                    const SizedBox(width: 6),
                    Text(
                      _lastUpdatedTime.isEmpty ? "LAST UPDATED: NOT ANALYZED YET" : "LAST UPDATED: $_lastUpdatedTime",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _lastUpdatedTime.isEmpty ? Colors.orange.shade800 : const Color(0xFF24292F),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _appBarToggle("OFFERS", _showOffer, (v) {
                setState(() => _showOffer = v ?? false);
                _saveSettings();
              }),
              _appBarToggle("PREV 30 DAYS MODE", _includeCurrentMonth, (v) {
                setState(() => _includeCurrentMonth = v ?? false);
                _saveSettings();
                _performAnalysis();
              }),
              const SizedBox(width: 4),
              _appBarToggle("FEATURES", _showFeatures, (v) {
                setState(() => _showFeatures = v ?? true);
                _saveSettings();
              }),
              const SizedBox(width: 4),
              _appBarToggle("MONTHS", _showMonths, (v) {
                setState(() => _showMonths = v ?? true);
                _saveSettings();
              }),
              const SizedBox(width: 4),
              _appBarToggle("RANKING", _showRanking, (v) {
                setState(() => _showRanking = v ?? true);
                _saveSettings();
              }),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _exportToExcel,
                icon: const Icon(Icons.download, size: 16),
                label: const Text("EXPORT EXCEL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade200, height: 1),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF2E86C1)))
          : _buildSplitGrid(),
    );
  }

  Widget _appBarToggle(String label, bool value, Function(bool?) onChanged) {
    return Row(
      children: [
        Transform.scale(
          scale: 0.8,
          child: Checkbox(
            value: value,
            activeColor: const Color(0xFF2E86C1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            onChanged: onChanged,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF566573), letterSpacing: 0.5)),
      ],
    );
  }

  Widget _buildSplitGrid() {
    double leftPaneW = _getW('NAME', 200) + _getW('PACK', 45) + 2;

    double staticAlwaysWidth = _getW('STATUS', 75);
    if (_showOffer) {
      staticAlwaysWidth += _getW('SUPP', 110) + _getW('OFFER', 45);
    }
    
    double featuresWidth = _showFeatures ? (_getW('PATENT', 85) + _getW('BRAND', 85) + _getW('RACK', 45) + _getW('MRP', 65) + _getW('PRATE', 65) + _getW('CONTENT', 110)) : 0;
    double fixedMetricsWidth = 0; 

    double dynamicMonthsWidth = 0;
    if (_showMonths && _allRankings.isNotEmpty) {
      for (int i = 0; i < _allRankings.first.monthlyStats.length; i++) {
        dynamicMonthsWidth += (_getW('M${i}_C', 45) + _getW('M${i}_H', 45) + _getW('M${i}_M', 50) + 1.0);
      }
    }

    double customColsWidth = 0;
    if (_showRanking) {
      customColsWidth = 40.0 + _getW('MAVG', 130) + _getW('SPECIAL', 130) + _getW('LASTSALE', 130);
      for (var col in _customMetricColumns) {
        customColsWidth += _getW(_getColKey(col), 130.0);
      }
    }

    double overallRankWidth = _showRanking ? (_getW('OVERALL', 110) + _getW('WARNING', 110) + _getW('REORDER', 110) + _getW('MAXORDER', 130)) : 0;

    const double rightBuffer = 300.0;
    double totalRightWidth = staticAlwaysWidth + featuresWidth + fixedMetricsWidth + dynamicMonthsWidth + customColsWidth + overallRankWidth + rightBuffer;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // LEFT PANE
        Container(
          width: leftPaneW,
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(2, 0))],
            border: Border(right: BorderSide(color: Colors.grey.shade300, width: 1)),
          ),
          child: Column(
            children: [
              Container(
                height: 140,
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFB),
                  border: Border(bottom: BorderSide(color: Color(0xFFEBEDEF), width: 1)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _staticHdr('NAME', "PRODUCT NAME", 200, type: ColumnType.text),
                    _staticHdr('PACK', "[P] PACK", 45, type: ColumnType.numeric),
                  ],
                ),
              ),
              _buildLeftFilterRow(),
              Expanded(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                  child: ListView.builder(
                    controller: _leftScrollCtrl,
                    itemCount: _displayRankings.length,
                    itemBuilder: (ctx, i) {
                      final r = _displayRankings[i];
                      final Color rowColor = i % 2 == 0 ? const Color(0xFFD9E1F2) : const Color(0xFFB4C6E7);
                      return Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: rowColor,
                          border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.5))),
                        ),
                        child: Row(
                          children: [
                            _cellText(r.name, _getW('NAME', 200), bold: true, isPrimary: true),
                            _cellText(r.pack.toString(), _getW('PACK', 45), center: true, isPrimary: true, bold: true),
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

        // RIGHT PANE
        Expanded(
          child: Scrollbar(
            controller: _horizontalScrollCtrl,
            thumbVisibility: true,
            thickness: 8,
            radius: const Radius.circular(4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: _horizontalScrollCtrl,
              child: SizedBox(
                width: totalRightWidth,
                child: Column(
                  children: [
                    SizedBox(
                      height: 140,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            decoration: const BoxDecoration(
                              color: Color(0xFFF8FAFB),
                              border: Border(bottom: BorderSide(color: Color(0xFFEBEDEF), width: 1)),
                            ),
                            child: Row(
                              children: [
                                _staticHdr('STATUS', "STATUS", 75, bgColor: const Color(0xFF2F5597), textColor: Colors.white, type: ColumnType.text),
                                if (_showFeatures) ...[
                                  _staticHdr('PATENT', "PATENT", 85, bgColor: const Color(0xFF2E7D32), textColor: Colors.white, type: ColumnType.text),
                                  _staticHdr('BRAND', "BRAND/GEN", 85, bgColor: const Color(0xFF2E7D32), textColor: Colors.white, type: ColumnType.text),
                                  _staticHdr('RACK', "RACK", 45, bgColor: const Color(0xFF2E7D32), textColor: Colors.white, type: ColumnType.text),
                                  _staticHdr('MRP', "MRP", 65, bgColor: const Color(0xFF2E7D32), textColor: Colors.white, type: ColumnType.numeric),
                                  _staticHdr('PRATE', "P.RT", 65, bgColor: const Color(0xFF2E7D32), textColor: Colors.white, type: ColumnType.numeric),
                                  _staticHdr('CONTENT', "CONTENT", 110, bgColor: const Color(0xFF2E7D32), textColor: Colors.white, type: ColumnType.text),
                                ],
                                if (_showOffer) ...[
                                  _staticHdr('SUPP', "SUPP", 110, bgColor: const Color(0xFF2F5597), textColor: Colors.white, type: ColumnType.text),
                                  _staticHdr('OFFER', "OFFERS", 45, bgColor: const Color(0xFF2F5597), textColor: Colors.white, type: ColumnType.text),
                                ],

                                if (_showMonths && _allRankings.isNotEmpty)
                                  ...List.generate(_allRankings.first.monthlyStats.length, (i) => _buildDynamicMonthHeader(i)),

                                if (_showRanking) ...[
                                  _fixedCriteriaHdr('MAVG', "MOVING", "AVERAGE", "A", _mavgInterval, (v) {
                                     setState(() { _mavgInterval = v; _calculateRankings(); _saveSettings(); });
                                  }, tooltip: "• Average monthly sales.\n• Ignores old zero-sale months.\n• Minimum divisor = 3 (for safety)."),
                                  _fixedCriteriaHdr('SPECIAL', "SPECIAL", "ORDERS", "B", _specialInterval, (v) {
                                     setState(() { _specialInterval = v; _calculateRankings(); _saveSettings(); });
                                  }, tooltip: "• Sum of all Special Orders.\n• Fetched directly from the Sales Screen."),
                                  _fixedSimpleCriteriaHdr('LASTSALE', "LAST SALE", "QUANTITY", "C", tooltip: "• The quantity of the most recent sale for this product.\n• Fetched directly from the database."),
                                  ...List.generate(_customMetricColumns.length, (i) => _dualDropdownHdr(i, _customMetricColumns[i])),

                                  // 1. Plus (+) Header Button Column
                                  Container(
                                    width: 40,
                                    decoration: BoxDecoration(
                                        color: const Color(0xFF0288D1), // Sky Blue
                                        border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.5), width: 0.5))
                                    ),
                                    child: Column(
                                      children: [
                                        Container(height: 40, color: const Color(0xFF01579B)),
                                        Container(height: 30, color: const Color(0xFF0277BD)),
                                        Expanded(
                                          child: InkWell(
                                            onTap: () {
                                              setState(() {
                                                _customMetricColumns.add({'rank': '1st HIGHER', 'metric': 'TOTAL MONTH SALE', 'interval': 0});
                                                _calculateRankings();
                                                _saveSettings();
                                              });
                                            },
                                            child: const Center(
                                              child: Icon(Icons.add_box_rounded, color: Colors.white, size: 22),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  _warningLevelHdr(),
                                  _reOrderLevelHdr(),
                                  _maxOrderLevelHdr(),
                                ],
                                _overallRankHdr(),
                              ],
                            ),
                          ),
                          const SizedBox(width: rightBuffer),
                        ],
                      ),
                    ),
                    _buildRightFilterRow(rightBuffer: rightBuffer),
                    Expanded(
                      child: Scrollbar(
                        controller: _rightScrollCtrl,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _rightScrollCtrl,
                          itemCount: _displayRankings.length,
                            itemBuilder: (ctx, i) {
                              final r = _displayRankings[i];
                              final Color rowColor = i % 2 == 0 ? const Color(0xFFD9E1F2) : const Color(0xFFB4C6E7);

                              // Pre-calculate Sky Blue Ranking colors (Alternating Multicolor)
                              final bool isDupA = _duplicateCriteriaKeys.contains("MOVING AVERAGE_NONE_$_mavgInterval");
                              final Color rowColorA = i % 2 == 0 
                                  ? (isDupA ? const Color(0xFFFDEDEC) : const Color(0xFFE0F2FE)) 
                                  : (isDupA ? const Color(0xFFFADBD8) : const Color(0xFFBAE6FD));
                              
                              final bool isDupB = _duplicateCriteriaKeys.contains("SPECIAL ORDERS_NONE_$_specialInterval");
                              final Color rowColorB = i % 2 == 0 
                                  ? (isDupB ? const Color(0xFFFDEDEC) : const Color(0xFFE0F2FE)) 
                                  : (isDupB ? const Color(0xFFFADBD8) : const Color(0xFFBAE6FD));

                              return Row(
                                children: [
                                  Container(
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: rowColor,
                                      border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.5))),
                                    ),
                                    child: Row(
                                      children: [
                                        _statusCell(r.isActive, _getW('STATUS', 75), i),
                                        if (_showFeatures) ...[
                                          _cellText(r.patent, _getW('PATENT', 85), bgColor: i % 2 == 0 ? const Color(0xFFE8F5E9) : const Color(0xFFC8E6C9)),
                                          _cellText(r.category, _getW('BRAND', 85), bgColor: i % 2 == 0 ? const Color(0xFFE8F5E9) : const Color(0xFFC8E6C9)),
                                          _cellText(r.rack, _getW('RACK', 45), center: true, bgColor: i % 2 == 0 ? const Color(0xFFE8F5E9) : const Color(0xFFC8E6C9)),
                                          _cellText(r.mrp.toStringAsFixed(2), _getW('MRP', 65), right: true, bgColor: i % 2 == 0 ? const Color(0xFFE8F5E9) : const Color(0xFFC8E6C9)),
                                          _cellText(r.pRate.toStringAsFixed(2), _getW('PRATE', 65), right: true, bgColor: i % 2 == 0 ? const Color(0xFFE8F5E9) : const Color(0xFFC8E6C9)),
                                          _cellText(r.genericName, _getW('CONTENT', 110), isSecondary: true, bgColor: i % 2 == 0 ? const Color(0xFFE8F5E9) : const Color(0xFFC8E6C9)),
                                        ],
                                        if (_showOffer) ...[
                                          _cellText(r.preferredWholesale, _getW('SUPP', 110)),
                                          _cellText(r.offer, _getW('OFFER', 45)),
                                        ],

                                        if (_showMonths) ...[
                                          for (int mIndex = 0; mIndex < _allRankings.first.monthlyStats.length; mIndex++) ...[
                                            _cellText(r.monthlyStats[mIndex].saleCount.toString(), _getW('M${mIndex}_C', 45), center: true),
                                            _cellText(_cleanFormat(r.monthlyStats[mIndex].higherSale), _getW('M${mIndex}_H', 45), center: true),
                                            _cellText(_cleanFormat(r.monthlyStats[mIndex].monthSale), _getW('M${mIndex}_M', 50), center: true, bold: true),
                                            Container(width: 1, height: 38, color: Colors.white.withValues(alpha: 0.3)),
                                          ]
                                        ],

                                        if (_showRanking) ...[
                                          // CRITERIA A: MOVING AVERAGE
                                          _cellText(_cleanFormat(r.mavg), _getW('MAVG', 130), center: true, bold: true, bgColor: rowColorA, textColor: const Color(0xFF0369A1), isAccent: true),
                                          
                                          // CRITERIA B: SPECIAL ORDERS
                                          _cellText(_cleanFormat(r.specialOrders), _getW('SPECIAL', 130), center: true, bold: true, bgColor: rowColorB, textColor: const Color(0xFF0369A1), isAccent: true),

                                          // CRITERIA C: LAST SALE QTY
                                          _cellText(
                                              _cleanFormat(r.lastSaleQty), 
                                              _getW('LASTSALE', 130), 
                                              center: true, 
                                              bold: true,
                                              bgColor: i % 2 == 0 ? const Color(0xFFE0F2FE) : const Color(0xFFBAE6FD),
                                              textColor: const Color(0xFF0369A1),
                                              isAccent: true
                                          ),

                                          // CRITERIA D, E, F...
                                          ...List.generate(_customMetricColumns.length, (colIdx) {
                                            final col = _customMetricColumns[colIdx];
                                            String letter = String.fromCharCode(68 + colIdx);
                                            final bool isDupC = _duplicateCriteriaKeys.contains("${col['metric']}_${col['rank']}_${col['interval']}");
                                            final Color critColor = i % 2 == 0 
                                                ? (isDupC ? const Color(0xFFFDEDEC) : const Color(0xFFE0F2FE)) 
                                                : (isDupC ? const Color(0xFFFADBD8) : const Color(0xFFBAE6FD));
                                            double val = r.customCriteria[letter] ?? 0.0;
                                            return _cellText(_cleanFormat(val), _getW(_getColKey(col), 130.0), center: true, bold: true, bgColor: critColor, textColor: const Color(0xFF0369A1), isAccent: true);
                                          }),

                                          // Spacer under (+) button
                                          Container(
                                              width: 40, 
                                              decoration: BoxDecoration(
                                                  color: i % 2 == 0 ? const Color(0xFFE0F2FE) : const Color(0xFFBAE6FD), 
                                              )
                                          ),

                                          // ORANGE THEME FOR WARNING LEVEL DATA [X]
                                          _cellText(
                                              _cleanFormat(r.warningScore), 
                                              _getW('WARNING', 110), 
                                              center: true, 
                                              bold: true, 
                                              bgColor: i % 2 == 0 ? const Color(0xFFFEF5E7) : const Color(0xFFFDEBD0), 
                                              textColor: const Color(0xFFD35400), 
                                              boldText: true
                                          ),
                                          
                                          // RED THEME FOR RE-ORDER LEVEL DATA [Y]
                                          _cellText(
                                              _cleanFormat(r.reOrderScore), 
                                              _getW('REORDER', 110), 
                                              center: true, 
                                              bold: true, 
                                              bgColor: i % 2 == 0 ? const Color(0xFFFDEDEC) : const Color(0xFFFADBD8), 
                                              textColor: const Color(0xFFC0392B), 
                                              boldText: true
                                          ),
                                          
                                          // GREEN THEME FOR MAX ORDER LEVEL DATA [Z]
                                          _cellText(
                                              _cleanFormat(r.maxOrderLevel), 
                                              _getW('MAXORDER', 130), 
                                              center: true, 
                                              bold: true, 
                                              bgColor: i % 2 == 0 ? const Color(0xFFE8F5E9) : const Color(0xFFC8E6C9), 
                                              textColor: const Color(0xFF2E7D32), 
                                              boldText: true
                                          ),
                                        ],

                                        // GOLDEN THEME FOR OVERALL RANK DATA [W]
                                        _cellText(
                                            _cleanFormat(r.weightedScore), 
                                            _getW('OVERALL', 110), 
                                            center: true, 
                                            bold: true, 
                                            bgColor: i % 2 == 0 ? const Color(0xFFFEF9E7) : const Color(0xFFF9E79F), 
                                            textColor: const Color(0xFF9A7D0A), 
                                            boldText: true
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: rightBuffer),
                                ],
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

  Widget _statusCell(bool active, double width, int index) {
    Color activeBg = index % 2 == 0 ? const Color(0xFFE8F5E9) : const Color(0xFFC8E6C9);
    Color inactiveBg = index % 2 == 0 ? const Color(0xFFFFEBEE) : const Color(0xFFFADBD8);

    return Container(
      width: width,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? activeBg : inactiveBg,
        border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.3))),
      ),
      child: Text(
        active ? "ACTIVE" : "INACTIVE",
        style: TextStyle(
            color: active ? const Color(0xFF2E7D32) : const Color(0xFFC62828), 
            fontWeight: FontWeight.w900, 
            fontSize: 8.5, 
            letterSpacing: 0.5
        ),
      ),
    );
  }

  Widget _resizeHandle(String colKey, double defaultWidth) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) {
        setState(() {
          double currentWidth = _colWidths[colKey] ?? defaultWidth;
          double newWidth = currentWidth + details.delta.dx;
          if (newWidth >= 30) {
            _colWidths[colKey] = newWidth;
          }
        });
      },
      onPanEnd: (_) => _saveSettings(),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(width: 8, color: Colors.transparent),
      ),
    );
  }

  Widget _staticHdr(String colKey, String label, double defaultWidth, {Color? bgColor, Color? textColor, String? tooltip, ColumnType type = ColumnType.text}) {
    return _FilterableHdr(
      title: label,
      colKey: colKey,
      type: type,
      width: _getW(colKey, defaultWidth),
      bgColor: bgColor ?? const Color(0xFF4472C4),
      textColor: textColor ?? Colors.white,
      tooltip: tooltip,
      activeFilter: _activeFilters[colKey],
      onQuickFilter: (c, v) => _applyQuickFilter(colKey, c, v),
      onAdvancedTap: (pos) => _openAdvancedFilterDialog(colKey, label, type, pos),
      onHeaderTap: () => _handleHeaderSort(colKey),
      isSorted: _sortCol == colKey,
      isAscending: _sortAscending,
      resizeHandle: Positioned(right: 0, top: 0, bottom: 0, child: _resizeHandle(colKey, defaultWidth)),
    );
  }

  void _handleHeaderSort(String colKey) {
    setState(() {
      if (_sortCol == colKey) {
        _sortAscending = !_sortAscending;
      } else {
        _sortCol = colKey;
        _sortAscending = false;
      }
      _applyFilters();
    });
  }

  Widget _fixedCriteriaHdr(String key, String line1, String line2, String letter, int currentInterval, Function(int) onIntervalChanged, {String? tooltip}) {
    final dups = _duplicateCriteriaKeys;
    final String currentKey = "${key == 'MAVG' ? 'MOVING AVERAGE' : 'SPECIAL ORDERS'}_NONE_$currentInterval";
    final bool isDup = dups.contains(currentKey);
    final Color bgColor = isDup ? const Color(0xFFC0392B) : const Color(0xFF0288D1); // Sky Blue Header
    final Color darkColor = isDup ? const Color(0xFF922B21) : const Color(0xFF0277BD); // Darker Sky Blue Interval Bar

    return _FilterableHdr(
      title: "CRITERIA $letter",
      colKey: key,
      type: ColumnType.numeric,
      width: _getW(key, 130),
      bgColor: bgColor,
      textColor: Colors.white,
      tooltip: tooltip,
      activeFilter: _activeFilters[key],
      onQuickFilter: (c, v) => _applyQuickFilter(key, c, v),
      onAdvancedTap: (pos) => _openAdvancedFilterDialog(key, "CRITERIA $letter", ColumnType.numeric, pos),
      onHeaderTap: () => _handleHeaderSort(key),
      isSorted: _sortCol == key,
      isAscending: _sortAscending,
      body: Column(
        children: [
          Container(
            height: 30,
            width: double.infinity,
            color: darkColor,
            alignment: Alignment.center,
            child: _intervalField(currentInterval, onIntervalChanged),
          ),
          Expanded(
            child: Container(
              alignment: Alignment.center,
              child: Text("$line1\n$line2", textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10.5, color: Colors.white, height: 1.1)),
            ),
          ),
        ],
      ),
      resizeHandle: Positioned(right: 0, top: 0, bottom: 0, child: _resizeHandle(key, 130)),
    );
  }

  Widget _dualDropdownHdr(int index, Map<String, dynamic> colData) {
    String colKey = _getColKey(colData);
    String letter = String.fromCharCode(68 + index); // D, E, F...

    String rankVal = colData['rank'] ?? "1st HIGHER";
    String metricVal = colData['metric'] ?? "TOTAL MONTH SALE";
    Color rankColor = rankVal.contains('HIGHER') ? Colors.green.shade700 : Colors.red.shade700;

    final dups = _duplicateCriteriaKeys;
    final String currentKey = "${colData['metric']}_${colData['rank']}_${colData['interval']}";
    final bool isDup = dups.contains(currentKey);
    final Color bgColor = isDup ? const Color(0xFFC0392B) : const Color(0xFF0288D1); // Sky Blue Header
    final Color darkColor = isDup ? const Color(0xFF922B21) : const Color(0xFF0277BD); // Darker Sky Blue Interval Bar

    return _FilterableHdr(
      title: "CRITERIA $letter",
      colKey: colKey,
      type: ColumnType.numeric,
      width: _getW(colKey, 130),
      bgColor: bgColor,
      textColor: Colors.white,
      activeFilter: _activeFilters[colKey],
      onQuickFilter: (c, v) => _applyQuickFilter(colKey, c, v),
      onAdvancedTap: (pos) => _openAdvancedFilterDialog(colKey, "CRITERIA $letter", ColumnType.numeric, pos),
      onHeaderTap: () => _handleHeaderSort(colKey),
      isSorted: _sortCol == colKey,
      isAscending: _sortAscending,
      body: Column(
        children: [
          Container(
            height: 30,
            width: double.infinity,
            color: darkColor,
            child: _headerTopFields(
              (colData['interval'] as num?)?.toInt() ?? 0,
              (colData['minRank'] as num?)?.toDouble() ?? 0.0,
              (v) {
                setState(() {
                  _customMetricColumns[index]['interval'] = v;
                  _calculateRankings();
                  _saveSettings();
                });
              },
              (v) {
                setState(() {
                  _customMetricColumns[index]['minRank'] = v;
                  _calculateRankings();
                  _saveSettings();
                });
              },
              () {
                setState(() {
                  _customMetricColumns.removeAt(index);
                  _calculateRankings();
                  _saveSettings();
                });
              },
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _customHdrDropdown(index: index, value: rankVal, options: _rankOptions, color: rankColor, key: 'rank', width: _getW(colKey, 130)),
                  const SizedBox(height: 2),
                  _customHdrDropdown(index: index, value: metricVal, options: _metricOptions, color: const Color(0xFF2C3E50), key: 'metric', width: _getW(colKey, 130)),
                ],
              ),
            ),
          ),
        ],
      ),
      resizeHandle: Positioned(right: 0, top: 0, bottom: 0, child: _resizeHandle(colKey, 130)),
    );
  }

  Widget _headerTopFields(int interval, double minRank, Function(int) onIntervalChanged, Function(double) onMinRankChanged, VoidCallback onDelete) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Row(
        children: [
          const Text("M:", style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(width: 1),
          Container(
            width: 25,
            height: 18,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3)),
            child: TextField(
              controller: TextEditingController(text: interval == 0 ? "ALL" : interval.toString()),
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: Color(0xFFD35400)),
              decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
              onSubmitted: (v) => onIntervalChanged(int.tryParse(v) ?? 0),
            ),
          ),
          const SizedBox(width: 3),
          const Text("MIN:", style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(width: 1),
          Container(
            width: 28,
            height: 18,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3)),
            child: TextField(
              controller: TextEditingController(text: minRank == 0 ? "0" : _cleanFormat(minRank)),
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: Color(0xFF27AE60)),
              decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
              onSubmitted: (v) => onMinRankChanged(double.tryParse(v) ?? 0.0),
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: onDelete,
            child: Container(
              padding: const EdgeInsets.all(1),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded, size: 9, color: Color(0xFF922B21)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _intervalField(int val, Function(int) onChanged) {
    return Container(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text("MONTHS:", style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5)),
            ),
          ),
          const SizedBox(width: 2),
          Container(
            width: 32,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 2, offset: const Offset(0, 1))],
            ),
            child: TextField(
              controller: TextEditingController(text: val == 0 ? "ALL" : val.toString()),
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFFD35400)),
              decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
              onSubmitted: (v) {
                int newVal = int.tryParse(v) ?? 0;
                onChanged(newVal);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _overallRankHdr() {
    return _buildRuleOrFormulaHdr(
      title: "[W] RANK",
      colKey: 'OVERALL',
      mainColor: const Color(0xFFFFD700), // Gold
      innerColor: const Color(0xFFDAA520), // Goldenrod
      rules: _rankRules,
      formulaCtrl: _formulaCtrl,
      formulaVal: _rankFormula,
      isValid: _isFormulaValid,
      onFormulaChanged: (v) => setState(() { _rankFormula = v.isEmpty ? "0" : v; _calculateRankings(); }),
      onFormulaSaved: () => { _saveSettings(), _validateFormulaSubmission(_rankFormula, "RANK") },
      onOpenRules: _showRankRuleBuilderDialog,
      colWidth: 110,
    );
  }

  Widget _warningLevelHdr() {
    return _buildRuleOrFormulaHdr(
      title: "[X] WARNING",
      colKey: 'WARNING',
      mainColor: const Color(0xFFE67E22), // Orange Header
      innerColor: const Color(0xFFD35400), // Darker Orange Input
      rules: _warningRules,
      formulaCtrl: _warningCtrl,
      formulaVal: _warningFormula,
      isValid: _isWarningValid,
      onFormulaChanged: (v) => setState(() { _warningFormula = v.isEmpty ? "0" : v; _calculateRankings(); }),
      onFormulaSaved: () => { _saveSettings(), _validateFormulaSubmission(_warningFormula, "WARNING") },
      onOpenRules: _showWarningRuleBuilderDialog,
      colWidth: 110,
    );
  }

  Widget _reOrderLevelHdr() {
    return _buildRuleOrFormulaHdr(
      title: "[Y] RE-ORDER\nLEVEL",
      colKey: 'REORDER',
      mainColor: const Color(0xFFC0392B), // Red Header
      innerColor: const Color(0xFF962D22), // Darker Red Input
      rules: _reOrderRules,
      formulaCtrl: _reOrderCtrl,
      formulaVal: _reOrderFormula,
      isValid: _isReOrderValid,
      onFormulaChanged: (v) => setState(() { _reOrderFormula = v.isEmpty ? "0" : v; _calculateRankings(); }),
      onFormulaSaved: () => { _saveSettings(), _validateFormulaSubmission(_reOrderFormula, "RE-ORDER") },
      onOpenRules: _showRuleBuilderDialog,
      colWidth: 110,
    );
  }

  Widget _maxOrderLevelHdr() {
    return _buildRuleOrFormulaHdr(
      title: "[Z] MAX ORDER\nLEVEL",
      colKey: 'MAXORDER',
      mainColor: const Color(0xFF27AE60), // Green Header
      innerColor: const Color(0xFF1E8449), // Darker Green Input
      rules: _maxOrderRules,
      formulaCtrl: _maxOrderCtrl,
      formulaVal: _maxOrderFormula,
      isValid: true,
      onFormulaChanged: (v) => setState(() { _maxOrderFormula = v.isEmpty ? "0" : v; _calculateRankings(); }),
      onFormulaSaved: () => { _saveSettings(), _validateFormulaSubmission(_maxOrderFormula, "MAX ORDER") },
      onOpenRules: _showMaxRuleBuilderDialog,
      colWidth: 130,
    );
  }

  void _showRankRuleBuilderDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _RuleBuilderDialog(
        title: "Rank Logic Rules (W)",
        initialRules: _rankRules,
        customColCount: _customMetricColumns.length,
        onSave: (newRules) {
          setState(() {
            _rankRules = newRules;
            _calculateRankings();
            _saveSettings();
          });
        },
      ),
    );
  }

  void _showWarningRuleBuilderDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _RuleBuilderDialog(
        title: "Warning Logic Rules (X)",
        initialRules: _warningRules,
        customColCount: _customMetricColumns.length,
        onSave: (newRules) {
          setState(() {
            _warningRules = newRules;
            _calculateRankings();
            _saveSettings();
          });
        },
      ),
    );
  }

  void _showRuleBuilderDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _RuleBuilderDialog(
        title: "Re-Order Logic Rules (Y)",
        initialRules: _reOrderRules,
        customColCount: _customMetricColumns.length,
        onSave: (newRules) {
          setState(() {
            _reOrderRules = newRules;
            _calculateRankings();
            _saveSettings();
          });
        },
      ),
    );
  }

  void _showMaxRuleBuilderDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _RuleBuilderDialog(
        title: "Max Order Logic Rules (Z)",
        initialRules: _maxOrderRules,
        customColCount: _customMetricColumns.length,
        onSave: (newRules) {
          setState(() {
            _maxOrderRules = newRules;
            _calculateRankings();
            _saveSettings();
          });
        },
      ),
    );
  }

  Widget _buildRuleOrFormulaHdr({
    required String title,
    required String colKey,
    required Color mainColor,
    required Color innerColor,
    required List<Map<String, dynamic>> rules,
    required TextEditingController formulaCtrl,
    required String formulaVal,
    required bool isValid,
    required Function(String) onFormulaChanged,
    required VoidCallback onFormulaSaved,
    required VoidCallback onOpenRules,
    required double colWidth,
  }) {
    return _FilterableHdr(
      title: title,
      colKey: colKey,
      type: ColumnType.numeric,
      width: _getW(colKey, colWidth),
      bgColor: mainColor,
      textColor: Colors.white,
      activeFilter: _activeFilters[colKey],
      onQuickFilter: (c, v) => _applyQuickFilter(colKey, c, v),
      onAdvancedTap: (pos) => _openAdvancedFilterDialog(colKey, title, ColumnType.numeric, pos),
      onHeaderTap: () => _handleHeaderSort(colKey),
      isSorted: _sortCol == colKey,
      isAscending: _sortAscending,
      body: Column(
        children: [
          if (rules.isNotEmpty)
            Expanded(
              child: Center(
                child: Container(
                  height: 32,
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ElevatedButton(
                    onPressed: onOpenRules,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: mainColor,
                      elevation: 0,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    child: Text(
                      "${rules.length} RULES",
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),
            )
          else ...[
            Container(
              height: 26,
              width: double.infinity,
              color: innerColor,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                child: TextField(
                  controller: formulaCtrl,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: innerColor),
                  decoration: const InputDecoration(border: InputBorder.none, isDense: true, hintText: "FORMULA", contentPadding: EdgeInsets.symmetric(vertical: 5)),
                  onChanged: onFormulaChanged,
                  onSubmitted: (_) => onFormulaSaved(),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onOpenRules,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    child: const Text(
                      "SET RULES",
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      resizeHandle: Positioned(right: 0, top: 0, bottom: 0, child: _resizeHandle(colKey, colWidth)),
    );
  }

  Widget _formulaResultHdr({
    required String title,
    required TextEditingController formulaCtrl,
    required String formulaVal,
    required bool isValid,
    required Function(String) onChanged,
    required VoidCallback onSaved,
    required String colKey,
    required double colWidth,
    Color titleColor = Colors.white,
    Color? bgColor,
    Color? darkColor,
  }) {
    final Color mainColor = bgColor ?? (isValid ? const Color(0xFF27AE60) : const Color(0xFFC0392B));
    final Color innerColor = darkColor ?? mainColor;

    return _FilterableHdr(
      title: title,
      colKey: colKey,
      type: ColumnType.numeric,
      width: _getW(colKey, colWidth),
      bgColor: mainColor,
      textColor: titleColor,
      activeFilter: _activeFilters[colKey],
      onQuickFilter: (c, v) => _applyQuickFilter(colKey, c, v),
      onAdvancedTap: (pos) => _openAdvancedFilterDialog(colKey, title, ColumnType.numeric, pos),
      onHeaderTap: () => _handleHeaderSort(colKey),
      isSorted: _sortCol == colKey,
      isAscending: _sortAscending,
      body: Column(
        children: [
          Container(
            height: 32,
            width: double.infinity,
            color: innerColor,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
              child: TextField(
                controller: formulaCtrl,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: innerColor),
                decoration: const InputDecoration(border: InputBorder.none, isDense: true, hintText: "FORMULA", contentPadding: EdgeInsets.symmetric(vertical: 8)),
                onChanged: onChanged,
                onSubmitted: (_) => onSaved(),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(isValid ? "VALID" : "INVALID", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: titleColor, height: 1.1)),
              ],
            ),
          ),
        ],
      ),
      resizeHandle: Positioned(right: 0, top: 0, bottom: 0, child: _resizeHandle(colKey, colWidth)),
    );
  }

  Widget _customHdrDropdown({required int index, required String value, required List<String> options, required Color color, required String key, required double width}) {
    return Container(
      height: 23,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 2, offset: const Offset(0, 1))],
      ),
      child: StatefulBuilder(
        builder: (context, setDropdownState) {
          String? focusedText;
          return Autocomplete<String>(
            initialValue: TextEditingValue(text: value),
            optionsBuilder: (TextEditingValue textEditingValue) {
              final currentText = textEditingValue.text;
              if (focusedText != null &&
                  currentText == focusedText &&
                  options.any((o) => o.toLowerCase().trim() == currentText.toLowerCase().trim())) {
                return const Iterable<String>.empty();
              }
              if (currentText.isEmpty) return options;
              return options.where((o) => o.toLowerCase().contains(currentText.toLowerCase()));
            },
            onSelected: (v) {
              FocusScope.of(context).unfocus();
              setState(() {
                _customMetricColumns[index][key] = v;
                _calculateRankings();
                _saveSettings();
              });
            },
            fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
              focusNode.addListener(() {
                if (focusNode.hasFocus) {
                  focusedText = controller.text;
                } else {
                  focusedText = null;
                }
              });
              return TextField(
                controller: controller,
                focusNode: focusNode,
                onTap: () {
                  if (focusNode.hasFocus) {
                    focusedText = controller.text;
                  }
                },
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: color),
                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 2), border: InputBorder.none),
              );
            },
            optionsViewBuilder: (context, onSelected, opts) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 8.0,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 200, // Increased width to show names in one line
                    constraints: const BoxConstraints(maxHeight: 250),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: opts.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                      itemBuilder: (BuildContext context, int i) {
                        final String option = opts.elementAt(i);
                        return InkWell(
                          onTap: () => onSelected(option),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Text(
                              option,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)),
                              softWrap: false,
                              overflow: TextOverflow.visible,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDynamicMonthHeader(int index) {
    if (_allRankings.isEmpty) return const SizedBox();
    final stat = _allRankings.first.monthlyStats[index];

    String startDate = DateFormat('dd-MMM-yy').format(stat.startDate).toUpperCase();
    String endDate = DateFormat('dd-MMM-yy').format(stat.endDate).toUpperCase();
    String dateRange = "$startDate TO $endDate";
    bool isLiveCurrent = index == 0 && _includeCurrentMonth;

    double cWidth = _getW('M${index}_C', 45);
    double hWidth = _getW('M${index}_H', 45);
    double mWidth = _getW('M${index}_M', 50);
    double totalMonthBlockWidth = cWidth + hWidth + mWidth + 1.0;

    // Determine the month label dynamically
    String monthLabel = _includeCurrentMonth
      ? "${DateFormat('dd/MM/yy').format(stat.startDate)} TO ${DateFormat('dd/MM/yy').format(stat.endDate)}"
      : DateFormat('MMMM yyyy').format(stat.startDate).toUpperCase();

    return Container(
      width: totalMonthBlockWidth,
      decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.5), width: 1))),
      child: Column(
        children: [
          Container(
            height: 45,
            color: const Color(0xFF2F5597), // Dark blue
            alignment: Alignment.center,
            child: Text(
              monthLabel,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5),
            ),
          ),
          Container(
            height: 40,
            color: const Color(0xFF4472C4), // Royal blue
            alignment: Alignment.center,
            child: Text(
              isLiveCurrent ? "LIVE: $dateRange" : dateRange,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.2),
              overflow: TextOverflow.clip,
              maxLines: 1,
            ),
          ),
          Expanded(
            child: Row(
              children: [
                _monthSubHdr('M${index}_C', "SALE\nCOUNT", cWidth, tooltip: "• Total bills/invoices.\n• How many times it was sold.", type: ColumnType.numeric),
                _monthSubHdr('M${index}_H', "HIGHER\nSALE", hWidth, tooltip: "• Biggest single sale.\n• Top quantity in one bill.", type: ColumnType.numeric),
                _monthSubHdr('M${index}_M', "MONTH\nSALE", mWidth, tooltip: "• Total quantity sold.\n• Sum of all pieces/strips this month.", type: ColumnType.numeric),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _monthSubHdr(String colKey, String label, double defaultWidth, {String? tooltip, ColumnType type = ColumnType.numeric}) {
    return _FilterableHdr(
      title: label,
      colKey: colKey,
      type: type,
      width: _getW(colKey, defaultWidth),
      bgColor: const Color(0xFF4472C4),
      textColor: Colors.white,
      tooltip: tooltip,
      activeFilter: _activeFilters[colKey],
      onQuickFilter: (c, v) => _applyQuickFilter(colKey, c, v),
      onAdvancedTap: (pos) => _openAdvancedFilterDialog(colKey, label, type, pos),
      onHeaderTap: () => _handleHeaderSort(colKey),
      isSorted: _sortCol == colKey,
      isAscending: _sortAscending,
      resizeHandle: Positioned(right: 0, top: 0, bottom: 0, child: _resizeHandle(colKey, defaultWidth)),
    );
  }

  Widget _fixedSimpleCriteriaHdr(String key, String line1, String line2, String letter, {String? tooltip}) {
    return _FilterableHdr(
      title: "CRITERIA $letter",
      colKey: key,
      type: ColumnType.numeric,
      width: _getW(key, 130),
      bgColor: const Color(0xFF0288D1), // Sky Blue Header
      textColor: Colors.white,
      tooltip: tooltip,
      activeFilter: _activeFilters[key],
      onQuickFilter: (c, v) => _applyQuickFilter(key, c, v),
      onAdvancedTap: (pos) => _openAdvancedFilterDialog(key, "CRITERIA $letter", ColumnType.numeric, pos),
      onHeaderTap: () => _handleHeaderSort(key),
      isSorted: _sortCol == key,
      isAscending: _sortAscending,
      body: Column(
        children: [
          Container(
            height: 30,
            width: double.infinity,
            color: const Color(0xFF0277BD), // Darker Sky Blue Bar
            alignment: Alignment.center,
            child: const Text("DATABASE", style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5)),
          ),
          Expanded(
            child: Container(
              alignment: Alignment.center,
              child: Text("$line1\n$line2", textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10.5, color: Colors.white, height: 1.1)),
            ),
          ),
        ],
      ),
      resizeHandle: Positioned(right: 0, top: 0, bottom: 0, child: _resizeHandle(key, 130)),
    );
  }

  Widget _buildLeftFilterRow() {
    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          _RankingFilterCell(colKey: 'NAME', label: "PRODUCT NAME", width: _getW('NAME', 200), type: ColumnType.text, activeFilter: _activeFilters['NAME'], onQuickFilter: _applyQuickFilter, onAdvancedTap: (pos) => _openAdvancedFilterDialog('NAME', "PRODUCT NAME", ColumnType.text, pos)),
          _RankingFilterCell(colKey: 'PACK', label: "PACK", width: _getW('PACK', 45), type: ColumnType.numeric, activeFilter: _activeFilters['PACK'], onQuickFilter: _applyQuickFilter, onAdvancedTap: (pos) => _openAdvancedFilterDialog('PACK', "PACK", ColumnType.numeric, pos)),
        ],
      ),
    );
  }

  Widget _buildRightFilterRow({double rightBuffer = 0}) {
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          _RankingFilterCell(colKey: 'STATUS', label: "STATUS", width: _getW('STATUS', 75), type: ColumnType.text, activeFilter: _activeFilters['STATUS'], onQuickFilter: _applyQuickFilter, onAdvancedTap: (pos) => _openAdvancedFilterDialog('STATUS', "STATUS", ColumnType.text, pos)),
          if (_showFeatures) ...[
            _RankingFilterCell(colKey: 'PATENT', label: "PATENT", width: _getW('PATENT', 85), type: ColumnType.text, activeFilter: _activeFilters['PATENT'], onQuickFilter: _applyQuickFilter, onAdvancedTap: (pos) => _openAdvancedFilterDialog('PATENT', "PATENT", ColumnType.text, pos)),
            _RankingFilterCell(colKey: 'BRAND', label: "BRAND/GEN", width: _getW('BRAND', 85), type: ColumnType.text, activeFilter: _activeFilters['BRAND'], onQuickFilter: _applyQuickFilter, onAdvancedTap: (pos) => _openAdvancedFilterDialog('BRAND', "BRAND/GEN", ColumnType.text, pos)),
            _RankingFilterCell(colKey: 'RACK', label: "RACK", width: _getW('RACK', 45), type: ColumnType.text, activeFilter: _activeFilters['RACK'], onQuickFilter: _applyQuickFilter, onAdvancedTap: (pos) => _openAdvancedFilterDialog('RACK', "RACK", ColumnType.text, pos)),
            _RankingFilterCell(colKey: 'MRP', label: "MRP", width: _getW('MRP', 65), type: ColumnType.numeric, activeFilter: _activeFilters['MRP'], onQuickFilter: _applyQuickFilter, onAdvancedTap: (pos) => _openAdvancedFilterDialog('MRP', "MRP", ColumnType.numeric, pos)),
            _RankingFilterCell(colKey: 'PRATE', label: "P.RT", width: _getW('PRATE', 65), type: ColumnType.numeric, activeFilter: _activeFilters['PRATE'], onQuickFilter: _applyQuickFilter, onAdvancedTap: (pos) => _openAdvancedFilterDialog('PRATE', "P.RT", ColumnType.numeric, pos)),
            _RankingFilterCell(colKey: 'CONTENT', label: "CONTENT", width: _getW('CONTENT', 110), type: ColumnType.text, activeFilter: _activeFilters['CONTENT'], onQuickFilter: _applyQuickFilter, onAdvancedTap: (pos) => _openAdvancedFilterDialog('CONTENT', "CONTENT", ColumnType.text, pos)),
          ],
          if (_showOffer) ...[
            _RankingFilterCell(colKey: 'SUPP', label: "SUPP", width: _getW('SUPP', 110), type: ColumnType.text, activeFilter: _activeFilters['SUPP'], onQuickFilter: _applyQuickFilter, onAdvancedTap: (pos) => _openAdvancedFilterDialog('SUPP', "SUPP", ColumnType.text, pos)),
            _RankingFilterCell(colKey: 'OFFER', label: "OFFERS", width: _getW('OFFER', 45), type: ColumnType.text, activeFilter: _activeFilters['OFFER'], onQuickFilter: _applyQuickFilter, onAdvancedTap: (pos) => _openAdvancedFilterDialog('OFFER', "OFFERS", ColumnType.text, pos)),
          ],

          if (_showMonths && _allRankings.isNotEmpty)
            for (int i = 0; i < _allRankings.first.monthlyStats.length; i++) ...[
               _RankingFilterCell(colKey: 'M${i}_C', label: "SALE COUNT", width: _getW('M${i}_C', 45), type: ColumnType.numeric, activeFilter: _activeFilters['M${i}_C'], onQuickFilter: _applyQuickFilter, onAdvancedTap: (pos) => _openAdvancedFilterDialog('M${i}_C', "SALE COUNT", ColumnType.numeric, pos)),
               _RankingFilterCell(colKey: 'M${i}_H', label: "HIGHER SALE", width: _getW('M${i}_H', 45), type: ColumnType.numeric, activeFilter: _activeFilters['M${i}_H'], onQuickFilter: _applyQuickFilter, onAdvancedTap: (pos) => _openAdvancedFilterDialog('M${i}_H', "HIGHER SALE", ColumnType.numeric, pos)),
               _RankingFilterCell(colKey: 'M${i}_M', label: "MONTH SALE", width: _getW('M${i}_M', 50), type: ColumnType.numeric, activeFilter: _activeFilters['M${i}_M'], onQuickFilter: _applyQuickFilter, onAdvancedTap: (pos) => _openAdvancedFilterDialog('M${i}_M', "MONTH SALE", ColumnType.numeric, pos)),
            ],

          if (_showRanking) ...[
            _RankingFilterCell(colKey: 'MAVG', label: "MOVING AVERAGE", width: _getW('MAVG', 130), type: ColumnType.numeric, activeFilter: _activeFilters['MAVG'], onQuickFilter: _applyQuickFilter, onAdvancedTap: (pos) => _openAdvancedFilterDialog('MAVG', "MOVING AVERAGE", ColumnType.numeric, pos)),
            _RankingFilterCell(colKey: 'SPECIAL', label: "SPECIAL ORDERS", width: _getW('SPECIAL', 130), type: ColumnType.numeric, activeFilter: _activeFilters['SPECIAL'], onQuickFilter: _applyQuickFilter, onAdvancedTap: (pos) => _openAdvancedFilterDialog('SPECIAL', "SPECIAL ORDERS", ColumnType.numeric, pos)),
            _RankingFilterCell(colKey: 'LASTSALE', label: "LAST SALE", width: _getW('LASTSALE', 130), type: ColumnType.numeric, activeFilter: _activeFilters['LASTSALE'], onQuickFilter: _applyQuickFilter, onAdvancedTap: (pos) => _openAdvancedFilterDialog('LASTSALE', "LAST SALE", ColumnType.numeric, pos)),
            for (int i = 0; i < _customMetricColumns.length; i++)
              _RankingFilterCell(colKey: String.fromCharCode(68 + i), label: "CRITERIA ${String.fromCharCode(68 + i)}", width: _getW(_getColKey(_customMetricColumns[i]), 130), type: ColumnType.numeric, activeFilter: _activeFilters[String.fromCharCode(68 + i)], onQuickFilter: _applyQuickFilter, onAdvancedTap: (pos) => _openAdvancedFilterDialog(String.fromCharCode(68 + i), "CRITERIA ${String.fromCharCode(68 + i)}", ColumnType.numeric, pos)),
            
            Container(width: 40, height: 26, decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade400)))),

            _RankingFilterCell(colKey: 'WARNING', label: "WARNING", width: _getW('WARNING', 110), type: ColumnType.numeric, activeFilter: _activeFilters['WARNING'], onQuickFilter: _applyQuickFilter, onAdvancedTap: (pos) => _openAdvancedFilterDialog('WARNING', "WARNING", ColumnType.numeric, pos)),
            _RankingFilterCell(colKey: 'REORDER', label: "RE-ORDER", width: _getW('REORDER', 110), type: ColumnType.numeric, activeFilter: _activeFilters['REORDER'], onQuickFilter: _applyQuickFilter, onAdvancedTap: (pos) => _openAdvancedFilterDialog('REORDER', "RE-ORDER", ColumnType.numeric, pos)),
            _RankingFilterCell(colKey: 'MAXORDER', label: "MAX ORDER", width: _getW('MAXORDER', 130), type: ColumnType.numeric, activeFilter: _activeFilters['MAXORDER'], onQuickFilter: _applyQuickFilter, onAdvancedTap: (pos) => _openAdvancedFilterDialog('MAXORDER', "MAX ORDER", ColumnType.numeric, pos)),
          ],
          _RankingFilterCell(colKey: 'OVERALL', label: "RANK SCORE", width: _getW('OVERALL', 110), type: ColumnType.numeric, activeFilter: _activeFilters['OVERALL'], onQuickFilter: _applyQuickFilter, onAdvancedTap: (pos) => _openAdvancedFilterDialog('OVERALL', "RANK SCORE", ColumnType.numeric, pos)),
          SizedBox(width: rightBuffer),
        ],
      ),
    );
  }

  Widget _cellText(String text, double width, {bool bold = false, bool right = false, bool center = false, Color? bgColor, Color? textColor, bool isPrimary = false, bool isSecondary = false, bool isAccent = false, bool boldText = false}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: center ? Alignment.center : (right ? Alignment.centerRight : Alignment.centerLeft),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(right: BorderSide(color: Colors.grey.shade100, width: 1)),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontWeight: (bold || boldText) ? FontWeight.w800 : FontWeight.w500,
            fontSize: isSecondary ? 9 : 10,
            color: textColor ?? (isPrimary ? const Color(0xFF1B2631) : (isAccent ? const Color(0xFF2F5597) : Colors.black87)),
            letterSpacing: 0.2
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _FilterableHdr({
    required String title,
    required String colKey,
    required ColumnType type,
    required double width,
    required Color bgColor,
    required Color textColor,
    String? tooltip,
    Map<String, dynamic>? activeFilter,
    required Function(String condition, String value) onQuickFilter,
    required Function(Offset position) onAdvancedTap,
    required VoidCallback onHeaderTap,
    bool isSorted = false,
    bool isAscending = false,
    Widget? body,
    Widget? resizeHandle,
  }) {
    return GestureDetector(
      onTap: onHeaderTap,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.5), width: 1)),
        ),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Row 1: Title Centered
                Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isSorted)
                        Icon(isAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 12, color: textColor.withValues(alpha: 0.8)),
                      if (isSorted) const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          title.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: textColor, height: 1.1),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                // Body
                if (body != null) Expanded(child: body),
              ],
            ),
            if (resizeHandle != null) resizeHandle,
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// FILTER CELL WIDGET FOR THE DEDICATED FILTER ROW
// ============================================================================
class _RankingFilterCell extends StatefulWidget {
  final String colKey;
  final String label;
  final double width;
  final ColumnType type;
  final Map<String, dynamic>? activeFilter;
  final Function(String, String, String) onQuickFilter;
  final Function(Offset position) onAdvancedTap;

  const _RankingFilterCell({
    required this.colKey, 
    required this.label,
    required this.width, 
    required this.type, 
    this.activeFilter, 
    required this.onQuickFilter,
    required this.onAdvancedTap,
  });

  @override
  State<_RankingFilterCell> createState() => _RankingFilterCellState();
}

class _RankingFilterCellState extends State<_RankingFilterCell> {
  late TextEditingController _ctrl;
  late String _condition;

  @override
  void initState() {
    super.initState();
    final f = widget.activeFilter;
    String initialVal = f != null && f['mode'] == 'quick' ? f['value']?.toString() ?? "" : "";
    _ctrl = TextEditingController(text: initialVal);
    _condition = f != null && f['mode'] == 'quick' ? f['condition'] : (widget.type == ColumnType.text ? 'Contains' : 'Equals');
  }

  @override
  void didUpdateWidget(covariant _RankingFilterCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final f = widget.activeFilter;
    if (f == null) {
      if (_ctrl.text.isNotEmpty) _ctrl.clear();
      _condition = widget.type == ColumnType.text ? 'Contains' : 'Equals';
    } else if (f['mode'] == 'quick') {
      String newVal = f['value']?.toString() ?? "";
      if (_ctrl.text != newVal) {
        _ctrl.text = newVal;
      }
      _condition = f['condition'];
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _getSymbol() {
    switch (_condition) {
      case 'Contains': return "inc";
      case 'Does Not Contain': return "!inc";
      case 'Begins With': return "A..";
      case 'Ends With': return "..Z";
      case 'Greater Than': return ">";
      case 'Less Than': return "<";
      case 'Before': return "<d";
      case 'After': return ">d";
      case 'Does Not Equal': return "≠";
      default: return "=";
    }
  }

  @override
  Widget build(BuildContext context) {
    bool hasAdvanced = widget.activeFilter != null && widget.activeFilter!['mode'] != 'quick';
    bool showAdvanced = widget.width > 55;
    bool showSymbol = widget.width > 40;

    return Container(
      width: widget.width,
      height: 26,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey.shade300, width: 1), bottom: BorderSide(color: Colors.grey.shade400, width: 1)),
      ),
      child: Row(
        children: [
          if (showSymbol)
            GestureDetector(
              onTapDown: (details) async {
                List<String> items = [];
                if (widget.type == ColumnType.text) {
                  items = ['Equals', 'Does Not Equal', 'Contains', 'Does Not Contain', 'Begins With', 'Ends With'];
                } else if (widget.type == ColumnType.numeric) {
                  items = ['Equals', 'Does Not Equal', 'Greater Than', 'Less Than'];
                } else {
                  items = ['Equals', 'Before', 'After'];
                }

                final result = await showMenu<String>(
                  context: context,
                  position: RelativeRect.fromLTRB(details.globalPosition.dx, details.globalPosition.dy + 10, details.globalPosition.dx, 0),
                  items: items.map((e) => PopupMenuItem(value: e, height: 30, child: Text(e, style: const TextStyle(fontSize: 10)))).toList(),
                );
                if (result != null) {
                  setState(() => _condition = result);
                  widget.onQuickFilter(widget.colKey, _condition, _ctrl.text);
                }
              },
              child: Container(
                width: 20,
                alignment: Alignment.center,
                color: Colors.grey.shade100,
                child: Text(_getSymbol(), style: const TextStyle(fontSize: 8, color: Colors.green, fontWeight: FontWeight.bold)),
              ),
            ),
          Expanded(
            child: TextField(
              controller: _ctrl,
              style: const TextStyle(fontSize: 9, height: 1.0),
              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 2, vertical: 6), border: InputBorder.none),
              onChanged: (v) => widget.onQuickFilter(widget.colKey, _condition, v),
            ),
          ),
          if (showAdvanced)
            GestureDetector(
              onTapDown: (details) => widget.onAdvancedTap(details.globalPosition),
              child: Container(
                width: 16,
                alignment: Alignment.center,
                child: Icon(Icons.filter_alt_outlined, size: 10, color: hasAdvanced ? Colors.orange : Colors.blueGrey.shade300),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// RE-ORDER RULE BUILDER DIALOG
// ============================================================================
// ============================================================================
// RE-ORDER RULE BUILDER DIALOG
// ============================================================================
class _RuleBuilderDialog extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> initialRules;
  final Function(List<Map<String, dynamic>>) onSave;
  final int customColCount;

  const _RuleBuilderDialog({required this.title, required this.initialRules, required this.onSave, required this.customColCount});

  @override
  State<_RuleBuilderDialog> createState() => _RuleBuilderDialogState();
}

class _RuleBuilderDialogState extends State<_RuleBuilderDialog> {
  late List<Map<String, dynamic>> _rules;

  @override
  void initState() {
    super.initState();
    _rules = List<Map<String, dynamic>>.from(widget.initialRules.map((r) => Map<String, dynamic>.from(r)));
    if (_rules.isEmpty) {
      _rules.add({'var': 'W', 'op': '>=', 'val': '', 'res': ''});
    }
  }

  void _addRule() {
    setState(() {
      _rules.add({'var': 'W', 'op': '>=', 'val': '', 'res': ''});
    });
  }

  bool _isImpossible(Map<String, dynamic> rule) {
    String op = rule['op'];
    double? left = double.tryParse(rule['var']); 
    double? right = double.tryParse(rule['val']?.toString() ?? '');
    
    if (left != null && right != null) {
      if (op == '=') return left != right;
      if (op == '>') return left <= right;
      if (op == '<') return left >= right;
      if (op == '>=') return left < right;
      if (op == '<=') return left > right;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.rule_folder_rounded, color: Color(0xFF27AE60)),
          const SizedBox(width: 12),
          Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.grey))
        ],
      ),
      content: SizedBox(
        width: 550,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                "Rules are checked from top to bottom. The first matching rule sets the Re-Order value. If no rules match, 0 is returned.",
                style: TextStyle(fontSize: 12, color: Colors.blueGrey, fontStyle: FontStyle.italic),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: List.generate(_rules.length, (index) {
                    final rule = _rules[index];
                    bool impossible = _isImpossible(rule);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      decoration: BoxDecoration(
                        color: impossible ? Colors.red.shade50 : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: impossible ? Colors.red.shade200 : Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2))
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 1. Variable Square (70x70)
                          _buildSquareBox(
                            width: 70,
                            height: 70,
                            child: _ruleVarDropdown(index),
                            borderColor: Colors.blue.shade600,
                          ),
                          const SizedBox(width: 10),

                          // 2. Operator Square (70x70) - MOVED HERE
                          _buildSquareBox(
                            width: 70,
                            height: 70,
                            borderColor: Colors.blue.shade600,
                            child: Center(
                              child: DropdownButton<String>(
                                value: rule['op'],
                                isExpanded: true,
                                underline: const SizedBox(),
                                icon: const SizedBox.shrink(),
                                alignment: Alignment.center,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.blue),
                                items: ['>', '<', '=', '>=', '<='].map((o) => DropdownMenuItem(value: o, child: Center(child: Text(o)))).toList(),
                                onChanged: (v) => setState(() => _rules[index]['op'] = v),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          
                          // 3. Value Input Square (70x70)
                          _buildSimpleInputBox(
                            width: 70,
                            height: 70,
                            hint: "Number",
                            color: Colors.blue.shade600,
                            borderColor: Colors.blue.shade600,
                            controller: TextEditingController(text: rule['val']?.toString() ?? "")..selection = TextSelection.collapsed(offset: (rule['val']?.toString() ?? "").length),
                            onChanged: (v) {
                              _rules[index]['val'] = v;
                            },
                          ),
                          const SizedBox(width: 10),

                          // 4. Result Input Square (70x70)
                          _buildSimpleInputBox(
                            width: 70,
                            height: 70,
                            hint: "Result",
                            color: const Color(0xFF27AE60),
                            borderColor: const Color(0xFF27AE60),
                            controller: TextEditingController(text: rule['res']?.toString() ?? "")..selection = TextSelection.collapsed(offset: (rule['res']?.toString() ?? "").length),
                            onChanged: (v) => _rules[index]['res'] = v,
                          ),
                          
                          const Spacer(),
                          
                          // Delete Action
                          IconButton(
                            onPressed: () => setState(() => _rules.removeAt(index)),
                            icon: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                              child: const Icon(Icons.delete_forever_rounded, size: 20, color: Colors.redAccent),
                            ),
                          )
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ),
            // Add Rule Button
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: IconButton(
                  onPressed: _addRule,
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: const Icon(Icons.add_rounded, color: Colors.blue, size: 28),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), 
          child: Text("CANCEL", style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold))
        ),
        ElevatedButton(
          onPressed: () {
            final validRules = _rules.where((r) => r['val'].toString().isNotEmpty && r['res'].toString().isNotEmpty).toList();
            widget.onSave(validRules);
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF27AE60), 
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
          ),
          child: const Text("APPLY RULES", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildSquareBox({required double width, required double height, required Widget child, required Color borderColor}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: child,
    );
  }

  Widget _buildSimpleInputBox({
    required double width, 
    required double height, 
    required String hint, 
    required Color color, 
    required Color borderColor,
    required TextEditingController controller,
    required Function(String) onChanged,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Center(
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9.\-+*()/=\s]')),
            TextInputFormatter.withFunction((oldVal, newVal) => newVal.copyWith(text: newVal.text.toUpperCase())),
          ],
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: color.withValues(alpha: 0.3), fontSize: 11),
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            isDense: true,
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _ruleVarDropdown(int index) {
    // Generate options dynamically based on available columns
    List<String> options = ['W', 'X', 'Y', 'Z', 'A', 'B', 'C', 'P', 'S', 'L']; 
    for (int i = 0; i < widget.customColCount; i++) {
      options.add(String.fromCharCode(68 + i)); // D, E, F...
    }
    
    String current = _rules[index]['var'];
    
    return Center(
      child: DropdownButton<String>(
        value: options.contains(current) ? current : null,
        hint: Text(current.isEmpty ? "Var" : current, style: const TextStyle(fontSize: 11)),
        isExpanded: true,
        underline: const SizedBox(),
        alignment: Alignment.center,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
        items: options.map((o) => DropdownMenuItem(value: o, child: Center(child: Text(o)))).toList(),
        onChanged: (v) => setState(() => _rules[index]['var'] = v),
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
