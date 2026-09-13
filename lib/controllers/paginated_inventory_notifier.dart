import 'package:flutter/material.dart';
import '../providers/pharmacy_provider.dart';
import '../repositories/product_repository.dart';
import '../utils/search_debouncer.dart';

class PaginatedInventoryNotifier extends ChangeNotifier {
  final SearchDebouncer _debouncer = SearchDebouncer(milliseconds: 250);
  List<Product> _items = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  final int _pageSize = 20;
  String _currentQuery = '';
  String _filterMode = 'Available';
  final bool _isMasterList;
  PharmacyProvider? _pharmacyProvider;
  int _lastStockVersion = -1;

  List<Product> get items => _items;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  int get offset => _offset;
  String get currentQuery => _currentQuery;
  String get filterMode => _filterMode;

  PaginatedInventoryNotifier({
    bool isMasterList = false,
    PharmacyProvider? pharmacyProvider,
  })  : _isMasterList = isMasterList,
        _pharmacyProvider = pharmacyProvider {
    if (pharmacyProvider != null) {
      _lastStockVersion = pharmacyProvider.stockVersion;
    }
  }

  void updateProvider(PharmacyProvider provider) {
    _pharmacyProvider = provider;
    if (_lastStockVersion != provider.stockVersion) {
      _lastStockVersion = provider.stockVersion;
      if (_items.isNotEmpty || _offset > 0) {
        refresh();
      }
    }
  }

  Future<void> loadInitial(String query, {String? filterMode}) async {
    _currentQuery = query;
    if (filterMode != null) {
      _filterMode = filterMode;
    }
    _offset = 0;
    _hasMore = true;
    _items = [];
    await fetchNextPage();
  }

  Future<void> fetchNextPage() async {
    if (_isLoading || !_hasMore) return;
    _isLoading = true;
    notifyListeners();

    try {
      List<Product> newBatch;
      if (_isMasterList) {
        newBatch = await ProductRepository.getPagedProducts(
          limit: _pageSize,
          offset: _offset,
          searchQuery: _currentQuery,
          pharmacyProvider: _pharmacyProvider,
        );
      } else {
        newBatch = await ProductRepository.getPagedStockBatches(
          limit: _pageSize,
          offset: _offset,
          searchQuery: _currentQuery,
          filterMode: _filterMode,
          pharmacyProvider: _pharmacyProvider,
        );
      }

      if (newBatch.length < _pageSize) {
        _hasMore = false;
      }

      _items.addAll(newBatch);
      _offset += newBatch.length;
    } catch (e) {
      debugPrint("Error fetching next page: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    await loadInitial(_currentQuery, filterMode: _filterMode);
  }

  void onSearchChanged(String query, {String? filterMode}) {
    _debouncer.run(() {
      loadInitial(query, filterMode: filterMode);
    });
  }

  @override
  void dispose() {
    _debouncer.dispose();
    super.dispose();
  }
}
