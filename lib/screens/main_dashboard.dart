import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../widgets/window_controls_bar.dart';
import '../widgets/draggable_modal.dart';
import 'quick_adjust_dialog.dart';

class MainDashboard extends StatelessWidget {
  const MainDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AppProvider>(context, listen: false);

    return Scaffold(
      backgroundColor: const Color(0xFFE9EDF0),
      body: Column(
        children: [
          // ==========================================
          // THE UNIFIED TITLE BAR
          // ==========================================
          WindowControlsBar(
            height: 50.0,
            titleWidget: const Row(
              children: [
                Icon(Icons.medical_services_rounded, color: Colors.white, size: 24),
                SizedBox(width: 8),
                Text(
                  "PHARMA PRO",
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                ),
              ],
            ),
            navigationMenu: Row(
              children: [
                _buildDropdownMenu(context, "MASTER", [
                  _MenuAction("Product Registration", () => provider.openProductRegistration()),
                  _MenuAction("Supplier Master", () => provider.openSupplierList()),
                ]),
                _buildDropdownMenu(context, "TRANSACTION", [
                  _MenuAction("Sales", () => provider.openSales()),
                  _MenuAction("Local Purchase", () => provider.openPurchase()),
                  _MenuAction("Quick Stock Adjust", () {
                    showDialog(context: context, barrierDismissible: false, builder: (context) => const DraggableModal(child: QuickAdjustDialog()));
                  }),
                  _MenuAction("Damage & Expiry Write-Off", () => provider.openDamageEntry()),
                  _MenuAction("Stock Adjustment (Batch)", () => provider.openStockAdjustmentBatch()),
                  _MenuAction("Stock Adjustment Report", () => provider.openStockAdjustmentBatchReport()),
                ]),
                _buildDropdownMenu(context, "STOCK", [
                  _MenuAction("Stock Ledger", () => provider.openStockLedger()),
                  _MenuAction("Consolidate Stock Position", () => provider.openConsolidateStock()),
                ]),
                _buildDropdownMenu(context, "ORDER", [
                  _MenuAction("Order Book", () => provider.openOrderBook()),
                  _MenuAction("Special Orders", () => provider.openSpecialOrders()),
                  _MenuAction("Product Ranking", () => provider.openProductRanking()),
                ]),
                _buildDropdownMenu(context, "ACCOUNTS", [
                  _MenuAction("Ledger", () => provider.openLedgerRegistration()),
                ]),
                _buildDropdownMenu(context, "ANALYSIS", [
                  _MenuAction("Sales Analysis", () => provider.openSalesReport()),
                  _MenuAction("Purchase Analysis", () => provider.openPurchaseReport()),
                  _MenuAction("Sales Return Analysis", () => provider.openSalesReturnReport()),
                  _MenuAction("Purchase Return Analysis", () => provider.openPurchaseReturnReport()),
                  _MenuAction("Stock Adjustment Report", () => provider.openStockAdjustmentBatchReport()),
                  _MenuAction("Product Ranking Analysis", () => provider.openProductRanking()),
                ]),
              ],
            ),
            trailingActions: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.search, color: Colors.white70),
                  tooltip: "Inventory",
                  onPressed: () => provider.openAllStockDetails(),
                ),
                IconButton(
                  icon: const Icon(Icons.notifications_none, color: Colors.white70),
                  tooltip: "Expiry List",
                  onPressed: () => provider.openExpiryList(),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, color: Colors.white70),
                  tooltip: "Settings",
                  onPressed: () => provider.openSettings(),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => provider.openSecuritySettings(),
                  child: const CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.person, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),

          // ==========================================
          // MAIN DASHBOARD CONTENT AREA
          // ==========================================
          const Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.local_pharmacy, size: 80, color: Colors.blueGrey),
                  SizedBox(height: 16),
                  Text(
                    "SAHAKAR MEDICALS",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Use the unified title bar to navigate",
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownMenu(BuildContext context, String title, List<_MenuAction> actions) {
    return PopupMenuButton<_MenuAction>(
      offset: const Offset(0, 40),
      elevation: 10,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: Colors.white70),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: Colors.white38),
          ],
        ),
      ),
      onSelected: (action) => action.callback(),
      itemBuilder: (context) {
        return actions.map((_MenuAction action) {
          return PopupMenuItem<_MenuAction>(
            value: action,
            height: 35,
            child: Text(
              action.title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
            ),
          );
        }).toList();
      },
    );
  }
}

class _MenuAction {
  final String title;
  final VoidCallback callback;
  _MenuAction(this.title, this.callback);
}
