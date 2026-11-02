import 'package:flutter/material.dart';
import '../services/app_notification_service.dart';
import '../services/server_config_service.dart';
import '../services/supabase_sync_service.dart';
import '../utils/theme_constants.dart';

class WatchdogPanelDialog extends StatefulWidget {
  final Function(String route)? onNavigate;

  const WatchdogPanelDialog({super.key, this.onNavigate});

  static void show(BuildContext context, {Function(String route)? onNavigate}) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        alignment: const Alignment(0.72, -0.75), // Aligned near Watchdog header button
        insetPadding: const EdgeInsets.only(top: 60, right: 120),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 580,
          height: 640,
          child: WatchdogPanelDialog(onNavigate: onNavigate),
        ),
      ),
    );
  }

  @override
  State<WatchdogPanelDialog> createState() => _WatchdogPanelDialogState();
}

class _WatchdogPanelDialogState extends State<WatchdogPanelDialog> {
  String _selectedCategory = 'all';
  String _selectedAction = 'all';

  Color _getCategoryColor(String category) {
    switch (category.toUpperCase()) {
      case 'SALES':
        return Colors.green.shade800;
      case 'PURCHASES':
        return Colors.blue.shade800;
      case 'CATALOG':
        return Colors.purple.shade800;
      case 'STOCK':
        return Colors.orange.shade800;
      case 'RETURNS':
        return Colors.red.shade800;
      case 'IMPORTS':
        return Colors.teal.shade800;
      case 'EXPORTS':
        return Colors.indigo.shade800;
      default:
        return Colors.purple.shade700;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toUpperCase()) {
      case 'SALES':
        return Icons.point_of_sale_rounded;
      case 'PURCHASES':
        return Icons.shopping_bag_rounded;
      case 'CATALOG':
        return Icons.inventory_2_rounded;
      case 'STOCK':
        return Icons.layers_rounded;
      case 'RETURNS':
        return Icons.assignment_return_rounded;
      case 'IMPORTS':
        return Icons.file_download_rounded;
      case 'EXPORTS':
        return Icons.file_upload_rounded;
      default:
        return Icons.visibility_rounded;
    }
  }

