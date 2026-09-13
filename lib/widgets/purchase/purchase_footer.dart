import 'package:flutter/material.dart';
import '../../utils/theme_constants.dart';

class PurchaseFooter extends StatelessWidget {
  final Widget recentPurchasesList;
  final Widget purchaseHistoryList;
  final String historyProductName;
  final TextEditingController remarksCtrl;
  final FocusNode remarksFocus;
  final Widget totalCalculationSection;

  final String? section1Title;
  final List<Map<String, dynamic>>? section1Headers;
  final int section1Flex;

  final String? section2Title;
  final List<Map<String, dynamic>>? section2Headers;
  final int section2Flex;
  final String? recentPurchasesTitle;
  final bool showRemarks;

  const PurchaseFooter({
    super.key,
    required this.recentPurchasesList,
    required this.purchaseHistoryList,
    required this.historyProductName,
    required this.remarksCtrl,
    required this.remarksFocus,
    required this.totalCalculationSection,
    this.section1Title,
    this.section1Headers,
    this.section1Flex = 3,
    this.section2Title,
    this.section2Headers,
    this.section2Flex = 6,
    this.recentPurchasesTitle,
    this.showRemarks = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final s1Title = section1Title ?? recentPurchasesTitle ?? "Recent Purchases";
    final s1Headers = section1Headers ?? [
      {'title': 'Entry', 'flex': 1}, 
      {'title': 'Supplier', 'flex': 3}, 
      {'title': 'Amount', 'flex': 2, 'align': Alignment.centerRight}
    ];

    final s2Title = section2Title ?? (historyProductName.isEmpty ? "Purchase History" : "Purchase History of $historyProductName");
    final s2Headers = section2Headers ?? [
      {'title': 'Date', 'width': 70.0}, 
      {'title': 'Entry No', 'width': 70.0}, 
      {'title': 'Supplier', 'flex': 2}, 
      {'title': 'MRP', 'width': 60.0, 'align': Alignment.centerRight}, 
      {'title': 'P.Rate', 'width': 60.0, 'align': Alignment.centerRight}, 
      {'title': 'F.Qty', 'width': 45.0, 'align': Alignment.centerRight}, 
      {'title': 'Disc%', 'width': 45.0, 'align': Alignment.centerRight}, 
      {'title': 'L.Cost', 'width': 70.0, 'align': Alignment.centerRight}
    ];

    return Container(
      height: 165,
      color: c.background,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(children: [
        // SECTION 1
        Expanded(
          flex: section1Flex, 
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, 
            children: [
              _footerTitle(s1Title), 
              _footerTableHdr(s1Headers), 
              Expanded(child: recentPurchasesList)
            ]
          )
        ),
        const SizedBox(width: 10),

        // SECTION 2
        Expanded(
          flex: section2Flex, 
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, 
            children: [
              _footerTitle(s2Title), 
              _footerTableHdr(s2Headers), 
              Expanded(child: purchaseHistoryList)
            ]
          )
        ),
        const SizedBox(width: 10),

        // REMARKS
        if (showRemarks) ...[
          Expanded(
            flex: 2, 
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                _footerTitle("Remarks"),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(color: c.cardBg, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(4)),
                    child: TextField(
                      controller: remarksCtrl, focusNode: remarksFocus,
                      maxLines: null, expands: true,
                      style: TextStyle(fontSize: 12, color: c.primaryText),
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(border: InputBorder.none, contentPadding: const EdgeInsets.all(8), hintText: "Enter remarks here...", hintStyle: TextStyle(fontSize: 11, color: c.secondaryText)),
                    ),
                  ),
                ),
              ]
            )
          ),
          const SizedBox(width: 10),
        ],

        // TOTAL CALCULATION SECTION
        totalCalculationSection,
      ]),
    );
  }

  Widget _footerTitle(String title) => Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(title, style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)));

  Widget _footerTableHdr(List<Map<String, dynamic>> cols) => Container(height: 22, color: const Color(0xFF334155), child: Row(children: cols.map((c) {
    Widget cell = Container(padding: const EdgeInsets.symmetric(horizontal: 4), alignment: c['align'] ?? Alignment.centerLeft, child: Text(c['title'], style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)));
    return c['width'] != null ? SizedBox(width: (c['width'] as num).toDouble(), child: cell) : Expanded(flex: c['flex'] ?? 1, child: cell);
  }).toList()));
}
