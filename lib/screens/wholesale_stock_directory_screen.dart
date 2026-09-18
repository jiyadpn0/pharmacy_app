import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../models/erp_models.dart';
import '../providers/pharmacy_provider.dart';
import '../utils/search_debouncer.dart';
import '../utils/theme_constants.dart';

class WholesaleStockDirectoryScreen extends StatefulWidget {
  const WholesaleStockDirectoryScreen({super.key});

  @override
  State<WholesaleStockDirectoryScreen> createState() => _WholesaleStockDirectoryScreenState();
}

class _WholesaleStockDirectoryScreenState extends State<WholesaleStockDirectoryScreen> {
  bool _isLoadingWholesalers = false;
  bool _isLoadingProducts = false;

  // Master Lists loaded from DB
  List<Map<String, dynamic>> _masterWholesalers = [];
  List<WholesaleStockItem> _supplierProducts = [];

  // Cached Filtered Results for UI
  List<WholesaleStockItem> _filteredItems = [];
  List<Map<String, dynamic>> _filteredCategoriesList = [];

  // Active Selections
  String _selectedWholesaler = "";
  String _selectedCategory = "ALL";

  // Search Queries
  String _searchQuery = "";

  // Controllers, Focus Nodes & Debouncers
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _wholesalerSearchCtrl = TextEditingController();
  final TextEditingController _categorySearchCtrl = TextEditingController();

  final FocusNode _wholesalerFocusNode = FocusNode();
  final FocusNode _categoryFocusNode = FocusNode();

  final SearchDebouncer _mainSearchDebouncer = SearchDebouncer(milliseconds: 100);

