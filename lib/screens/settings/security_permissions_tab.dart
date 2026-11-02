import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/pharmacy_provider.dart';
import '../../services/app_notification_service.dart';
import '../../utils/theme_constants.dart';

class SecurityPermissionsTab extends StatefulWidget {
  final Function(PharmacyProvider) showPasswordDialog;

  const SecurityPermissionsTab({
    super.key,
    required this.showPasswordDialog,
  });

  @override
  State<SecurityPermissionsTab> createState() => _SecurityPermissionsTabState();
}

class _SecurityPermissionsTabState extends State<SecurityPermissionsTab> {
  Widget _buildSectionHeader(String title, String subtitle) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppStyles.h2Of(context)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: c.secondaryText, fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildSecurityToggle({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isDisabled = false,
  }) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDisabled ? Colors.grey.withValues(alpha: 0.1) : AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: isDisabled ? Colors.grey : AppColors.primary, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDisabled ? Colors.grey : c.primaryText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch(
            value: value,
            activeThumbColor: AppColors.primary,
            onChanged: isDisabled ? null : onChanged,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PharmacyProvider>(context);
    final hasPassword = provider.masterPassword.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Security & Access Control", "Android-style security locks for sensitive operations."),
        const SizedBox(height: 24),
        Container(
          width: 624,
          padding: const EdgeInsets.all(32),
          decoration: AppStyles.cardDecorationOf(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("MASTER SECURITY PIN", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.5)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(hasPassword ? Icons.lock_outline : Icons.lock_open_rounded, color: hasPassword ? AppColors.success : Colors.orange),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(hasPassword ? "Security PIN is Active" : "No PIN Set (System Unprotected)", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                          Text(hasPassword ? "Required for sensitive actions like deletions." : "Create a PIN to enable protection toggles below.", style: const TextStyle(color: Colors.blueGrey, fontSize: 12, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => widget.showPasswordDialog(provider),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hasPassword ? Colors.redAccent.withValues(alpha: 0.1) : AppColors.primary,
                        foregroundColor: hasPassword ? Colors.redAccent : Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(hasPassword ? "RESET PIN" : "CREATE PIN", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 48),
        _buildSectionHeader("Action Permissions", "Individual toggles for restricted features."),
        const SizedBox(height: 24),
        Container(
          width: 624,
          padding: const EdgeInsets.all(32),
          decoration: AppStyles.cardDecorationOf(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. INVOICE & DAILY LOCK SECURITY
              const Text("1. INVOICE & DAILY LOCK SECURITY", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.5)),
              const SizedBox(height: 24),
              _buildSecurityToggle(
                title: "Lock Previous Day Edits",
                subtitle: "Disables modifying, editing, or deleting any sale or purchase invoice dated prior to today without Master PIN.",
                icon: Icons.calendar_today_rounded,
                value: provider.securityToggles['lock_previous_day_edits'] ?? true,
                onChanged: (val) => provider.updateSecurityToggle('lock_previous_day_edits', val),
              ),
              _buildSecurityToggle(
                title: "Require PIN for Today's Edits",
                subtitle: "Forces Master PIN entry even when modifying invoices created on the current date.",
                icon: Icons.edit_calendar_rounded,
                value: provider.securityToggles['require_pin_edit_today_sales'] ?? false,
                onChanged: (val) => provider.updateSecurityToggle('require_pin_edit_today_sales', val),
                isDisabled: !hasPassword,
              ),
              _buildSecurityToggle(
                title: "Require PIN for Deleting Sales Bills",
                subtitle: "Prompts for Master PIN before a user can permanently delete or cancel a sales invoice.",
                icon: Icons.delete_sweep_rounded,
                value: provider.securityToggles['require_pin_delete_sales'] ?? false,
                onChanged: (val) => provider.updateSecurityToggle('require_pin_delete_sales', val),
                isDisabled: !hasPassword,
              ),
              _buildSecurityToggle(
                title: "Require PIN for Deleting Purchases",
                subtitle: "Restricts removing existing purchase invoices to prevent unauthorized stock reductions.",
                icon: Icons.shopping_cart_checkout_rounded,
                value: provider.securityToggles['require_pin_delete_purchases'] ?? false,
                onChanged: (val) => provider.updateSecurityToggle('require_pin_delete_purchases', val),
                isDisabled: !hasPassword,
              ),
              _buildSecurityToggle(
                title: "Require PIN for Discounts Above Threshold",
                subtitle: "Prompts for authorization if an employee attempts to give a discount higher than your set limit (e.g., > 10%).",
                icon: Icons.percent_rounded,
                value: provider.securityToggles['require_pin_discount_threshold'] ?? false,
                onChanged: (val) => provider.updateSecurityToggle('require_pin_discount_threshold', val),
                isDisabled: !hasPassword,
              ),

              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 32),

              // 2. INVENTORY & STOCK CONTROLS
              const Text("2. INVENTORY & STOCK CONTROLS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.5)),
              const SizedBox(height: 24),
              _buildSecurityToggle(
                title: "Require PIN for Stock Adjustments",
                subtitle: "Locks manual stock quantity additions or subtractions in the Stock Adjustment module.",
                icon: Icons.settings_suggest_rounded,
                value: provider.securityToggles['require_pin_stock_adjustments'] ?? false,
                onChanged: (val) => provider.updateSecurityToggle('require_pin_stock_adjustments', val),
                isDisabled: !hasPassword,
              ),
              _buildSecurityToggle(
                title: "Require PIN for Adding New Agent (Stock Check)",
                subtitle: "Prompts for admin PIN before adding an extra verification agent in the Stock Checking window.",
                icon: Icons.person_add_alt_1_rounded,
                value: provider.securityToggles['require_pin_add_agent_stock_check'] ?? true,
                onChanged: (val) => provider.updateSecurityToggle('require_pin_add_agent_stock_check', val),
                isDisabled: !hasPassword,
              ),
              _buildSecurityToggle(
                title: "Require PIN for Admin Stock Adjustment",
                subtitle: "Locks the consolidated 'Adjustment (Admin)' view in Stock Checking behind a PIN.",
                icon: Icons.admin_panel_settings_rounded,
                value: provider.securityToggles['require_pin_admin_stock_adjustment'] ?? true,
                onChanged: (val) => provider.updateSecurityToggle('require_pin_admin_stock_adjustment', val),
                isDisabled: !hasPassword,
              ),
              _buildSecurityToggle(
                title: "Require PIN for Writing Off Damaged/Expired Stock",
                subtitle: "Prevents unauthorized removal of inventory logged under damage or expiry write-offs.",
                icon: Icons.broken_image_rounded,
                value: provider.securityToggles['require_pin_write_off'] ?? false,
                onChanged: (val) => provider.updateSecurityToggle('require_pin_write_off', val),
                isDisabled: !hasPassword,
              ),
              _buildSecurityToggle(
                title: "Require PIN for Merging Duplicate Products",
                subtitle: "Protects against accidental or unauthorized consolidation of product masters and batch histories.",
                icon: Icons.call_merge_rounded,
                value: provider.securityToggles['require_pin_merge_products'] ?? false,
                onChanged: (val) => provider.updateSecurityToggle('require_pin_merge_products', val),
                isDisabled: !hasPassword,
              ),
              _buildSecurityToggle(
                title: "Require PIN for Changing Medicine Selling Rates / MRP",
                subtitle: "Restricts staff from manually overriding selling prices or MRP during sales entry or in product master.",
                icon: Icons.currency_exchange_rounded,
                value: provider.securityToggles['require_pin_change_rates'] ?? false,
                onChanged: (val) => provider.updateSecurityToggle('require_pin_change_rates', val),
                isDisabled: !hasPassword,
              ),

              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 32),

              // 3. MASTER DATA & REPORTS SECURITY
              const Text("3. MASTER DATA & REPORTS SECURITY", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.5)),
              const SizedBox(height: 24),
              _buildSecurityToggle(
                title: "Require PIN for Editing Customer / Supplier Master",
                subtitle: "Prompts for PIN before altering supplier bank details, customer credit balances, or contact info.",
                icon: Icons.assignment_ind_rounded,
                value: provider.securityToggles['require_pin_edit_master'] ?? false,
                onChanged: (val) => provider.updateSecurityToggle('require_pin_edit_master', val),
                isDisabled: !hasPassword,
              ),
              _buildSecurityToggle(
                title: "Lock Financial & Tax Reports",
                subtitle: "Restricts access to GSTR-1, GSTR-3B, Profit & Loss, and Margin reports behind the Master PIN.",
                icon: Icons.bar_chart_rounded,
                value: provider.securityToggles['require_pin_financial_reports'] ?? false,
                onChanged: (val) => provider.updateSecurityToggle('require_pin_financial_reports', val),
                isDisabled: !hasPassword,
              ),
              _buildSecurityToggle(
                title: "Require PIN for Database Reset or Bulk CSV Imports",
                subtitle: "Adds a high-security lock before performing database wipes, inventory resets, or bulk updates.",
                icon: Icons.upload_file_rounded,
                value: provider.securityToggles['require_pin_db_reset_imports'] ?? false,
                onChanged: (val) => provider.updateSecurityToggle('require_pin_db_reset_imports', val),
                isDisabled: !hasPassword,
              ),
              ListenableBuilder(
                listenable: AppNotificationService.instance,
                builder: (context, _) {
                  return _buildSecurityToggle(
                    title: "Lock Notification Center with Master PIN",
                    subtitle: "Requires Master PIN before opening or clearing notifications in the Notification Center.",
                    icon: Icons.notifications_active_rounded,
                    value: AppNotificationService.instance.isNotificationLockEnabled,
                    onChanged: (val) => AppNotificationService.instance.setNotificationLockEnabled(val),
                    isDisabled: !hasPassword,
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
