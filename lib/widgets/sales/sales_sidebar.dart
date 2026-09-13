import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../payment_received_dialog.dart';

class SalesSidebar extends StatelessWidget {
  final VoidCallback? onNewSale;

  const SalesSidebar({
    super.key,
    this.onNewSale,
  });

  @override
  Widget build(BuildContext context) {
    final app = Provider.of<AppProvider>(context, listen: false);

    return Container(
      width: 170,
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(left: BorderSide(color: Color(0xFF334155))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Title
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            color: const Color(0xFF0F172A),
            alignment: Alignment.center,
            child: const Text(
              "QUICK ACTIONS",
              style: TextStyle(
                color: Color(0xFFF59E0B),
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: [
                // ==========================================
                // 1. ENTRIES (NON-CLICKABLE HEADER)
                // ==========================================
                _buildSectionHeader("1. ENTRIES"),
                _buildActionButton(
                  label: "Purchase",
                  icon: Icons.local_shipping_outlined,
                  color: const Color(0xFF38BDF8),
                  onTap: () => app.openPurchase(),
                ),
                _buildActionButton(
                  label: "Sales",
                  icon: Icons.point_of_sale_rounded,
                  color: const Color(0xFF10B981),
                  onTap: onNewSale ?? () => app.openSales(),
                ),
                _buildActionButton(
                  label: "Purchase Return",
                  icon: Icons.assignment_return_outlined,
                  color: const Color(0xFFF97316),
                  onTap: () => app.openPurchaseReturn(),
                ),
                _buildActionButton(
                  label: "Sales Return",
                  icon: Icons.keyboard_return_rounded,
                  color: const Color(0xFFFB7185),
                  onTap: () => app.openSalesReturn(),
                ),

                const SizedBox(height: 12),

                // ==========================================
                // 2. STOCK MANAGEMENT (NON-CLICKABLE HEADER)
                // ==========================================
                _buildSectionHeader("2. STOCK MANAGEMENT"),
                _buildActionButton(
                  label: "Damage",
                  icon: Icons.broken_image_outlined,
                  color: const Color(0xFFEF4444),
                  onTap: () => app.openDamageEntry(),
                ),
                _buildActionButton(
                  label: "Adjustment",
                  icon: Icons.tune_rounded,
                  color: const Color(0xFFA855F7),
                  onTap: () => app.openStockAdjustment(),
                ),

                const SizedBox(height: 12),

                // ==========================================
                // 3. ACCOUNTS (NON-CLICKABLE HEADER)
                // ==========================================
                _buildSectionHeader("3. ACCOUNTS"),
                _buildActionButton(
                  label: "Quick Payment",
                  icon: Icons.payments_rounded,
                  color: const Color(0xFF2DD4BF),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => const PaymentReceivedDialog(),
                    );
                  },
                ),
                _buildActionButton(
                  label: "Daybook",
                  icon: Icons.menu_book_rounded,
                  color: const Color(0xFF60A5FA),
                  onTap: () => app.openDailyReport(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 6, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Material(
        color: const Color(0xFF334155).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: color.withValues(alpha: 0.15),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF475569).withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