  @override
  void initState() {
    super.initState();

    _searchCtrl.addListener(() {
      _mainSearchDebouncer.run(() {
        if (mounted && _searchQuery != _searchCtrl.text) {
          _searchQuery = _searchCtrl.text;
          _applyLocalTableFilters();
        }
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadWholesalers();
    });
  }

  @override
  void dispose() {
    _mainSearchDebouncer.dispose();

    _searchCtrl.dispose();
    _wholesalerSearchCtrl.dispose();
    _categorySearchCtrl.dispose();

    _wholesalerFocusNode.dispose();
    _categoryFocusNode.dispose();
    super.dispose();
  }

  /// 1. Load Wholesaler List (Ultra-fast <10ms)
  Future<void> _loadWholesalers() async {
    setState(() => _isLoadingWholesalers = true);
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    try {
      final list = await provider.getWholesalerNamesWithCounts();
      if (mounted) {
        _masterWholesalers = list;
        setState(() {
          _isLoadingWholesalers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingWholesalers = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading wholesalers: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 2. Load Products for Selected Wholesaler (Ultra-fast <5ms)
  Future<void> _loadProductsForWholesaler(String supplierName) async {
    if (supplierName.trim().isEmpty) {
      setState(() {
        _supplierProducts = [];
        _filteredItems = [];
        _filteredCategoriesList = [];
      });
      return;
    }

    setState(() => _isLoadingProducts = true);
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    try {
      final items = await provider.getWholesaleDirectoryForSupplier(supplierName);
      if (mounted) {
        _supplierProducts = items;
        _buildCategoriesList();
        _applyLocalTableFilters();
        setState(() {
          _isLoadingProducts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingProducts = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading products for $supplierName: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Build Categories List for current Wholesaler
  void _buildCategoriesList() {
    Map<String, int> catCounts = {};
    int totalCount = _supplierProducts.length;

    for (var p in _supplierProducts) {
      String c = p.categoryName.isEmpty ? "General" : p.categoryName;
      catCounts[c] = (catCounts[c] ?? 0) + 1;
    }

    List<String> sortedCats = catCounts.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    List<Map<String, dynamic>> list = [
      {'name': "ALL", 'count': totalCount}
    ];

    for (var c in sortedCats) {
      list.add({'name': c, 'count': catCounts[c] ?? 0});
    }

    _filteredCategoriesList = list;
  }

  /// Instant Table Filter (0ms)
  void _applyLocalTableFilters() {
    final String q = _searchQuery.trim().toLowerCase();
    final String selectedCLower = _selectedCategory.toLowerCase();

    List<WholesaleStockItem> list = [];

    for (int i = 0; i < _supplierProducts.length; i++) {
      final p = _supplierProducts[i];

      // Category filter
      if (selectedCLower != 'all') {
        String c = p.categoryName.isEmpty ? "general" : p.categoryName.toLowerCase();
        if (c != selectedCLower) continue;
      }

      // Search query filter
      if (q.isNotEmpty) {
        bool matchesName = p.productName.toLowerCase().contains(q);
        bool matchesCompany = p.companyName.toLowerCase().contains(q);
        bool matchesGeneric = p.genericName.toLowerCase().contains(q);
        bool matchesCategory = p.categoryName.toLowerCase().contains(q);

        if (!matchesName && !matchesCompany && !matchesGeneric && !matchesCategory) {
          continue;
        }
      }

      list.add(p);
    }

    setState(() {
      _filteredItems = list;
    });
  }

  Future<void> _exportExcel() async {
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    if (_filteredItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No items to export!"), backgroundColor: Colors.orange),
      );
      return;
    }

    String cleanWholesaler = _selectedWholesaler.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
    String defaultFileName = 'Wholesale_Directory_${cleanWholesaler}_${DateFormat('ddMMyyyy').format(DateTime.now())}.xlsx';

    String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Save Wholesale Directory Excel',
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (outputFile != null) {
      final bytes = await provider.exportWholesaleStockToExcelBytes(_filteredItems, _selectedWholesaler, _selectedCategory);

      if (bytes != null) {
        await File(outputFile).writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Wholesale directory exported successfully!"), backgroundColor: Colors.green),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeColors = isDark ? AppThemeColors.dark : AppThemeColors.light;

    int totalItemsCount = _filteredItems.length;

    return Scaffold(
      backgroundColor: themeColors.background,
      body: Column(
        children: [
          // ==========================================
          // TOP HEADER TOOLBAR
          // ==========================================
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                    : [const Color(0xFF1E293B), const Color(0xFF334155)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade600.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade400.withOpacity(0.4)),
                  ),
                  child: const Icon(Icons.storefront_rounded, color: Colors.blueAccent, size: 24),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "WHOLESALE MEDICINE DIRECTORY",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Select a wholesale supplier dropdown to view company names and categories",
                      style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
                    ),
                  ],
                ),
                const Spacer(),

                // Refresh Button
                IconButton(
                  onPressed: () {
                    _wholesalerSearchCtrl.clear();
                    _categorySearchCtrl.clear();
                    _searchCtrl.clear();
                    _selectedWholesaler = "";
                    _selectedCategory = "ALL";
                    _loadWholesalers();
                  },
                  tooltip: "Refresh Wholesalers",
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 8),

                // Excel Export Button
                ElevatedButton.icon(
                  onPressed: _exportExcel,
                  icon: const Icon(Icons.explicit_outlined, size: 18, color: Colors.white),
                  label: const Text("Export Excel", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),

          // ==========================================
          // TOP DROPDOWNS & FILTER BAR
          // ==========================================
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: themeColors.surface,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 1. WHOLESALER SEARCHABLE DROPDOWN
                _buildWholesalerAutocomplete(themeColors, isDark),
                const SizedBox(width: 16),

                // 2. CATEGORY SEARCHABLE DROPDOWN
                _buildCategoryAutocomplete(themeColors, isDark),
                const SizedBox(width: 16),

                // 3. SEARCH MEDICINE INPUT
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "SEARCH MEDICINE",
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade600),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.grey.shade300,
                            width: 1,
                          ),
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: "Search medicine or company...",
                            hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                            prefixIcon: const Icon(Icons.search, size: 16, color: Colors.grey),
                            suffixIcon: _searchCtrl.text.isNotEmpty
                                ? InkWell(
                                    onTap: () {
                                      _searchCtrl.clear();
                                      _searchQuery = "";
                                      _applyLocalTableFilters();
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      child: Icon(Icons.close, size: 14, color: Colors.grey.shade600),
                                    ),
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ==========================================
          // MAIN MEDICINE DIRECTORY TABLE
          // ==========================================
          Expanded(
            child: _selectedWholesaler.isEmpty
                ? _buildEmptyStatePlaceholder(themeColors)
                : Column(
                    children: [
                      // Data Table
                      Expanded(
                        child: _isLoadingProducts
                            ? const Center(child: CircularProgressIndicator())
                            : _filteredItems.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.inventory_2_outlined, size: 54, color: Colors.grey.shade400),
                                        const SizedBox(height: 12),
                                        Text(
                                          "No medicines found for $_selectedWholesaler",
                                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: themeColors.primaryText),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          "Try selecting a different category or search query",
                                          style: TextStyle(fontSize: 12, color: themeColors.secondaryText),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: _filteredItems.length + 1, // Header + Rows
                                    itemBuilder: (context, index) {
                                      if (index == 0) {
                                        return _buildTableHeader(themeColors, isDark);
                                      }
                                      final item = _filteredItems[index - 1];
                                      return _buildTableRow(index, item, themeColors, isDark);
                                    },
                                  ),
                      ),

                      // ==========================================
                      // SUMMARY FOOTER BAR
                      // ==========================================
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFF1E293B),
                          border: Border(
                            top: BorderSide(color: Colors.blue.shade700, width: 2),
                          ),
                        ),
                        child: Row(
                          children: [
                            _buildFooterStat("TOTAL MEDICINES", "$totalItemsCount", Icons.medical_information_outlined, Colors.blueAccent),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // --- 1. Wholesaler Autocomplete Dropdown Widget ---
  Widget _buildWholesalerAutocomplete(AppThemeColors themeColors, bool isDark) {
    final options = _masterWholesalers.map((w) => w['name'].toString()).toList();

    return SizedBox(
      width: 320,
      child: _SearchableDropdownWidget(
        label: "1. SELECT WHOLESALER",
        controller: _wholesalerSearchCtrl,
        focusNode: _wholesalerFocusNode,
        nextFocus: _categoryFocusNode,
        allItems: options,
        defaultOption: "Select Wholesaler",
        icon: Icons.storefront_rounded,
        onValueChanged: (v) {
          if (v.isEmpty || v == "Select Wholesaler") {
            _selectedWholesaler = "";
            _selectedCategory = "ALL";
            _categorySearchCtrl.text = "ALL";
            _supplierProducts = [];
            _filteredItems = [];
            _filteredCategoriesList = [];
            setState(() {});
          } else {
            _selectedWholesaler = v;
            _selectedCategory = "ALL";
            _categorySearchCtrl.text = "ALL";
            _loadProductsForWholesaler(v);
          }
        },
      ),
    );
  }

  // --- 2. Category Autocomplete Dropdown Widget ---
  Widget _buildCategoryAutocomplete(AppThemeColors themeColors, bool isDark) {
    final optionsList = _filteredCategoriesList.map((c) => c['name'].toString()).toList();

    return SizedBox(
      width: 260,
      child: _SearchableDropdownWidget(
        label: "2. SELECT CATEGORY",
        controller: _categorySearchCtrl,
        focusNode: _categoryFocusNode,
        enabled: _selectedWholesaler.isNotEmpty,
        allItems: optionsList,
        defaultOption: "ALL",
        icon: Icons.category_rounded,
        onValueChanged: (v) {
          if (v.isEmpty || v == "Select Category" || v == "ALL" || v == "ALL CATEGORIES") {
            _selectedCategory = "ALL";
          } else {
            _selectedCategory = v;
          }
          _applyLocalTableFilters();
        },
      ),
    );
  }

  // --- Empty State Placeholder ---
  Widget _buildEmptyStatePlaceholder(AppThemeColors themeColors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.blue.shade50.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.storefront_outlined, size: 64, color: Colors.blue.shade700),
          ),
          const SizedBox(height: 20),
          Text(
            "Select a Wholesale Supplier",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: themeColors.primaryText),
          ),
          const SizedBox(height: 8),
          Text(
            "Select a wholesale supplier from the top dropdown to load their company names and medicine directory",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: themeColors.secondaryText),
          ),
        ],
      ),
    );
  }

  // --- Table Header ---
  Widget _buildTableHeader(AppThemeColors themeColors, bool isDark) {
    final bgColor = isDark ? const Color(0xFF1E293B) : const Color(0xFF0F172A);
    return Container(
      height: 40,
      color: bgColor,
      child: const Row(
        children: [
          _HeaderCell("SL", width: 50, center: true),
          Expanded(child: _HeaderCell("MEDICINE / PRODUCT NAME", width: double.infinity)),
          _HeaderCell("COMPANY / MANUFACTURER", width: 240),
          _HeaderCell("CATEGORY", width: 180),
          _HeaderCell("MEDICINE RANK", width: 140, center: true),
          _HeaderCell("BALANCE STOCK", width: 130, center: true),
        ],
      ),
    );
  }

  // --- Table Row ---
  Widget _buildTableRow(int sl, WholesaleStockItem item, AppThemeColors themeColors, bool isDark) {
    final rowBg = sl % 2 == 0
        ? (isDark ? const Color(0xFF0F172A) : Colors.white)
        : (isDark ? const Color(0xFF182232) : const Color(0xFFF8FAFC));

    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: rowBg,
        border: Border(bottom: BorderSide(color: themeColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          _DataCell("$sl", width: 50, center: true, textColor: themeColors.secondaryText),

          // Product Name + Packing
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: themeColors.primaryText),
                  ),
                  if (item.packing > 1 || item.unit.isNotEmpty)
                    Text(
                      "Pack: ${item.packing} (${item.unit})",
                      style: TextStyle(fontSize: 10, color: themeColors.secondaryText),
                    ),
                ],
              ),
            ),
          ),

          // Company Name (Manufacturer - Highlighted)
          _DataCellWidget(
            width: 240,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.shade50.withOpacity(isDark ? 0.15 : 1.0),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue.shade200.withOpacity(0.5)),
              ),
              child: Text(
                item.companyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isDark ? Colors.blue.shade200 : Colors.blue.shade900),
              ),
            ),
          ),

