import 'dart:math';

class MonthlyStat {
  final DateTime startDate;
  final DateTime endDate;
  int saleCount = 0;
  double higherSale = 0.0;
  double monthSale = 0.0;
  double specialOrderQty = 0.0;

  MonthlyStat({required this.startDate, required this.endDate});

  Map<String, dynamic> toJson() => {
        's': startDate.toIso8601String(),
        'e': endDate.toIso8601String(),
        'sc': saleCount,
        'hs': higherSale,
        'ms': monthSale,
        'so': specialOrderQty,
      };

  factory MonthlyStat.fromJson(Map<String, dynamic> json) {
    return MonthlyStat(
      startDate: DateTime.parse(json['s']),
      endDate: DateTime.parse(json['e']),
    )
      ..saleCount = (json['sc'] as num?)?.toInt() ?? 0
      ..higherSale = (json['hs'] as num?)?.toDouble() ?? 0.0
      ..monthSale = (json['ms'] as num?)?.toDouble() ?? 0.0
      ..specialOrderQty = (json['so'] as num?)?.toDouble() ?? 0.0;
  }
}

class ProductRanking {
  final String id;
  final String name;
  final int pack;
  final bool isActive;
  final String patent;
  final String category;
  final String rack;
  final double mrp;
  final double pRate;
  final String genericName;
  final String preferredWholesale;
  final String offer;

  List<MonthlyStat> monthlyStats;
  double weightedScore = 0.0;
  double reOrderScore = 0.0;
  double warningScore = 0.0;
  double lastSaleQty = 0.0;
  double maxOrderLevel = 0.0;
  double currentStock = 0.0;

  double mavg = 0.0;
  double specialOrders = 0.0;
  Map<String, double> customCriteria = {};

  double get calculatedRank => weightedScore;
  double get reorderLevel => reOrderScore;

