import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pharmacy_provider.dart';
import '../services/app_notification_service.dart';
import '../utils/theme_constants.dart';

class NotificationPanelDialog extends StatefulWidget {
  final Function(String route)? onNavigate;

  const NotificationPanelDialog({super.key, this.onNavigate});

  static void show(BuildContext context, {Function(String route)? onNavigate}) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        alignment: const Alignment(0.82, -0.75), // Top-right near header bell
        insetPadding: const EdgeInsets.only(top: 60, right: 100),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 520,
          height: 580,
          child: NotificationPanelDialog(onNavigate: onNavigate),
        ),
      ),
    );
  }

  @override
  State<NotificationPanelDialog> createState() => _NotificationPanelDialogState();
}

class _NotificationPanelDialogState extends State<NotificationPanelDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  IconData _getTypeIcon(NotificationType type) {
    switch (type) {
      case NotificationType.stock:
        return Icons.warning_amber_rounded;
      case NotificationType.backup:
        return Icons.cloud_done_rounded;
      case NotificationType.security:
        return Icons.shield_rounded;
      case NotificationType.watchdog:
      default:
        return Icons.visibility_rounded;
    }
  }

  Color _getTypeColor(NotificationType type, [int? badgeColorValue]) {
    if (badgeColorValue != null) {
      return Color(badgeColorValue);
    }
    switch (type) {
      case NotificationType.stock:
        return Colors.orange.shade800;
      case NotificationType.backup:
        return Colors.teal.shade700;
      case NotificationType.security:
        return Colors.indigo.shade700;
      case NotificationType.watchdog:
      default:
        return Colors.purple.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final service = AppNotificationService.instance;
    final pharma = Provider.of<PharmacyProvider>(context);

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final allNotifs = service.notifications;
        final stockNotifs = service.getNotificationsByType(NotificationType.stock);
        final syncNotifs = service.getNotificationsByType(NotificationType.backup);
        final securityNotifs = service.getNotificationsByType(NotificationType.security);
        final watchdogNotifs = service.getNotificationsByType(NotificationType.watchdog);

        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: c.background,
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: c.isDark ? Colors.grey.shade900 : Colors.blue.shade900,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_active_rounded, color: Colors.amberAccent, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "NOTIFICATION CENTER",
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1),
                            ),
                            Text(
                              service.unreadCount > 0
                                  ? "${service.unreadCount} unread store alert${service.unreadCount > 1 ? 's' : ''}"
                                  : "All notifications caught up",
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: service.notifications.isNotEmpty ? () => service.markAllAsRead() : null,
                        child: const Text("Read All", style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
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

                // Category Tabs
                Container(
                  color: c.isDark ? Colors.grey.shade900 : Colors.blue.shade50,
                  child: TabBar(
                    controller: _tabController,
                    labelColor: Colors.blue.shade800,
                    unselectedLabelColor: Colors.grey.shade600,
                    indicatorColor: Colors.blue.shade800,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                    tabs: const [
                      Tab(text: "All"),
                      Tab(text: "Stock"),
                      Tab(text: "Sync & Excel"),
                      Tab(text: "Security"),
                    ],
                  ),
                ),

                // Tab Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildListWithSyncTasks(context, pharma, allNotifs, showSyncTasks: true),
                      _buildListWithSyncTasks(context, pharma, stockNotifs, showSyncTasks: false),
                      _buildListWithSyncTasks(context, pharma, syncNotifs, showSyncTasks: true),
                      _buildListWithSyncTasks(context, pharma, securityNotifs, showSyncTasks: false),
                    ],
                  ),
                ),

                // Footer
                if (allNotifs.isNotEmpty || pharma.syncQueue.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: c.border)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("${allNotifs.length} total logs", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        Row(
                          children: [
                            if (pharma.syncQueue.any((t) => t.status != 'In Progress' && t.status != 'Pending'))
                              TextButton(
                                onPressed: () => pharma.clearCompletedSyncTasks(),
                                child: const Text("Clear Excel Queue", style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                            TextButton(
                              onPressed: () => service.clearAll(),
                              child: const Text("Clear All Logs", style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ],
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

  Widget _buildListWithSyncTasks(
    BuildContext context,
    PharmacyProvider provider,
    List<AppNotification> items, {
    required bool showSyncTasks,
  }) {
    final tasks = showSyncTasks ? provider.syncQueue : <SyncTask>[];

    if (items.isEmpty && tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_off_outlined, color: Colors.grey.shade400, size: 40),
            const SizedBox(height: 12),
            const Text("No notifications in this category", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      children: [
        if (showSyncTasks && tasks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4, bottom: 6),
            child: Row(
              children: [
                const Icon(Icons.sync_alt_rounded, size: 14, color: Colors.blue),
                const SizedBox(width: 6),
                const Text(
                  "REALTIME EXCEL DATA MOVEMENT",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.blue, letterSpacing: 0.5),
                ),
                const Spacer(),
                Text(
                  "${tasks.length} Task${tasks.length > 1 ? 's' : ''}",
                  style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          ...tasks.map((task) => _buildSyncTaskCard(context, provider, task)),
          const Divider(height: 16, thickness: 1),
        ],

        if (items.isNotEmpty)
          ...items.map((notif) => _buildNotificationCard(context, notif)),
      ],
    );
  }

  Widget _buildSyncTaskCard(BuildContext context, PharmacyProvider provider, SyncTask task) {
    final c = AppColors.of(context);
    final isInProgress = task.status == 'In Progress' || task.status == 'Pending';
    final isCompleted = task.status == 'Completed';

    Color badgeColor;
    String badgeText;
    IconData badgeIcon;

    if (isInProgress) {
      badgeColor = Colors.amber.shade800;
      badgeText = "IN PROGRESS";
      badgeIcon = Icons.sync_rounded;
    } else if (isCompleted) {
      badgeColor = Colors.green.shade700;
      badgeText = "COMPLETED";
      badgeIcon = Icons.check_circle_rounded;
    } else {
      badgeColor = Colors.red.shade700;
      badgeText = "NOT COMPLETED";
      badgeIcon = Icons.cancel_rounded;
    }

    int percentageInt = (task.progress * 100).clamp(0, 100).toInt();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.isDark ? Colors.grey.shade900 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isInProgress
              ? Colors.blue.shade400
              : (isCompleted ? Colors.green.shade400 : Colors.red.shade400),
          width: isInProgress ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Title & Status Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: (task.type.toLowerCase() == 'import' ? Colors.blue : Colors.teal).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  task.type.toLowerCase() == 'import' ? Icons.file_download_rounded : Icons.file_upload_rounded,
                  color: task.type.toLowerCase() == 'import' ? Colors.blue.shade800 : Colors.teal.shade800,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: c.isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      "${task.type} • Excel Background Operation",
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Status Badge with Realtime %
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 12, color: badgeColor),
                    const SizedBox(width: 4),
                    Text(
                      isInProgress ? "$percentageInt%" : badgeText,
                      style: TextStyle(
                        color: badgeColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Realtime Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: isInProgress ? task.progress : (isCompleted ? 1.0 : task.progress),
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                isInProgress ? Colors.blue.shade600 : (isCompleted ? Colors.green.shade600 : Colors.red.shade600),
              ),
              minHeight: 6,
            ),
          ),

          const SizedBox(height: 8),

          // Realtime Status Message & CANCEL Button Row
          Row(
            children: [
              Expanded(
                child: Text(
                  isInProgress
                      ? (task.statusMessage.contains('%') ? task.statusMessage : "${task.statusMessage} ($percentageInt%)")
                      : (task.resultMessage ?? (isCompleted ? "Completed successfully." : "Not completed.")),
                  style: TextStyle(
                    fontSize: 11,
                    color: isInProgress
                        ? (c.isDark ? Colors.amber.shade200 : Colors.blue.shade900)
                        : (isCompleted ? Colors.green.shade800 : Colors.red.shade800),
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isInProgress) ...[
                const SizedBox(width: 8),
                // CANCEL BUTTON
                OutlinedButton.icon(
                  onPressed: () {
                    provider.cancelSyncTask(task.id);
                  },
                  icon: const Icon(Icons.cancel_outlined, size: 14, color: Colors.red),
                  label: const Text("CANCEL", style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.w900)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red, width: 1.2),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ] else ...[
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16, color: Colors.grey),
                  onPressed: () {
                    provider.clearCompletedSyncTasks();
                  },
                  tooltip: "Dismiss task",
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(BuildContext context, AppNotification notif) {
    final c = AppColors.of(context);
    final color = _getTypeColor(notif.type, notif.badgeColorValue);
    final icon = _getTypeIcon(notif.type);
    final isUnread = !notif.isRead;

    final cardBg = isUnread
        ? (c.isDark ? Colors.blue.shade900.withValues(alpha: 0.3) : Colors.blue.shade50)
        : (c.isDark ? Colors.grey.shade900.withValues(alpha: 0.2) : Colors.white);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isUnread ? Colors.blue.shade300 : c.border.withValues(alpha: 0.5),
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
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                radius: 18,
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isUnread) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              "NEW",
                              style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                        Expanded(
                          child: Text(
                            notif.title,
                            style: TextStyle(
                              fontWeight: isUnread ? FontWeight.w900 : FontWeight.bold,
                              fontSize: 12,
                              color: isUnread ? (c.isDark ? Colors.white : Colors.blue.shade900) : null,
                            ),
                          ),
                        ),
                        if (notif.terminalName != null && notif.terminalName!.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: color.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.computer_rounded, size: 10, color: color),
                                const SizedBox(width: 3),
                                Text(
                                  notif.terminalName!,
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      notif.message,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
                        color: isUnread ? (c.isDark ? Colors.white70 : Colors.black87) : Colors.grey.shade700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.access_time_rounded, size: 11, color: isUnread ? Colors.blue.shade700 : Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          notif.formattedDateTime,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                            color: isUnread ? Colors.blue.shade800 : Colors.grey,
                          ),
                        ),
                      ],
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
}
