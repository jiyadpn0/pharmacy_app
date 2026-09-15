import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../providers/app_provider.dart';
import '../providers/pharmacy_provider.dart';
import '../providers/mdi_controller.dart';
import '../widgets/window_controls_bar.dart';
import '../widgets/draggable_modal.dart';
import '../utils/theme_constants.dart';
import 'quick_adjust_dialog.dart';
import 'current_stock_screen.dart';
import 'product_profile_screen.dart';
import '../services/update_checker_service.dart';
import 'package:window_manager/window_manager.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    HardwareKeyboard.instance.addHandler(_handleGlobalKeys);

    // Silent check for software updates on boot
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        UpdateCheckerService.checkForUpdates(context, silent: true);
      }
    });

    // Delay auto-backup so it never contends for DB locks during startup
    Timer(const Duration(seconds: 15), () async {
      if (!mounted) return;
      final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);
      await pharmacy.performAutoBackupIfNeeded();
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeys);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose && mounted) {
      final pharmacy = Provider.of<PharmacyProvider>(context, listen: false);
      await pharmacy.performAutoBackupIfNeeded(forceOnExit: true);
      await windowManager.destroy();
    }
  }

  bool _handleGlobalKeys(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    if (HardwareKeyboard.instance.isControlPressed) {
      if (event.logicalKey == LogicalKeyboardKey.arrowRight || event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        final pharma = Provider.of<PharmacyProvider>(context, listen: false);
        final app = Provider.of<AppProvider>(context, listen: false);

        bool hasW3Name = pharma.salesSessions[2]['agent'].toString().trim().isNotEmpty;
        int current = pharma.activeSessionIdx;
        int next;

        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          if (hasW3Name) {
            next = (current + 1) % 3;
          } else {
            next = (current == 0) ? 1 : 0;
          }
        } else {
          if (hasW3Name) {
            next = (current - 1 + 3) % 3;
          } else {
            next = (current == 1) ? 0 : 1;
          }
        }

        pharma.setSalesSession(next);
        app.switchToSalesTab();
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final app = Provider.of<AppProvider>(context);

    return PopScope(
      canPop: false, // Prevents closing the entire window when a dialog pops
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            // 1. BACKGROUND CONTENT LAYER
            Column(
              children: [
                const SizedBox(height: 92), // Reserved space for the Header
                Expanded(
                  child: Container(
                    color: const Color(0xFF1E293B).withValues(alpha: 0.05),
                  ),
                ),
                const SizedBox(height: 24), // Reserved space for Status Bar
              ],
            ),

            // 2. THE FLOATING WINDOW LAYER (MDI)
            // This sits in the middle, but maximized windows stay below the header.
            const Positioned.fill(
              child: MdiArea(),
            ),

            // 3. FIXED HEADER LAYER (ALWAYS ON TOP)
            // We place this LAST in the stack so it's guaranteed to receive drag events!
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildUnifiedTitleBar(context, app),
                  _buildMenuBar(context, app),
                  _buildWindowDock(context, app),
                ],
              ),
            ),

            // 4. FIXED STATUS BAR
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildStatusBar(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnifiedTitleBar(BuildContext context, AppProvider app) {
    return SizedBox(
      height: 32.0,
      child: WindowControlsBar(
        height: 32.0,
        backgroundColor: const Color(0xFF0F172A),
        titleWidget: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.medical_services_rounded, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text(
              "PHARMA PRO",
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        trailingActions: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Consumer<PharmacyProvider>(
              builder: (_, pharma, __) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildAgentSelector(pharma),
                  const SizedBox(width: 8),
                  _buildGlobalWorkspaces(app, pharma),
                  const SizedBox(width: 8),
                  _buildThemeToggleButton(app),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _buildFinancialYearSelector(context),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.security_outlined, color: Colors.white70, size: 16),
              onPressed: () => app.openSettings(tab: "Security & Backup"),
              tooltip: "Security & Backup",
              constraints: const BoxConstraints(maxHeight: 28, maxWidth: 28),
              padding: const EdgeInsets.all(4),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white70, size: 16),
              onPressed: () => app.openSettings(),
              tooltip: "Settings",
              constraints: const BoxConstraints(maxHeight: 28, maxWidth: 28),
              padding: const EdgeInsets.all(4),
            ),
            const SizedBox(width: 4),
            const CircleAvatar(
              radius: 10,
              backgroundColor: Colors.white24,
              child: Icon(Icons.person, color: Colors.white, size: 14),
            ),
          ],
        ),
      ),
    );
  }

  // ---> NEW: DYNAMIC AGENT SELECTOR WIDGET <---
  Widget _buildAgentSelector(PharmacyProvider pharma) {
    List<String> agents = pharma.staffNames;
    if (agents.isEmpty) {
      agents = ["Admin", "Jiyad", "Suresh", "Ramesh", "Staff 1", "Staff 2"];
    } else {
      agents = List<String>.from(agents);
    }
    
    String currentAgent = "Agent";
    if (pharma.salesSessions.isNotEmpty && pharma.activeSessionIdx < pharma.salesSessions.length) {
      final String raw = pharma.salesSessions[pharma.activeSessionIdx]['agent']?.toString() ?? "";
      if (raw.isNotEmpty) {
        if (!agents.contains(raw)) {
          agents.add(raw);
        }
        currentAgent = raw;
      }
    }

    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white24),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          dropdownColor: const Color(0xFF1E293B),
          value: currentAgent == "Agent" ? null : currentAgent,
          hint: const Row(
            children: [
              Icon(Icons.support_agent_rounded, color: Colors.white70, size: 12),
              SizedBox(width: 4),
              Text("Select Agent", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          icon: const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.arrow_drop_down, color: Colors.white60, size: 14),
          ),
          isDense: true,
          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
          items: agents.map((String agent) {
            return DropdownMenuItem<String>(
              value: agent,
              child: Row(
                children: [
                  const Icon(Icons.person, color: Colors.white70, size: 12),
                  const SizedBox(width: 6),
                  Text(agent),
                ],
              ),
            );
          }).toList(),
          onChanged: (String? newValue) {
            if (newValue != null) {
              // Updates the agent for the current workspace and triggers UI rebuild
              final session = Map<String, dynamic>.from(pharma.salesSessions[pharma.activeSessionIdx]);
              session['agent'] = newValue;
              pharma.updateSalesSession(pharma.activeSessionIdx, session);
            }
          },
        ),
      ),
    );
  }

  Widget _buildThemeToggleButton(AppProvider app) {
    final bool isDark = app.isDarkMode;
    return Tooltip(
      message: isDark ? "Switch to White/Light Mode" : "Switch to Dark Mode",
      child: InkWell(
        onTap: () => app.toggleDarkMode(),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: isDark ? Colors.amber.shade900.withValues(alpha: 0.3) : Colors.white10,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isDark ? Colors.amberAccent : Colors.white24,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isDark ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                size: 12,
                color: isDark ? Colors.amberAccent : Colors.white70,
              ),
              const SizedBox(width: 4),
              Text(
                isDark ? "WHITE MODE" : "DARK MODE",
                style: TextStyle(
                  color: isDark ? Colors.amberAccent : Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuBar(BuildContext context, AppProvider app) {
    return Container(
      height: 28,
      width: double.infinity,
      color: const Color(0xFF1E293B),
      child: Row(
        children: [
          const SizedBox(width: 12),
          _CompactDropdownMenu(title: "MASTER", actions: [
            _MenuAction("Product Registration", () => app.openProductRegistration()),
            _MenuAction("Supplier Master", () => app.openSupplierList()),
            _MenuAction("Patient Master", () => app.openPatientList()),
            _MenuAction("Doctor Registration", () => app.openDoctorRegistration()),
            _MenuAction("Staff Management", () => app.openStaffManagement()),
            _MenuAction("Category Master", () => app.openCategoryRegistration()),
            _MenuAction("Rack Master", () => app.openRackRegistration()),
            _MenuAction("Generic Master", () => app.openGenericRegistration()),
            _MenuAction("Manufacturer Master", () => app.openManufacturerRegistration()),
            _MenuAction("Tax Registration", () => app.openTaxRegistration()),
            _MenuAction("Account Master", () => app.openAccountRegistration()),
            _MenuAction("Prescription Master", () => app.openPrescriptionRegistration()),
            _MenuAction("Mapping Manager", () => app.openProductMappingReport()),
          ]),
          _CompactDropdownMenu(title: "TRANSACTION", actions: [
            _MenuAction("Sales Entry", () => app.openSales()),
            _MenuAction("Purchase Entry", () => app.openPurchase()),
            _MenuAction("Purchase Return", () => app.openPurchaseReturn()),
            _MenuAction("Sales Return", () => app.openSalesReturn()),
            _MenuAction("Damage & Expiry Entry", () => app.openDamageEntry()),
          ]),
          _CompactDropdownMenu(title: "STOCK", actions: [
            _MenuAction("Product Profile", () {
              Provider.of<MdiController>(context, listen: false).openWindow(
                MdiWindow(
                  id: "product_profile",
                  title: "Product Profile Ledger",
                  width: 1100,
                  height: 700,
                  content: const ProductProfileScreen(),
                ),
              );
            }),
            _MenuAction("Live Current Stock", () {
              Provider.of<MdiController>(context, listen: false).openWindow(
                MdiWindow(
                  id: "current_stock",
                  title: "Live Current Stock",
                  width: 1000,
                  height: 600,
                  content: const CurrentStockScreen(),
                ),
              );
            }),
            _MenuAction("Stock Ledger", () => app.openStockLedger()),
            _MenuAction("Consolidate Stock", () => app.openConsolidateStock()),
            _MenuAction("Inventory", () => app.openAllStockDetails()),
          ]),
          _CompactDropdownMenu(title: "STOCK MANAGEMENT", actions: [
            _MenuAction("Stock Checking", () => app.openStockChecking()),
            _MenuAction("Bulk Stock Manager", () => app.openStockManagement()),
            _MenuAction("Quick Adjustment", () {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const DraggableModal(child: QuickAdjustDialog()),
              );
            }),
            _MenuAction("Stock Adjustment (Batch)", () => app.openStockAdjustmentBatch()),
            _MenuAction("Damage & Expiry Entry", () => app.openDamageEntry()),
            _MenuAction("Expiry Check", () => app.openExpiryList()),
          ]),
          _CompactDropdownMenu(title: "ORDER", actions: [
            _MenuAction("Order Book", () => app.openOrderBook()),
            _MenuAction("Order Confirmation", () => app.openOrderConfirmation()),
            _MenuAction("Special Orders", () => app.openSpecialOrders()),
            _MenuAction("Stock Enquiries", () => app.openStockEnquiries()),
            _MenuAction("Product Ranking", () => app.openProductRanking()),
          ]),
          _CompactDropdownMenu(title: "REPORTS", actions: [
            _MenuAction("Sales Analysis", () => app.openSalesReport()),
            _MenuAction("Schedule H1 / Narcotics Register", () => app.openScheduleH1Register()),
            _MenuAction("Reorder Assistant (PO Generator)", () => app.openReorderAssistant()),
            _MenuAction("Sales Return Analysis", () => app.openSalesReturnReport()),
            _MenuAction("GST Filing Report", () => app.openGstReport()),
            _MenuAction("Purchase Analysis", () => app.openPurchaseReport()),
            _MenuAction("Purchase Return Analysis", () => app.openPurchaseReturnReport()),
            _MenuAction("Stock Adjustment Report", () => app.openStockAdjustmentBatchReport()),
          ]),
          _CompactDropdownMenu(title: "ACCOUNTS", actions: [
            _MenuAction("Ledger Registration", null, children: [
              _MenuAction("Ledger Registration", () => app.openLedgerRegistration()),
              _MenuAction("Account Master", () => app.openAccountRegistration()),
              _MenuAction("Payment Entry", () => app.openPayment()),
              _MenuAction("Customer Ledger", () => app.openCustomerLedger()),
            ]),
            _MenuAction("Receipt Entry", () => app.openReceipt()),
            _MenuAction("Daily Report", () => app.openDailyReport()),
          ]),
          _CompactDropdownMenu(title: "ANALYSIS", actions: [
            _MenuAction("Sales Analysis", () => app.openSalesReport()),
            _MenuAction("Purchase Analysis", () => app.openPurchaseReport()),
            _MenuAction("Sales Return Analysis", () => app.openSalesReturnReport()),
            _MenuAction("Purchase Return Analysis", () => app.openPurchaseReturnReport()),
            _MenuAction("Stock Adjustment Report", () => app.openStockAdjustmentBatchReport()),
            _MenuAction("Product Ranking Analysis", () => app.openProductRanking()),
          ]),

          // Add a solid drag handle for the remaining space in the Menu Bar
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              child: Container(color: Colors.transparent),
            ),
          ),
        ],
      ),
    );
  }

  // ---> NEW: AGENT COLOR MAPPER <---
  Color _getAgentColor(String agentName) {
    switch (agentName.trim().toLowerCase()) {
      case "jiyad": return Colors.teal.shade400;
      case "admin": return Colors.indigo.shade400;
      case "suresh": return Colors.orange.shade400;
      case "ramesh": return Colors.purple.shade400;
      case "staff 1": return Colors.pink.shade400;
      case "staff 2": return Colors.cyan.shade400;
      default:
        final colors = [
          Colors.teal.shade400,
          Colors.indigo.shade400,
          Colors.orange.shade400,
          Colors.purple.shade400,
          Colors.pink.shade400,
          Colors.cyan.shade400,
          Colors.blue.shade400,
          Colors.amber.shade600,
          const Color(0xFF34D399),
        ];
        if (agentName.isEmpty) return Colors.blue.shade400;
        final hash = agentName.trim().toLowerCase().codeUnits.fold(0, (prev, elem) => prev + elem);
        return colors[hash % colors.length];
    }
  }

  Widget _buildGlobalWorkspaces(AppProvider app, PharmacyProvider pharma) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: List.generate(3, (i) {
          bool isSessionActive = pharma.activeSessionIdx == i;
          String agent = pharma.salesSessions[i]['agent'];
          bool hasName = agent.isNotEmpty;
          if (agent.isEmpty) agent = "W${i + 1}";

          // Apply unique colors ONLY if an agent is selected
          Color agentColor = hasName ? _getAgentColor(agent) : Colors.transparent;

          // Background: Colored if assigned, grey if unassigned
          Color bgColor = hasName 
              ? agentColor.withValues(alpha: isSessionActive ? 0.3 : 0.1) 
              : (isSessionActive ? const Color(0xFF37474F) : Colors.black26);

          // Border: Colored if assigned, white/grey if unassigned
          Color borderColor = hasName 
              ? agentColor 
              : (isSessionActive ? Colors.white54 : Colors.white12);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: () {
                  pharma.setSalesSession(i);
                  app.switchToSalesTab();
                },
                child: Container(
                  width: 50,
                  height: 22,
                  margin: const EdgeInsets.only(left: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: borderColor,
                      width: isSessionActive ? 1.5 : 1.0,
                    ),
                  ),
                  child: Text(
                    agent,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: (hasName || isSessionActive) ? Colors.white : Colors.white60,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              if (isSessionActive && hasName)
                Positioned(
                  top: -4,
                  right: -4,
                  child: GestureDetector(
                    onTap: () {
                      // ---> THE FIX: Explicitly clear the agent when clicking the red X <---
                      final session = Map<String, dynamic>.from(pharma.salesSessions[i]);
                      session['agent'] = "";
                      pharma.updateSalesSession(i, session, notify: false);
                      pharma.clearSalesSession(i);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: const Icon(Icons.close, size: 8, color: Colors.white),
                    ),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }

  void _showTabContextMenu(BuildContext context, AppProvider app, Offset position) async {
    final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'recover',
          enabled: app.closedTabsHistory.isNotEmpty,
          child: Row(
            children: const [
              Icon(Icons.restore_page_rounded, size: 16),
              SizedBox(width: 8),
              Text("Recover last closed tab"),
            ],
          ),
        ),
      ],
    );

    if (result == 'recover') {
      app.recoverLastClosedTab();
    }
  }

  Widget _buildWindowDock(BuildContext context, AppProvider app) {
    final mdi = Provider.of<MdiController>(context);
    final bool isDark = app.isDarkMode;
    final allItems = [
      ...app.openTabs.asMap().entries.map((e) => {
            'title': e.value.title,
            'type': 'tab',
            'index': e.key,
            'id': '',
            'isActive': app.activeTabIndex == e.key
          }),
      ...mdi.windows.where((w) => !w.isMinimized).map((w) => {
            'title': w.title,
            'type': 'mdi',
            'index': -1,
            'id': w.id,
            'isActive': true
          }),
    ];

    if (allItems.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showTabContextMenu(context, app, details.globalPosition);
      },
      child: Container(
        height: 32,
        width: double.infinity,
        color: const Color(0xFF0F172A),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: allItems.length,
              itemBuilder: (context, index) {
                final item = allItems[index];
                final bool isActive = item['isActive'] as bool;
                final bool isHome = item['title'] == 'Home';
                final String titleText = (item['title'] as String).toUpperCase();

                // RESTORE ORIGINAL MATCHING COLOR PALETTE WITH FIX FOR TEXT VISIBILITY
                final Color tabBg = isActive
                    ? (isDark ? const Color(0xFF1E293B) : Colors.white)
                    : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.12));

                final Color txtColor = isActive
                    ? (isDark ? Colors.amberAccent : const Color(0xFF0F172A))
                    : Colors.white70;

                final Color closeIconColor = isActive
                    ? (isDark ? Colors.amberAccent.withValues(alpha: 0.9) : const Color(0xFF0F172A))
                    : Colors.white38;

                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      if (item['type'] == 'tab') {
                        app.focusTab(item['index'] as int);
                      } else {
                        mdi.focusWindow(item['id'] as String);
                      }
                    },
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 50, maxWidth: 140),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      margin: const EdgeInsets.only(right: 1, top: 1),
                      decoration: BoxDecoration(
                        color: tabBg,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                        border: Border(
                          right: BorderSide(
                            color: isActive ? Colors.transparent : Colors.white.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                      ),
                      child: DefaultTextStyle(
                        style: TextStyle(
                          color: txtColor,
                          fontSize: 10.5,
                          fontWeight: isActive ? FontWeight.w900 : FontWeight.w600,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Expanded(
                              child: Text(
                                titleText,
                                style: TextStyle(
                                  color: txtColor,
                                  fontSize: 10.5,
                                  fontWeight: isActive ? FontWeight.w900 : FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            if (item['type'] == 'tab' && !isHome) ...[
                              const SizedBox(width: 4),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => confirmCloseTab(context, () => app.closeTab(item['index'] as int)),
                                  borderRadius: BorderRadius.circular(4),
                                  hoverColor: Colors.red.withValues(alpha: 0.2),
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: Icon(
                                      Icons.close,
                                      size: 11,
                                      color: closeIconColor,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Drag area for the window
          Expanded(
            flex: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (details) => windowManager.startDragging(),
              child: const SizedBox(width: 80, height: double.infinity),
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, app, child) {
        return Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: AppColors.primary,
          child: Row(
            children: [
              const Icon(Icons.dns, size: 12, color: Colors.green),
              const SizedBox(width: 4),
              const Text(
                "CONNECTED",
                style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
              ),
              const Expanded(child: SizedBox()),
              Flexible(
                child: Text(
                  app.statusMessage,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontStyle: FontStyle.italic),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Expanded(child: SizedBox()),
              const Text(
                "SAHAKAR MEDICALS - v1.0.0",
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFinancialYearSelector(BuildContext context) {
    return Consumer<PharmacyProvider>(
      builder: (context, pharma, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white24),
          ),
          child: PopupMenuButton<String>(
            tooltip: "Switch Financial Year",
            initialValue: pharma.selectedFinancialYear,
            onSelected: (String year) {
              pharma.setSelectedFinancialYear(year);
            },
            itemBuilder: (BuildContext context) {
              return pharma.availableFinancialYears.map((String year) {
                return PopupMenuItem<String>(
                  value: year,
                  height: 30,
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 12,
                        color: pharma.selectedFinancialYear == year ? AppColors.primary : Colors.black54,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        year,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: pharma.selectedFinancialYear == year ? FontWeight.bold : FontWeight.normal,
                          color: pharma.selectedFinancialYear == year ? AppColors.primary : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList();
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_month_rounded, size: 12, color: Colors.white70),
                const SizedBox(width: 4),
                Text(
                  pharma.selectedFinancialYear,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 12, color: Colors.white60),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CompactDropdownMenu extends StatefulWidget {
  final String title;
  final List<_MenuAction> actions;

  const _CompactDropdownMenu({required this.title, required this.actions});

  @override
  State<_CompactDropdownMenu> createState() => _CompactDropdownMenuState();
}

class _CompactDropdownMenuState extends State<_CompactDropdownMenu> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Provider.of<AppProvider>(context, listen: false).isDarkMode;
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
        elevation: const WidgetStatePropertyAll(12),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(8),
              bottomRight: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
          ),
        ),
      ),
      menuChildren: widget.actions.map((a) => _buildMenuItem(a, isDark)).toList(),
      builder: (context, controller, child) {
        bool isOpen = controller.isOpen;
        return MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isOpen 
                    ? const Color(0xFF334155) 
                    : (_isHovered ? Colors.white.withValues(alpha: 0.1) : Colors.transparent),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isOpen ? Colors.white54 : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: isOpen ? Colors.white : Colors.white70,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 12,
                    color: isOpen ? Colors.white : Colors.white38,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMenuItem(_MenuAction action, bool isDark) {
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    if (action.children != null && action.children!.isNotEmpty) {
      return SubmenuButton(
        menuChildren: action.children!.map((a) => _buildMenuItem(a, isDark)).toList(),
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
          minimumSize: const WidgetStatePropertyAll(Size(180, 35)),
          fixedSize: const WidgetStatePropertyAll(Size.fromHeight(35)),
          overlayColor: WidgetStatePropertyAll(isDark ? Colors.white12 : Colors.black12),
        ),
        child: Text(
          action.title,
          style: TextStyle(
            fontSize: 11, 
            fontWeight: FontWeight.w500, 
            color: textColor,
          ),
        ),
      );
    }
    return MenuItemButton(
      onPressed: action.callback,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
        minimumSize: const WidgetStatePropertyAll(Size(180, 35)),
        fixedSize: const WidgetStatePropertyAll(Size.fromHeight(35)),
        overlayColor: WidgetStatePropertyAll(isDark ? Colors.white12 : Colors.black12),
      ),
      child: Text(
        action.title,
        style: TextStyle(
          fontSize: 11, 
          fontWeight: FontWeight.w500, 
          color: textColor,
        ),
      ),
    );
  }
}

class _MenuAction {
  final String title;
  final VoidCallback? callback;
  final List<_MenuAction>? children;
  _MenuAction(this.title, this.callback, {this.children});
}

class MdiArea extends StatelessWidget {
  const MdiArea({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppProvider, MdiController>(
      builder: (context, app, mdi, child) {
        return LayoutBuilder(builder: (context, constraints) {
          List<Widget> allWindows = [];

          const double topSafeOffset = 92.0; // 32 (Title) + 28 (Menu) + 32 (Tabs)
          const double bottomSafeOffset = 24.0;
          final double safeHeight = constraints.maxHeight - topSafeOffset - bottomSafeOffset;

          // 1. RENDER BACKGROUND TABS (Locked to the safe zone)
          List<int> indices = List.generate(app.openTabs.length, (i) => i);
          indices.sort((a, b) {
            if (a == app.activeTabIndex) return 1;
            if (b == app.activeTabIndex) return -1;
            return 0;
          });

          for (int i in indices) {
            final tab = app.openTabs[i];
            bool isActive = app.activeTabIndex == i;
            bool isHome = tab.title == 'Home';
            bool isMax = tab.isMaximized || isHome;
            
            double left = isMax ? 0 : tab.position.dx;
            double top = isMax ? topSafeOffset : tab.position.dy;
            double width = isMax ? constraints.maxWidth : tab.size.width;
            double height = isMax ? safeHeight : tab.size.height;

            allWindows.add(
              Positioned(
                key: ValueKey("tab_$i"),
                left: left,
                top: top,
                width: width,
                height: height,
                child: Offstage(
                  offstage: isMax && !isActive,
                  child: TickerMode(
                    enabled: !isMax || isActive,
                    child: _MdiWindowWidget(
                      title: tab.title,
                      isMaximized: isMax,
                      isActive: isActive,
                      showHeader: !isHome && !tab.isMaximized, 
                      onClose: tab.closable ? () => confirmCloseTab(context, () => app.closeTab(i)) : null,
                      onMaximize: isHome ? null : () => app.toggleWindowMaximize(i),
                      onFocus: () => app.focusTab(i),
                      onDragFinished: (newPos) => app.updateWindowPosition(i, newPos),
                      onResizeFinished: (newSize) => app.updateWindowSize(i, newSize),
                      initialPosition: tab.position,
                      initialSize: tab.size,
                      child: tab.content,
                    ),
                  ),
                ),
              ),
            );
          }

          // 2. RENDER FLOATING WINDOWS (With proper Z-Indexing!)
          // The last window in the MDI controller's list is the active one in front
          final String? activeWindowId = mdi.windows.isNotEmpty ? mdi.windows.last.id : null;

          for (var window in mdi.windows.where((w) => !w.isMinimized)) {
            bool isMax = window.isMaximized;

            double left = isMax ? 0 : window.position.dx;
            double top = isMax ? topSafeOffset : window.position.dy;
            double width = isMax ? constraints.maxWidth : window.width;
            double height = isMax ? safeHeight : window.height;

            allWindows.add(
              Positioned(
                key: ValueKey("win_${window.id}"),
                left: left,
                top: top,
                width: width,
                height: height,
                child: _MdiWindowWidget(
                  title: window.title,
                  isMaximized: isMax,
                  isActive: window.id == activeWindowId, // Highlights the title bar of the top window!
                  onClose: () => mdi.closeWindow(window.id),
                  onMaximize: () => mdi.toggleMaximize(window.id),
                  onFocus: () => mdi.focusWindow(window.id),
                  onDragFinished: (newPos) => mdi.updateWindowPosition(window.id, newPos),
                  onResizeFinished: (newSize) => mdi.updateWindowSize(window.id, newSize.width, newSize.height),
                  initialPosition: window.position,
                  initialSize: Size(window.width, window.height),
                  child: window.content,
                ),
              ),
            );
          }

          return Stack(
            clipBehavior: Clip.none,
            children: allWindows,
          );
        });
      },
    );
  }
}

class _MdiWindowWidget extends StatefulWidget {
  final String title;
  final Widget child;
  final bool isMaximized;
  final bool isActive;
  final bool showHeader;
  final VoidCallback? onClose;
  final VoidCallback? onMaximize;
  final VoidCallback? onFocus;
  final Function(Offset)? onDragFinished;
  final Function(Size)? onResizeFinished;
  final Offset initialPosition;
  final Size initialSize;

  const _MdiWindowWidget({
    required this.title,
    required this.child,
    required this.isMaximized,
    required this.isActive,
    this.showHeader = true,
    this.onClose,
    this.onMaximize,
    this.onFocus,
    this.onDragFinished,
    this.onResizeFinished,
    required this.initialPosition,
    required this.initialSize,
  });

  @override
  State<_MdiWindowWidget> createState() => _MdiWindowWidgetState();
}

class _MdiWindowWidgetState extends State<_MdiWindowWidget> {
  Offset _dragOffset = Offset.zero;
  Size _resizeOffset = Size.zero;
  bool _isDragging = false;
  bool _isResizing = false;

  @override
  void didUpdateWidget(_MdiWindowWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPosition != oldWidget.initialPosition) _dragOffset = Offset.zero;
    if (widget.initialSize != oldWidget.initialSize) _resizeOffset = Size.zero;
  }

  @override
  Widget build(BuildContext context) {
    // --- DROPDOWN FIX ---
    // If the window is a maximized background tab, DO NOT intercept touches.
    // Return the pure widget so Flutter's dropdowns and overlays work natively!
    if (widget.isMaximized && !widget.showHeader) {
      return widget.child; 
    }

    final bool isDark = Provider.of<AppProvider>(context, listen: false).isDarkMode;
    final Color windowBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color inactiveHeaderBg = isDark ? const Color(0xFF182232) : Colors.blueGrey.shade100;
    final Color inactiveTextColor = isDark ? Colors.white70 : Colors.black87;
    final Color inactiveIconColor = isDark ? Colors.white60 : Colors.black45;

    // --- FLOATING WINDOW RENDERING ---
    return Transform.translate(
      offset: _dragOffset,
      child: SizedBox(
        width: widget.isMaximized ? null : (widget.initialSize.width + _resizeOffset.width),
        height: widget.isMaximized ? null : (widget.initialSize.height + _resizeOffset.height),
        // Use Listener instead of GestureDetector so it never swallows child taps!
        child: Listener(
          onPointerDown: (_) => widget.onFocus?.call(),
          behavior: HitTestBehavior.deferToChild,
          child: Material(
            elevation: widget.isMaximized ? 0 : (widget.isActive ? 24 : 8),
            borderRadius: widget.isMaximized ? BorderRadius.zero : BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: Container(
              decoration: BoxDecoration(
                color: windowBg,
                border: Border.all(
                  color: widget.isActive ? (isDark ? const Color(0xFF3B82F6) : const Color(0xFF0F172A)) : (isDark ? const Color(0xFF334155) : Colors.grey.shade400),
                  width: widget.isMaximized ? 0 : (widget.isActive ? 2.0 : 1.0),
                ),
                borderRadius: widget.isMaximized ? BorderRadius.zero : BorderRadius.circular(8),
              ),
              child: Stack(
                children: [
                  Column(
                    children: [
                      if (widget.showHeader)
                        GestureDetector(
                          onPanStart: (_) {
                            widget.onFocus?.call();
                            setState(() => _isDragging = true);
                          },
                          onPanUpdate: widget.isMaximized ? null : (details) {
                            final screenSize = MediaQuery.of(context).size;
                            setState(() {
                              double newDx = _dragOffset.dx + details.delta.dx;
                              double newDy = _dragOffset.dy + details.delta.dy;

                              double globalX = widget.initialPosition.dx + newDx;
                              double globalY = widget.initialPosition.dy + newDy;

                              // The Edge Bouncer
                              if (globalY < 90) newDy = 90 - widget.initialPosition.dy;
                              if (globalX > screenSize.width - 150) newDx = (screenSize.width - 150) - widget.initialPosition.dx;
                              if (globalX < -widget.initialSize.width + 150) newDx = (-widget.initialSize.width + 150) - widget.initialPosition.dx;
                              if (globalY > screenSize.height - 50) newDy = (screenSize.height - 50) - widget.initialPosition.dy;

                              _dragOffset = Offset(newDx, newDy);
                            });
                          },
                          onPanEnd: (_) {
                            if (_isDragging && widget.onDragFinished != null) {
                              widget.onDragFinished!(widget.initialPosition + _dragOffset);
                            }
                            setState(() => _isDragging = false);
                          },
                          onDoubleTap: widget.onMaximize,
                          child: Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            // Changes color based on Z-Index
                            color: widget.isActive ? const Color(0xFF0F172A) : inactiveHeaderBg,
                            child: Row(
                              children: [
                                Icon(Icons.window, size: 16, color: widget.isActive ? Colors.white70 : inactiveIconColor),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.title,
                                    style: TextStyle(
                                      color: widget.isActive ? Colors.white : inactiveTextColor,
                                      fontWeight: widget.isActive ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (widget.onMaximize != null)
                                  IconButton(
                                    icon: Icon(widget.isMaximized ? Icons.fullscreen_exit : Icons.fullscreen, size: 18, color: widget.isActive ? Colors.white70 : inactiveIconColor),
                                    onPressed: widget.onMaximize,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                if (widget.onClose != null) ...[
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: Icon(Icons.close, size: 18, color: widget.isActive ? Colors.red.shade300 : Colors.black45),
                                    onPressed: widget.onClose,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      Expanded(
                        child: RepaintBoundary(
                          child: ClipRect(
                            child: widget.child,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!widget.isMaximized && widget.onResizeFinished != null)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeDownRight,
                        child: GestureDetector(
                          onPanStart: (_) => setState(() => _isResizing = true),
                          onPanUpdate: (details) {
                            setState(() {
                              _resizeOffset = Size(
                                _resizeOffset.width + details.delta.dx,
                                _resizeOffset.height + details.delta.dy,
                              );
                            });
                          },
                          onPanEnd: (_) {
                            if (_isResizing) {
                              widget.onResizeFinished!(Size(
                                widget.initialSize.width + _resizeOffset.width,
                                widget.initialSize.height + _resizeOffset.height,
                              ));
                            }
                            setState(() => _isResizing = false);
                          },
                          child: Container(
                            width: 20,
                            height: 20,
                            color: Colors.transparent,
                            child: CustomPaint(
                              painter: _ResizeHandlePainter(),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResizeHandlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(size.width * 0.7, size.height), Offset(size.width, size.height * 0.7), paint);
    canvas.drawLine(Offset(size.width * 0.4, size.height), Offset(size.width, size.height * 0.4), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void confirmCloseTab(BuildContext context, VoidCallback onConfirm) {
  final FocusNode noFocusNode = FocusNode();

  showDialog(
    context: context,
    builder: (ctx) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        noFocusNode.requestFocus();
      });

      return AlertDialog(
        title: const Text("Unsaved Changes", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("Some data are not saved, are you sure to delete?"),
        actions: [
          TextButton(
            focusNode: noFocusNode,
            onPressed: () => Navigator.of(ctx).pop(), // No (default focused)
            child: const Text("No", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.of(ctx).pop();
              onConfirm(); // Yes
            },
            child: const Text("Yes"),
          ),
        ],
      );
    },
  );
}