          // Category
          _DataCell(item.categoryName, width: 180, textColor: themeColors.primaryText, bold: true),

          // Medicine Rank (from Product Ranking)
          _DataCellWidget(
            width: 140,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: item.rank > 0
                      ? Colors.amber.shade50.withOpacity(isDark ? 0.2 : 1.0)
                      : Colors.grey.shade100.withOpacity(isDark ? 0.1 : 1.0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: item.rank > 0
                        ? Colors.amber.shade400.withOpacity(0.6)
                        : Colors.grey.shade300,
                  ),
                ),
                child: Text(
                  item.rank > 0 ? "#${item.rank}" : "-",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: item.rank > 0
                        ? (isDark ? Colors.amber.shade300 : Colors.amber.shade900)
                        : themeColors.secondaryText,
                  ),
                ),
              ),
            ),
          ),

          // Balance Stock (Total Stock Balance)
          _DataCellWidget(
            width: 130,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: item.currentStock > 0
                      ? Colors.green.shade50.withOpacity(isDark ? 0.2 : 1.0)
                      : Colors.red.shade50.withOpacity(isDark ? 0.15 : 1.0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: item.currentStock > 0
                        ? Colors.green.shade300.withOpacity(0.6)
                        : Colors.red.shade200.withOpacity(0.5),
                  ),
                ),
                child: Text(
                  "${item.currentStock}",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: item.currentStock > 0
                        ? (isDark ? Colors.green.shade300 : const Color(0xFF047857))
                        : (isDark ? Colors.red.shade300 : Colors.red.shade800),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Footer Helper ---
  Widget _buildFooterStat(String title, String value, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: color)),
          ],
        ),
      ],
    );
  }
}

