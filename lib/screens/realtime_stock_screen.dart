import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p_path;
import '../providers/pharmacy_provider.dart';
import '../utils/theme_constants.dart';
import '../utils/search_debouncer.dart';
import '../utils/app_formatters.dart';

class RealtimeStockScreen extends StatefulWidget {
  const RealtimeStockScreen({super.key});

  @override
  State<RealtimeStockScreen> createState() => _RealtimeStockScreenState();
}

class _RealtimeStockScreenState extends State<RealtimeStockScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _horizontalScrollCtrl = ScrollController();
  final ScrollController _verticalScrollCtrl = ScrollController();
  final SearchDebouncer _debouncer = SearchDebouncer(milliseconds: 150);

  String _filterMode = "ALL"; // "ALL", "IN_STOCK", "LOW_STOCK", "ZERO_STOCK", "OVERSTOCK"
  String _selectedCategory = "ALL";
  String _searchQuery = "";
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    _debouncer.run(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchCtrl.text.trim().toLowerCase();
        });
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _horizontalScrollCtrl.dispose();
    _verticalScrollCtrl.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  List<Product> _getFilteredProducts(List<Product> sourceList) {
    return sourceList.where((p) {
      // 1. Filter mode
      if (_filterMode == "IN_STOCK" && p.stock <= 0) return false;
      if (_filterMode == "ZERO_STOCK" && p.stock > 0) return false;
      if (_filterMode == "LOW_STOCK" && (p.stock > p.reorderLevel || p.reorderLevel <= 0 || p.stock <= 0)) return false;
      if (_filterMode == "OVERSTOCK" && (p.stock <= p.maxLevel || p.maxLevel <= 0)) return false;

      // 2. Category Filter
      if (_selectedCategory != "ALL" && p.category.toLowerCase() != _selectedCategory.toLowerCase()) {
        return false;
      }

      // 3. Search Query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery;
        final nameMatch = p.name.toLowerCase().contains(q);
        final idMatch = p.id.toLowerCase().contains(q);
        final rackMatch = p.rack.toLowerCase().contains(q);
        final genMatch = p.genericName.toLowerCase().contains(q);
        final hsnMatch = p.hsnCode.toLowerCase().contains(q);
        final patentMatch = p.patent.toLowerCase().contains(q);
        final catMatch = p.category.toLowerCase().contains(q);
        if (!nameMatch && !idMatch && !rackMatch && !genMatch && !hsnMatch && !patentMatch && !catMatch) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  Future<void> _exportToExcel(List<Product> products) async {
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No records available to export.")),
      );
      return;
    }

    setState(() => _isExporting = true);
    try {
      final excel = excel_lib.Excel.createExcel();
      final sheet = excel['Realtime Stock Profile'];
      excel.delete('Sheet1');

      // Add Headers
      sheet.appendRow([
        excel_lib.TextCellValue('Product ID'),
        excel_lib.TextCellValue('Name'),
        excel_lib.TextCellValue('Packing'),
        excel_lib.TextCellValue('Rack'),
        excel_lib.TextCellValue('HSN Code'),
        excel_lib.TextCellValue('MRP'),
        excel_lib.TextCellValue('P.Rate'),
        excel_lib.TextCellValue('Patent / Mfg'),
        excel_lib.TextCellValue('Generic Name'),
        excel_lib.TextCellValue('GST %'),
        excel_lib.TextCellValue('Category'),
        excel_lib.TextCellValue('Sub Category'),
        excel_lib.TextCellValue('S.Disc %'),
        excel_lib.TextCellValue('Schedule'),
        excel_lib.TextCellValue('Realtime Qty'),
        excel_lib.TextCellValue('Reorder Level'),
        excel_lib.TextCellValue('Max Level'),
      ]);

      for (var p in products) {
        sheet.appendRow([
          excel_lib.TextCellValue(p.id),
          excel_lib.TextCellValue(p.name),
          excel_lib.IntCellValue(p.packSize),
          excel_lib.TextCellValue(p.rack),
          excel_lib.TextCellValue(p.hsnCode),
          excel_lib.DoubleCellValue(p.mrp),
          excel_lib.DoubleCellValue(p.purchaseRate),
          excel_lib.TextCellValue(p.patent),
          excel_lib.TextCellValue(p.genericName),
          excel_lib.DoubleCellValue(p.gstPercent),
          excel_lib.TextCellValue(p.category),
          excel_lib.TextCellValue(p.subCategory),
          excel_lib.DoubleCellValue(p.sDiscPercent),
          excel_lib.TextCellValue(p.schedule),
          excel_lib.IntCellValue(p.stock),
          excel_lib.IntCellValue(p.reorderLevel),
          excel_lib.IntCellValue(p.maxLevel),
        ]);
      }

      final dir = await getApplicationDocumentsDirectory();
      final timeStr = DateTime.now().millisecondsSinceEpoch;
      final filePath = p_path.join(dir.path, 'Realtime_Stock_Profile_$timeStr.xlsx');
      final fileBytes = excel.save();

      if (fileBytes != null) {
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Excel exported successfully to:\n$filePath"),
              backgroundColor: Colors.green.shade800,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error exporting to Excel: $e"),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  String _formatStripsLoose(int totalUnits, int packSize) {
    if (packSize <= 1) return "$totalUnits Units";
    int strips = totalUnits ~/ packSize;
    int loose = totalUnits % packSize;
    if (strips == 0) return "$loose L";
    if (loose == 0) return "$strips S";
    return "$strips S / $loose L";
  }

  @override
  Widget build(BuildContext context) {
    final pharmacy = Provider.of<PharmacyProvider>(context);
    final allProducts = pharmacy.productMaster.isNotEmpty ? pharmacy.productMaster : pharmacy.products;

    // Get categories for dropdown
    final categories = <String>{"ALL"};
    for (var p in allProducts) {
      if (p.category.trim().isNotEmpty) categories.add(p.category.trim());
    }

    final filtered = _getFilteredProducts(allProducts);

    // Stats calculations
    int totalItems = filtered.length;
    int totalLiveUnits = filtered.fold(0, (sum, p) => sum + (p.stock > 0 ? p.stock : 0));
    double totalValuationPRate = filtered.fold(0.0, (sum, p) => sum + (p.stock > 0 ? p.stock * p.purchaseRate : 0.0));
    double totalValuationMRP = filtered.fold(0.0, (sum, p) => sum + (p.stock > 0 ? p.stock * p.mrp : 0.0));
    int reorderAlertCount = filtered.where((p) => p.reorderLevel > 0 && p.stock <= p.reorderLevel && p.stock > 0).length;

    return Scaffold(
      backgroundColor: Colors.blueGrey.shade50,
      body: Column(
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              boxShadow: [
                BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_rounded, color: Colors.white, size: 24),
                const SizedBox(width: 10),
                const Text(
                  "REALTIME STOCK QUANTITY",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt, color: Colors.yellow, size: 14),
                      const SizedBox(width: 2),
                      Text(
                        "${allProducts.length} Live Items",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _isExporting ? null : () => _exportToExcel(filtered),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: _isExporting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.file_download_rounded, size: 16),
                  label: const Text("Export Excel", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: "Refresh Live Stock Data",
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                  onPressed: () async {
                    await pharmacy.loadFromDatabase();
                  },
                ),
              ],
            ),
          ),

          // KPI Summary Cards Bar
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Row(
              children: [
                _buildKpiCard(
                  title: "FILTERED PRODUCTS",
                  value: "$totalItems",
                  icon: Icons.medication_rounded,
                  color: Colors.blue.shade700,
                ),
                const SizedBox(width: 10),
                _buildKpiCard(
                  title: "TOTAL LIVE QTY (UNITS)",
                  value: AppFormatters.formatNumber(totalLiveUnits),
                  icon: Icons.layers_rounded,
                  color: Colors.teal.shade700,
                ),
                const SizedBox(width: 10),
                _buildKpiCard(
                  title: "VALUATION (P.RATE)",
                  value: "₹${AppFormatters.formatNumber(totalValuationPRate.round())}",
                  icon: Icons.account_balance_wallet_rounded,
                  color: Colors.purple.shade700,
                ),
                const SizedBox(width: 10),
                _buildKpiCard(
                  title: "VALUATION (MRP)",
                  value: "₹${AppFormatters.formatNumber(totalValuationMRP.round())}",
                  icon: Icons.sell_rounded,
                  color: Colors.indigo.shade700,
                ),
                const SizedBox(width: 10),
                _buildKpiCard(
                  title: "REORDER ALERTS",
                  value: "$reorderAlertCount",
                  icon: Icons.warning_amber_rounded,
                  color: reorderAlertCount > 0 ? Colors.orange.shade800 : Colors.grey.shade600,
                ),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 1, color: Colors.black12),

          // Search & Filter Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                // Search Input
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: "Search Product ID, Name, Rack, HSN, Generic, Patent...",
                        hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchCtrl.clear();
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: Colors.grey.shade400),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Category Dropdown
                SizedBox(
                  height: 36,
                  child: DropdownButtonHideUnderline(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: DropdownButton<String>(
                        value: categories.contains(_selectedCategory) ? _selectedCategory : "ALL",
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedCategory = val);
                        },
                        items: categories.map((cat) {
                          return DropdownMenuItem(
                            value: cat,
                            child: Text(cat == "ALL" ? "All Categories" : cat),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Filter Chips
                Wrap(
                  spacing: 6,
                  children: [
                    _buildFilterChip("ALL", "All", Colors.blueGrey),
                    _buildFilterChip("IN_STOCK", "In Stock", Colors.green),
                    _buildFilterChip("LOW_STOCK", "Low Stock", Colors.orange),
                    _buildFilterChip("ZERO_STOCK", "Out of Stock", Colors.red),
                    _buildFilterChip("OVERSTOCK", "Overstock", Colors.purple),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 1, color: Colors.black12),

          // High Performance Horizontal & Vertical Data Table
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text(
                          "No stock items found matching criteria.",
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                : Scrollbar(
                    controller: _horizontalScrollCtrl,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _horizontalScrollCtrl,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: 2150, // Total fixed width for all 17 columns
                        child: Column(
                          children: [
                            // Table Header
                            Container(
                              height: 38,
                              color: Colors.blueGrey.shade800,
                              child: const Row(
                                children: [
                                  _HeaderCell("#", width: 50, align: Alignment.center),
                                  _HeaderCell("PRODUCT ID", width: 120),
                                  _HeaderCell("NAME", width: 220),
                                  _HeaderCell("PACKING", width: 80, align: Alignment.center),
                                  _HeaderCell("RACK", width: 80, align: Alignment.center),
                                  _HeaderCell("HSN CODE", width: 100),
                                  _HeaderCell("MRP (₹)", width: 90, align: Alignment.centerRight),
                                  _HeaderCell("P.RATE (₹)", width: 90, align: Alignment.centerRight),
                                  _HeaderCell("PATENT / MFG", width: 160),
                                  _HeaderCell("GENERIC NAME", width: 180),
                                  _HeaderCell("GST %", width: 70, align: Alignment.center),
                                  _HeaderCell("CATEGORY", width: 140),
                                  _HeaderCell("SUB CATEGORY", width: 130),
                                  _HeaderCell("S.DISC %", width: 80, align: Alignment.center),
                                  _HeaderCell("SCHEDULE", width: 90, align: Alignment.center),
                                  _HeaderCell("REALTIME QTY", width: 160, align: Alignment.center),
                                  _HeaderCell("REORDER LVK", width: 100, align: Alignment.center),
                                  _HeaderCell("MAX LEVEL", width: 100, align: Alignment.center),
                                ],
                              ),
                            ),

                            // Table Rows List
                            Expanded(
                              child: ListView.builder(
                                controller: _verticalScrollCtrl,
                                itemCount: filtered.length,
                                itemExtent: 32.0, // Fixed row height for high performance rendering
                                itemBuilder: (context, index) {
                                  final p = filtered[index];
                                  final isEven = index % 2 == 0;

                                  // Stock state color
                                  Color qtyBg = Colors.green.shade50;
                                  Color qtyTextColor = Colors.green.shade900;
                                  if (p.stock <= 0) {
                                    qtyBg = Colors.red.shade50;
                                    qtyTextColor = Colors.red.shade900;
                                  } else if (p.reorderLevel > 0 && p.stock <= p.reorderLevel) {
                                    qtyBg = Colors.orange.shade50;
                                    qtyTextColor = Colors.orange.shade900;
                                  }

                                  return Container(
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: isEven ? Colors.white : Colors.grey.shade50,
                                      border: Border(
                                        bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        _DataCell("${index + 1}", width: 50, align: Alignment.center, isMuted: true),
                                        _DataCell(p.id, width: 120, isBold: true),
                                        _DataCell(p.name, width: 220, isBold: true, color: Colors.indigo.shade900),
                                        _DataCell("${p.packSize}", width: 80, align: Alignment.center),
                                        _DataCell(p.rack.isEmpty ? "-" : p.rack, width: 80, align: Alignment.center, isMuted: p.rack.isEmpty),
                                        _DataCell(p.hsnCode.isEmpty ? "-" : p.hsnCode, width: 100, isMuted: p.hsnCode.isEmpty),
                                        _DataCell(p.mrp.toStringAsFixed(2), width: 90, align: Alignment.centerRight),
                                        _DataCell(p.purchaseRate.toStringAsFixed(2), width: 90, align: Alignment.centerRight),
                                        _DataCell(p.patent.isEmpty ? "-" : p.patent, width: 160, isMuted: p.patent.isEmpty),
                                        _DataCell(p.genericName.isEmpty ? "-" : p.genericName, width: 180, isMuted: p.genericName.isEmpty),
                                        _DataCell("${p.gstPercent.toStringAsFixed(0)}%", width: 70, align: Alignment.center),
                                        _DataCell(p.category.isEmpty ? "-" : p.category, width: 140, isMuted: p.category.isEmpty),
                                        _DataCell(p.subCategory.isEmpty ? "-" : p.subCategory, width: 130, isMuted: p.subCategory.isEmpty),
                                        _DataCell("${p.sDiscPercent.toStringAsFixed(1)}%", width: 80, align: Alignment.center),
                                        _DataCell(p.schedule.isEmpty ? "-" : p.schedule, width: 90, align: Alignment.center, isMuted: p.schedule.isEmpty),

                                        // Realtime Qty Cell with badge
                                        Container(
                                          width: 160,
                                          alignment: Alignment.center,
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: qtyBg,
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: qtyTextColor.withValues(alpha: 0.3)),
                                            ),
                                            child: Text(
                                              "${p.stock} (${_formatStripsLoose(p.stock, p.packSize)})",
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: qtyTextColor,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),

                                        _DataCell(
                                          "${p.reorderLevel}",
                                          width: 100,
                                          align: Alignment.center,
                                          color: p.reorderLevel > 0 && p.stock <= p.reorderLevel ? Colors.orange.shade900 : null,
                                          isBold: p.reorderLevel > 0 && p.stock <= p.reorderLevel,
                                        ),
                                        _DataCell("${p.maxLevel}", width: 100, align: Alignment.center),
                                      ],
                                    ),
                                  );
                                },
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
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black87),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String mode, String label, Color color) {
    final isSelected = _filterMode == mode;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _filterMode = mode);
      },
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.white : Colors.black87,
      ),
      selectedColor: color,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  final double width;
  final Alignment align;

  const _HeaderCell(
    this.text, {
    required this.width,
    this.align = Alignment.centerLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          letterSpacing: 0.3,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String text;
  final double width;
  final Alignment align;
  final bool isBold;
  final bool isMuted;
  final Color? color;

  const _DataCell(
    this.text, {
    required this.width,
    this.align = Alignment.centerLeft,
    this.isBold = false,
    this.isMuted = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: isMuted ? Colors.grey.shade500 : (color ?? Colors.black87),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