  ProductRanking({
    required this.id,
    required this.name,
    required this.pack,
    required this.isActive,
    required this.patent,
    required this.category,
    required this.rack,
    required this.mrp,
    required this.pRate,
    required this.genericName,
    required this.preferredWholesale,
    this.offer = "",
    required this.monthlyStats,
    this.maxOrderLevel = 0.0,
    this.weightedScore = 0.0,
    this.reOrderScore = 0.0,
    this.lastSaleQty = 0.0,
    this.currentStock = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'pack': pack,
        'isActive': isActive,
        'patent': patent,
        'category': category,
        'rack': rack,
        'mrp': mrp,
        'pRate': pRate,
        'genericName': genericName,
        'preferredWholesale': preferredWholesale,
        'offer': offer,
        'monthlyStats': monthlyStats.map((m) => m.toJson()).toList(),
        'weightedScore': weightedScore,
        'reOrderScore': reOrderScore,
        'warningScore': warningScore,
        'lastSaleQty': lastSaleQty,
        'maxOrderLevel': maxOrderLevel,
        'currentStock': currentStock,
        'mavg': mavg,
        'specialOrders': specialOrders,
        'customCriteria': customCriteria,
      };

  factory ProductRanking.fromJson(Map<String, dynamic> json) {
    var statsList = (json['monthlyStats'] as List?)
            ?.map((m) => MonthlyStat.fromJson(m as Map<String, dynamic>))
            .toList() ??
        [];
    var customMap = (json['customCriteria'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        ) ??
        {};

    return ProductRanking(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      pack: (json['pack'] as num?)?.toInt() ?? 1,
      isActive: json['isActive'] == true,
      patent: json['patent']?.toString() ?? '',
      category: json['category']?.toString() ?? 'General',
      rack: json['rack']?.toString() ?? '',
      mrp: (json['mrp'] as num?)?.toDouble() ?? 0.0,
      pRate: (json['pRate'] as num?)?.toDouble() ?? 0.0,
      genericName: json['genericName']?.toString() ?? '',
      preferredWholesale: json['preferredWholesale']?.toString() ?? '-',
      offer: json['offer']?.toString() ?? '',
      monthlyStats: statsList,
      weightedScore: (json['weightedScore'] as num?)?.toDouble() ?? 0.0,
      reOrderScore: (json['reOrderScore'] as num?)?.toDouble() ?? 0.0,
      lastSaleQty: (json['lastSaleQty'] as num?)?.toDouble() ?? 0.0,
      currentStock: (json['currentStock'] as num?)?.toDouble() ?? 0.0,
      maxOrderLevel: (json['maxOrderLevel'] as num?)?.toDouble() ?? 0.0,
    )
      ..warningScore = (json['warningScore'] as num?)?.toDouble() ?? 0.0
      ..mavg = (json['mavg'] as num?)?.toDouble() ?? 0.0
      ..specialOrders = (json['specialOrders'] as num?)?.toDouble() ?? 0.0
      ..customCriteria = customMap;
  }
}

class ProductRankingCalculator {
  static void calculateRankings({
    required List<ProductRanking> rankings,
    required String rankFormula,
    List<Map<String, dynamic>> rankRules = const [],
    required String reOrderFormula,
    required List<Map<String, dynamic>> reOrderRules,
    required String warningFormula,
    List<Map<String, dynamic>> warningRules = const [],
    required String maxOrderFormula,
    required List<Map<String, dynamic>> maxOrderRules,
    required List<Map<String, dynamic>> customMetricColumns,
    int mavgInterval = 0,
    int specialInterval = 0,
  }) {
    bool allValid = true;
    bool allReValid = true;
    bool allWarValid = true;

    bool hasV(String f, String v) =>
        RegExp('(?<![A-Z0-9\\.])$v(?![A-Z0-9\\.])').hasMatch(f.toUpperCase());

    if (hasV(rankFormula, 'W') ||
        hasV(rankFormula, 'X') ||
        hasV(rankFormula, 'Y') ||
        hasV(rankFormula, 'Z')) {
      allValid = false;
    }
    if (hasV(reOrderFormula, 'Y') || hasV(reOrderFormula, 'Z')) {
      allReValid = false;
    }
    if (hasV(warningFormula, 'X') || hasV(warningFormula, 'Z')) {
      allWarValid = false;
    }

    for (var product in rankings) {
      bool hasActivity = product.currentStock > 0 ||
          product.lastSaleQty > 0 ||
          product.monthlyStats.any((m) =>
              m.monthSale > 0 ||
              m.higherSale > 0 ||
              m.saleCount > 0 ||
              m.specialOrderQty > 0);

      if (!hasActivity) {
        product.mavg = 0.0;
        product.specialOrders = 0.0;
        product.weightedScore = 0.0;
        product.reOrderScore = 0.0;
        product.warningScore = 0.0;
        product.maxOrderLevel = 0.0;
        continue;
      }

      Map<String, double> vars = {};

      vars['P'] = product.pack.toDouble();
      vars['A'] = double.tryParse(getMovingAverage(product, interval: mavgInterval)) ?? 0.0;
      product.mavg = vars['A']!;
      vars['B'] = product.monthlyStats
          .take(specialInterval == 0 ? product.monthlyStats.length : specialInterval)
          .fold(0.0, (sum, m) => sum + m.specialOrderQty);
      product.specialOrders = vars['B']!;
      vars['C'] = product.lastSaleQty;
      vars['L'] = product.lastSaleQty;
      vars['S'] = product.currentStock;

      for (int i = 0; i < customMetricColumns.length; i++) {
        String letter = String.fromCharCode(68 + i);
        final col = customMetricColumns[i];
        double minR = (col['minRank'] as num?)?.toDouble() ?? 0.0;
        String valStr = calculateCustomMetric(
          product: product,
          rankPart: col['rank'] as String? ?? "1st HIGHER",
          metricPart: col['metric'] as String? ?? "TOTAL MONTH SALE",
          interval: (col['interval'] as num?)?.toInt() ?? 0,
          minRank: minR,
        );
        vars[letter] = double.tryParse(valStr) ?? 0.0;
        product.customCriteria[letter] = vars[letter]!;
      }

      // 1. Calc RANK (W)
      if (rankRules.isNotEmpty) {
        product.weightedScore = evaluateRules(rankRules, vars);
      } else {
        double? score = allValid ? evaluateFormula(rankFormula, vars) : null;
        product.weightedScore = score ?? 0.0;
      }
      vars['W'] = product.weightedScore;

      // 2. Calc REORDER (Y)
      if (reOrderRules.isNotEmpty) {
        product.reOrderScore = evaluateRules(reOrderRules, vars);
      } else {
        double? reScore = allReValid ? evaluateFormula(reOrderFormula, vars) : null;
        product.reOrderScore = reScore ?? 0.0;
      }
      vars['Y'] = product.reOrderScore;

      // 3. Calc WARNING (X)
      if (warningRules.isNotEmpty) {
        product.warningScore = evaluateRules(warningRules, vars);
      } else {
        double? warScore = allWarValid ? evaluateFormula(warningFormula, vars) : null;
        product.warningScore = warScore ?? 0.0;
      }
      vars['X'] = product.warningScore;

      // 4. Calc MAXORDER (Z)
      if (maxOrderRules.isNotEmpty) {
        product.maxOrderLevel = evaluateRules(maxOrderRules, vars);
      } else {
        double? maxScore = evaluateFormula(maxOrderFormula, vars);
        product.maxOrderLevel = maxScore ?? (product.reOrderScore * 2.0).ceilToDouble();
      }
      vars['Z'] = product.maxOrderLevel;
    }
  }

  static String cleanFormat(double val) {
    if (val == 0) return "0";
    if (val == val.toInt()) return val.toInt().toString();
    return val.toStringAsFixed(1);
  }

  static String getMovingAverage(ProductRanking r, {int interval = 0}) {
    if (r.monthlyStats.isEmpty) return "0.0";
    List<MonthlyStat> stats = r.monthlyStats;
    if (interval > 0) stats = stats.take(interval).toList();

    List<double> chronoSales = stats.map((e) => e.monthSale).toList().reversed.toList();
    int firstSaleIndex = 0;
    bool hasSales = false;
    for (int i = 0; i < chronoSales.length; i++) {
      if (chronoSales[i] != 0) {
        firstSaleIndex = i;
        hasSales = true;
        break;
      }
    }
    if (!hasSales) return "0";

    List<double> activeSales = chronoSales.sublist(firstSaleIndex);
    double totalSum = activeSales.fold(0.0, (a, b) => a + b);
    int divisor = activeSales.length < 3 ? 3 : activeSales.length;
    return cleanFormat(totalSum / divisor);
  }

  static String calculateCustomMetric({
    required ProductRanking product,
    required String rankPart,
    required String metricPart,
    int interval = 0,
    double minRank = 0.0,
  }) {
    if (product.monthlyStats.isEmpty) {
      if (minRank > 0) return cleanFormat(minRank);
      return "0";
    }

    List<MonthlyStat> stats = product.monthlyStats;
    if (interval > 0) stats = stats.take(interval).toList();

    double resVal = 0.0;

    if (metricPart == "MOVING AVERAGE" || metricPart == "TOTAL SALE AVERAGE") {
      resVal = double.tryParse(getMovingAverage(product, interval: interval)) ?? 0.0;
    } else {
      List<double> monthSales = stats.map((e) => e.monthSale).toList()..sort();
      List<double> higherSales = stats.map((e) => e.higherSale).toList()..sort();
      List<int> saleCounts = stats.map((e) => e.saleCount).toList()..sort();

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

    return cleanFormat(resVal);
  }

  static double evaluateRules(List<Map<String, dynamic>> rules, Map<String, double> vars) {
    const double eps = 0.0001;
    for (var rule in rules) {
      try {
        String varName = rule['var'] ?? 'Y';
        String op = rule['op'] ?? '>=';
        double target = evaluateFormula(rule['val']?.toString() ?? '0', vars) ?? 0.0;
        double result = evaluateFormula(rule['res']?.toString() ?? '0', vars) ?? 0.0;
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

  static final RegExp _funcRegex = RegExp(r"(AVERAGE|MAX|MIN|IF)\(([^()]+)\)");
  static final RegExp _parenRegex = RegExp(r"\(([^()]+)\)");
  static final Map<String, RegExp> _varRegexCache = {};

  static RegExp _getVarRegex(String k) {
    return _varRegexCache.putIfAbsent(k, () => RegExp('(?<![A-Z0-9\\.])$k(?![A-Z0-9\\.])'));
  }

  static double? evaluateFormula(String formula, Map<String, double> vars) {
    try {
      String s = formula.toUpperCase().replaceAll(' ', '');
      if (s.startsWith('=')) s = s.substring(1);
      if (s.isEmpty) return 0.0;

      List<String> sortedKeys = vars.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
      for (var k in sortedKeys) {
        s = s.replaceAll(_getVarRegex(k), vars[k].toString());
      }
      return _recursiveEval(s);
    } catch (_) {
      return null;
    }
  }

  static double? _recursiveEval(String s) {
    int safety = 0;
    while (safety < 50) {
      safety++;
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
            } else if (name == "MIN") {
              result = vals.reduce(min);
            } else if (name == "AVERAGE") {
              result = vals.reduce((a, b) => a + b) / vals.length;
            }
          }
        }
        s = s.replaceRange(fMatch.start, fMatch.end, result.toString());
        continue;
      }

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

  static List<String> _splitParams(String s) {
    List<String> res = [];
    int depth = 0;
    StringBuffer sb = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      String char = s[i];
      if (char == '(') depth++;
      else if (char == ')') depth--;
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

  static double? _evaluateFinalMath(String expr) {
    const double eps = 0.0001;
    final List<String> ops = [">=", "<=", "!=", ">", "<", "="];
    for (var op in ops) {
      if (expr.contains(op)) {
        int idx = expr.indexOf(op);
        String leftPart = expr.substring(0, idx).trim();
        String rightPart = expr.substring(idx + op.length).trim();
        double left = _evaluateBasicMath(leftPart) ?? 0.0;
        double right = _evaluateBasicMath(rightPart) ?? 0.0;
        bool res = false;
        if (op == ">") res = left > (right + eps);
        else if (op == "<") res = left < (right - eps);
        else if (op == ">=") res = left >= (right - eps);
        else if (op == "<=") res = left <= (right + eps);
        else if (op == "=") res = (left - right).abs() < eps;
        else if (op == "!=") res = (left - right).abs() >= eps;
        return res ? 1.0 : 0.0;
      }
    }
    return _evaluateBasicMath(expr);
  }

  static double? _evaluateBasicMath(String expr) {
    try {
      RegExp mdRegex = RegExp("(-?[0-9.]+(?:[eE]-?[0-9]+)?)([*\\/])(-?[0-9.]+(?:[eE]-?[0-9]+)?)");
      int s1 = 0;
      while (mdRegex.hasMatch(expr) && s1 < 20) {
        s1++;
        expr = expr.replaceAllMapped(mdRegex, (m) {
          double a = double.tryParse(m.group(1)!) ?? 0;
          double b = double.tryParse(m.group(3)!) ?? 0;
          return m.group(2) == "*" ? (a * b).toString() : (b.abs() < 1e-12 ? "0" : (a / b).toString());
        });
      }

      List<String> tokens = [];
      String cur = "";
      for (int i = 0; i < expr.length; i++) {
        String c = expr[i];
        bool isSign = (c == "-" && (i == 0 || "+-*/".contains(expr[i - 1]) || (i > 0 && expr[i - 1].toUpperCase() == "E")));
        if (isSign) {
          cur += c;
          continue;
        }
        if ("+-".contains(c)) {
          if (cur.isNotEmpty) tokens.add(cur);
          tokens.add(c);
          cur = "";
        } else {
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
    } catch (_) {
      return null;
    }
  }
}