// ==========================================
// TABLE CELL HELPER WIDGETS
// ==========================================
class _HeaderCell extends StatelessWidget {
  final String label;
  final double width;
  final bool center;

  const _HeaderCell(this.label, {required this.width, this.center = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width == double.infinity ? null : width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          label,
          textAlign: center ? TextAlign.center : TextAlign.left,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String text;
  final double width;
  final bool center;
  final bool bold;
  final Color textColor;

  const _DataCell(
    this.text, {
    required this.width,
    this.center = false,
    this.bold = false,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          text,
          textAlign: center ? TextAlign.center : TextAlign.left,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

class _DataCellWidget extends StatelessWidget {
  final Widget child;
  final double width;

  const _DataCellWidget({required this.child, required this.width});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: child,
      ),
    );
  }
}

class _SearchableDropdownWidget extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final FocusNode? nextFocus;
  final List<String> allItems;
  final String defaultOption;
  final Function(String) onValueChanged;
  final bool enabled;
  final IconData? icon;

  const _SearchableDropdownWidget({
    required this.label,
    required this.controller,
    required this.focusNode,
    this.nextFocus,
    required this.allItems,
    required this.defaultOption,
    required this.onValueChanged,
    this.enabled = true,
    this.icon,
  });

  @override
  State<_SearchableDropdownWidget> createState() => _SearchableDropdownWidgetState();
}

class _SearchableDropdownWidgetState extends State<_SearchableDropdownWidget> {
  int _highlightedIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (!widget.focusNode.hasFocus) {
      _resolveSelection();
    }
  }

