import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product_ranking.dart';

class RankingEngineService {
  static final RankingEngineService instance = RankingEngineService._internal();
  RankingEngineService._internal();

  Map<String, ProductRanking> _cachedRankingsMap = {};
  Map<String, ProductRanking> get cachedRankingsMap => _cachedRankingsMap;

  void updateCachedRankings(List<ProductRanking> rankings, SharedPreferences prefs) {
    _cachedRankingsMap = {};
    for (var pr in rankings) {
      if (pr.id.isNotEmpty) _cachedRankingsMap[pr.id] = pr;
      if (pr.name.isNotEmpty) _cachedRankingsMap[pr.name.toUpperCase().trim()] = pr;
    }
    final encodedList = rankings.take(2000).map((r) => jsonEncode(r.toJson())).toList();
    prefs.setStringList('pr_cached_rankings_v2', encodedList);
  }

  Future<Map<String, ProductRanking>> getProductRankingsMap(SharedPreferences prefs) async {
    if (_cachedRankingsMap.isNotEmpty) {
      return _cachedRankingsMap;
    }

    final cachedList = prefs.getStringList('pr_cached_rankings_v2');
    if (cachedList != null && cachedList.isNotEmpty) {
      final Map<String, ProductRanking> map = {};
      for (var item in cachedList) {
        try {
          final pr = ProductRanking.fromJson(jsonDecode(item));
          if (pr.id.isNotEmpty) map[pr.id] = pr;
          if (pr.name.isNotEmpty) map[pr.name.toUpperCase().trim()] = pr;
        } catch (_) {}
      }
      if (map.isNotEmpty) {
        _cachedRankingsMap = map;
        return _cachedRankingsMap;
      }
    }
    return _cachedRankingsMap;
  }
}