  Map<String, dynamic> _getOpTypeInfo(String opType) {
    switch (opType.toUpperCase()) {
      case 'ADDITION':
        return {
          'label': 'ADDITION',
          'icon': Icons.add_circle_outline_rounded,
          'color': Colors.green.shade700,
        };
      case 'EDIT':
        return {
          'label': 'EDIT',
          'icon': Icons.edit_note_rounded,
          'color': Colors.blue.shade700,
        };
      case 'DELETE':
        return {
          'label': 'DELETE',
          'icon': Icons.delete_forever_rounded,
          'color': Colors.red.shade700,
        };
      case 'STOCK_CHANGE':
        return {
          'label': 'STOCK CHANGE',
          'icon': Icons.swap_vert_rounded,
          'color': Colors.orange.shade800,
        };
      case 'IMPORT':
        return {
          'label': 'IMPORT',
          'icon': Icons.file_download_rounded,
          'color': Colors.teal.shade700,
        };
      case 'EXPORT':
        return {
          'label': 'EXPORT',
          'icon': Icons.file_upload_rounded,
          'color': Colors.indigo.shade700,
        };
      default:
        return {
          'label': 'EVENT',
          'icon': Icons.info_outline_rounded,
          'color': Colors.purple.shade700,
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final service = AppNotificationService.instance;
    final serverConfig = ServerConfigService.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([service, serverConfig]),
      builder: (context, _) {
        final watchdogLogs = service.getNotificationsByType(NotificationType.watchdog);
        final bool isConnected = serverConfig.isConnected;

        final filteredLogs = watchdogLogs.where((log) {
          final cat = log.detectedCategory;
          final op = log.detectedOperationType;

          // Category filter
          if (_selectedCategory == 'sales' && cat != 'SALES') return false;
          if (_selectedCategory == 'purchases' && cat != 'PURCHASES') return false;
          if (_selectedCategory == 'catalog' && (cat != 'CATALOG' || log.operationType == 'IMPORT')) return false;
          if (_selectedCategory == 'stock' && cat != 'STOCK') return false;
          if (_selectedCategory == 'returns' && cat != 'RETURNS') return false;
          if (_selectedCategory == 'imports' && (cat != 'IMPORTS' && log.operationType != 'IMPORT')) return false;

          // Action filter
          if (_selectedAction == 'addition' && op != 'ADDITION') return false;
          if (_selectedAction == 'edit' && op != 'EDIT') return false;
          if (_selectedAction == 'delete' && op != 'DELETE') return false;

          return true;
        }).toList();

        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: c.background,
            child: Column(
              children: [
                // Header (No Overflow Layout)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: c.isDark ? Colors.grey.shade900 : Colors.purple.shade900,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.visibility_rounded, color: Colors.purpleAccent, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "MULTI-PC WATCHDOG LIVE FEED 🐕",
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5),
                            ),
                            const SizedBox(height: 3),
                            // Green Live Synced Indicator Badge (Separate Line to prevent header overflow)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: isConnected ? Colors.green.shade900 : Colors.red.shade900,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isConnected ? Colors.greenAccent : Colors.redAccent,
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isConnected ? Icons.check_circle_rounded : Icons.sync_problem_rounded,
                                    color: isConnected ? Colors.greenAccent : Colors.amberAccent,
                                    size: 10,
                                  ),
                                  const SizedBox(width: 3),
                                  FutureBuilder<int>(
                                    future: SupabaseSyncService.instance.getUnsyncedTotalCount(),
                                    builder: (context, snapshot) {
                                      final unsynced = snapshot.data ?? 0;
                                      final String text = !isConnected
                                          ? "OFFLINE / RECONNECTING 🟠"
                                          : (unsynced > 0
                                              ? "UPLOADING DRAFTS ($unsynced PENDING) 🟠"
                                              : "SYSTEM SYNCED CORRECTLY 🟢");
                                      return Text(
                                        text,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.3,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              "Today's real-time event stream across all counters (${watchdogLogs.length} activity logs today)",
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10.5),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: watchdogLogs.isNotEmpty ? () => service.markAllAsRead() : null,
                        child: const Text("Read All", style: TextStyle(color: Colors.purpleAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),

                // Primary Category Bar (Imports and Exports on far right side)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  color: c.isDark ? Colors.grey.shade900 : Colors.purple.shade50,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildCategoryChip('all', 'All Categories (${watchdogLogs.length})', Colors.purple.shade800),
                        const SizedBox(width: 5),
                        _buildCategoryChip('sales', '🟢 Sales', Colors.green.shade800),
                        const SizedBox(width: 5),
                        _buildCategoryChip('purchases', '🔵 Purchases', Colors.blue.shade800),
                        const SizedBox(width: 5),
                        _buildCategoryChip('catalog', '🟣 Catalog', Colors.purple.shade800),
                        const SizedBox(width: 5),
                        _buildCategoryChip('stock', '🟠 Stock', Colors.orange.shade800),
                        const SizedBox(width: 5),
                        _buildCategoryChip('returns', '🔴 Returns', Colors.red.shade800),
                        const SizedBox(width: 12),
                        // Divider before Far Right Imports
                        Container(height: 18, width: 1.5, color: Colors.grey.shade400),
                        const SizedBox(width: 12),
                        _buildCategoryChip('imports', '📥 Imports', Colors.teal.shade800),
                      ],
                    ),
                  ),
                ),

                // Action Sub-Filter Bar (Only Additions, Edits, Deletes)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.isDark ? Colors.black26 : Colors.purple.shade100.withValues(alpha: 0.3),
                    border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.5))),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text("ACTIONS: ", style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Colors.grey)),
                        const SizedBox(width: 4),
                        _buildActionChip('all', 'All Actions'),
                        const SizedBox(width: 4),
                        _buildActionChip('addition', '➕ Additions'),
                        const SizedBox(width: 4),
                        _buildActionChip('edit', '✏️ Edits'),
                        const SizedBox(width: 4),
                        _buildActionChip('delete', '🗑️ Deletes'),
                      ],
                    ),
                  ),
                ),

                // Feed List
                Expanded(
                  child: filteredLogs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.visibility_off_outlined, color: Colors.grey.shade400, size: 44),
                              const SizedBox(height: 12),
                              const Text(
                                "No Watchdog activity logs for today in this filter view",
                                style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Real-time updates from PC 1, PC 2 & Cloud will stream here automatically.",
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                          itemCount: filteredLogs.length,
                          itemBuilder: (ctx, idx) => _buildWatchdogCard(context, filteredLogs[idx]),
                        ),
                ),

                // Footer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.border)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "${filteredLogs.length} event${filteredLogs.length > 1 ? 's' : ''} shown (Newest on top)",
                        style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                      ),
                      TextButton.icon(
                        onPressed: watchdogLogs.isNotEmpty
                            ? () {
                                service.clearAll();
                              }
                            : null,
                        icon: const Icon(Icons.delete_sweep_rounded, size: 14, color: Colors.red),
                        label: const Text("Clear Watchdog Logs", style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryChip(String key, String label, Color color) {
    final isSelected = _selectedCategory == key;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
          color: isSelected ? Colors.white : Colors.black87,
        ),
      ),
      selected: isSelected,
      selectedColor: color,
      backgroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      visualDensity: VisualDensity.compact,
      onSelected: (selected) {
        if (selected) setState(() => _selectedCategory = key);
      },
    );
  }

  Widget _buildActionChip(String key, String label) {
    final isSelected = _selectedAction == key;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
          color: isSelected ? Colors.white : Colors.grey.shade800,
        ),
      ),
      selected: isSelected,
      selectedColor: Colors.purple.shade700,
      backgroundColor: Colors.white.withValues(alpha: 0.8),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      visualDensity: VisualDensity.compact,
      onSelected: (selected) {
        if (selected) setState(() => _selectedAction = key);
      },
    );
  }

  Widget _buildWatchdogCard(BuildContext context, AppNotification notif) {
    final c = AppColors.of(context);
    final category = notif.detectedCategory;
    final categoryColor = _getCategoryColor(category);
    final categoryIcon = _getCategoryIcon(category);
    final isUnread = !notif.isRead;

    final opType = notif.detectedOperationType;
    final opInfo = _getOpTypeInfo(opType);
    final String opLabel = opInfo['label'];
    final IconData opIcon = opInfo['icon'];
    final Color opColor = opInfo['color'];

    final cardBg = isUnread
        ? (c.isDark ? Colors.purple.shade900.withValues(alpha: 0.25) : Colors.purple.shade50.withValues(alpha: 0.7))
        : (c.isDark ? Colors.grey.shade900.withValues(alpha: 0.2) : Colors.white);

    final terminal = notif.terminalName ?? 'Cloud Server';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isUnread ? categoryColor.withValues(alpha: 0.5) : c.border.withValues(alpha: 0.5),
          width: isUnread ? 1.2 : 0.8,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          AppNotificationService.instance.markAsRead(notif.id);
          if (notif.actionRoute != null && widget.onNavigate != null) {
            Navigator.pop(context);
            widget.onNavigate!(notif.actionRoute!);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // TOP SIDE HEADING ROW: [CATEGORY SIDE HEADING] + [OPERATION TYPE BADGE] + [LIVE BADGE]
              Row(
                children: [
                  // 1. Side Heading Category Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: categoryColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(categoryIcon, color: Colors.white, size: 10),
                        const SizedBox(width: 4),
                        Text(
                          "[$category]",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),

                  // 2. Operation Type Tag Badge (ADDITION, EDIT, DELETE, STOCK CHANGE, IMPORT, EXPORT)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: opColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: opColor, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(opIcon, size: 10, color: opColor),
                        const SizedBox(width: 3),
                        Text(
                          opLabel,
                          style: TextStyle(
                            color: opColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (isUnread) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade700,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        "LIVE",
                        style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),

              // Title & Clean 1-Line Message
              Text(
                notif.message,
                style: TextStyle(
                  fontWeight: isUnread ? FontWeight.w900 : FontWeight.bold,
                  fontSize: 12,
                  color: c.isDark ? Colors.white : Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),

              // BOTTOM ROW: Time + Synced Badge + Terminal / PC Badge
              Row(
                children: [
                  Icon(Icons.access_time_rounded, size: 10, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    notif.formattedDateTime,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                  const Spacer(),
                  // Green Synced Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                      color: Colors.green.shade900.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.green.shade600, width: 0.7),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 8, color: Colors.greenAccent),
                        SizedBox(width: 2),
                        Text(
                          "SYNCED",
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Terminal / PC Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: categoryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: categoryColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.computer_rounded, size: 10, color: categoryColor),
                        const SizedBox(width: 3),
                        Text(
                          terminal,
                          style: TextStyle(
                            color: categoryColor,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