  List<String> _getFilteredOptions(String text) {
    final cleanText = text.trim().toLowerCase();
    final cleanDefault = widget.defaultOption.trim().toLowerCase();

    final validItems = widget.allItems.where((item) {
      final cleanItem = item.trim().toLowerCase();
      return cleanItem.isNotEmpty && (cleanDefault.isEmpty || cleanItem != cleanDefault);
    }).toList();

    if (cleanText.isEmpty || cleanText == cleanDefault) {
      return validItems;
    }

    final startsWith = validItems.where((item) => item.toLowerCase().startsWith(cleanText)).toList();
    final contains = validItems.where((item) => !item.toLowerCase().startsWith(cleanText) && item.toLowerCase().contains(cleanText)).toList();

    return [...startsWith, ...contains];
  }

  void _resolveSelection() {
    final currentText = widget.controller.text.trim();
    final cleanDefault = widget.defaultOption.trim();

    if (currentText.isEmpty || currentText.toLowerCase() == cleanDefault.toLowerCase()) {
      if (widget.controller.text != widget.defaultOption) {
        widget.controller.text = widget.defaultOption;
      }
      widget.onValueChanged(widget.defaultOption);
      return;
    }

    final filtered = _getFilteredOptions(currentText);

    if (filtered.isNotEmpty) {
      int idx = _highlightedIndex;
      if (idx < 0 || idx >= filtered.length) {
        idx = 0;
      }
      final selectedOption = filtered[idx];
      if (widget.controller.text != selectedOption) {
        widget.controller.text = selectedOption;
      }
      widget.onValueChanged(selectedOption);
    } else {
      widget.controller.text = widget.defaultOption;
      widget.onValueChanged(widget.defaultOption);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label.isNotEmpty) ...[
          Text(
            widget.label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade600),
          ),
          const SizedBox(height: 4),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            return RawAutocomplete<String>(
              textEditingController: widget.controller,
              focusNode: widget.focusNode,
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (!widget.enabled) return const Iterable<String>.empty();
                final filtered = _getFilteredOptions(textEditingValue.text);
                return filtered.take(50);
              },
              onSelected: (String selection) {
                widget.controller.text = selection;
                widget.onValueChanged(selection);
                if (widget.nextFocus != null) {
                  widget.nextFocus!.requestFocus();
                }
              },
              fieldViewBuilder: (context, textController, fieldFocusNode, onFieldSubmitted) {
                return Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: widget.enabled ? Colors.white : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: fieldFocusNode.hasFocus ? Colors.blue : Colors.grey.shade300,
                      width: fieldFocusNode.hasFocus ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      if (widget.icon != null) ...[
                        const SizedBox(width: 8),
                        Icon(widget.icon, size: 16, color: widget.enabled ? Colors.blueAccent : Colors.grey),
                      ],
                      Expanded(
                        child: TextField(
                          controller: textController,
                          focusNode: fieldFocusNode,
                          enabled: widget.enabled,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: widget.enabled ? Colors.black87 : Colors.grey.shade600,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: widget.defaultOption,
                            hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          onChanged: (val) {
                            _highlightedIndex = 0;
                          },
                          onSubmitted: (_) {
                            _resolveSelection();
                            if (widget.nextFocus != null) {
                              widget.nextFocus!.requestFocus();
                            }
                          },
                        ),
                      ),
                      if (widget.enabled && textController.text.isNotEmpty && textController.text != widget.defaultOption)
                        InkWell(
                          onTap: () {
                            textController.clear();
                            widget.onValueChanged(widget.defaultOption);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(Icons.close, size: 14, color: Colors.grey.shade600),
                          ),
                        ),
                      Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                    ],
                  ),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                final highlightedIndex = AutocompleteHighlightedOption.of(context);
                if (highlightedIndex >= 0 && highlightedIndex < options.length) {
                  _highlightedIndex = highlightedIndex;
                }

                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 6.0,
                    borderRadius: BorderRadius.circular(6),
                    color: Colors.white,
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      width: constraints.maxWidth,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade100),
                        itemBuilder: (context, index) {
                          final option = options.elementAt(index);
                          final isHighlighted = AutocompleteHighlightedOption.of(context) == index;
                          return InkWell(
                            onTap: () => onSelected(option),
                            child: Container(
                              color: isHighlighted ? Colors.blue.shade50 : Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              child: Text(
                                option,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w600,
                                  color: isHighlighted ? Colors.blue.shade900 : Colors.black87,
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
            );
          },
        ),
      ],
    );
  }
}
