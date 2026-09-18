import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/erp_models.dart';
import '../../providers/pharmacy_provider.dart';

class WholesaleAvailabilityDialog extends StatefulWidget {
  final String productName;
  final String company;
  final String category;
  final String productId;

  const WholesaleAvailabilityDialog({
    super.key,
    required this.productName,
    this.company = "",
    this.category = "",
    this.productId = "",
  });

  static Future<void> show(
    BuildContext context, {
    required String productName,
    String company = "",
    String category = "",
    String productId = "",
  }) async {
    if (productName.trim().isEmpty) return;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => WholesaleAvailabilityDialog(
        productName: productName,
        company: company,
        category: category,
        productId: productId,
      ),
    );
  }

  @override
  State<WholesaleAvailabilityDialog> createState() => _WholesaleAvailabilityDialogState();
}

class _WholesaleAvailabilityDialogState extends State<WholesaleAvailabilityDialog> {
  bool _isLoading = true;
  List<WholesalerAvailabilityResult> _allResults = [];
  List<WholesalerAvailabilityResult> _filteredResults = [];
  String _filterText = "";
  int _selectedIndex = 0;

  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadAvailability();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAvailability() async {
    setState(() => _isLoading = true);
    final provider = Provider.of<PharmacyProvider>(context, listen: false);
    try {
      final list = await provider.checkWholesalerAvailability(
        productName: widget.productName,
        patent: widget.company,
        category: widget.category,
        productId: widget.productId,
      );
      if (mounted) {
        setState(() {
          _allResults = list;
          _filteredResults = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilter() {
    final query = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filterText = query;
      if (query.isEmpty) {
        _filteredResults = _allResults;
      } else {
        _filteredResults = _allResults.where((r) {
          return r.wholesalerName.toLowerCase().contains(query) ||
              r.matchReason.toLowerCase().contains(query) ||
              r.matchedDetail.toLowerCase().contains(query);
        }).toList();
      }
      _selectedIndex = 0;
    });
  }

  void _handleKeyDown(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_filteredResults.isNotEmpty) {
        setState(() {
          _selectedIndex = (_selectedIndex + 1).clamp(0, _filteredResults.length - 1);
        });
        _scrollToIndex();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_filteredResults.isNotEmpty) {
        setState(() {
          _selectedIndex = (_selectedIndex - 1).clamp(0, _filteredResults.length - 1);
        });
        _scrollToIndex();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
    }
  }

  void _scrollToIndex() {
    if (!_scrollCtrl.hasClients) return;
    const itemExtent = 64.0;
    final targetOffset = _selectedIndex * itemExtent;
    _scrollCtrl.animateTo(
      targetOffset.clamp(0.0, _scrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final int greenCount = _allResults.where((r) => r.status == WholesalerMatchStatus.exactPurchase).length;
    final int orangeCount = _allResults.where((r) => r.status == WholesalerMatchStatus.brandVariantPurchase).length;
    final int yellowCount = _allResults.where((r) => r.status == WholesalerMatchStatus.directoryMatch).length;

    return RawKeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKey: _handleKeyDown,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Container(
          width: 750,
          constraints: const BoxConstraints(maxHeight: 650),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              // 1. Header Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E293B),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade600.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.storefront_rounded, color: Colors.blueAccent, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "WHOLESALE AVAILABILITY DIRECTORY",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Supplier availability status for ${widget.productName.toUpperCase()}",
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: "Close (ESC)",
                    )
                  ],
                ),
              ),

              // 2. Checked Medicine Summary Info Box
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.productName.toUpperCase(),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (widget.company.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    "Company: ${widget.company}",
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              if (widget.category.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    "Category: ${widget.category}",
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                                  ),
                                ),
                              ],
                            ],
                          )
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 3. Search & Legend Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    // Search box
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: TextField(
                          controller: _searchCtrl,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            hintText: "Filter wholesaler...",
                            prefixIcon: const Icon(Icons.search, size: 18),
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Status Badges Legend
                    _buildLegendBadge(
                      label: "Exact Bought",
                      count: greenCount,
                      color: const Color(0xFF16A34A),
                      bgColor: const Color(0xFFDCFCE7),
                    ),
                    const SizedBox(width: 6),
                    _buildLegendBadge(
                      label: "Brand Bought",
                      count: orangeCount,
                      color: const Color(0xFFEA580C),
                      bgColor: const Color(0xFFFFEDD5),
                    ),
                    const SizedBox(width: 6),
                    _buildLegendBadge(
                      label: "Directory Match",
                      count: yellowCount,
                      color: const Color(0xFFCA8A04),
                      bgColor: const Color(0xFFFEF9C3),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // 4. Wholesalers List
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(),
                      )
                    : (_filteredResults.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 8),
                                Text(
                                  _filterText.isNotEmpty
                                      ? "No wholesaler matching '$_filterText'"
                                      : "No wholesalers found for this item or brand",
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            itemCount: _filteredResults.length,
                            itemBuilder: (ctx, idx) {
                              final res = _filteredResults[idx];
                              final isSelected = idx == _selectedIndex;

                              return _buildWholesalerCard(res, isSelected, () {
                                setState(() => _selectedIndex = idx);
                              });
                            },
                          )),
              ),

              // 5. Bottom Instructions Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "🟢 Green = Bought exact item | 🟧 Orange = Bought brand variant | 🟡 Yellow = Mapped product/brand",
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                      ),
                    ),
                    Text(
                      "Press ESC to close",
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendBadge({
    required String label,
    required int count,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            "$label: $count",
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildWholesalerCard(
    WholesalerAvailabilityResult res,
    bool isSelected,
    VoidCallback onTap,
  ) {
    Color cardBg;
    Color borderColor;
    Color badgeColor;
    Color badgeText;
    String statusLabel;
    IconData statusIcon;

    switch (res.status) {
      case WholesalerMatchStatus.exactPurchase:
        cardBg = const Color(0xFFF0FDF4); // Light Green
        borderColor = const Color(0xFF22C55E); // Green
        badgeColor = const Color(0xFF16A34A);
        badgeText = Colors.white;
        statusLabel = "PURCHASED EXACT ITEM";
        statusIcon = Icons.check_circle_rounded;
        break;

      case WholesalerMatchStatus.brandVariantPurchase:
        cardBg = const Color(0xFFFFF7ED); // Light Orange
        borderColor = const Color(0xFFF97316); // Orange
        badgeColor = const Color(0xFFEA580C);
        badgeText = Colors.white;
        statusLabel = "PURCHASED BRAND VARIANT";
        statusIcon = Icons.local_offer_rounded;
        break;

      case WholesalerMatchStatus.directoryMatch:
        cardBg = const Color(0xFFFEFCE8); // Light Yellow
        borderColor = const Color(0xFFEAB308); // Yellow/Gold
        badgeColor = const Color(0xFFCA8A04);
        badgeText = Colors.white;
        statusLabel = "DIRECTORY MATCH";
        statusIcon = Icons.store_rounded;
        break;

      case WholesalerMatchStatus.none:
        cardBg = Colors.grey.shade50;
        borderColor = Colors.grey.shade300;
        badgeColor = Colors.grey;
        badgeText = Colors.white;
        statusLabel = "NO PURCHASE HISTORY";
        statusIcon = Icons.help_outline;
        break;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? cardBg.withOpacity(0.9) : cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? borderColor : borderColor.withOpacity(0.5),
            width: isSelected ? 2.5 : 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: borderColor.withOpacity(0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          children: [
            // Status Icon
            Icon(statusIcon, color: badgeColor, size: 22),
            const SizedBox(width: 12),

            // Wholesaler Name & Match Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          res.wholesalerName.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (res.purchaseCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            "${res.purchaseCount} items",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        res.matchReason,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: badgeColor,
                        ),
                      ),
                      if (res.matchedDetail.isNotEmpty) ...[
                        Text(
                          " • ",
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                        Expanded(
                          child: Text(
                            res.matchedDetail,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade800,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Status Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: badgeText,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
